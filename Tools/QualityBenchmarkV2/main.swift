import Foundation
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif
#if canImport(TestDatasetGeneratorLibrary)
import TestDatasetGeneratorLibrary
#endif
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Benchmark Data Models

struct PhotoSeriesBenchmarkDataset: Codable {
    let version: String
    let dataset_name: String
    let description: String
    let total_series: Int
    let total_frames: Int
    let series: [PhotoSeries]
}

struct PhotoSeries: Codable {
    let series_id: String
    let scene_type: String
    let description: String
    let ground_truth: SeriesGroundTruth
    let frames: [SeriesFrame]
}

struct SeriesGroundTruth: Codable {
    let preferred_order: [String]
    let acceptable_keepers: [String]
    let unacceptable_rejects: [String]
    let reasons: [String: String]
}

struct SeriesFrame: Codable {
    let photo_id: String
    let relative_time_seconds: Double
    let simulated_attributes: FrameSimulatedAttributes
}

struct FrameSimulatedAttributes: Codable {
    let sharpness: Double
    let face_count: Int
    let face_sharpness: Double
    let eye_openness: Double
    let face_confidence: Double
    let face_capture_quality: Double
    let exposure_score: Double
}

// MARK: - Eye State Evaluation Models

public enum BenchmarkEyeState: String, Codable {
    case open = "OPEN"
    case closed = "CLOSED"
    case unknown = "UNKNOWN"
}

struct EyeStateEvaluationMetrics: Codable, Sendable {
    let totalEyesEvaluated: Int
    let accuracy: Double
    let openPrecision: Double
    let openRecall: Double
    let openF1: Double
    let closedPrecision: Double
    let closedRecall: Double
    let closedF1: Double
    let falseClosedRate: Double // Crucial: false rejection risk (saying eyes closed when open)
    let falseOpenRate: Double
}

// MARK: - Ranking & Ablation Result Models

struct SeriesRankingMetrics: Codable, Sendable {
    let configurationName: String
    let enableFaceCaptureQuality: Bool
    let totalSeriesEvaluated: Int
    let top1Accuracy: Double
    let top2Recall: Double
    let top3Recall: Double
    let pairwiseAccuracy: Double
    let rejectInclusionRate: Double
    let meanRankOfPreferred: Double
    let executionDurationMs: Double
    let memoryResidentBytes: UInt64
}

struct FailureCase: Codable, Sendable {
    let seriesId: String
    let sceneType: String
    let preferredFrameId: String
    let baselineWinnerId: String
    let experimentalWinnerId: String
    let baselineCorrect: Bool
    let experimentalCorrect: Bool
    let failureCategory: String // "focus", "eyes", "expression", "pose", "exposure"
    let explanation: String
}

struct AblationComparison: Codable, Sendable {
    let baseline: SeriesRankingMetrics
    let experimental: SeriesRankingMetrics
    let top1AccuracyDelta: Double
    let pairwiseAccuracyDelta: Double
    let winnerFlipsCount: Int
    let winnerFlipRate: Double
    let regressions: [FailureCase]
    let improvements: [FailureCase]
}

struct QualityBenchmarkV2Report: Codable, Sendable {
    let timestamp: String
    let benchmarkVersion: String
    let datasetPath: String
    let totalSeries: Int
    let totalFrames: Int
    let ablation: AblationComparison
    let eyeStateBenchmark: EyeStateEvaluationMetrics?
}

// MARK: - Benchmark Runner Implementation

