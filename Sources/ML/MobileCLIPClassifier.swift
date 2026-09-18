import Foundation
import CoreGraphics
import CoreML
import Vision
import Accelerate

public enum ClassificationBackend: String, Sendable {
    case mobileCLIP = "MobileCLIP-S0"
    case visionFallback = "Apple Vision"
}

public final class MobileCLIPClassifier: ImageClassifierProtocol, @unchecked Sendable {
    private let fallbackClassifier = VisionSceneClassifier()
    private let isAppleSilicon: Bool
    private var coreMLModel: MLModel?
    private var conceptEmbeddings: [WeddingCategory: [Float]] = [:]
    public private(set) var isCoreMLModelLoaded: Bool = false
    public private(set) var lastUsedBackend: ClassificationBackend = .visionFallback

    public init(hardwareCapabilities: HardwareCapabilities = HardwareCapabilities(), customModelURL: URL? = nil, forceVisionFallback: Bool = false) {
        self.isAppleSilicon = hardwareCapabilities.isAppleSilicon
        if !forceVisionFallback {
            loadConceptEmbeddings()
            loadCoreMLModel(customURL: customModelURL)
        }
    }

    private func loadConceptEmbeddings() {
        // Load precalculated 512-d concept text embeddings for fixed 12 wedding categories
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
            // On Apple Silicon: .all (Neural Engine + GPU + CPU)
            // On Intel: .cpuAndGPU (Intel Core CPU + integrated/discrete GPU)
            config.computeUnits = isAppleSilicon ? .all : .cpuAndGPU
            self.coreMLModel = try MLModel(contentsOf: compiledURL, configuration: config)
            self.isCoreMLModelLoaded = true
        } catch {
            self.coreMLModel = nil
            self.isCoreMLModelLoaded = false
        }
    }

    public func classify(cgImage: CGImage, metadata: PhotoMetadata, faceCount: Int) -> (category: WeddingCategory, confidence: Double) {
        let result = classifyWithBackend(cgImage: cgImage, metadata: metadata, faceCount: faceCount)
        return (result.category, result.confidence)
    }

    public func classifyWithBackend(cgImage: CGImage, metadata: PhotoMetadata, faceCount: Int) -> (category: WeddingCategory, confidence: Double, backend: ClassificationBackend) {
        // If Core ML MobileCLIP image encoder is loaded, perform authentic zero-shot inference
        if let model = coreMLModel, !conceptEmbeddings.isEmpty {
            if let (cat, conf) = runMobileCLIPInference(model: model, cgImage: cgImage) {
                lastUsedBackend = .mobileCLIP
                return (cat, conf, .mobileCLIP)
            }
        }

        // Seamless fallback to Apple Vision scene classifier
        lastUsedBackend = .visionFallback
        let (fallbackCat, fallbackConf) = fallbackClassifier.classify(cgImage: cgImage, metadata: metadata, faceCount: faceCount)
        return (fallbackCat, fallbackConf, .visionFallback)
    }

    public func classifyWithObservations(_ observations: [VNClassificationObservation]?, metadata: PhotoMetadata, faceCount: Int) -> (category: WeddingCategory, confidence: Double) {
        lastUsedBackend = .visionFallback
        return fallbackClassifier.processObservations(observations, metadata: metadata, faceCount: faceCount)
    }

    public func runMobileCLIPInference(model: MLModel, cgImage: CGImage) -> (category: WeddingCategory, confidence: Double)? {
        // 1. Discover model input feature dynamically
        let inputInfo = discoverInputImageDetails(model: model)

        // 2. Preprocess CGImage into CVPixelBuffer at expected dimensions
        guard let pixelBuffer = createPixelBuffer(from: cgImage, width: inputInfo.width, height: inputInfo.height) else {
            return nil
        }

        // 3. Construct input feature provider
        let featureProvider: MLDictionaryFeatureProvider
        do {
            featureProvider = try MLDictionaryFeatureProvider(dictionary: [inputInfo.name: pixelBuffer])
        } catch {
            return nil
        }

        // 4. Run Core ML prediction
        let outputProvider: MLFeatureProvider
        do {
            outputProvider = try model.prediction(from: featureProvider)
        } catch {
            return nil
        }

        // 5. Extract multiArray output dynamically
        guard let rawEmbedding = extractEmbedding(from: outputProvider, model: model), !rawEmbedding.isEmpty else {
            return nil
        }

        // 6. Dimensionality validation against concept embeddings
        let expectedDim = conceptEmbeddings.values.first?.count ?? 512
        guard rawEmbedding.count == expectedDim else {
            return nil
        }

        // 7. L2 Normalization of image embedding
        var sumSquares: Float = 0.0
        for v in rawEmbedding { sumSquares += v * v }
        let norm = sqrt(sumSquares)
        guard norm > 1e-6 else { return nil }
        let normalizedEmbedding = rawEmbedding.map { $0 / norm }

        // 8. Cosine similarity against precalculated concept embeddings
        var bestCategory: WeddingCategory = .other
        var maxSimilarity: Float = -Float.greatestFiniteMagnitude

        for (category, conceptVec) in conceptEmbeddings {
            let sim = Self.cosineSimilarity(normalizedEmbedding, conceptVec)
            if sim > maxSimilarity {
                maxSimilarity = sim
                bestCategory = category
            }
        }

        // 9. Calibrated confidence mapping from cosine similarity [-1, 1] to [0.1, 1.0]
        let calibratedConfidence = Double(min(1.0, max(0.1, (maxSimilarity + 1.0) / 2.0)))
        return (bestCategory, calibratedConfidence)
    }

    // MARK: - Helpers

    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dot: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 1e-6 else { return 0.0 }
        return dot / denom
    }

    private func discoverInputImageDetails(model: MLModel) -> (name: String, width: Int, height: Int) {
        let inputDescriptions = model.modelDescription.inputDescriptionsByName
        for (name, desc) in inputDescriptions {
            if desc.type == .image {
                if let constraint = desc.imageConstraint {
                    return (name, constraint.pixelsWide, constraint.pixelsHigh)
                }
                return (name, 256, 256)
            }
        }
        if let first = inputDescriptions.first {
            return (first.key, 256, 256)
        }
        return ("image", 256, 256)
    }

    private func createPixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func extractEmbedding(from outputProvider: MLFeatureProvider, model: MLModel) -> [Float]? {
        let outputDescriptions = model.modelDescription.outputDescriptionsByName
        for (name, desc) in outputDescriptions {
            if desc.type == .multiArray,
               let featureValue = outputProvider.featureValue(for: name),
               let multiArray = featureValue.multiArrayValue {
                return multiArrayToFloatArray(multiArray)
            }
        }
        for name in outputProvider.featureNames {
            if let fv = outputProvider.featureValue(for: name),
               let multiArray = fv.multiArrayValue {
                return multiArrayToFloatArray(multiArray)
            }
        }
        return nil
    }

    private func multiArrayToFloatArray(_ multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = Float(truncating: multiArray[i])
        }
        return result
    }
}
