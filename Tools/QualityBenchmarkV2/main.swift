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
    let ground_truth: SyntheticSeriesGroundTruth
    let frames: [SyntheticSeriesFrame]
}

struct SyntheticSeriesGroundTruth: Codable {
    let preferred_order: [String]
    let acceptable_keepers: [String]
    let unacceptable_rejects: [String]
    let reasons: [String: String]?
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

// MARK: - Benchmark Metrics & Ablation Result Models

struct SeriesRankingMetrics: Codable, Sendable {
    let evaluationMode: String // "REAL_IMAGE_ANALYSIS" or "SYNTHETIC_LOGIC_VALIDATION"
    let configurationName: String
    let enableFaceCaptureQuality: Bool
    let manifestSeriesCount: Int
    let evaluatedSeriesCount: Int
    let excludedSeriesCount: Int
    let top1Accuracy: Double
    let top2Recall: Double
    let top3Recall: Double
    let pairwiseAccuracy: Double
    let pairwiseEvaluatedPairs: Int
    let pairwiseTotalAnnotatedPairs: Int
    let pairwiseCoverage: Double
    let weightedPairwiseAccuracy: Double?
    let meanAnnotatorAgreement: Double?
    let ambiguousPairRate: Double?
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
    let improvementsCount: Int
    let regressionsCount: Int
    let neutralFlipsCount: Int
    let noFlipCount: Int
    let regressions: [FailureCase]
    let improvements: [FailureCase]
}

struct RealSeriesRankingReport: Codable, Sendable {
    let benchmarkVersion: String
    let timestamp: String
    let manifestSeriesCount: Int
    let evaluatedSeriesCount: Int
    let excludedSeriesCount: Int
    let seriesEvaluations: [SeriesEvaluationRecord]
    let seriesRankings: [SeriesRankingDetail]
}

struct QualityBenchmarkV2Report: Codable, Sendable {
    let timestamp: String
    let benchmarkVersion: String
    let realImageBenchmarkStatus: String
    let realImageBenchmarkDetails: String?
    let realImageRankingDetailsPath: String?
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
        var photoTriageRootPath: String? = nil
        var outputJSONPath = "artifacts/quality-benchmark-v2.json"
        var outputMDPath = "artifacts/QUALITY_BENCHMARK_V2.md"
        var detailsJSONPath = "artifacts/real-series-ranking-details.json"

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--synthetic-fixture":
                if i + 1 < args.count { syntheticFixturePath = args[i + 1]; i += 1 }
            case "--real-series":
                if i + 1 < args.count { realSeriesManifestPath = args[i + 1]; i += 1 }
            case "--photo-triage-root":
                if i + 1 < args.count { photoTriageRootPath = args[i + 1]; i += 1 }
            case "--output-json":
                if i + 1 < args.count { outputJSONPath = args[i + 1]; i += 1 }
            case "--output-md":
                if i + 1 < args.count { outputMDPath = args[i + 1]; i += 1 }
            case "--details-json":
                if i + 1 < args.count { detailsJSONPath = args[i + 1]; i += 1 }
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
        var realImageStatus = "AWAITING_LABELED_DATASET"
        var realImageDetails: String? = nil
        var realImageRankingPath: String? = nil
        var realImageAblation: AblationComparison? = nil

