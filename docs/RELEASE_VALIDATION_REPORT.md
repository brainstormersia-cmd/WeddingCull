# WeddingCull Final Release Dataset Validation Report

* **Git Commit**: `dcf08818159a3e7eacf1983b821b23efb1399c3f`
* **Generated At**: `2026-09-18T09:03:42.391152+00:00`
* **Overall Verdict**: **PASS**

## Release Performance Baseline

* **BASELINE_RELEASE_ARM64**: 48.9 PPS, 82 MB RSS, 30.68s wall clock (Release build, Apple Silicon)
* **BASELINE_RELEASE_INTEL**: 4.3 PPS, 183 MB RSS, 350.33s wall clock (Release build, Native Intel)

## Subsystem Validation Matrix

| Subsystem / Benchmark | Status | Details |
| :--- | :--- | :--- |
| **Apple Silicon (arm64) 1500->700** | **EXECUTED** | 48.9 PPS, 82 MB RSS (release) |
| **Native Intel (x86_64) 1500->700** | **EXECUTED** | 4.3 PPS, 183 MB RSS (release) |
| **AlbumBench Real Wedding Dataset** | **EXECUTED / REGRESSION REFERENCE** | 8 albums (274 photos), F1=38.4%, Time=14.0s (Photographic tuning frozen; regression reference) |
| **Strict Real Camera RAWs** | **EXECUTED** | ARW: PASS, CR2: PASS, NEF: PASS, RAF: UNSUPPORTED |
| **MobileCLIP Core ML Model** | **EXECUTED** | MobileCLIP-S0, Latency=167.5ms |
| **Public IQA Benchmark Framework** | **NOT_VERIFIED_IN_PUBLIC_CI** | Dataset directory not supplied or not present on public CI runner. To evaluate locally: download SPAQ dataset and run with --dataset-dir <PATH> |

## Pipeline Readiness, UI Interactivity & Session Reopen

| Milestone / SLA | Apple Silicon (arm64) | Native Intel (x86_64) | Design Target |
| :--- | :---: | :---: | :--- |
| **Time to Folder Ready (metadata)** | 0.6 s | 2.06 s | Instant metadata & placeholder cards |
| **Time to First Thumbnail (rendered)** | 0.63 s | 2.07 s | Progressive first-page rendering |
| **Time to Interactive Grid (24 cells)** | 0.78 s | 2.08 s | Immediate non-blocking browsing |
| **Time to First Analyzed Photo** | 0.81 s | 2.61 s | Incremental vision stream |
| **Time to Preliminary Selection** | 29.23 s | 347.71 s | Early cull visibility |
| **Time to Final Selection** | 30.68 s | 350.33 s | Full cull finalized |
| **Session Reopen Latency (1,500 photos)** | **0.089 s** | **0.084 s** | **< 2.0s Target** |

## Native Intel Decoupled Concurrency Matrix Sweep (Pipeline Workers x Classify Slots)

> Evaluates decoupling global pipeline concurrency (preview/quality/face) from `VNClassifyImageRequest` concurrency to reduce measured contention/oversubscription on Intel CPUs.

| Pipeline Workers | Classify Slots | Wall Clock (s) | Throughput (PPS) | Scene Classify (ms/p) | Face Detect (ms/p) | Cat Agr % | IDs Match |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 2 | 1 | 39.23s | **3.80 PPS** | 370.0 ms | 94.4 ms | 100.0% | YES |
| 2 | 2 | 32.27s | **4.62 PPS** | 314.6 ms | 83.0 ms | 100.0% | NO |
| 3 | 1 | 36.73s | **4.06 PPS** | 595.8 ms | 92.3 ms | 100.0% | NO |
| 3 | 2 | 40.27s | **3.70 PPS** | 639.1 ms | 99.5 ms | 100.0% | NO |
| 4 | 1 | 44.96s | **3.31 PPS** | 1006.4 ms | 117.7 ms | 100.0% | NO |
| 4 | 2 | 44.82s | **3.32 PPS** | 1017.8 ms | 117.4 ms | 100.0% | NO |

## Native Intel 1,500-Photo Scaling Comparison

| Configuration | Photos | Wall Clock (s) | Throughput (PPS) | Scene Classify Total | Peak RSS (MB) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| 4 Global Workers (Baseline) | 1,500 | 384.09s | 3.91 PPS | 1,272.66s | 214 MB |
| 2 Global Workers (Full Run) | 1499 | 364.70s | **4.10 PPS** | 514.97s | 203 MB |
| Winning Configuration (P:2, C:2) | 1499 | 350.33s | **4.30 PPS** | 518.33s | 183 MB |

## Native Intel Concurrency Sweep (x86_64)

