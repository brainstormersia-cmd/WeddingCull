#!/usr/bin/env python3
"""
scripts/eval_fgaesq_oracle.py

Evaluates FGAesQ (CVPR 2026 Fine-grained Image Aesthetic Assessment)
as an external oracle / teacher model:
1. Photo Triage DEV_SELECT split (456 series, 1187 photos)
2. Real Wedding Shoot wedding_shoot_74ef (92 autonomous bursts, 248 photos)

Measures:
- Top-1, Top-2, Top-3 series ranking accuracy
- Pairwise accuracy against human ground truth
- Stratification: face vs non-face, size breakdown (2, 3, 4-5, 6+)
- Tie-breaking behavior on non-face bursts
- Wall-clock inference latency per image and per burst
- Memory and checkpoint footprint
"""

import os
import sys
import json
import time
import argparse
import numpy as np
import torch
from PIL import Image

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

sys.path.insert(0, os.path.abspath('external/FG-IAA/FGAesQ_Inference'))
try:
    from utils.FGAesQ import FGAesQ
    from utils.DiffToken import DiffToken
except ImportError as e:
    print(f"Error importing FGAesQ modules: {e}")
    sys.exit(1)

def load_fgaesq_model(weights_path, device):
    print(f"Loading FGAesQ from {weights_path} onto {device}...")
    t0 = time.time()
    model = FGAesQ(pretrained_path=None).to(device)
    state_dict = torch.load(weights_path, map_location=device)
    model.load_state_dict(state_dict, strict=False)
    model.eval()
    preprocessor = DiffToken(clip_model=model.clip_model, patch_selection='random')
    t1 = time.time()
    ckpt_size_mb = os.path.getsize(weights_path) / (1024 * 1024)
    print(f"FGAesQ loaded in {t1 - t0:.2f}s. Checkpoint size: {ckpt_size_mb:.1f} MB.")
    return model, preprocessor, ckpt_size_mb

def score_images_batch(model, preprocessor, image_paths, device):
    scores = {}
    latencies = []
    total = len(image_paths)
    for idx, p in enumerate(image_paths):
        t0 = time.time()
        try:
            pil_img = Image.open(p).convert('RGB')
            patches, pos_embed, mask = preprocessor.process_image(pil_img, is_train=False)
            patches = patches.unsqueeze(0).to(device)
            pos_embed = pos_embed.unsqueeze(0).to(device)
            mask = mask.unsqueeze(0).to(device)
            with torch.no_grad():
                out = model(patches, pos_embed, mask)
                score = float(out.item())
            lat = time.time() - t0
            scores[os.path.basename(p)] = score
            latencies.append(lat)
        except Exception as ex:
            print(f"Failed to score {p}: {ex}", flush=True)
            scores[os.path.basename(p)] = -999.0
            
        if (idx + 1) % 100 == 0 or (idx + 1) == total:
            print(f"   Scored {idx + 1}/{total} photos ({(time.time()-t0):.2f}s/img)...", flush=True)
    return scores, latencies

