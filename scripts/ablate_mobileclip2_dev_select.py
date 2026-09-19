#!/usr/bin/env python3
"""
scripts/ablate_mobileclip2_dev_select.py

Ablation study on DEV_SELECT evaluating:
1. Technical Quality Baseline
2. Technical + MobileCLIP2 Net Quality (sharpness/exposure semantic contrast)
3. Technical + MobileCLIP2 Wedding Category Similarities
4. MobileCLIP2 Standalone Semantic Ranking

Strict holdout hygiene: Zero evaluation on VAL!
"""

import os
import sys
import json
import math
import numpy as np

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

def main():
    print("===================================================================")
    print("🔬 MobileCLIP2-S0 Feature Ablation Study on DEV_SELECT")
    print("===================================================================")
    
    with open('X:/WeddingCullDatasets/derived/manifests/photo_triage_dev_select.json', 'r', encoding='utf-8') as f:
        mdata = json.load(f)
    with open('X:/WeddingCullDatasets/derived/features/photo_triage_dev_select_technical.json', 'r', encoding='utf-8') as f:
        tech_feats = json.load(f)
    with open('X:/WeddingCullDatasets/derived/features/photo_triage_dev_select_mobileclip2.json', 'r', encoding='utf-8') as f:
        clip_feats = json.load(f)
        
    series_dict = mdata['series']
    total_series = len(series_dict)
    print(f"Loaded {total_series} series from DEV_SELECT.")
    
    # Define score functions
    def score_clip_standalone(fn):
        cf = clip_feats.get(fn, {})
        # Net semantic quality: sharp - blur + good_exp - bad_exp
        return cf.get('net_quality_sharpness', 0.0) + 0.5 * cf.get('net_quality_exposure', 0.0)
        
    def score_tech_plus_clip(fn):
        tf = tech_feats.get(fn, {})
        cf = clip_feats.get(fn, {})
        raw_s = tf.get('rawSharpness', 0.0)
        norm_s = max(0.0, min(1.0, math.log1p(raw_s) / math.log1p(2000.0)))
        exp_score = tf.get('exposureScore', 0.5)
        clip_q = cf.get('net_quality_sharpness', 0.0)
        return 0.60 * norm_s + 0.25 * exp_score + 0.15 * clip_q
        
    def score_tech_baseline(fn):
        tf = tech_feats.get(fn, {})
        raw_s = tf.get('rawSharpness', 0.0)
        norm_s = max(0.0, min(1.0, math.log1p(raw_s) / math.log1p(2000.0)))
        exp_score = tf.get('exposureScore', 0.5)
        return 0.70 * norm_s + 0.30 * exp_score
        
    score_configs = {
        'Technical Quality Baseline': score_tech_baseline,
        'MobileCLIP2 Standalone Semantic': score_clip_standalone,
        'Technical + MobileCLIP2 Net Quality': score_tech_plus_clip
    }
    
    results = {}
    for name, sfn in score_configs.items():
        t1_corr = 0
        t2_corr = 0
        t3_corr = 0
        p_corr = 0
        p_tot = 0
        
        for sid, sinfo in series_dict.items():
            photos = [p['filename'] for p in sinfo.get('photos', [])]
            if len(photos) < 2: continue
            
            ranked_gt = sinfo.get('ranked_photos_preferred_order', [])
            if not ranked_gt:
                sorted_photos = sorted(sinfo.get('photos', []), key=lambda x: x.get('series_rank', 999))
                ranked_gt = [p['filename'] for p in sorted_photos]
            gt_winner = ranked_gt[0]
            
            ranked_preds = sorted(photos, key=lambda fn: (-sfn(fn), fn))
            if ranked_preds[0] == gt_winner: t1_corr += 1
            if gt_winner in ranked_preds[:2]: t2_corr += 1
            if gt_winner in ranked_preds[:3]: t3_corr += 1
            
            for pr in sinfo.get('pairs', []):
                fa = os.path.basename(pr['path_a'])
                fb = os.path.basename(pr['path_b'])
                maj = pr.get('majority_winner')
                if not maj: continue
                p_tot += 1
                if (fa if sfn(fa) >= sfn(fb) else fb) == maj:
                    p_corr += 1
                    
        res = {
            'top1_pct': (t1_corr / total_series) * 100.0,
            'top2_pct': (t2_corr / total_series) * 100.0,
            'top3_pct': (t3_corr / total_series) * 100.0,
            'pairwise_acc_pct': (p_corr / p_tot) * 100.0 if p_tot else 0.0
        }
        results[name] = res
        print(f"Configuration: {name:<36} | Top-1: {res['top1_pct']:5.2f}% | Top-2: {res['top2_pct']:5.2f}% | Top-3: {res['top3_pct']:5.2f}% | Pairwise: {res['pairwise_acc_pct']:5.2f}%")
        
    out_path = 'artifacts/mobileclip2_dev_select_ablation_results.json'
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved MobileCLIP2 ablation results to: {out_path}")

if __name__ == '__main__':
    main()
