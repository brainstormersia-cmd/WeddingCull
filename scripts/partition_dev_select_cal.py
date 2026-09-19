import os
import sys
import json
import hashlib

DEV_MANIFEST = "X:/WeddingCullDatasets/derived/manifests/photo_triage_dev.json"
OUTPUT_DIR = "X:/WeddingCullDatasets/derived/manifests"

def deterministic_series_hash(series_id, seed="phototriage_dev_subsplit_v1"):
    """Stable SHA-256 hash of series ID for deterministic partitioning."""
    return hashlib.sha256(f"{seed}_{series_id}".encode("utf-8")).hexdigest()

def main():
    print("=== Partitioning DEV into DEV_SELECT and DEV_CAL ===")
    with open(DEV_MANIFEST, "r", encoding="utf-8") as f:
        dev_data = json.load(f)

    dev_series = dev_data["series"]
    total_dev = len(dev_series)
    print(f"Total DEV series: {total_dev}")
    assert total_dev == 912, f"Expected 912 series in DEV, got {total_dev}"

    # Sort series deterministically by SHA-256 hash
    hashed_series = []
    for sid_str, s_data in dev_series.items():
        sid = int(sid_str)
        h = deterministic_series_hash(sid)
        hashed_series.append((h, sid_str, s_data))

    hashed_series.sort(key=lambda x: x[0])

    # Exactly 50/50 split: 456 to DEV_SELECT, 456 to DEV_CAL
    select_items = hashed_series[:456]
    cal_items = hashed_series[456:]

    assert len(select_items) == 456
    assert len(cal_items) == 456

    select_sids = set(x[1] for x in select_items)
    cal_sids = set(x[1] for x in cal_items)
    assert select_sids.isdisjoint(cal_sids), "DEV_SELECT and DEV_CAL must be strictly disjoint!"

    dev_select_series = {sid: data for _, sid, data in select_items}
    dev_cal_series = {sid: data for _, sid, data in cal_items}

    # Count pairs and photos
    select_pairs = sum(len(s.get("pairs", [])) for s in dev_select_series.values())
    cal_pairs = sum(len(s.get("pairs", [])) for s in dev_cal_series.values())

    select_photos = sum(len(s.get("photos", [])) for s in dev_select_series.values())
    cal_photos = sum(len(s.get("photos", [])) for s in dev_cal_series.values())

    print(f"DEV_SELECT: {len(dev_select_series)} series, {select_pairs} pairs, {select_photos} photos")
    print(f"DEV_CAL:    {len(dev_cal_series)} series, {cal_pairs} pairs, {cal_photos} photos")

    dev_select_manifest = {
        "split_name": "DEV_SELECT",
        "description": "Photo Triage Model/Feature/Hyperparameter Selection Split (50% of DEV, deterministic series-level SHA-256 partition)",
        "partition_procedure": "SHA-256(phototriage_dev_subsplit_v1_{series_id}), first 456 series sorted by hash",
        "total_series": len(dev_select_series),
        "total_pairs": select_pairs,
        "total_photos": select_photos,
        "series_ids": sorted(list(select_sids), key=lambda x: int(x)),
        "series": dev_select_series
    }

    dev_cal_manifest = {
        "split_name": "DEV_CAL",
        "description": "Photo Triage Calibration & Risk/Coverage Threshold Selection Split (50% of DEV, deterministic series-level SHA-256 partition)",
        "partition_procedure": "SHA-256(phototriage_dev_subsplit_v1_{series_id}), second 456 series sorted by hash",
        "total_series": len(dev_cal_series),
        "total_pairs": cal_pairs,
        "total_photos": cal_photos,
        "series_ids": sorted(list(cal_sids), key=lambda x: int(x)),
        "series": dev_cal_series
    }

    select_path = os.path.join(OUTPUT_DIR, "photo_triage_dev_select.json")
    cal_path = os.path.join(OUTPUT_DIR, "photo_triage_dev_cal.json")

    with open(select_path, "w", encoding="utf-8") as f:
        json.dump(dev_select_manifest, f, indent=2)
    print(f"Saved DEV_SELECT manifest to {select_path}")

    with open(cal_path, "w", encoding="utf-8") as f:
        json.dump(dev_cal_manifest, f, indent=2)
    print(f"Saved DEV_CAL manifest to {cal_path}")

if __name__ == "__main__":
    main()