        if let ptRoot = photoTriageRootPath {
            print("\n--> Inspecting Photo Triage root: \(ptRoot)")
            let adapter = PhotoTriageAdapter()
            let rootURL = URL(fileURLWithPath: ptRoot)
            let inspection = adapter.inspect(rootURL: rootURL)
            if inspection.isAvailable {
                do {
                    let dataset = try adapter.loadDataset(from: rootURL)
                    let (status, details, ablation, rPath) = evaluateRealImageDataset(
                        dataset: dataset,
                        detailsPath: detailsJSONPath
                    )
                    realImageStatus = status
                    realImageDetails = details
                    realImageAblation = ablation
                    realImageRankingPath = rPath
                } catch {
                    realImageStatus = "AWAITING_EXTERNAL_DATASET"
                    realImageDetails = error.localizedDescription
                    blockers.append("Photo Triage external dataset: \(error.localizedDescription)")
                    print("[INFO] Photo Triage: \(realImageStatus) (\(error.localizedDescription))")
                }
            } else {
                realImageStatus = "AWAITING_EXTERNAL_DATASET"
                realImageDetails = inspection.statusMessage
                blockers.append("Photo Triage external dataset: \(inspection.statusMessage)")
                print("[INFO] Photo Triage: \(realImageStatus)")
                print("       \(inspection.statusMessage)")
            }
        } else if let manifestPath = realSeriesManifestPath {
            print("\n--> Checking Real Image Benchmark manifest: \(manifestPath)")
            guard FileManager.default.fileExists(atPath: manifestPath) else {
                realImageStatus = "FAILED"
                realImageDetails = "Manifest file not found at \(manifestPath)"
                print("ERROR: Manifest missing at \(manifestPath)")
                exit(1)
            }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                  let dataset = try? JSONDecoder().decode(RealSeriesBenchmarkDataset.self, from: data) else {
                realImageStatus = "FAILED"
                realImageDetails = "Failed to decode RealSeriesBenchmarkDataset JSON at \(manifestPath)"
                print("ERROR: Manifest decode failed at \(manifestPath)")
                exit(1)
            }
            let (status, details, ablation, rPath) = evaluateRealImageDataset(
                dataset: dataset,
                detailsPath: detailsJSONPath
            )
            realImageStatus = status
            realImageDetails = details
            realImageAblation = ablation
            realImageRankingPath = rPath
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
            benchmarkVersion: "2.2.0",
            realImageBenchmarkStatus: realImageStatus,
            realImageBenchmarkDetails: realImageDetails,
            realImageRankingDetailsPath: realImageRankingPath,
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

    static func evaluateRealImageDataset(
        dataset: RealSeriesBenchmarkDataset,
        detailsPath: String
    ) -> (String, String, AblationComparison?, String?) {
        let qualityAnalyzer = TechnicalQualityAnalyzer()
        let faceRecognizer = FaceIdentityRecognizer()
        let scorer = QualityScorer()

        let baseDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: false)
        let expDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: true)

        let tStart = CFAbsoluteTimeGetCurrent()

        var seriesEvaluations: [SeriesEvaluationRecord] = []
        var seriesRankings: [SeriesRankingDetail] = []

        var evaluatedSeriesCount = 0
        var excludedSeriesCount = 0

        // Pairwise metrics
        var totalAnnotatedPairs = 0
        var evaluatedPairs = 0
        var baseCorrectPairs = 0
        var expCorrectPairs = 0
        var baseWeightedCorrect: Double = 0.0
        var expWeightedCorrect: Double = 0.0
        var totalVotes = 0
        var agreementSum: Double = 0.0
        var ambiguousPairsCount = 0

        // Ranking metrics (when preferred_order is supplied)
        var rankingSeriesCount = 0
        var baseTop1 = 0
        var expTop1 = 0
        var baseTop2 = 0
        var expTop2 = 0
        var baseTop3 = 0
        var expTop3 = 0
        var baseRankSum = 0
        var expRankSum = 0
        var baseRejectCount = 0
        var expRejectCount = 0

        // Winner flip metrics
        var winnerFlips = 0
        var improvements: [FailureCase] = []
        var regressions: [FailureCase] = []
        var neutralFlips = 0
        var noFlips = 0

        for s in dataset.series {
            let expectedFrames = s.frames.count
            var foundFrames = 0
            var missingPhotoIds: [String] = []
            var decodeFailures: [String] = []
            var decodedImages: [String: CGImage] = [:]

            for f in s.frames {
                let url = URL(fileURLWithPath: f.image_path)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    missingPhotoIds.append(f.photo_id)
                    continue
                }
                guard let cg = PreviewPipeline.decodeProductionPreview(from: url, maxPixelSize: 1000) else {
                    decodeFailures.append(f.photo_id)
                    continue
                }
                decodedImages[f.photo_id] = cg
                foundFrames += 1
            }

