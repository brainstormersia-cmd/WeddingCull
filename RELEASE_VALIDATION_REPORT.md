# WeddingCull Final Release Dataset Validation Report

* **Git Commit**: `9b7549f6b8a98bf6809fe3bbdfa673cabb9a32f1`
* **Generated At**: `2026-09-18T20:55:50.566346+00:00`
* **Overall Verdict**: **PASS**

## Release Performance Baseline

* **BASELINE_RELEASE_ARM64**: 111.9 PPS, 81 MB RSS, 13.4s wall clock (Release build, Apple Silicon)
* **BASELINE_RELEASE_INTEL**: 6.8 PPS, 248 MB RSS, 220.76s wall clock (Release build, Native Intel)

## Subsystem Validation Matrix

| Subsystem / Benchmark | Status | Details |
| :--- | :--- | :--- |
| **Apple Silicon (arm64) 1500->700** | **EXECUTED** | 111.9 PPS, 81 MB RSS (release) |
| **Native Intel (x86_64) 1500->700** | **EXECUTED** | 6.8 PPS, 248 MB RSS (release) |
| **AlbumBench Real Wedding Dataset** | **EXECUTED / REGRESSION REFERENCE** | 8 albums (274 photos), F1=38.5%, Time=13.3s (Photographic tuning frozen; regression reference) |
| **Strict Real Camera RAWs** | **EXECUTED** | ARW: PASS, CR2: PASS, NEF: PASS, RAF: UNSUPPORTED |
| **MobileCLIP Core ML Model** | **EXECUTED** | MobileCLIP-S0, Latency=137.3ms |
| **Public IQA Benchmark Framework** | **NOT_VERIFIED_IN_PUBLIC_CI** | Dataset directory not supplied or not present on public CI runner. To evaluate locally: download SPAQ dataset and run with --dataset-dir <PATH> |

## Pipeline Readiness, UI Interactivity & Session Reopen

| Milestone / SLA | Apple Silicon (arm64) | Native Intel (x86_64) | Design Target |
| :--- | :---: | :---: | :--- |
| **Time to Folder Ready (metadata)** | 0.24 s | 1.15 s | Instant metadata & placeholder cards |
| **Time to First Thumbnail (rendered)** | 0.25 s | 1.28 s | Progressive first-page rendering |
| **Time to Interactive Grid (24 cells)** | 0.44 s | 4.6 s | Immediate non-blocking browsing |
| **Time to First Analyzed Photo** | 0.28 s | 1.96 s | Incremental vision stream |
| **Time to Preliminary Selection** | 11.75 s | 217.66 s | Early cull visibility |
| **Time to Final Selection** | 13.4 s | 220.76 s | Full cull finalized |
| **Session Reopen Latency (1,500 photos)** | **0.072 s** | **0.089 s** | **< 2.0s Target** |

## Native Intel Decoupled Concurrency Matrix Sweep (Pipeline Workers x Classify Slots)

> Evaluates decoupling global pipeline concurrency (preview/quality/face) from `VNClassifyImageRequest` concurrency to reduce measured contention/oversubscription on Intel CPUs.

| Pipeline Workers | Classify Slots | Wall Clock (s) | Throughput (PPS) | Scene Classify (ms/p) | Face Detect (ms/p) | Cat Agr % | IDs Match |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 2 | 1 | 39.53s | **3.77 PPS** | 251.3 ms | 94.6 ms | 100.0% | YES |
| 2 | 2 | 41.97s | **3.55 PPS** | 392.8 ms | 106.0 ms | 100.0% | YES |
| 3 | 1 | 48.70s | **3.06 PPS** | 312.9 ms | 122.3 ms | 100.0% | YES |
| 3 | 2 | 38.65s | **3.86 PPS** | 494.8 ms | 102.1 ms | 100.0% | YES |
| 4 | 1 | 38.37s | **3.88 PPS** | 244.8 ms | 95.4 ms | 100.0% | YES |
| 4 | 2 | 33.55s | **4.44 PPS** | 423.6 ms | 87.4 ms | 100.0% | YES |

## Pipeline Determinism & Reproducibility Diagnostics

> Verifies identical cold-start determinism, warm-cache reload consistency, decoupled concurrency slot invariance, and quantifies lossy preview JPEG impact.

