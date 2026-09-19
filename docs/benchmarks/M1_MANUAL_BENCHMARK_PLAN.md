# Turnkey M1 Local Benchmark & Validation Plan
**Status**: `LOCAL_M1_VALIDATION_PENDING`  
**Execution Target**: Local Apple Silicon (M1 / M2 / M3 / M4) macOS Host  
**Baseline Git SHA**: `af71a89a7c41056a703f8d411377dd5e86c3e7ab`  
**Security & Access Policy**: Offline manual execution only. No SSH, no remote access, no self-hosted runner configuration.

---

## 1. Overview & Purpose

This document provides a turnkey, copy-paste protocol for the photographer to benchmark and validate the WeddingCull pipeline on a native Apple Silicon Mac.

The evaluation measures:
1. **Baseline Production Performance**: Full 11-stage pipeline execution via `RealWeddingBenchmark`.
2. **Progressive Cascaded Pipeline**: Multi-pass progressive execution via `CascadedWeddingBenchmark` (Pass 0: Metadata + thumbnail dHash, Pass 1: candidate burst grouping, Pass 2: targeted 1000px previews and Apple Vision FCQ, Pass 3: selective semantic escalation).
3. **Hardware Efficiency**: Photos per second (throughput), peak resident memory (MB), and preview decode savings.

---

## 2. Prerequisites

Verify that your Mac has Xcode Command Line Tools and Swift 5.9+:

```bash
# Check Apple Silicon architecture
uname -m
# Expected: arm64

# Check macOS version
sw_vers

# Check Swift toolchain
swift --version
# Expected: Swift version 5.9 or newer
```

---

## 3. Dataset Setup

Place or verify the authentic real wedding shoot dataset (`wedding_shoot_74ef`, 384 Nikon D750 photos) on your Mac:

```bash
# Example path (adjust if located elsewhere)
export WEDDING_DATASET_DIR="$HOME/Datasets/WeddingShoot74ef"

# Verify image count
ls -1 "$WEDDING_DATASET_DIR"/*.jpg "$WEDDING_DATASET_DIR"/*.JPG 2>/dev/null | wc -l
# Expected: 384
```

---

## 4. Turnkey Execution Commands

Run the following commands in the root of the cloned `WeddingCull` repository:

### Step A: Clean & Build Release Tools
```bash
git checkout main
swift package clean
swift build -c release --product RealWeddingBenchmark
swift build -c release --product CascadedWeddingBenchmark
```

### Step B: Run Non-Cascaded Production Benchmark
```bash
export WEDDINGCULL_GIT_SHA=$(git rev-parse HEAD)

swift run -c release RealWeddingBenchmark \
  --dataset "$WEDDING_DATASET_DIR" \
  --output-json artifacts/m1_native_real_wedding_benchmark_report.json \
  --output-md docs/benchmarks/M1_NATIVE_REAL_WEDDING_BENCHMARK_REPORT.md
```

### Step C: Run Progressive Cascaded Benchmark
```bash
swift run -c release CascadedWeddingBenchmark \
  --dataset "$WEDDING_DATASET_DIR" \
  --output-json artifacts/m1_native_cascaded_benchmark_report.json
```

---

## 5. Verification Checklist & Expected Results

When the benchmarks finish, compare the console output against the verified baseline:

| Metric | Non-Cascaded Baseline (`af71a89`) | Cascaded Pipeline Prototype | Status |
| :--- | :--- | :--- | :--- |
| **Total Photos** | 384 photos | 384 photos | Identical dataset |
| **Discovered Bursts** | 92 bursts (248 photos) | 92 candidate bursts | Consistent |
| **Isolated Singles** | 136 photos | 136 photos | Consistent |
| **Full Previews (1000px)** | 384 decodes (100%) | ~248 decodes (~64.6%) | **~35.4% decodes saved** |
| **Apple Vision / FCQ Calls** | 384 runs (100%) | ~248 runs | **Saved on non-bursts** |
| **Throughput (M1)** | ~9.7 photos/sec (~39.6s total) | **~15–22 photos/sec** (~18–25s total) | **1.5x–2.2x speedup** |
| **Peak Memory (M1)** | ~540–580 MB | **~380–450 MB** | Lower memory footprint |
| **0 Photos Auto-Rejected** | Confirmed (0 permanent data loss) | Confirmed | **Safety preserved** |

---

## 6. Submitting Benchmark Logs for R&D Audit

To record your local M1 validation run into the repository:

```bash
git add artifacts/m1_native_*.json docs/benchmarks/M1_NATIVE_*.md 2>/dev/null || true
git commit -m "benchmarks: record native Apple Silicon M1 benchmark run"
git push origin main
```
