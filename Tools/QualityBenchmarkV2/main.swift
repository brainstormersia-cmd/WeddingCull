import Foundation
import CoreGraphics
import ImageIO
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif
#if canImport(TestDatasetGeneratorLibrary)
import TestDatasetGeneratorLibrary
#endif
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Real-Image Benchmark Data Models (Labels Only, No Pre-Injected Features)

struct RealSeriesBenchmarkDataset: Codable {
    let version: String
    let dataset_name: String
    let description: String?
    let total_series: Int
    let total_frames: Int
    let series: [RealPhotoSeries]
}

struct RealPhotoSeries: Codable {
    let series_id: String
    let scene_type: String
    let description: String?
    let frames: [RealSeriesFrame]
    let ground_truth: SeriesGroundTruth
}

struct RealSeriesFrame: Codable {
    let photo_id: String
    let image_path: String
}

struct SeriesGroundTruth: Codable {
    let preferred_order: [String]
    let acceptable_keepers: [String]
    let unacceptable_rejects: [String]
    let reasons: [String: String]?
}

// MARK: - Synthetic Unit-Test Fixture Models

struct SyntheticFixtureDataset: Codable {
    let version: String
    let fixture_type: String?
    let dataset_name: String
    let description: String
    let total_series: Int
    let total_frames: Int
    let series: [SyntheticPhotoSeries]
}

struct SyntheticPhotoSeries: Codable {
    let series_id: String
    let scene_type: String
    let description: String
    let ground_truth: SeriesGroundTruth
    let frames: [SyntheticSeriesFrame]
}

struct SyntheticSeriesFrame: Codable {
    let photo_id: String
    let relative_time_seconds: Double
    let simulated_attributes: SyntheticAttributes
}

struct SyntheticAttributes: Codable {
    let sharpness: Double
    let face_count: Int
    let face_sharpness: Double
    let eye_openness: Double
    let face_confidence: Double
    let face_capture_quality: Double
    let exposure_score: Double
}

// MARK: - Ranking & Ablation Result Models

struct SeriesRankingMetrics: Codable, Sendable {
    let evaluationMode: String // "REAL_IMAGE_ANALYSIS" or "SYNTHETIC_LOGIC_VALIDATION"
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
    let failureCategory: String
    let explanation: String
}

struct AblationComparison: Codable, Sendable {
    let evaluationMode: String
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
    let realImageBenchmarkStatus: String
    let realImageBenchmarkDetails: String?
    let realImageAblation: AblationComparison?
    let syntheticLogicValidation: AblationComparison
    let eyeStateBenchmarkStatus: String
    let eyeStateBenchmarkNote: String
    let datasetBlockers: [String]
}

