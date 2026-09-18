# WeddingCull Final Release Dataset Validation Report

* **Git Commit**: `cacf4c6010b4a238480a15553061469c07f11769`
* **Generated At**: `2026-09-18T00:14:46.188939+00:00`
* **Overall Verdict**: **PASS**

## Release Performance Baseline

* **BASELINE_RELEASE_ARM64**: 18.7 PPS, 61 MB RSS, 80.36s wall clock (Release build, Apple Silicon)
* **BASELINE_RELEASE_INTEL**: 3.1 PPS, 205 MB RSS, 488.02s wall clock (Release build, Native Intel)

## Subsystem Validation Matrix

| Subsystem / Benchmark | Status | Details |
| :--- | :--- | :--- |
| **Apple Silicon (arm64) 1500->700** | **EXECUTED** | 18.7 PPS, 61 MB RSS (release) |
| **Native Intel (x86_64) 1500->700** | **EXECUTED** | 3.1 PPS, 205 MB RSS (release) |
| **AlbumBench Real Wedding Dataset** | **EXECUTED / REGRESSION REFERENCE** | 8 albums (274 photos), F1=38.5%, Time=7.3s (Photographic tuning frozen; regression reference) |
| **Strict Real Camera RAWs** | **EXECUTED** | ARW: PASS, CR2: PASS, NEF: PASS, RAF: UNSUPPORTED |
| **MobileCLIP Core ML Model** | **EXECUTED** | MobileCLIP-S0, Latency=202.1ms |
| **Public IQA Benchmark Framework** | **NOT_VERIFIED_IN_PUBLIC_CI** | Dataset directory not supplied or not present on public CI runner. To evaluate locally: download SPAQ dataset and run with --dataset-dir <PATH> |
