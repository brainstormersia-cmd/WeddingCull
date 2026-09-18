# WeddingCull — Release Performance Baseline & System Architecture Report

* **Repository**: `brainstormersia-cmd/WeddingCull`
* **Commit**: `dcf08818159a3e7eacf1983b821b23efb1399c3f`
* **Configuration**: `Release` (`-O` compiler optimizations enabled)
* **Overall Verdict**: **PASS** (100% Measured on Native Hardware in CI)

---

## 1. Executive Summary

This report establishes the truthful, measured **Release Performance Baseline** for WeddingCull across Apple Silicon (`arm64`) and Native Intel (`x86_64`) hardware. All measurements were obtained by compiling the target binaries in `Release` configuration (`swift build -c release`) and executing the real validation suite against 1,500 photos, real camera RAW fixtures, CVPR 2026 AlbumBench wedding albums, and Apple MobileCLIP Core ML models.

### Key Highlights

* **Apple Silicon (arm64)**:
  * **Throughput**: **48.9 – 53.0 photos / second** (~30 seconds wall clock for 1,500 photos; up from 18.7 PPS pre-optimization baseline, **2.8x speedup**)
  * **Peak Memory (RSS)**: **81 – 82 MB** (Budget: < 2,560 MB; **96.8% under budget**)
  * **Pipeline Readiness**:
    * `timeToFolderReady`: **0.60 s** (< 1.0s target)
    * `timeToFirstThumbnail`: **0.63 s**
    * `timeToInteractiveGrid`: **0.78 s** (24 cells rendered and interactive)
  * **Session Reopen Latency**: **0.089 s** (< 2.0s target)
* **Native Intel (x86_64)**:
  * **Throughput**: **4.30 photos / second** (350.33 seconds wall clock for 1,500 photos with Winning Decoupled Configuration: Pipeline 2, Classify Slots 2; up from 3.1 PPS original baseline, and faster than 3.91 PPS 4-worker run)
  * **2-Worker Global Scaling**: **4.10 photos / second** (364.70 seconds wall clock; eliminates 757 seconds of wasted scene classification CPU time)
  * **Pre-Tuning 4-Worker Baseline**: **3.91 photos / second** (384.09 seconds wall clock; burned 1,272.66s in scene classification due to contention)
  * **Peak Memory (RSS)**: **183 MB** (Budget: < 2,560 MB; **92.9% under budget**)
  * **Pipeline Readiness**:
    * `timeToFolderReady`: **2.06 s**
    * `timeToFirstThumbnail`: **2.07 s**
    * `timeToInteractiveGrid`: **2.08 s** (24 cells rendered and interactive)
  * **Session Reopen Latency**: **0.084 s** (< 2.0s target)
* **Selection Determinism & Accuracy**: Exactly **700 photos** selected out of 1,499 valid logical photos; selected photo IDs remain 100% byte-identical across eager vs lazy FeaturePrint and incremental DiversitySelector.
* **AlbumBench Ground-Truth Reference**: 8 real albums (274 wedding images) evaluated in **13.98 seconds** (Mean F1: 38.4%, Mean Event Coverage: 88.5%).

---

## 2. Dual-Architecture Benchmark Comparison

| Metric | Apple Silicon (`arm64`) | Native Intel (`x86_64`) Decoupled Winner | Native Intel (`x86_64`) 2 Workers | Native Intel (`x86_64`) 4 Workers (Baseline) | Target / Budget | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **macOS Version** | macOS 14.8.9 (Sonoma) | macOS 15.7.9 (Sequoia) | macOS 15.7.9 (Sequoia) | macOS 15.7.9 (Sequoia) | Modern macOS | **PASS** |
| **Build Configuration** | `release` (`-O`) | `release` (`-O`) | `release` (`-O`) | `release` (`-O`) | `release` | **PASS** |
| **Hardware Resources** | 3 vCPUs, 7 GB RAM, ANE/Metal | 4 vCPUs, 14 GB RAM, Metal | 4 vCPUs, 14 GB RAM, Metal | 4 vCPUs, 14 GB RAM, Metal | Native runners | **PASS** |
| **Worker Concurrency** | 3 workers | 2 pipeline / 2 classify | 2 workers global | 4 workers global | Hardware-adapted | **PASS** |
| **Input Files** | 1,500 files (30.2 MB) | 1,500 files (30.2 MB) | 1,500 files (30.2 MB) | 1,500 files (30.2 MB) | ~1,500 photos | **PASS** |
| **Imported Photos** | 1,499 (1 corrupt rejected) | 1,499 (1 corrupt rejected) | 1,499 (1 corrupt rejected) | 1,499 (1 corrupt rejected) | Safe error handling | **PASS** |
| **Final Selection** | **700 photos** | **700 photos** | **700 photos** | **700 photos** | 700 target | **PASS** |
| **Total Wall Clock** | **30.68 s** | **350.33 s** | **364.70 s** | **384.09 s** | Complete pipeline | **PASS** |
| **Throughput (PPS)** | **48.9 – 53.0 PPS** | **4.30 PPS** | **4.10 PPS** | **3.91 PPS** | Truthful Release | **PASS** |
| **Peak Memory (RSS)** | **82 MB** | **183 MB** | **203 MB** | **214 MB** | < 2,560 MB | **PASS** |
| **Export Validation** | **PASS** (700 exported) | **PASS** (700 exported) | **PASS** (700 exported) | **PASS** (700 exported) | 100% matched | **PASS** |
| **Session Reopen Latency** | **PASS** (0.089 s) | **PASS** (0.084 s) | **PASS** (0.129 s) | **PASS** (0.104 s) | < 2.0 s target | **PASS** |

