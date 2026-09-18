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
    public let votes_a: Int?
    public let votes_b: Int?
    public let has_raw_votes: Bool
    public let derived_order_preference: String?
    public let reasons: [String]?

    public var totalVotes: Int {
        return (votes_a ?? 0) + (votes_b ?? 0)
    }

    /// Derived majority winner if not tied
    public var majorityWinner: String? {
        guard let va = votes_a, let vb = votes_b else {
            return derived_order_preference
        }
        if va > vb { return photo_a }
        if vb > va { return photo_b }
        return nil // Exact tie
    }

    /// Preference probability for photo_a: votes_a / totalVotes (0.5 if tied or no votes)
    public var preferenceProbabilityA: Double {
        guard let va = votes_a, let vb = votes_b, (va + vb) > 0 else { return 0.5 }
        return Double(va) / Double(va + vb)
    }

    /// Preference probability for majority winner: max(votes_a, votes_b) / totalVotes
    public var preferenceProbabilityWinner: Double {
        guard let va = votes_a, let vb = votes_b, (va + vb) > 0 else { return 0.5 }
        return Double(max(va, vb)) / Double(va + vb)
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
        votes_a: Int?,
        votes_b: Int?,
        has_raw_votes: Bool = true,
        derived_order_preference: String? = nil,
        reasons: [String]? = nil
    ) {
        self.photo_a = photo_a
        self.photo_b = photo_b
        self.votes_a = votes_a
        self.votes_b = votes_b
        self.has_raw_votes = has_raw_votes
        self.derived_order_preference = derived_order_preference
        self.reasons = reasons
    }

    enum CodingKeys: String, CodingKey {
        case photo_a
        case photo_b
        case votes_a
        case votes_b
        case has_raw_votes
        case derived_order_preference
        case reasons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        photo_a = try container.decode(String.self, forKey: .photo_a)
        photo_b = try container.decode(String.self, forKey: .photo_b)
        votes_a = try container.decodeIfPresent(Int.self, forKey: .votes_a)
        votes_b = try container.decodeIfPresent(Int.self, forKey: .votes_b)
        if let raw = try container.decodeIfPresent(Bool.self, forKey: .has_raw_votes) {
            has_raw_votes = raw
        } else {
            has_raw_votes = (votes_a != nil && votes_b != nil)
        }
        derived_order_preference = try container.decodeIfPresent(String.self, forKey: .derived_order_preference)
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(photo_a, forKey: .photo_a)
        try container.encode(photo_b, forKey: .photo_b)
        try container.encodeIfPresent(votes_a, forKey: .votes_a)
        try container.encodeIfPresent(votes_b, forKey: .votes_b)
        try container.encode(has_raw_votes, forKey: .has_raw_votes)
        try container.encodeIfPresent(derived_order_preference, forKey: .derived_order_preference)
        try container.encodeIfPresent(reasons, forKey: .reasons)
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