// MARK: - QualityBenchmarkV2 Runner

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

        var syntheticFixturePath = "docs/datasets/synthetic-ranking-fixture.json"
        var realSeriesManifestPath: String? = nil
        var outputJSONPath = "artifacts/quality-benchmark-v2.json"
        var outputMDPath = "artifacts/QUALITY_BENCHMARK_V2.md"

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--synthetic-fixture":
                if i + 1 < args.count { syntheticFixturePath = args[i + 1]; i += 1 }
            case "--real-series":
                if i + 1 < args.count { realSeriesManifestPath = args[i + 1]; i += 1 }
            case "--output-json":
                if i + 1 < args.count { outputJSONPath = args[i + 1]; i += 1 }
            case "--output-md":
                if i + 1 < args.count { outputMDPath = args[i + 1]; i += 1 }
            case "--help", "-h":
                printUsage()
                return
            default:
                break
            }
            i += 1
        }

        print("==================================================")
        print("🎯 WeddingCull Quality Benchmark V2")
        print("==================================================")

        var blockers: [String] = []

        // 1. Real Image Benchmark Evaluation (Actual Image Pixels)
        var realImageStatus = "NOT_MEASURED"
        var realImageDetails: String? = nil
        var realImageAblation: AblationComparison? = nil

        if let manifestPath = realSeriesManifestPath {
            print("\n--> Checking Real Image Benchmark manifest: \(manifestPath)")
            let (status, details, ablation) = evaluateRealImageBenchmark(manifestPath: manifestPath)
            realImageStatus = status
            realImageDetails = details
            realImageAblation = ablation
        } else {
            realImageStatus = "AWAITING_LABELED_DATASET"
            let msg = "No publicly licensed wedding burst dataset with fine-grained human curator ranking orders is currently present in the repository. The benchmark architecture is fully implemented to decode real CGImages and evaluate Vision observations when image files and ground-truth manifests are supplied."
            realImageDetails = msg
            blockers.append("Photographer ground truth burst dataset: No legally usable public wedding burst dataset with per-frame curator preference rankings exists; waiting for curated shoot donation.")
            print("\n[INFO] Real Image Benchmark: \(realImageStatus)")
            print("       \(msg)")
        }

        // 2. Synthetic Logic Validation (Unit-Test Invariant Fixture)
        print("\n--> Running Synthetic Logic Validation (Unit Test Fixture)...")
        print("    Path: \(syntheticFixturePath)")
        guard FileManager.default.fileExists(atPath: syntheticFixturePath) else {
            print("ERROR: Synthetic fixture missing at \(syntheticFixturePath)")
            exit(1)
        }

        guard let fixtureData = try? Data(contentsOf: URL(fileURLWithPath: syntheticFixturePath)),
              let fixture = try? JSONDecoder().decode(SyntheticFixtureDataset.self, from: fixtureData) else {
            print("ERROR: Failed to decode synthetic fixture JSON at \(syntheticFixturePath)")
            exit(1)
        }

        let syntheticAblation = evaluateSyntheticLogicValidation(fixture: fixture)
        print(String(format: "    [Synthetic Logic] Baseline Top-1:     %.1f%%", syntheticAblation.baseline.top1Accuracy * 100))
        print(String(format: "    [Synthetic Logic] Experimental Top-1: %.1f%%", syntheticAblation.experimental.top1Accuracy * 100))
        print(String(format: "    [Synthetic Logic] Top-1 Delta:        %+.1f%%", syntheticAblation.top1AccuracyDelta * 100))
        print(String(format: "    [Synthetic Logic] Pairwise Delta:     %+.1f%%", syntheticAblation.pairwiseAccuracyDelta * 100))
        print("    [Synthetic Logic] Winner Flips:       \(syntheticAblation.winnerFlipsCount) / \(syntheticAblation.baseline.totalSeriesEvaluated)")
        print("    [Synthetic Logic] Improvements:       \(syntheticAblation.improvements.count)")
        print("    [Synthetic Logic] Regressions:        \(syntheticAblation.regressions.count)")

        // 3. Eye-State Benchmark Status (Explicitly NOT MEASURED without real labeled in-the-wild crops)
        let eyeStateStatus = "NOT MEASURED"
        let eyeStateNote = "Eye-state benchmark requires actual image crops with independent ground-truth eye labels (e.g., CEW / Closed Eyes in the Wild). Fabricated or synthetic metrics are omitted."
        blockers.append("Eye-state ground truth dataset: Awaiting integration of verified, legally permissible in-the-wild eye-crop benchmark dataset.")

        // 4. Assemble Report
        let nowFormatter = ISO8601DateFormatter()
        let report = QualityBenchmarkV2Report(
            timestamp: nowFormatter.string(from: Date()),
            benchmarkVersion: "2.1.0",
            realImageBenchmarkStatus: realImageStatus,
            realImageBenchmarkDetails: realImageDetails,
            realImageAblation: realImageAblation,
            syntheticLogicValidation: syntheticAblation,
            eyeStateBenchmarkStatus: eyeStateStatus,
            eyeStateBenchmarkNote: eyeStateNote,
            datasetBlockers: blockers
        )

        // 5. Write JSON Artifact
        do {
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try jsonEncoder.encode(report)
            let outURL = URL(fileURLWithPath: outputJSONPath)
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outURL)
            print("\n[OK] Wrote benchmark JSON: \(outputJSONPath)")
        } catch {
            print("WARNING: Failed to write JSON output: \(error)")
        }

        // 6. Write Markdown Artifact
        let mdContent = generateMarkdownReport(report: report)
        do {
            let mdURL = URL(fileURLWithPath: outputMDPath)
            try FileManager.default.createDirectory(at: mdURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try mdContent.write(to: mdURL, atomically: true, encoding: .utf8)
            print("[OK] Wrote benchmark markdown: \(outputMDPath)")
        } catch {
            print("WARNING: Failed to write Markdown output: \(error)")
        }

        print("\n==================================================")
        print("✅ Quality Benchmark V2 Execution Completed")
        print("==================================================")
    }

    // MARK: - Real Image Evaluation Logic

    static func evaluateRealImageBenchmark(manifestPath: String) -> (String, String, AblationComparison?) {
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            return ("FAILED", "Manifest file not found at \(manifestPath)", nil)
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let dataset = try? JSONDecoder().decode(RealSeriesBenchmarkDataset.self, from: data) else {
            return ("FAILED", "Failed to parse real-image series manifest JSON at \(manifestPath)", nil)
        }

        let qualityAnalyzer = TechnicalQualityAnalyzer()
        let faceRecognizer = FaceIdentityRecognizer()

        var totalImagesFound = 0
        var totalImagesMissing = 0

        // Check image availability
        for s in dataset.series {
            for f in s.frames {
                if FileManager.default.fileExists(atPath: f.image_path) {
                    totalImagesFound += 1
                } else {
                    totalImagesMissing += 1
                }
            }
        }

        if totalImagesFound == 0 {
            let details = "Manifest specified \(dataset.total_frames) frames across \(dataset.total_series) series, but 0 image files were found on disk. Real image pixel analysis could not run."
            return ("AWAITING_IMAGE_FILES", details, nil)
        }

        print("Found \(totalImagesFound) real image files on disk (\(totalImagesMissing) missing). Analyzing pixels...")

        func analyzeSeries(withCQ: Bool) -> SeriesRankingMetrics {
            let detector = DuplicateAndBurstDetector(enableFaceCaptureQuality: withCQ)
            let tStart = CFAbsoluteTimeGetCurrent()

            var top1 = 0
            var top2 = 0
            var top3 = 0
            var rankSum = 0
            var correctPairs = 0
            var totalPairs = 0
            var rejectCount = 0

            for s in dataset.series {
                var items: [PhotoItem] = []
                for f in s.frames {
                    guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: f.image_path) as CFURL, nil),
                          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                        continue
                    }

                    // 1. Real Technical Quality Analysis on Image Pixels
                    let tech = qualityAnalyzer.analyze(cgImage: cgImage)

                    // 2. Real Face Recognition & Capture Quality via Apple Vision
                    let faces = faceRecognizer.extractFacesWithIdentity(from: cgImage, enableFaceCaptureQuality: withCQ)

                    // 3. Real Crop-based Face Sharpness
                    var faceSharpnesses: [Double] = []
                    for face in faces {
                        let cropSharp = qualityAnalyzer.computeRegionSharpness(cgImage: cgImage, normalizedRect: face.boundingBox)
                        faceSharpnesses.append(cropSharp)
                    }

                    var metrics = QualityMetrics()
                    metrics.rawSharpness = tech.rawSharpness
                    metrics.meanLuminance = tech.meanLuminance
                    metrics.shadowClipping = tech.shadowClipping
                    metrics.highlightClipping = tech.highlightClipping
                    metrics.compositionProxyScore = tech.compositionProxyScore
                    metrics.faceCount = faces.count

                    if !faces.isEmpty {
                        let totalConf = faces.reduce(0.0) { $0 + $1.detectionConfidence }
                        metrics.faceQualityScore = totalConf / Double(faces.count)
                        let totalEyes = faces.reduce(0.0) { $0 + $1.eyeOpenness }
                        metrics.averageEyeOpenness = totalEyes / Double(faces.count)
                        if withCQ {
                            let validCQs = faces.compactMap { $0.faceCaptureQuality }
                            if !validCQs.isEmpty {
                                let avgCQ = validCQs.reduce(0.0, +) / Double(validCQs.count)
                                metrics.rawFaceCaptureQuality = avgCQ
                                metrics.faceCaptureQualityScore = avgCQ
                            }
                        }
                        metrics.rawFaceSharpness = faceSharpnesses.reduce(0.0, +) / Double(faceSharpnesses.count)
                    }

                    let item = PhotoItem(
                        id: f.photo_id,
                        fileName: URL(fileURLWithPath: f.image_path).lastPathComponent,
                        sourceURL: URL(fileURLWithPath: f.image_path),
                        metrics: metrics
                    )
                    items.append(item)
                }

                guard items.count >= 2 else { continue }

                // Rank with DuplicateAndBurstDetector
                let ranked = items.sorted { a, b in
                    let sA = detector.computeBurstFrameQuality(a)
                    let sB = detector.computeBurstFrameQuality(b)
                    let qA = round(sA * 10000.0) / 10000.0
                    let qB = round(sB * 10000.0) / 10000.0
                    if qA != qB { return qA > qB }
                    return a.id < b.id
                }

                guard let prefFirst = s.ground_truth.preferred_order.first else { continue }
                let rankedIDs = ranked.map { $0.id }

                if rankedIDs.first == prefFirst { top1 += 1 }
                if rankedIDs.prefix(2).contains(prefFirst) { top2 += 1 }
                if rankedIDs.prefix(3).contains(prefFirst) { top3 += 1 }

                if let idx = rankedIDs.firstIndex(of: prefFirst) {
                    rankSum += (idx + 1)
                } else {
                    rankSum += rankedIDs.count
                }

                if let winner = rankedIDs.first, s.ground_truth.unacceptable_rejects.contains(winner) {
                    rejectCount += 1
                }

                let prefOrder = s.ground_truth.preferred_order
                for p1 in 0..<prefOrder.count {
                    for p2 in (p1 + 1)..<prefOrder.count {
                        let idA = prefOrder[p1]
                        let idB = prefOrder[p2]
                        guard let rA = rankedIDs.firstIndex(of: idA), let rB = rankedIDs.firstIndex(of: idB) else { continue }
                        totalPairs += 1
                        if rA < rB { correctPairs += 1 }
                    }
                }
            }

            let durMs = (CFAbsoluteTimeGetCurrent() - tStart) * 1000.0
            let total = Double(max(1, dataset.series.count))

            return SeriesRankingMetrics(
                evaluationMode: "REAL_IMAGE_ANALYSIS",
                configurationName: withCQ ? "Real Image (+FaceCaptureQuality)" : "Real Image (Baseline Confidence Only)",
                enableFaceCaptureQuality: withCQ,
                totalSeriesEvaluated: dataset.series.count,
                top1Accuracy: Double(top1) / total,
                top2Recall: Double(top2) / total,
                top3Recall: Double(top3) / total,
                pairwiseAccuracy: totalPairs > 0 ? Double(correctPairs) / Double(totalPairs) : 1.0,
                rejectInclusionRate: Double(rejectCount) / total,
                meanRankOfPreferred: Double(rankSum) / total,
                executionDurationMs: durMs,
                memoryResidentBytes: getCurrentResidentMemoryBytes()
            )
        }

        let baseResult = analyzeSeries(withCQ: false)
        let expResult = analyzeSeries(withCQ: true)

        let ablation = AblationComparison(
            evaluationMode: "REAL_IMAGE_ANALYSIS",
            baseline: baseResult,
            experimental: expResult,
            top1AccuracyDelta: expResult.top1Accuracy - baseResult.top1Accuracy,
            pairwiseAccuracyDelta: expResult.pairwiseAccuracy - baseResult.pairwiseAccuracy,
            winnerFlipsCount: 0,
            winnerFlipRate: 0.0,
            regressions: [],
            improvements: []
        )

        return ("EXECUTED", "Analyzed \(totalImagesFound) real image files across \(dataset.series.count) series.", ablation)
    }

    // MARK: - Synthetic Logic Validation Logic

    static func evaluateSyntheticLogicValidation(fixture: SyntheticFixtureDataset) -> AblationComparison {
        let baselineDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: false)
        let experimentalDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: true)

        func evaluate(with detector: DuplicateAndBurstDetector, configName: String) -> SeriesRankingMetrics {
            let tStart = CFAbsoluteTimeGetCurrent()
            var top1 = 0
            var top2 = 0
            var top3 = 0
            var rankSum = 0
            var correctPairs = 0
            var totalPairs = 0
            var rejectCount = 0

            for series in fixture.series {
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

                    return PhotoItem(
                        id: frame.photo_id,
                        fileName: "\(frame.photo_id).jpg",
                        sourceURL: URL(fileURLWithPath: "/fixture/\(frame.photo_id).jpg"),
                        metrics: metrics
                    )
                }

                let ranked = items.sorted { a, b in
                    let sA = detector.computeBurstFrameQuality(a)
                    let sB = detector.computeBurstFrameQuality(b)
                    let qA = round(sA * 10000.0) / 10000.0
                    let qB = round(sB * 10000.0) / 10000.0
                    if qA != qB { return qA > qB }
                    return a.id < b.id
                }

                guard let prefFirst = series.ground_truth.preferred_order.first else { continue }
                let rankedIDs = ranked.map { $0.id }

                if rankedIDs.first == prefFirst { top1 += 1 }
                if rankedIDs.prefix(2).contains(prefFirst) { top2 += 1 }
                if rankedIDs.prefix(3).contains(prefFirst) { top3 += 1 }

                if let idx = rankedIDs.firstIndex(of: prefFirst) {
                    rankSum += (idx + 1)
                } else {
                    rankSum += rankedIDs.count
                }

                if let winner = rankedIDs.first, series.ground_truth.unacceptable_rejects.contains(winner) {
                    rejectCount += 1
                }

                let prefOrder = series.ground_truth.preferred_order
                for p1 in 0..<prefOrder.count {
                    for p2 in (p1 + 1)..<prefOrder.count {
                        let idA = prefOrder[p1]
                        let idB = prefOrder[p2]
                        guard let rA = rankedIDs.firstIndex(of: idA), let rB = rankedIDs.firstIndex(of: idB) else { continue }
                        totalPairs += 1
                        if rA < rB { correctPairs += 1 }
                    }
                }
            }

            let durMs = (CFAbsoluteTimeGetCurrent() - tStart) * 1000.0
            let total = Double(max(1, fixture.series.count))

            return SeriesRankingMetrics(
                evaluationMode: "SYNTHETIC_LOGIC_VALIDATION",
                configurationName: configName,
                enableFaceCaptureQuality: detector.enableFaceCaptureQuality,
                totalSeriesEvaluated: fixture.series.count,
                top1Accuracy: Double(top1) / total,
                top2Recall: Double(top2) / total,
                top3Recall: Double(top3) / total,
                pairwiseAccuracy: totalPairs > 0 ? Double(correctPairs) / Double(totalPairs) : 1.0,
                rejectInclusionRate: Double(rejectCount) / total,
                meanRankOfPreferred: Double(rankSum) / total,
                executionDurationMs: durMs,
                memoryResidentBytes: getCurrentResidentMemoryBytes()
            )
        }

        let baseResult = evaluate(with: baselineDetector, configName: "Synthetic Baseline (Confidence Only)")
        let expResult = evaluate(with: experimentalDetector, configName: "Synthetic Experimental (+FaceCaptureQuality)")

        // Identify winner flips, improvements, regressions
        var winnerFlips = 0
        var improvements: [FailureCase] = []
        var regressions: [FailureCase] = []

        for series in fixture.series {
            func rankSeries(detector: DuplicateAndBurstDetector) -> [String] {
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
                    return PhotoItem(
                        id: frame.photo_id,
                        fileName: "\(frame.photo_id).jpg",
                        sourceURL: URL(fileURLWithPath: "/fixture/\(frame.photo_id).jpg"),
                        metrics: metrics
                    )
                }

                return items.sorted { a, b in
                    let sA = detector.computeBurstFrameQuality(a)
                    let sB = detector.computeBurstFrameQuality(b)
                    let qA = round(sA * 10000.0) / 10000.0
                    let qB = round(sB * 10000.0) / 10000.0
                    if qA != qB { return qA > qB }
                    return a.id < b.id
                }.map { $0.id }
            }

            let baseRank = rankSeries(detector: baselineDetector)
            let expRank = rankSeries(detector: experimentalDetector)

            guard let baseWinner = baseRank.first, let expWinner = expRank.first else { continue }
            guard let preferredFirst = series.ground_truth.preferred_order.first else { continue }

            if baseWinner != expWinner {
                winnerFlips += 1
            }

            let baseCorrect = (baseWinner == preferredFirst)
            let expCorrect = (expWinner == preferredFirst)

            let reasonStr = series.ground_truth.reasons?[preferredFirst] ?? "preferred"
            let cat: String
            if reasonStr.contains("category: optimal") { cat = "optimal" }
            else if reasonStr.contains("category: focus") { cat = "focus" }
            else if reasonStr.contains("category: eyes") { cat = "eyes" }
            else if reasonStr.contains("category: expression") { cat = "expression" }
            else if reasonStr.contains("category: pose") { cat = "pose" }
            else { cat = "exposure" }

            if !baseCorrect && expCorrect {
                let note = series.ground_truth.reasons?[baseWinner] ?? "Defective frame"
                improvements.append(FailureCase(
                    seriesId: series.series_id,
                    sceneType: series.scene_type,
                    preferredFrameId: preferredFirst,
                    baselineWinnerId: baseWinner,
                    experimentalWinnerId: expWinner,
                    baselineCorrect: false,
                    experimentalCorrect: true,
                    failureCategory: cat,
                    explanation: "Baseline chose \(baseWinner) on detection confidence alone. Experimental selected \(expWinner) via FaceCaptureQuality (\(note))."
                ))
            } else if baseCorrect && !expCorrect {
                let note = series.ground_truth.reasons?[expWinner] ?? "Defective frame"
                regressions.append(FailureCase(
                    seriesId: series.series_id,
                    sceneType: series.scene_type,
                    preferredFrameId: preferredFirst,
                    baselineWinnerId: baseWinner,
                    experimentalWinnerId: expWinner,
                    baselineCorrect: true,
                    experimentalCorrect: false,
                    failureCategory: cat,
                    explanation: "Experimental chose non-preferred frame \(expWinner) (\(note))."
                ))
            }
        }

        let total = Double(max(1, fixture.series.count))

        return AblationComparison(
            evaluationMode: "SYNTHETIC_LOGIC_VALIDATION",
            baseline: baseResult,
            experimental: expResult,
            top1AccuracyDelta: expResult.top1Accuracy - baseResult.top1Accuracy,
            pairwiseAccuracyDelta: expResult.pairwiseAccuracy - baseResult.pairwiseAccuracy,
            winnerFlipsCount: winnerFlips,
            winnerFlipRate: Double(winnerFlips) / total,
            regressions: regressions,
            improvements: improvements
        )
    }

    // MARK: - Markdown Report Generation

    static func generateMarkdownReport(report: QualityBenchmarkV2Report) -> String {
        let syn = report.syntheticLogicValidation
        var md = """
        # Quality Benchmark V2 Report

        **Generated**: \(report.timestamp)  
        **Benchmark Architecture Version**: \(report.benchmarkVersion)  

        ---

        ## 1. Real Image Benchmark Status

        * **Status**: `\(report.realImageBenchmarkStatus)`  
        * **Details**: \(report.realImageBenchmarkDetails ?? "None")  
        """

        if let real = report.realImageAblation {
            md += """

            ### Real Image Empirical Results

            | Metric | Baseline (Confidence Only) | Experimental (+FaceCaptureQuality) | Delta |
            | :--- | :---: | :---: | :---: |
            | **Top-1 Winner Accuracy** | \(String(format: "%.1f%%", real.baseline.top1Accuracy * 100)) | \(String(format: "%.1f%%", real.experimental.top1Accuracy * 100)) | \(String(format: "%+.1f%%", real.top1AccuracyDelta * 100)) |
            | **Top-2 Winner Recall** | \(String(format: "%.1f%%", real.baseline.top2Recall * 100)) | \(String(format: "%.1f%%", real.experimental.top2Recall * 100)) | \(String(format: "%+.1f%%", (real.experimental.top2Recall - real.baseline.top2Recall) * 100)) |
            | **Top-3 Winner Recall** | \(String(format: "%.1f%%", real.baseline.top3Recall * 100)) | \(String(format: "%.1f%%", real.experimental.top3Recall * 100)) | \(String(format: "%+.1f%%", (real.experimental.top3Recall - real.baseline.top3Recall) * 100)) |
            | **Pairwise Concordance** | \(String(format: "%.1f%%", real.baseline.pairwiseAccuracy * 100)) | \(String(format: "%.1f%%", real.experimental.pairwiseAccuracy * 100)) | \(String(format: "%+.1f%%", real.pairwiseAccuracyDelta * 100)) |
            """
        } else {
            md += """

            > [!IMPORTANT]
            > **Dataset Blocker**: No legally permissible public wedding photography dataset with fine-grained human curator ranking orders (1st, 2nd, 3rd, blink, reject) currently exists in the repository.
            > The pipeline and benchmark infrastructure are fully implemented to decode real `CGImage`s and query Apple Vision directly when image manifests are supplied.
            """
        }

        md += """

        ---

        ## 2. Synthetic Logic Validation (Unit Test Fixture)

        > [!NOTE]
        > The following metrics are derived from `docs/datasets/synthetic-ranking-fixture.json`.
        > They validate ranking math, Kendall's tau pairwise concordance, and ablation control flow determinism.
        > They do **NOT** represent real photographic quality claims.

        | Metric | Baseline (Confidence Only) | Experimental (+FaceCaptureQuality) | Delta |
        | :--- | :---: | :---: | :---: |
        | **Top-1 Winner Accuracy** | \(String(format: "%.1f%%", syn.baseline.top1Accuracy * 100)) | \(String(format: "%.1f%%", syn.experimental.top1Accuracy * 100)) | \(String(format: "%+.1f%%", syn.top1AccuracyDelta * 100)) |
        | **Top-2 Winner Recall** | \(String(format: "%.1f%%", syn.baseline.top2Recall * 100)) | \(String(format: "%.1f%%", syn.experimental.top2Recall * 100)) | \(String(format: "%+.1f%%", (syn.experimental.top2Recall - syn.baseline.top2Recall) * 100)) |
        | **Top-3 Winner Recall** | \(String(format: "%.1f%%", syn.baseline.top3Recall * 100)) | \(String(format: "%.1f%%", syn.experimental.top3Recall * 100)) | \(String(format: "%+.1f%%", (syn.experimental.top3Recall - syn.baseline.top3Recall) * 100)) |
        | **Pairwise Concordance** | \(String(format: "%.1f%%", syn.baseline.pairwiseAccuracy * 100)) | \(String(format: "%.1f%%", syn.experimental.pairwiseAccuracy * 100)) | \(String(format: "%+.1f%%", syn.pairwiseAccuracyDelta * 100)) |
        | **Mean Rank of Preferred** | \(String(format: "%.2f", syn.baseline.meanRankOfPreferred)) | \(String(format: "%.2f", syn.experimental.meanRankOfPreferred)) | \(String(format: "%+.2f", syn.experimental.meanRankOfPreferred - syn.baseline.meanRankOfPreferred)) |
        | **Unacceptable Reject Rate** | \(String(format: "%.1f%%", syn.baseline.rejectInclusionRate * 100)) | \(String(format: "%.1f%%", syn.experimental.rejectInclusionRate * 100)) | \(String(format: "%+.1f%%", (syn.experimental.rejectInclusionRate - syn.baseline.rejectInclusionRate) * 100)) |
        | **Winner Flips** | - | \(syn.winnerFlipsCount) / \(syn.baseline.totalSeriesEvaluated) (\(String(format: "%.1f%%", syn.winnerFlipRate * 100))) | - |

        ### Synthetic Logic Failure Analysis
        * **Improvements**: \(syn.improvements.count) cases where FaceCaptureQuality resolves confusions caused by high confidence on defective frames.
        * **Regressions**: \(syn.regressions.count) cases.

        ---

        ## 3. Eye-State Benchmark Status

        * **Status**: `\(report.eyeStateBenchmarkStatus)`  
        * **Note**: \(report.eyeStateBenchmarkNote)  

        ---

        ## 4. Current Dataset Blockers

        """

        for b in report.datasetBlockers {
            md += "* \(b)\n"
        }

        md += "\n---\n*Report generated by WeddingCull QualityBenchmarkV2.*"
        return md
    }

    static func printUsage() {
        print("""
        Usage: QualityBenchmarkV2 [options]

        Options:
          --synthetic-fixture <path>  Path to synthetic logic validation fixture (default: docs/datasets/synthetic-ranking-fixture.json)
          --real-series <path>        Path to real-image series ground truth manifest (labels only)
          --output-json <path>        Path to output JSON report (default: artifacts/quality-benchmark-v2.json)
          --output-md <path>          Path to output Markdown report (default: artifacts/QUALITY_BENCHMARK_V2.md)
          --help, -h                  Show this help message
        """)
    }
}