---

## 3. Pipeline Readiness & Real UI Interactivity Metrics

To ensure the application feels fast before full background analysis is complete, the pipeline instruments user-visible milestones, coupled with real XCUITest macOS UI measurements:

| Pipeline Readiness Milestone | Apple Silicon (`arm64`) | Native Intel (`x86_64`) | User Experience Impact |
| :--- | :--- | :--- | :--- |
| **Time to Folder Ready** | **0.60 s** | **2.06 s** | Folder scanned, metadata read, empty state dismissed |
| **Time to First Thumbnail** | **0.63 s** | **2.07 s** | First photo rendered on screen (progressive delivery) |
| **Time to Interactive Grid** | **0.78 s** | **2.08 s** | First page of grid (24 photos) interactive and scrollable |
| **Time to First Analyzed Photo**| **0.81 s** | **2.61 s** | Technical scoring visible on first photo |
| **Time to Preliminary Selection**| **29.23 s** | **347.71 s** | Bursts grouped, preliminary picks surfaced |
| **Time to Final Selection** | **30.68 s** | **350.33 s** | Full cull finalized |
| **Session Reopen Latency** | **0.089 s** | **0.084 s** | Reopening existing 1,500-photo shoot (< 2.0s target) |

### Real UI XCUITest Measurement (`WeddingCullUITests`)
* Folder Open → First Rendered Thumbnail: **8.71 s** (Measured in live GUI app)
* Folder Open → 24 Rendered Cells in Grid: **12.48 s** (Verified interactive before full analysis finishes)
* User Interactive Scroll Gesture: **2.39 s** (Smooth vertical scroll gesture executed and verified cleanly)

---

## 4. Microsecond Phase Breakdown

The table below breaks down the cumulative worker processing time across each pipeline phase for the 1,500-photo workload:

| Pipeline Phase | Apple Silicon Cumulative | Apple Silicon Per-Photo | Native Intel Cumulative (Winner) | Native Intel Per-Photo (Winner) | Native Intel 4-Worker Baseline |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Discovery & Metadata** | 0.60 s | - | 2.06 s | - | 2.64 s |
| **Preview Generation** | 12.62 s (cumulative) | 8.4 ms | 1.22 s (cumulative) | 0.8 ms | 27.94 s |
| **Technical Quality Scoring**| 9.10 s (cumulative) | 6.1 ms | 17.18 s (cumulative) | 11.5 ms | 16.64 s |
| **Face Detection & Landmarks** | 3.87 s (cumulative) | 2.6 ms | 132.33 s (cumulative) | 88.2 ms | 145.75 s |
| **FeaturePrint Generation** | 0.35 s (0.2 ms/p) | 0.2 ms | 8.38 s (5.6 ms/p) | 5.6 ms | 10.29 s |
| **Scene Classification** | 58.01 s (cumulative) | 38.7 ms | 518.33 s (cumulative) | 345.5 ms | 1,272.66 s |
| **Burst & Duplicate** | 0.48 s | - | 8.61 s | - | 10.54 s |
| **Temporal Segmentation** | 0.03 s | - | 0.08 s | - | 0.09 s |
| **Ranking & Diversity Selection** | 1.42 s (0.9 ms/p) | 0.9 ms | 2.54 s (1.7 ms/p) | 1.7 ms | 3.15 s |
| **Session Persistence Write** | 0.20 s | - | 0.10 s | - | 0.13 s |
| **Total Wall Clock Time** | **30.68 s** | 20.5 ms | **350.33 s** | 233.6 ms | **384.09 s** |

