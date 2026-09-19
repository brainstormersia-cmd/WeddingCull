#!/usr/bin/env python3
"""
scripts/extract_mobileclip2_features.py

Extracts MobileCLIP2-S0 embeddings (512-d) and concept similarities:
- 12 Wedding concepts from WeddingConceptsEmbeddings.json
- 4 Photographic quality contrast prompts
- Raw normalized 512-d embeddings for PCA ablation

Supports processing any manifest split (e.g. DEV_SELECT, DEV_CAL, FIT).
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

import open_clip

# Photographic quality text prompts
QUALITY_PROMPTS = [
    "a sharp crisp high quality in-focus photograph",
    "a blurry out-of-focus motion-blurred low quality photograph",
    "a well-exposed photograph with natural lighting and rich contrast",
    "a poorly exposed underexposed or overexposed photograph"
]

def load_concept_text_features(concepts_path, model, tokenizer, device):
    concept_vectors = {}
    if os.path.exists(concepts_path):
        try:
            with open(concepts_path, 'r', encoding='utf-8') as f:
                cdata = json.load(f)
            # Recompute text embeddings with MobileCLIP2 tokenizer to ensure matching space
            cats = cdata.get('categories', {})
            print(f"Loaded {len(cats)} wedding concept categories.")
            # For each category, create text prompts
            for cat_name in cats.keys():
                # Formulate a natural prompt
                cat_prompt = f"a wedding photo of {cat_name}"
                tok = tokenizer([cat_prompt]).to(device)
                with torch.no_grad():
                    txt_feat = model.encode_text(tok)
                    txt_feat /= txt_feat.norm(dim=-1, keepdim=True)
                concept_vectors[cat_name] = txt_feat.squeeze(0).cpu().numpy()
        except Exception as e:
            print(f"Warning loading wedding concepts: {e}")
            
    # Quality prompts
    q_tokens = tokenizer(QUALITY_PROMPTS).to(device)
    with torch.no_grad():
        q_feats = model.encode_text(q_tokens)
        q_feats /= q_feats.norm(dim=-1, keepdim=True)
    q_matrix = q_feats.cpu().numpy() # [4, 512]
    
    return concept_vectors, q_matrix

def extract_mobileclip2_features(manifest_path, images_dir, output_path, concepts_path, batch_size=32):
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Loading MobileCLIP2-S0 on {device}...")
    t0 = time.time()
    model, _, preprocess = open_clip.create_model_and_transforms('MobileCLIP2-S0', pretrained='dfndr2b')
    tokenizer = open_clip.get_tokenizer('MobileCLIP2-S0')
    model = model.to(device).eval()
    print(f"MobileCLIP2-S0 loaded in {time.time()-t0:.2f}s.")
    
    concept_vecs, q_matrix = load_concept_text_features(concepts_path, model, tokenizer, device)
    concept_names = sorted(list(concept_vecs.keys()))
    if concept_names:
        c_matrix = np.stack([concept_vecs[c] for c in concept_names], axis=0) # [C, 512]
    else:
        c_matrix = None
        
    print(f"Loading manifest: {manifest_path}")
    with open(manifest_path, 'r', encoding='utf-8') as f:
        mdata = json.load(f)
        
    photos = set()
    for sid, sinfo in mdata['series'].items():
        for p in sinfo.get('photos', []):
            fn = p.get('filename')
            if fn: photos.add(fn)
            
    photo_list = sorted(list(photos))
    print(f"Found {len(photo_list)} unique photos.")
    
    existing_paths = []
    existing_fns = []
    for fn in photo_list:
        p = os.path.join(images_dir, fn)
        if os.path.exists(p):
            existing_paths.append(p)
            existing_fns.append(fn)
            
    print(f"Found {len(existing_paths)} photos on disk. Extracting MobileCLIP2 embeddings (batch size {batch_size})...")
    
    results = {}
    t_start = time.time()
    n_batches = (len(existing_paths) + batch_size - 1) // batch_size
    
    for b_idx in range(n_batches):
        start_i = b_idx * batch_size
        end_i = min(len(existing_paths), start_i + batch_size)
        batch_paths = existing_paths[start_i:end_i]
        batch_fns = existing_fns[start_i:end_i]
        
        batch_tensors = []
        valid_fns = []
        for fn, p in zip(batch_fns, batch_paths):
            try:
                img = Image.open(p).convert('RGB')
                tensor = preprocess(img)
                batch_tensors.append(tensor)
                valid_fns.append(fn)
            except Exception as e:
                print(f"Error loading {p}: {e}")
                
        if not batch_tensors:
            continue
            
        inp = torch.stack(batch_tensors).to(device)
        with torch.no_grad():
            img_feats = model.encode_image(inp)
            img_feats /= img_feats.norm(dim=-1, keepdim=True)
            emb_np = img_feats.cpu().numpy() # [B, 512]
            
        # Quality cosine similarities
        q_sims = np.dot(emb_np, q_matrix.T) # [B, 4]
        # Concept cosine similarities
        c_sims = np.dot(emb_np, c_matrix.T) if c_matrix is not None else None # [B, C]
        
        for i, fn in enumerate(valid_fns):
            q_sharp = float(q_sims[i, 0])
            q_blur = float(q_sims[i, 1])
            q_good_exp = float(q_sims[i, 2])
            q_bad_exp = float(q_sims[i, 3])
            net_sharp = q_sharp - q_blur
            net_exp = q_good_exp - q_bad_exp
            
            entry = {
                'photo_id': fn,
                'embedding_512': emb_np[i].tolist(),
                'net_quality_sharpness': net_sharp,
                'net_quality_exposure': net_exp,
                'raw_prompt_sims': {
                    'sharp': q_sharp,
                    'blur': q_blur,
                    'good_exp': q_good_exp,
                    'bad_exp': q_bad_exp
                }
            }
            if c_sims is not None:
                entry['wedding_concept_sims'] = {
                    c_name: float(c_sims[i, c_idx])
                    for c_idx, c_name in enumerate(concept_names)
                }
            results[fn] = entry
            
        if (b_idx + 1) % 5 == 0 or (b_idx + 1) == n_batches:
            elapsed = time.time() - t_start
            done = min(len(existing_paths), (b_idx + 1) * batch_size)
            print(f"   Processed {done}/{len(existing_paths)} photos ({elapsed:.1f}s elapsed, {elapsed/done*1000:.1f} ms/photo)...")
            
    total_time = time.time() - t_start
    print(f"MobileCLIP2 feature extraction completed: {len(results)} photos in {total_time:.2f}s ({total_time/len(results)*1000:.1f} ms/photo)")
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f)
    print(f"Saved MobileCLIP2 features to: {output_path}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--images-dir', default=r'X:\WeddingCullDatasets\raw\PhotoTriage\train_val\train_val_imgs')
    parser.add_argument('--concepts', default='Sources/ML/Resources/WeddingConceptsEmbeddings.json')
    parser.add_argument('--output', required=True)
    parser.add_argument('--batch-size', type=int, default=32)
    args = parser.parse_args()
    
    extract_mobileclip2_features(args.manifest, args.images_dir, args.output, args.concepts, args.batch_size)

if __name__ == '__main__':
    main()
