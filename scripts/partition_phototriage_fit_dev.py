import os
import sys
import json
import hashlib

TRAIN_MANIFEST = "X:/WeddingCullDatasets/derived/manifests/photo_triage_train.json"
VAL_MANIFEST = "X:/WeddingCullDatasets/derived/manifests/photo_triage_val.json"
OUTPUT_DIR = "X:/WeddingCullDatasets/derived/manifests"

def deterministic_series_hash(series_id):
    """Stable SHA-256 hash of series ID for deterministic partitioning."""
    return hashlib.sha256(f"phototriage_series_{series_id}".encode("utf-8")).hexdigest()

def main():
    print("Loading train and val manifests...")
    with open(TRAIN_MANIFEST, "r", encoding="utf-8") as f:
        train_data = json.load(f)
    with open(VAL_MANIFEST, "r", encoding="utf-8") as f:
        val_data = json.load(f)

    train_series_dict = train_data["series"]
    val_series_dict = val_data["series"]

    total_train = len(train_series_dict)
    total_val = len(val_series_dict)
    print(f"Total train series: {total_train}")
    print(f"Total val series: {total_val}")

    assert total_train == 4560, f"Expected 4560 train series, got {total_train}"
    assert total_val == 195, f"Expected 195 val series, got {total_val}"

    val_series_ids = set(int(sid) for sid in val_series_dict.keys())

    # 1. Hash each series_id deterministically
    hashed_series = []
    for sid_str, s_data in train_series_dict.items():
        sid = int(sid_str)
        assert sid not in val_series_ids, f"Series {sid} found in both TRAIN and VAL!"
        h = deterministic_series_hash(sid)
        hashed_series.append((h, sid, s_data))

    # 2. Sort by stable hash
    hashed_series.sort(key=lambda x: x[0])

    # 3. Assign first 3,648 to FIT, remaining 912 to DEV
    fit_count = 3648
    dev_count = 912
    assert fit_count + dev_count == total_train, "FIT + DEV count must equal total train"

    fit_items = hashed_series[:fit_count]
    dev_items = hashed_series[fit_count:]

    assert len(fit_items) == 3648, f"Expected 3648 in FIT, got {len(fit_items)}"
    assert len(dev_items) == 912, f"Expected 912 in DEV, got {len(dev_items)}"

    fit_series_ids = set(item[1] for item in fit_items)
    dev_series_ids = set(item[1] for item in dev_items)

    # 4. Mandatory Disjoint Partition Assertions
    assert fit_series_ids.isdisjoint(dev_series_ids), "FIT and DEV must be disjoint!"
    assert fit_series_ids.isdisjoint(val_series_ids), "FIT and VAL must be disjoint!"
    assert dev_series_ids.isdisjoint(val_series_ids), "DEV and VAL must be disjoint!"
    print("Assertions PASSED: FIT intersect DEV = empty, FIT intersect VAL = empty, DEV intersect VAL = empty")

    fit_series_dict = {str(sid): data for _, sid, data in fit_items}
    dev_series_dict = {str(sid): data for _, sid, data in dev_items}

    # Count pairs
    fit_pairs = sum(len(s.get("pairs", [])) for s in fit_series_dict.values())
    dev_pairs = sum(len(s.get("pairs", [])) for s in dev_series_dict.values())

    fit_manifest = {
        "split_name": "FIT",
        "description": "Photo Triage Model Fitting Split (80% of official train, partitioned by deterministic series hash)",
        "total_series": len(fit_series_dict),
        "total_pairs": fit_pairs,
        "series": fit_series_dict
    }

    dev_manifest = {
        "split_name": "DEV",
        "description": "Photo Triage Development & Model Selection Split (20% of official train, partitioned by deterministic series hash)",
        "total_series": len(dev_series_dict),
        "total_pairs": dev_pairs,
        "series": dev_series_dict
    }

    fit_out_path = os.path.join(OUTPUT_DIR, "photo_triage_fit.json")
    dev_out_path = os.path.join(OUTPUT_DIR, "photo_triage_dev.json")

    with open(fit_out_path, "w", encoding="utf-8") as f:
        json.dump(fit_manifest, f, indent=2)
    print(f"Saved FIT manifest ({len(fit_series_dict)} series, {fit_pairs} pairs) to {fit_out_path}")

    with open(dev_out_path, "w", encoding="utf-8") as f:
        json.dump(dev_manifest, f, indent=2)
    print(f"Saved DEV manifest ({len(dev_series_dict)} series, {dev_pairs} pairs) to {dev_out_path}")

if __name__ == "__main__":
    main()
