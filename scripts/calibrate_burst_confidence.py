#!/usr/bin/env python3
"""
scripts/calibrate_burst_confidence.py

Workstream 5: Calibrated Burst Confidence & Review Reduction
Fits probability models P(winner matches human preference | Delta s, context)
strictly on DEV_CAL (456 series, 1,196 pairs).

Evaluates:
- Platt Scaling vs Temperature Scaling vs Isotonic Regression vs Context-Aware Platt
- ECE (Expected Calibration Error), Brier Score, Log Loss
- Reliability Diagram bins
- Risk-Coverage Curve (Error rate at 90%, 80%, 70%, 50% coverage)
- Application to Real Wedding Shoot (wedding_shoot_74ef, 92 bursts):
  Evaluates Review reduction operating points under strict risk bounds.
"""

import os
import sys
import json
import math
import time
import argparse
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.isotonic import IsotonicRegression
from scipy.optimize import minimize

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

def compute_candidate_d_score(fn, tech_feats, face_feats):
    tf = tech_feats.get(fn, {})
    ff = face_feats.get(fn, {})
    
    raw_s = tf.get('rawSharpness', 0.0)
    norm_s = max(0.0, min(1.0, math.log1p(raw_s) / math.log1p(2000.0)))
    exp_score = tf.get('exposureScore', 0.5)
    
    has_face = (ff.get('face_count', 0) > 0)
    if has_face:
        raw_fs = ff.get('meanFaceSharpness') or ff.get('rawFaceSharpness') or raw_s
        norm_fs = max(0.0, min(1.0, math.log1p(raw_fs) / math.log1p(2000.0)))
        fcq = ff.get('meanFaceCaptureQuality') or ff.get('faceCaptureQuality') or 0.8
        eye = ff.get('averageEyeOpenness') or 0.8
        return 0.50 * norm_fs + 0.30 * fcq + 0.10 * eye + 0.10 * exp_score
    else:
        return 0.70 * norm_s + 0.30 * exp_score

def extract_dev_cal_burst_decisions(manifest_path, tech_path, faces_path):
    print(f"Loading DEV_CAL manifest: {manifest_path}")
    with open(manifest_path, 'r', encoding='utf-8') as f:
        mdata = json.load(f)
    with open(tech_path, 'r', encoding='utf-8') as f:
        tech_feats = json.load(f)
    with open(faces_path, 'r', encoding='utf-8') as f:
        face_feats = json.load(f)
        
    burst_data = []
    
    for sid, sinfo in mdata['series'].items():
        photos = [p['filename'] for p in sinfo.get('photos', [])]
        if len(photos) < 2: continue
        
        # Ground truth winner
        ranked_gt = sinfo.get('ranked_photos_preferred_order', [])
        if not ranked_gt:
            sorted_photos = sorted(sinfo.get('photos', []), key=lambda x: x.get('series_rank', 999))
            ranked_gt = [p['filename'] for p in sorted_photos]
        gt_winner = ranked_gt[0]
        
        # Candidate D scores
        scores = {fn: compute_candidate_d_score(fn, tech_feats, face_feats) for fn in photos}
        ranked_preds = sorted(photos, key=lambda fn: (-scores[fn], fn))
        pred_winner = ranked_preds[0]
        pred_runner_up = ranked_preds[1]
        
        s_win = scores[pred_winner]
        s_ru = scores[pred_runner_up]
        delta_s = max(0.0, s_win - s_ru)
        
        # Target: 1 if model predicted winner matches human ground-truth winner, 0 otherwise
        is_winner_correct = 1.0 if (pred_winner == gt_winner) else 0.0
        
        has_faces = any(face_feats.get(fn, {}).get('face_count', 0) > 0 for fn in photos)
        
        burst_data.append({
            'series_id': sid,
            'size': len(photos),
            'has_faces': 1.0 if has_faces else 0.0,
            'delta_s': delta_s,
            'winner_id': pred_winner,
            'runner_up_id': pred_runner_up,
            'gt_winner': gt_winner,
            'is_correct': is_winner_correct
        })
        
    print(f"Extracted {len(burst_data)} series decisions from DEV_CAL.")
    return burst_data

