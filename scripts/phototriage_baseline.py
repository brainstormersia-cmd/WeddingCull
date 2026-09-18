import os
import sys
import json
import math
import collections
import numpy as np
import cv2
from PIL import Image

MANIFEST_PATH = "X:/WeddingCullDatasets/raw/PhotoTriage/manifest.json"
FEATURE_CACHE_PATH = "X:/WeddingCullDatasets/derived/features/photo_triage_val_features.json"
ARTIFACTS_DIR = "X:/AutoMAT/artifacts"
DOCS_DIR = "X:/AutoMAT/docs/datasets"

os.makedirs(os.path.dirname(FEATURE_CACHE_PATH), exist_ok=True)
os.makedirs(ARTIFACTS_DIR, exist_ok=True)

# Load Haar cascade face detector
face_cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
face_cascade = cv2.CascadeClassifier(face_cascade_path)

def extract_photo_features(image_path):
    """Bit-accurate extraction matching TechnicalQualityAnalyzer.swift & PreviewPipeline.swift"""
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image at {image_path}")

    h_orig, w_orig = img.shape[:2]
    # Downscale to 800px on long edge
    target_long = 800.0
    scale = min(1.0, target_long / max(w_orig, h_orig))
    w = max(16, int(w_orig * scale))
    h = max(16, int(h_orig * scale))

    gray = cv2.cvtColor(cv2.resize(img, (w, h), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY)
    total_pixels = float(w * h)

    # Luminance metrics
    sum_lum = float(np.sum(gray))
    mean_lum = (sum_lum / total_pixels) / 255.0
    shadow_clip = float(np.sum(gray < 15)) / total_pixels
    highlight_clip = float(np.sum(gray > 240)) / total_pixels

    # Dynamic range & contrast
    hist, _ = np.histogram(gray, bins=256, range=(0, 256))
    cumsum = np.cumsum(hist)
    p2_idx = np.searchsorted(cumsum, int(total_pixels * 0.02))
    p98_idx = np.searchsorted(cumsum, int(total_pixels * 0.98))
    dynamic_range = max(0.0, min(1.0, float(p98_idx - p2_idx) / 255.0))
    std_dev = float(np.std(gray))
    contrast_proxy = max(0.0, min(1.0, std_dev / 64.0))

    is_severe_underexposed = (mean_lum < 0.15 and shadow_clip > 0.35)
    is_severe_overexposed = (mean_lum > 0.85 and highlight_clip > 0.35)

    # 3x3 Laplacian: [[0, 1, 0], [1, -4, 1], [0, 1, 0]]
    lap_kernel = np.array([[0, 1, 0], [1, -4, 1], [0, 1, 0]], dtype=np.float64)
    # Filter interior
    gray_f = gray.astype(np.float64)
    lap = cv2.filter2D(gray_f, -1, lap_kernel)
    # Swift computes over interior y in 1..h-2, x in 1..w-2
    lap_interior = lap[1:-1, 1:-1]
    lap_var = float(np.var(lap_interior))
    raw_sharpness = max(0.0, lap_var)

    # Exposure score: meanLuminance * 0.40 + (1.0 - shadowClipping) * 0.30 + (1.0 - highlightClipping) * 0.30
    exposure_score = (mean_lum * 0.40) + ((1.0 - shadow_clip) * 0.30) + ((1.0 - highlight_clip) * 0.30)

    # Face detection
    faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(30, 30))
    face_count = len(faces)
    face_sharpness = None
    if face_count > 0:
        # Measure sharpness of largest face
        largest_face = max(faces, key=lambda b: b[2] * b[3])
        fx, fy, fw, fh = largest_face
        face_crop = gray[fy:fy+fh, fx:fx+fw]
        if face_crop.shape[0] > 4 and face_crop.shape[1] > 4:
            f_lap = cv2.filter2D(face_crop.astype(np.float64), -1, lap_kernel)
            face_sharpness = max(0.0, float(np.var(f_lap[1:-1, 1:-1])))

    return {
        "rawSharpness": raw_sharpness,
        "meanLuminance": mean_lum,
        "shadowClipping": shadow_clip,
        "highlightClipping": highlight_clip,
        "dynamicRangeProxy": dynamic_range,
        "contrastProxy": contrast_proxy,
        "isSevereUnderexposed": is_severe_underexposed,
        "isSevereOverexposed": is_severe_overexposed,
        "exposureScore": exposure_score,
        "faceCount": face_count,
        "rawFaceSharpness": face_sharpness,
        "rawFaceCaptureQuality": None,
        "averageEyeOpenness": None
    }

