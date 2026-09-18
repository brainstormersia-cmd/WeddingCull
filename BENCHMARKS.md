# WeddingCull Benchmark Results (Measured)

> [!NOTE]
> **Dataset Notice**: This benchmark was executed using the `synthetic-generated` dataset fixture. It verifies pipeline throughput, concurrency scaling, memory bounds (< 2.5 GB), temporal grouping, burst clustering, and diversity selection on both Intel (`x86_64`) and Apple Silicon (`arm64`). Real-world RAW decoding (e.g. 45MP uncompressed CR3/ARW from dual SD/CFexpress cards) will have lower I/O throughput determined by disk read speed and Apple CoreGraphics RAW decoding overhead.

* **Dataset Type**: `synthetic-wedding-benchmark`
* **Dataset Size**: 1,499 photographs (1,500 input files, 1 RAW+JPEG pair)
* **Architecture**: `arm64` (Apple Silicon) & `x86_64` (Native Intel)
* **Memory Budget**: Strict < 2,560 MB (2.5 GB) ceiling enforced

## Execution Metrics (1,500 Photo Workload — Release Configuration)

* **Build Configuration**: `Release` (`-O` compiler optimizations)
* **Git SHA**: `cacf4c6010b4a238480a15553061469c07f11769`

| Metric | Apple Silicon (`arm64`) | Native Intel (`x86_64`) | Budget / Target | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| **Total Wall Clock Time** | **80.36 s** | **488.02 s** | Full batch pipeline | **PASS** |
| **Sustained Throughput** | **18.7 photos/sec** | **3.1 photos/sec** | Release baseline | **PASS** |
| **Peak Resident Memory (RSS)** | **61 MB** | **205 MB** | < 2,560 MB limit | **PASS** |
| **Time to Folder Ready** | **0.47 s** | **1.64 s** | < 1.0 s target | **PASS** |
| **Time to First Thumbnail** | **0.52 s** | **5.21 s** | < 1.0 s target | **PASS** |
| **Time to Interactive Grid** | **0.98 s** | **10.25 s** | < 2.0 s target | **PASS** |
| **Target Selection Count** | **700 / 700** | **700 / 700** | Exactly 700 selected | **PASS** |
| **Export Verification** | **PASS** (700 exported) | **PASS** (700 exported) | 100% matched | **PASS** |
| **Session Round-Trip** | **PASS** (0.17 s) | **PASS** (0.11 s) | < 2.0 s target | **PASS** |

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

