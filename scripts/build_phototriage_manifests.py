import os
import sys
import glob
import json
import collections
import scipy.io

RAW_DIR = "X:/WeddingCullDatasets/raw/PhotoTriage"
DERIVED_DIR = "X:/WeddingCullDatasets/derived"
SPLITS_DIR = os.path.join(DERIVED_DIR, "splits")
MANIFESTS_DIR = os.path.join(DERIVED_DIR, "manifests")

os.makedirs(SPLITS_DIR, exist_ok=True)
os.makedirs(MANIFESTS_DIR, exist_ok=True)

def load_mat_ranks(mat_path):
    ranks_by_series = {}
    if not os.path.exists(mat_path):
        return ranks_by_series
    mat = scipy.io.loadmat(mat_path)
    series_arr = mat.get("train_val_series")
    if series_arr is None:
        return ranks_by_series
    
    # Iterate through all 4,755 series
    for i in range(series_arr.shape[1]):
        elem = series_arr[0, i]
        sid = int(elem['SERIES_ID'][0, 0][0, 0])
        size = int(elem['SERIES_SIZE'][0, 0][0, 0])
        # RANK is array of 1-based ranks corresponding to photo 1, 2, ...
        rank_arr = elem['RANK'][0, 0].flatten()
        bt_arr = elem['Bradley_Terry'][0, 0].flatten()
        ranks_by_series[sid] = {
            "size": size,
            "ranks": [int(r) for r in rank_arr],
            "bradley_terry": [float(b) for b in bt_arr]
        }
    return ranks_by_series

