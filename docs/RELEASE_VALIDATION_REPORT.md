# WeddingCull Final Dataset Validation Report

* **Git Commit**: `aa751bea14c73b9809996dbcb7fed41670e50b5a`
* **Generated At**: `2026-09-17T22:31:22.271999+00:00`
* **Overall Verdict**: **PASS**

## Subsystem Audit Matrix

| Subsystem / Benchmark | Status | Details |
| :--- | :--- | :--- |
| **Apple Silicon (arm64) 1500→700** | **EXECUTED** | 2.6 PPS, 60 MB RSS |
| **Native Intel (x86_64) 1500→700** | **EXECUTED** | 1.4 PPS, 209 MB RSS |
| **AlbumBench Real Wedding Dataset** | **EXECUTED** | 8 albums (274 photos), F1=39.2% |
| **Strict Real Camera RAWs** | **EXECUTED** | Canon CR2, Nikon NEF, Sony ARW, Fuji RAF (3/4 passed) |
| **MobileCLIP Core ML Model** | **EXECUTED** | MobileCLIP-S0, Latency=161.0ms |
| **Public IQA Benchmark Framework** | **NOT_VERIFIED_IN_PUBLIC_CI** | Dataset directory not supplied or not present on public CI runner. To evaluate locally: download SPAQ dataset and run with --dataset-dir <PATH> |