            // Completeness check:
            // If preferred_order is provided, every preferred frame must be found and decoded
            if let pref = s.ground_truth.preferred_order {
                for pid in pref {
                    if decodedImages[pid] == nil && !missingPhotoIds.contains(pid) && !decodeFailures.contains(pid) {
                        missingPhotoIds.append(pid)
                    }
                }
            }

            let isEvaluable = missingPhotoIds.isEmpty && decodeFailures.isEmpty && foundFrames >= 2

            if !isEvaluable {
                let reason: String
                if !missingPhotoIds.isEmpty {
                    reason = "Missing frame files: [\(missingPhotoIds.joined(separator: ", "))]"
                } else if !decodeFailures.isEmpty {
                    reason = "Decode failures on frames: [\(decodeFailures.joined(separator: ", "))]"
                } else {
                    reason = "Fewer than 2 frames available (\(foundFrames) found)"
                }
                seriesEvaluations.append(SeriesEvaluationRecord(
                    seriesId: s.series_id,
                    sceneType: s.scene_type,
                    expectedFrameCount: expectedFrames,
                    foundFrameCount: foundFrames,
                    missingPhotoIds: missingPhotoIds,
                    decodeFailures: decodeFailures,
                    isEvaluable: false,
                    exclusionReason: reason
                ))
                excludedSeriesCount += 1
                continue
            }

            // Series is completely valid and evaluable
            seriesEvaluations.append(SeriesEvaluationRecord(
                seriesId: s.series_id,
                sceneType: s.scene_type,
                expectedFrameCount: expectedFrames,
                foundFrameCount: foundFrames,
                missingPhotoIds: [],
                decodeFailures: [],
                isEvaluable: true,
                exclusionReason: nil
            ))
            evaluatedSeriesCount += 1

            // --- SINGLE-PASS MEASUREMENT OF REAL PIXELS ---
            var measuredFeatures: [String: MeasuredPhotoFeatures] = [:]
            var baselineItems: [PhotoItem] = []
            var experimentalItems: [PhotoItem] = []

            for f in s.frames {
                guard let previewCG = decodedImages[f.photo_id] else { continue }

                // 1. Technical quality analysis (scaled to 800px device gray context)
                let tech = qualityAnalyzer.analyze(cgImage: previewCG)

                // 2. Apple Vision Face Landmarks and FaceCaptureQuality (1000px face input)
                let faces = faceRecognizer.extractFacesWithIdentity(from: previewCG, enableFaceCaptureQuality: true)

                // 3. Genuine crop-based face sharpness
                var faceSharpnesses: [Double] = []
                for face in faces {
                    let cropSharp = qualityAnalyzer.computeRegionSharpness(cgImage: previewCG, normalizedRect: face.boundingBox)
                    faceSharpnesses.append(cropSharp)
                }

                let avgFaceSharp = faceSharpnesses.isEmpty ? nil : (faceSharpnesses.reduce(0.0, +) / Double(faceSharpnesses.count))
                let avgConf = faces.isEmpty ? 0.8 : (faces.reduce(0.0) { $0 + $1.detectionConfidence } / Double(faces.count))
                let avgEye = faces.isEmpty ? nil : (faces.reduce(0.0) { $0 + $1.eyeOpenness } / Double(faces.count))
                let validCQs = faces.compactMap { $0.faceCaptureQuality }
                let avgCQ = validCQs.isEmpty ? nil : (validCQs.reduce(0.0, +) / Double(validCQs.count))

                let expScore = QualityScorer.computeExposureScore(
                    meanLuminance: tech.meanLuminance,
                    shadowClipping: tech.shadowClipping,
                    highlightClipping: tech.highlightClipping
                )

                let feat = MeasuredPhotoFeatures(
                    photoId: f.photo_id,
                    rawSharpness: tech.rawSharpness,
                    faceSharpness: avgFaceSharp,
                    detectionConfidence: avgConf,
                    faceCaptureQuality: avgCQ,
                    eyeOpenness: avgEye,
                    meanLuminance: tech.meanLuminance,
                    shadowClipping: tech.shadowClipping,
                    highlightClipping: tech.highlightClipping,
                    exposureScore: expScore
                )
                measuredFeatures[f.photo_id] = feat

                // Baseline Item (zero FaceCaptureQuality leakage)
                var mBase = QualityMetrics()
                mBase.rawSharpness = tech.rawSharpness
                mBase.rawFaceSharpness = avgFaceSharp
                mBase.faceCount = faces.count
                mBase.faceQualityScore = avgConf
                mBase.rawFaceCaptureQuality = nil
                mBase.faceCaptureQualityScore = nil
                mBase.averageEyeOpenness = avgEye
                mBase.meanLuminance = tech.meanLuminance
                mBase.shadowClipping = tech.shadowClipping
                mBase.highlightClipping = tech.highlightClipping
                mBase.compositionProxyScore = tech.compositionProxyScore
                mBase.isSevereUnderexposed = tech.isSevereUnderexposed
                mBase.isSevereOverexposed = tech.isSevereOverexposed
                mBase.exposureScore = expScore

                baselineItems.append(PhotoItem(
                    id: f.photo_id,
                    fileName: URL(fileURLWithPath: f.image_path).lastPathComponent,
                    sourceURL: URL(fileURLWithPath: f.image_path),
                    metrics: mBase
                ))

                // Experimental Item (+FaceCaptureQuality)
                var mExp = mBase
                mExp.rawFaceCaptureQuality = avgCQ
                mExp.faceCaptureQualityScore = avgCQ

                experimentalItems.append(PhotoItem(
                    id: f.photo_id,
                    fileName: URL(fileURLWithPath: f.image_path).lastPathComponent,
                    sourceURL: URL(fileURLWithPath: f.image_path),
                    metrics: mExp
                ))
            }