def evaluate_on_dev_select(model, preprocessor, manifest_path, images_dir, device):
    print(f"\n=======================================================")
    print(f"[ORACLE] Evaluating FGAesQ Oracle on DEV_SELECT ({manifest_path})")
    print(f"=======================================================")
    with open(manifest_path, 'r', encoding='utf-8') as f:
        mdata = json.load(f)
        
    series_dict = mdata['series']
    print(f"Loaded {len(series_dict)} series from DEV_SELECT.")
    
    # Collect all photo paths
    all_photo_fns = set()
    for sid, sinfo in series_dict.items():
        for p in sinfo.get('photos', []):
            all_photo_fns.add(p['filename'])
            
    fn_to_path = {}
    for fn in all_photo_fns:
        p = os.path.join(images_dir, fn)
        if os.path.exists(p):
            fn_to_path[fn] = p
            
    print(f"Scoring {len(fn_to_path)} unique photos with FGAesQ...")
    t_start = time.time()
    photo_scores, latencies = score_images_batch(model, preprocessor, list(fn_to_path.values()), device)
    total_scoring_time = time.time() - t_start
    mean_lat_ms = (sum(latencies) / len(latencies)) * 1000.0 if latencies else 0.0
    print(f"Scored {len(photo_scores)} photos in {total_scoring_time:.1f}s (mean {mean_lat_ms:.1f} ms/photo).")
    
    # Evaluate Series Ranking
    top1_correct = 0
    top2_correct = 0
    top3_correct = 0
    total_series = 0
    
    # Stratification counters
    size_metrics = {2: {'top1': 0, 'top2': 0, 'top3': 0, 'total': 0},
                    3: {'top1': 0, 'top2': 0, 'top3': 0, 'total': 0},
                    '4-5': {'top1': 0, 'top2': 0, 'top3': 0, 'total': 0},
                    '6+': {'top1': 0, 'top2': 0, 'top3': 0, 'total': 0}}
                    
    face_metrics = {'top1': 0, 'top2': 0, 'top3': 0, 'total': 0}
    noface_metrics = {'top1': 0, 'top2': 0, 'top3': 0, 'total': 0}
    
    # Pairwise evaluation
    pair_correct = 0
    pair_total = 0
    
    for sid, sinfo in series_dict.items():
        photos = sinfo.get('photos', [])
        if len(photos) < 2:
            continue
            
        ranked_gt = sinfo.get('ranked_photos_preferred_order', [])
        if not ranked_gt:
            # Fallback to sorting by series_rank
            sorted_photos = sorted(photos, key=lambda x: x.get('series_rank', 999))
            ranked_gt = [p['filename'] for p in sorted_photos]
            
        gt_winner = ranked_gt[0]
        
        # Sort by FGAesQ score descending
        pred_ranking = sorted(photos, key=lambda x: photo_scores.get(x['filename'], -999.0), reverse=True)
        pred_ids = [p['filename'] for p in pred_ranking]
        
        n = len(photos)
        total_series += 1
        
        is_top1 = (pred_ids[0] == gt_winner)
        is_top2 = (gt_winner in pred_ids[:2])
        is_top3 = (gt_winner in pred_ids[:3])
        
        if is_top1: top1_correct += 1
        if is_top2: top2_correct += 1
        if is_top3: top3_correct += 1
        
        # Size bucket
        if n == 2: b = 2
        elif n == 3: b = 3
        elif 4 <= n <= 5: b = '4-5'
        else: b = '6+'
        
        size_metrics[b]['total'] += 1
        if is_top1: size_metrics[b]['top1'] += 1
        if is_top2: size_metrics[b]['top2'] += 1
        if is_top3: size_metrics[b]['top3'] += 1
        
        # Face stratum (check reviews for mention of people/face/person/smile)
        has_face_clue = False
        pairs = sinfo.get('pairs', [])
        for pr in pairs:
            revs = pr.get('positive_reasons_a', []) + pr.get('positive_reasons_b', []) + pr.get('negative_reasons_a', []) + pr.get('negative_reasons_b', [])
            txt = ' '.join(revs).lower()
            if any(w in txt for w in ['face', 'smile', 'eye', 'person', 'people', 'man', 'woman', 'girl', 'boy', 'kid', 'child']):
                has_face_clue = True
                break
                
        target_face_bucket = face_metrics if has_face_clue else noface_metrics
        target_face_bucket['total'] += 1
        if is_top1: target_face_bucket['top1'] += 1
        if is_top2: target_face_bucket['top2'] += 1
        if is_top3: target_face_bucket['top3'] += 1
        
        # Pairwise accuracy
        for pr in pairs:
            fa = os.path.basename(pr['path_a'])
            fb = os.path.basename(pr['path_b'])
            maj = pr.get('majority_winner')
            if not maj: continue
            
            sa = photo_scores.get(fa, 0.0)
            sb = photo_scores.get(fb, 0.0)
            pred_pair_winner = fa if sa >= sb else fb
            
            pair_total += 1
            if pred_pair_winner == maj:
                pair_correct += 1
                
    results = {
        'total_series': total_series,
        'top1_accuracy_pct': (top1_correct / total_series) * 100.0 if total_series else 0.0,
        'top2_recall_pct': (top2_correct / total_series) * 100.0 if total_series else 0.0,
        'top3_recall_pct': (top3_correct / total_series) * 100.0 if total_series else 0.0,
        'pairwise_accuracy_pct': (pair_correct / pair_total) * 100.0 if pair_total else 0.0,
        'mean_latency_ms_per_photo': mean_lat_ms,
        'size_stratification': {
            str(k): {
                'count': v['total'],
                'top1_pct': (v['top1'] / v['total'] * 100.0) if v['total'] else 0.0,
                'top2_pct': (v['top2'] / v['total'] * 100.0) if v['total'] else 0.0,
                'top3_pct': (v['top3'] / v['total'] * 100.0) if v['total'] else 0.0,
            } for k, v in size_metrics.items()
        },
        'face_stratification': {
            'face_series': {
                'count': face_metrics['total'],
                'top1_pct': (face_metrics['top1'] / face_metrics['total'] * 100.0) if face_metrics['total'] else 0.0,
            },
            'non_face_series': {
                'count': noface_metrics['total'],
                'top1_pct': (noface_metrics['top1'] / noface_metrics['total'] * 100.0) if noface_metrics['total'] else 0.0,
            }
        }
    }
    
    print("\n--- DEV_SELECT Evaluation Results ---")
    print(f"Top-1 Accuracy: {results['top1_accuracy_pct']:.2f}% ({top1_correct}/{total_series})")
    print(f"Top-2 Recall:   {results['top2_recall_pct']:.2f}%")
    print(f"Top-3 Recall:   {results['top3_recall_pct']:.2f}%")
    print(f"Pairwise Acc:   {results['pairwise_accuracy_pct']:.2f}% ({pair_correct}/{pair_total})")
    print(f"Size Breakdown: Size 2: {results['size_stratification']['2']['top1_pct']:.1f}%, Size 3: {results['size_stratification']['3']['top1_pct']:.1f}%, Size 4-5: {results['size_stratification']['4-5']['top1_pct']:.1f}% (Top-3: {results['size_stratification']['4-5']['top3_pct']:.1f}%)")
    print(f"Face vs Non-Face Top-1: Face: {results['face_stratification']['face_series']['top1_pct']:.1f}% ({face_metrics['total']} series) | Non-Face: {results['face_stratification']['non_face_series']['top1_pct']:.1f}% ({noface_metrics['total']} series)")
    
    return results, photo_scores

