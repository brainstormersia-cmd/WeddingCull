import Foundation

// MARK: - Canonical Real-Image Series Dataset Schema

public struct RealSeriesBenchmarkDataset: Codable, Sendable {
    public let version: String
    public let dataset_name: String
    public let description: String?
    public let total_series: Int
    public let total_frames: Int
    public let series: [RealPhotoSeries]

    public init(
        version: String = "2.0",
        dataset_name: String,
        description: String? = nil,
        total_series: Int,
        total_frames: Int,
        series: [RealPhotoSeries]
    ) {
        self.version = version
        self.dataset_name = dataset_name
        self.description = description
        self.total_series = total_series
        self.total_frames = total_frames
        self.series = series
    }
}

public struct RealPhotoSeries: Codable, Sendable {
    public let series_id: String
    public let scene_type: String
    public let description: String?
    public let frames: [RealSeriesFrame]
    public let ground_truth: SeriesGroundTruth

    public init(
        series_id: String,
        scene_type: String = "burst",
        description: String? = nil,
        frames: [RealSeriesFrame],
        ground_truth: SeriesGroundTruth
    ) {
        self.series_id = series_id
        self.scene_type = scene_type
        self.description = description
        self.frames = frames
        self.ground_truth = ground_truth
    }
}

public struct RealSeriesFrame: Codable, Sendable {
    public let photo_id: String
    public let image_path: String

    public init(photo_id: String, image_path: String) {
        self.photo_id = photo_id
        self.image_path = image_path
    }
}

public struct GroundTruthPairwiseComparison: Codable, Sendable {
    public let photo_a: String
    public let photo_b: String
    public let votes_a: Int
    public let votes_b: Int
    public let reasons: [String]?

    public var totalVotes: Int {
        return votes_a + votes_b
    }

    /// Derived majority winner if not tied
    public var majorityWinner: String? {
        if votes_a > votes_b { return photo_a }
        if votes_b > votes_a { return photo_b }
        return nil // Exact tie
    }

    /// Preference probability for photo_a: votes_a / totalVotes (0.5 if tied or no votes)
    public var preferenceProbabilityA: Double {
        guard totalVotes > 0 else { return 0.5 }
        return Double(votes_a) / Double(totalVotes)
    }

    /// Preference probability for majority winner: max(votes_a, votes_b) / totalVotes
    public var preferenceProbabilityWinner: Double {
        guard totalVotes > 0 else { return 0.5 }
        return Double(max(votes_a, votes_b)) / Double(totalVotes)
    }

    /// Annotator agreement: proportion of votes for majority winner
    public var annotatorAgreement: Double {
        return preferenceProbabilityWinner
    }

    /// True if annotator agreement is below 0.70 (indicating significant ambiguity or division among annotators)
    public var isAmbiguous: Bool {
        return annotatorAgreement < 0.70
    }

    public init(
        photo_a: String,
        photo_b: String,
        votes_a: Int,
        votes_b: Int,
        reasons: [String]? = nil
    ) {
        self.photo_a = photo_a
        self.photo_b = photo_b
        self.votes_a = votes_a
        self.votes_b = votes_b
        self.reasons = reasons
    }
}

public struct SeriesGroundTruth: Codable, Sendable {
    public let preferred_order: [String]?
    public let acceptable_keepers: [String]?
    public let unacceptable_rejects: [String]?
    public let pairwise_comparisons: [GroundTruthPairwiseComparison]?
    public let reasons: [String: String]?

    public init(
        preferred_order: [String]? = nil,
        acceptable_keepers: [String]? = nil,
        unacceptable_rejects: [String]? = nil,
        pairwise_comparisons: [GroundTruthPairwiseComparison]? = nil,
        reasons: [String: String]? = nil
    ) {
        self.preferred_order = preferred_order
        self.acceptable_keepers = acceptable_keepers
        self.unacceptable_rejects = unacceptable_rejects
        self.pairwise_comparisons = pairwise_comparisons
        self.reasons = reasons
    }
}

// MARK: - Completeness and Measured Feature Records

public struct SeriesEvaluationRecord: Codable, Sendable {
    public let seriesId: String
    public let sceneType: String
    public let expectedFrameCount: Int
    public let foundFrameCount: Int
    public let missingPhotoIds: [String]
    public let decodeFailures: [String]
    public let isEvaluable: Bool
    public let exclusionReason: String?

    public init(
        seriesId: String,
        sceneType: String,
        expectedFrameCount: Int,
        foundFrameCount: Int,
        missingPhotoIds: [String],
        decodeFailures: [String],
        isEvaluable: Bool,
        exclusionReason: String?
    ) {
        self.seriesId = seriesId
        self.sceneType = sceneType
        self.expectedFrameCount = expectedFrameCount
        self.foundFrameCount = foundFrameCount
        self.missingPhotoIds = missingPhotoIds
        self.decodeFailures = decodeFailures
        self.isEvaluable = isEvaluable
        self.exclusionReason = exclusionReason
    }
}

public struct MeasuredPhotoFeatures: Codable, Sendable {
    public let photoId: String
    public let rawSharpness: Double
    public let faceSharpness: Double?
    public let detectionConfidence: Double
    public let faceCaptureQuality: Double?
    public let eyeOpenness: Double?
    public let meanLuminance: Double
    public let shadowClipping: Double
    public let highlightClipping: Double
    public let exposureScore: Double

    public init(
        photoId: String,
        rawSharpness: Double,
        faceSharpness: Double?,
        detectionConfidence: Double,
        faceCaptureQuality: Double?,
        eyeOpenness: Double?,
        meanLuminance: Double,
        shadowClipping: Double,
        highlightClipping: Double,
        exposureScore: Double
    ) {
        self.photoId = photoId
        self.rawSharpness = rawSharpness
        self.faceSharpness = faceSharpness
        self.detectionConfidence = detectionConfidence
        self.faceCaptureQuality = faceCaptureQuality
        self.eyeOpenness = eyeOpenness
        self.meanLuminance = meanLuminance
        self.shadowClipping = shadowClipping
        self.highlightClipping = highlightClipping
        self.exposureScore = exposureScore
    }
}

public struct SeriesRankingDetail: Codable, Sendable {
    public let series_id: String
    public let scene_type: String
    public let human_ranking: [String]?
    public let baseline_ranking: [String]
    public let experimental_ranking: [String]
    public let baseline_winner: String
    public let experimental_winner: String
    public let winner_changed: Bool
    public let baseline_correct: Bool?
    public let experimental_correct: Bool?
    public let flip_classification: String // "IMPROVEMENT", "REGRESSION", "NEUTRAL_FLIP", "NO_FLIP", "N/A"
    public let photo_features: [String: MeasuredPhotoFeatures]

    public init(
        series_id: String,
        scene_type: String,
        human_ranking: [String]?,
        baseline_ranking: [String],
        experimental_ranking: [String],
        baseline_winner: String,
        experimental_winner: String,
        winner_changed: Bool,
        baseline_correct: Bool?,
        experimental_correct: Bool?,
        flip_classification: String,
        photo_features: [String: MeasuredPhotoFeatures]
    ) {
        self.series_id = series_id
        self.scene_type = scene_type
        self.human_ranking = human_ranking
        self.baseline_ranking = baseline_ranking
        self.experimental_ranking = experimental_ranking
        self.baseline_winner = baseline_winner
        self.experimental_winner = experimental_winner
        self.winner_changed = winner_changed
        self.baseline_correct = baseline_correct
        self.experimental_correct = experimental_correct
        self.flip_classification = flip_classification
        self.photo_features = photo_features
    }
}