            // Production pre-burst metrics preparation
            let prepBase = scorer.preparePreBurstMetrics(items: baselineItems)
            let prepExp = scorer.preparePreBurstMetrics(items: experimentalItems)

            // Production burst ranking
            let rankedBase = prepBase.sorted { a, b in
                let sA = baseDetector.computeBurstFrameQuality(a)
                let sB = baseDetector.computeBurstFrameQuality(b)
                let qA = round(sA * 10000.0) / 10000.0
                let qB = round(sB * 10000.0) / 10000.0
                if qA != qB { return qA > qB }
                return a.id < b.id
            }

            let rankedExp = prepExp.sorted { a, b in
                let sA = expDetector.computeBurstFrameQuality(a)
                let sB = expDetector.computeBurstFrameQuality(b)
                let qA = round(sA * 10000.0) / 10000.0
                let qB = round(sB * 10000.0) / 10000.0
                if qA != qB { return qA > qB }
                return a.id < b.id
            }

            let baseRankedIds = rankedBase.map(\.id)
            let expRankedIds = rankedExp.map(\.id)

            // 1. Native Pairwise Evaluation
            if let pairs = s.ground_truth.pairwise_comparisons, !pairs.isEmpty {
                for pair in pairs {
                    totalAnnotatedPairs += 1
                    totalVotes += pair.totalVotes
                    agreementSum += pair.annotatorAgreement
                    if pair.isAmbiguous {
                        ambiguousPairsCount += 1
                    }

                    guard let bIdxA = baseRankedIds.firstIndex(of: pair.photo_a),
                          let bIdxB = baseRankedIds.firstIndex(of: pair.photo_b),
                          let eIdxA = expRankedIds.firstIndex(of: pair.photo_a),
                          let eIdxB = expRankedIds.firstIndex(of: pair.photo_b) else {
                        continue
                    }

                    evaluatedPairs += 1

                    if let winner = pair.majorityWinner {
                        let bWinner = (bIdxA < bIdxB) ? pair.photo_a : pair.photo_b
                        let eWinner = (eIdxA < eIdxB) ? pair.photo_a : pair.photo_b

                        if bWinner == winner {
                            baseCorrectPairs += 1
                            baseWeightedCorrect += pair.annotatorAgreement
                        }
                        if eWinner == winner {
                            expCorrectPairs += 1
                            expWeightedCorrect += pair.annotatorAgreement
                        }
                    }
                }
            }

