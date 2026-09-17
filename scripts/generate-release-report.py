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
    # 3. AlbumBench Real Public Dataset
    albumbench_status = "EXECUTED" if (albumbench and albumbench.get("evaluatedAlbumsCount", 0) > 0) else ("FAILED" if albumbench else "NOT_VERIFIED")
    # 4. Strict RAW
    raw_status = "EXECUTED" if (raw_report and raw_report.get("mandatoryStatus") == "PASS") else ("FAILED" if raw_report else "NOT_VERIFIED")
    # 5. MobileCLIP Strict
    mobileclip_status = "EXECUTED" if (mobileclip and mobileclip.get("status") == "PASS") else ("FAILED" if mobileclip else "NOT_VERIFIED")
    # 6. Public IQA
    iqa_status = iqa_report.get("status", "DOCUMENTED_ONLY") if iqa_report else "DOCUMENTED_ONLY"

    overall_pass = (
        arm64_status == "EXECUTED" and
        intel_status == "EXECUTED" and
        albumbench_status == "EXECUTED" and
        raw_status == "EXECUTED" and
        mobileclip_status == "EXECUTED"
    )

    report = {
        "title": "WeddingCull Final Release Dataset Validation Report",
        "timestamp": timestamp,
        "gitSHA": git_sha,
        "overallVerdict": "PASS" if overall_pass else "INCOMPLETE_OR_FAILED",
        "auditMatrix": {
            "dualArchitecture1500Benchmark": {
                "arm64_apple_silicon": {
                    "status": arm64_status,
                    "targetCardinality": bench_arm64.get("targetCardinality") if bench_arm64 else None,
                    "finalSelectedCount": bench_arm64.get("finalSelectedCount") if bench_arm64 else None,
                    "throughputPPS": bench_arm64.get("photosPerSecond") if bench_arm64 else None,
                    "peakRSSMB": bench_arm64.get("peakMemoryMB") if bench_arm64 else None,
                    "wallClockSeconds": bench_arm64.get("wallClockSeconds") if bench_arm64 else None
                },
                "x86_64_native_intel": {
                    "status": intel_status,
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
                    "evaluatedAlbums": albumbench.get("evaluatedAlbumsCount") if albumbench else None,
                    "totalImages": albumbench.get("totalImagesEvaluated") if albumbench else None,
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
                "mandatoryCanonCR2": "PASS" if (raw_report and raw_report.get("mandatoryStatus") == "PASS") else "FAIL",
                "totalTestedFixtures": raw_report.get("totalFixturesTested") if raw_report else 0,
                "passedFixtures": raw_report.get("passedFixturesCount") if raw_report else 0
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
    print(f"✅ Generated master report: {output_report_path}")

    # Generate Markdown Summary
    md_content = f"""# WeddingCull Final Dataset Validation Report

* **Git Commit**: `{git_sha}`
* **Generated At**: `{timestamp}`
* **Overall Verdict**: **{report['overallVerdict']}**

## Subsystem Audit Matrix

| Subsystem / Benchmark | Status | Details |
| :--- | :--- | :--- |
| **Apple Silicon (arm64) 1500→700** | **{arm64_status}** | {bench_arm64.get('photosPerSecond', 'N/A') if bench_arm64 else 'N/A'} PPS, {bench_arm64.get('peakMemoryMB', 'N/A') if bench_arm64 else 'N/A'} MB RSS |
| **Native Intel (x86_64) 1500→700** | **{intel_status}** | {bench_intel.get('photosPerSecond', 'N/A') if bench_intel else 'N/A'} PPS, {bench_intel.get('peakMemoryMB', 'N/A') if bench_intel else 'N/A'} MB RSS |
| **AlbumBench Real Wedding Dataset** | **{albumbench_status}** | {albumbench.get('evaluatedAlbumsCount', 0) if albumbench else 0} albums ({albumbench.get('totalImagesEvaluated', 0) if albumbench else 0} photos), F1={f"{albumbench['meanF1']*100:.1f}%" if albumbench and 'meanF1' in albumbench else 'N/A'} |
| **Strict Real Camera RAWs** | **{raw_status}** | Canon CR2, Nikon NEF, Sony ARW, Fuji RAF ({raw_report.get('passedFixturesCount', 0) if raw_report else 0}/{raw_report.get('totalFixturesTested', 0) if raw_report else 0} passed) |
| **MobileCLIP Core ML Model** | **{mobileclip_status}** | {mobileclip.get('classificationBackend', 'N/A') if mobileclip else 'N/A'}, Latency={f"{mobileclip['averageLatencyMs']:.1f}ms" if mobileclip and 'averageLatencyMs' in mobileclip else 'N/A'} |
| **Public IQA Benchmark Framework** | **{iqa_status}** | {iqa_report.get('message', 'Framework ready for local execution') if iqa_report else 'Framework ready for local execution'} |
"""
    with open(output_md_path, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"✅ Generated master markdown: {output_md_path}")

if __name__ == "__main__":
    main()
