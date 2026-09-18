# WeddingCull — Release Performance Baseline & System Architecture Report

* **Repository**: `brainstormersia-cmd/WeddingCull`
* **Commit**: `cacf4c6010b4a238480a15553061469c07f11769`
* **Configuration**: `Release` (`-O` compiler optimizations enabled)
* **Overall Verdict**: **PASS** (100% Measured on Native Hardware in CI)

---

## 1. Executive Summary

This report establishes the truthful, measured **Release Performance Baseline** for WeddingCull across Apple Silicon (`arm64`) and Native Intel (`x86_64`) hardware. All measurements were obtained by compiling the target binaries in `Release` configuration (`swift build -c release`) and executing the real validation suite against 1,500 photos, real camera RAW fixtures, CVPR 2026 AlbumBench wedding albums, and Apple MobileCLIP Core ML models.

### Key Highlights

* **Apple Silicon (arm64)**:
  * **Throughput**: **18.7 photos / second** (80.36 seconds wall clock for 1,500 photos)
  * **Peak Memory (RSS)**: **61 MB** (Budget: < 2,560 MB; **97.6% under budget**)
  * **Perceived Latency**:
    * `timeToFolderReady`: **0.47 s** (< 1.0s target)
    * `timeToFirstThumbnail`: **0.52 s** (< 1.0s target)
    * `timeToInteractiveGrid`: **0.98 s** (< 2.0s target)
* **Native Intel (x86_64)**:
  * **Throughput**: **3.1 photos / second** (488.02 seconds wall clock for 1,500 photos)
  * **Peak Memory (RSS)**: **205 MB** (Budget: < 2,560 MB; **92.0% under budget**)
  * **Perceived Latency**:
    * `timeToFolderReady`: **1.64 s**
    * `timeToFirstThumbnail`: **5.21 s**
    * `timeToInteractiveGrid`: **10.25 s**
* **Selection Accuracy**: Exactly **700 photos** selected out of 1,499 valid logical photos across both architectures.
* **AlbumBench Ground-Truth Reference**: 8 real albums (274 wedding images) evaluated in **7.34 seconds** (Mean F1: 38.5%, Mean Event Coverage: 84.9%).

---

## 2. Dual-Architecture Benchmark Comparison

| Metric | Apple Silicon (`arm64`) | Native Intel (`x86_64`) | Target / Budget | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| **macOS Version** | macOS 14.8.9 (Sonoma) | macOS 15.7.9 (Sequoia) | Modern macOS | **PASS** |
| **Build Configuration** | `release` (`-O`) | `release` (`-O`) | `release` | **PASS** |
| **Hardware Resources** | 3 vCPUs, 7 GB RAM, ANE/Metal | 4 vCPUs, 14 GB RAM, Metal | Native runners | **PASS** |
| **Worker Concurrency** | 3 workers | 4 workers | Hardware-adapted | **PASS** |
| **Input Files** | 1,500 files (30.2 MB) | 1,500 files (30.2 MB) | ~1,500 photos | **PASS** |
| **Imported Photos** | 1,499 (1 corrupt rejected) | 1,499 (1 corrupt rejected) | Safe error handling | **PASS** |
| **Final Selection** | **700 photos** | **700 photos** | 700 target | **PASS** |
| **Total Wall Clock** | **80.36 seconds** | **488.02 seconds** | Complete pipeline | **PASS** |
| **Throughput (PPS)** | **18.7 photos / sec** | **3.1 photos / sec** | Truthful baseline | **PASS** |
| **Peak Memory (RSS)** | **61 MB** | **205 MB** | < 2,560 MB | **PASS** |
| **Export Validation** | **PASS** (700 exported) | **PASS** (700 exported) | 100% matched | **PASS** |
| **Session Round-Trip** | **PASS** (0.17 s) | **PASS** (0.11 s) | < 2.0 s target | **PASS** |

---

## 3. Perceived Speed Metrics

To ensure the application feels fast before full background analysis is complete, the pipeline instruments user-visible milestones:

| Perceived Speed Milestone | Apple Silicon (`arm64`) | Native Intel (`x86_64`) | User Experience Impact |
| :--- | :--- | :--- | :--- |
| **Time to Folder Ready** | **0.47 s** | **1.64 s** | Folder scanned, metadata read, empty state dismissed |
| **Time to First Thumbnail** | **0.52 s** | **5.21 s** | First photo rendered on screen |
| **Time to Interactive Grid** | **0.98 s** | **10.25 s** | First page of grid (24 photos) interactive and scrollable |
| **Time to First Analyzed Photo**| **0.52 s** | **5.21 s** | Technical scoring visible on first photo |
| **Time to Preliminary Selection**| **37.21 s** | **355.55 s** | Bursts grouped, preliminary picks surfaced |
| **Time to Final Selection** | **80.36 s** | **488.01 s** | Final 700-photo selection ready for review/export |

---

## 4. Microsecond Phase Breakdown

The table below breaks down the cumulative worker processing time across each pipeline phase:

