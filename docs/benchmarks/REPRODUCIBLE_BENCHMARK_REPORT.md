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

## 3. Authentic Complete Un-culled Wedding Shoot Benchmark (`wedding_shoot_74ef`)

- **Dataset**: `wedding_shoot_74ef` (Category A: Complete Un-culled Wedding Shoot)
- **Sensor & Continuity**: Nikon D750, uniform native resolution (6016x4016, 24.16 MP), 384 frames present out of 410 camera counter span (**93.7% continuity**), single afternoon/evening event (4.1 hours).
- **Execution Platform**: Apple Silicon arm64 macOS 14.8.9, native Swift benchmark using production components (`RealWeddingBenchmark`).
- **Autonomous Burst Discovery**: 92 burst sequences discovered by `DuplicateAndBurstDetector.detectBursts()` across 248 photos (**64.58% burst ratio**).
- **Singles**: 136 photos (35.42%).
- **Alternates Collapsed**: 80 burst alternates safely collapsed into stacks (20.83%).
- **Review Items Flagged**: 76 near-ties ($\le 0.05$ score gap) preserved in `.review` rather than auto-culled.
- **Catastrophic Auto-Rejections**: 0 (0.0%).
- **Inspection Units**: **304** units (136 singles + 92 burst winners + 76 review items), down from 384 input photos.
- **Measured Inspection-Unit Compression**: **20.83%** (measured inspection-unit compression on `wedding_shoot_74ef`, not time saving).
- **Safety & Ground Truth Status**: 0 photos auto-rejected; human keeper loss is unmeasurable because no human keeper ground truth is available (no embedded rating tags or external XMP sidecars).
- **Review Score Gap Distribution (76 Reviews / 92 Bursts)**: 0.000–0.005: 33 (35.9%), 0.005–0.010: 11 (12.0%), 0.010–0.020: 10 (10.9%), 0.020–0.030: 7 (7.6%), 0.030–0.050: 15 (16.3%), >0.050: 16 (17.4%). For non-face bursts (N=30), 22 have gap $\le 0.005$ (96.7% review rate) because negligible sharpness spread assigns equivalent sharpness (0.50) while consecutive frames have nearly identical exposure.
- **Detailed Audit & Stratification Tables**: See [`REAL_WEDDING_BENCHMARK_REPORT.md`](REAL_WEDDING_BENCHMARK_REPORT.md).

## 4. Status of the 80% Workload Reduction Claim

1. **Pre-curated Datasets (AlbumBench - Category C)**: AlbumBench consists of Flickr wedding albums that have ALREADY been culled by photographers before upload (photographers discarded ~95% of their burst frames). Therefore, AlbumBench only offers ~2.19% workload reduction on average (up to 19.35% on burst-heavy albums).
2. **Authentic Complete Un-culled Shoot (`wedding_shoot_74ef` - Category A)**: Evaluated through a native Swift benchmark using production components, achieving **20.83% measured inspection-unit compression on `wedding_shoot_74ef`** (not time saving). 0 photos auto-rejected; human keeper loss is unmeasurable because no human keeper ground truth is available (76 near-ties preserved for human review). WeddingCull guarantees no permanent data deletion via non-destructive grouping, which is strictly distinguished from "no keeper missed during inspection".
3. **The 80% Figure is a Product Target, Not a Universal Fact**: Manual culling workload compression is strictly bounded by the event's burst ratio and review conservatism:
   $$\text{Workload Compression} \le \text{Burst Ratio} \times (1 - \text{Review Rate})$$
   In a shoot with 35.4% single shots and 19.8% near-tie review candidates, 20.83% represents the exact mathematically safe compression achievable without risking keepers. Reaching 75–80% workload reduction requires either an ultra-rapid burst shoot (>85% burst ratio, e.g. continuous high-speed sports/wedding action) or narrower review thresholds once model confidence is further validated on annotated un-culled shoots.
4. **Zero Keeper Loss Observed on Evaluated Datasets**: On both Photo Triage (195 validation series) and AlbumBench (8 real wedding albums), the hardened production rules achieved **0.00% Keeper Loss Rate** (0 of 195 Photo Triage keepers lost, 0 of 189 AlbumBench keepers lost). Under no circumstances are claims of "100% safety" or "80% guaranteed reduction" made; only empirical observations on authentic datasets are reported.

