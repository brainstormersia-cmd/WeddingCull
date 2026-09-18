# WeddingCull Experiment Integrity & Non-Substitution Protocol

This policy governs all benchmarking, feature extraction, ablation studies, and model evaluations in WeddingCull.

---

## 1. Non-Substitution Mandate

When an experiment requires an Apple platform capability (e.g., Apple Vision `VNDetectFaceCaptureQualityRequest`, `VNDetectFaceLandmarksRequest`, CoreGraphics 1000px/800px preview pipeline) that is unavailable in the current operating system (Windows or Linux):

1. **STOP** that part of the experiment.
2. **NEVER** substitute unavailable production technology with an approximation (e.g. OpenCV Haar cascades, MediaPipe, PIL) and present the result as production-equivalent.
3. If an experiment requires macOS, report:
   ```text
   BLOCKED_MACOS_REQUIRED
   ```
   and provide the exact command and transfer artifact required to execute authentically on macOS.

---

## 2. Official Experiment States

Every experiment report and artifact must declare one of three mutually exclusive states:

| Official State | Definition | Validation Criteria |
| :--- | :--- | :--- |
| `EXECUTED_AUTHENTIC` | Executed using genuine production Swift code and native macOS frameworks. | Real macOS runner, Apple Vision linked and executed, authentic CoreGraphics pipeline, verified Git SHA. |
| `EXECUTED_PROXY` | Approximated using non-production tools (e.g. Python OpenCV) for diagnostic or pipeline testing. | Must carry explicit warning banner: `PROXY_EXPERIMENT — NOT PRODUCTION EQUIVALENT`. Cannot replace baseline. |
| `NOT_RUN_BLOCKED` | Experiment paused due to missing platform dependencies or unverified datasets. | Emits exact blocker code (e.g. `BLOCKED_MACOS_REQUIRED`) and commands required to resume. |

> [!CAUTION]
> Reporting `PASS` without specifying an official state is strictly forbidden.

---

## 3. Mandatory Provenance Attributes

Every empirical result and benchmark artifact must include:
1. `source_dataset`: Canonical dataset name and citation.
2. `split`: Exact partition name (`FIT`, `DEV`, `VAL`, `TEST`).
3. `exact_counts`: Series count, image count, and evaluated pairs count.
4. `git_sha`: Full 40-character or 7-character commit SHA.
5. `executable_or_script`: The exact binary or script invoked.
6. `operating_system`: OS name, version, and kernel.
7. `feature_extractor`: The exact feature extraction engine (`WeddingCullFeatureExporter` vs proxy).
8. `apple_vision_actually_executed`: Explicit boolean.
9. `output_artifact_path`: Path to persisted machine-readable output.

> [!NOTE]
> **No artifact = no empirical claim.**
> Terminology such as "verified", "production-equivalent", "authentic", or "WeddingCull baseline" is reserved exclusively for `EXECUTED_AUTHENTIC` runs.

---

## 4. No-Image-IO Rule for Python Modeling

Python ranking and modeling scripts must **never** read raw image files or import `cv2`, `PIL`, `imageio`, or `skimage`.
They must accept only feature caches (`--features <features.jsonl>`) and ground-truth labels (`--labels <labels.json>`).
This separation guarantees that image analysis is authored and executed solely by the single authoritative Swift codebase (`Sources/`).
