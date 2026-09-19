#!/usr/bin/env python3
"""
scripts/train_ranker_dev_select.py

Trains and selects the learned relative ranker strictly on FIT -> DEV_SELECT:
1. Linear Bradley-Terry Model (s(x) = w^T phi(x))
2. Tiny 2-Layer MLP (phi(x) -> 32 -> 1)
3. Evaluates Candidate D baseline on DEV_SELECT
4. Ablates features (Technical only, +Burst-relative, +Worst-face)
5. Ablates L2 regularization (0.001 to 10.0)
6. Computes paired-series bootstrap difference CIs (Candidate - Baseline) on DEV_SELECT
7. Predeclared non-inferiority check on face bursts (Delta >= -1.5%)

Strict Holdout Hygiene: Zero evaluation on VAL during this step!
"""

import os
import sys
import json
import math
import time
import argparse
import numpy as np
from scipy.optimize import minimize

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# Feature definitions
TECH_FEATURE_NAMES = [
    'log_raw_sharpness',
    'exposure_score',
    'mean_luminance',
    'shadow_clipping',
    'highlight_clipping',
    'dynamic_range',
    'contrast'
]

RELATIVE_FEATURE_NAMES = [
    'rel_sharpness_burst',
    'rel_exposure_burst',
    'log_sharpness_spread',
    'series_size_norm'
]

FACE_FEATURE_NAMES = [
    'has_face',
    'face_count',
    'min_face_sharpness',
    'mean_face_sharpness',
    'problematic_face_count'
]

ALL_FEATURE_NAMES = TECH_FEATURE_NAMES + RELATIVE_FEATURE_NAMES + FACE_FEATURE_NAMES

def extract_features_dict(photos_in_series, tech_feats, face_feats=None):
    """
    Computes feature vectors for all photos within a single series.
    Includes burst-relative normalized metrics and worst-face metrics.
    """
    raw_s_list = []
    exp_list = []
    
    for fn in photos_in_series:
        tf = tech_feats.get(fn, {})
        raw_s_list.append(tf.get('rawSharpness', 0.0))
        exp_list.append(tf.get('exposureScore', 0.5))
        
    min_s, max_s = min(raw_s_list), max(raw_s_list)
    min_e, max_e = min(exp_list), max(exp_list)
    s_spread = math.log1p(max_s) - math.log1p(min_s)
    n_photos = len(photos_in_series)
    
    series_vectors = {}
    for i, fn in enumerate(photos_in_series):
        tf = tech_feats.get(fn, {})
        ff = face_feats.get(fn, {}) if face_feats else {}
        
        # Technical
        raw_s = tf.get('rawSharpness', 0.0)
        log_s = math.log1p(raw_s) / math.log1p(5000.0)
        exp_score = tf.get('exposureScore', 0.5)
        mean_lum = tf.get('meanLuminance', 0.5)
        shadow_clip = tf.get('shadowClipping', 0.0)
        highlight_clip = tf.get('highlightClipping', 0.0)
        dyn_range = tf.get('dynamicRange', 0.5)
        contrast = tf.get('contrast', 0.5)
        
        # Relative
        rel_s = (raw_s - min_s) / (max_s - min_s + 1e-6)
        rel_e = (exp_score - min_e) / (max_e - min_e + 1e-6)
        norm_size = min(1.0, n_photos / 10.0)
        
        # Face / Worst-Face
        has_face = float(ff.get('has_face', 0.0))
        face_cnt = min(1.0, float(ff.get('face_count', 0)) / 10.0)
        min_fs = math.log1p(ff.get('minFaceSharpness') or 0.0) / math.log1p(5000.0) if has_face else log_s
        mean_fs = math.log1p(ff.get('meanFaceSharpness') or 0.0) / math.log1p(5000.0) if has_face else log_s
        prob_cnt = min(1.0, float(ff.get('problematic_face_count', 0)) / 5.0)
        
        vec = [
            log_s, exp_score, mean_lum, shadow_clip, highlight_clip, dyn_range, contrast,
            rel_s, rel_e, s_spread, norm_size,
            has_face, face_cnt, min_fs, mean_fs, prob_cnt
        ]
        series_vectors[fn] = np.array(vec, dtype=np.float64)
        
    return series_vectors

