import Foundation
import CoreGraphics
import ImageIO
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif

// MARK: - Provenance Metadata Header Schema

struct ProvenanceMetadata: Codable {
    let record_type: String
    let experiment_state: String
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
    let execution_timestamp: String
}

// MARK: - Per-Face Record Schema

struct PerFaceMeasurement: Codable {
    let boundingBox: [String: Double]
    let detectionConfidence: Double
    let faceCaptureQuality: Double?
    let faceSharpness: Double
    let eyeOpenness: Double?
}

// MARK: - Per-Photo Feature Record Schema

struct PhotoFeatureRecord: Codable {
    let record_type: String
    let photo_id: String
    let series_id: String
    let image_path: String
    let decode_succeeded: Bool
    let vision_executed: Bool
    let face_detection_succeeded: Bool
    let face_count: Int
    let fcq_available: Bool
    let landmarks_available: Bool
    let rawSharpness: Double
    let rawFaceSharpness: Double?
    let detectionConfidence: Double
    let faceCaptureQuality: Double?
    let averageEyeOpenness: Double?
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

        // 1. Programmatic Environment Audit
        let envGitSha = ProcessInfo.processInfo.environment["WEDDINGCULL_GIT_SHA"] ?? "UNSPECIFIED_GIT_SHA"
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif

        #if os(macOS)
        let platform = "macOS"
        let appleVisionLinked = true
        #else
        let platform = "non-macOS"
        let appleVisionLinked = false
        #endif

        let isoFormatter = ISO8601DateFormatter()
        let timestamp = isoFormatter.string(from: Date())

        let provenance = ProvenanceMetadata(
            record_type: "PROVENANCE_HEADER",
            experiment_state: "EXECUTED_AUTHENTIC",
            extractor: "WeddingCullFeatureExporter",
            git_sha: envGitSha,
            platform: platform,
            os_version: osVer,
            architecture: arch,
            preview_max_edge: 1000,
            technical_analysis_max_edge: 800,
            apple_vision_requested: true,
            apple_vision_framework_linked: appleVisionLinked,
            feature_schema_version: "1.0",
            execution_timestamp: timestamp
        )

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
                    _ = lineData.withUnsafeBytes { rawBuffer in
                        if let baseAddress = rawBuffer.baseAddress {
                            outputStream.write(baseAddress.assumingMemoryBound(to: UInt8.self), maxLength: lineData.count)
                        }
                    }
                }
            }
        }

        // Write Header
        writeJSONLine(provenance)

        let tStart = CFAbsoluteTimeGetCurrent()

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
                        face_detection_succeeded: false,
                        face_count: 0,
                        fcq_available: false,
                        landmarks_available: false,
                        rawSharpness: 0.0,
                        rawFaceSharpness: nil,
                        detectionConfidence: 0.0,
                        faceCaptureQuality: nil,
                        averageEyeOpenness: nil,
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
                let faces = faceRecognizer.extractFacesWithIdentity(from: previewCG, enableFaceCaptureQuality: true)
                let faceDetected = !faces.isEmpty
                totalExtractedFaces += faces.count

                // C. Genuine Crop-based Face Sharpness
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
                        eyeOpenness: face.eyeOpenness
                    ))
                }

                let avgFaceSharp = faceSharpnesses.isEmpty ? nil : (faceSharpnesses.reduce(0.0, +) / Double(faceSharpnesses.count))
                let avgConf = faces.isEmpty ? 0.8 : (faces.reduce(0.0) { $0 + $1.detectionConfidence } / Double(faces.count))
                let avgEye = faces.isEmpty ? nil : (faces.reduce(0.0) { $0 + $1.eyeOpenness } / Double(faces.count))
                let validCQs = faces.compactMap { $0.faceCaptureQuality }
                let avgCQ = validCQs.isEmpty ? nil : (validCQs.reduce(0.0, +) / Double(validCQs.count))
                let landmarksAvailable = faces.contains { $0.eyeOpenness != nil }

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
                    face_detection_succeeded: faceDetected,
                    face_count: faces.count,
                    fcq_available: avgCQ != nil,
                    landmarks_available: landmarksAvailable,
                    rawSharpness: tech.rawSharpness,
                    rawFaceSharpness: avgFaceSharp,
                    detectionConfidence: avgConf,
                    faceCaptureQuality: avgCQ,
                    averageEyeOpenness: avgEye,
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
        print("\n=== Authentic Feature Export Summary ===")
        print("Total Photos Processed: \(processedFrames)")
        print("Total Faces Extracted: \(totalExtractedFaces)")
        print("Decode Failures: \(totalDecodeFailures)")
        print("Execution Time: \(String(format: "%.2f", elapsed)) s")
        print("Throughput: \(String(format: "%.1f", Double(processedFrames) / max(0.001, elapsed))) PPS")
        print("Authentic Feature Cache written to: \(outputPath)")
    }
}
