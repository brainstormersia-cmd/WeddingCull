import os
import sys
import json
import math
import argparse
import numpy as np
from scipy.optimize import minimize
from ranking_evaluator import load_feature_cache, evaluate_series_ranking

FEATURE_NAMES = [
    "log_raw_sharpness",
    "log_face_sharpness",
    "has_face",
    "detection_confidence",
    "fcq_available",
    "face_capture_quality",
    "eye_measured",
    "eye_openness",
    "mean_luminance",
    "shadow_clipping",
    "highlight_clipping",
    "dynamic_range",
    "contrast",
    "severe_underexposed",
    "severe_overexposed"
]

def extract_vector(feat):
    if not feat:
        return np.zeros(len(FEATURE_NAMES), dtype=np.float64)

    raw_s = feat.get("rawSharpness", 0.0)
    raw_fs = feat.get("rawFaceSharpness")
    log_s = math.log1p(raw_s) / math.log1p(5000.0)
    log_fs = (math.log1p(raw_fs) / math.log1p(5000.0)) if raw_fs is not None else log_s

    face_count = feat.get("face_count", 0)
    has_face = 1.0 if face_count > 0 else 0.0
    conf = feat.get("detectionConfidence", 0.5) if has_face else 0.0

    fcq = feat.get("faceCaptureQuality")
    fcq_available = 1.0 if fcq is not None else 0.0
    fcq_val = fcq if fcq is not None else 0.0

    eye_measured = 1.0 if (feat.get("faces_with_measured_eyes_count", 0) > 0 or (feat.get("landmarks_available", False) and feat.get("averageEyeOpenness") is not None)) else 0.0
    eye_val = feat.get("averageEyeOpenness", 0.0) if eye_measured else 0.0

    mean_lum = feat.get("meanLuminance", 0.5)
    shadow_clip = feat.get("shadowClipping", 0.0)
    highlight_clip = feat.get("highlightClipping", 0.0)
    dyn_range = feat.get("dynamicRange", 0.5)
    contrast = feat.get("contrast", 0.5)
    is_underexp = 1.0 if feat.get("severeUnderexposure", False) else 0.0
    is_overexp = 1.0 if feat.get("severeOverexposure", False) else 0.0

    return np.array([
        log_s,
        log_fs,
        has_face,
        conf,
        fcq_available,
        fcq_val,
        eye_measured,
        eye_val,
        mean_lum,
        shadow_clip,
        highlight_clip,
        dyn_range,
        contrast,
        is_underexp,
        is_overexp
    ], dtype=np.float64)

def sigmoid(z):
    z = np.clip(z, -15.0, 15.0)
    return 1.0 / (1.0 + np.exp(-z))

