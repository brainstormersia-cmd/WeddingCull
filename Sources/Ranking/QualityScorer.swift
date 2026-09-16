import Foundation

public final class QualityScorer: Sendable {
    public init() {}

    /// Normalizes and computes all score components for a collection of photos
    public func scorePhotos(items: [PhotoItem]) -> [PhotoItem] {
        guard !items.isEmpty else { return [] }

        // 1. Gather raw distributions for robust normalization
        let rawSharpnessValues = items.map { $0.metrics.rawSharpness }
        let rawFaceSharpnessValues = items.compactMap { $0.metrics.rawFaceSharpness }

        let sharpnessNormalizer = RobustNormalizer(values: rawSharpnessValues)
        let faceSharpnessNormalizer = RobustNormalizer(values: rawFaceSharpnessValues)

        // 2. Score each photo
        var scoredItems: [PhotoItem] = []
        scoredItems.reserveCapacity(items.count)

        for var item in items {
            var m = item.metrics

            // Normalized sharpness
            m.sharpnessScore = sharpnessNormalizer.normalize(m.rawSharpness)

            // Normalized face sharpness
            if let rawFace = m.rawFaceSharpness {
                m.faceSharpnessScore = faceSharpnessNormalizer.normalize(rawFace)
            } else {
                m.faceSharpnessScore = m.sharpnessScore // Fallback when no faces present
            }

            // Exposure score: penalized by clipping and extreme deviations from optimal middle luminance
            let luminanceDeviation = abs(m.meanLuminance - 0.5) * 2.0 // 0.0 optimal, 1.0 extreme
            let clippingPenalty = (m.shadowClipping + m.highlightClipping) * 1.5
            let expScore = max(0.05, 1.0 - (luminanceDeviation * 0.4 + clippingPenalty * 0.6))
            m.exposureScore = expScore

            // Semantic importance score based on wedding category
            m.semanticImportanceScore = min(1.0, item.category.selectionWeight / 1.5)

            // Technical score: weighted combination of sharpness and exposure
            if m.faceCount > 0 {
                m.technicalScore = (m.faceSharpnessScore * 0.45) + (m.sharpnessScore * 0.25) + (m.exposureScore * 0.30)
            } else {
                m.technicalScore = (m.sharpnessScore * 0.65) + (m.exposureScore * 0.35)
            }

            // Overall score: technical quality + face quality (if applicable) + composition + semantic weight
            var overall = (m.technicalScore * 0.45) + (m.compositionProxyScore * 0.15) + (m.semanticImportanceScore * 0.20)
            if m.faceCount > 0 {
                overall += (m.faceQualityScore * 0.20)
            } else {
                overall += (m.technicalScore * 0.20)
            }

            // Severe penalties for catastrophic defects
            if m.isSevereUnderexposed || m.isSevereOverexposed {
                overall *= 0.4
            }
            if item.metadata.isCorrupt {
                overall = 0.0
            }

            m.overallScore = max(0.01, min(1.0, overall))

            // Build factual explanatory reason
            m.selectionReason = buildSelectionReason(item: item, metrics: m)

            item.metrics = m
            scoredItems.append(item)
        }

        return scoredItems
    }

    private func buildSelectionReason(item: PhotoItem, metrics: QualityMetrics) -> String {
        var reasons: [String] = []

        if item.isBurstWinner {
            reasons.append("Best frame in burst")
        }
        if metrics.faceCount > 0 {
            if metrics.faceSharpnessScore > 0.7 {
                reasons.append("sharp faces")
            }
            if let eye = metrics.averageEyeOpenness, eye > 0.8 {
                reasons.append("eyes open")
            }
        } else if metrics.sharpnessScore > 0.7 {
            reasons.append("crisp focus")
        }

        if metrics.exposureScore > 0.8 {
            reasons.append("balanced exposure")
        }

        switch item.category {
        case .ceremony: reasons.append("ceremony coverage")
        case .couple: reasons.append("couple portrait")
        case .cakeAndToast: reasons.append("cake moment")
        case .danceParty: reasons.append("party highlight")
        case .details: reasons.append("key detail")
        default: break
        }

        if reasons.isEmpty {
            return "Good overall quality"
        } else {
            return reasons.joined(separator: " · ")
        }
    }
}