---

## 5. Intel Concurrency Analysis & Decoupled Architecture

### A. Global Concurrency Sweep (250 Photos)

Profiling revealed that `VNClassifyImageRequest` scaling on Intel x86_64 exhibits severe contention when worker count exceeds CPU core availability:

| Global Workers | Throughput (PPS) | Wall Clock (s) | Face Detection ms/p | Scene Classification ms/p | Peak Memory (MB) |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **1** | 3.06 | 81.33 s | 64.9 ms | **215.2 ms** | 190 MB |
| **2** | **4.53** | **54.91 s** | 73.9 ms | **299.6 ms** | 180 MB |
| **3** | 4.52 | 55.09 s | 76.7 ms | 499.0 ms | 189 MB |
| **4** | 4.09 | 60.84 s | 87.5 ms | **774.8 ms** | 186 MB |

> **Key Finding**: Increasing global workers from 1 to 4 balloons `VNClassifyImageRequest` from **215.2 ms** to **774.8 ms per photo** (3.6x slowdown) due to measured `VNClassifyImageRequest` contention/oversubscription on Intel CPUs without Neural Engine cores. 2 global workers produced the optimal balance.

### B. Decoupled Concurrency Matrix Sweep (Pipeline 2, 3, 4 × Classify Slots 1, 2)

To evaluate whether decoupling pipeline tasks (preview, quality, face) from scene classification could further reduce contention, we swept all 6 combinations on 150 test photos:

| Pipeline Workers | Classify Slots | Throughput (PPS) | Wall Clock (s) | Face ms/p | Scene ms/p | Category Agreement | Face Agreement |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 2 | 1 | 3.80 | 39.23 s | 94.4 ms | 370.0 ms | **100.0%** | **100.0%** |
| **2** | **2** | **4.62** | **32.27 s** | 83.0 ms | **314.6 ms** | **100.0%** | **100.0%** |
| 3 | 1 | 4.06 | 36.73 s | 92.3 ms | 595.8 ms | **100.0%** | **100.0%** |
| 3 | 2 | 3.70 | 40.27 s | 99.5 ms | 639.1 ms | **100.0%** | **100.0%** |
| 4 | 1 | 3.31 | 44.96 s | 117.7 ms | 1006.4 ms | **100.0%** | **100.0%** |
| 4 | 2 | 3.32 | 44.82 s | 117.4 ms | 1017.8 ms | **100.0%** | **100.0%** |

* **Winning Configuration**: **Pipeline 2 / Classify Slots 2** achieved **4.62 PPS** (32.27s).
* **Contention Evidence**: At 4 pipeline workers, Scene Classification ms/p exceeded **1,000 ms/photo**, confirming severe CPU oversubscription.
* **Semantic Invariance**: 100.0% category agreement and 100.0% face count agreement across all configurations.

### C. Full 1,500-Photo Scaling Verification

Scaling the configurations to the full 1,500-photo workload verified the gains:
* **4-Worker Baseline**: 3.91 PPS, 384.09s wall clock, 1,272.66s scene classification CPU time.
* **2-Worker Global Run**: 4.10 PPS, 364.70s wall clock, 514.97s scene classification CPU time (757s CPU time saved).
* **Winning Decoupled Configuration (2 Pipeline, 2 Classify Slots)**: **4.30 PPS**, **350.33s wall clock**, 518.33s scene classification CPU time (**+10.0% throughput increase**, **33.76 seconds faster wall clock**).

---

## 6. Key Bottlenecks Identified & Resolved

During baseline profiling and measured optimization passes, six major bottlenecks were identified and eliminated:

1. **Redundant Preview Disk Reloading**:
   * *Previous behavior*: `PreviewPipeline` generated a 1000px preview JPEG to disk, and `AnalysisPipeline.processItem` immediately re-opened the JPEG from disk and de-compressed it with ImageIO.
   * *Optimization*: `PreviewPipeline.generatePreviewAndThumbnailWithImage` returns the already decoded in-memory `CGImage`. `AnalysisPipeline` reuses this image directly, completely eliminating 1,500 redundant disk reads and JPEG decompressions.
2. **Double RAW Sensor Decode**:
   * *Previous behavior*: Creating the 320px thumbnail called ImageIO against the original source file a second time, triggering redundant parsing of large RAW/JPEG files.
   * *Optimization*: The 320px thumbnail is now downsampled directly from the in-memory 1000px preview via `CGBitmapContext` (< 0.5ms per image), never touching the full original file a second time.
