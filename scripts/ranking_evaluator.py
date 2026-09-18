import os
import sys
import json
import math
import collections
import numpy as np

def load_feature_cache(features_path, allow_proxy=False):
    """
    Loads feature cache from JSONL or JSON file.
    Enforces provenance metadata validation.
    """
    if not os.path.exists(features_path):
        raise FileNotFoundError(f"Feature cache not found at: {features_path}")

    provenance_start = None
    provenance_completion = None
    features = {}

    if features_path.endswith(".jsonl"):
        with open(features_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line: continue
                record = json.loads(line)
                rec_type = record.get("record_type")
                if rec_type in ("PROVENANCE_HEADER", "PROVENANCE_START"):
                    provenance_start = record
                elif rec_type == "PROVENANCE_COMPLETION":
                    provenance_completion = record
                elif rec_type == "PHOTO_FEATURES":
                    features[record["photo_id"]] = record
                else:
                    # Fallback for plain jsonl
                    pid = record.get("photo_id") or record.get("photoId")
                    if pid: features[pid] = record
    else:
        with open(features_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            provenance_start = data.get("provenance") or data.get("provenance_start")
            provenance_completion = data.get("provenance_completion")
            if "features" in data:
                features = data["features"]
            else:
                features = {k: v for k, v in data.items() if k not in ("provenance", "provenance_start", "provenance_completion")}
        else:
            features = data

    provenance = provenance_completion or provenance_start

    # Provenance Validation: EXECUTED_AUTHENTIC is only valid if PROVENANCE_COMPLETION is present,
    # ran on macOS, and executed without blocking failure.
    is_authentic = False
    if provenance_completion:
        exp_state = provenance_completion.get("experiment_state")
        platform = provenance_completion.get("platform", "")
        if exp_state == "EXECUTED_AUTHENTIC" and "macOS" in platform:
            is_authentic = True
    elif provenance_start:
        exp_state = provenance_start.get("experiment_state")
        platform = provenance_start.get("platform", "")
        vision_req = provenance_start.get("apple_vision_requested", False)
        if exp_state == "EXECUTED_AUTHENTIC" and "macOS" in platform and vision_req:
            is_authentic = True

    if not is_authentic and not allow_proxy:
        raise RuntimeError(
            f"BLOCKED_MACOS_REQUIRED: Authentic Apple Vision features required.\n"
            f"Feature cache at '{features_path}' does not contain valid macOS authentic provenance.\n"
            f"Provenance record: {provenance}\n"
            f"To run as a labeled proxy experiment for testing, pass --allow-proxy-for-testing explicitly."
        )

    return features, provenance, is_authentic

def evaluate_series_ranking(series_list, score_fn, num_bootstrap=1000, seed=42):
    """
    Evaluates pairwise and series-ranking performance over complete series.
    Computes 95% bootstrap confidence intervals resampled strictly at SERIES level.
    """
    rng = np.random.RandomState(seed)

    evaluated_series_count = len(series_list)
    series_results = []
    all_pairs = []

    for s in series_list:
        sid = s["series_id"]
        # Score each photo
        photo_scores = {}
        for p in s.get("photos", []):
            fname = p["filename"] if isinstance(p, dict) else p
            photo_scores[fname] = score_fn(fname, sid)

        # Ranked photos descending
        ranked_pids = sorted(photo_scores.keys(), key=lambda pid: (-photo_scores[pid], pid))

        # Preferred order
        pref_order = s.get("ranked_photos_preferred_order") or s.get("preferred_order") or []
        preferred_winner = pref_order[0] if pref_order else None

        top1_hit = (ranked_pids[0] == preferred_winner) if (ranked_pids and preferred_winner) else False
        top2_hit = (preferred_winner in ranked_pids[:2]) if (len(ranked_pids) >= 2 and preferred_winner) else False
        top3_hit = (preferred_winner in ranked_pids[:3]) if (preferred_winner and len(ranked_pids) >= 1) else False
        winner_rank = (ranked_pids.index(preferred_winner) + 1) if (preferred_winner and preferred_winner in ranked_pids) else len(ranked_pids)

        series_pairs = []
        for p in s.get("pairs", []) or s.get("pairwise_comparisons", []):
            pa = p["photo_a"]
            pb = p["photo_b"]
            va = p.get("votes_a")
            vb = p.get("votes_b")
            has_raw = p.get("has_raw_votes", True)
            derived_pref = p.get("derived_order_preference")

            sa = photo_scores.get(pa, 0.0)
            sb = photo_scores.get(pb, 0.0)
            diff = sa - sb

            # Sigmoid calibrated predicted probability: P(A > B)
            p_pred_a = 1.0 / (1.0 + math.exp(-max(-10.0, min(10.0, diff * 5.0))))

            if has_raw and va is not None and vb is not None and (va + vb) > 0:
                tot = va + vb
                p_human_a = va / tot
                agreement = max(va, vb) / tot
                maj_winner = pa if va > vb else (pb if vb > va else None)
                is_correct = (pa if sa >= sb else pb) == maj_winner if maj_winner else None
                brier = (p_pred_a - p_human_a) ** 2
                eps = 1e-6
                p_pred_clip = max(eps, min(1.0 - eps, p_pred_a))
                log_loss = -(p_human_a * math.log(p_pred_clip) + (1.0 - p_human_a) * math.log(1.0 - p_pred_clip))

                if agreement >= 0.90:
                    stratum = "DECISIVE_CONSENSUS"
                elif agreement >= 0.80:
                    stratum = "STRONG_CONSENSUS"
                elif agreement >= 0.70:
                    stratum = "MODERATE_CONSENSUS"
                else:
                    stratum = "AMBIGUOUS_OR_SPLIT"
            else:
                tot = 0
                p_human_a = 0.5
                agreement = 1.0
                maj_winner = derived_pref
                is_correct = ((pa if sa >= sb else pb) == maj_winner) if maj_winner else None
                brier = None
                log_loss = None
                stratum = "DERIVED_RANK"

            pair_res = {
                "series_id": sid,
                "photo_a": pa,
                "photo_b": pb,
                "score_diff": diff,
                "confidence_proxy": abs(diff),
                "is_correct": is_correct,
                "brier": brier,
                "log_loss": log_loss,
                "agreement": agreement,
                "agreement_stratum": stratum
            }
            series_pairs.append(pair_res)
            all_pairs.append(pair_res)

        series_results.append({
            "series_id": sid,
            "top1_hit": top1_hit,
            "top2_hit": top2_hit,
            "top3_hit": top3_hit,
            "winner_rank": winner_rank,
            "pairs": series_pairs
        })

    # Point estimates
    def compute_summary_metrics(s_subset):
        pairs_subset = []
        for s in s_subset:
            pairs_subset.extend(s["pairs"])

        n_s = len(s_subset)
        if n_s == 0 or len(pairs_subset) == 0:
            return {}

        top1 = sum(1 for s in s_subset if s["top1_hit"]) / n_s
        top2 = sum(1 for s in s_subset if s["top2_hit"]) / n_s
        top3 = sum(1 for s in s_subset if s["top3_hit"]) / n_s
        mean_rank = sum(s["winner_rank"] for s in s_subset) / n_s

        maj_pairs = [p for p in pairs_subset if p["is_correct"] is not None]
        pairwise_acc = sum(1 for p in maj_pairs if p["is_correct"]) / len(maj_pairs) if maj_pairs else 0.0

        brier_pairs = [p for p in pairs_subset if p["brier"] is not None]
        brier = sum(p["brier"] for p in brier_pairs) / len(brier_pairs) if brier_pairs else 0.0
        log_loss = sum(p["log_loss"] for p in brier_pairs) / len(brier_pairs) if brier_pairs else 0.0

        # Risk-coverage at 80%
        sorted_pairs = sorted(pairs_subset, key=lambda p: p["confidence_proxy"], reverse=True)
        cov80_cutoff = int(math.ceil(0.80 * len(sorted_pairs)))
        sub80 = sorted_pairs[:cov80_cutoff]
        sub80_maj = [p for p in sub80 if p["is_correct"] is not None]
        acc_80 = sum(1 for p in sub80_maj if p["is_correct"]) / len(sub80_maj) if sub80_maj else 0.0
        err_80 = 1.0 - acc_80

        return {
            "pairwise_accuracy": pairwise_acc,
            "brier_score": brier,
            "log_loss": log_loss,
            "top1_accuracy": top1,
            "top2_recall": top2,
            "top3_recall": top3,
            "mean_winner_rank": mean_rank,
            "acc_at_80_cov": acc_80,
            "err_at_80_cov": err_80
        }

    point_metrics = compute_summary_metrics(series_results)

    # 95% Bootstrap Confidence Intervals resampled strictly by SERIES
    bootstrap_metrics = collections.defaultdict(list)
    n_series = len(series_results)

    if num_bootstrap > 0 and n_series > 1:
        for b in range(num_bootstrap):
            indices = rng.choice(n_series, size=n_series, replace=True)
            resampled_series = [series_results[i] for i in indices]
            b_metrics = compute_summary_metrics(resampled_series)
            for k, v in b_metrics.items():
                bootstrap_metrics[k].append(v)

    confidence_intervals = {}
    for k, values in bootstrap_metrics.items():
        if values:
            ci_low = float(np.percentile(values, 2.5))
            ci_high = float(np.percentile(values, 97.5))
            confidence_intervals[k] = {
                "ci_95_low": round(ci_low, 4),
                "ci_95_high": round(ci_high, 4),
                "point_estimate": round(point_metrics.get(k, 0.0), 4)
            }

    # Strata breakdown
    strata_breakdown = {}
    for st in ["DECISIVE_CONSENSUS", "STRONG_CONSENSUS", "MODERATE_CONSENSUS", "AMBIGUOUS_OR_SPLIT", "DERIVED_RANK"]:
        st_pairs = [p for p in all_pairs if p["agreement_stratum"] == st]
        if not st_pairs: continue
        st_maj = [p for p in st_pairs if p["is_correct"] is not None]
        st_acc = sum(1 for p in st_maj if p["is_correct"]) / len(st_maj) if st_maj else 0.0
        st_brier = [p["brier"] for p in st_pairs if p["brier"] is not None]
        mean_brier = round(sum(st_brier) / len(st_brier), 4) if st_brier else None
        strata_breakdown[st] = {
            "pairs_count": len(st_pairs),
            "fraction_of_total": round(len(st_pairs) / max(1, len(all_pairs)), 4),
            "majority_accuracy": round(st_acc * 100, 2),
            "mean_brier": mean_brier
        }

    return {
        "point_metrics": point_metrics,
        "confidence_intervals_95_series_level": confidence_intervals,
        "strata_breakdown": strata_breakdown,
        "total_series": len(series_list),
        "total_pairs": len(all_pairs)
    }
