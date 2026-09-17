#!/usr/bin/env bash
set -eo pipefail

echo "===================================================="
echo "📦 Fetching AlbumBench / CUFED Wedding Subset"
echo "===================================================="

MANIFEST_FILE="docs/datasets/albumbench-wedding-subset.json"
TARGET_DIR="tests/fixtures/datasets/albumbench_wedding"
ALBUM_LIMIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      MANIFEST_FILE="$2"
      shift 2
      ;;
    --target-dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --limit)
      ALBUM_LIMIT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "❌ Manifest file not found: $MANIFEST_FILE"
  exit 1
fi

mkdir -p "$TARGET_DIR"

PYTHON_CMD="python3"
if ! command -v python3 &>/dev/null; then
  if command -v python &>/dev/null; then
    PYTHON_CMD="python"
  else
    echo "❌ Neither python3 nor python found."
    exit 1
  fi
fi

echo "Using Python: $($PYTHON_CMD --version)"
echo "Target directory: $TARGET_DIR"
echo "Manifest: $MANIFEST_FILE"

$PYTHON_CMD - <<EOF
import json
import os
import sys
import urllib.request
import time

manifest_path = "$MANIFEST_FILE"
target_dir = "$TARGET_DIR"
limit = int("$ALBUM_LIMIT")

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

albums = manifest.get("albums", [])
if limit > 0:
    albums = albums[:limit]

total_albums = len(albums)
total_images = sum(len(a.get("images", [])) for a in albums)
print(f"Fetching {total_albums} albums ({total_images} images)...")

downloaded_count = 0
skipped_count = 0
failed_count = 0

for idx, album in enumerate(albums, 1):
    aid = album["album_id"]
    album_dir = os.path.join(target_dir, aid)
    os.makedirs(album_dir, exist_ok=True)
    
    # Save album metadata
    meta_path = os.path.join(album_dir, "metadata.json")
    with open(meta_path, "w", encoding="utf-8") as mf:
        json.dump(album, mf, indent=2)
        
    images = album.get("images", [])
    print(f"[{idx}/{total_albums}] Album {aid}: {len(images)} images")
    
    for img in images:
        path = img["path"]
        url = img["download_url"]
        filename = os.path.basename(path)
        dest_path = os.path.join(album_dir, filename)
        
        if os.path.exists(dest_path) and os.path.getsize(dest_path) > 1000:
            skipped_count += 1
            continue
            
        # Download image with retry
        success = False
        for attempt in range(3):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; WeddingCull/1.0)"})
                with urllib.request.urlopen(req, timeout=15) as resp:
                    if resp.status == 200:
                        content = resp.read()
                        with open(dest_path, "wb") as out_f:
                            out_f.write(content)
                        success = True
                        downloaded_count += 1
                        break
            except Exception as e:
                time.sleep(1.0)
                
        if not success:
            print(f"⚠️ Failed to download {url}")
            failed_count += 1

print("====================================================")
print(f"AlbumBench fetch summary:")
print(f"  Downloaded: {downloaded_count}")
print(f"  Cached/Skipped: {skipped_count}")
print(f"  Failed: {failed_count}")
print(f"  Albums ready: {total_albums}")
print("====================================================")

if failed_count > 0 and downloaded_count + skipped_count == 0:
    print("❌ Fatal: No images could be downloaded.")
    sys.exit(1)
EOF

echo "✅ AlbumBench dataset fetch complete."
