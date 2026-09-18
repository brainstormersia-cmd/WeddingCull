import json
import os
import sys
import subprocess
from datetime import datetime, timezone

def read_json_safe(path):
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: could not parse {path}: {e}")
    return None

def get_git_sha():
    try:
        res = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return "unknown"

def main():
    output_dir = sys.argv[1] if len(sys.argv) > 1 else "artifacts"
    output_report_path = os.path.join(output_dir, "release-validation-report.json")
    output_md_path = os.path.join(output_dir, "RELEASE_VALIDATION_REPORT.md")

    git_sha = get_git_sha()
    timestamp = datetime.now(timezone.utc).isoformat()

    bench_arm64 = read_json_safe(os.path.join(output_dir, "benchmark-arm64.json"))
    bench_intel = read_json_safe(os.path.join(output_dir, "benchmark-intel.json"))
    albumbench = read_json_safe(os.path.join(output_dir, "albumbench-report.json"))
    raw_report = read_json_safe(os.path.join(output_dir, "raw-validation-report.json"))
    mobileclip = read_json_safe(os.path.join(output_dir, "mobileclip-report.json"))
    selection_gt = read_json_safe(os.path.join(output_dir, "selection-ground-truth-report.json"))
    category_rep = read_json_safe(os.path.join(output_dir, "category-report.json"))
    dup_burst_rep = read_json_safe(os.path.join(output_dir, "duplicate-burst-report.json"))
    iqa_report = read_json_safe(os.path.join(output_dir, "iqa-report.json"))

    # Determine status of each subsystem
    # 1. 1500->700 ARM64
    arm64_status = "EXECUTED" if (bench_arm64 and bench_arm64.get("memoryWithinBudget")) else ("FAILED" if bench_arm64 else "NOT_VERIFIED")
    # 2. 1500->700 Intel
    intel_status = "EXECUTED" if (bench_intel and bench_intel.get("memoryWithinBudget")) else ("FAILED" if bench_intel else "NOT_VERIFIED")
    # 3. AlbumBench Real Public Dataset (Regression Reference)
    albumbench_status = "EXECUTED / REGRESSION REFERENCE" if (albumbench and albumbench.get("evaluatedAlbumsCount", 0) > 0) else ("FAILED" if albumbench else "NOT_VERIFIED")
    
    # 4. Strict RAW with per-format breakdown
    raw_formats = raw_report.get("formats", {}) if raw_report else {}
    if not raw_formats and raw_report:
        for r in raw_report.get("results", []):
            raw_formats[r.get("format", "UNKNOWN")] = r.get("status", "UNKNOWN")
    raw_mandatory_pass = (raw_report and raw_report.get("mandatoryStatus") == "PASS")
    raw_status = "EXECUTED" if raw_mandatory_pass else ("FAILED" if raw_report else "NOT_VERIFIED")

    # 5. MobileCLIP Strict
    mobileclip_status = "EXECUTED" if (mobileclip and mobileclip.get("status") == "PASS") else ("FAILED" if mobileclip else "NOT_VERIFIED")
    # 6. Public IQA
    iqa_status = iqa_report.get("status", "DOCUMENTED_ONLY") if iqa_report else "DOCUMENTED_ONLY"

    overall_pass = (
        arm64_status == "EXECUTED" and
        intel_status == "EXECUTED" and
        albumbench_status.startswith("EXECUTED") and
        raw_status == "EXECUTED" and
        mobileclip_status == "EXECUTED"
    )

    raw_format_summary = ", ".join([f"{fmt}: {st}" for fmt, st in sorted(raw_formats.items())]) if raw_formats else "None"

    report = {
        "title": "WeddingCull Final Release Dataset Validation Report",
        "timestamp": timestamp,
        "gitSHA": git_sha,
        "overallVerdict": "PASS" if overall_pass else "INCOMPLETE_OR_FAILED",
        "baselinePerformance": {
            "BASELINE_RELEASE_ARM64": {
                "buildConfiguration": bench_arm64.get("buildConfiguration", "release") if bench_arm64 else None,
                "architecture": "arm64",
                "photosPerSecond": bench_arm64.get("photosPerSecond") if bench_arm64 else None,
                "peakRSSMB": bench_arm64.get("peakMemoryMB") if bench_arm64 else None,
                "wallClockSeconds": bench_arm64.get("wallClockSeconds") if bench_arm64 else None,
                "datasetMode": bench_arm64.get("datasetMode", "LOW_RES_SCALE") if bench_arm64 else None,
                "phaseTimings": bench_arm64.get("phaseTimings") if bench_arm64 else None,
                "perceivedSpeedMetrics": bench_arm64.get("perceivedSpeedMetrics") if bench_arm64 else None
            },
            "BASELINE_RELEASE_INTEL": {
                "buildConfiguration": bench_intel.get("buildConfiguration", "release") if bench_intel else None,
                "architecture": "x86_64",
                "photosPerSecond": bench_intel.get("photosPerSecond") if bench_intel else None,
                "peakRSSMB": bench_intel.get("peakMemoryMB") if bench_intel else None,
                "wallClockSeconds": bench_intel.get("wallClockSeconds") if bench_intel else None,
                "datasetMode": bench_intel.get("datasetMode", "LOW_RES_SCALE") if bench_intel else None,
                "phaseTimings": bench_intel.get("phaseTimings") if bench_intel else None,
                "perceivedSpeedMetrics": bench_intel.get("perceivedSpeedMetrics") if bench_intel else None
            }
        },
        "auditMatrix": {
            "dualArchitecture1500Benchmark": {
                "arm64_apple_silicon": {
                    "status": arm64_status,
                    "buildConfiguration": bench_arm64.get("buildConfiguration", "release") if bench_arm64 else None,
                    "targetCardinality": bench_arm64.get("targetCardinality") if bench_arm64 else None,
                    "finalSelectedCount": bench_arm64.get("finalSelectedCount") if bench_arm64 else None,
                    "throughputPPS": bench_arm64.get("photosPerSecond") if bench_arm64 else None,
                    "peakRSSMB": bench_arm64.get("peakMemoryMB") if bench_arm64 else None,
                    "wallClockSeconds": bench_arm64.get("wallClockSeconds") if bench_arm64 else None
                },
                "x86_64_native_intel": {
                    "status": intel_status,
                    "buildConfiguration": bench_intel.get("buildConfiguration", "release") if bench_intel else None,
                    "targetCardinality": bench_intel.get("targetCardinality") if bench_intel else None,
                    "finalSelectedCount": bench_intel.get("finalSelectedCount") if bench_intel else None,
                    "throughputPPS": bench_intel.get("photosPerSecond") if bench_intel else None,
                    "peakRSSMB": bench_intel.get("peakMemoryMB") if bench_intel else None,
                    "wallClockSeconds": bench_intel.get("wallClockSeconds") if bench_intel else None
                }
            },
            "realPublicDatasetValidation": {
                "albumBenchWedding": {
                    "status": albumbench_status,
                    "tuningStatus": "FROZEN_REGRESSION_REFERENCE",
                    "evaluatedAlbums": albumbench.get("evaluatedAlbumsCount") if albumbench else None,
                    "totalImages": albumbench.get("totalImagesEvaluated") if albumbench else None,
                    "executionTimeSeconds": albumbench.get("executionTimeSeconds") if albumbench else None,
                    "meanPrecision": albumbench.get("meanPrecision") if albumbench else None,
                    "meanRecall": albumbench.get("meanRecall") if albumbench else None,
                    "meanF1": albumbench.get("meanF1") if albumbench else None,
                    "meanJaccard": albumbench.get("meanJaccard") if albumbench else None,
                    "meanSpearmanRho": albumbench.get("meanSpearmanRho") if albumbench else None,
                    "meanKendallTau": albumbench.get("meanKendallTau") if albumbench else None,
                    "meanGroupingARI": albumbench.get("meanGroupingARI") if albumbench else None,
                    "meanEventCoverage": albumbench.get("meanEventCoverage") if albumbench else None
                },
                "spaqKonIQAesthetics": {
                    "status": iqa_status,
                    "note": iqa_report.get("message") if iqa_report else "Framework ready (IQAValidationRunner); requires local dataset directory due to academic licensing."
                }
            },
            "realCameraRAWDecoding": {
                "status": raw_status,
                "mandatoryCanonCR2": "PASS" if raw_mandatory_pass else "FAIL",
                "formatCompatibilityMatrix": raw_formats,
                "totalTestedFixtures": raw_report.get("totalFixturesTested") if raw_report else 0,
                "passedFixtures": raw_report.get("passedFixturesCount") if raw_report else 0,
                "unsupportedFixtures": raw_report.get("unsupportedFixturesCount") if raw_report else 0
            },
            "mobileCLIPAdvancedAI": {
                "status": mobileclip_status,
                "backend": mobileclip.get("classificationBackend") if mobileclip else "NOT_VERIFIED",
                "revision": mobileclip.get("repoRevision") if mobileclip else None,
                "latencyMs": mobileclip.get("averageLatencyMs") if mobileclip else None
            },
            "selectionIntegrity": {
                "burstWinnerAgreement": dup_burst_rep.get("burstWinnerAgreementRate") if dup_burst_rep else None,
                "categoryCoverage": category_rep.get("categoryCoverageRate") if category_rep else None,
                "duplicateLeakage": dup_burst_rep.get("duplicateLeakageRate") if dup_burst_rep else None,
                "uniqueKeeperFalseRejectRate": selection_gt.get("uniqueKeeperFalseRejectRate") if selection_gt else None
            }
        }
    }

    with open(output_report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"[OK] Generated master report: {output_report_path}")

    # Generate Markdown Summary
    albumbench_exec_time = f"{albumbench['executionTimeSeconds']:.1f}s" if albumbench and "executionTimeSeconds" in albumbench else "N/A"
    albumbench_f1 = f"{albumbench['meanF1']*100:.1f}%" if albumbench and 'meanF1' in albumbench else "N/A"

    sweep_arm64 = read_json_safe(os.path.join(output_dir, "concurrency-sweep-arm64.json"))
    sweep_intel = read_json_safe(os.path.join(output_dir, "concurrency-sweep-intel.json"))
    if sweep_arm64:
        report["concurrencySweepARM64"] = sweep_arm64
    if sweep_intel:
        report["concurrencySweepIntel"] = sweep_intel

    md_content = f"""# WeddingCull Final Release Dataset Validation Report

* **Git Commit**: `{git_sha}`
* **Generated At**: `{timestamp}`
* **Overall Verdict**: **{report['overallVerdict']}**

## Release Performance Baseline

* **BASELINE_RELEASE_ARM64**: {bench_arm64.get('photosPerSecond', 'N/A') if bench_arm64 else 'N/A'} PPS, {bench_arm64.get('peakMemoryMB', 'N/A') if bench_arm64 else 'N/A'} MB RSS, {bench_arm64.get('wallClockSeconds', 'N/A') if bench_arm64 else 'N/A'}s wall clock (Release build, Apple Silicon)
* **BASELINE_RELEASE_INTEL**: {bench_intel.get('photosPerSecond', 'N/A') if bench_intel else 'N/A'} PPS, {bench_intel.get('peakMemoryMB', 'N/A') if bench_intel else 'N/A'} MB RSS, {bench_intel.get('wallClockSeconds', 'N/A') if bench_intel else 'N/A'}s wall clock (Release build, Native Intel)

## Subsystem Validation Matrix

| Subsystem / Benchmark | Status | Details |
| :--- | :--- | :--- |
| **Apple Silicon (arm64) 1500->700** | **{arm64_status}** | {bench_arm64.get('photosPerSecond', 'N/A') if bench_arm64 else 'N/A'} PPS, {bench_arm64.get('peakMemoryMB', 'N/A') if bench_arm64 else 'N/A'} MB RSS ({bench_arm64.get('buildConfiguration', 'release') if bench_arm64 else 'release'}) |
| **Native Intel (x86_64) 1500->700** | **{intel_status}** | {bench_intel.get('photosPerSecond', 'N/A') if bench_intel else 'N/A'} PPS, {bench_intel.get('peakMemoryMB', 'N/A') if bench_intel else 'N/A'} MB RSS ({bench_intel.get('buildConfiguration', 'release') if bench_intel else 'release'}) |
| **AlbumBench Real Wedding Dataset** | **{albumbench_status}** | {albumbench.get('evaluatedAlbumsCount', 0) if albumbench else 0} albums ({albumbench.get('totalImagesEvaluated', 0) if albumbench else 0} photos), F1={albumbench_f1}, Time={albumbench_exec_time} (Photographic tuning frozen; regression reference) |
| **Strict Real Camera RAWs** | **{raw_status}** | {raw_format_summary} |
| **MobileCLIP Core ML Model** | **{mobileclip_status}** | {mobileclip.get('classificationBackend', 'N/A') if mobileclip else 'N/A'}, Latency={f"{mobileclip['averageLatencyMs']:.1f}ms" if mobileclip and 'averageLatencyMs' in mobileclip else 'N/A'} |
| **Public IQA Benchmark Framework** | **{iqa_status}** | {iqa_report.get('message', 'Framework ready for local execution') if iqa_report else 'Framework ready for local execution'} |
"""

    sweep_intel = read_json_safe(os.path.join(output_dir, "concurrency-sweep-intel.json"))
    sweep_arm64 = read_json_safe(os.path.join(output_dir, "concurrency-sweep-arm64.json"))
    vision_intel = read_json_safe(os.path.join(output_dir, "vision-configs-sweep-intel.json"))
    vision_arm64 = read_json_safe(os.path.join(output_dir, "vision-configs-sweep-arm64.json"))

    if sweep_intel:
        md_content += "\n## Native Intel Concurrency Sweep (x86_64)\n\n"
        md_content += "| Workers | Wall Clock (s) | Throughput (PPS) | Peak RSS (MB) | Face Detection (ms/photo) | FeaturePrint (ms/photo) | Scene Classify (ms/photo) | Diversity Selection (s) |\n"
        md_content += "| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |\n"
        for r in sweep_intel:
            md_content += f"| {r.get('workers')} | {r.get('wallClockSeconds'):.2f}s | **{r.get('throughputPPS'):.2f} PPS** | {r.get('peakMemoryMB')} MB | {r.get('faceMsPerPhoto'):.1f} ms | {r.get('fpMsPerPhoto'):.1f} ms | {r.get('sceneMsPerPhoto'):.1f} ms | {r.get('rankingAndSelectionSeconds'):.2f}s |\n"

    if sweep_arm64:
        md_content += "\n## Apple Silicon Concurrency Sweep (arm64)\n\n"
        md_content += "| Workers | Wall Clock (s) | Throughput (PPS) | Peak RSS (MB) | Face Detection (ms/photo) | FeaturePrint (ms/photo) | Scene Classify (ms/photo) | Diversity Selection (s) |\n"
        md_content += "| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |\n"
        for r in sweep_arm64:
            md_content += f"| {r.get('workers')} | {r.get('wallClockSeconds'):.2f}s | **{r.get('throughputPPS'):.2f} PPS** | {r.get('peakMemoryMB')} MB | {r.get('faceMsPerPhoto'):.1f} ms | {r.get('fpMsPerPhoto'):.1f} ms | {r.get('sceneMsPerPhoto'):.1f} ms | {r.get('rankingAndSelectionSeconds'):.2f}s |\n"

    if vision_intel:
        md_content += "\n## Native Intel Vision Configurations & Resolution Sweep (x86_64)\n\n"
        md_content += "| Configuration | Mode | Face (px) | Scene (px) | Wall Clock (s) | Throughput (PPS) | Face (ms/photo) | Face Agr % | Scene (ms/photo) | Scene Agr % |\n"
        md_content += "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |\n"
        for r in vision_intel:
            md_content += f"| {r.get('configName')} | {r.get('mode')} | {r.get('facePixelSize')} | {r.get('scenePixelSize')} | {r.get('wallClockSeconds'):.2f}s | **{r.get('throughputPPS'):.2f} PPS** | {r.get('faceMsPerPhoto'):.1f} ms | {r.get('faceCountAgreementPct'):.1f}% | {r.get('sceneMsPerPhoto'):.1f} ms | {r.get('categoryAgreementPct'):.1f}% |\n"

    if vision_arm64:
        md_content += "\n## Apple Silicon Vision Configurations & Resolution Sweep (arm64)\n\n"
        md_content += "| Configuration | Mode | Face (px) | Scene (px) | Wall Clock (s) | Throughput (PPS) | Face (ms/photo) | Face Agr % | Scene (ms/photo) | Scene Agr % |\n"
        md_content += "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |\n"
        for r in vision_arm64:
            md_content += f"| {r.get('configName')} | {r.get('mode')} | {r.get('facePixelSize')} | {r.get('scenePixelSize')} | {r.get('wallClockSeconds'):.2f}s | **{r.get('throughputPPS'):.2f} PPS** | {r.get('faceMsPerPhoto'):.1f} ms | {r.get('faceCountAgreementPct'):.1f}% | {r.get('sceneMsPerPhoto'):.1f} ms | {r.get('categoryAgreementPct'):.1f}% |\n"

    pt_arm = bench_arm64.get("phaseTimings") if bench_arm64 else None
    pt_int = bench_intel.get("phaseTimings") if bench_intel else None
    if pt_arm or pt_int:
        count_arm = float(bench_arm64.get("inputCount", 1500)) if bench_arm64 else 1500.0
        count_int = float(bench_intel.get("inputCount", 1500)) if bench_intel else 1500.0
        md_content += "\n## Comparative Phase Timings Breakdown\n\n"
        md_content += "| Pipeline Phase | Apple Silicon Cumulative | Apple Silicon Per-Photo | Native Intel Cumulative | Native Intel Per-Photo |\n"
        md_content += "| :--- | :--- | :--- | :--- | :--- |\n"

        phases = [
            ("Discovery & Metadata", "discoverySeconds", False),
            ("Preview Generation", "previewGenerationSeconds", True),
            ("Face Detection & Landmarks", "faceDetectionSeconds", True),
            ("FeaturePrint Generation", "featurePrintSeconds", True),
            ("Total Face & Feature", "faceAndFeatureSeconds", True),
            ("Quality Scoring", "qualityScoringSeconds", True),
            ("Scene Classification", "sceneClassificationSeconds", True),
            ("Burst & Duplicate", "burstAndDuplicateSeconds", False),
            ("Temporal Segmentation", "clusteringAndSegmentationSeconds", False),
            ("Ranking & Diversity Selection", "rankingAndSelectionSeconds", True),
            ("Session Persistence Write", "sessionPersistenceSeconds", False),
            ("Total Wall Clock Time", "totalWallClockSeconds", True),
        ]
        for name, key, is_per_photo in phases:
            val_arm = pt_arm.get(key) if pt_arm else None
            val_int = pt_int.get(key) if pt_int else None
            str_arm_cum = f"{val_arm:.2f}s" if val_arm is not None else "-"
            str_arm_per = f"{(val_arm / count_arm) * 1000.0:.1f} ms" if (val_arm is not None and is_per_photo) else "-"
            str_int_cum = f"{val_int:.2f}s" if val_int is not None else "-"
            str_int_per = f"{(val_int / count_int) * 1000.0:.1f} ms" if (val_int is not None and is_per_photo) else "-"
            md_content += f"| **{name}** | {str_arm_cum} | {str_arm_per} | {str_int_cum} | {str_int_per} |\n"
    with open(output_md_path, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"[OK] Generated master markdown: {output_md_path}")

if __name__ == "__main__":
    main()
