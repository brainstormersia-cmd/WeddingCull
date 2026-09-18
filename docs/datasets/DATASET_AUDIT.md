# Photographic Dataset Integrity Audit Report

**Audit Date**: 2026-09-18T22:48:00Z  
**Dataset Storage Root**: `X:/WeddingCullDatasets/raw`  
**Audit Version**: 1.0.0

---

## 1. Executive Summary

All 6 primary real photographic datasets have been successfully extracted and verified on disk under `X:\WeddingCullDatasets\raw\`.

| Dataset | Total Images | Annotations / Ground Truth | Evaluability Status | License Classification |
| :--- | :---: | :---: | :---: | :---: |
| **Photo Triage** | 31,086 | 12,558 pairs + 74,655 reviews | **100% COMPLETE (Evaluable)** | `RESEARCH_ONLY` |
| **PARA** | 31,220 | 807,586 aesthetic records | **100% COMPLETE (Evaluable)** | `RESEARCH_ONLY` |
| **HRIQ** | 1,120 (x3 res = 3,360) | 1,120 MOS subjects | **Images Complete / Awaiting MOS table** | `RESEARCH_ONLY` |
| **CUHK Blur** | 1,000 | 1,000 binary blur masks | **100% COMPLETE (Evaluable)** | `RESEARCH_ONLY` |
| **CEW** | 10,176 | 10,180 binary eye states | **100% COMPLETE (Evaluable)** | `RESEARCH_ONLY` |
| **MRL Eye** | 84,898 | 84,937 attribute tuples | **100% COMPLETE (Evaluable)** | `RESEARCH_ONLY` |

---

## 2. Photo Triage Completeness & Denominator Audit

Photo Triage is the **primary benchmark** for same-moment photo ranking and pairwise human preferences.

* **Total Images on Disk**: 31,086 (Decodable: 31,086, Corrupt: 0)
* **Review JSONs Available**: 4,986 files containing 74,655 individual voter choices
* **Split Partitioning**:
  * **Train**: 4,560 series, 12,075 pairwise comparisons
  * **Validation (Benchmark Set)**: 195 series, 483 pairwise comparisons
  * **Test (Held-Out)**: 967 series, 2,585 pairwise comparisons
* **Validation Split Evaluability**:
  * Manifest Series: **195**
  * Complete Series: **195**
  * Excluded Series: **0**
  * Annotated Pairs: **483**
  * Evaluated Pairs: **483**
  * Pairwise Coverage: **100.0%**

---

## 3. Dataset-Specific Integrity Findings

### A. PARA (Personalized Aesthetics Assessment)
* Total Images: **31,220** across **446** sessions.
* Annotation Records: **807,586** rows in `PARA-Images.csv`.
* Status: Decrypted and extracted with zero corruption.

### B. HRIQ (High Resolution Image Quality)
* Canonical Resolution (2880x2160): **1120** images (merged parts 1 & 2 cleanly).
* Downsampled Resolutions (1024x768, 512x384): **1120** and **1120** images.
* All resolutions match 1:1 across 1,120 base images.

### C. CUHK Blur
* Defocus & Motion Blur Images: **1000** images.
* Pixel-level Ground Truth Masks: **1000** masks.
* Shi et al. Baseline Results: **1000** images.
* Pair Completeness: **100% matched**.

### D. CEW & MRL Eye (Eye State & Blink Benchmarks)
* CEW Dataset A Eye Crops: **8,984** crops.
* CEW Dataset B High-Res Faces: **1,192** faces.
* MRL Eye Subject Crops: **84,898** crops across **38** subjects.
* Filename attributes validated: gender, glasses, eye state, reflections, lighting, sensor.
