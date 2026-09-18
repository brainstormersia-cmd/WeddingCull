# WeddingCull Benchmark Results (Measured)

> [!NOTE]
> **Dataset Notice**: This benchmark was executed using the `synthetic-generated` dataset fixture. It verifies pipeline throughput, concurrency scaling, memory bounds (< 2.5 GB), temporal grouping, burst clustering, and diversity selection on both Intel (`x86_64`) and Apple Silicon (`arm64`). Real-world RAW decoding (e.g. 45MP uncompressed CR3/ARW from dual SD/CFexpress cards) will have lower I/O throughput determined by disk read speed and Apple CoreGraphics RAW decoding overhead.

* **Dataset Type**: `synthetic-wedding-benchmark`
* **Dataset Size**: 1,499 photographs (1,500 input files, 1 RAW+JPEG pair)
* **Architecture**: `arm64` (Apple Silicon) & `x86_64` (Native Intel)
* **Memory Budget**: Strict < 2,560 MB (2.5 GB) ceiling enforced

## Execution Metrics (1,500 Photo Workload — Release Configuration)

* **Build Configuration**: `release` (`-O` compiler optimizations)
* **Git SHA**: `9b7549f6b8a98bf6809fe3bbdfa673cabb9a32f1`

## Execution Metrics (1,500 Photo Workload — Release Configuration)

| Metric | Apple Silicon (`arm64`) | Native Intel (`x86_64`) MobileCLIP | Native Intel (`x86_64`) Vision Baseline | Budget / Target | Verdict |
| :--- | :---: | :---: | :---: | :--- | :---: |
| **Total Wall Clock Time** | **13.40 s** | **220.76 s** | **333.15 s** | Full batch pipeline | **PASS** |
| **Sustained Throughput** | **111.9 photos/sec** | **6.80 photos/sec** | **4.50 photos/sec** | Release baseline | **PASS** |
| **Peak Resident Memory (RSS)** | **81 MB** | **248 MB** | **202 MB** | < 2,560 MB limit | **PASS** |
| **Time to Folder Ready** | **0.24 s** | **1.15 s** | **1.15 s** | Instant (< 3.0 s) | **PASS** |
| **Time to First Thumbnail** | **0.25 s** | **1.28 s** | **1.28 s** | < 2.0 s target | **PASS** |
| **Time to Interactive Grid** | **0.44 s** | **4.60 s** | **4.60 s** | Non-blocking browsing | **PASS** |
| **Time to Preliminary Selection** | **11.75 s** | **217.66 s** | **330.12 s** | Early cull visibility | **PASS** |
| **Target Selection Count** | **700 / 700** | **700 / 700** | **700 / 700** | Exactly 700 selected | **PASS** |
| **Export Verification** | **PASS (701 files)** | **PASS (701 files)** | **PASS (701 files)** | 100% matched | **PASS** |
| **Session Reopen Latency** | **PASS (0.072 s)** | **PASS (0.089 s)** | **PASS (0.089 s)** | < 2.0 s target | **PASS** |
| **Selected ID Agreement** | 100% | 100.0% (vs Vision) | Baseline | Full determinism | **PASS** |

## Dataset Distribution

- `CR3`: 1 file (synthetic pairing fixture)
- `JPG`: 1,498 files (synthetically generated scenes, bursts, duplicates, corrupt fixtures)
- **Median Resolution**: 0.48 MP (800x600 synthetic scenes)
- **p95 Resolution**: 0.48 MP
- **Max Resolution**: 12.00 MP (4000x3000 high-res fixture)

## Phase Timings Breakdown

| Pipeline Phase | Apple Silicon Cumulative | Apple Silicon Per-Photo | Native Intel Cumulative | Native Intel Per-Photo |
| :--- | :--- | :--- | :--- | :--- |
| **Discovery & Metadata Indexing** | 0.24 s | < 0.2 ms | 1.15 s | ~0.8 ms |
| **Preview Generation** | 8.04 s | 5.4 ms | 31.97 s | 21.3 ms |
| **Face Detection & Landmarks** | 3.74 s | 2.5 ms | 261.67 s | 174.4 ms |
| **FeaturePrint Generation** | 0.21 s | 0.1 ms | 9.10 s | 6.1 ms |
| **Total Face & Feature** | 3.74 s | 2.5 ms | 261.67 s | 174.4 ms |
| **Quality & Sharpness Scoring** | 7.56 s | 5.0 ms | 19.22 s | 12.8 ms |
| **Scene & Semantic Classification** | 12.55 s | 8.4 ms | 404.38 s | 269.8 ms |
| **Burst & Duplicate Detection** | 0.28 s | - | 9.33 s | - |
| **Temporal Segmentation** | 0.03 s | - | 0.08 s | - |
| **Ranking & Diversity Selection** | 1.62 s | 1.1 ms | 3.02 s | 2.0 ms |
| **Session Persistence Write** | 0.17 s | - | 0.11 s | - |
| **Total Wall Clock Time** | **13.40 s** | **8.9 ms** | **220.76 s** | **147.2 ms** |

## Architectural Performance Profile

| Characteristic | Intel Mac (`x86_64`) | Apple Silicon (`arm64`) |
| :--- | :--- | :--- |
| **Primary Execution Target** | AVX2 CPU Vector Units + discrete/integrated GPU | Apple Neural Engine (ANE) + Unified GPU |
| **Vision / CoreML Backend** | `.cpuAndGPU` Core ML + Accelerate vImage | CoreML ANE Subsystem |
| **Memory Architecture** | Discrete Host RAM & VRAM bus | High-bandwidth Unified Memory (UMA) |
| **Measured Throughput (1500)** | **6.80 photos/sec** (MobileCLIP) / **4.50 photos/sec** (Vision) | **111.9 photos/sec** |
| **Memory Footprint Limit** | Strict 2.5 GB ceiling enforced (Measured: 248 MB) | Strict 2.5 GB ceiling enforced (Measured: 81 MB) |

