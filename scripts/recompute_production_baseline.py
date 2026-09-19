import os
import sys
import json
import math
import collections
import numpy as np
from ranking_evaluator import load_feature_cache

VAL_MANIFEST = "X:/WeddingCullDatasets/derived/manifests/photo_triage_val.json"
VAL_FEATURES = "X:/WeddingCullDatasets/derived/features/photo_triage_val_features_authentic.jsonl"
OUTPUT_BASELINE = "artifacts/phototriage_val_production_candidate_d_baseline.json"

def score_candidate_d_series(series_photos, features):
    """
    Exact Candidate D production implementation from DuplicateAndBurstDetector.swift (af71a89).
    """
    # 1. Compute burstContext strictly on non-face members
    non_face_sharps = []
    for pid in series_photos:
        f = features.get(pid, {})
        if f.get("face_count", 0) == 0:
            raw_s = f.get("rawSharpness", 0.0)
            non_face_sharps.append(math.log1p(max(0.0, raw_s)))

    if non_face_sharps:
        min_log_sharp = min(non_face_sharps)
        max_log_sharp = max(non_face_sharps)
        burst_ctx = (min_log_sharp, max_log_sharp)
    else:
        burst_ctx = None

    scores = {}
    for pid in series_photos:
        f = features.get(pid, {})
        score = 0.0
        face_count = f.get("face_count", 0)

        # Exposure score
        mean_lum = f.get("meanLuminance", 0.5)
        shadow_clip = f.get("shadowClipping", 0.0)
        highlight_clip = f.get("highlightClipping", 0.0)
        dev = abs(mean_lum - 0.5) * 2.0
        clip = (shadow_clip + highlight_clip) * 1.5
        exp_score = max(0.05, 1.0 - (dev * 0.4 + clip * 0.6))

        if face_count > 0:
            # Face branch: enableFaceCaptureQuality = true
            fcq = f.get("faceCaptureQuality")
            if fcq is not None:
                score += fcq * 0.40
            else:
                score += f.get("detectionConfidence", 0.8) * 0.40

            raw_fs = f.get("rawFaceSharpness")
            if raw_fs is not None:
                face_sharp = min(1.0, raw_fs / 500.0)
            else:
                raw_s = f.get("rawSharpness", 0.0)
                face_sharp = min(1.0, raw_s / 500.0)
            score += face_sharp * 0.30

            eye = f.get("averageEyeOpenness")
            if eye is not None:
                score += eye * 0.15

            score += exp_score * 0.15
        else:
            # Non-face branch
            raw_s = f.get("rawSharpness", 0.0)
            cur_log = math.log1p(max(0.0, raw_s))
            if burst_ctx is not None and burst_ctx[1] > 0.0:
                spread = burst_ctx[1] - burst_ctx[0]
                if spread > 0.18:
                    sharp = min(1.0, max(0.0, (cur_log - burst_ctx[0]) / spread))
                else:
                    sharp = 0.50
            elif raw_s > 0.0:
                sharp = min(1.0, cur_log / math.log1p(2500.0))
            else:
                sharp = 0.0

            score += sharp * 0.50
            score += exp_score * 0.50

        # Severe penalty
        is_severe_underexp = (mean_lum < 0.05 and shadow_clip > 0.70) or f.get("severeUnderexposure", False)
        is_severe_overexp = (mean_lum > 0.95 and highlight_clip > 0.70) or f.get("severeOverexposure", False)
        if is_severe_underexp or is_severe_overexp:
            score -= 0.25

        scores[pid] = max(0.0, score)

    return scores