### Native Intel (x86_64)

| Comparison | Selected IDs Match | Cat Agr % | Face Agr % | Burst Winners | Max Score Diff | Byte-Identical? |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| Cold 1 vs Cold 2 (Identical 2/2) | YES ✅ | 100.0% | 100.0% | MATCH ✅ | 0.00000 | YES ✅ |
| Warm 1 vs Warm 2 (Identical 2/2) | YES ✅ | 100.0% | 100.0% | MATCH ✅ | 0.00000 | YES ✅ |
| Cold (2, 1) vs Cold (2, 2) | YES ✅ | 100.0% | 100.0% | MATCH ✅ | 0.00000 | YES ✅ |
| Cold 1 vs Warm 2 (Cold vs Warm) | YES ✅ | 100.0% | 100.0% | MATCH ✅ | 0.00000 | YES ✅ |

### Apple Silicon (arm64)

| Comparison | Selected IDs Match | Cat Agr % | Face Agr % | Burst Winners | Max Score Diff | Byte-Identical? |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| Cold 1 vs Cold 2 (Identical 2/2) | YES ✅ | 100.0% | 100.0% | MATCH ✅ | 0.00000 | YES ✅ |
| Warm 1 vs Warm 2 (Identical 2/2) | YES ✅ | 100.0% | 100.0% | MATCH ✅ | 0.00000 | YES ✅ |
| Cold (2, 1) vs Cold (2, 2) | YES ✅ | 100.0% | 100.0% | MATCH ✅ | 0.00000 | YES ✅ |
| Cold 1 vs Warm 2 (Cold vs Warm) | YES ✅ | 100.0% | 100.0% | MATCH ✅ | 0.00000 | YES ✅ |


## Native Intel Two-Stage Pipeline Sweep (Producer-Consumer Backpressure)

> Benchmarks decoupled producer (Stage A: preview/quality/face) and consumer (Stage B: scene classification) with bounded backpressure channels.

| Configuration | Wall Clock (s) | Throughput (PPS) | Peak RSS (MB) | Scene Classify (ms/p) | Face Detect (ms/p) | IDs Match |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| Stage A: 2 / Stage B: 1 / Queue: 8 | 32.52s | **4.58 PPS** | 223 MB | 206.2 ms | 83.5 ms | YES |
| Stage A: 2 / Stage B: 2 / Queue: 8 | 30.74s | **4.85 PPS** | 225 MB | 390.5 ms | 81.4 ms | YES |
| Stage A: 3 / Stage B: 1 / Queue: 8 | 31.46s | **4.74 PPS** | 215 MB | 200.6 ms | 87.7 ms | YES |
| Stage A: 3 / Stage B: 2 / Queue: 8 | 30.65s | **4.86 PPS** | 223 MB | 386.4 ms | 89.7 ms | YES |
| Stage A: 4 / Stage B: 1 / Queue: 8 | 32.40s | **4.60 PPS** | 226 MB | 205.8 ms | 97.4 ms | YES |
| Stage A: 4 / Stage B: 2 / Queue: 8 | 31.92s | **4.67 PPS** | 227 MB | 405.9 ms | 102.4 ms | YES |
| Stage A: 2 / Stage B: 2 / Queue: 4 | 36.21s | **4.12 PPS** | 213 MB | 461.1 ms | 92.9 ms | YES |
| Stage A: 2 / Stage B: 2 / Queue: 16 | 32.93s | **4.52 PPS** | 242 MB | 418.4 ms | 102.8 ms | YES |
| Stage A: 3 / Stage B: 2 / Queue: 4 | 32.11s | **4.64 PPS** | 215 MB | 395.8 ms | 85.8 ms | YES |
| Stage A: 3 / Stage B: 2 / Queue: 16 | 36.97s | **4.03 PPS** | 246 MB | 469.9 ms | 112.8 ms | YES |

## Explicit Native Intel 1,500-Photo Backend Comparison

> Full 1,500-photo runs comparing Apple Vision (`VNClassifyImageRequest`) vs MobileCLIP-S0 Core ML (`.cpuAndGPU`).