def main():
    parser = argparse.ArgumentParser(description="WeddingCull Linear Bradley-Terry Pairwise Preference Ranker")
    parser.add_argument("--features", required=True, help="Path to exported features (.jsonl or .json)")
    parser.add_argument("--fit-manifest", default="X:/WeddingCullDatasets/derived/manifests/photo_triage_fit.json", help="FIT split manifest")
    parser.add_argument("--dev-manifest", default="X:/WeddingCullDatasets/derived/manifests/photo_triage_dev.json", help="DEV split manifest")
    parser.add_argument("--output-model", default="artifacts/linear_pairwise_ranker.json", help="Path to save learned model weights")
    parser.add_argument("--l2-reg", type=float, default=1.0, help="L2 regularization strength")
    parser.add_argument("--allow-proxy-for-testing", action="store_true", help="Allow proxy features for testing")
    parser.add_argument("--num-bootstrap", type=int, default=1000, help="Number of series-level bootstrap iterations for evaluation")
    args = parser.parse_args()

    print("=== Training Linear Bradley-Terry Pairwise Preference Ranker ===")
    print(f"Features: {args.features}")
    print(f"FIT Manifest: {args.fit_manifest}")
    print(f"DEV Manifest: {args.dev_manifest}")
    print(f"L2 Regularization: {args.l2_reg}")

    # Load and validate feature cache
    features, provenance, is_authentic = load_feature_cache(args.features, allow_proxy=args.allow_proxy_for_testing)
    print(f"Loaded {len(features)} feature vectors. Authentic: {is_authentic}")

    with open(args.fit_manifest, "r", encoding="utf-8") as f:
        fit_data = json.load(f)
    with open(args.dev_manifest, "r", encoding="utf-8") as f:
        dev_data = json.load(f)

    fit_series = list(fit_data["series"].values())
    dev_series = list(dev_data["series"].values())
    print(f"FIT Series: {len(fit_series)}, DEV Series: {len(dev_series)}")

    # Prepare Training Pair Data
    X_diff_list = []
    y_target_list = []
    sample_weights_list = []

    for s in fit_series:
        pairs = s.get("pairs", []) or s.get("pairwise_comparisons", [])
        if not pairs: continue

        # Filter to pairs that possess genuine raw crowd votes
        valid_raw_pairs = []
        for p in pairs:
            if p.get("has_raw_votes") is False:
                continue
            va = p.get("votes_a")
            vb = p.get("votes_b")
            if va is None or vb is None or (va + vb) == 0:
                continue
            valid_raw_pairs.append(p)

        if not valid_raw_pairs: continue
        series_weight = 1.0 / float(len(valid_raw_pairs))  # Series-balanced weighting

        for p in valid_raw_pairs:
            pa = p["photo_a"]
            pb = p["photo_b"]
            va = p["votes_a"]
            vb = p["votes_b"]
            tot = va + vb

            feat_a = features.get(pa)
            feat_b = features.get(pb)
            if not feat_a or not feat_b: continue

            phi_a = extract_vector(feat_a)
            phi_b = extract_vector(feat_b)
            delta_phi = phi_a - phi_b
            p_target = va / tot

            X_diff_list.append(delta_phi)
            y_target_list.append(p_target)
            sample_weights_list.append(series_weight)

    X_diff = np.array(X_diff_list, dtype=np.float64)
    y_target = np.array(y_target_list, dtype=np.float64)
    sample_weights = np.array(sample_weights_list, dtype=np.float64)
    sample_weights /= np.mean(sample_weights)  # Normalize weights to mean 1

    print(f"Training on {len(X_diff)} pairwise comparisons from FIT split (strictly pairs with genuine raw votes).")

    # Objective: Weighted Soft Binary Cross-Entropy with L2 regularization
    num_feats = X_diff.shape[1]

    def loss_and_grad(w):
        logits = X_diff.dot(w)
        p_pred = sigmoid(logits)
        eps = 1e-12
        p_pred_clipped = np.clip(p_pred, eps, 1.0 - eps)

        bce = -(y_target * np.log(p_pred_clipped) + (1.0 - y_target) * np.log(1.0 - p_pred_clipped))
        weighted_loss = np.mean(sample_weights * bce) + 0.5 * args.l2_reg * np.sum(w ** 2)

        # Gradient
        grad_bce = sample_weights * (p_pred - y_target)
        grad = (X_diff.T.dot(grad_bce) / len(X_diff)) + args.l2_reg * w
        return weighted_loss, grad

    # Optimize using L-BFGS-B
    w0 = np.zeros(num_feats, dtype=np.float64)
    res = minimize(loss_and_grad, w0, jac=True, method="L-BFGS-B")

    learned_w = res.x
    print(f"\nOptimization Completed (Success: {res.success}, Iterations: {res.nit}, Loss: {res.fun:.4f})")
    print("=== Learned Feature Weights (Bradley-Terry) ===")
    for fname, weight in zip(FEATURE_NAMES, learned_w):
        print(f"  {fname:24s}: {weight:+.4f}")

    # Model Scoring Function
    def score_learned_model(pid, sid):
        feat = features.get(pid)
        if not feat: return 0.0
        vec = extract_vector(feat)
        return float(vec.dot(learned_w))

    # Evaluate on DEV split
    print("\nEvaluating Learned Model on DEV Split...")
    eval_result = evaluate_series_ranking(dev_series, score_learned_model, num_bootstrap=args.num_bootstrap)
    pm = eval_result["point_metrics"]
    ci = eval_result["confidence_intervals_95_series_level"]
    pair_acc_ci = ci.get("pairwise_accuracy", {})
    top1_ci = ci.get("top1_accuracy", {})

    print(f"  Pairwise Acc: {pm.get('pairwise_accuracy', 0)*100:.2f}% [95% CI: {pair_acc_ci.get('ci_95_low', 0)*100:.1f}% - {pair_acc_ci.get('ci_95_high', 0)*100:.1f}%]")
    print(f"  Top-1 Acc:    {pm.get('top1_accuracy', 0)*100:.2f}% [95% CI: {top1_ci.get('ci_95_low', 0)*100:.1f}% - {top1_ci.get('ci_95_high', 0)*100:.1f}%]")
    print(f"  Top-2 Recall: {pm.get('top2_recall', 0)*100:.2f}% | Top-3 Recall: {pm.get('top3_recall', 0)*100:.2f}%")
    print(f"  Brier Score:  {pm.get('brier_score', 0):.4f} | Soft Log Loss: {pm.get('log_loss', 0):.4f}")
    print(f"  Acc @ 80% Cov:{pm.get('acc_at_80_cov', 0)*100:.2f}% (Error: {pm.get('err_at_80_cov', 0)*100:.2f}%)")

    # Persist Learned Model
    experiment_state = "EXECUTED_AUTHENTIC" if is_authentic else "EXECUTED_PROXY"
    model_artifact = {
        "model_type": "Linear_Bradley_Terry_Pairwise_Scorer",
        "experiment_state": experiment_state,
        "label": "AUTHENTIC_MODEL" if is_authentic else "PROXY_EXPERIMENT — NOT PRODUCTION EQUIVALENT",
        "fit_series_count": len(fit_series),
        "fit_pairs_count": len(X_diff),
        "dev_series_count": len(dev_series),
        "feature_names": FEATURE_NAMES,
        "weights": learned_w.tolist(),
        "l2_regularization": args.l2_reg,
        "provenance": provenance,
        "dev_evaluation": eval_result
    }

    os.makedirs(os.path.dirname(args.output_model), exist_ok=True)
    with open(args.output_model, "w", encoding="utf-8") as f:
        json.dump(model_artifact, f, indent=2)
    print(f"\nModel artifact saved to: {args.output_model}")

if __name__ == "__main__":
    main()
