# WeddingCull Real Wedding Validation Report

* **Evaluation Date**: 2026-09-17T22:13:10Z
* **Dataset**: Synthetic Wedding Shoot Benchmark (250 photos)
* **Status**: Completed

## Ground-Truth Alignment & Performance

| Metric | Measured Value | Standard Target |
| :--- | :--- | :--- |
| **Total Photos Evaluated** | 249 | Complete Shoot |
| **AI Selected Photos** | 125 | Target: 125 |
| **Photographer Keepers** | 201 | Reference Gallery |
| **Intersection Count** | 121 | Matched Keepers |
| **Precision@Target** | 96.8% | High quality density |
| **Recall@Target** | 60.2% | > 80.0% |
| **Jaccard Similarity** | 59.0% | Overlap Agreement |
| **Hard-Reject Error Rate** | 3.2% | < 1.0% |
| **Burst Winner Agreement** | 100.0% | > 90.0% |
| **Category Coverage** | 50.0% | 100% |
| **Duplicate Leakage Rate** | 0.0% | 0.0% |
| **Unique Moment False Reject** | 0.0% | < 5.0% |
| **Manual Substitutions Needed** | 80 | Minimal |

## Editorial Quality Notes

- Evaluated using controlled synthetic wedding shoot.
- Verify with real photographer dataset using scripts/evaluate-wedding.sh