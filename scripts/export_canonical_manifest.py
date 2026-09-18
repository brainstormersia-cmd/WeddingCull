import os
import json

VAL_MANIFEST = "X:/WeddingCullDatasets/derived/manifests/photo_triage_val.json"
TARGET_CANONICAL = "X:/WeddingCullDatasets/raw/PhotoTriage/manifest.json"

def main():
    with open(VAL_MANIFEST, "r", encoding="utf-8") as f:
        val_data = json.load(f)

    canonical_series = []
    total_frames = 0

    for sid_str, s in sorted(val_data["series"].items(), key=lambda x: int(x[0])):
        sid = int(sid_str)
        series_id = f"{sid:06d}"
        
        frames = []
        for p in s["photos"]:
            fname = p["filename"]
            rel_path = f"train_val/train_val_imgs/{fname}"
            frames.append({
                "photo_id": fname,
                "image_path": rel_path
            })
        total_frames += len(frames)

        pairwise = []
        for p in s["pairs"]:
            all_reasons = p["positive_reasons_a"] + p["negative_reasons_b"] + p["positive_reasons_b"] + p["negative_reasons_a"]
            pairwise.append({
                "photo_a": p["photo_a"],
                "photo_b": p["photo_b"],
                "votes_a": p["votes_a"],
                "votes_b": p["votes_b"],
                "reasons": all_reasons if all_reasons else None
            })

        pref_order = s["ranked_photos_preferred_order"]

        canonical_series.append({
            "series_id": series_id,
            "scene_type": "photo_triage",
            "description": f"Photo Triage Series {sid}",
            "frames": frames,
            "ground_truth": {
                "preferred_order": pref_order,
                "acceptable_keepers": [pref_order[0]] if pref_order else [],
                "unacceptable_rejects": [],
                "pairwise_comparisons": pairwise,
                "reasons": {}
            }
        })

    canonical_dataset = {
        "version": "2.0",
        "dataset_name": "Princeton_Adobe_Photo_Triage_Val",
        "description": "Princeton Adobe Photo Triage Validation Set (195 series, 483 pairs)",
        "total_series": len(canonical_series),
        "total_frames": total_frames,
        "series": canonical_series
    }

    with open(TARGET_CANONICAL, "w", encoding="utf-8") as f:
        json.dump(canonical_dataset, f, indent=2)

    print(f"Exported canonical manifest to {TARGET_CANONICAL} with {len(canonical_series)} series and {total_frames} frames.")

if __name__ == "__main__":
    main()