            // 2. Ranking Evaluation (if preferred_order is available)
            var humanWinner: String? = nil
            if let pref = s.ground_truth.preferred_order, let first = pref.first {
                humanWinner = first
                rankingSeriesCount += 1

                if baseRankedIds.first == first { baseTop1 += 1 }
                if baseRankedIds.prefix(2).contains(first) { baseTop2 += 1 }
                if baseRankedIds.prefix(3).contains(first) { baseTop3 += 1 }
                if let idx = baseRankedIds.firstIndex(of: first) { baseRankSum += (idx + 1) }

                if expRankedIds.first == first { expTop1 += 1 }
                if expRankedIds.prefix(2).contains(first) { expTop2 += 1 }
                if expRankedIds.prefix(3).contains(first) { expTop3 += 1 }
                if let idx = expRankedIds.firstIndex(of: first) { expRankSum += (idx + 1) }

                if let rejects = s.ground_truth.unacceptable_rejects {
                    if let bw = baseRankedIds.first, rejects.contains(bw) { baseRejectCount += 1 }
                    if let ew = expRankedIds.first, rejects.contains(ew) { expRejectCount += 1 }
                }
            }

            // 3. Dynamic Winner-Flip Classification
            let baseWinner = baseRankedIds.first ?? ""
            let expWinner = expRankedIds.first ?? ""
            let winnerChanged = (baseWinner != expWinner)
            if winnerChanged { winnerFlips += 1 }

            var baseCorrect: Bool? = nil
            var expCorrect: Bool? = nil
            var classification = "NO_FLIP"

            if let hw = humanWinner {
                let bc = (baseWinner == hw)
                let ec = (expWinner == hw)
                baseCorrect = bc
                expCorrect = ec

                if !bc && ec {
                    classification = "IMPROVEMENT"
                    improvements.append(FailureCase(
                        seriesId: s.series_id,
                        sceneType: s.scene_type,
                        preferredFrameId: hw,
                        baselineWinnerId: baseWinner,
                        experimentalWinnerId: expWinner,
                        baselineCorrect: false,
                        experimentalCorrect: true,
                        failureCategory: "capture_quality",
                        explanation: "FaceCaptureQuality resolved ambiguity where detector confidence favored defective frame \(baseWinner)."
                    ))
                } else if bc && !ec {
                    classification = "REGRESSION"
                    regressions.append(FailureCase(
                        seriesId: s.series_id,
                        sceneType: s.scene_type,
                        preferredFrameId: hw,
                        baselineWinnerId: baseWinner,
                        experimentalWinnerId: expWinner,
                        baselineCorrect: true,
                        experimentalCorrect: false,
                        failureCategory: "capture_quality",
                        explanation: "FaceCaptureQuality demoted preferred frame \(baseWinner) in favor of \(expWinner)."
                    ))
                } else if winnerChanged {
                    classification = "NEUTRAL_FLIP"
                    neutralFlips += 1
                } else {
                    classification = "NO_FLIP"
                    noFlips += 1
                }
            } else if winnerChanged {
                classification = "NEUTRAL_FLIP"
                neutralFlips += 1
            } else {
                classification = "NO_FLIP"
                noFlips += 1
            }

            seriesRankings.append(SeriesRankingDetail(
                series_id: s.series_id,
                scene_type: s.scene_type,
                human_ranking: s.ground_truth.preferred_order,
                baseline_ranking: baseRankedIds,
                experimental_ranking: expRankedIds,
                baseline_winner: baseWinner,
                experimental_winner: expWinner,
                winner_changed: winnerChanged,
                baseline_correct: baseCorrect,
                experimental_correct: expCorrect,
                flip_classification: classification,
                photo_features: measuredFeatures
            ))
        }

