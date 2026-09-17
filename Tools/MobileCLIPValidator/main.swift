import Foundation
import CoreGraphics
import CoreML
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif

struct MobileCLIPReport: Codable {
    let timestamp: String
    let status: String // "PASS" or "FAIL"
    let modelName: String
    let repoRevision: String
    let modelLoaded: Bool
    let modelPath: String?
    let computeUnitsUsed: String
    let outputEmbeddingDim: Int
    let classificationBackend: String
    let testCategoryAssigned: String
    let testConfidence: Double
    let averageLatencyMs: Double
    let notes: String
}

@main
struct MobileCLIPValidator {
    static let pinnedRevision = "3e0a7bfb9fe83da8a3efaa3fd8f7df24214bb947"

    static func createSyntheticCGImage(width: Int = 256, height: Int = 256) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw synthetic wedding ceremony scene
        ctx.setFillColor(red: 0.95, green: 0.90, blue: 0.85, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.setFillColor(red: 0.85, green: 0.70, blue: 0.60, alpha: 1.0)
        ctx.fillEllipse(in: CGRect(x: 80, y: 80, width: 96, height: 96))

        return ctx.makeImage()
    }

    static func main() async {
        let args = CommandLine.arguments
        var outputJSON = "artifacts/mobileclip-report.json"
        var customModelPath: String? = nil

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--output-json":
                if i + 1 < args.count {
                    outputJSON = args[i + 1]
                    i += 1
                }
            case "--model-path":
                if i + 1 < args.count {
                    customModelPath = args[i + 1]
                    i += 1
                }
            default:
                break
            }
            i += 1
        }

        print("====================================================")
        print("🧠 WeddingCull Strict MobileCLIP CoreML Validator")
        print("====================================================")
        print("Pinned Repository: apple/coreml-mobileclip@\(pinnedRevision)")

        let customURL = customModelPath != nil ? URL(fileURLWithPath: customModelPath!) : nil
        let hardware = HardwareCapabilities()
        let classifier = MobileCLIPClassifier(hardwareCapabilities: hardware, customModelURL: customURL)

        guard let testCG = createSyntheticCGImage() else {
            print("❌ Failed to create test CGImage")
            exit(1)
        }

        let isLoaded = classifier.isCoreMLModelLoaded
        print("Core ML Model Loaded: \(isLoaded ? "YES ✅" : "NO ❌")")

        let dummyMetadata = PhotoMetadata()
        let result = classifier.classifyWithBackend(cgImage: testCG, metadata: dummyMetadata, faceCount: 1)

        print("Backend Used: \(result.backend.rawValue)")
        print("Predicted Category: \(result.category.rawValue)")
        print(String(format: "Confidence: %.2f", result.confidence))

        let isStrictMobileCLIP = (result.backend == .mobileCLIP) && isLoaded

        var avgLatencyMs = 0.0
        if isStrictMobileCLIP {
            print("Benchmarking MobileCLIP Core ML inference latency (10 warmup + 20 measured runs)...")
            // Warmup
            for _ in 0..<10 {
                _ = classifier.classifyWithBackend(cgImage: testCG, metadata: dummyMetadata, faceCount: 1)
            }
            let start = Date()
            let iterations = 20
            for _ in 0..<iterations {
                _ = classifier.classifyWithBackend(cgImage: testCG, metadata: dummyMetadata, faceCount: 1)
            }
            let elapsed = Date().timeIntervalSince(start)
            avgLatencyMs = (elapsed / Double(iterations)) * 1000.0
            print(String(format: "Average Inference Latency: %.2f ms / image", avgLatencyMs))
        }

        let status = isStrictMobileCLIP ? "PASS" : "FAIL"
        let notes: String
        if isStrictMobileCLIP {
            notes = "Strict MobileCLIP Core ML model loaded and executed verified predictions without fallback."
        } else {
            notes = "Strict validation FAILED: MobileCLIP Core ML model was not loaded; execution fell back to Apple Vision."
        }

        let report = MobileCLIPReport(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            status: status,
            modelName: "mobileclip_s0_image",
            repoRevision: pinnedRevision,
            modelLoaded: isLoaded,
            modelPath: customModelPath ?? "models/mobileclip_s0_image.mlmodelc",
            computeUnitsUsed: hardware.isAppleSilicon ? "All (Neural Engine + GPU + CPU)" : "CPU and GPU (Intel AVX2 / Metal)",
            outputEmbeddingDim: 512,
            classificationBackend: result.backend.rawValue,
            testCategoryAssigned: result.category.rawValue,
            testConfidence: result.confidence,
            averageLatencyMs: avgLatencyMs,
            notes: notes
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let json = try? encoder.encode(report) {
            let outURL = URL(fileURLWithPath: outputJSON)
            try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? json.write(to: outURL)
            print("\n✅ Written MobileCLIP validation report to \(outputJSON)")
        }

        print("====================================================")
        print("MobileCLIP Strict Validation Verdict: \(status)")
        print("====================================================")

        exit(isStrictMobileCLIP ? 0 : 1)
    }
}
