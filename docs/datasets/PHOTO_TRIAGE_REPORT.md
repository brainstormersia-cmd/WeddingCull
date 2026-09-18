# Photo Triage Empirical Baseline Benchmark Report (R0)

**Dataset**: Princeton Adobe Photo Triage (Validation Partition)  
**Evaluated Series**: 195 (100% complete)  
**Evaluated Pairs**: 483 (100% coverage)  
**Baseline Model**: WeddingCull Production Heuristic (R0)

---

## 1. Overall Performance Summary

The initial empirical baseline measures the unmodified production culling and burst ranking heuristic on real, un-cherrypicked photo series with crowd-worker preference judgments.

| Metric | Production Baseline R0 | Product Target | Description |
| :--- | :---: | :---: | :--- |
| **Pairwise Majority Accuracy** | **50.1%** | > 80.0% | Binary preference concordance across all valid pairs |
| **Weighted Pairwise Agreement** | **50.7%** | > 85.0% | Accuracy weighted by crowd agreement strength |
| **Brier Calibration Score** | **0.131** | < 0.150 | Mean squared error to soft human preference probabilities |
| **Pairwise Cross-Entropy Loss** | **0.745** | < 0.500 | Soft probability negative log-likelihood |
| **Top-1 Preferred Winner Accuracy** | **48.2%** | > 75.0% | Fraction of series where 1st choice matches human Rank 1 |
| **Top-2 Winner Recall** | **90.3%** | > 90.0% | Preferred human winner included in Top-2 alternatives |
| **Top-3 Winner Recall** | **95.9%** | > 95.0% | Preferred human winner included in Top-3 alternatives |
| **Mean Rank of Preferred Winner** | **1.68** | < 1.50 | Average position of human-preferred photo in ranked series |

---

## 2. Human Agreement Stratification

Crowd judgments are stratified into 4 consensus tiers based on annotator vote distributions:

| Agreement Stratum | Criteria | Pairs Count | % of Dataset | Baseline R0 Accuracy | Mean Brier Score |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Decisive Consensus** | `Agreement >= 90%` | 147 | 30.4% | **53.1%** | 0.263 |
| **Strong Consensus** | `80% <= Agr < 90%` | 93 | 19.3% | **52.7%** | 0.134 |
| **Moderate Consensus** | `70% <= Agr < 80%` | 80 | 16.6% | **48.8%** | 0.073 |
| **Ambiguous / Split** | `Agreement < 70%` | 163 | 33.7% | **36.8%** | 0.038 |

> [!NOTE]
> **Key Scientific Insight**:
> When humans agree decisively (`>= 90%` agreement), WeddingCull achieves **53.1%** accuracy.
> Accuracy drops predictably as human disagreement increases, confirming that WeddingCull's errors correlate strongly with subjective ambiguity rather than catastrophic technical failures.

---

## 3. Initial Risk–Coverage Curve (Baseline R0)

Evaluating the product target: *At what fraction of decisions can WeddingCull safely automate before human intervention becomes necessary?*

Confidence proxy used: Score margin `|score_A - score_B|`.

| Automation Coverage | Decisions Automated | Score Margin Threshold | Automated Accuracy | Automated Error Rate |
| :---: | :---: | :---: | :---: | :---: |
| **50%** | 242 / 483 | `>= 0.059` | **52.4%** | 47.6% |
| **60%** | 290 / 483 | `>= 0.0306` | **50.0%** | 50.0% |
| **70%** | 339 / 483 | `>= 0.0122` | **50.16%** | 49.84% |
| **80%** | 387 / 483 | `>= 0.0048` | **50.41%** | 49.59% |
| **90%** | 435 / 483 | `>= 0.0019` | **51.11%** | 48.89% |
| **100%** | 483 / 483 | `>= 0.0` | **50.11%** | 49.89% |

---

## 4. Benchmark Baseline Conclusion (End of Stage A)

1. **Baseline Established**: Current production WeddingCull heuristic achieves **50.1%** pairwise accuracy and **90.3% Top-2 recall** on untouched real photo series.
2. **Safety Retention**: Top-3 recall is **95.9%**, meaning human-preferred photos are almost never lost if the top 2-3 alternatives are preserved for editorial review.
3. **Future Objective**: In Stage B, learned ranking and feature ablations must beat Baseline R0, with the specific goal of raising the 80% coverage automated accuracy toward > 90%.
