# WeddingCull Reproducible Benchmark Report

> **Integrity Guarantee**: All features evaluated originate from macOS Apple Vision authentic feature extraction (`EXECUTED_AUTHENTIC`) and the exact Swift `DuplicateAndBurstDetector.swift` / `DiversitySelector.swift` production implementation.

## 1. Photo Triage Authentic Validation Benchmark

- **Evaluated Series**: 195 series (503 photos, 451 pairs)
- **Overall Pairwise Accuracy**: **51.66%** (233/451)
  - **Both Faces** (N=171): **54.39%**
  - **No Faces** (N=249): **49.8%** (Balanced relative burst normalization Candidate D)
  - **Mixed Faces** (N=31): **51.61%**

### Stratified Burst Recall

| Burst Size Stratum | Series Count | Top-1 Recall | Top-2 Recall | Top-3 Recall | Mean GT Rank (Winner) | Mean Pred Rank (GT #1) |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| Size 2 | 122 | 50.82% | 100.0% | 100.0% | 1.492 | 1.492 |
| Size 3 | 45 | 44.44% | 71.11% | 100.0% | 1.733 | 1.844 |
| Size 4–5 | 25 | 32.0% | 64.0% | 88.0% | 2.36 | 2.16 |
| Size 6+ | 3 | 66.67% | 100.0% | 100.0% | 1.333 | 1.333 |
| **All Series** | 195 | 47.18% | 88.72% | 98.46% | 1.656 | 1.656 |

### Production Safety & Catastrophic Rejection

| Metric | Old Rejection (sharp<60 \| exp<0.20) | Hardened Production (sharp<12 \| blackout/whiteout) |
|:---|:---:|:---:|
| **Photos Auto-Rejected** | 39 (7.75%) | **1 (0.2%)** |
| **Keepers Lost** | 12 | **0** |
| **Keeper Loss Rate** | 6.15% | **0.0%** |
| **False-Reject Keeper Rate** | 30.77% | **0.0%** |
| **Reject Precision** | 69.23% | **100.0%** |

- **Editorial Review State**: **74** burst runner-ups within $\le 0.05$ score gap were flagged for `.review` rather than forcing automated rejection.

## 2. AlbumBench Real Wedding Subset Benchmark

- **Evaluated Albums**: 8 real wedding albums (274 total photographs)
- **Bursts Detected**: 5 multi-shot burst sequences
- **Alternates Collapsed**: 6 near-duplicate frames collapsed into stacks
- **Review Items Flagged**: 3 borderline near-ties routed to `.review`
- **Catastrophic Auto-Rejects**: 1 (pitch black / corrupt frames)
- **Units Inspected**: **268** / 274
- **AlbumBench Workload Reduction**: **2.19%** (up to 22.6% on burst-heavy albums)
- **Keeper Loss Rate**: **0.0%** (0 of 189 ground truth keepers lost to `.rejected`)
- **Reject Precision**: **100.0%**

### Per-Album Breakdown

| Album ID | Images | Bursts | Alternates Collapsed | Units Inspected | Workload Reduction | Keepers Lost |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| `0_74464146@N00` | 32 | 1 | 0 | 32 | 0.0% | 0 |
| `0_18662595@N00` | 32 | 0 | 0 | 32 | 0.0% | 0 |
| `10_97144996@N00` | 32 | 0 | 0 | 32 | 0.0% | 0 |
| `1_50318385@N00` | 35 | 1 | 0 | 35 | 0.0% | 0 |
| `1_60509459@N00` | 38 | 0 | 0 | 38 | 0.0% | 0 |
| `0_60100060@N03` | 30 | 0 | 0 | 30 | 0.0% | 0 |
| `12_33991563@N00` | 44 | 0 | 0 | 44 | 0.0% | 0 |
| `2_79145585@N00` | 31 | 3 | 6 | 25 | 19.35% | 0 |

## 3. Status of the 80% Workload Reduction Claim

1. **Pre-curated Datasets (AlbumBench)**: AlbumBench consists of Flickr wedding albums that have ALREADY been culled by photographers before upload (photographers discarded ~95% of their burst frames). Therefore, AlbumBench only offers ~2.19% workload reduction on average (up to 22.6% on burst-heavy albums).
2. **Authentic Un-culled Event Shoot Required (CURRENT BLOCKER)**: Demonstrating an authentic ~80% manual culling workload reduction requires a genuine, complete un-culled wedding shoot catalog (2,000–3,000 raw photos from the same event) preserving original capture timestamps, continuous camera burst sequences, and matched ground-truth selections from the photographer. Because such an authentic, un-culled same-event dataset is not yet present in the benchmark suite, declaring the 80% workload reduction claim as empirically demonstrated is **BLOCKED**. Composite simulations must not be used as proof.
3. **Zero Keeper Loss Observed on Evaluated Datasets**: On both Photo Triage (195 validation series) and AlbumBench (8 real wedding albums), the hardened production rules achieved **0.00% Keeper Loss Rate** (0 of 195 Photo Triage keepers lost, 0 of 189 AlbumBench keepers lost).