        let durMs = (CFAbsoluteTimeGetCurrent() - tStart) * 1000.0
        let manifestCount = dataset.series.count

        if evaluatedSeriesCount == 0 {
            let details = "Manifest specified \(manifestCount) series, but 0 complete series were evaluable. Excluded: \(excludedSeriesCount)."
            return ("INCOMPLETE_DATASET", details, nil, nil)
        }

        // Compute metrics strictly using evaluated denominators
        let evalCountDouble = Double(evaluatedSeriesCount)
        let rankCountDouble = Double(max(1, rankingSeriesCount))
        let evalPairsDouble = Double(max(1, evaluatedPairs))
        let annotPairsDouble = Double(max(1, totalAnnotatedPairs))

        let meanAgreement = totalAnnotatedPairs > 0 ? (agreementSum / annotPairsDouble) : nil
        let ambigRate = totalAnnotatedPairs > 0 ? (Double(ambiguousPairsCount) / annotPairsDouble) : nil

        let baseMetrics = SeriesRankingMetrics(
            evaluationMode: "REAL_IMAGE_ANALYSIS",
            configurationName: "Real Image Baseline (Confidence Only)",
            enableFaceCaptureQuality: false,
            manifestSeriesCount: manifestCount,
            evaluatedSeriesCount: evaluatedSeriesCount,
            excludedSeriesCount: excludedSeriesCount,
            top1Accuracy: rankingSeriesCount > 0 ? (Double(baseTop1) / rankCountDouble) : 0.0,
            top2Recall: rankingSeriesCount > 0 ? (Double(baseTop2) / rankCountDouble) : 0.0,
            top3Recall: rankingSeriesCount > 0 ? (Double(baseTop3) / rankCountDouble) : 0.0,
            pairwiseAccuracy: evaluatedPairs > 0 ? (Double(baseCorrectPairs) / evalPairsDouble) : 1.0,
            pairwiseEvaluatedPairs: evaluatedPairs,
            pairwiseTotalAnnotatedPairs: totalAnnotatedPairs,
            pairwiseCoverage: totalAnnotatedPairs > 0 ? (Double(evaluatedPairs) / annotPairsDouble) : 1.0,
            weightedPairwiseAccuracy: evaluatedPairs > 0 ? (baseWeightedCorrect / evalPairsDouble) : nil,
            meanAnnotatorAgreement: meanAgreement,
            ambiguousPairRate: ambigRate,
            rejectInclusionRate: rankingSeriesCount > 0 ? (Double(baseRejectCount) / rankCountDouble) : 0.0,
            meanRankOfPreferred: rankingSeriesCount > 0 ? (Double(baseRankSum) / rankCountDouble) : 0.0,
            executionDurationMs: durMs,
            memoryResidentBytes: getCurrentResidentMemoryBytes()
        )

        let expMetrics = SeriesRankingMetrics(
            evaluationMode: "REAL_IMAGE_ANALYSIS",
            configurationName: "Real Image Experimental (+FaceCaptureQuality)",
            enableFaceCaptureQuality: true,
            manifestSeriesCount: manifestCount,
            evaluatedSeriesCount: evaluatedSeriesCount,
            excludedSeriesCount: excludedSeriesCount,
            top1Accuracy: rankingSeriesCount > 0 ? (Double(expTop1) / rankCountDouble) : 0.0,
            top2Recall: rankingSeriesCount > 0 ? (Double(expTop2) / rankCountDouble) : 0.0,
            top3Recall: rankingSeriesCount > 0 ? (Double(expTop3) / rankCountDouble) : 0.0,
            pairwiseAccuracy: evaluatedPairs > 0 ? (Double(expCorrectPairs) / evalPairsDouble) : 1.0,
            pairwiseEvaluatedPairs: evaluatedPairs,
            pairwiseTotalAnnotatedPairs: totalAnnotatedPairs,
            pairwiseCoverage: totalAnnotatedPairs > 0 ? (Double(evaluatedPairs) / annotPairsDouble) : 1.0,
            weightedPairwiseAccuracy: evaluatedPairs > 0 ? (expWeightedCorrect / evalPairsDouble) : nil,
            meanAnnotatorAgreement: meanAgreement,
            ambiguousPairRate: ambigRate,
            rejectInclusionRate: rankingSeriesCount > 0 ? (Double(expRejectCount) / rankCountDouble) : 0.0,
            meanRankOfPreferred: rankingSeriesCount > 0 ? (Double(expRankSum) / rankCountDouble) : 0.0,
            executionDurationMs: durMs,
            memoryResidentBytes: getCurrentResidentMemoryBytes()
        )

