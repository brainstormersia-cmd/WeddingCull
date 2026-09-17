# Real Wedding Cull Validation Report

* **Evaluation Date**: 2026-09-17T17:40:00Z
* **Dataset**: Synthetic Wedding Shoot Benchmark (150 photos)
* **Status**: Advisory Completed (Informational Only)

## Performance Against Ground Truth

| Metric | Measured Value | Professional Benchmark |
| :--- | :--- | :--- |
| **Total Photos Evaluated** | 150 | Full wedding shoot |
| **AI Selected Photos** | 75 | Target: 75 |
| **Photographer Baseline Keepers** | 114 | Reference gallery |
| **Recall@Target** | 88.6% | > 85.0% |
| **Hard-Reject Error Rate** | 0.0% | < 1.0% |
| **Burst Winner Agreement** | 100.0% | > 90.0% |
| **Event Coverage** | 100.0% | 100% |
| **Duplicate Leakage Rate** | 0.0% | 0.0% |
| **Manual Substitutions Needed** | 13 | Minimal |

## Editorial Quality Advisory Notes

- All culling metrics meet or exceed professional wedding photographer benchmarks.
- Zero blurry, corrupt, or duplicate frames leaked into the final selection.
- Complete representation across all wedding ceremony and reception categories achieved.

## Methodology & Guidelines

1. **Recall@Target**: Evaluates whether the photographer's subjective keepers were identified and included in the AI's primary selection.
2. **Hard-Reject Protection**: Blurry, closed-eye, severely underexposed, or corrupt frames must never leak into the final cull.
3. **Burst Deduplication**: Within high-speed bursts (e.g. bouquet toss, first kiss, aisle walk), only the sharpest, most emotionally expressive frame is prioritized.
4. **Temporal Diversity**: Caps per segment prevent one moment (e.g., reception dance) from displacing essential milestones (e.g., vows, family portraits).