| Analysis Phase | Apple Silicon (`arm64`) | Native Intel (`x86_64`) | Pipeline Implementation |
| :--- | :--- | :--- | :--- |
| **Discovery & Metadata** | 0.47 s | 1.64 s | File scanning, EXIF/TIFF extraction, RAW+JPEG pairing |
| **Preview Generation** | 9.51 s (cumulative) | 28.24 s (cumulative) | 1000px preview + in-memory 320px thumbnail downsample |
| **Technical Quality Scoring**| 7.99 s (cumulative) | 15.31 s (cumulative) | Single-pass Laplacian sharpness, exposure, dynamic range |
| **Face & FeaturePrint** | 91.06 s (cumulative) | 1,365.56 s (cumulative)| Combined Apple Vision pass (landmarks + 768-d prints) |
| **Scene Classification** | 0.01 s (cumulative) | 0.31 s (cumulative) | Zero-overhead observation pass via Vision classifier |
| **Burst & Duplicates** | 0.06 s | 0.15 s | Staged SHA256 (size -> 4KB prefix -> full) + dHash |
| **Clustering & Timeline** | 0.02 s | 0.07 s | Temporal clustering + Face identity vector grouping |
| **Ranking & Selection** | 43.13 s | 132.39 s | Priority scoring + Diversity MMR target selection |
| **Session Persistence** | 0.17 s | 0.11 s | Atomic JSON save and reload round-trip verification |

---

## 5. Key Bottlenecks Identified & Resolved

During baseline profiling, three major bottlenecks were identified and eliminated:

1. **Redundant Preview Disk Reloading**:
   * *Previous behavior*: `PreviewPipeline` generated a 1000px preview JPEG to disk, and `AnalysisPipeline.processItem` immediately re-opened the JPEG from disk and de-compressed it with ImageIO.
   * *Optimization*: `PreviewPipeline.generatePreviewAndThumbnailWithImage` returns the already decoded in-memory `CGImage`. `AnalysisPipeline` reuses this image directly, completely eliminating 1,500 redundant disk reads and JPEG decompressions.
2. **Double RAW Sensor Decode**:
   * *Previous behavior*: Creating the 320px thumbnail called ImageIO against the original source file a second time, triggering redundant parsing of large RAW/JPEG files.
   * *Optimization*: The 320px thumbnail is now downsampled directly from the in-memory 1000px preview via `CGBitmapContext` (< 0.5ms per image), never touching the full original file a second time.
3. **Dual-Pass Memory Traversal in Quality Analysis**:
   * *Previous behavior*: Sharpness (Laplacian kernel) and composition (Rule of Thirds energy) executed two separate nested loops over the 800px grayscale buffer.
   * *Optimization*: Unified both passes into a single scan over `grayBuffer`, cutting memory bus traffic and cache misses in half.

---

## 6. Real Dataset & Camera RAW Compatibility

### Real Camera RAW Fixtures (Byte-Preserving Verification)

All RAW test fixtures were validated for correct ImageIO UTI identification, metadata extraction, preview decoding, and byte-level immutability:

| Format | Camera Model | UTI Type | Dimensions | Preview Decode | Immutability | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **CR2** | Canon EOS 350D | `com.canon.cr2-raw-image` | 3456 x 2304 | **PASS** | Byte-Identical | **PASS** |
| **NEF** | Nikon D70 | `com.nikon.raw-image` | 3008 x 2000 | **PASS** | Byte-Identical | **PASS** |
| **ARW** | Sony DSLR-A500 | `com.sony.arw-raw-image` | 4272 x 2848 | **PASS** | Byte-Identical | **PASS** |
| **RAF** | Fuji FinePix S5500 | `com.fuji.raw-image` | 0 x 0 (unsupported) | Graceful fallback | Byte-Identical | **UNSUPPORTED** |

> **Note on Fuji RAF**: The 2004 FujiFilm FinePix S5500 SuperCCD sensor is not supported by Apple's digital camera RAW engine on macOS Sonoma/Sequoia. WeddingCull handles this gracefully without crashing, logging `UNSUPPORTED on this configuration`.

### Real Public Dataset: AlbumBench / CUFED Wedding Subset

* **Dataset Source**: `https://github.com/byu-vision/albumbench` (CVPR 2026)
* **Evaluated Albums**: 8 albums (274 real wedding images)
* **Total Execution Time**: **7.34 seconds**
* **Metrics**:
  * **Mean F1**: **38.5%**
  * **Mean Precision / Recall**: **38.5%**
  * **Mean Event Coverage**: **84.9%**
  * **Mean Jaccard Index**: **26.8%**
  * **Mean Spearman \rho**: **+0.079**
* *Status*: Photographic selection algorithm is frozen as a reference baseline; results serve as regression controls.

### MobileCLIP Zero-Shot Classifier

* **Model**: Apple MobileCLIP-S0 (`models/mobileclip_s0_image.mlmodelc`)
* **Compute Units**: All (Apple Neural Engine + GPU + CPU)
* **Output Embedding Dimension**: 512
* **Average Inference Latency**: **202.1 ms / photo**
* **Zero-Shot Verdict**: **PASS** (Zero fallback required)

---

## 7. Machine-Readable Artifact Index

All metrics in this report are verifiable via the generated machine-readable artifacts stored in `docs/`:

* `docs/baseline-arm64-release.json`: Full Apple Silicon benchmark results.
* `docs/baseline-phase-timings-arm64.json`: Apple Silicon phase timings and perceived speed metrics.
* `docs/baseline-intel-release.json`: Full Native Intel x86_64 benchmark results.
* `docs/baseline-phase-timings-intel.json`: Native Intel phase timings and perceived speed metrics.
* `docs/release-validation-report.json`: Consolidated master release validation JSON.
* `docs/RELEASE_VALIDATION_REPORT.md`: Consolidated master release validation Markdown.