        let ablation = AblationComparison(
            evaluationMode: "REAL_IMAGE_ANALYSIS",
            baseline: baseMetrics,
            experimental: expMetrics,
            top1AccuracyDelta: expMetrics.top1Accuracy - baseMetrics.top1Accuracy,
            pairwiseAccuracyDelta: expMetrics.pairwiseAccuracy - baseMetrics.pairwiseAccuracy,
            winnerFlipsCount: winnerFlips,
            winnerFlipRate: Double(winnerFlips) / evalCountDouble,
            improvementsCount: improvements.count,
            regressionsCount: regressions.count,
            neutralFlipsCount: neutralFlips,
            noFlipCount: noFlips,
            regressions: regressions,
            improvements: improvements
        )

        // Write real-series ranking details artifact
        let rankingReport = RealSeriesRankingReport(
            benchmarkVersion: "2.2.0",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            manifestSeriesCount: manifestCount,
            evaluatedSeriesCount: evaluatedSeriesCount,
            excludedSeriesCount: excludedSeriesCount,
            seriesEvaluations: seriesEvaluations,
            seriesRankings: seriesRankings
        )

        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(rankingReport)
            let outURL = URL(fileURLWithPath: detailsPath)
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outURL)
            print("[OK] Wrote detailed real-series ranking report: \(detailsPath)")
        } catch {
            print("WARNING: Failed to write details report: \(error)")
        }

        let summary = "Evaluated \(evaluatedSeriesCount) / \(manifestCount) complete series (\(excludedSeriesCount) excluded). Single-pass real image analysis complete."
        return ("SUCCESS", summary, ablation, detailsPath)
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
                manifestSeriesCount: fixture.series.count,
                evaluatedSeriesCount: fixture.series.count,
                excludedSeriesCount: 0,
                top1Accuracy: Double(top1) / total,
                top2Recall: Double(top2) / total,
                top3Recall: Double(top3) / total,
                pairwiseAccuracy: totalPairs > 0 ? Double(correctPairs) / Double(totalPairs) : 1.0,
                pairwiseEvaluatedPairs: totalPairs,
                pairwiseTotalAnnotatedPairs: totalPairs,
                pairwiseCoverage: 1.0,
                weightedPairwiseAccuracy: nil,
                meanAnnotatorAgreement: nil,
                ambiguousPairRate: nil,
                rejectInclusionRate: Double(rejectCount) / total,
                meanRankOfPreferred: Double(rankSum) / total,
                executionDurationMs: durMs,
                memoryResidentBytes: getCurrentResidentMemoryBytes()
            )
        }

        let baseResult = evaluate(with: baselineDetector, configName: "Synthetic Baseline (Confidence Only)")
        let expResult = evaluate(with: experimentalDetector, configName: "Synthetic Experimental (+FaceCaptureQuality)")

        var winnerFlips = 0
        var improvements: [FailureCase] = []
        var regressions: [FailureCase] = []
        var neutralFlips = 0
        var noFlips = 0

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
            } else {
                noFlips += 1
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
            } else if baseWinner != expWinner {
                neutralFlips += 1
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
            improvementsCount: improvements.count,
            regressionsCount: regressions.count,
            neutralFlipsCount: neutralFlips,
            noFlipCount: noFlips,
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

            ### Real Image Empirical Results (Evaluated Series: \(real.baseline.evaluatedSeriesCount) / \(real.baseline.manifestSeriesCount))

            | Metric | Baseline (Confidence Only) | Experimental (+FaceCaptureQuality) | Delta |
            | :--- | :---: | :---: | :---: |
            | **Pairwise Concordance** | \(String(format: "%.1f%%", real.baseline.pairwiseAccuracy * 100)) | \(String(format: "%.1f%%", real.experimental.pairwiseAccuracy * 100)) | \(String(format: "%+.1f%%", real.pairwiseAccuracyDelta * 100)) |
            | **Evaluated Pairs / Total** | \(real.baseline.pairwiseEvaluatedPairs) / \(real.baseline.pairwiseTotalAnnotatedPairs) (\(String(format: "%.1f%%", real.baseline.pairwiseCoverage * 100))) | \(real.experimental.pairwiseEvaluatedPairs) / \(real.experimental.pairwiseTotalAnnotatedPairs) (\(String(format: "%.1f%%", real.experimental.pairwiseCoverage * 100))) | - |
            | **Top-1 Winner Accuracy** | \(String(format: "%.1f%%", real.baseline.top1Accuracy * 100)) | \(String(format: "%.1f%%", real.experimental.top1Accuracy * 100)) | \(String(format: "%+.1f%%", real.top1AccuracyDelta * 100)) |
            | **Top-2 Winner Recall** | \(String(format: "%.1f%%", real.baseline.top2Recall * 100)) | \(String(format: "%.1f%%", real.experimental.top2Recall * 100)) | \(String(format: "%+.1f%%", (real.experimental.top2Recall - real.baseline.top2Recall) * 100)) |
            | **Top-3 Winner Recall** | \(String(format: "%.1f%%", real.baseline.top3Recall * 100)) | \(String(format: "%.1f%%", real.experimental.top3Recall * 100)) | \(String(format: "%+.1f%%", (real.experimental.top3Recall - real.baseline.top3Recall) * 100)) |
            | **Mean Rank of Preferred** | \(String(format: "%.2f", real.baseline.meanRankOfPreferred)) | \(String(format: "%.2f", real.experimental.meanRankOfPreferred)) | \(String(format: "%+.2f", real.experimental.meanRankOfPreferred - real.baseline.meanRankOfPreferred)) |
            | **Unacceptable Reject Rate** | \(String(format: "%.1f%%", real.baseline.rejectInclusionRate * 100)) | \(String(format: "%.1f%%", real.experimental.rejectInclusionRate * 100)) | \(String(format: "%+.1f%%", (real.experimental.rejectInclusionRate - real.baseline.rejectInclusionRate) * 100)) |
            | **Winner Flips** | - | \(real.winnerFlipsCount) / \(real.baseline.evaluatedSeriesCount) (\(String(format: "%.1f%%", real.winnerFlipRate * 100))) | - |
            | **Improvements / Regressions** | - | +\(real.improvementsCount) / -\(real.regressionsCount) | - |
            """

            if let p = report.realImageRankingDetailsPath {
                md += "\n*Detailed per-series rankings and measured features written to: `\(p)`*\n"
            }
        } else {
            md += """

            > [!IMPORTANT]
            > **Dataset Blocker**: No legally permissible public wedding photography dataset with fine-grained human curator ranking orders (1st, 2nd, 3rd, blink, reject) currently exists in the repository.
            > The pipeline and benchmark infrastructure are fully implemented to decode real `CGImage`s and query Apple Vision directly when image manifests or Photo Triage roots are supplied.
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
          --synthetic-fixture <path>   Path to synthetic logic validation fixture (default: docs/datasets/synthetic-ranking-fixture.json)
          --real-series <path>         Path to real-image series ground truth manifest (labels only)
          --photo-triage-root <path>   Path to local Photo Triage dataset root directory
          --output-json <path>         Path to output JSON report (default: artifacts/quality-benchmark-v2.json)
          --output-md <path>           Path to output Markdown report (default: artifacts/QUALITY_BENCHMARK_V2.md)
          --details-json <path>        Path to output real-series ranking details artifact (default: artifacts/real-series-ranking-details.json)
          --help, -h                   Show this help message
        """)
    }
}