def build_split(split_name, pairlist_path, imgs_dir, reviews_dir, mat_ranks):
    print(f"\nBuilding canonical manifest for {split_name}...")
    if not os.path.exists(pairlist_path):
        print(f"Error: {pairlist_path} not found.")
        return None

    # 1. Read pairlist
    pairs_raw = []
    series_ids = set()
    with open(pairlist_path, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if not parts: continue
            sid = int(parts[0])
            p1 = int(parts[1])
            p2 = int(parts[2])
            pt_ratio = float(parts[3]) if len(parts) > 3 else None
            r1 = int(parts[4]) if len(parts) > 4 else None
            r2 = int(parts[5]) if len(parts) > 5 else None
            pairs_raw.append({
                "series_id": sid,
                "p1": p1,
                "p2": p2,
                "pairlist_bt_ratio": pt_ratio,
                "pairlist_r1": r1,
                "pairlist_r2": r2
            })
            series_ids.add(sid)

    print(f"  Found {len(series_ids)} series, {len(pairs_raw)} pairlist records.")

    # 2. For each series, load reviews JSON
    series_manifests = {}
    pair_manifests = []
    
    agreement_distribution = collections.Counter()

    for sid in sorted(series_ids):
        rev_file = os.path.join(reviews_dir, f"{sid:06d}.json")
        reviews = []
        if os.path.exists(rev_file):
            try:
                with open(rev_file, "r", encoding="utf-8") as jf:
                    reviews = json.load(jf).get("reviews", [])
            except Exception as e:
                print(f"  Error reading {rev_file}: {e}")

        # Tally pairwise votes and reasons
        # Map: (pA_ind, pB_ind) -> { votesA, votesB, posReasonsA, negReasonsA, posReasonsB, negReasonsB, reviews }
        pairwise_votes = collections.defaultdict(lambda: {
            "votes_a": 0,
            "votes_b": 0,
            "pos_reasons_a": [],
            "neg_reasons_a": [],
            "pos_reasons_b": [],
            "neg_reasons_b": [],
            "reviews": []
        })

        all_photo_indices = set()

        for r in reviews:
            # compareFile format: "{sid}-{ind}.JPG"
            f1 = r["compareFile1"]
            f2 = r["compareFile2"]
            c = r["userChoice"]
            reasons = r.get("reason", ["", ""])

            try:
                ind1 = int(f1.split("-")[1].split(".")[0])
                ind2 = int(f2.split("-")[1].split(".")[0])
            except Exception:
                continue

            all_photo_indices.add(ind1)
            all_photo_indices.add(ind2)

            # Standardize key so ind_a < ind_b
            if ind1 < ind2:
                key = (ind1, ind2)
                chose_a = (c == "LEFT")
                rec = pairwise_votes[key]
                rec["reviews"].append(r)
                if chose_a:
                    rec["votes_a"] += 1
                    if len(reasons) > 0 and reasons[0].strip():
                        rec["pos_reasons_a"].append(reasons[0].strip())
                    if len(reasons) > 1 and reasons[1].strip():
                        rec["neg_reasons_b"].append(reasons[1].strip())
                else:
                    rec["votes_b"] += 1
                    if len(reasons) > 0 and reasons[0].strip():
                        rec["pos_reasons_b"].append(reasons[0].strip())
                    if len(reasons) > 1 and reasons[1].strip():
                        rec["neg_reasons_a"].append(reasons[1].strip())
            else:
                key = (ind2, ind1)
                chose_b = (c == "LEFT")
                rec = pairwise_votes[key]
                rec["reviews"].append(r)
                if chose_b:
                    rec["votes_b"] += 1
                    if len(reasons) > 0 and reasons[0].strip():
                        rec["pos_reasons_b"].append(reasons[0].strip())
                    if len(reasons) > 1 and reasons[1].strip():
                        rec["neg_reasons_a"].append(reasons[1].strip())
                else:
                    rec["votes_a"] += 1
                    if len(reasons) > 0 and reasons[0].strip():
                        rec["pos_reasons_a"].append(reasons[0].strip())
                    if len(reasons) > 1 and reasons[1].strip():
                        rec["neg_reasons_b"].append(reasons[1].strip())

        # Build series photo list and preferred order from mat_ranks
        mat_info = mat_ranks.get(sid, {})
        rank_list = mat_info.get("ranks", [])
        bt_list = mat_info.get("bradley_terry", [])
        mat_size = mat_info.get("size", 0)
        
        # In Photo Triage, photo indices are 1, 2, ...
        all_indices = set(range(1, mat_size + 1)).union(all_photo_indices)
        sorted_indices = sorted(all_indices)
        photo_records = []
        for idx in sorted_indices:
            fname = f"{sid:06d}-{idx:02d}.JPG"
            fpath = os.path.join(imgs_dir, fname)
            rnk = rank_list[idx - 1] if (idx - 1 < len(rank_list)) else None
            bt = bt_list[idx - 1] if (idx - 1 < len(bt_list)) else None
            photo_records.append({
                "photo_index": idx,
                "filename": fname,
                "path": fpath,
                "exists_on_disk": os.path.exists(fpath),
                "series_rank": rnk,
                "bradley_terry": bt
            })

        # Rank-ordered photos (1st place, 2nd place, ...)
        ranked_photos = [p["filename"] for p in sorted(photo_records, key=lambda x: (x["series_rank"] if x["series_rank"] is not None else 999))]
        preferred_winner = ranked_photos[0] if ranked_photos else None

        # Build series pairs
        series_pairs = []
        for (ind_a, ind_b), rec in sorted(pairwise_votes.items()):
            fname_a = f"{sid:06d}-{ind_a:02d}.JPG"
            fname_b = f"{sid:06d}-{ind_b:02d}.JPG"
            path_a = os.path.join(imgs_dir, fname_a)
            path_b = os.path.join(imgs_dir, fname_b)

            v_a = rec["votes_a"]
            v_b = rec["votes_b"]
            tot = v_a + v_b
            p_a = v_a / tot if tot > 0 else 0.5
            agreement = max(v_a, v_b) / tot if tot > 0 else 0.5
            is_ambig = (agreement < 0.70) or (v_a == v_b)

            if agreement >= 0.90:
                stratum = "DECISIVE_CONSENSUS"
            elif agreement >= 0.80:
                stratum = "STRONG_CONSENSUS"
            elif agreement >= 0.70:
                stratum = "MODERATE_CONSENSUS"
            else:
                stratum = "AMBIGUOUS_OR_SPLIT"

            agreement_distribution[stratum] += 1

            maj_winner = fname_a if v_a > v_b else (fname_b if v_b > v_a else "TIE")

            pair_entry = {
                "series_id": sid,
                "photo_a": fname_a,
                "photo_b": fname_b,
                "path_a": path_a,
                "path_b": path_b,
                "votes_a": v_a,
                "votes_b": v_b,
                "total_votes": tot,
                "pHuman_a": p_a,
                "majority_winner": maj_winner,
                "annotator_agreement": agreement,
                "is_ambiguous": is_ambig,
                "agreement_stratum": stratum,
                "positive_reasons_a": rec["pos_reasons_a"],
                "negative_reasons_a": rec["neg_reasons_a"],
                "positive_reasons_b": rec["pos_reasons_b"],
                "negative_reasons_b": rec["neg_reasons_b"],
                "raw_reviews": rec["reviews"]
            }
            series_pairs.append(pair_entry)
            pair_manifests.append(pair_entry)

        series_manifests[sid] = {
            "series_id": sid,
            "photo_count": len(photo_records),
            "photos": photo_records,
            "ranked_photos_preferred_order": ranked_photos,
            "preferred_winner_photo": preferred_winner,
            "pairs_count": len(series_pairs),
            "pairs": series_pairs,
            "is_complete_and_evaluable": all(p["exists_on_disk"] for p in photo_records) and len(photo_records) >= 2
        }

    out_manifest = {
        "split_name": split_name,
        "total_series": len(series_manifests),
        "complete_series": sum(1 for s in series_manifests.values() if s["is_complete_and_evaluable"]),
        "total_pairs": len(pair_manifests),
        "agreement_distribution": dict(agreement_distribution),
        "series": series_manifests
    }

    out_file = os.path.join(MANIFESTS_DIR, f"photo_triage_{split_name}.json")
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(out_manifest, f, indent=2)
    print(f"  Saved {split_name} manifest with {len(series_manifests)} series and {len(pair_manifests)} pairs to {out_file}")

    return out_manifest

def main():
    mat_path = os.path.join(RAW_DIR, "train_val", "train_val_series.mat")
    mat_ranks = load_mat_ranks(mat_path)
    print(f"Loaded Bradley-Terry ranks for {len(mat_ranks)} series from MAT file.")

    train_val_imgs = os.path.join(RAW_DIR, "train_val", "train_val_imgs")
    reviews_dir = os.path.join(RAW_DIR, "train_val", "reviews_trainval", "reviews_trainval")

    # 1. Validation Split Manifest (PRIMARY BENCHMARK)
    val_pairlist = os.path.join(RAW_DIR, "train_val", "val_pairlist.txt")
    val_data = build_split("val", val_pairlist, train_val_imgs, reviews_dir, mat_ranks)

    # 2. Train Split Manifest (FOR FUTURE TRAINING)
    train_pairlist = os.path.join(RAW_DIR, "train_val", "train_pairlist.txt")
    train_data = build_split("train", train_pairlist, train_val_imgs, reviews_dir, mat_ranks)

    print("\nCanonical manifests built successfully.")

if __name__ == "__main__":
    main()
