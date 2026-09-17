# WeddingCull Benchmark Results (Measured)

> [!NOTE]
> **Dataset Notice**: This benchmark was executed using the `synthetic-generated` dataset fixture. It verifies pipeline throughput, concurrency scaling, memory bounds (< 2.5 GB), temporal grouping, burst clustering, and diversity selection on both Intel (`x86_64`) and Apple Silicon (`arm64`). Real-world RAW decoding (e.g. 45MP uncompressed CR3/ARW from dual SD/CFexpress cards) will have lower I/O throughput determined by disk read speed and Apple CoreGraphics RAW decoding overhead.

* **Dataset Type**: `synthetic-wedding-benchmark`
* **Dataset Size**: 1,499 photographs (1,500 input files, 1 RAW+JPEG pair)
* **Architecture**: `arm64` (Apple Silicon) & `x86_64` (Native Intel)
* **Memory Budget**: Strict < 2,560 MB (2.5 GB) ceiling enforced

## Execution Metrics (1,500 Photo Workload)

| Metric | Apple Silicon (`arm64`) | Native Intel (`x86_64`) | Budget / Target |
| :--- | :--- | :--- | :--- |
| **Total Processing Time** | 566.77 s | 1085.33 s | Sustained batch run |
| **Sustained Throughput** | **2.6 photos/sec** | **1.4 photos/sec** | > 1.0 photos/sec |
| **Peak Resident Memory (RSS)** | **60 MB** | **209 MB** | < 2560 MB limit (PASS) |
| **Burst Groups Identified** | 5 groups | 5 groups | Verified |
| **Person Identity Clusters** | 2 clusters | 2 clusters | Verified |
| **Target Selection Count** | 700 / 700 | 700 / 700 | Met |
| **Session Persistence** | Verified | Verified | Saved & Reloaded |
| **Export Verification** | Verified | Verified | Exact count & sidecars |

## Dataset Distribution

- `CR3`: 1 file (synthetic pairing fixture)
- `JPG`: 1,498 files (synthetically generated scenes, bursts, duplicates, corrupt fixtures)
- **Min Resolution**: 0.48 MP (800x600 synthetic scenes)
- **Median Resolution**: 0.48 MP
- **Max Resolution**: 12.00 MP (4000x3000 high-res fixture)

## Architectural Performance Profile

| Characteristic | Intel Mac (`x86_64`) | Apple Silicon (`arm64`) |
| :--- | :--- | :--- |
| **Primary Execution Target** | AVX2 CPU Vector Units + discrete/integrated GPU | Apple Neural Engine (ANE) + Unified GPU |
| **Vision / CoreML Backend** | Accelerate vImage / CPU fallback | CoreML ANE Subsystem |
| **Memory Architecture** | Discrete Host RAM & VRAM bus | High-bandwidth Unified Memory (UMA) |
| **Target Throughput (1500)** | ~2-5 photos/sec | ~10-25 photos/sec |
| **Memory Footprint Limit** | Strict 2.5 GB ceiling enforced | Strict 2.5 GB ceiling enforced |

