#!/usr/bin/env python3
import os
import sys
import zipfile
import json
from PIL import Image, ExifTags
from datetime import datetime

WEDDING_DIR = "datasets/wedding"
EXTRACTED_DIR = os.path.join(WEDDING_DIR, "extracted")
os.makedirs(EXTRACTED_DIR, exist_ok=True)

DATASETS = [
    {
        "name": "wedding_shoot_74ef",
        "zips": [
            "2026091974ef32c0a53fff40729b96b7be721cbeb806e85a3dda180da9a665e532a408f7.zip",
            "2026091974ef32c0a53fff40729b96b7be721cbeb806e85a3dda180da9a665e532a408f7_2.zip",
            "2026091974ef32c0a53fff40729b96b7be721cbeb806e85a3dda180da9a665e532a408f7_3.zip"
        ]
    },
    {
        "name": "wedding_shoot_84ec",
        "zips": [
            "2026091984ec1743cf1be588f92c0607b01409d7afff60c20f8c50886ec94c21d9c76496.zip"
        ]
    },
    {
        "name": "wedding_shoot_fac0",
        "zips": [
            "20260919fac05504d27a82a6f5fb198c33ee6ab35ff3eceb0491aa5fda423493712eb71f.zip"
        ]
    }
]

def extract_all():
    for ds in DATASETS:
        target_folder = os.path.join(EXTRACTED_DIR, ds["name"])
        os.makedirs(target_folder, exist_ok=True)
        print(f"\n=== Extracting {ds['name']} to {target_folder} ===")
        for zname in ds["zips"]:
            zpath = os.path.join(WEDDING_DIR, zname)
            print(f"  Extracting {zname}...")
            with zipfile.ZipFile(zpath, "r") as z:
                z.extractall(target_folder)
        file_count = len([f for f in os.listdir(target_folder) if not os.path.isdir(os.path.join(target_folder, f))])
        print(f"  Done. Total files extracted: {file_count}")

def parse_exif(img_path):
    info = {
        "datetime": None,
        "make": None,
        "model": None,
        "iso": None,
        "focal_length": None,
        "exposure_time": None,
        "f_number": None,
        "width": None,
        "height": None
    }
    try:
        with Image.open(img_path) as im:
            info["width"], info["height"] = im.size
            raw_exif = im._getexif()
            if raw_exif:
                exif = {ExifTags.TAGS.get(k, k): v for k, v in raw_exif.items()}
                dt_str = exif.get("DateTimeOriginal") or exif.get("DateTime")
                if dt_str:
                    try:
                        info["datetime"] = datetime.strptime(str(dt_str), "%Y:%m:%d %H:%M:%S")
                    except Exception:
                        info["datetime"] = None
                info["make"] = str(exif.get("Make", "")).strip() or None
                info["model"] = str(exif.get("Model", "")).strip() or None
                info["iso"] = exif.get("ISOSpeedRatings")
                info["focal_length"] = exif.get("FocalLength")
                info["exposure_time"] = exif.get("ExposureTime")
                info["f_number"] = exif.get("FNumber")
    except Exception as e:
        info["error"] = str(e)
    return info

def audit_datasets():
    audit_results = {}
    for ds in DATASETS:
        ds_name = ds["name"]
        target_folder = os.path.join(EXTRACTED_DIR, ds_name)
        print(f"\n=== Auditing {ds_name} ===")
        files = sorted([f for f in os.listdir(target_folder) if f.lower().endswith(('.jpg', '.jpeg', '.png', '.cr2', '.cr3', '.nef', '.arw'))])
        print(f"Total image files: {len(files)}")
        
        records = []
        for f in files:
            p = os.path.join(target_folder, f)
            ex = parse_exif(p)
            ex["filename"] = f
            records.append(ex)

        timestamps = [r["datetime"] for r in records if r["datetime"] is not None]
        models = set(r["model"] for r in records if r["model"])
        makes = set(r["make"] for r in records if r["make"])
        resolutions = set(f"{r['width']}x{r['height']}" for r in records if r['width'])

        dt_sorted = sorted([r for r in records if r["datetime"] is not None], key=lambda x: x["datetime"])
        
        intervals = []
        burst_candidates = 0
        for i in range(1, len(dt_sorted)):
            delta = (dt_sorted[i]["datetime"] - dt_sorted[i-1]["datetime"]).total_seconds()
            intervals.append(delta)
            if delta <= 2.0:
                burst_candidates += 1

        first_time = dt_sorted[0]["datetime"].strftime("%Y-%m-%d %H:%M:%S") if dt_sorted else "N/A"
        last_time = dt_sorted[-1]["datetime"].strftime("%Y-%m-%d %H:%M:%S") if dt_sorted else "N/A"
        total_duration_hours = ((dt_sorted[-1]["datetime"] - dt_sorted[0]["datetime"]).total_seconds() / 3600.0) if len(dt_sorted) >= 2 else 0.0

        audit_results[ds_name] = {
            "total_images": len(files),
            "valid_exif_count": len(dt_sorted),
            "camera_makes": list(makes),
            "camera_models": list(models),
            "resolutions": list(resolutions),
            "first_shot": first_time,
            "last_shot": last_time,
            "duration_hours": round(total_duration_hours, 2),
            "shots_under_2s_interval": burst_candidates,
            "sample_filenames": files[:8]
        }
        print(f"  Makes: {makes}")
        print(f"  Models: {models}")
        print(f"  Resolutions: {resolutions}")
        print(f"  Time span: {first_time} -> {last_time} ({total_duration_hours:.2f} hours)")
        print(f"  Shots <= 2.0s apart: {burst_candidates} / {len(dt_sorted)}")

    out_path = os.path.join(EXTRACTED_DIR, "audit_summary.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(audit_results, f, indent=2)
    print(f"\nAudit summary saved to {out_path}")

if __name__ == "__main__":
    extract_all()
    audit_datasets()
