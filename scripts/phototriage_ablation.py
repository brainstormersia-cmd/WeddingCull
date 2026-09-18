import os
import sys
import json
import math
import argparse
import numpy as np
from ranking_evaluator import load_feature_cache, evaluate_series_ranking

def main():
    parser = argparse.ArgumentParser(description="WeddingCull Photo Triage Feature Ablation Study")
    parser.add_argument("--features", required=True, help="Path to exported features (.jsonl or .json)")
    parser.add_argument("--manifest", default="X:/WeddingCullDatasets/derived/manifests/photo_triage_dev.json", help="Evaluation manifest (DEV split)")
    parser.add_argument("--output", default="artifacts/phototriage_dev_ablation.json", help="Output artifact path")
    parser.add_argument("--allow-proxy-for-testing", action="store_true", help="Allow proxy features for testing")
    parser.add_argument("--num-bootstrap", type=int, default=1000, help="Number of series-level bootstrap iterations")
    args = parser.parse_args()

    print("=== WeddingCull Photo Triage Feature Ablation (DEV Split) ===")
    print(f"Features: {args.features}")
    print(f"Manifest: {args.manifest}")
    print(f"Allow Proxy: {args.allow_proxy_for_testing}")

    # Load and validate feature cache
    features, provenance, is_authentic = load_feature_cache(args.features, allow_proxy=args.allow_proxy_for_testing)
    print(f"Loaded {len(features)} feature vectors. Authentic: {is_authentic}")

    with open(args.manifest, "r", encoding="utf-8") as f:
        manifest_data = json.load(f)

    series_dict = manifest_data["series"]
    series_list = list(series_dict.values())
    print(f"Loaded {len(series_list)} series for ablation evaluation.")

    # Define Scoring Models for Ablation
    models = {}

    # R0: Authentic Production Baseline Heuristic (FCQ disabled, /500 clamp)
    def score_r0(pid, sid):
        feat = features.get(pid)
        if not feat: return 0.0
        return feat.get("productionBaselineFrameQuality", 0.0)
    models["R0_Production_Baseline_Heuristic"] = score_r0

    # R1: Production Heuristic + Authentic FCQ
    def score_r1(pid, sid):
        feat = features.get(pid)
        if not feat: return 0.0
        return feat.get("productionFrameQualityWithFCQ", 0.0)
    models["R1_Production_With_FCQ"] = score_r1

    # R2a: Continuous Log-Sharpness Transform: log(1 + sharp) / log(1 + 5000)
    def score_r2a_log(pid, sid):
        feat = features.get(pid)
        if not feat: return 0.0
        raw_s = feat.get("rawSharpness", 0.0)
        face_count = feat.get("face_count", 0)
        raw_fs = feat.get("rawFaceSharpness")

        log_sharp = math.log1p(raw_s) / math.log1p(5000.0)
        log_face_sharp = (math.log1p(raw_fs) / math.log1p(5000.0)) if raw_fs is not None else log_sharp

        score = 0.0
        if face_count > 0:
            score += 0.50 * 0.40
            score += min(1.0, log_face_sharp) * 0.30
            if feat.get("averageEyeOpenness") is not None:
                score += feat["averageEyeOpenness"] * 0.15
        else:
            score += min(1.0, log_sharp) * 0.60

        score += feat.get("exposureScore", 0.5) * 0.15
        if feat.get("severeUnderexposure", False) or feat.get("severeOverexposure", False):
            score -= 0.25
        return max(0.0, score)
    models["R2a_Log1p_Sharpness_Transform"] = score_r2a_log

    # R2b: Sigmoid Sharpness Transform: 1 / (1 + exp(-0.005 * (sharp - 400)))
    def score_r2b_sigmoid(pid, sid):
        feat = features.get(pid)
        if not feat: return 0.0
        raw_s = feat.get("rawSharpness", 0.0)
        face_count = feat.get("face_count", 0)
        raw_fs = feat.get("rawFaceSharpness")

        sig_sharp = 1.0 / (1.0 + math.exp(-max(-10.0, min(10.0, 0.005 * (raw_s - 400.0)))))
        sig_face_sharp = (1.0 / (1.0 + math.exp(-max(-10.0, min(10.0, 0.005 * (raw_fs - 400.0)))))) if raw_fs is not None else sig_sharp

        score = 0.0
        if face_count > 0:
            score += 0.50 * 0.40
            score += sig_face_sharp * 0.30
            if feat.get("averageEyeOpenness") is not None:
                score += feat["averageEyeOpenness"] * 0.15
        else:
            score += sig_sharp * 0.60

        score += feat.get("exposureScore", 0.5) * 0.15
        if feat.get("severeUnderexposure", False) or feat.get("severeOverexposure", False):
            score -= 0.25
        return max(0.0, score)
    models["R2b_Sigmoid_Sharpness_Transform"] = score_r2b_sigmoid

    # R2c: Face-Only Dominance (when faces present, 80% weight on face sharpness)
    def score_r2c_face_dominant(pid, sid):
        feat = features.get(pid)
        if not feat: return 0.0
        face_count = feat.get("face_count", 0)
        raw_fs = feat.get("rawFaceSharpness")
        raw_s = feat.get("rawSharpness", 0.0)

        score = 0.0
        if face_count > 0 and raw_fs is not None:
            # 80% on face sharpness
            score += (math.log1p(raw_fs) / math.log1p(5000.0)) * 0.80
            score += feat.get("exposureScore", 0.5) * 0.20
        else:
            score += (math.log1p(raw_s) / math.log1p(5000.0)) * 0.70
            score += feat.get("exposureScore", 0.5) * 0.30

        if feat.get("severeUnderexposure", False) or feat.get("severeOverexposure", False):
            score -= 0.25
        return max(0.0, score)
    models["R2c_Face_Dominant_Sharpness"] = score_r2c_face_dominant

    # Execute Evaluations
    results = {}
    print("\nRunning model evaluations with series-level bootstrap...")

    for model_name, score_fn in models.items():
        print(f"  Evaluating {model_name}...")
        res = evaluate_series_ranking(series_list, score_fn, num_bootstrap=args.num_bootstrap)
        results[model_name] = res
        pm = res["point_metrics"]
        ci = res["confidence_intervals_95_series_level"]
        pair_acc_ci = ci.get("pairwise_accuracy", {})
        top1_ci = ci.get("top1_accuracy", {})
        print(f"    Pairwise Acc: {pm.get('pairwise_accuracy', 0)*100:.2f}% [95% CI: {pair_acc_ci.get('ci_95_low', 0)*100:.1f}% - {pair_acc_ci.get('ci_95_high', 0)*100:.1f}%]")
        print(f"    Top-1 Acc:    {pm.get('top1_accuracy', 0)*100:.2f}% [95% CI: {top1_ci.get('ci_95_low', 0)*100:.1f}% - {top1_ci.get('ci_95_high', 0)*100:.1f}%]")
        print(f"    Top-2 Recall: {pm.get('top2_recall', 0)*100:.2f}% | Top-3 Recall: {pm.get('top3_recall', 0)*100:.2f}%")
        print(f"    Brier Score:  {pm.get('brier_score', 0):.4f} | Soft Log Loss: {pm.get('log_loss', 0):.4f}")
        print(f"    Acc @ 80% Cov:{pm.get('acc_at_80_cov', 0)*100:.2f}% (Error: {pm.get('err_at_80_cov', 0)*100:.2f}%)")

    # Persist Report Artifact
    experiment_state = "EXECUTED_AUTHENTIC" if is_authentic else "EXECUTED_PROXY"
    report = {
        "experiment_state": experiment_state,
        "label": "AUTHENTIC_EXPERIMENT" if is_authentic else "PROXY_EXPERIMENT — NOT PRODUCTION EQUIVALENT",
        "split": "DEV",
        "series_count": len(series_list),
        "provenance": provenance,
        "models_evaluated": results
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"\nAblation report written to: {args.output}")

if __name__ == "__main__":
    main()