def evaluate_baseline(manifest_path, features_path, num_bootstrap=2000, seed=42):
    features, provenance, is_authentic = load_feature_cache(features_path)
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    series_dict = manifest["series"]
    series_list = list(series_dict.values())
    print(f"Evaluating {len(series_list)} series. Authentic features: {is_authentic}")

    series_evals = []
    all_pairs_eval = []

    for s in series_list:
        sid = s["series_id"]
        photos = s.get("photos", [])
        pids = [p["filename"] if isinstance(p, dict) else p for p in photos]

        # Candidate D series scoring
        scores = score_candidate_d_series(pids, features)

        # Ranked descending by score (rounded to 4 decimals), tie-breaker pid ascending
        ranked_pids = sorted(pids, key=lambda pid: (-round(scores[pid], 4), pid))

        # Ground truth winner
        pref_order = s.get("ranked_photos_preferred_order") or []
        pref_winner = s.get("preferred_winner_photo") or (pref_order[0] if pref_order else None)

        winner_rank = None
        if pref_winner and pref_winner in ranked_pids:
            winner_rank = ranked_pids.index(pref_winner) + 1

        top1_correct = 1.0 if (pref_winner and ranked_pids[0] == pref_winner) else 0.0
        top2_correct = 1.0 if (pref_winner and winner_rank is not None and winner_rank <= 2) else 0.0
        top3_correct = 1.0 if (pref_winner and winner_rank is not None and winner_rank <= 3) else 0.0

        # Stratum metadata
        has_face = any(features.get(pid, {}).get("face_count", 0) > 0 for pid in pids)
        size_category = "size_2" if len(pids) == 2 else ("size_3" if len(pids) == 3 else ("size_4_5" if len(pids) <= 5 else "size_6_plus"))

        # Evaluate pairs
        pairs = s.get("pairs", [])
        pair_correct_count = 0
        pair_total_count = 0
        for p in pairs:
            pa = p["photo_a"]
            pb = p["photo_b"]
            pref = p.get("majority_winner") or p.get("preferred_photo")
            sa = scores.get(pa, 0.0)
            sb = scores.get(pb, 0.0)

            # Strict total order prediction
            qa = round(sa, 4)
            qb = round(sb, 4)
            if qa != qb:
                pred = pa if qa > qb else pb
            else:
                pred = pa if pa < pb else pb

            is_correct = 1.0 if pred == pref else 0.0
            pair_correct_count += is_correct
            pair_total_count += 1
            all_pairs_eval.append({
                "series_id": sid,
                "is_correct": is_correct,
                "score_diff": abs(sa - sb),
                "has_face": has_face
            })

        series_pair_acc = (pair_correct_count / pair_total_count) if pair_total_count > 0 else None

        series_evals.append({
            "series_id": sid,
            "photo_count": len(pids),
            "size_category": size_category,
            "has_face": has_face,
            "top1_correct": top1_correct,
            "top2_correct": top2_correct,
            "top3_correct": top3_correct,
            "winner_rank": winner_rank,
            "pair_acc": series_pair_acc,
            "pair_count": pair_total_count
        })

    # Point metrics
    total_series = len(series_evals)
    top1_acc = np.mean([x["top1_correct"] for x in series_evals])
    top2_rec = np.mean([x["top2_correct"] for x in series_evals])
    top3_rec = np.mean([x["top3_correct"] for x in series_evals])
    mean_rank = np.mean([x["winner_rank"] for x in series_evals if x["winner_rank"] is not None])
    total_pair_correct = sum(p["is_correct"] for p in all_pairs_eval)
    pairwise_acc = total_pair_correct / len(all_pairs_eval)

    # Size-stratified point metrics
    size_metrics = {}
    for cat in ["size_2", "size_3", "size_4_5", "size_6_plus"]:
        items = [x for x in series_evals if x["size_category"] == cat]
        if items:
            size_metrics[cat] = {
                "count": len(items),
                "top1_accuracy": float(np.mean([x["top1_correct"] for x in items])),
                "top2_recall": float(np.mean([x["top2_correct"] for x in items])),
                "top3_recall": float(np.mean([x["top3_correct"] for x in items]))
            }

    # Face-stratified point metrics
    face_items = [x for x in series_evals if x["has_face"]]
    noface_items = [x for x in series_evals if not x["has_face"]]
    face_metrics = {
        "face_series_count": len(face_items),
        "face_top1": float(np.mean([x["top1_correct"] for x in face_items])),
        "face_top3": float(np.mean([x["top3_correct"] for x in face_items])),
        "noface_series_count": len(noface_items),
        "noface_top1": float(np.mean([x["top1_correct"] for x in noface_items])),
        "noface_top3": float(np.mean([x["top3_correct"] for x in noface_items]))
    }

    # Series-level Bootstrap (2,000 resamples)
    rng = np.random.RandomState(seed)
    boot_top1 = []
    boot_top2 = []
    boot_top3 = []
    boot_pair = []
    boot_face_top1 = []
    boot_noface_top1 = []

    n = len(series_evals)
    for _ in range(num_bootstrap):
        idx = rng.randint(0, n, size=n)
        sample = [series_evals[i] for i in idx]

        boot_top1.append(np.mean([x["top1_correct"] for x in sample]))
        boot_top2.append(np.mean([x["top2_correct"] for x in sample]))
        boot_top3.append(np.mean([x["top3_correct"] for x in sample]))

        tot_p_corr = sum(x["pair_acc"] * x["pair_count"] for x in sample if x["pair_acc"] is not None)
        tot_p = sum(x["pair_count"] for x in sample)
        boot_pair.append(tot_p_corr / max(1, tot_p))

        f_sample = [x for x in sample if x["has_face"]]
        nf_sample = [x for x in sample if not x["has_face"]]
        if f_sample: boot_face_top1.append(np.mean([x["top1_correct"] for x in f_sample]))
        if nf_sample: boot_noface_top1.append(np.mean([x["top1_correct"] for x in nf_sample]))

    ci_95 = {
        "top1_accuracy": {
            "point_estimate": float(top1_acc),
            "ci_95_low": float(np.percentile(boot_top1, 2.5)),
            "ci_95_high": float(np.percentile(boot_top1, 97.5))
        },
        "top2_recall": {
            "point_estimate": float(top2_rec),
            "ci_95_low": float(np.percentile(boot_top2, 2.5)),
            "ci_95_high": float(np.percentile(boot_top2, 97.5))
        },
        "top3_recall": {
            "point_estimate": float(top3_rec),
            "ci_95_low": float(np.percentile(boot_top3, 2.5)),
            "ci_95_high": float(np.percentile(boot_top3, 97.5))
        },
        "pairwise_accuracy": {
            "point_estimate": float(pairwise_acc),
            "ci_95_low": float(np.percentile(boot_pair, 2.5)),
            "ci_95_high": float(np.percentile(boot_pair, 97.5))
        },
        "face_top1": {
            "point_estimate": face_metrics["face_top1"],
            "ci_95_low": float(np.percentile(boot_face_top1, 2.5)),
            "ci_95_high": float(np.percentile(boot_face_top1, 97.5))
        },
        "noface_top1": {
            "point_estimate": face_metrics["noface_top1"],
            "ci_95_low": float(np.percentile(boot_noface_top1, 2.5)),
            "ci_95_high": float(np.percentile(boot_noface_top1, 97.5))
        }
    }

    baseline_report = {
        "model_id": "PRODUCTION_CANDIDATE_D_AF71A89",
        "commit_sha": "af71a89a7c41056a703f8d411377dd5e86c3e7ab",
        "status": "FROZEN_PRODUCTION_BASELINE",
        "split": "VAL (Holdout)",
        "total_series": total_series,
        "total_pairs": len(all_pairs_eval),
        "point_metrics": {
            "top1_accuracy": float(top1_acc),
            "top2_recall": float(top2_rec),
            "top3_recall": float(top3_rec),
            "mean_winner_rank": float(mean_rank),
            "pairwise_accuracy": float(pairwise_acc)
        },
        "confidence_intervals_95_series_level": ci_95,
        "size_stratified": size_metrics,
        "face_stratified": face_metrics,
        "provenance": provenance
    }

    os.makedirs(os.path.dirname(OUTPUT_BASELINE), exist_ok=True)
    with open(OUTPUT_BASELINE, "w", encoding="utf-8") as f:
        json.dump(baseline_report, f, indent=2)

    print("\n=======================================================")
    print("FROZEN PRODUCTION BASELINE REPORT (commit af71a89)")
    print("=======================================================")
    print(f"Top-1 Accuracy:    {top1_acc*100:.2f}% [95% CI: {ci_95['top1_accuracy']['ci_95_low']*100:.1f}% - {ci_95['top1_accuracy']['ci_95_high']*100:.1f}%]")
    print(f"Top-2 Recall:      {top2_rec*100:.2f}% [95% CI: {ci_95['top2_recall']['ci_95_low']*100:.1f}% - {ci_95['top2_recall']['ci_95_high']*100:.1f}%]")
    print(f"Top-3 Recall:      {top3_rec*100:.2f}% [95% CI: {ci_95['top3_recall']['ci_95_low']*100:.1f}% - {ci_95['top3_recall']['ci_95_high']*100:.1f}%]")
    print(f"Pairwise Accuracy: {pairwise_acc*100:.2f}% [95% CI: {ci_95['pairwise_accuracy']['ci_95_low']*100:.1f}% - {ci_95['pairwise_accuracy']['ci_95_high']*100:.1f}%]")
    print(f"Mean Winner Rank:  {mean_rank:.3f}")
    print("\n--- Size Stratified ---")
    for cat, m in size_metrics.items():
        print(f"  {cat:12s} (N={m['count']:3d}): Top-1={m['top1_accuracy']*100:.1f}%, Top-2={m['top2_recall']*100:.1f}%, Top-3={m['top3_recall']*100:.1f}%")
    print("\n--- Face vs Non-Face Stratified ---")
    print(f"  Face Bursts    (N={face_metrics['face_series_count']:3d}): Top-1={face_metrics['face_top1']*100:.1f}% [95% CI: {ci_95['face_top1']['ci_95_low']*100:.1f}% - {ci_95['face_top1']['ci_95_high']*100:.1f}%]")
    print(f"  Non-Face Bursts(N={face_metrics['noface_series_count']:3d}): Top-1={face_metrics['noface_top1']*100:.1f}% [95% CI: {ci_95['noface_top1']['ci_95_low']*100:.1f}% - {ci_95['noface_top1']['ci_95_high']*100:.1f}%]")
    print(f"\nFrozen baseline saved to: {OUTPUT_BASELINE}")

if __name__ == "__main__":
    evaluate_baseline(VAL_MANIFEST, VAL_FEATURES)
