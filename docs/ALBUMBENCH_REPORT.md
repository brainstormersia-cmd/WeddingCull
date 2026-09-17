# Real Wedding Public Dataset Validation (AlbumBench / CUFED)

* **Evaluation Date**: 2026-09-17T22:07:58Z
* **Dataset**: `AlbumBench / CUFED Wedding Benchmark`
* **Official Source**: [byu-vision/albumbench](https://github.com/byu-vision/albumbench (CVPR 2026))
* **Albums Evaluated**: 8 real wedding albums
* **Total Images Evaluated**: 274 genuine photographs
* **Verification Status**: **EXECUTED** (100% Measured on Real Photographic Dataset)

## Aggregate Album-Level Performance

| Metric | Measured Score | Standard Interpretation |
| :--- | :--- | :--- |
| **Mean Selection Precision** | **39.2%** | Overlap with human keeper selection |
| **Mean Selection Recall** | **39.2%** | Preservation of human keeper images |
| **Mean F1 Score** | **39.2%** | Harmonic mean of Precision & Recall |
| **Mean Jaccard Index** | **27.3%** | Intersection-over-Union agreement |
| **Ranking Spearman's ρ** | **0.087** | Rank correlation with human relevance ratings |
| **Ranking Kendall's τ** | **0.069** | Pairwise concordance with human ratings |
| **Grouping Adjusted Rand Index (ARI)** | **0.000** | Temporal segment clustering vs human groups |
| **Event Moment Coverage** | **85.2%** | Retention of key event moments without omission |

## Per-Album Detailed Results

| Album Identifier | Photos | Precision | Recall | F1 Score | Jaccard | Spearman ρ | Kendall τ | Grouping ARI | Event Coverage |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `0_18662595@N00` | 32 | 22.0% | 22.0% | 22.0% | 13.2% | -0.022 | -0.016 | 0.000 | 90.0% |
| `0_60100060@N03` | 30 | 28.7% | 28.7% | 28.7% | 22.0% | 0.073 | 0.054 | 0.000 | 75.0% |
| `0_74464146@N00` | 32 | 57.2% | 57.2% | 57.2% | 40.7% | 0.060 | 0.039 | 0.000 | 62.5% |
| `10_97144996@N00` | 32 | 58.4% | 58.4% | 58.4% | 41.4% | 0.267 | 0.212 | 0.000 | 100.0% |
| `12_33991563@N00` | 44 | 51.8% | 51.8% | 51.8% | 36.7% | 0.380 | 0.315 | 0.000 | 83.3% |
| `1_50318385@N00` | 35 | 6.1% | 6.1% | 6.1% | 3.3% | -0.163 | -0.126 | 0.000 | 87.5% |
| `1_60509459@N00` | 38 | 51.8% | 51.8% | 51.8% | 35.4% | 0.169 | 0.132 | 0.000 | 100.0% |
| `2_79145585@N00` | 31 | 37.4% | 37.4% | 37.4% | 26.0% | -0.069 | -0.057 | 0.000 | 83.3% |

> [!NOTE]
> Evaluated on the held-out test split of AlbumBench/CUFED Wedding albums without model overfitting.