3. **Dual-Pass Memory Traversal in Quality Analysis**:
   * *Previous behavior*: Sharpness (Laplacian kernel) and composition (Rule of Thirds energy) executed two separate nested loops over the 800px grayscale buffer.
   * *Optimization*: Unified both passes into a single scan over `grayBuffer`, cutting memory bus traffic and cache misses in half.
4. **DiversitySelector Redundant All-Pairs Similarity Scans**:
   * *Previous behavior*: Each iteration over candidate photos recomputed cosine similarity against every previously selected photo, yielding O(K^2 * N) complexity.
   * *Optimization*: Maintained incremental maximum similarity scores and cached segment-cap availability per candidate, reducing complexity to O(K * N).
   * *Measured Result*: Intel execution dropped from **132.39s to 2.54s** (52x speedup, 98.1% reduction); ARM64 dropped from **43.13s to 1.42s** (30x speedup). Deterministic selected photo IDs remained 100% byte-identical.
5. **Eager FeaturePrint Generation on All Images**:
   * *Previous behavior*: `VNGenerateImageFeaturePrintRequest` was executed eagerly for every single photo during worker processing, taking 782.2 ms/photo (1,172.53s total) on Intel.
   * *Optimization*: Implemented lazy FeaturePrint evaluation. FeaturePrints are generated only on candidate pairs that are temporally close (<= 4.0s), not from identical camera bursts, and whose dHash perceptual similarity falls in the ambiguous threshold (< 0.85).
   * *Measured Result*: Intel FeaturePrint time plummeted from **1,172.53s (782.2 ms/p) to 8.38s (5.6 ms/p)** — an exact **99.3% measured reduction**, driving Intel wall-clock time down from 695s to 350.33s (+98% throughput gain). Eager vs lazy equivalence verified with 100% matching burst groups and winners.
6. **Intel Scene Classification Contention / Oversubscription**:
   * *Diagnosed behavior*: On Intel CPUs without Apple Neural Engine hardware, concurrent execution of `VNClassifyImageRequest` across 4 worker threads caused measured contention and thread oversubscription, inflating inference latency from **215.2 ms/photo** (at 1 worker) to **774.8 ms/photo** (at 4 workers).
   * *Decoupled Solution*: Decoupled pipeline concurrency (preview decode, technical quality, and face detection) from `VNClassifyImageRequest` concurrency slots via semaphore gating, keeping scene classification execution at measured optimal density.

---

## 7. Real Dataset & Camera RAW Compatibility

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
* **Total Execution Time**: **13.98 seconds**
* **Metrics**:
  * **Mean F1**: **38.4%**
  * **Mean Precision / Recall**: **38.4%**
  * **Mean Event Coverage**: **88.5%**
  * **Mean Jaccard Index**: **26.8%**
  * **Mean Spearman rho**: **+0.081**
* *Status*: Photographic selection algorithm is frozen as a reference baseline; results serve as regression controls.

### MobileCLIP Zero-Shot Classifier

* **Model**: Apple MobileCLIP-S0 (`models/mobileclip_s0_image.mlmodelc`)
* **Compute Units**: All (Apple Neural Engine + GPU + CPU)
* **Output Embedding Dimension**: 512
* **Average Inference Latency**: **167.5 ms / photo**
* **Zero-Shot Verdict**: **PASS** (Zero fallback required)

---

## 8. Machine-Readable Artifact Index

All metrics in this report are verifiable via the generated machine-readable artifacts stored in `docs/`:

* `docs/baseline-arm64-release.json`: Master Apple Silicon benchmark results (48.9 – 53.0 PPS).
* `docs/baseline-phase-timings-arm64.json`: Apple Silicon phase timings and perceived speed metrics.
* `docs/baseline-intel-release.json`: Master Native Intel x86_64 benchmark results (4.30 PPS winning decoupled config).
* `docs/baseline-phase-timings-intel.json`: Native Intel phase timings for winning decoupled config.
* `docs/benchmark-intel-2workers.json`: Native Intel full 1,500-photo benchmark with 2 global workers (4.10 PPS).
* `docs/concurrency-sweep-intel.json`: Intel worker sweep (1, 2, 3, 4 workers) with face and scene breakdown.
* `docs/classify-matrix-sweep-intel.json`: Decoupled concurrency matrix sweep (Pipeline 2,3,4 × Classify 1,2).
* `docs/release-validation-report.json`: Consolidated master release validation JSON.
* `docs/RELEASE_VALIDATION_REPORT.md`: Consolidated master release validation Markdown.
