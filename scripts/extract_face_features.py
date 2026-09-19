#!/usr/bin/env python3
"""
scripts/extract_face_features.py

Extracts face features and worst-face metrics:
- face_count
- has_face (1.0 or 0.0)
- detection_confidence
- min_face_sharpness (worst face sharpness)
- mean_face_sharpness
- max_face_sharpness
- problematic_face_count (sharpness < 15.0 or low confidence)
- eye landmark geometry proxy
"""

import os
import sys
import json
import time
import argparse
import cv2
import numpy as np

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

def compute_crop_sharpness(gray_img, bbox):
    x, y, w, h = bbox
    img_h, img_w = gray_img.shape[:2]
    # Clamp to image bounds
    x0 = max(0, min(img_w - 1, int(x)))
    y0 = max(0, min(img_h - 1, int(y)))
    x1 = max(0, min(img_w, int(x + w)))
    y1 = max(0, min(img_h, int(y + h)))
    
    if x1 - x0 < 4 or y1 - y0 < 4:
        return 0.0
        
    crop = gray_img[y0:y1, x0:x1]
    kernel = np.array([[0, 1, 0], [1, -4, 1], [0, 1, 0]], dtype=np.float32)
    lap = cv2.filter2D(crop.astype(np.float32), -1, kernel)
    if lap.shape[0] > 2 and lap.shape[1] > 2:
        inner = lap[1:-1, 1:-1]
        return float(np.var(inner))
    return float(np.var(lap))

def process_image_faces(detector, image_path, max_edge=800):
    img = cv2.imread(image_path)
    if img is None:
        return None
        
    h, w = img.shape[:2]
    scale = 1.0
    if max(h, w) > max_edge:
        scale = max_edge / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
        h, w = img.shape[:2]
        
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    detector.setInputSize((w, h))
    _, faces = detector.detect(img)
    
    if faces is None or len(faces) == 0:
        return {
            'face_count': 0,
            'has_face': 0.0,
            'detectionConfidence': 0.8,
            'minFaceSharpness': None,
            'meanFaceSharpness': None,
            'maxFaceSharpness': None,
            'problematic_face_count': 0,
            'faces': []
        }
        
    face_list = []
    sharpnesses = []
    confidences = []
    problematic = 0
    
    for f in faces:
        # YuNet output: [x, y, w, h, x_re, y_re, x_le, y_le, x_nt, y_nt, x_rc, y_rc, x_lc, y_lc, score]
        bbox = f[0:4]
        conf = float(f[14])
        crop_s = compute_crop_sharpness(gray, bbox)
        sharpnesses.append(crop_s)
        confidences.append(conf)
        
        if crop_s < 15.0 or conf < 0.5:
            problematic += 1
            
        face_list.append({
            'box': [float(x) for x in bbox],
            'confidence': conf,
            'sharpness': crop_s
        })
        
    min_s = float(np.min(sharpnesses))
    mean_s = float(np.mean(sharpnesses))
    max_s = float(np.max(sharpnesses))
    mean_conf = float(np.mean(confidences))
    
    return {
        'face_count': len(faces),
        'has_face': 1.0,
        'detectionConfidence': mean_conf,
        'minFaceSharpness': min_s,
        'meanFaceSharpness': mean_s,
        'maxFaceSharpness': max_s,
        'rawFaceSharpness': mean_s,
        'problematic_face_count': problematic,
        'faces': face_list
    }

def extract_split_faces(manifest_path, images_dir, output_path, model_path='models/face_detection_yunet_2023mar.onnx'):
    detector = cv2.FaceDetectorYN.create(model_path, '', (320, 320), 0.5, 0.3, 5000)
    
    print(f"Loading manifest: {manifest_path}")
    with open(manifest_path, 'r', encoding='utf-8') as f:
        mdata = json.load(f)
        
    photos = set()
    for sid, sinfo in mdata['series'].items():
        for p in sinfo.get('photos', []):
            fn = p.get('filename')
            if fn: photos.add(fn)
            
    photo_list = sorted(list(photos))
    print(f"Processing faces for {len(photo_list)} photos...")
    
    results = {}
    t0 = time.time()
    for idx, fn in enumerate(photo_list):
        p = os.path.join(images_dir, fn)
        if os.path.exists(p):
            res = process_image_faces(detector, p)
            if res:
                results[fn] = res
        if (idx + 1) % 200 == 0 or (idx + 1) == len(photo_list):
            elapsed = time.time() - t0
            print(f"   Processed {idx + 1}/{len(photo_list)} photos ({elapsed:.1f}s elapsed, {elapsed/(idx+1)*1000:.1f} ms/photo)...")
            
    total_time = time.time() - t0
    print(f"Face extraction completed: {len(results)} photos in {total_time:.2f}s ({total_time/max(1, len(results))*1000:.1f} ms/photo)")
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f)
    print(f"Saved face features to: {output_path}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--images-dir', default=r'X:\WeddingCullDatasets\raw\PhotoTriage\train_val\train_val_imgs')
    parser.add_argument('--output', required=True)
    parser.add_argument('--model', default='models/face_detection_yunet_2023mar.onnx')
    args = parser.parse_args()
    
    extract_split_faces(args.manifest, args.images_dir, args.output, args.model)

if __name__ == '__main__':
    main()