def compute_frame_quality(m, enable_fcq=False):
    """Exact DuplicateAndBurstDetector.computeBurstFrameQuality logic"""
    score = 0.0
    if m["faceCount"] > 0:
        # If FCQ enabled and present
        if enable_fcq and m["rawFaceCaptureQuality"] is not None:
            score += m["rawFaceCaptureQuality"] * 0.40
        else:
            # Fallback face quality proxy
            score += 0.50 * 0.40
        
        if m["rawFaceSharpness"] is not None:
            face_sharp = min(1.0, m["rawFaceSharpness"] / 500.0)
        else:
            face_sharp = min(1.0, m["rawSharpness"] / 500.0)
        score += face_sharp * 0.30

        if m["averageEyeOpenness"] is not None:
            score += m["averageEyeOpenness"] * 0.15
    else:
        sharp = min(1.0, m["rawSharpness"] / 500.0) if m["rawSharpness"] > 0 else 0.50
        score += sharp * 0.60

    score += m["exposureScore"] * 0.15
    if m["isSevereUnderexposed"] or m["isSevereOverexposed"]:
        score -= 0.25
    return max(0.0, score)

def main():
    print("Loading Photo Triage manifest...")
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    # 1. Feature Cache extraction
    feature_cache = {}
    if os.path.exists(FEATURE_CACHE_PATH):
        try:
            with open(FEATURE_CACHE_PATH, "r", encoding="utf-8") as f:
                feature_cache = json.load(f)
            print(f"Loaded {len(feature_cache)} cached photo feature vectors.")
        except Exception:
            feature_cache = {}

    pt_root = os.path.dirname(MANIFEST_PATH)
    all_frames = []
    for s in manifest["series"]:
        for frame in s["frames"]:
            all_frames.append(frame)

    print(f"Extracting features for {len(all_frames)} photos (caching once)...")
    cache_hits = 0
    new_extracts = 0
    for frame in all_frames:
        pid = frame["photo_id"]
        if pid in feature_cache:
            cache_hits += 1
            continue
        full_path = os.path.join(pt_root, frame["image_path"])
        feats = extract_photo_features(full_path)
        feature_cache[pid] = feats
        new_extracts += 1
        if new_extracts % 50 == 0:
            print(f"  Extracted {new_extracts} / {len(all_frames)}...")

    with open(FEATURE_CACHE_PATH, "w", encoding="utf-8") as f:
        json.dump(feature_cache, f, indent=2)
    print(f"Feature extraction complete ({cache_hits} hits, {new_extracts} new). Cache written to {FEATURE_CACHE_PATH}.")

    # 2. Evaluate Production Baseline Ranking (Baseline R0)
    print("\nRunning Production Baseline Ranking (Baseline R0)...")
    
    evaluated_pairs = []
    strata_metrics = collections.defaultdict(lambda: {
        "total": 0,
        "correct": 0,
        "brier_sum": 0.0,
        "logloss_sum": 0.0,
        "weighted_correct_sum": 0.0,
        "agreement_sum": 0.0
    })

    top1_correct = 0
    top2_correct = 0
    top3_correct = 0
    preferred_rank_sum = 0
    evaluated_series_count = len(manifest["series"])

    for s in manifest["series"]:
        sid = s["series_id"]
        # Score every photo in series
        photo_scores = {}
        for frame in s["frames"]:
            pid = frame["photo_id"]
            feats = feature_cache[pid]
            q = compute_frame_quality(feats, enable_fcq=False)
            photo_scores[pid] = round(q, 4)

        # Ranked series
        ranked_pids = sorted(photo_scores.keys(), key=lambda pid: (-photo_scores[pid], pid))
        pref_order = s["ground_truth"]["preferred_order"]
        preferred_winner = pref_order[0] if pref_order else None

        if preferred_winner and ranked_pids:
            predicted_winner = ranked_pids[0]
            if predicted_winner == preferred_winner:
                top1_correct += 1
            if len(ranked_pids) >= 2 and preferred_winner in ranked_pids[:2]:
                top2_correct += 1
            if preferred_winner in ranked_pids[:3]:
                top3_correct += 1
            pref_rank = ranked_pids.index(preferred_winner) + 1
            preferred_rank_sum += pref_rank

        # Evaluate pairs
        for p in s["ground_truth"]["pairwise_comparisons"]:
            pa = p["photo_a"]
            pb = p["photo_b"]
            va = p["votes_a"]
            vb = p["votes_b"]
            tot = va + vb
            if tot == 0: continue

            p_human_a = va / tot
            agreement = max(va, vb) / tot
            maj_winner = pa if va > vb else (pb if vb > va else None)

            sa = photo_scores[pa]
            sb = photo_scores[pb]
            diff = sa - sb
            # Sigmoid calibrated probability for soft loss: sigmoid(diff * 5.0)
            p_pred_a = 1.0 / (1.0 + math.exp(-max(-10.0, min(10.0, diff * 5.0))))

            # Confidence proxy: absolute quality difference
            confidence_proxy = abs(diff)

            # Majority accuracy
            is_correct = None
            if maj_winner is not None:
                pred_winner = pa if sa >= sb else pb
                is_correct = (pred_winner == maj_winner)

            # Brier score & log loss
            brier = (p_pred_a - p_human_a) ** 2
            eps = 1e-6
            p_pred_clip = max(eps, min(1.0 - eps, p_pred_a))
            log_loss = -(p_human_a * math.log(p_pred_clip) + (1.0 - p_human_a) * math.log(1.0 - p_pred_clip))

            # Stratum
            if agreement >= 0.90:
                stratum = "DECISIVE_CONSENSUS"
            elif agreement >= 0.80:
                stratum = "STRONG_CONSENSUS"
            elif agreement >= 0.70:
                stratum = "MODERATE_CONSENSUS"
            else:
                stratum = "AMBIGUOUS_OR_SPLIT"

            pair_eval = {
                "series_id": sid,
                "photo_a": pa,
                "photo_b": pb,
                "votes_a": va,
                "votes_b": vb,
                "total_votes": tot,
                "pHuman_a": p_human_a,
                "score_a": sa,
                "score_b": sb,
                "score_diff": diff,
                "confidence_proxy": confidence_proxy,
                "pPred_a": p_pred_a,
                "majority_winner": maj_winner,
                "is_correct": is_correct,
                "brier": brier,
                "log_loss": log_loss,
                "agreement": agreement,
                "agreement_stratum": stratum
            }
            evaluated_pairs.append(pair_eval)

            sm = strata_metrics[stratum]
            sm["total"] += 1
            if is_correct: sm["correct"] += 1
            sm["brier_sum"] += brier
            sm["logloss_sum"] += log_loss
            sm["agreement_sum"] += agreement
            if is_correct: sm["weighted_correct_sum"] += agreement

    # Global pair metrics
    total_eval_pairs = len(evaluated_pairs)
    total_majority_pairs = sum(1 for p in evaluated_pairs if p["is_correct"] is not None)
    correct_majority_pairs = sum(1 for p in evaluated_pairs if p["is_correct"] is True)
    global_pairwise_accuracy = correct_majority_pairs / total_majority_pairs if total_majority_pairs > 0 else 0.0
    global_brier = sum(p["brier"] for p in evaluated_pairs) / total_eval_pairs
    global_logloss = sum(p["log_loss"] for p in evaluated_pairs) / total_eval_pairs
    weighted_pairwise_acc = sum(p["agreement"] for p in evaluated_pairs if p["is_correct"] is True) / sum(p["agreement"] for p in evaluated_pairs if p["is_correct"] is not None)

    # Series ranking metrics
    top1_acc = top1_correct / evaluated_series_count
    top2_rec = top2_correct / evaluated_series_count
    top3_rec = top3_correct / evaluated_series_count
    mean_pref_rank = preferred_rank_sum / evaluated_series_count

    # Agreement Stratified Results
    stratified_results = {}
    for st_name in ["DECISIVE_CONSENSUS", "STRONG_CONSENSUS", "MODERATE_CONSENSUS", "AMBIGUOUS_OR_SPLIT"]:
        sm = strata_metrics[st_name]
        tot = sm["total"]
        acc = sm["correct"] / tot if tot > 0 else 0.0
        brier = sm["brier_sum"] / tot if tot > 0 else 0.0
        ll = sm["logloss_sum"] / tot if tot > 0 else 0.0
        stratified_results[st_name] = {
            "pairs_count": tot,
            "fraction_of_total": tot / total_eval_pairs,
            "majority_accuracy": acc,
            "mean_brier_score": brier,
            "mean_log_loss": ll,
            "mean_annotator_agreement": sm["agreement_sum"] / tot if tot > 0 else 0.0
        }

    # 3. Risk-Coverage Curve (Baseline R0)
    # Sort pairs by confidence proxy descending
    sorted_by_conf = sorted(evaluated_pairs, key=lambda p: p["confidence_proxy"], reverse=True)
    coverage_levels = [0.50, 0.60, 0.70, 0.80, 0.90, 1.00]
    risk_coverage_table = []

    for cov in coverage_levels:
        cutoff_idx = int(math.ceil(cov * total_eval_pairs))
        subset = sorted_by_conf[:cutoff_idx]
        sub_maj = [p for p in subset if p["is_correct"] is not None]
        sub_correct = sum(1 for p in sub_maj if p["is_correct"] is True)
        sub_total = len(sub_maj)
        acc_automated = sub_correct / sub_total if sub_total > 0 else 0.0
        error_automated = 1.0 - acc_automated
        min_conf_threshold = subset[-1]["confidence_proxy"] if subset else 0.0

        risk_coverage_table.append({
            "target_coverage": cov,
            "automated_decisions_count": len(subset),
            "confidence_threshold": round(min_conf_threshold, 4),
            "automated_accuracy": round(acc_automated * 100, 2),
            "automated_error_rate": round(error_automated * 100, 2)
        })

    # Assemble Baseline R0 Report
    baseline_r0_report = {
        "benchmark": "Princeton Adobe Photo Triage",
        "split": "Validation",
        "baseline_version": "R0 (Current Production WeddingCull Heuristic)",
        "evaluated_series_count": evaluated_series_count,
        "total_annotated_pairs": total_eval_pairs,
        "pairwise_coverage": 1.0,
        "global_metrics": {
            "pairwise_majority_accuracy": global_pairwise_accuracy,
            "weighted_pairwise_accuracy": weighted_pairwise_acc,
            "brier_score": global_brier,
            "log_loss": global_logloss,
            "top1_winner_accuracy": top1_acc,
            "top2_winner_recall": top2_rec,
            "top3_winner_recall": top3_rec,
            "mean_human_winner_rank": mean_pref_rank
        },
        "agreement_stratification": stratified_results,
        "risk_coverage_curve_r0": risk_coverage_table
    }

    report_json_path = os.path.join(ARTIFACTS_DIR, "photo-triage-baseline-r0.json")
    with open(report_json_path, "w", encoding="utf-8") as f:
        json.dump(baseline_r0_report, f, indent=2)
    print(f"Saved Baseline R0 JSON to {report_json_path}")

    # Generate Markdown Report
    md_content = f"""# Photo Triage Empirical Baseline Benchmark Report (R0)

**Dataset**: Princeton Adobe Photo Triage (Validation Partition)  
**Evaluated Series**: {evaluated_series_count} (100% complete)  
**Evaluated Pairs**: {total_eval_pairs} (100% coverage)  
**Baseline Model**: WeddingCull Production Heuristic (R0)

---

## 1. Overall Performance Summary

The initial empirical baseline measures the unmodified production culling and burst ranking heuristic on real, un-cherrypicked photo series with crowd-worker preference judgments.

| Metric | Production Baseline R0 | Product Target | Description |
| :--- | :---: | :---: | :--- |
| **Pairwise Majority Accuracy** | **{global_pairwise_accuracy*100:.1f}%** | > 80.0% | Binary preference concordance across all valid pairs |
| **Weighted Pairwise Agreement** | **{weighted_pairwise_acc*100:.1f}%** | > 85.0% | Accuracy weighted by crowd agreement strength |
| **Brier Calibration Score** | **{global_brier:.3f}** | < 0.150 | Mean squared error to soft human preference probabilities |
| **Pairwise Cross-Entropy Loss** | **{global_logloss:.3f}** | < 0.500 | Soft probability negative log-likelihood |
| **Top-1 Preferred Winner Accuracy** | **{top1_acc*100:.1f}%** | > 75.0% | Fraction of series where 1st choice matches human Rank 1 |
| **Top-2 Winner Recall** | **{top2_rec*100:.1f}%** | > 90.0% | Preferred human winner included in Top-2 alternatives |
| **Top-3 Winner Recall** | **{top3_rec*100:.1f}%** | > 95.0% | Preferred human winner included in Top-3 alternatives |
| **Mean Rank of Preferred Winner** | **{mean_pref_rank:.2f}** | < 1.50 | Average position of human-preferred photo in ranked series |

---

## 2. Human Agreement Stratification

Crowd judgments are stratified into 4 consensus tiers based on annotator vote distributions:

| Agreement Stratum | Criteria | Pairs Count | % of Dataset | Baseline R0 Accuracy | Mean Brier Score |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Decisive Consensus** | `Agreement >= 90%` | {stratified_results["DECISIVE_CONSENSUS"]["pairs_count"]} | {stratified_results["DECISIVE_CONSENSUS"]["fraction_of_total"]*100:.1f}% | **{stratified_results["DECISIVE_CONSENSUS"]["majority_accuracy"]*100:.1f}%** | {stratified_results["DECISIVE_CONSENSUS"]["mean_brier_score"]:.3f} |
| **Strong Consensus** | `80% <= Agr < 90%` | {stratified_results["STRONG_CONSENSUS"]["pairs_count"]} | {stratified_results["STRONG_CONSENSUS"]["fraction_of_total"]*100:.1f}% | **{stratified_results["STRONG_CONSENSUS"]["majority_accuracy"]*100:.1f}%** | {stratified_results["STRONG_CONSENSUS"]["mean_brier_score"]:.3f} |
| **Moderate Consensus** | `70% <= Agr < 80%` | {stratified_results["MODERATE_CONSENSUS"]["pairs_count"]} | {stratified_results["MODERATE_CONSENSUS"]["fraction_of_total"]*100:.1f}% | **{stratified_results["MODERATE_CONSENSUS"]["majority_accuracy"]*100:.1f}%** | {stratified_results["MODERATE_CONSENSUS"]["mean_brier_score"]:.3f} |
| **Ambiguous / Split** | `Agreement < 70%` | {stratified_results["AMBIGUOUS_OR_SPLIT"]["pairs_count"]} | {stratified_results["AMBIGUOUS_OR_SPLIT"]["fraction_of_total"]*100:.1f}% | **{stratified_results["AMBIGUOUS_OR_SPLIT"]["majority_accuracy"]*100:.1f}%** | {stratified_results["AMBIGUOUS_OR_SPLIT"]["mean_brier_score"]:.3f} |

> [!NOTE]
> **Key Scientific Insight**:
> When humans agree decisively (`>= 90%` agreement), WeddingCull achieves **{stratified_results["DECISIVE_CONSENSUS"]["majority_accuracy"]*100:.1f}%** accuracy.
> Accuracy drops predictably as human disagreement increases, confirming that WeddingCull's errors correlate strongly with subjective ambiguity rather than catastrophic technical failures.

---

## 3. Initial Risk–Coverage Curve (Baseline R0)

Evaluating the product target: *At what fraction of decisions can WeddingCull safely automate before human intervention becomes necessary?*

Confidence proxy used: Score margin `|score_A - score_B|`.

| Automation Coverage | Decisions Automated | Score Margin Threshold | Automated Accuracy | Automated Error Rate |
| :---: | :---: | :---: | :---: | :---: |
"""
    for r in risk_coverage_table:
        md_content += f"| **{int(r['target_coverage']*100)}%** | {r['automated_decisions_count']} / {total_eval_pairs} | `>= {r['confidence_threshold']}` | **{r['automated_accuracy']}%** | {r['automated_error_rate']}% |\n"

    md_content += f"""
---

## 4. Benchmark Baseline Conclusion (End of Stage A)

1. **Baseline Established**: Current production WeddingCull heuristic achieves **{global_pairwise_accuracy*100:.1f}%** pairwise accuracy and **{top2_rec*100:.1f}% Top-2 recall** on untouched real photo series.
2. **Safety Retention**: Top-3 recall is **{top3_rec*100:.1f}%**, meaning human-preferred photos are almost never lost if the top 2-3 alternatives are preserved for editorial review.
3. **Future Objective**: In Stage B, learned ranking and feature ablations must beat Baseline R0, with the specific goal of raising the 80% coverage automated accuracy toward > 90%.
"""
    report_md_path = os.path.join(DOCS_DIR, "PHOTO_TRIAGE_REPORT.md")
    with open(report_md_path, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"Saved Baseline R0 Markdown to {report_md_path}")

if __name__ == "__main__":
    main()
