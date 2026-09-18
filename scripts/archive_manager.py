import os
import sys
import hashlib
import json
import shutil
import glob

SOURCE_DIR = "X:/AutoMAT/datasets"
TARGET_ARCHIVES_DIR = "X:/WeddingCullDatasets/archives"
INVENTORY_FILE = os.path.join(TARGET_ARCHIVES_DIR, "archive-inventory.json")

def compute_sha256(filepath, buffer_size=4 * 1024 * 1024):
    hasher = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(buffer_size):
            hasher.update(chunk)
    return hasher.hexdigest()

def main():
    os.makedirs(TARGET_ARCHIVES_DIR, exist_ok=True)
    existing_inventory = {}
    if os.path.exists(INVENTORY_FILE):
        try:
            with open(INVENTORY_FILE, "r") as f:
                existing_inventory = json.load(f)
        except Exception:
            existing_inventory = {}

    archive_patterns = ["*.zip", "*.rar", "*.7z", "*.tar", "*.gz"]
    source_files = []
    for pat in archive_patterns:
        source_files.extend(glob.glob(os.path.join(SOURCE_DIR, pat)))

    inventory = {}
    print(f"Preserving and verifying {len(source_files)} archives from {SOURCE_DIR}...")

    for src in sorted(source_files):
        fname = os.path.basename(src)
        dst = os.path.join(TARGET_ARCHIVES_DIR, fname)
        src_size = os.path.getsize(src)

        # Check if already present and verified
        cached_info = existing_inventory.get(fname, {})
        if os.path.exists(dst) and os.path.getsize(dst) == src_size and cached_info.get("sha256"):
            print(f"[CACHED] {fname} ({src_size / (1024*1024):.2f} MB)")
            inventory[fname] = cached_info
            continue

        print(f"[COPYING] {fname} ({src_size / (1024*1024):.2f} MB)...")
        if not os.path.exists(dst) or os.path.getsize(dst) != src_size:
            shutil.copy2(src, dst)

        print(f"[HASHING] {fname}...")
        sha256_hash = compute_sha256(dst)
        print(f"  SHA-256: {sha256_hash}")

        inventory[fname] = {
            "filename": fname,
            "source_path": src,
            "preserved_path": dst,
            "byte_size": src_size,
            "sha256": sha256_hash,
            "extraction_status": "PENDING"
        }

    with open(INVENTORY_FILE, "w") as f:
        json.dump(inventory, f, indent=2)

    print(f"\nInventory saved to {INVENTORY_FILE} with {len(inventory)} entries.")

if __name__ == "__main__":
    main()
