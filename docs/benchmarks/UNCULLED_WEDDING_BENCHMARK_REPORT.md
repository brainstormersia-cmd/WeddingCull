# WeddingCull: Synthetic/Composite 2,495-Photo Simulation Report

> [!WARNING]
> **SIMULATION ONLY — NOT AN AUTHENTIC UN-CULLED WEDDING SHOOT BENCHMARK**
> This benchmark is a **synthetic/composite simulation** assembled from independent multi-shot burst sequences in the Photo Triage dataset, isolated single photos, and synthetic defect images (blackouts, whiteouts, extreme blur).
> 
> **It is NOT an authentic un-culled wedding shoot and MUST NOT be used as proof of the ~80% manual culling workload reduction claim.**

---

## 1. Methodological Limitations & Integrity Caveats

Before examining any simulation figures, the following methodological boundaries are explicitly recorded:

1. **Composite, Not Authentic**: The catalog does not originate from a single wedding event. It combines unrelated series from Photo Triage and synthetic defects. It lacks authentic capture timestamps, metadata, and the natural shooting rhythm of a professional wedding photographer.
2. **Diagnostic Proxy, Not Production Pipeline**: Metrics were computed via a Python/OpenCV/Haar cascade proxy script (`scripts/benchmark_wedding_workload.py`). Production performance must be evaluated through the authentic macOS Apple Vision Swift pipeline (`WeddingCullFeatureExporter` / `QualityBenchmarkV2`), not Python approximations.
3. **Assumed Bursts, Not Autonomous Detection**: Burst groupings were assigned directly from Photo Triage series metadata rather than being discovered autonomously by `DuplicateAndBurstDetector.detectBursts()` from raw folder imports.
4. **Python Top-K Sort, Not Real DiversitySelector**: The Curated Mode in this simulation used a naive Python score sort to pick the top 450 frames. It did not execute `DiversitySelector.swift`, which performs timeline coverage, category balancing, and person clustering. Picking an arbitrary `targetCount=450` is a simulation parameter, not a demonstrated workload reduction.
5. **Removal of Hypothetical Scenarios**: All hypothetical unverified scenarios (e.g., "96%-burst / 80% reduction") have been completely removed.
6. **Blocker Declared**: Empirical validation of the ~80% workload reduction claim is **BLOCKED** until a complete, authentic, un-culled wedding shoot catalog (2,000–3,000 photos from the same event, preserving timestamps and paired with photographer keeper ground truth) is obtained and evaluated.

---

## 2. Simulation Results (Diagnostic Reference Only)

The table below records the diagnostic behavior of the simulated pipeline on this 2,495-photo composite collection:

- **Total Photos in Composite**: 2,495 (1,565 burst frames across 455 series, 840 isolated frames, 90 synthetic defects)
- **Multi-Shot Bursts (Assumed from Dataset)**: 455 bursts
- **Alternates Collapsed**: 866 frames
- **Catastrophic Defects Auto-Rejected**: 100 frames (90 synthetic, 10 dataset frames)
- **Borderline Near-Ties Flagged for Review**: 244 frames

| Simulated Workflow | Initial Photos | Units Inspected (Simulated) | Frames Collapsed / Culled | Simulated Reduction |
|:---|:---:|:---:|:---:|:---:|
| **Manual Unassisted Review** | 2,495 | 2,495 | 0 | 0.0% |
| **Stack Tile Grid Mode** (Tiles + Singles) | 2,495 | **1,293** | 1,202 | **48.18%** |
| **Grid Mode + Review Queue** | 2,495 | **1,537** | 958 | **38.40%** |
| **Curated Mode** (Arbitrary Top-450 Sort + Reviews) | 2,495 | **694** | 1,801 | **72.18%** *(Simulation parameter)* |

---

## 3. Safety Metric Observations on the Composite Dataset

| Metric | Measured on Composite | Production Target | Note |
|:---|:---:|:---:|:---|
| **Keeper Loss Rate** | **0.23%** (3 / 1,295) | < 1.0% | 3 flagged dataset keepers culled |
| **Auto-Reject Precision** | **97.00%** (97 / 100) | > 95.0% | 97 true defects among 100 rejects |
| **False-Reject Keeper Rate** | **3.00%** (3 / 100) | < 5.0% | 3 crowd-voted choices among ruined series |
| **Burst Winner Exact Top-1 Match** | **40.22%** (183 / 455) | > 40.0% | Exact match to Photo Triage rank 1 |

### Inspection of the 3 Auto-Rejected Dataset "Keepers"
- `000498-02.JPG`: Laplacian Sharpness = **7.32** (threshold: 12.0). Entire series is ruined by severe motion blur.
- `000528-01.JPG`: Laplacian Sharpness = **1.80**. Both frames in series are completely out of focus.
- `001066-01.JPG`: Shadow Clipping = **88.1%**, Mean Luminance = **0.039**. Accidental blackout frame.

*Verdict*: While labeled as "winners" in Photo Triage because crowd workers were forced to select a photo even in completely ruined series, all 3 images are catastrophic technical defects.

---

## 4. Next Steps & Blocker Declaration

- **BLOCKER**: We do not yet possess an authentic, un-culled wedding shoot dataset from the same event with original capture timestamps and photographer ground truth.
- **Action**: Stop creating synthetic/composite simulations. When an authentic un-culled shoot dataset becomes available, run it end-to-end through the authentic macOS Swift pipeline (`DuplicateAndBurstDetector.detectBursts()`, `DiversitySelector.swift`, `TechnicalQualityAnalyzer`) without pre-grouping or Python approximations.
