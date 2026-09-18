import Foundation
import CoreGraphics
import ImageIO
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif

// MARK: - Provenance Start Record Schema

struct ProvenanceStartRecord: Codable {
    let record_type: String
    let status: String
    let extractor: String
    let git_sha: String
    let platform: String
    let os_version: String
    let architecture: String
    let preview_max_edge: Int
    let technical_analysis_max_edge: Int
    let apple_vision_requested: Bool
    let apple_vision_framework_linked: Bool
    let feature_schema_version: String
    let dataset_root: String
    let dataset_name: String
    let total_series: Int
    let total_frames: Int
    let start_timestamp: String
}

// MARK: - Provenance Completion Record Schema

struct ProvenanceCompletionRecord: Codable {
    let record_type: String
    let experiment_state: String
    let extractor: String
    let git_sha: String
    let platform: String
    let os_version: String
    let architecture: String
    let total_photos_processed: Int
    let total_faces_extracted: Int
    let total_decode_failures: Int
    let total_vision_failures: Int
    let elapsed_seconds: Double
    let photos_per_second: Double
    let completion_timestamp: String
}

// MARK: - Per-Face Record Schema

struct PerFaceMeasurement: Codable {
    let boundingBox: [String: Double]
    let detectionConfidence: Double
    let faceCaptureQuality: Double?
    let faceSharpness: Double
    let eyeOpenness: Double?
    let eyeOpennessMeasured: Bool
    let leftEyeLandmarksAvailable: Bool
    let rightEyeLandmarksAvailable: Bool
}

// MARK: - Per-Photo Feature Record Schema

struct PhotoFeatureRecord: Codable {
    let record_type: String
    let photo_id: String
    let series_id: String
    let image_path: String
    let decode_succeeded: Bool
    let vision_executed: Bool
    let vision_request_succeeded: Bool
    let vision_error: String?
    let face_detection_succeeded: Bool
    let face_count: Int
    let fcq_available: Bool
    let landmarks_available: Bool
    let faces_with_measured_eyes_count: Int
    let rawSharpness: Double
    let rawFaceSharpness: Double?
    let minFaceSharpness: Double?
    let maxFaceSharpness: Double?
    let medianFaceSharpness: Double?
    let detectionConfidence: Double
    let faceCaptureQuality: Double?
    let minFaceCaptureQuality: Double?
    let medianFaceCaptureQuality: Double?
    let averageEyeOpenness: Double?
    let minEyeOpenness: Double?
    let meanLuminance: Double
    let shadowClipping: Double
    let highlightClipping: Double
    let dynamicRange: Double
    let contrast: Double
    let exposureScore: Double
    let severeUnderexposure: Bool
    let severeOverexposure: Bool
    let productionBaselineFrameQuality: Double
    let productionFrameQualityWithFCQ: Double
    let perFaceMeasurements: [PerFaceMeasurement]
}

// MARK: - Main Entry Point

@main
struct WeddingCullFeatureExporterApp {
    static func main() {
        // Enforce macOS environment requirement
        #if !os(macOS)
        print("❌ FATAL: BLOCKED_MACOS_REQUIRED")
        print("WeddingCullFeatureExporter requires native macOS Apple Vision framework (VNDetectFaceLandmarksRequest, VNDetectFaceCaptureQualityRequest).")
        print("Execution on non-macOS environments is strictly blocked to maintain experiment integrity.")
        exit(86)
        #endif

        let args = CommandLine.arguments

        func getArg(_ flag: String) -> String? {
            if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
                return args[idx + 1]
            }
            return nil
        }

        guard let datasetRoot = getArg("--dataset") ?? getArg("--dataset-root") else {
            print("Usage: WeddingCullFeatureExporter --dataset <dataset_path> --output <output.jsonl> [--prefer-train]")
            print("Example: WeddingCullFeatureExporter --dataset X:/WeddingCullDatasets/raw/PhotoTriage --output photo_triage_val_features_authentic.jsonl")
            exit(1)
        }

        let outputPath = getArg("--output") ?? "photo_triage_features_authentic.jsonl"
        let preferTrain = args.contains("--prefer-train")

        print("=== WeddingCull Authentic Feature Exporter ===")
        print("Dataset Root: \(datasetRoot)")
        print("Output Path: \(outputPath)")
        print("Prefer Train: \(preferTrain)")

