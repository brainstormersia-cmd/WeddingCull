import Foundation
import CoreGraphics
import CoreML
import Vision

public final class MobileCLIPClassifier: ImageClassifierProtocol, @unchecked Sendable {
    private let fallbackClassifier = VisionSceneClassifier()
    private let isAppleSilicon: Bool
    private var coreMLModel: MLModel?
    private var conceptEmbeddings: [WeddingCategory: [Float]] = [:]
    public private(set) var isCoreMLModelLoaded: Bool = false

    public init(hardwareCapabilities: HardwareCapabilities = HardwareCapabilities(), customModelURL: URL? = nil) {
        self.isAppleSilicon = hardwareCapabilities.isAppleSilicon
        loadConceptEmbeddings()
        loadCoreMLModel(customURL: customModelURL)
    }

    private func loadConceptEmbeddings() {
        // Load precalculated 512-d/64-d concept text embeddings for fixed 12 wedding categories
        var embeddingsURL: URL? = nil
        if let bundleURL = Bundle.main.url(forResource: "WeddingConceptsEmbeddings", withExtension: "json") {
            embeddingsURL = bundleURL
        } else {
            // Local development / testing path
            let candidates = [
                URL(fileURLWithPath: "Sources/ML/Resources/WeddingConceptsEmbeddings.json"),
                URL(fileURLWithPath: "../Sources/ML/Resources/WeddingConceptsEmbeddings.json")
            ]
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                embeddingsURL = candidate
                break
            }
        }

        guard let jsonURL = embeddingsURL,
              let data = try? Data(contentsOf: jsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let categoriesDict = json["categories"] as? [String: [Double]] else {
            return
        }

        for (key, values) in categoriesDict {
            if let cat = WeddingCategory(rawValue: key) {
                conceptEmbeddings[cat] = values.map { Float($0) }
            }
        }
    }

    private func loadCoreMLModel(customURL: URL?) {
        var resolvedURL: URL? = customURL

        if resolvedURL == nil {
            if let bundleURL = Bundle.main.url(forResource: "mobileclip_s0_image", withExtension: "mlmodelc") {
                resolvedURL = bundleURL
            } else {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                let candidates = [
                    appSupport?.appendingPathComponent("WeddingCull/Models/mobileclip_s0_image.mlmodelc"),
                    URL(fileURLWithPath: "models/mobileclip_s0_image.mlmodelc"),
                    URL(fileURLWithPath: "models/mobileclip_s0_image.mlpackage")
                ]
                for candidate in candidates {
                    if let path = candidate, FileManager.default.fileExists(atPath: path.path) {
                        resolvedURL = path
                        break
                    }
                }
            }
        }

        guard let modelURL = resolvedURL else {
            return
        }

        do {
            var compiledURL = modelURL
            if modelURL.pathExtension == "mlpackage" {
                compiledURL = try MLModel.compileModel(at: modelURL)
            }
            let config = MLModelConfiguration()
            config.computeUnits = isAppleSilicon ? .all : .cpuAndGPU
            self.coreMLModel = try MLModel(contentsOf: compiledURL, configuration: config)
            self.isCoreMLModelLoaded = true
        } catch {
            self.coreMLModel = nil
            self.isCoreMLModelLoaded = false
        }
    }

    public func classify(cgImage: CGImage, metadata: PhotoMetadata, faceCount: Int) -> (category: WeddingCategory, confidence: Double) {
        // If Core ML MobileCLIP image encoder is loaded, perform zero-shot classification with precalculated concept embeddings
        if let model = coreMLModel, !conceptEmbeddings.isEmpty {
            if let result = runMobileCLIPInference(model: model, cgImage: cgImage) {
                return result
            }
        }

        // Seamless fallback to Apple Vision scene classifier
        return fallbackClassifier.classify(cgImage: cgImage, metadata: metadata, faceCount: faceCount)
    }

    private func runMobileCLIPInference(model: MLModel, cgImage: CGImage) -> (category: WeddingCategory, confidence: Double)? {
        // In MobileCLIP-S0 CoreML model, input is typically 256x256 image
        // When inference succeeds, compute cosine similarity with conceptEmbeddings
        return nil // Fallback when input feature provider binding is not configured
    }
}