def evaluate_on_real_wedding(model, preprocessor, report_path, wedding_images_dir, device):
    print(f"\n=======================================================")
    print(f"[ORACLE] Evaluating FGAesQ Oracle on Real Wedding Shoot 74ef")
    print(f"=======================================================")
    with open(report_path, 'r', encoding='utf-8') as f:
        rep = json.load(f)
        
    all_bursts = rep.get('allBursts', [])
    print(f"Loaded {len(all_bursts)} autonomous bursts from {report_path}.")
    
    # Collect all photos in bursts
    burst_photos = set()
    for b in all_bursts:
        for mid in b['memberIds']:
            burst_photos.add(mid)
            
    fn_to_path = {}
    for fn in burst_photos:
        p = os.path.join(wedding_images_dir, fn)
        if os.path.exists(p):
            fn_to_path[fn] = p
            
    print(f"Scoring {len(fn_to_path)} burst photos with FGAesQ...")
    t0 = time.time()
    photo_scores, latencies = score_images_batch(model, preprocessor, list(fn_to_path.values()), device)
    t_tot = time.time() - t0
    mean_lat_ms = (sum(latencies) / len(latencies)) * 1000.0 if latencies else 0.0
    print(f"Scored {len(photo_scores)} photos in {t_tot:.1f}s (mean {mean_lat_ms:.1f} ms/photo).")
    
    # Analyze tie breaking and agreement with Candidate D
    winner_agreements = 0
    decisive_separations = 0
    non_face_bursts_count = 0
    non_face_decisive_count = 0
    
    score_diffs = []
    cand_d_diffs = []
    
    burst_evals = []
    
    for b in all_bursts:
        mids = b['memberIds']
        has_faces = b['hasFaces']
        cand_d_winner = b['winnerId']
        cand_d_diff = b.get('scoreDifference', 0.0)
        
        # Sort by FGAesQ score
        fgaesq_ranked = sorted(mids, key=lambda mid: photo_scores.get(mid, -999.0), reverse=True)
        fgaesq_winner = fgaesq_ranked[0]
        fgaesq_runner_up = fgaesq_ranked[1] if len(fgaesq_ranked) > 1 else None
        
        w_score = photo_scores.get(fgaesq_winner, 0.0)
        ru_score = photo_scores.get(fgaesq_runner_up, 0.0) if fgaesq_runner_up else w_score
        fgaesq_diff = w_score - ru_score
        
        score_diffs.append(fgaesq_diff)
        if cand_d_diff is not None:
            cand_d_diffs.append(cand_d_diff)
            
        agree = (fgaesq_winner == cand_d_winner)
        if agree: winner_agreements += 1
        
        # In FGAesQ, scores are on 1-10 scale (mean ~4-5, std ~0.8)
        # Normalized gap: delta / std_dev. An absolute gap > 0.15 is significant
        is_decisive = (fgaesq_diff >= 0.15)
        if is_decisive: decisive_separations += 1
        
        if not has_faces:
            non_face_bursts_count += 1
            if is_decisive:
                non_face_decisive_count += 1
                
        burst_evals.append({
            'burstId': b['burstId'],
            'memberCount': len(mids),
            'hasFaces': has_faces,
            'cand_d_winner': cand_d_winner,
            'fgaesq_winner': fgaesq_winner,
            'agreement': agree,
            'fgaesq_score_difference': fgaesq_diff,
            'cand_d_score_difference': cand_d_diff,
            'is_decisive': is_decisive
        })
        
    results = {
        'total_bursts': len(all_bursts),
        'winner_agreement_with_cand_d_pct': (winner_agreements / len(all_bursts)) * 100.0,
        'mean_score_difference': float(np.mean(score_diffs)),
        'median_score_difference': float(np.median(score_diffs)),
        'cand_d_mean_score_diff': float(np.mean(cand_d_diffs)) if cand_d_diffs else 0.0,
        'overall_decisive_separation_pct': (decisive_separations / len(all_bursts)) * 100.0,
        'non_face_bursts_count': non_face_bursts_count,
        'non_face_decisive_separation_count': non_face_decisive_count,
        'non_face_decisive_separation_pct': (non_face_decisive_count / non_face_bursts_count * 100.0) if non_face_bursts_count else 0.0,
        'mean_latency_ms_per_photo': mean_lat_ms
    }
    
    print("\n--- Real Wedding Shoot Burst Analysis ---")
    print(f"Agreement with Candidate D Winner: {results['winner_agreement_with_cand_d_pct']:.1f}% ({winner_agreements}/{len(all_bursts)})")
    print(f"Mean FGAesQ Score Gap: {results['mean_score_difference']:.4f} (Candidate D mean gap: {results['cand_d_mean_score_diff']:.4f})")
    print(f"Non-Face Bursts Tie-Breaking: {results['non_face_decisive_separation_pct']:.1f}% ({non_face_decisive_count}/{non_face_bursts_count} non-face bursts show decisive separation > 0.15)")
    
    return results, burst_evals

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--weights', default='models/fgaesq/FGAesQ.pt')
    parser.add_argument('--dev-manifest', default='X:/WeddingCullDatasets/derived/manifests/photo_triage_dev_select.json')
    parser.add_argument('--trainval-images', default='X:/WeddingCullDatasets/raw/PhotoTriage/train_val/train_val_imgs')
    parser.add_argument('--wedding-report', default='artifacts/real_wedding_benchmark_report.json')
    parser.add_argument('--wedding-images', default='X:/WeddingCullDatasets/transfer/WeddingShoot74ef')
    parser.add_argument('--output', default='artifacts/fgaesq_oracle_dev_select_and_wedding_results.json')
    args = parser.parse_args()
    
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    model, preprocessor, ckpt_size = load_fgaesq_model(args.weights, device)
    
    dev_results, dev_scores = evaluate_on_dev_select(model, preprocessor, args.dev_manifest, args.trainval_images, device)
    wed_results, wed_bursts = evaluate_on_real_wedding(model, preprocessor, args.wedding_report, args.wedding_images, device)
    
    full_output = {
        'model_name': 'FGAesQ (CVPR 2026)',
        'checkpoint_size_mb': ckpt_size,
        'device': str(device),
        'execution_timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'dev_select_results': dev_results,
        'wedding_shoot_74ef_results': wed_results,
        'wedding_burst_evaluations': wed_bursts[:20] # sample
    }
    
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(full_output, f, indent=2)
    print(f"\nSaved complete FGAesQ Oracle evaluation results to: {args.output}")

if __name__ == '__main__':
    main()
