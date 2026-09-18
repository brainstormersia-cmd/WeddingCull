import Foundation

public struct QualityMetrics: Codable, Sendable, Equatable {
    // Raw measurements
    public var rawSharpness: Double
    public var rawFaceSharpness: Double?
    public var meanLuminance: Double
    public var shadowClipping: Double
    public var highlightClipping: Double
    public var dynamicRangeProxy: Double
    public var contrastProxy: Double
    public var isSevereUnderexposed: Bool
    public var isSevereOverexposed: Bool
    public var faceCount: Int
    public var averageEyeOpenness: Double?
    public var rawFaceCaptureQuality: Double?

    // Normalized scores (0.0 to 1.0)
    public var sharpnessScore: Double
    public var faceSharpnessScore: Double
    public var exposureScore: Double
    public var faceQualityScore: Double
    public var faceCaptureQualityScore: Double?
    public var compositionProxyScore: Double
    public var uniquenessScore: Double
    public var semanticImportanceScore: Double
    public var technicalScore: Double
    public var overallScore: Double

    // Explanatory reason
    public var selectionReason: String

    public init(
        rawSharpness: Double = 0.0,
        rawFaceSharpness: Double? = nil,
        meanLuminance: Double = 0.5,
        shadowClipping: Double = 0.0,
        highlightClipping: Double = 0.0,
        dynamicRangeProxy: Double = 0.5,
        contrastProxy: Double = 0.5,
        isSevereUnderexposed: Bool = false,
        isSevereOverexposed: Bool = false,
        faceCount: Int = 0,
        averageEyeOpenness: Double? = nil,
        rawFaceCaptureQuality: Double? = nil,
        sharpnessScore: Double = 0.5,
        faceSharpnessScore: Double = 0.5,
        exposureScore: Double = 0.5,
        faceQualityScore: Double = 0.5,
        faceCaptureQualityScore: Double? = nil,
        compositionProxyScore: Double = 0.5,
        uniquenessScore: Double = 0.5,
        semanticImportanceScore: Double = 0.5,
        technicalScore: Double = 0.5,
        overallScore: Double = 0.5,
        selectionReason: String = ""
    ) {
        self.rawSharpness = rawSharpness
        self.rawFaceSharpness = rawFaceSharpness
        self.meanLuminance = meanLuminance
        self.shadowClipping = shadowClipping
        self.highlightClipping = highlightClipping
        self.dynamicRangeProxy = dynamicRangeProxy
        self.contrastProxy = contrastProxy
        self.isSevereUnderexposed = isSevereUnderexposed
        self.isSevereOverexposed = isSevereOverexposed
        self.faceCount = faceCount
        self.averageEyeOpenness = averageEyeOpenness
        self.rawFaceCaptureQuality = rawFaceCaptureQuality
        self.sharpnessScore = sharpnessScore
        self.faceSharpnessScore = faceSharpnessScore
        self.exposureScore = exposureScore
        self.faceQualityScore = faceQualityScore
        self.faceCaptureQualityScore = faceCaptureQualityScore
        self.compositionProxyScore = compositionProxyScore
        self.uniquenessScore = uniquenessScore
        self.semanticImportanceScore = semanticImportanceScore
        self.technicalScore = technicalScore
        self.overallScore = overallScore
        self.selectionReason = selectionReason
    }

    public var isTechnicallyLowQuality: Bool {
        return sharpnessScore < 0.25 || exposureScore < 0.2 || (faceCount > 0 && faceSharpnessScore < 0.2)
    }
}