| Workers | Wall Clock (s) | Throughput (PPS) | Peak RSS (MB) | Face Detection (ms/photo) | FeaturePrint (ms/photo) | Scene Classify (ms/photo) | Diversity Selection (s) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 1 | 81.33s | **3.06 PPS** | 190 MB | 64.9 ms | 16.8 ms | 215.2 ms | 0.07s |
| 2 | 54.91s | **4.53 PPS** | 180 MB | 73.9 ms | 24.7 ms | 299.6 ms | 0.08s |
| 3 | 55.09s | **4.52 PPS** | 189 MB | 76.7 ms | 22.1 ms | 499.0 ms | 0.09s |
| 4 | 60.84s | **4.09 PPS** | 186 MB | 87.5 ms | 21.8 ms | 774.8 ms | 0.09s |

## Apple Silicon Concurrency Sweep (arm64)

| Workers | Wall Clock (s) | Throughput (PPS) | Peak RSS (MB) | Face Detection (ms/photo) | FeaturePrint (ms/photo) | Scene Classify (ms/photo) | Diversity Selection (s) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 1 | 4.48s | **55.62 PPS** | 71 MB | 2.2 ms | 0.3 ms | 4.1 ms | 0.04s |
| 2 | 2.28s | **109.39 PPS** | 68 MB | 3.8 ms | 0.4 ms | 5.0 ms | 0.03s |
| 3 | 3.53s | **70.59 PPS** | 59 MB | 5.2 ms | 0.4 ms | 25.9 ms | 0.03s |
| 4 | 4.07s | **61.17 PPS** | 61 MB | 4.7 ms | 0.3 ms | 44.6 ms | 0.03s |

## Apple Silicon Vision Configurations & Resolution Sweep (arm64)

| Configuration | Mode | Face (px) | Scene (px) | Wall Clock (s) | Throughput (PPS) | Face (ms/photo) | Face Agr % | Scene (ms/photo) | Scene Agr % |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Separate (1000px, Eager FP) | separate | 1000 | 1000 | 3.08s | **48.35 PPS** | 6.3 ms | 100.0% | 19.0 ms | 100.0% |
| Separate (1000px, Lazy FP) [Baseline] | separate | 1000 | 1000 | 2.91s | **51.15 PPS** | 4.2 ms | 100.0% | 42.7 ms | 100.0% |
| Combined perform() (1000px, Lazy FP) | combined | 1000 | 1000 | 3.83s | **38.94 PPS** | 31.5 ms | 100.0% | 31.5 ms | 100.0% |
| Scene 800px (Face 1000px, Lazy FP) | separate | 1000 | 800 | 2.92s | **51.04 PPS** | 4.2 ms | 100.0% | 43.4 ms | 100.0% |
| Scene 640px (Face 1000px, Lazy FP) | separate | 1000 | 640 | 3.01s | **49.48 PPS** | 4.2 ms | 100.0% | 40.6 ms | 100.0% |
| Face 800px (Scene 1000px, Lazy FP) | separate | 800 | 1000 | 2.98s | **50.02 PPS** | 4.6 ms | 100.0% | 43.8 ms | 100.0% |
| Face 640px (Scene 1000px, Lazy FP) | separate | 640 | 1000 | 3.02s | **49.29 PPS** | 2.8 ms | 100.0% | 43.2 ms | 100.0% |
| Combined (800px, Lazy FP) | combined | 800 | 800 | 3.16s | **47.13 PPS** | 26.0 ms | 100.0% | 26.2 ms | 100.0% |
| Combined (640px, Lazy FP) | combined | 640 | 640 | 2.94s | **50.73 PPS** | 3.2 ms | 100.0% | 39.1 ms | 100.0% |

## Comparative Phase Timings Breakdown

| Pipeline Phase | Apple Silicon Cumulative | Apple Silicon Per-Photo | Native Intel Cumulative | Native Intel Per-Photo |
| :--- | :--- | :--- | :--- | :--- |
| **Discovery & Metadata** | 0.60s | - | 2.06s | - |
| **Preview Generation** | 12.62s | 8.4 ms | 1.22s | 0.8 ms |
| **Face Detection & Landmarks** | 3.87s | 2.6 ms | 132.33s | 88.2 ms |
| **FeaturePrint Generation** | 0.35s | 0.2 ms | 8.38s | 5.6 ms |
| **Total Face & Feature** | 3.87s | 2.6 ms | 132.33s | 88.2 ms |
| **Quality Scoring** | 9.10s | 6.1 ms | 17.18s | 11.5 ms |
| **Scene Classification** | 58.01s | 38.7 ms | 518.33s | 345.6 ms |
| **Burst & Duplicate** | 0.48s | - | 8.61s | - |
| **Temporal Segmentation** | 0.03s | - | 0.08s | - |
| **Ranking & Diversity Selection** | 1.42s | 0.9 ms | 2.54s | 1.7 ms |
| **Session Persistence Write** | 0.20s | - | 0.10s | - |
| **Total Wall Clock Time** | 30.68s | 20.5 ms | 350.33s | 233.6 ms |
