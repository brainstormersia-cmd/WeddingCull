#!/usr/bin/env python3
"""
scripts/extract_split_features.py

Extracts technical quality metrics with exact mathematical parity to Swift's
TechnicalQualityAnalyzer and QualityScorer:
- rawSharpness (Laplacian variance on inner pixels of 800px max edge preview)
- meanLuminance (0-1)
- shadowClipping (fraction of pixels < 15)
- highlightClipping (fraction of pixels > 240)
- dynamicRange (p98 - p2) / 255.0
- contrast stdDev / 64.0
- exposureScore (exact Swift piecewise formula)
- burst-relative normalized sharpness & exposure
"""

import os
import sys
import json
import time
import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
import cv2
import numpy as np

def analyze_image_technical(image_path, max_edge=800):
    img_bgr = cv2.imread(image_path)
    if img_bgr is None:
        return None
    h, w = img_bgr.shape[:2]
    if max(h, w) > max_edge:
        scale = max_edge / max(h, w)
        new_w, new_h = int(w * scale), int(h * scale)
        img_bgr = cv2.resize(img_bgr, (new_w, new_h), interpolation=cv2.INTER_AREA)
        h, w = new_h, new_w
        
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    total_pixels = float(h * w)
    
    # Exposure & clipping
    sum_lum = float(np.sum(gray))
    mean_lum = (sum_lum / total_pixels) / 255.0
    shadow_clip = float(np.sum(gray < 15)) / total_pixels
    highlight_clip = float(np.sum(gray > 240)) / total_pixels
    
    # Percentiles
    p2 = float(np.percentile(gray, 2))
    p98 = float(np.percentile(gray, 98))
    dyn_range = max(0.0, min(1.0, (p98 - p2) / 255.0))
    
    # Contrast
    std = float(np.std(gray))
    contrast = max(0.0, min(1.0, std / 64.0))
    
    # Exact Swift QualityScorer exposure formula
    lum_penalty = abs(mean_lum - 0.5) * 2.0 * 0.4
    clip_penalty = (shadow_clip + highlight_clip) * 1.5 * 0.6
    exp_score = max(0.05, 1.0 - (lum_penalty + clip_penalty))
    
    # Laplacian variance on inner region [1:-1, 1:-1]
    kernel = np.array([[0, 1, 0], [1, -4, 1], [0, 1, 0]], dtype=np.float32)
    lap = cv2.filter2D(gray.astype(np.float32), -1, kernel)
    inner = lap[1:-1, 1:-1]
    raw_sharpness = float(np.var(inner))
    
    return {
        'photo_id': os.path.basename(image_path),
        'image_path': image_path,
        'rawSharpness': raw_sharpness,
        'meanLuminance': mean_lum,
        'shadowClipping': shadow_clip,
        'highlightClipping': highlight_clip,
        'dynamicRange': dyn_range,
        'contrast': contrast,
        'exposureScore': exp_score
    }

def process_batch(paths):
    results = {}
    for p in paths:
        res = analyze_image_technical(p)
        if res:
            results[res['photo_id']] = res
    return results

def extract_for_manifest(manifest_path, images_dir, output_path, max_workers=6):
    print(f"Loading manifest: {manifest_path}")
    with open(manifest_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    all_photos = set()
    for sid, sinfo in data['series'].items():
        for p in sinfo.get('photos', []):
            fn = p.get('filename')
            if fn:
                all_photos.add(fn)
                
    photo_list = sorted(list(all_photos))
    print(f"Found {len(photo_list)} unique photos in manifest across {len(data['series'])} series.")
    
    full_paths = []
    for fn in photo_list:
        p = os.path.join(images_dir, fn)
        if os.path.exists(p):
            full_paths.append(p)
        else:
            print(f"Warning: {fn} not found in {images_dir}")
            
    print(f"Found {len(full_paths)} existing photo files on disk. Starting parallel extraction ({max_workers} workers)...")
    t0 = time.time()
    
    batch_size = 50
    batches = [full_paths[i:i + batch_size] for i in range(0, len(full_paths), batch_size)]
    
    extracted_features = {}
    with ProcessPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process_batch, b): b for b in batches}
        done_count = 0
        for fut in as_completed(futures):
            res = fut.result()
            extracted_features.update(res)
            done_count += len(res)
            if done_count % 250 == 0 or done_count == len(full_paths):
                print(f"   Extracted {done_count}/{len(full_paths)} photos ({(time.time()-t0):.1f}s elapsed)...")
                
    t1 = time.time()
    print(f"Extraction completed: {len(extracted_features)} photos in {t1-t0:.2f}s ({(t1-t0)/max(1, len(extracted_features))*1000:.1f} ms/photo)")
    
    # Save to JSON
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(extracted_features, f, indent=2)
    print(f"Saved extracted features to: {output_path}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--images-dir', default=r'X:\WeddingCullDatasets\raw\PhotoTriage\train_val\train_val_imgs')
    parser.add_argument('--output', required=True)
    parser.add_argument('--workers', type=int, default=6)
    args = parser.parse_args()
    
    extract_for_manifest(args.manifest, args.images_dir, args.output, args.workers)

if __name__ == '__main__':
    main()