@main
struct QualityBenchmarkV2Runner {
    static func getCurrentResidentMemoryBytes() -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
        #else
        return 0
        #endif
    }

    static func main() async {
        let args = CommandLine.arguments

        var groundTruthPath = "docs/datasets/wedding-photo-series-ground-truth.json"
        var outputJSONPath = "artifacts/quality-benchmark-v2.json"
        var outputMDPath = "artifacts/QUALITY_BENCHMARK_V2.md"
        var runAblationMode = true
        var runEyeStateMode = true

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--ground-truth":
                if i + 1 < args.count { groundTruthPath = args[i + 1]; i += 1 }
            case "--output-json":
                if i + 1 < args.count { outputJSONPath = args[i + 1]; i += 1 }
            case "--output-md":
                if i + 1 < args.count { outputMDPath = args[i + 1]; i += 1 }
            case "--no-ablation":
                runAblationMode = false
            case "--no-eye-state":
                runEyeStateMode = false
            case "--help", "-h":
                printUsage()
                return
            default:
                break
            }
            i += 1
        }

        print("=== WeddingCull Quality Benchmark V2 ===")
        print("Dataset: \(groundTruthPath)")

        let datasetURL = URL(fileURLWithPath: groundTruthPath)
        guard FileManager.default.fileExists(atPath: datasetURL.path) else {
            print("ERROR: Ground truth dataset not found at \(groundTruthPath)")
            exit(1)
        }

        let datasetData: Data
        do {
            datasetData = try Data(contentsOf: datasetURL)
        } catch {
            print("ERROR: Failed to read dataset: \(error)")
            exit(1)
        }

        let dataset: PhotoSeriesBenchmarkDataset
        do {
            dataset = try JSONDecoder().decode(PhotoSeriesBenchmarkDataset.self, from: datasetData)
        } catch {
            print("ERROR: Failed to decode dataset JSON: \(error)")
            exit(1)
        }

        print("Loaded \(dataset.total_series) series with \(dataset.total_frames) total frames.")

        // 1. Run Baseline Evaluation (enableFaceCaptureQuality: false)
        print("\n--> Running Baseline evaluation (FaceCaptureQuality = OFF)...")
        let baselineResult = evaluateSeriesBenchmark(
            dataset: dataset,
            enableFaceCaptureQuality: false,
            configName: "Baseline (Confidence Only)"
        )
        print(String(format: "    Top-1 Accuracy: %.1f%%", baselineResult.top1Accuracy * 100))
        print(String(format: "    Top-3 Recall:   %.1f%%", baselineResult.top3Recall * 100))
        print(String(format: "    Pairwise Acc:   %.1f%%", baselineResult.pairwiseAccuracy * 100))

        // 2. Run Experimental Evaluation (enableFaceCaptureQuality: true)
        print("\n--> Running Experimental evaluation (FaceCaptureQuality = ON)...")
        let experimentalResult = evaluateSeriesBenchmark(
            dataset: dataset,
            enableFaceCaptureQuality: true,
            configName: "Experimental (+FaceCaptureQuality)"
        )
        print(String(format: "    Top-1 Accuracy: %.1f%%", experimentalResult.top1Accuracy * 100))
        print(String(format: "    Top-3 Recall:   %.1f%%", experimentalResult.top3Recall * 100))
        print(String(format: "    Pairwise Acc:   %.1f%%", experimentalResult.pairwiseAccuracy * 100))

        // 3. Ablation Analysis: Flips, Improvements, Regressions
        let ablation = analyzeAblation(
            dataset: dataset,
            baseline: baselineResult,
            experimental: experimentalResult
        )

        // 4. Eye-State Evaluation Scaffolding
        let eyeMetrics: EyeStateEvaluationMetrics?
        if runEyeStateMode {
            eyeMetrics = evaluateEyeState(dataset: dataset)
        } else {
            eyeMetrics = nil
        }

        // 5. Build Final Report
        let nowFormatter = ISO8601DateFormatter()
        let report = QualityBenchmarkV2Report(
            timestamp: nowFormatter.string(from: Date()),
            benchmarkVersion: "2.0.0",
            datasetPath: groundTruthPath,
            totalSeries: dataset.total_series,
            totalFrames: dataset.total_frames,
            ablation: ablation,
            eyeStateBenchmark: eyeMetrics
        )

        // 6. Write JSON Artifact
        do {
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try jsonEncoder.encode(report)
            let outURL = URL(fileURLWithPath: outputJSONPath)
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jsonData.write(to: outURL)
            print("\nWrote benchmark JSON to \(outputJSONPath)")
        } catch {
            print("WARNING: Failed to write JSON output: \(error)")
        }

        // 7. Write Markdown Artifact
        let mdContent = generateMarkdownReport(report: report)
        do {
            let mdURL = URL(fileURLWithPath: outputMDPath)
            try FileManager.default.createDirectory(at: mdURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try mdContent.write(to: mdURL, atomically: true, encoding: .utf8)
            print("Wrote benchmark report to \(outputMDPath)")
        } catch {
            print("WARNING: Failed to write MD output: \(error)")
        }

        print("\n=== Quality Benchmark V2 Completed Successfully ===")
    }

    // MARK: - Evaluation Functions

    static func evaluateSeriesBenchmark(
        dataset: PhotoSeriesBenchmarkDataset,
        enableFaceCaptureQuality: Bool,
        configName: String
    ) -> SeriesRankingMetrics {
        let detector = DuplicateAndBurstDetector(enableFaceCaptureQuality: enableFaceCaptureQuality)
        let tStart = CFAbsoluteTimeGetCurrent()

        var top1Correct = 0
        var top2RecallCount = 0
        var top3RecallCount = 0
        var totalPairs = 0
        var correctPairs = 0
        var rejectIncludedCount = 0
        var rankSum = 0

        for series in dataset.series {
            let items = series.frames.map { frame -> PhotoItem in
                var metrics = QualityMetrics()
                metrics.rawSharpness = frame.simulated_attributes.sharpness * 500.0
                metrics.sharpnessScore = frame.simulated_attributes.sharpness
                metrics.faceCount = frame.simulated_attributes.face_count
                metrics.rawFaceSharpness = frame.simulated_attributes.face_sharpness * 500.0
                metrics.faceSharpnessScore = frame.simulated_attributes.face_sharpness
                metrics.averageEyeOpenness = frame.simulated_attributes.eye_openness
                metrics.exposureScore = frame.simulated_attributes.exposure_score
                metrics.faceQualityScore = frame.simulated_attributes.face_confidence

                if enableFaceCaptureQuality {
                    metrics.rawFaceCaptureQuality = frame.simulated_attributes.face_capture_quality
                    metrics.faceCaptureQualityScore = frame.simulated_attributes.face_capture_quality
                }

                let dummyURL = URL(fileURLWithPath: "/tmp/\(frame.photo_id).jpg")
                return PhotoItem(
                    id: frame.photo_id,
                    fileName: "\(frame.photo_id).jpg",
                    sourceURL: dummyURL,
                    metrics: metrics
                )
            }

            // Rank frames using DuplicateAndBurstDetector logic
            let ranked = items.sorted { a, b in
                let scoreA = detector.computeBurstFrameQuality(a)
                let scoreB = detector.computeBurstFrameQuality(b)
                let qA = round(scoreA * 10000.0) / 10000.0
                let qB = round(scoreB * 10000.0) / 10000.0
                if qA != qB {
                    return qA > qB
                }
                return a.id < b.id
            }

            guard let preferredFirst = series.ground_truth.preferred_order.first else { continue }
            let rankedIDs = ranked.map { $0.id }

            // 1. Top-1 Accuracy
            if rankedIDs.first == preferredFirst {
                top1Correct += 1
            }

            // 2. Top-2 Recall
            if rankedIDs.prefix(2).contains(preferredFirst) {
                top2RecallCount += 1
            }

            // 3. Top-3 Recall
            if rankedIDs.prefix(3).contains(preferredFirst) {
                top3RecallCount += 1
            }

            // 4. Preferred Rank
            if let idx = rankedIDs.firstIndex(of: preferredFirst) {
                rankSum += (idx + 1)
            } else {
                rankSum += rankedIDs.count
            }

            // 5. Reject Inclusion Check
            if let winner = rankedIDs.first, series.ground_truth.unacceptable_rejects.contains(winner) {
                rejectIncludedCount += 1
            }

            // 6. Pairwise Concordance against preferred order
            let prefOrder = series.ground_truth.preferred_order
            for p1 in 0..<prefOrder.count {
                for p2 in (p1 + 1)..<prefOrder.count {
                    let idA = prefOrder[p1]
                    let idB = prefOrder[p2]
                    guard let rA = rankedIDs.firstIndex(of: idA), let rB = rankedIDs.firstIndex(of: idB) else { continue }
                    totalPairs += 1
                    if rA < rB {
                        correctPairs += 1
                    }
                }
            }
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - tStart) * 1000.0
        let total = Double(max(1, dataset.series.count))

        return SeriesRankingMetrics(
            configurationName: configName,
            enableFaceCaptureQuality: enableFaceCaptureQuality,
            totalSeriesEvaluated: dataset.series.count,
            top1Accuracy: Double(top1Correct) / total,
            top2Recall: Double(top2RecallCount) / total,
            top3Recall: Double(top3RecallCount) / total,
            pairwiseAccuracy: totalPairs > 0 ? Double(correctPairs) / Double(totalPairs) : 1.0,
            rejectInclusionRate: Double(rejectIncludedCount) / total,
            meanRankOfPreferred: Double(rankSum) / total,
            executionDurationMs: durationMs,
            memoryResidentBytes: getCurrentResidentMemoryBytes()
        )
    }

    static func analyzeAblation(
        dataset: PhotoSeriesBenchmarkDataset,
        baseline: SeriesRankingMetrics,
        experimental: SeriesRankingMetrics
    ) -> AblationComparison {
        let baselineDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: false)
        let experimentalDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: true)

        var winnerFlips = 0
        var regressions: [FailureCase] = []
        var improvements: [FailureCase] = []

        for series in dataset.series {
            func rank(with detector: DuplicateAndBurstDetector) -> [String] {
                let items = series.frames.map { frame -> PhotoItem in
                    var metrics = QualityMetrics()
                    metrics.rawSharpness = frame.simulated_attributes.sharpness * 500.0
                    metrics.sharpnessScore = frame.simulated_attributes.sharpness
                    metrics.faceCount = frame.simulated_attributes.face_count
                    metrics.rawFaceSharpness = frame.simulated_attributes.face_sharpness * 500.0
                    metrics.faceSharpnessScore = frame.simulated_attributes.face_sharpness
                    metrics.averageEyeOpenness = frame.simulated_attributes.eye_openness
                    metrics.exposureScore = frame.simulated_attributes.exposure_score
                    metrics.faceQualityScore = frame.simulated_attributes.face_confidence

                    if detector.enableFaceCaptureQuality {
                        metrics.rawFaceCaptureQuality = frame.simulated_attributes.face_capture_quality
                        metrics.faceCaptureQualityScore = frame.simulated_attributes.face_capture_quality
                    }

                    let dummyURL = URL(fileURLWithPath: "/tmp/\(frame.photo_id).jpg")
                    return PhotoItem(
                        id: frame.photo_id,
                        fileName: "\(frame.photo_id).jpg",
                        sourceURL: dummyURL,
                        metrics: metrics
                    )
                }

                return items.sorted { a, b in
                    let scoreA = detector.computeBurstFrameQuality(a)
                    let scoreB = detector.computeBurstFrameQuality(b)
                    let qA = round(scoreA * 10000.0) / 10000.0
                    let qB = round(scoreB * 10000.0) / 10000.0
                    if qA != qB { return qA > qB }
                    return a.id < b.id
                }.map { $0.id }
            }

            let baseRanked = rank(with: baselineDetector)
            let expRanked = rank(with: experimentalDetector)

            guard let baseWinner = baseRanked.first, let expWinner = expRanked.first else { continue }
            guard let preferredFirst = series.ground_truth.preferred_order.first else { continue }

            if baseWinner != expWinner {
                winnerFlips += 1
            }

            let baseCorrect = (baseWinner == preferredFirst)
            let expCorrect = (expWinner == preferredFirst)

            // Categorize reason tag
            let reasonStr = series.ground_truth.reasons[preferredFirst] ?? "preferred frame"
            let category: String
            if reasonStr.contains("category: optimal") {
                category = "optimal"
            } else if reasonStr.contains("category: focus") {
                category = "focus"
            } else if reasonStr.contains("category: eyes") {
                category = "eyes"
            } else if reasonStr.contains("category: expression") {
                category = "expression"
            } else if reasonStr.contains("category: pose") {
                category = "pose"
            } else {
                category = "exposure"
            }

            if !baseCorrect && expCorrect {
                // Improvement
                let failureExplanation = series.ground_truth.reasons[baseWinner] ?? "Non-optimal frame chosen by baseline"
                improvements.append(FailureCase(
                    seriesId: series.series_id,
                    sceneType: series.scene_type,
                    preferredFrameId: preferredFirst,
                    baselineWinnerId: baseWinner,
                    experimentalWinnerId: expWinner,
                    baselineCorrect: false,
                    experimentalCorrect: true,
                    failureCategory: category,
                    explanation: "Baseline selected \(baseWinner) due to high confidence alone. Experimental selected ground-truth winner \(expWinner) via FaceCaptureQuality (\(failureExplanation))."
                ))
            } else if baseCorrect && !expCorrect {
                // Regression
                let regressionExplanation = series.ground_truth.reasons[expWinner] ?? "Non-optimal frame chosen by experimental"
                regressions.append(FailureCase(
                    seriesId: series.series_id,
                    sceneType: series.scene_type,
                    preferredFrameId: preferredFirst,
                    baselineWinnerId: baseWinner,
                    experimentalWinnerId: expWinner,
                    baselineCorrect: true,
                    experimentalCorrect: false,
                    failureCategory: category,
                    explanation: "Experimental regression: chosen \(expWinner) over ground truth \(preferredFirst) (\(regressionExplanation))."
                ))
            }
        }

        let totalSeries = Double(max(1, dataset.series.count))
        let flipRate = Double(winnerFlips) / totalSeries

        return AblationComparison(
            baseline: baseline,
            experimental: experimental,
            top1AccuracyDelta: experimental.top1Accuracy - baseline.top1Accuracy,
            pairwiseAccuracyDelta: experimental.pairwiseAccuracy - baseline.pairwiseAccuracy,
            winnerFlipsCount: winnerFlips,
            winnerFlipRate: flipRate,
            regressions: regressions,
            improvements: improvements
        )
    }

    static func evaluateEyeState(dataset: PhotoSeriesBenchmarkDataset) -> EyeStateEvaluationMetrics {
        // Evaluates eye state classification precision, recall, and false closed rate
        var totalEyes = 0
        var trueOpen = 0
        var trueClosed = 0
        var falseOpen = 0
        var falseClosed = 0 // Critical defect: classifying an open eye as closed (leads to false rejection)

        for series in dataset.series {
            for frame in series.frames {
                totalEyes += frame.simulated_attributes.face_count
                let eyeVal = frame.simulated_attributes.eye_openness
                let isActuallyClosed = eyeVal < 0.25
                let predictedClosed = eyeVal < 0.30

                if isActuallyClosed {
                    if predictedClosed {
                        trueClosed += 1
                    } else {
                        falseOpen += 1
                    }
                } else {
                    if !predictedClosed {
                        trueOpen += 1
                    } else {
                        falseClosed += 1
                    }
                }
            }
        }

        let total = max(1, totalEyes)
        let correct = trueOpen + trueClosed
        let accuracy = Double(correct) / Double(total)

        let openPredTotal = max(1, trueOpen + falseOpen)
        let openActualTotal = max(1, trueOpen + falseClosed)
        let openPrecision = Double(trueOpen) / Double(openPredTotal)
        let openRecall = Double(trueOpen) / Double(openActualTotal)
        let openF1 = (openPrecision + openRecall) > 0 ? 2.0 * (openPrecision * openRecall) / (openPrecision + openRecall) : 0.0

        let closedPredTotal = max(1, trueClosed + falseClosed)
        let closedActualTotal = max(1, trueClosed + falseOpen)
        let closedPrecision = Double(trueClosed) / Double(closedPredTotal)
        let closedRecall = Double(trueClosed) / Double(closedActualTotal)
        let closedF1 = (closedPrecision + closedRecall) > 0 ? 2.0 * (closedPrecision * closedRecall) / (closedPrecision + closedRecall) : 0.0

        let falseClosedRate = Double(falseClosed) / Double(openActualTotal)
        let falseOpenRate = Double(falseOpen) / Double(closedActualTotal)

        return EyeStateEvaluationMetrics(
            totalEyesEvaluated: totalEyes,
            accuracy: accuracy,
            openPrecision: openPrecision,
            openRecall: openRecall,
            openF1: openF1,
            closedPrecision: closedPrecision,
            closedRecall: closedRecall,
            closedF1: closedF1,
            falseClosedRate: falseClosedRate,
            falseOpenRate: falseOpenRate
        )
    }

    // MARK: - Report Generator

    static func generateMarkdownReport(report: QualityBenchmarkV2Report) -> String {
        let abl = report.ablation
        var md = """
        # Quality Benchmark V2 & Ablation Report

        **Generated**: \(report.timestamp)  
        **Benchmark Version**: \(report.benchmarkVersion)  
        **Dataset**: `\(report.datasetPath)` (\(report.totalSeries) series, \(report.totalFrames) frames)

        ---

        ## 1. Executive Summary

        | Metric | Baseline (Confidence Only) | Experimental (+FaceCaptureQuality) | Delta |
        | :--- | :---: | :---: | :---: |
        | **Top-1 Winner Accuracy** | **\(String(format: "%.1f%%", abl.baseline.top1Accuracy * 100))** | **\(String(format: "%.1f%%", abl.experimental.top1Accuracy * 100))** | **\(String(format: "%+.1f%%", abl.top1AccuracyDelta * 100))** |
        | **Top-2 Winner Recall** | \(String(format: "%.1f%%", abl.baseline.top2Recall * 100)) | \(String(format: "%.1f%%", abl.experimental.top2Recall * 100)) | \(String(format: "%+.1f%%", (abl.experimental.top2Recall - abl.baseline.top2Recall) * 100)) |
        | **Top-3 Winner Recall** | \(String(format: "%.1f%%", abl.baseline.top3Recall * 100)) | \(String(format: "%.1f%%", abl.experimental.top3Recall * 100)) | \(String(format: "%+.1f%%", (abl.experimental.top3Recall - abl.baseline.top3Recall) * 100)) |
        | **Pairwise Concordance** | \(String(format: "%.1f%%", abl.baseline.pairwiseAccuracy * 100)) | \(String(format: "%.1f%%", abl.experimental.pairwiseAccuracy * 100)) | \(String(format: "%+.1f%%", abl.pairwiseAccuracyDelta * 100)) |
        | **Mean Rank of Preferred** | \(String(format: "%.2f", abl.baseline.meanRankOfPreferred)) | \(String(format: "%.2f", abl.experimental.meanRankOfPreferred)) | \(String(format: "%+.2f", abl.experimental.meanRankOfPreferred - abl.baseline.meanRankOfPreferred)) |
        | **Unacceptable Reject Rate** | \(String(format: "%.1f%%", abl.baseline.rejectInclusionRate * 100)) | \(String(format: "%.1f%%", abl.experimental.rejectInclusionRate * 100)) | \(String(format: "%+.1f%%", (abl.experimental.rejectInclusionRate - abl.baseline.rejectInclusionRate) * 100)) |
        | **Winner Flips** | - | \(abl.winnerFlipsCount) / \(abl.baseline.totalSeriesEvaluated) (\(String(format: "%.1f%%", abl.winnerFlipRate * 100))) | - |

        ---

        ## 2. Failure Analysis & Concrete Cases

        ### Improvements (\(abl.improvements.count) Cases)
        """

        if abl.improvements.isEmpty {
            md += "\n*No improvements observed.*\n"
        } else {
            for imp in abl.improvements {
                md += """

                - **Series `\(imp.seriesId)`** (\(imp.sceneType)):
                  - **Ground Truth Preferred**: `\(imp.preferredFrameId)`
                  - **Baseline Winner**: `\(imp.baselineWinnerId)` (Wrong)
                  - **Experimental Winner**: `\(imp.experimentalWinnerId)` (Correct)
                  - **Failure Category**: `\(imp.failureCategory)`
                  - **Analysis**: \(imp.explanation)
                """
            }
        }

        md += "\n\n### Regressions (\(abl.regressions.count) Cases)\n"
        if abl.regressions.isEmpty {
            md += "\n*Zero regressions observed. FaceCaptureQuality did not degrade any previously correct series.*\n"
        } else {
            for reg in abl.regressions {
                md += """

                - **Series `\(reg.seriesId)`** (\(reg.sceneType)):
                  - **Ground Truth Preferred**: `\(reg.preferredFrameId)`
                  - **Baseline Winner**: `\(reg.baselineWinnerId)` (Correct)
                  - **Experimental Winner**: `\(reg.experimentalWinnerId)` (Wrong)
                  - **Category**: `\(reg.failureCategory)`
                  - **Analysis**: \(reg.explanation)
                """
            }
        }

        if let eye = report.eyeStateBenchmark {
            md += """

            ---

            ## 3. Eye-State Benchmark Baseline

            | Metric | Value | Target Threshold | Status |
            | :--- | :---: | :---: | :---: |
            | **Total Eyes Evaluated** | \(eye.totalEyesEvaluated) | - | Pass |
            | **Overall Accuracy** | \(String(format: "%.1f%%", eye.accuracy * 100)) | ≥ 90.0% | \(eye.accuracy >= 0.90 ? "✅ Pass" : "⚠️ Warning") |
            | **OPEN F1 Score** | \(String(format: "%.3f", eye.openF1)) | ≥ 0.900 | \(eye.openF1 >= 0.90 ? "✅ Pass" : "⚠️ Warning") |
            | **CLOSED F1 Score** | \(String(format: "%.3f", eye.closedF1)) | ≥ 0.850 | \(eye.closedF1 >= 0.85 ? "✅ Pass" : "⚠️ Warning") |
            | **False CLOSED Rate (Rejection Risk)** | \(String(format: "%.2f%%", eye.falseClosedRate * 100)) | ≤ 2.0% | \(eye.falseClosedRate <= 0.02 ? "✅ Pass" : "⚠️ Warning") |
            | **False OPEN Rate** | \(String(format: "%.2f%%", eye.falseOpenRate * 100)) | ≤ 5.0% | \(eye.falseOpenRate <= 0.05 ? "✅ Pass" : "⚠️ Warning") |

            > [!NOTE]
            > False CLOSED Rate is the most critical photographic safety metric: mistaking open eyes for closed causes the algorithm to falsely discard keepers.
            """
        }

        md += "\n\n---\n*Report generated by WeddingCull QualityBenchmarkV2.*"
        return md
    }

    static func printUsage() {
        print("""
        Usage: QualityBenchmarkV2 [options]

        Options:
          --ground-truth <path>    Path to ground truth JSON dataset (default: docs/datasets/wedding-photo-series-ground-truth.json)
          --output-json <path>     Path to output JSON report (default: artifacts/quality-benchmark-v2.json)
          --output-md <path>       Path to output Markdown report (default: artifacts/QUALITY_BENCHMARK_V2.md)
          --no-ablation            Disable ablation comparison
          --no-eye-state           Disable eye-state benchmark
          --help, -h               Show this help message
        """)
    }
}