def compute_calibration_metrics(y_true, y_prob, n_bins=10):
    brier = float(np.mean((y_prob - y_true) ** 2))
    
    eps = 1e-12
    y_prob_clip = np.clip(y_prob, eps, 1.0 - eps)
    log_loss = float(-np.mean(y_true * np.log(y_prob_clip) + (1.0 - y_true) * np.log(1.0 - y_prob_clip)))
    
    # ECE
    bin_edges = np.linspace(0.0, 1.0, n_bins + 1)
    ece = 0.0
    reliability_bins = []
    
    for i in range(n_bins):
        low, high = bin_edges[i], bin_edges[i+1]
        mask = (y_prob >= low) & (y_prob < high) if i < n_bins - 1 else (y_prob >= low) & (y_prob <= high)
        n_in_bin = int(np.sum(mask))
        if n_in_bin > 0:
            bin_conf = float(np.mean(y_prob[mask]))
            bin_acc = float(np.mean(y_true[mask]))
            bin_err = abs(bin_acc - bin_conf)
            ece += (n_in_bin / len(y_true)) * bin_err
            reliability_bins.append({
                'bin_idx': i,
                'range': [float(low), float(high)],
                'count': n_in_bin,
                'mean_confidence': bin_conf,
                'empirical_accuracy': bin_acc,
                'calibration_error': bin_err
            })
        else:
            reliability_bins.append({
                'bin_idx': i,
                'range': [float(low), float(high)],
                'count': 0,
                'mean_confidence': float((low + high) / 2.0),
                'empirical_accuracy': 0.0,
                'calibration_error': 0.0
            })
            
    return {
        'brier_score': brier,
        'log_loss': log_loss,
        'ece': ece,
        'reliability_diagram_bins': reliability_bins
    }

