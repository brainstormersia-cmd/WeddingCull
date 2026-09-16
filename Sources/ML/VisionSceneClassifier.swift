import Foundation
import CoreGraphics
import Vision

public final class VisionSceneClassifier: ImageClassifierProtocol, Sendable {
    public init() {}

    public func classify(cgImage: CGImage, metadata: PhotoMetadata, faceCount: Int) -> (category: WeddingCategory, confidence: Double) {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        var visionScores: [WeddingCategory: Double] = [:]

        do {
            try handler.perform([request])
            if let observations = request.results {
                for obs in observations where obs.confidence >= 0.1 {
                    let identifier = obs.identifier.lowercased()
                    let confidence = Double(obs.confidence)

                    if let cat = mapVisionIdentifierToCategory(identifier) {
                        visionScores[cat] = max(visionScores[cat] ?? 0.0, confidence)
                    }
                }
            }
        } catch {
            // Vision classify unavailable or failed; use heuristics
        }

        // Apply context heuristics
        if faceCount == 0 {
            visionScores[.details] = (visionScores[.details] ?? 0.3) + 0.3
        } else if faceCount == 1 {
            visionScores[.bride] = (visionScores[.bride] ?? 0.2) + 0.15
            visionScores[.groom] = (visionScores[.groom] ?? 0.2) + 0.15
        } else if faceCount == 2 {
            visionScores[.couple] = (visionScores[.couple] ?? 0.3) + 0.35
            visionScores[.ceremony] = (visionScores[.ceremony] ?? 0.2) + 0.15
        } else if faceCount >= 5 {
            visionScores[.familyAndGroups] = (visionScores[.familyAndGroups] ?? 0.3) + 0.3
            visionScores[.guestsCandid] = (visionScores[.guestsCandid] ?? 0.2) + 0.2
        }

        // Find best category
        if let best = visionScores.max(by: { $0.value < $1.value }) {
            return (best.key, min(1.0, max(0.3, best.value)))
        }

        // Fallback default
        if faceCount > 0 {
            return (.guestsCandid, 0.4)
        } else {
            return (.details, 0.4)
        }
    }

    private func mapVisionIdentifierToCategory(_ identifier: String) -> WeddingCategory? {
        if identifier.contains("wedding dress") || identifier.contains("veil") || identifier.contains("bride") {
            return .bride
        }
        if identifier.contains("tuxedo") || identifier.contains("groom") || identifier.contains("suit") {
            return .groom
        }
        if identifier.contains("altar") || identifier.contains("church") || identifier.contains("chapel") || identifier.contains("ceremony") {
            return .ceremony
        }
        if identifier.contains("couple") || identifier.contains("hug") || identifier.contains("kiss") || identifier.contains("romance") {
            return .couple
        }
        if identifier.contains("cake") || identifier.contains("toast") || identifier.contains("champagne") || identifier.contains("dessert") {
            return .cakeAndToast
        }
        if identifier.contains("dance") || identifier.contains("dancing") || identifier.contains("disco") || identifier.contains("stage") || identifier.contains("party") {
            return .danceParty
        }
        if identifier.contains("dining") || identifier.contains("banquet") || identifier.contains("table") || identifier.contains("buffet") {
            return .reception
        }
        if identifier.contains("flower") || identifier.contains("bouquet") || identifier.contains("ring") || identifier.contains("jewelry") || identifier.contains("decor") {
            return .details
        }
        if identifier.contains("crowd") || identifier.contains("audience") || identifier.contains("group") {
            return .familyAndGroups
        }
        return nil
    }
}