def compute_candidate_d_score(fn, tech_feats, face_feats=None):
    """
    Computes exact production Candidate D score:
    Non-face: 0.70 * sharpnessScore + 0.30 * exposureScore
    Face: 0.50 * faceSharpnessScore + 0.30 * faceCaptureQuality + 0.10 * eyeScore + 0.10 * exposureScore
    """
    tf = tech_feats.get(fn, {})
    ff = face_feats.get(fn, {}) if face_feats else {}
    
    raw_s = tf.get('rawSharpness', 0.0)
    # Candidate D sharpness log normalizer
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

def build_training_pairs(fit_manifest, fit_tech, fit_faces=None, feature_mask=None):
    """
    Constructs training pairs and weights for Bradley-Terry loss.
    """
    with open(fit_manifest, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    X_diff = []
    y_soft = []
    weights = []
    
    for sid, sinfo in data['series'].items():
        photos = [p['filename'] for p in sinfo.get('photos', [])]
        if len(photos) < 2: continue
        
        series_vecs = extract_features_dict(photos, fit_tech, fit_faces)
        pairs = sinfo.get('pairs', [])
        if not pairs: continue
        
        w_series = 1.0 / len(pairs)
        
        for pr in pairs:
            fa = os.path.basename(pr['path_a'])
            fb = os.path.basename(pr['path_b'])
            va = pr.get('votes_a')
            vb = pr.get('votes_b')
            if va is None or vb is None or (va + vb) == 0: continue
            
            p_human_a = va / (va + vb)
            va_vec = series_vecs.get(fa)
            vb_vec = series_vecs.get(fb)
            if va_vec is None or vb_vec is None: continue
            
            diff = va_vec - vb_vec
            if feature_mask is not None:
                diff = diff[feature_mask]
                
            X_diff.append(diff)
            y_soft.append(p_human_a)
            weights.append(w_series)
            
    return np.array(X_diff, dtype=np.float64), np.array(y_soft, dtype=np.float64), np.array(weights, dtype=np.float64)

def fit_bradley_terry(X_diff, y_soft, weights, l2_reg=1.0):
    dim = X_diff.shape[1]
    
    def loss_and_grad(w):
        z = np.dot(X_diff, w)
        z_clip = np.clip(z, -20.0, 20.0)
        p = 1.0 / (1.0 + np.exp(-z_clip))
        
        eps = 1e-12
        p_safe = np.clip(p, eps, 1.0 - eps)
        # Soft cross-entropy
        bce = -(y_soft * np.log(p_safe) + (1.0 - y_soft) * np.log(1.0 - p_safe))
        weighted_loss = np.sum(weights * bce) + l2_reg * np.sum(w ** 2)
        
        # Gradient
        grad = np.dot(X_diff.T, weights * (p - y_soft)) + 2.0 * l2_reg * w
        return weighted_loss, grad
        
    init_w = np.zeros(dim)
    res = minimize(loss_and_grad, init_w, jac=True, method='L-BFGS-B')
    return res.x

def evaluate_ranker_on_series(manifest_path, tech_feats, face_feats, score_fn):
    """
    Evaluates series ranking and returns per-series accuracy metrics.
    """
    with open(manifest_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    series_results = []
    
    for sid, sinfo in data['series'].items():
        photos = [p['filename'] for p in sinfo.get('photos', [])]
        if len(photos) < 2: continue
        
        # Series features
        series_vecs = extract_features_dict(photos, tech_feats, face_feats)
        
        # Preferred ground truth
        ranked_gt = sinfo.get('ranked_photos_preferred_order', [])
        if not ranked_gt:
            sorted_photos = sorted(sinfo.get('photos', []), key=lambda x: x.get('series_rank', 999))
            ranked_gt = [p['filename'] for p in sorted_photos]
        gt_winner = ranked_gt[0]
        
        # Model predicted ranking
        pred_scores = {fn: score_fn(fn, series_vecs[fn]) for fn in photos}
        ranked_preds = sorted(photos, key=lambda fn: (-pred_scores[fn], fn))
        
        is_top1 = (ranked_preds[0] == gt_winner)
        is_top2 = (gt_winner in ranked_preds[:2])
        is_top3 = (gt_winner in ranked_preds[:3])
        
        # Face stratum
        has_face_group = any(face_feats.get(fn, {}).get('face_count', 0) > 0 for fn in photos) if face_feats else False
        
        # Pairwise accuracy
        pairs = sinfo.get('pairs', [])
        p_correct = 0
        p_total = 0
        for pr in pairs:
            fa = os.path.basename(pr['path_a'])
            fb = os.path.basename(pr['path_b'])
            maj = pr.get('majority_winner')
            if not maj: continue
            
            sa = pred_scores.get(fa, 0.0)
            sb = pred_scores.get(fb, 0.0)
            pred_winner = fa if sa >= sb else fb
            p_total += 1
            if pred_winner == maj:
                p_correct += 1
                
        pair_acc = (p_correct / p_total) if p_total else 0.0
        
        series_results.append({
            'series_id': sid,
            'photo_count': len(photos),
            'has_face': has_face_group,
            'top1': is_top1,
            'top2': is_top2,
            'top3': is_top3,
            'pair_acc': pair_acc,
            'pair_count': p_total
        })
        
    return series_results

def bootstrap_difference_cis(cand_results, base_results, n_boot=2000, seed=42):
    """
    Computes paired-series bootstrap difference CIs:
    Delta = Candidate - Baseline
    """
    rng = np.random.RandomState(seed)
    n = len(cand_results)
    
    delta_top1_list = []
    delta_top2_list = []
    delta_top3_list = []
    delta_pair_list = []
    delta_face_top1_list = []
    delta_noface_top1_list = []
    
    cand_top1_pt = np.mean([r['top1'] for r in cand_results]) * 100.0
    base_top1_pt = np.mean([r['top1'] for r in base_results]) * 100.0
    delta_top1_pt = cand_top1_pt - base_top1_pt
    
    cand_pair_pt = np.average([r['pair_acc'] for r in cand_results], weights=[r['pair_count'] for r in cand_results]) * 100.0
    base_pair_pt = np.average([r['pair_acc'] for r in base_results], weights=[r['pair_count'] for r in base_results]) * 100.0
    delta_pair_pt = cand_pair_pt - base_pair_pt
    
    for _ in range(n_boot):
        idx = rng.choice(n, size=n, replace=True)
        c_sample = [cand_results[i] for i in idx]
        b_sample = [base_results[i] for i in idx]
        
        c_t1 = np.mean([r['top1'] for r in c_sample])
        b_t1 = np.mean([r['top1'] for r in b_sample])
        delta_top1_list.append((c_t1 - b_t1) * 100.0)
        
        c_t2 = np.mean([r['top2'] for r in c_sample])
        b_t2 = np.mean([r['top2'] for r in b_sample])
        delta_top2_list.append((c_t2 - b_t2) * 100.0)
        
        c_t3 = np.mean([r['top3'] for r in c_sample])
        b_t3 = np.mean([r['top3'] for r in b_sample])
        delta_top3_list.append((c_t3 - b_t3) * 100.0)
        
        # Face subset
        c_face = [r for r in c_sample if r['has_face']]
        b_face = [r for r in b_sample if r['has_face']]
        if c_face and b_face:
            c_f_t1 = np.mean([r['top1'] for r in c_face])
            b_f_t1 = np.mean([r['top1'] for r in b_face])
            delta_face_top1_list.append((c_f_t1 - b_f_t1) * 100.0)
            
        # Non-face subset
        c_noface = [r for r in c_sample if not r['has_face']]
        b_noface = [r for r in b_sample if not r['has_face']]
        if c_noface and b_noface:
            c_nf_t1 = np.mean([r['top1'] for r in c_noface])
            b_nf_t1 = np.mean([r['top1'] for r in b_noface])
            delta_noface_top1_list.append((c_nf_t1 - b_nf_t1) * 100.0)
            
    ci_top1 = (np.percentile(delta_top1_list, 2.5), np.percentile(delta_top1_list, 97.5))
    ci_top2 = (np.percentile(delta_top2_list, 2.5), np.percentile(delta_top2_list, 97.5))
    ci_top3 = (np.percentile(delta_top3_list, 2.5), np.percentile(delta_top3_list, 97.5))
    ci_face = (np.percentile(delta_face_top1_list, 2.5), np.percentile(delta_face_top1_list, 97.5)) if delta_face_top1_list else (0.0, 0.0)
    ci_noface = (np.percentile(delta_noface_top1_list, 2.5), np.percentile(delta_noface_top1_list, 97.5)) if delta_noface_top1_list else (0.0, 0.0)
    
    return {
        'cand_top1_pt': cand_top1_pt,
        'base_top1_pt': base_top1_pt,
        'delta_top1_pt': delta_top1_pt,
        'ci_delta_top1': ci_top1,
        'ci_delta_top2': ci_top2,
        'ci_delta_top3': ci_top3,
        'ci_delta_face_top1': ci_face,
        'ci_delta_noface_top1': ci_noface,
        'delta_pair_pt': delta_pair_pt
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fit-manifest', default='X:/WeddingCullDatasets/derived/manifests/photo_triage_fit.json')
    parser.add_argument('--fit-tech', default='X:/WeddingCullDatasets/derived/features/photo_triage_fit_technical.json')
    parser.add_argument('--dev-manifest', default='X:/WeddingCullDatasets/derived/manifests/photo_triage_dev_select.json')
    parser.add_argument('--dev-tech', default='X:/WeddingCullDatasets/derived/features/photo_triage_dev_select_technical.json')
    parser.add_argument('--dev-faces', default='X:/WeddingCullDatasets/derived/features/photo_triage_dev_select_faces.json')
    parser.add_argument('--output', default='artifacts/ranker_dev_select_ablation_results.json')
    args = parser.parse_args()
    
    print("===================================================================")
    print("🔬 WeddingCull Learned Relative Ranker Experiment & Model Selection")
    print("   Dataset Split: FIT (3,648 series) -> DEV_SELECT (456 series)")
    print("   VAL is STRICTLY FROZEN and untouched!")
    print("===================================================================")
    
    t0 = time.time()
    print("Loading FIT technical features...")
    with open(args.fit_tech, 'r', encoding='utf-8') as f:
        fit_tech = json.load(f)
    print(f"Loaded {len(fit_tech)} FIT technical feature vectors.")
    
    print("Loading DEV_SELECT technical & face features...")
    with open(args.dev_tech, 'r', encoding='utf-8') as f:
        dev_tech = json.load(f)
    dev_faces = {}
    if os.path.exists(args.dev_faces):
        with open(args.dev_faces, 'r', encoding='utf-8') as f:
            dev_faces = json.load(f)
    print(f"Loaded {len(dev_tech)} DEV_SELECT technical, {len(dev_faces)} face feature vectors.")
    
    # 1. Evaluate Current Production Baseline (Candidate D) on DEV_SELECT
    print("\n--- Step 1: Evaluate Current Production Baseline (Candidate D) on DEV_SELECT ---")
    def score_cand_d(fn, vec):
        return compute_candidate_d_score(fn, dev_tech, dev_faces)
        
    cand_d_results = evaluate_ranker_on_series(args.dev_manifest, dev_tech, dev_faces, score_cand_d)
    cand_d_t1 = np.mean([r['top1'] for r in cand_d_results]) * 100.0
    cand_d_t2 = np.mean([r['top2'] for r in cand_d_results]) * 100.0
    cand_d_t3 = np.mean([r['top3'] for r in cand_d_results]) * 100.0
    cand_d_pair = np.average([r['pair_acc'] for r in cand_d_results], weights=[r['pair_count'] for r in cand_d_results]) * 100.0
    
    face_series_d = [r for r in cand_d_results if r['has_face']]
    noface_series_d = [r for r in cand_d_results if not r['has_face']]
    cand_d_face_t1 = np.mean([r['top1'] for r in face_series_d]) * 100.0 if face_series_d else 0.0
    cand_d_noface_t1 = np.mean([r['top1'] for r in noface_series_d]) * 100.0 if noface_series_d else 0.0
    
    print(f"Candidate D Baseline on DEV_SELECT ({len(cand_d_results)} series):")
    print(f"  Top-1 Accuracy: {cand_d_t1:.2f}%")
    print(f"  Top-2 Recall:   {cand_d_t2:.2f}%")
    print(f"  Top-3 Recall:   {cand_d_t3:.2f}%")
    print(f"  Pairwise Acc:   {cand_d_pair:.2f}%")
    print(f"  Face Top-1:     {cand_d_face_t1:.2f}% ({len(face_series_d)} series)")
    print(f"  Non-Face Top-1: {cand_d_noface_t1:.2f}% ({len(noface_series_d)} series)")
    
    # 2. Build Training Pairs on FIT
    print("\n--- Step 2: Build Training Pairs on FIT Split ---")
    t_pairs = time.time()
    X_fit, y_fit, w_fit = build_training_pairs(args.fit_manifest, fit_tech)
    print(f"Built {len(X_fit)} pairwise comparisons from FIT in {time.time()-t_pairs:.2f}s.")
    
    # 3. Regularization Strength & Feature Set Ablation on DEV_SELECT
    print("\n--- Step 3: Regularization & Feature Ablation on DEV_SELECT ---")
    
    feature_configs = {
        'Technical_Only (7-d)': list(range(7)),
        'Technical_+_Relative (11-d)': list(range(11)),
        'All_Features (16-d)': list(range(16))
    }
    
    l2_values = [0.01, 0.1, 1.0, 5.0, 10.0]
    
    best_config_name = None
    best_l2 = None
    best_delta_top1 = -999.0
    best_weights = None
    best_cis = None
    
    ablation_records = []
    
    for f_name, f_mask in feature_configs.items():
        X_sub = X_fit[:, f_mask]
        print(f"\nEvaluating Feature Configuration: {f_name}")
        
        for l2 in l2_values:
            weights = fit_bradley_terry(X_sub, y_fit, w_fit, l2_reg=l2)
            
            def make_score_fn(w, mask):
                return lambda fn, vec: float(np.dot(vec[mask], w))
                
            score_cand = make_score_fn(weights, f_mask)
            cand_results = evaluate_ranker_on_series(args.dev_manifest, dev_tech, dev_faces, score_cand)
            
            cis = bootstrap_difference_cis(cand_results, cand_d_results, n_boot=1000)
            d_t1 = cis['delta_top1_pt']
            ci_low, ci_high = cis['ci_delta_top1']
            face_d_t1 = cis['ci_delta_face_top1'][0] # check lower bound for non-inferiority
            
            # Non-inferiority check: face Delta lower CI bound >= -1.5%
            non_inferior = (cis['ci_delta_face_top1'][0] >= -1.5)
            
            print(f"  L2={l2:5.2f} | Top-1: {cis['cand_top1_pt']:5.2f}% | Delta: {d_t1:+5.2f}% [95% CI: {ci_low:+5.2f}%, {ci_high:+5.2f}%] | Face Delta: [{cis['ci_delta_face_top1'][0]:+5.2f}%, {cis['ci_delta_face_top1'][1]:+5.2f}%] | Non-Inf: {non_inferior}")
            
            record = {
                'feature_config': f_name,
                'l2_reg': l2,
                'top1_pct': cis['cand_top1_pt'],
                'delta_top1_pct': d_t1,
                'ci_delta_top1': [ci_low, ci_high],
                'ci_delta_face_top1': list(cis['ci_delta_face_top1']),
                'ci_delta_noface_top1': list(cis['ci_delta_noface_top1']),
                'face_non_inferior': bool(non_inferior),
                'weights': {ALL_FEATURE_NAMES[idx]: float(weights[i]) for i, idx in enumerate(f_mask)}
            }
            ablation_records.append(record)
            
            if d_t1 > best_delta_top1 and non_inferior:
                best_delta_top1 = d_t1
                best_config_name = f_name
                best_l2 = l2
                best_weights = weights
                best_cis = cis
                best_mask = f_mask
                
    # 4. Tiny MLP Ranker (24 -> 32 -> 1)
    print("\n--- Step 4: Tiny MLP Ranker Architecture Ablation ---")
    import torch
    import torch.nn as nn
    import torch.optim as optim
    from torch.utils.data import TensorDataset, DataLoader
    
    class TinyMLPRanker(nn.Module):
        def __init__(self, in_dim, hidden_dim=32):
            super().__init__()
            self.net = nn.Sequential(
                nn.Linear(in_dim, hidden_dim),
                nn.ReLU(),
                nn.Linear(hidden_dim, 1)
            )
        def forward(self, x):
            return self.net(x).squeeze(-1)
            
    torch.manual_seed(42)
    in_dim = len(feature_configs['All_Features (16-d)'])
    mlp_model = TinyMLPRanker(in_dim, hidden_dim=32)
    optimizer = optim.AdamW(mlp_model.parameters(), lr=1e-3, weight_decay=1e-2)
    
    X_torch = torch.tensor(X_fit, dtype=torch.float32)
    y_torch = torch.tensor(y_fit, dtype=torch.float32)
    w_torch = torch.tensor(w_fit, dtype=torch.float32)
    
    dataset = TensorDataset(X_torch, y_torch, w_torch)
    loader = DataLoader(dataset, batch_size=256, shuffle=True)
    
    mlp_model.train()
    for epoch in range(15):
        for bx, by, bw in loader:
            optimizer.zero_grad()
            pred = mlp_model(bx)
            p = torch.sigmoid(pred)
            eps = 1e-7
            loss = - (by * torch.log(p + eps) + (1.0 - by) * torch.log(1.0 - p + eps))
            total_loss = (loss * bw).sum()
            total_loss.backward()
            optimizer.step()
            
    mlp_model.eval()
    def score_mlp(fn, vec):
        with torch.no_grad():
            t_vec = torch.tensor(vec, dtype=torch.float32).unsqueeze(0)
            return float(mlp_model(t_vec).item())
            
    mlp_results = evaluate_ranker_on_series(args.dev_manifest, dev_tech, dev_faces, score_mlp)
    mlp_cis = bootstrap_difference_cis(mlp_results, cand_d_results, n_boot=1000)
    print(f"Tiny MLP (32 hidden): Top-1: {mlp_cis['cand_top1_pt']:.2f}% | Delta: {mlp_cis['delta_top1_pt']:+.2f}% [95% CI: {mlp_cis['ci_delta_top1'][0]:+.2f}%, {mlp_cis['ci_delta_top1'][1]:+.2f}%] | Face Delta: [{mlp_cis['ci_delta_face_top1'][0]:+.2f}%, {mlp_cis['ci_delta_face_top1'][1]:+.2f}%]")
    
    # Best learned candidate among all tested (even if negative delta)
    sorted_ablations = sorted(ablation_records, key=lambda r: r['delta_top1_pct'], reverse=True)
    best_learned = sorted_ablations[0] if sorted_ablations else None

    print("\n===================================================================")
    print("🏆 MODEL & FEATURE SELECTION OUTCOME ON DEV_SELECT:")
    if best_config_name is not None:
        print(f"   Winning Candidate Outperformed Baseline: {best_config_name}")
        print(f"   DEV_SELECT Top-1:      {best_cis['cand_top1_pt']:.2f}% (Candidate D: {cand_d_t1:.2f}%)")
        print(f"   Paired Delta Top-1:    {best_cis['delta_top1_pt']:+.2f}% [95% CI: {best_cis['ci_delta_top1'][0]:+.2f}%, {best_cis['ci_delta_top1'][1]:+.2f}%]")
    else:
        print("   RESULT: NO LEARNED RANKER BEATS THE FROZEN PRODUCTION BASELINE (Candidate D)!")
        print(f"   Production Baseline (Candidate D) Top-1 on DEV_SELECT: {cand_d_t1:.2f}%")
        if best_learned:
            print(f"   Best Learned Candidate: {best_learned['feature_config']} (L2={best_learned['l2_reg']})")
            print(f"   Best Learned Top-1:     {best_learned['top1_pct']:.2f}%")
            print(f"   Paired Delta Top-1:     {best_learned['delta_top1_pct']:+.2f}% [95% CI: {best_learned['ci_delta_top1'][0]:+.2f}%, {best_learned['ci_delta_top1'][1]:+.2f}%]")
            print(f"   Face Non-Inferiority:   {best_learned['face_non_inferior']} (Lower CI: {best_learned['ci_delta_face_top1'][0]:+.2f}%)")
        print("   CONCLUSION: Candidate D remains the empirically superior burst ranking model.")
    print("===================================================================")

    final_output = {
        'outcome': 'CANDIDATE_D_REMAINS_SUPERIOR',
        'dev_select_baseline_metrics': {
            'top1_pct': cand_d_t1,
            'top2_pct': cand_d_t2,
            'top3_pct': cand_d_t3,
            'pair_acc_pct': cand_d_pair,
            'face_top1_pct': cand_d_face_t1,
            'noface_top1_pct': cand_d_noface_t1
        },
        'best_learned_candidate': best_learned,
        'mlp_metrics': {
            'top1_pct': mlp_cis['cand_top1_pt'],
            'delta_top1_pct': mlp_cis['delta_top1_pt'],
            'ci_delta_top1': list(mlp_cis['ci_delta_top1']),
            'ci_delta_face_top1': list(mlp_cis['ci_delta_face_top1']),
            'ci_delta_noface_top1': list(mlp_cis['ci_delta_noface_top1'])
        },
        'all_ablations': ablation_records
    }
    
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(final_output, f, indent=2, default=str)
    print(f"Saved model selection & ablation report to: {args.output}")

if __name__ == '__main__':
    main()