def compute_risk_coverage_curve(y_true, y_prob):
    """
    Evaluates error rate as a function of automatic coverage.
    Decisions with high confidence are auto-accepted (coverage); low confidence sent to Review.
    """
    sorted_indices = np.argsort(y_prob)[::-1] # highest confidence first
    sorted_true = y_true[sorted_indices]
    
    total = len(y_true)
    coverages = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2]
    
    curve = []
    for cov in coverages:
        k = max(1, int(round(total * cov)))
        accepted_true = sorted_true[:k]
        # Error rate = fraction of accepted decisions where winner was wrong
        acc = np.mean(accepted_true)
        err_rate = float(1.0 - acc)
        min_prob_threshold = float(y_prob[sorted_indices[k - 1]])
        
        curve.append({
            'coverage_pct': cov * 100.0,
            'retained_count': k,
            'review_count': total - k,
            'review_rate_pct': (1.0 - cov) * 100.0,
            'confidence_threshold': min_prob_threshold,
            'error_rate_pct': err_rate * 100.0,
            'accuracy_pct': float(acc * 100.0)
        })
        
    return curve

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dev-manifest', default='X:/WeddingCullDatasets/derived/manifests/photo_triage_dev_cal.json')
    parser.add_argument('--dev-tech', default='X:/WeddingCullDatasets/derived/features/photo_triage_dev_cal_technical.json')
    parser.add_argument('--dev-faces', default='X:/WeddingCullDatasets/derived/features/photo_triage_dev_cal_faces.json')
    parser.add_argument('--wedding-report', default='artifacts/real_wedding_benchmark_report.json')
    parser.add_argument('--output', default='artifacts/burst_confidence_calibration_report.json')
    args = parser.parse_args()
    
    print("===================================================================")
    print("📈 WeddingCull Burst Confidence Calibration & Review Reduction")
    print("   Dataset Split: DEV_CAL (456 series, strictly disjoint from DEV_SELECT)")
    print("   VAL is STRICTLY FROZEN and untouched!")
    print("===================================================================")
    
    burst_data = extract_dev_cal_burst_decisions(args.dev_manifest, args.dev_tech, args.dev_faces)
    
    y_true = np.array([d['is_correct'] for d in burst_data], dtype=np.float64)
    delta_s = np.array([d['delta_s'] for d in burst_data], dtype=np.float64)
    has_faces = np.array([d['has_faces'] for d in burst_data], dtype=np.float64)
    sizes = np.array([d['size'] for d in burst_data], dtype=np.float64)
    
    # Baseline: Current heuristic (P = 0.90 if delta_s > 0.05 else 0.50)
    baseline_probs = np.where(delta_s > 0.05, 0.85, 0.45)
    base_metrics = compute_calibration_metrics(y_true, baseline_probs)
    print("\n--- Baseline Heuristic Confidence (Hard Delta > 0.05) on DEV_CAL ---")
    print(f"  ECE:         {base_metrics['ece']:.4f}")
    print(f"  Brier Score: {base_metrics['brier_score']:.4f}")
    print(f"  Log Loss:    {base_metrics['log_loss']:.4f}")
    
    # Model 1: Platt Scaling (Univariate Delta_s)
    platt_model = LogisticRegression(C=1.0)
    platt_model.fit(delta_s.reshape(-1, 1), y_true)
    platt_probs = platt_model.predict_proba(delta_s.reshape(-1, 1))[:, 1]
    platt_metrics = compute_calibration_metrics(y_true, platt_probs)
    print("\n--- Model 1: Platt Scaling (P = sigmoid(a * delta_s + b)) ---")
    print(f"  Learned Param a: {platt_model.coef_[0][0]:.4f}, b: {platt_model.intercept_[0]:.4f}")
    print(f"  ECE:             {platt_metrics['ece']:.4f}")
    print(f"  Brier Score:     {platt_metrics['brier_score']:.4f}")
    print(f"  Log Loss:        {platt_metrics['log_loss']:.4f}")
    
    # Model 2: Temperature Scaling (delta_s / T)
    def temp_loss(T):
        p = 1.0 / (1.0 + np.exp(-delta_s / max(0.01, T[0])))
        eps = 1e-12
        p = np.clip(p, eps, 1.0 - eps)
        return -np.mean(y_true * np.log(p) + (1.0 - y_true) * np.log(1.0 - p))
    res_t = minimize(temp_loss, [0.1], method='Nelder-Mead')
    opt_t = float(res_t.x[0])
    temp_probs = 1.0 / (1.0 + np.exp(-delta_s / max(0.01, opt_t)))
    temp_metrics = compute_calibration_metrics(y_true, temp_probs)
    print("\n--- Model 2: Temperature Scaling (P = sigmoid(delta_s / T)) ---")
    print(f"  Learned Temp T:  {opt_t:.4f}")
    print(f"  ECE:             {temp_metrics['ece']:.4f}")
    print(f"  Brier Score:     {temp_metrics['brier_score']:.4f}")
    print(f"  Log Loss:        {temp_metrics['log_loss']:.4f}")
    
    # Model 3: Isotonic Regression
    iso_model = IsotonicRegression(out_of_bounds='clip')
    iso_probs = iso_model.fit_transform(delta_s, y_true)
    iso_metrics = compute_calibration_metrics(y_true, iso_probs)
    print("\n--- Model 3: Isotonic Regression ---")
    print(f"  ECE:             {iso_metrics['ece']:.4f}")
    print(f"  Brier Score:     {iso_metrics['brier_score']:.4f}")
    print(f"  Log Loss:        {iso_metrics['log_loss']:.4f}")
    
    # Model 4: Context-Aware Platt Scaling (Delta_s + has_faces + 1/size)
    inv_size = 1.0 / sizes
    X_context = np.column_stack([delta_s, has_faces, inv_size])
    ctx_model = LogisticRegression(C=1.0)
    ctx_model.fit(X_context, y_true)
    ctx_probs = ctx_model.predict_proba(X_context)[:, 1]
    ctx_metrics = compute_calibration_metrics(y_true, ctx_probs)
    print("\n--- Model 4: Context-Aware Platt Scaling (Delta_s + HasFaces + 1/Size) ---")
    print(f"  Coefficients:    Delta_s={ctx_model.coef_[0][0]:.3f}, HasFaces={ctx_model.coef_[0][1]:.3f}, 1/Size={ctx_model.coef_[0][2]:.3f}, Bias={ctx_model.intercept_[0]:.3f}")
    print(f"  ECE:             {ctx_metrics['ece']:.4f}")
    print(f"  Brier Score:     {ctx_metrics['brier_score']:.4f}")
    print(f"  Log Loss:        {ctx_metrics['log_loss']:.4f}")
    
    # Best calibration model selection on DEV_CAL
    candidate_models = {
        'Baseline Heuristic': (base_metrics, baseline_probs),
        'Platt Scaling': (platt_metrics, platt_probs),
        'Temperature Scaling': (temp_metrics, temp_probs),
        'Isotonic Regression': (iso_metrics, iso_probs),
        'Context-Aware Platt': (ctx_metrics, ctx_probs)
    }
    
    # Select by lowest Brier score
    best_cal_name = min(candidate_models.keys(), key=lambda k: candidate_models[k][0]['brier_score'])
    best_cal_metrics, best_cal_probs = candidate_models[best_cal_name]
    print(f"\n🏆 Best Calibrated Model on DEV_CAL: {best_cal_name} (Brier={best_cal_metrics['brier_score']:.4f}, ECE={best_cal_metrics['ece']:.4f})")
    
    # Risk-Coverage Curve
    print("\n--- Risk-Coverage Analysis on DEV_CAL ---")
    risk_curve = compute_risk_coverage_curve(y_true, best_cal_probs)
    print(f"{'Coverage':>10} | {'Review Rate':>12} | {'Prob Threshold':>15} | {'Error Rate':>12} | {'Accuracy':>10}")
    print("-" * 68)
    for pt in risk_curve:
        print(f"{pt['coverage_pct']:9.0f}% | {pt['review_rate_pct']:11.1f}% | {pt['confidence_threshold']:14.4f} | {pt['error_rate_pct']:11.2f}% | {pt['accuracy_pct']:9.2f}%")
        
    # Real Wedding Shoot Application
    print("\n===================================================================")
    print("💒 Transfer of Calibrated Confidence Model to Real Wedding Shoot 74ef")
    print("===================================================================")
    with open(args.wedding_report, 'r', encoding='utf-8') as f:
        rep = json.load(f)
        
    all_bursts = rep.get('allBursts', [])
    print(f"Applying calibrated model to {len(all_bursts)} autonomous bursts...")
    
    # Extract features for bursts
    burst_sims = []
    for b in all_bursts:
        d_val = b.get('scoreDifference', 0.0) or 0.0
        hf = 1.0 if b['hasFaces'] else 0.0
        sz = float(b['memberCount'])
        inv_sz = 1.0 / sz
        
        # Predict with Context-Aware Platt
        feat_vec = np.array([[d_val, hf, inv_sz]])
        p_cal = float(ctx_model.predict_proba(feat_vec)[0, 1])
        
        burst_sims.append({
            'burstId': b['burstId'],
            'memberCount': int(sz),
            'hasFaces': bool(hf),
            'scoreDifference': d_val,
            'currentReview': (b.get('reviewCount', 0) > 0),
            'calibratedProbability': p_cal
        })
        
    # Analyze Review count reduction under standard photographer risk tolerances
    # Thresholds: P >= 0.85, P >= 0.80, P >= 0.75, P >= 0.70, P >= 0.65
    operating_points = []
    current_review_count = rep.get('reviewCount', 76)
    current_review_rate = rep.get('reviewRatioPct', 82.6)
    
    for thresh in [0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55]:
        auto_accepted_bursts = sum(1 for b in burst_sims if b['calibratedProbability'] >= thresh)
        review_bursts = len(burst_sims) - auto_accepted_bursts
        review_rate = (review_bursts / len(burst_sims)) * 100.0
        operating_points.append({
            'probability_threshold': thresh,
            'auto_accepted_bursts': auto_accepted_bursts,
            'review_bursts_count': review_bursts,
            'review_rate_pct': review_rate,
            'bursts_freed_from_review': current_review_count - review_bursts,
            'review_reduction_pct': ((current_review_count - review_bursts) / current_review_count) * 100.0 if current_review_count else 0.0
        })
        
    print(f"\nCurrent Production Baseline on Wedding Shoot 74ef:")
    print(f"  Reviews: {current_review_count} / {len(all_bursts)} bursts ({current_review_rate:.1f}% Review Rate)")
    print(f"\nCalibrated Review Rate Operating Points on Wedding Shoot 74ef:")
    print(f"{'Prob Threshold':>15} | {'Review Bursts':>14} | {'Review Rate':>12} | {'Reviews Saved':>14} | {'Reduction':>10}")
    print("-" * 75)
    for op in operating_points:
        print(f"{op['probability_threshold']:14.2f} | {op['review_bursts_count']:13d} | {op['review_rate_pct']:11.1f}% | {op['bursts_freed_from_review']:13d} | {op['review_reduction_pct']:9.1f}%")
        
    final_calibration_report = {
        'split': 'DEV_CAL',
        'total_burst_decisions': len(burst_data),
        'best_calibration_model': best_cal_name,
        'model_comparisons': {
            name: {
                'brier_score': m[0]['brier_score'],
                'log_loss': m[0]['log_loss'],
                'ece': m[0]['ece']
            } for name, m in candidate_models.items()
        },
        'best_model_reliability_diagram': best_cal_metrics['reliability_diagram_bins'],
        'risk_coverage_curve': risk_curve,
        'wedding_shoot_74ef_transfer': {
            'total_bursts': len(all_bursts),
            'baseline_review_count': current_review_count,
            'baseline_review_rate_pct': current_review_rate,
            'calibrated_operating_points': operating_points
        },
        'safety_statement': "0 photos auto-rejected; human keeper loss on wedding_shoot_74ef is unmeasurable because no human keeper ground truth is available."
    }
    
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(final_calibration_report, f, indent=2)
    print(f"\nSaved burst confidence calibration report to: {args.output}")

if __name__ == '__main__':
    main()
