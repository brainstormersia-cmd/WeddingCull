# Princeton Adobe Photo Triage Dataset Format Specification

This document defines the verified, empirical structure of the Princeton Adobe Photo Triage dataset based on direct inspection of archive package `archive.zip` (13.0 GB, SHA-256: `e70743beb5b91cc55cf545d78ac8312a420e086a94116b81da1f3ce91f810bc0`).

---

## 1. Directory Structure

```text
PhotoTriage/
├── train_val/
│   ├── train_pairlist.txt            (12,075 pairwise records)
│   ├── val_pairlist.txt              (483 pairwise records)
│   ├── train_val_series.mat          (4,755 series records with Bradley-Terry scores)
│   ├── README.txt                    (Citation and format summary)
│   ├── train_val_imgs/               (12,988 JPEG images: %06d-%02d.JPG)
│   └── reviews_trainval/
│       └── reviews_trainval/
│           ├── 000001.json           (4,986 JSON files with raw human votes & reasons)
│           └── ...
└── test/
    ├── test_pairlist.txt             (2,585 pairwise evaluation pairs)
    ├── README.txt
    └── test_imgs/                    (2,555 JPEG images: %06d-%02d.JPG)
```

---

## 2. Split Partitioning & Leakage Prevention

The Princeton authors partitioned photo series strictly by series ID. There is **zero overlap** among partitions:

| Split | Series Count | Pairs Count | Images Count | Review JSONs Available |
| :--- | :---: | :---: | :---: | :---: |
| **Train** | 4,560 | 12,075 | ~12,300 | 4,560 (100%) |
| **Validation** | 195 | 483 | ~688 | 195 (100%) |
| **Test** | 967 | 2,585 | 2,555 | 0 (Held-out benchmark) |
| **Overlap** | **0** | **0** | **0** | - |

> [!IMPORTANT]
> **No Series Leakage**: Images from the same series never cross train, validation, or test partitions.
> All machine learning models must be trained on `Train`, calibrated on `Validation`, and evaluated on `Test` or untouched holdout validation.

---

## 3. Pairlist Text File Specifications

### Files: `train_val/train_pairlist.txt`, `train_val/val_pairlist.txt`
* **Delimiter**: Single space (` `).
* **Line Format**:
  ```text
  #SERIES_ID #PHOTO1_IND #PHOTO2_IND #PREFERENCE_RATIO #RANK_1 #RANK_2
  ```
* **Sample Lines**:
  ```text
  15 1 2 0.123 2 1
  15 1 3 0.546 2 3
  15 2 3 0.896 1 3
  ```
* **Column Definitions**:
  1. `SERIES_ID`: Integer identifier without leading zeroes (e.g. `15`).
  2. `PHOTO1_IND`: 1-based index of Photo 1 in the series (e.g. `1`).
  3. `PHOTO2_IND`: 1-based index of Photo 2 in the series (e.g. `2`).
  4. `PREFERENCE_RATIO`: Derived Bradley-Terry modeled probability that Photo 1 is preferred over Photo 2 (`P(Photo1 > Photo2)`), in range `[0.0, 1.0]`.
  5. `RANK_1`: 1-based global series rank of Photo 1 (1 = best/preferred winner).
  6. `RANK_2`: 1-based global series rank of Photo 2.

### File: `test/test_pairlist.txt`
* **Line Format**:
  ```text
  #SERIES_ID #PHOTO1_IND #PHOTO2_IND
  ```
* **Sample Lines**:
  ```text
  4 1 2
  4 1 3
  4 2 3
  ```
  *(Evaluation pairs without ground-truth labels).*

---

## 4. Raw Review JSON Schema (`reviews_trainval/reviews_trainval/%06d.json`)

Each file contains the full collection of individual crowd-worker annotations for that series.

### Schema:
```json
{
  "reviews": [
    {
      "compareID1": 0,
      "compareID2": 1,
      "compareFile1": "15-1.JPG",
      "compareFile2": "15-2.JPG",
      "userChoice": "RIGHT",
      "reason": [
        "",
        "the window takes away from the view of what your trying to see"
      ]
    },
    {
      "compareID1": 1,
      "compareID2": 0,
      "compareFile1": "15-2.JPG",
      "compareFile2": "15-1.JPG",
      "userChoice": "LEFT",
      "reason": [
        "",
        "it blocks the image."
      ]
    }
  ]
}
```

### Field Definitions:
* `compareID1`, `compareID2`: **0-based** indices of the compared frames (0 corresponds to Photo 1).
* `compareFile1`, `compareFile2`: Short format strings: `"{series_id}-{photo_ind}.JPG"`.
  * Note: The presentation order (`LEFT` vs `RIGHT`) was randomly alternated to prevent position bias.
* `userChoice`:
  * `"LEFT"`: The annotator preferred `compareFile1`.
  * `"RIGHT"`: The annotator preferred `compareFile2`.
* `reason`: 2-element array:
  * `reason[0]`: Positive reason describing why the preferred photo was chosen (frequently blank `""`).
  * `reason[1]`: Negative reason describing defects of the unselected photo (`"insignificant and blurry"`, `"not focused well"`, `"the composition is bad"`, `"too cropped"`).

---

## 5. File Naming Mapping & Normalization

Image files on disk follow standard 6-digit zero-padded formatting:

| Entity | Review JSON Representation | Physical Disk File in `train_val_imgs/` |
| :--- | :--- | :--- |
| Series 1, Photo 1 | `1-1.JPG` | `000001-01.JPG` |
| Series 1, Photo 2 | `1-2.JPG` | `000001-02.JPG` |
| Series 15, Photo 1 | `15-1.JPG` | `000015-01.JPG` |
| Series 4560, Photo 3 | `4560-3.JPG` | `004560-03.JPG` |

**Image Specification**:
* Resolution: 800px on long edge with aspect ratio preserved.
* Format: Standard baseline JPEG (sRGB).

---

## 6. Raw vs. Derived Annotation Architecture

To comply with the culling evaluation methodology, WeddingCull preserves raw voter records and derives analytical properties dynamically:

```text
Raw Annotations (Immutable)
├── series_id: 15
├── photo_a: "000015-01.JPG"
├── photo_b: "000015-02.JPG"
├── votes_a: 2
├── votes_b: 7
├── total_votes: 9
├── reviews: [ { userChoice, reasons... } ]
└── positive_reasons: []
    negative_reasons: ["too vague composition", "the window takes away from view"]

            │
            ▼
Derived Properties (Analytical)
├── pHuman(A > B) = votes_a / (votes_a + votes_b) = 2 / 9 = 0.222
├── majorityWinner = "000015-02.JPG"
├── annotatorAgreement = max(votes_a, votes_b) / total_votes = 7 / 9 = 0.778
├── isAmbiguous = annotatorAgreement < 0.70 (False: strong consensus)
└── consensusTier = "0.70–0.80" (Moderate Consensus)
```
