import os
import sys
import json
import shutil
import zipfile

VAL_MANIFEST = "X:/WeddingCullDatasets/derived/manifests/photo_triage_val.json"
PT_RAW_ROOT = "X:/WeddingCullDatasets/raw/PhotoTriage"
TRANSFER_DIR = "X:/WeddingCullDatasets/transfer/PhotoTriageValidation"
ZIP_OUTPUT = "X:/WeddingCullDatasets/transfer/PhotoTriageValidation.zip"

def main():
    print("=== Building Photo Triage Validation Transfer Bundle ===")
    os.makedirs(TRANSFER_DIR, exist_ok=True)
    images_dest = os.path.join(TRANSFER_DIR, "images")
    reviews_dest = os.path.join(TRANSFER_DIR, "reviews")
    os.makedirs(images_dest, exist_ok=True)
    os.makedirs(reviews_dest, exist_ok=True)

    with open(VAL_MANIFEST, "r", encoding="utf-8") as f:
        val_data = json.load(f)

    series_dict = val_data["series"]
    print(f"Validation series count: {len(series_dict)}")

    all_images = set()
    all_series_ids = []

    for sid_str, s in series_dict.items():
        sid = int(sid_str)
        all_series_ids.append(sid)
        for p in s.get("photos", []):
            fname = p["filename"] if isinstance(p, dict) else p
            all_images.add(fname)

    print(f"Total unique validation images: {len(all_images)}")

    # 1. Copy images
    src_img_dir = os.path.join(PT_RAW_ROOT, "train_val", "train_val_imgs")
    copied_images = 0
    missing_images = 0

    for img_name in sorted(all_images):
        src = os.path.join(src_img_dir, img_name)
        dst = os.path.join(images_dest, img_name)
        if os.path.exists(src):
            if not os.path.exists(dst) or os.path.getsize(src) != os.path.getsize(dst):
                shutil.copy2(src, dst)
            copied_images += 1
        else:
            print(f"WARNING: Image not found: {src}")
            missing_images += 1

    print(f"Copied {copied_images} images to {images_dest} (missing: {missing_images})")
    assert missing_images == 0, f"Cannot build bundle with {missing_images} missing images!"

    # 2. Copy reviews
    src_rev_dir = os.path.join(PT_RAW_ROOT, "train_val", "reviews_trainval", "reviews_trainval")
    copied_reviews = 0
    for sid in all_series_ids:
        rev_name = f"{sid:06d}.json"
        src = os.path.join(src_rev_dir, rev_name)
        dst = os.path.join(reviews_dest, rev_name)
        if os.path.exists(src):
            shutil.copy2(src, dst)
            copied_reviews += 1

    print(f"Copied {copied_reviews} review JSONs to {reviews_dest}")

    # 3. Copy pairlist
    src_pairlist = os.path.join(PT_RAW_ROOT, "train_val", "val_pairlist.txt")
    dst_pairlist = os.path.join(TRANSFER_DIR, "val_pairlist.txt")
    shutil.copy2(src_pairlist, dst_pairlist)
    print(f"Copied val_pairlist.txt to {dst_pairlist}")

    # 4. Generate local bundle manifest
    bundle_manifest = {
        "dataset_name": "Photo Triage Validation (Transfer Bundle)",
        "series_count": len(series_dict),
        "total_images": len(all_images),
        "images_directory": "images",
        "reviews_directory": "reviews",
        "pairlist_file": "val_pairlist.txt"
    }
    with open(os.path.join(TRANSFER_DIR, "bundle_info.json"), "w", encoding="utf-8") as f:
        json.dump(bundle_manifest, f, indent=2)

    # 5. Write README.md with macOS command
    readme_content = """# Photo Triage Validation Bundle for macOS Authentic Extraction

This directory contains the complete, self-contained 195-series validation partition of Princeton Adobe Photo Triage (~688 images).

## Authentic macOS Feature Extraction Command

To execute authentic image decoding, Apple Vision face analysis, FaceCaptureQuality, face-crop Laplacian sharpness, and exposure metrics on macOS:

```bash
# Set Git SHA environment variable
export WEDDINGCULL_GIT_SHA=$(git rev-parse HEAD)

# Run authentic feature exporter
swift run WeddingCullFeatureExporter \
    --dataset . \
    --output photo_triage_val_features_authentic.jsonl
```

Transfer the resulting `photo_triage_val_features_authentic.jsonl` back to:
`X:/WeddingCullDatasets/derived/features/photo_triage_val_features_authentic.jsonl`
"""
    with open(os.path.join(TRANSFER_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write(readme_content)

    # 6. Create ZIP archive
    print(f"Creating ZIP archive at {ZIP_OUTPUT}...")
    with zipfile.ZipFile(ZIP_OUTPUT, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(TRANSFER_DIR):
            for file in files:
                full_p = os.path.join(root, file)
                rel_p = os.path.relpath(full_p, TRANSFER_DIR)
                zipf.write(full_p, arcname=os.path.join("PhotoTriageValidation", rel_p))

    zip_size_mb = os.path.getsize(ZIP_OUTPUT) / (1024 * 1024)
    print(f"Successfully generated {ZIP_OUTPUT} ({zip_size_mb:.2f} MB)")

if __name__ == "__main__":
    main()