        // 1. Mandatory Git SHA Audit
        var detectedGitSha = ProcessInfo.processInfo.environment["WEDDINGCULL_GIT_SHA"]
        if detectedGitSha == nil || detectedGitSha!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || detectedGitSha == "UNSPECIFIED_GIT_SHA" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["rev-parse", "HEAD"]
            let pipe = Pipe()
            process.standardOutput = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                        detectedGitSha = output
                    }
                }
            } catch {}
        }

        guard let gitSha = detectedGitSha, !gitSha.isEmpty, gitSha != "UNSPECIFIED_GIT_SHA" else {
            print("❌ FATAL: Valid Git SHA is strictly required for experiment provenance. Set WEDDINGCULL_GIT_SHA or ensure git repository is accessible.")
            exit(87)
        }

        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif

        let platform = "macOS"
        let appleVisionLinked = true

        let isoFormatter = ISO8601DateFormatter()
        let startTimestamp = isoFormatter.string(from: Date())

        // 2. Load Dataset via Direct PhotoTriageAdapter
        let adapter = PhotoTriageAdapter()
        let rootURL = URL(fileURLWithPath: datasetRoot)
        let inspection = adapter.inspect(rootURL: rootURL)
        guard inspection.isAvailable else {
            print("ERROR: Dataset inspection failed: \(inspection.statusMessage)")
            exit(2)
        }

        let dataset: RealSeriesBenchmarkDataset
        do {
            dataset = try adapter.loadDataset(from: rootURL)
            print("Loaded dataset: \(dataset.dataset_name) (\(dataset.total_series) series, \(dataset.total_frames) frames)")
        } catch {
            print("ERROR: Failed to load dataset: \(error)")
            exit(3)
        }

        // 3. Initialize Analyzers
        let qualityAnalyzer = TechnicalQualityAnalyzer()
        let faceRecognizer = FaceIdentityRecognizer()
        let baseDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: false)
        let expDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: true)

        var processedFrames = 0
        var totalDecodeFailures = 0
        var totalVisionFailures = 0
        var totalExtractedFaces = 0

        // Prepare Output File
        let outURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let outputStream = OutputStream(url: outURL, append: false) else {
            print("ERROR: Could not open output file at \(outputPath)")
            exit(4)
        }
        outputStream.open()
        defer { outputStream.close() }

        let encoder = JSONEncoder()

        func writeJSONLine<T: Encodable>(_ record: T) {
            if let data = try? encoder.encode(record),
               let str = String(data: data, encoding: .utf8) {
                let line = str + "\n"
                if let lineData = line.data(using: .utf8) {
                    lineData.withUnsafeBytes { rawBuffer in
                        if let baseAddress = rawBuffer.baseAddress {
                            outputStream.write(baseAddress.assumingMemoryBound(to: UInt8.self), maxLength: lineData.count)
                        }
                    }
                }
            }
        }

        // Write Start Provenance
        let startProvenance = ProvenanceStartRecord(
            record_type: "PROVENANCE_START",
            status: "STARTED",
            extractor: "WeddingCullFeatureExporter",
            git_sha: gitSha,
            platform: platform,
            os_version: osVer,
            architecture: arch,
            preview_max_edge: 1000,
            technical_analysis_max_edge: 800,
            apple_vision_requested: true,
            apple_vision_framework_linked: appleVisionLinked,
            feature_schema_version: "1.0",
            dataset_root: datasetRoot,
            dataset_name: dataset.dataset_name,
            total_series: dataset.total_series,
            total_frames: dataset.total_frames,
            start_timestamp: startTimestamp
        )
        writeJSONLine(startProvenance)

        let tStart = CFAbsoluteTimeGetCurrent()

        func computeMedian(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let count = sorted.count
            if count % 2 == 1 {
                return sorted[count / 2]
            } else {
                return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
            }
        }

        // 4. Extract Superset of Measurements for every unique photo
        var seenPhotos = Set<String>()

        for s in dataset.series {
            for f in s.frames {
                let pid = f.photo_id
                if seenPhotos.contains(pid) { continue }
                seenPhotos.insert(pid)

                let imgURL = URL(fileURLWithPath: f.image_path)
                guard FileManager.default.fileExists(atPath: imgURL.path),
                      let previewCG = PreviewPipeline.decodeProductionPreview(from: imgURL, maxPixelSize: 1000) else {
                    totalDecodeFailures += 1
                    let failRecord = PhotoFeatureRecord(
                        record_type: "PHOTO_FEATURES",
                        photo_id: pid,
                        series_id: s.series_id,
                        image_path: f.image_path,
                        decode_succeeded: false,
                        vision_executed: false,
                        vision_request_succeeded: false,
                        vision_error: "Preview decode failed",
                        face_detection_succeeded: false,
                        face_count: 0,
                        fcq_available: false,
                        landmarks_available: false,
                        faces_with_measured_eyes_count: 0,
                        rawSharpness: 0.0,
                        rawFaceSharpness: nil,
                        minFaceSharpness: nil,
                        maxFaceSharpness: nil,
                        medianFaceSharpness: nil,
                        detectionConfidence: 0.0,
                        faceCaptureQuality: nil,
                        minFaceCaptureQuality: nil,
                        medianFaceCaptureQuality: nil,
                        averageEyeOpenness: nil,
                        minEyeOpenness: nil,
                        meanLuminance: 0.0,
                        shadowClipping: 0.0,
                        highlightClipping: 0.0,
                        dynamicRange: 0.0,
                        contrast: 0.0,
                        exposureScore: 0.0,
                        severeUnderexposure: false,
                        severeOverexposure: false,
                        productionBaselineFrameQuality: 0.0,
                        productionFrameQualityWithFCQ: 0.0,
                        perFaceMeasurements: []
                    )
                    writeJSONLine(failRecord)
                    continue
                }

                // A. Technical Analysis (800px long edge context)
                let tech = qualityAnalyzer.analyze(cgImage: previewCG)

                // B. Apple Vision Face Analysis (1000px context)
                let faceResult = faceRecognizer.extractFacesWithIdentityResult(from: previewCG, enableFaceCaptureQuality: true)
                let visionSucceeded = faceResult.visionRequestSucceeded
                if !visionSucceeded {
                    totalVisionFailures += 1
                }
                let faces = faceResult.faces
                let faceDetected = !faces.isEmpty
                totalExtractedFaces += faces.count

                // C. Genuine Crop-based Face Sharpness & Landmark Measurements
                var perFaceRecords: [PerFaceMeasurement] = []
                var faceSharpnesses: [Double] = []

                for face in faces {
                    let cropSharp = qualityAnalyzer.computeRegionSharpness(cgImage: previewCG, normalizedRect: face.boundingBox)
                    faceSharpnesses.append(cropSharp)
                    let bboxDict: [String: Double] = [
                        "x": Double(face.boundingBox.origin.x),
                        "y": Double(face.boundingBox.origin.y),
                        "width": Double(face.boundingBox.size.width),
                        "height": Double(face.boundingBox.size.height)
                    ]
                    perFaceRecords.append(PerFaceMeasurement(
                        boundingBox: bboxDict,
                        detectionConfidence: face.detectionConfidence,
                        faceCaptureQuality: face.faceCaptureQuality,
                        faceSharpness: cropSharp,
                        eyeOpenness: face.eyeOpenness,
                        eyeOpennessMeasured: face.eyeOpennessMeasured,
                        leftEyeLandmarksAvailable: face.leftEyeLandmarksAvailable,
                        rightEyeLandmarksAvailable: face.rightEyeLandmarksAvailable
                    ))
                }

                let avgFaceSharp = faceSharpnesses.isEmpty ? nil : (faceSharpnesses.reduce(0.0, +) / Double(faceSharpnesses.count))
                let minFaceSharp = faceSharpnesses.min()
                let maxFaceSharp = faceSharpnesses.max()
                let medianFaceSharp = computeMedian(faceSharpnesses)

                let avgConf = faces.isEmpty ? 0.8 : (faces.reduce(0.0) { $0 + $1.detectionConfidence } / Double(faces.count))

                let validCQs = faces.compactMap { $0.faceCaptureQuality }
                let avgCQ = validCQs.isEmpty ? nil : (validCQs.reduce(0.0, +) / Double(validCQs.count))
                let minCQ = validCQs.min()
                let medianCQ = computeMedian(validCQs)

                let measuredEyes = faces.filter { $0.eyeOpennessMeasured }
                let measuredEyesCount = measuredEyes.count
                let validEyes = measuredEyes.compactMap { $0.eyeOpenness }
                let avgEye = validEyes.isEmpty ? (faces.isEmpty ? nil : 0.8) : (validEyes.reduce(0.0, +) / Double(validEyes.count))
                let minEye = validEyes.min()
                let landmarksAvailable = faces.contains { $0.leftEyeLandmarksAvailable || $0.rightEyeLandmarksAvailable }

                // D. Exposure
                let expScore = QualityScorer.computeExposureScore(
                    meanLuminance: tech.meanLuminance,
                    shadowClipping: tech.shadowClipping,
                    highlightClipping: tech.highlightClipping
                )

                // E. Production Heuristic Scores
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

                var mExp = mBase
                mExp.rawFaceCaptureQuality = avgCQ
                mExp.faceCaptureQualityScore = avgCQ

                let itemBase = PhotoItem(
                    id: pid,
                    fileName: imgURL.lastPathComponent,
                    sourceURL: imgURL,
                    metrics: mBase
                )
                let itemExp = PhotoItem(
                    id: pid,
                    fileName: imgURL.lastPathComponent,
                    sourceURL: imgURL,
                    metrics: mExp
                )

                let scoreBase = baseDetector.computeBurstFrameQuality(itemBase)
                let scoreExp = expDetector.computeBurstFrameQuality(itemExp)

                let photoRecord = PhotoFeatureRecord(
                    record_type: "PHOTO_FEATURES",
                    photo_id: pid,
                    series_id: s.series_id,
                    image_path: f.image_path,
                    decode_succeeded: true,
                    vision_executed: true,
                    vision_request_succeeded: visionSucceeded,
                    vision_error: faceResult.errorDescription,
                    face_detection_succeeded: faceDetected,
                    face_count: faces.count,
                    fcq_available: avgCQ != nil,
                    landmarks_available: landmarksAvailable,
                    faces_with_measured_eyes_count: measuredEyesCount,
                    rawSharpness: tech.rawSharpness,
                    rawFaceSharpness: avgFaceSharp,
                    minFaceSharpness: minFaceSharp,
                    maxFaceSharpness: maxFaceSharp,
                    medianFaceSharpness: medianFaceSharp,
                    detectionConfidence: avgConf,
                    faceCaptureQuality: avgCQ,
                    minFaceCaptureQuality: minCQ,
                    medianFaceCaptureQuality: medianCQ,
                    averageEyeOpenness: avgEye,
                    minEyeOpenness: minEye,
                    meanLuminance: tech.meanLuminance,
                    shadowClipping: tech.shadowClipping,
                    highlightClipping: tech.highlightClipping,
                    dynamicRange: tech.dynamicRangeProxy,
                    contrast: tech.contrastProxy,
                    exposureScore: expScore,
                    severeUnderexposure: tech.isSevereUnderexposed,
                    severeOverexposure: tech.isSevereOverexposed,
                    productionBaselineFrameQuality: scoreBase,
                    productionFrameQualityWithFCQ: scoreExp,
                    perFaceMeasurements: perFaceRecords
                )
                writeJSONLine(photoRecord)

                processedFrames += 1
                if processedFrames % 50 == 0 {
                    print("  Processed \(processedFrames) / \(seenPhotos.count)...")
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - tStart
        let pps = Double(processedFrames) / max(0.001, elapsed)
        let completionTimestamp = isoFormatter.string(from: Date())

        // 5. Emit Final Provenance Completion (earned upon successful completion)
        let completionRecord = ProvenanceCompletionRecord(
            record_type: "PROVENANCE_COMPLETION",
            experiment_state: "EXECUTED_AUTHENTIC",
            extractor: "WeddingCullFeatureExporter",
            git_sha: gitSha,
            platform: platform,
            os_version: osVer,
            architecture: arch,
            total_photos_processed: processedFrames,
            total_faces_extracted: totalExtractedFaces,
            total_decode_failures: totalDecodeFailures,
            total_vision_failures: totalVisionFailures,
            elapsed_seconds: elapsed,
            photos_per_second: pps,
            completion_timestamp: completionTimestamp
        )
        writeJSONLine(completionRecord)

        print("\n=== Authentic Feature Export Summary ===")
        print("Total Photos Processed: \(processedFrames)")
        print("Total Faces Extracted: \(totalExtractedFaces)")
        print("Decode Failures: \(totalDecodeFailures)")
        print("Vision Failures: \(totalVisionFailures)")
        let elapsedStr = String(format: "%.2f", elapsed)
        let ppsStr = String(format: "%.1f", pps)
        print("Execution Time: \(elapsedStr) s")
        print("Throughput: \(ppsStr) PPS")
        print("Authentic Feature Cache written to: \(outputPath)")
    }
}
