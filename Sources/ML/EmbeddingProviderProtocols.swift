import Foundation
import CoreGraphics
import Vision

public protocol VisualEmbeddingProvider: Sendable {
    func generateEmbedding(from cgImage: CGImage) async throws -> [Float]
}

public protocol SemanticEmbeddingProvider: Sendable {
    func isAvailable() -> Bool
    func classifyZeroShot(cgImage: CGImage, categoryPrompts: [WeddingCategory: [String]]) async throws -> (category: WeddingCategory, confidence: Double)
}

public protocol ImageClassifierProtocol: Sendable {
    func classify(cgImage: CGImage, metadata: PhotoMetadata, faceCount: Int) -> (category: WeddingCategory, confidence: Double)
}