| Backend | Model Loaded | Wall Clock (s) | Throughput (PPS) | Scene Classify (ms/p) | Peak RSS (MB) | Selected ID Agreement |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Apple Vision** | No (System Framework) | 333.15s | **4.50 PPS** | 424.7 ms | 202 MB | Baseline |
| **MobileCLIP-S0 (Core ML)** | Yes (`.cpuAndGPU`) | 220.76s | **6.80 PPS** | 269.8 ms | 248 MB | 100.0% |

## Native Intel MobileCLIP-S0 Core ML Benchmark (.cpuAndGPU)

* **Backend Confirmed**: `MobileCLIP-S0`
* **Wall-clock Time**: 220.76s
* **Throughput**: **6.8 PPS**
* **Peak Memory**: 248 MB

## Native Intel 1,500-Photo Scaling Comparison

| Configuration | Photos | Wall Clock (s) | Throughput (PPS) | Scene Classify Total | Peak RSS (MB) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| 4 Global Workers (Baseline) | 1,500 | 384.09s | 3.91 PPS | 1,272.66s | 214 MB |
| 2 Global Workers (Full Run) | 1499 | 260.44s | **5.80 PPS** | 203.00s | 258 MB |
| Winning Configuration (P:4, C:2) | 1499 | 220.76s | **6.80 PPS** | 404.38s | 248 MB |

## Native Intel Concurrency Sweep (x86_64)

| Workers | Wall Clock (s) | Throughput (PPS) | Peak RSS (MB) | Face Detection (ms/photo) | FeaturePrint (ms/photo) | Scene Classify (ms/photo) | Diversity Selection (s) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 1 | 91.14s | **2.73 PPS** | 180 MB | 75.1 ms | 21.0 ms | 239.4 ms | 0.10s |
| 2 | 5.78s | **43.08 PPS** | 181 MB | 0.0 ms | 21.6 ms | 0.0 ms | 0.12s |
| 3 | 5.30s | **47.00 PPS** | 182 MB | 0.0 ms | 19.8 ms | 0.0 ms | 0.10s |
| 4 | 4.86s | **51.26 PPS** | 182 MB | 0.0 ms | 18.2 ms | 0.0 ms | 0.09s |

## Apple Silicon Concurrency Sweep (arm64)

| Workers | Wall Clock (s) | Throughput (PPS) | Peak RSS (MB) | Face Detection (ms/photo) | FeaturePrint (ms/photo) | Scene Classify (ms/photo) | Diversity Selection (s) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 1 | 4.13s | **60.22 PPS** | 71 MB | 1.8 ms | 0.4 ms | 3.6 ms | 0.04s |
| 2 | 0.19s | **1299.39 PPS** | 69 MB | 0.0 ms | 0.2 ms | 0.0 ms | 0.04s |
| 3 | 0.18s | **1368.62 PPS** | 71 MB | 0.0 ms | 0.3 ms | 0.0 ms | 0.04s |
| 4 | 0.17s | **1499.70 PPS** | 70 MB | 0.0 ms | 0.2 ms | 0.0 ms | 0.04s |

## Comparative Phase Timings Breakdown

| Pipeline Phase | Apple Silicon Cumulative | Apple Silicon Per-Photo | Native Intel Cumulative | Native Intel Per-Photo |
| :--- | :--- | :--- | :--- | :--- |
| **Discovery & Metadata** | 0.24s | - | 1.15s | - |
| **Preview Generation** | 8.04s | 5.4 ms | 31.97s | 21.3 ms |
| **Face Detection & Landmarks** | 3.74s | 2.5 ms | 261.67s | 174.4 ms |
| **FeaturePrint Generation** | 0.21s | 0.1 ms | 9.10s | 6.1 ms |
| **Total Face & Feature** | 3.74s | 2.5 ms | 261.67s | 174.4 ms |
| **Quality Scoring** | 7.56s | 5.0 ms | 19.22s | 12.8 ms |
| **Scene Classification** | 12.55s | 8.4 ms | 404.38s | 269.6 ms |
| **Burst & Duplicate** | 0.28s | - | 9.33s | - |
| **Temporal Segmentation** | 0.03s | - | 0.08s | - |
| **Ranking & Diversity Selection** | 1.62s | 1.1 ms | 3.02s | 2.0 ms |
| **Session Persistence Write** | 0.17s | - | 0.11s | - |
| **Total Wall Clock Time** | 13.40s | 8.9 ms | 220.76s | 147.2 ms |
