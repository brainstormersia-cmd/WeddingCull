import XCTest
import CoreGraphics
import CoreML
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class MobileCLIPInferenceTests: XCTestCase {

    func testConceptEmbeddingsLoadingAndDimensionality() throws {
        let classifier = MobileCLIPClassifier()
        // Ensure classifier loads the bundled or local concept embeddings
        let dummyImage = createSolidColorCGImage(color: .white, width: 256, height: 256)
        let metadata = PhotoMetadata()
        let result = classifier.classify(cgImage: dummyImage, metadata: metadata, faceCount: 0)

        XCTAssertNotNil(result.category, "Classifier must return a valid category")
        XCTAssertGreaterThan(result.confidence, 0.0, "Confidence must be strictly positive")
    }

    func testCosineSimilarityCalculation() {
        // Identical unit vectors -> 1.0
        let v1: [Float] = [1.0, 0.0, 0.0]
        let v2: [Float] = [1.0, 0.0, 0.0]
        XCTAssertEqual(MobileCLIPClassifier.cosineSimilarity(v1, v2), 1.0, accuracy: 1e-5)

        // Orthogonal vectors -> 0.0
        let v3: [Float] = [0.0, 1.0, 0.0]
        XCTAssertEqual(MobileCLIPClassifier.cosineSimilarity(v1, v3), 0.0, accuracy: 1e-5)

        // Opposite vectors -> -1.0
        let v4: [Float] = [-1.0, 0.0, 0.0]
        XCTAssertEqual(MobileCLIPClassifier.cosineSimilarity(v1, v4), -1.0, accuracy: 1e-5)

        // Dimension mismatch -> 0.0
        let vShort: [Float] = [1.0, 0.0]
        XCTAssertEqual(MobileCLIPClassifier.cosineSimilarity(v1, vShort), 0.0)

        // Empty vector -> 0.0
        XCTAssertEqual(MobileCLIPClassifier.cosineSimilarity([], []), 0.0)
    }

    func testGracefulFallbackWhenModelAbsent() {
        // Intentionally initialize with non-existent model URL
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_mobileclip_\(UUID().uuidString).mlmodelc")
        let classifier = MobileCLIPClassifier(customModelURL: nonExistentURL)

        XCTAssertFalse(classifier.isCoreMLModelLoaded, "Model should not be loaded from invalid path")

        let dummyImage = createSolidColorCGImage(color: .white, width: 100, height: 100)
        let metadata = PhotoMetadata()
        let result = classifier.classifyWithBackend(cgImage: dummyImage, metadata: metadata, faceCount: 0)

        XCTAssertEqual(result.backend, .visionFallback, "Backend must report visionFallback when Core ML is absent")
        XCTAssertNotNil(result.category)
        XCTAssertGreaterThan(result.confidence, 0.0)
        XCTAssertEqual(classifier.lastUsedBackend, .visionFallback)
    }

    func testConceptEmbeddingsJSONStructure() throws {
        // Read WeddingConceptsEmbeddings.json directly
        let candidates = [
            URL(fileURLWithPath: "Sources/ML/Resources/WeddingConceptsEmbeddings.json"),
            URL(fileURLWithPath: "../Sources/ML/Resources/WeddingConceptsEmbeddings.json")
        ]
        var foundData: Data? = nil
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            foundData = try? Data(contentsOf: candidate)
            break
        }

        XCTAssertNotNil(foundData, "WeddingConceptsEmbeddings.json must exist in project sources")
        guard let data = foundData else { return }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)

        let dimensions = json?["dimensions"] as? Int
        XCTAssertEqual(dimensions, 512, "MobileCLIP-S0 embeddings must be 512-dimensional")

        let categories = json?["categories"] as? [String: [Double]]
        XCTAssertNotNil(categories)
        XCTAssertEqual(categories?.count, 12, "All 12 wedding categories must be present")

        // Verify all 12 categories are normalized unit vectors (L2 norm ~ 1.0)
        for (categoryName, values) in categories ?? [:] {
            XCTAssertEqual(values.count, 512, "Category \(categoryName) must have exactly 512 float dimensions")
            let sumSq = values.reduce(0.0) { $0 + $1 * $1 }
            let norm = sqrt(sumSq)
            XCTAssertEqual(norm, 1.0, accuracy: 1e-3, "Category \(categoryName) embedding must be L2-normalized")
        }
    }

    private func createSolidColorCGImage(color: CGColor, width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
