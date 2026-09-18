import Foundation

public struct SessionData: Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let currentAlgorithmVersion = 1

    public var schemaVersion: Int
    public var algorithmVersion: Int
    public var sessionID: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var sourceFolderPath: String
    public var targetSelectionCount: Int
    public var photos: [PhotoItem]
    public var burstGroups: [BurstGroup]
    public var segments: [TemporalSegment]
    public var personClusters: [PersonCluster]
    public var completedPhases: [String]
    public var phaseTimings: PhaseTimings?
    public var perceivedSpeedMetrics: PerceivedSpeedMetrics?

    public init(
        schemaVersion: Int = SessionData.currentSchemaVersion,
        algorithmVersion: Int = SessionData.currentAlgorithmVersion,
        sessionID: String = UUID().uuidString,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        sourceFolderPath: String = "",
        targetSelectionCount: Int = 700,
        photos: [PhotoItem] = [],
        burstGroups: [BurstGroup] = [],
        segments: [TemporalSegment] = [],
        personClusters: [PersonCluster] = [],
        completedPhases: [String] = [],
        phaseTimings: PhaseTimings? = nil,
        perceivedSpeedMetrics: PerceivedSpeedMetrics? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.algorithmVersion = algorithmVersion
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sourceFolderPath = sourceFolderPath
        self.targetSelectionCount = targetSelectionCount
        self.photos = photos
        self.burstGroups = burstGroups
        self.segments = segments
        self.personClusters = personClusters
        self.completedPhases = completedPhases
        self.phaseTimings = phaseTimings
        self.perceivedSpeedMetrics = perceivedSpeedMetrics
    }
}

public struct PhaseTimings: Codable, Sendable {
    public var discoverySeconds: Double
    public var previewGenerationSeconds: Double
    public var faceDetectionSeconds: Double
    public var featurePrintSeconds: Double
    public var faceAndFeatureSeconds: Double
    public var qualityScoringSeconds: Double
    public var sceneClassificationSeconds: Double
    public var burstAndDuplicateSeconds: Double
    public var clusteringAndSegmentationSeconds: Double
    public var rankingAndSelectionSeconds: Double
    public var sessionPersistenceSeconds: Double
    public var totalWallClockSeconds: Double

    public init(
        discoverySeconds: Double = 0.0,
        previewGenerationSeconds: Double = 0.0,
        faceDetectionSeconds: Double = 0.0,
        featurePrintSeconds: Double = 0.0,
        faceAndFeatureSeconds: Double = 0.0,
        qualityScoringSeconds: Double = 0.0,
        sceneClassificationSeconds: Double = 0.0,
        burstAndDuplicateSeconds: Double = 0.0,
        clusteringAndSegmentationSeconds: Double = 0.0,
        rankingAndSelectionSeconds: Double = 0.0,
        sessionPersistenceSeconds: Double = 0.0,
        totalWallClockSeconds: Double = 0.0
    ) {
        self.discoverySeconds = discoverySeconds
        self.previewGenerationSeconds = previewGenerationSeconds
        self.faceDetectionSeconds = faceDetectionSeconds
        self.featurePrintSeconds = featurePrintSeconds
        self.faceAndFeatureSeconds = faceAndFeatureSeconds != 0.0 ? faceAndFeatureSeconds : (faceDetectionSeconds + featurePrintSeconds)
        self.qualityScoringSeconds = qualityScoringSeconds
        self.sceneClassificationSeconds = sceneClassificationSeconds
        self.burstAndDuplicateSeconds = burstAndDuplicateSeconds
        self.clusteringAndSegmentationSeconds = clusteringAndSegmentationSeconds
        self.rankingAndSelectionSeconds = rankingAndSelectionSeconds
        self.sessionPersistenceSeconds = sessionPersistenceSeconds
        self.totalWallClockSeconds = totalWallClockSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case discoverySeconds
        case previewGenerationSeconds
        case faceDetectionSeconds
        case featurePrintSeconds
        case faceAndFeatureSeconds
        case qualityScoringSeconds
        case sceneClassificationSeconds
        case burstAndDuplicateSeconds
        case clusteringAndSegmentationSeconds
        case rankingAndSelectionSeconds
        case sessionPersistenceSeconds
        case totalWallClockSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.discoverySeconds = try container.decodeIfPresent(Double.self, forKey: .discoverySeconds) ?? 0.0
        self.previewGenerationSeconds = try container.decodeIfPresent(Double.self, forKey: .previewGenerationSeconds) ?? 0.0
        let faceSec = try container.decodeIfPresent(Double.self, forKey: .faceDetectionSeconds) ?? 0.0
        let fpSec = try container.decodeIfPresent(Double.self, forKey: .featurePrintSeconds) ?? 0.0
        let legacyFaceAndFeature = try container.decodeIfPresent(Double.self, forKey: .faceAndFeatureSeconds) ?? 0.0
        self.faceDetectionSeconds = faceSec
        self.featurePrintSeconds = fpSec
        self.faceAndFeatureSeconds = legacyFaceAndFeature != 0.0 ? legacyFaceAndFeature : (faceSec + fpSec)
        self.qualityScoringSeconds = try container.decodeIfPresent(Double.self, forKey: .qualityScoringSeconds) ?? 0.0
        self.sceneClassificationSeconds = try container.decodeIfPresent(Double.self, forKey: .sceneClassificationSeconds) ?? 0.0
        self.burstAndDuplicateSeconds = try container.decodeIfPresent(Double.self, forKey: .burstAndDuplicateSeconds) ?? 0.0
        self.clusteringAndSegmentationSeconds = try container.decodeIfPresent(Double.self, forKey: .clusteringAndSegmentationSeconds) ?? 0.0
        self.rankingAndSelectionSeconds = try container.decodeIfPresent(Double.self, forKey: .rankingAndSelectionSeconds) ?? 0.0
        self.sessionPersistenceSeconds = try container.decodeIfPresent(Double.self, forKey: .sessionPersistenceSeconds) ?? 0.0
        self.totalWallClockSeconds = try container.decodeIfPresent(Double.self, forKey: .totalWallClockSeconds) ?? 0.0
    }
}

public struct PerceivedSpeedMetrics: Codable, Sendable {
    public var timeToFolderReady: Double
    public var timeToFirstThumbnail: Double
    public var timeToInteractiveGrid: Double
    public var timeToFirstAnalyzedPhoto: Double
    public var timeToPreliminarySelection: Double
    public var timeToFinalSelection: Double

    public init(
        timeToFolderReady: Double = 0.0,
        timeToFirstThumbnail: Double = 0.0,
        timeToInteractiveGrid: Double = 0.0,
        timeToFirstAnalyzedPhoto: Double = 0.0,
        timeToPreliminarySelection: Double = 0.0,
        timeToFinalSelection: Double = 0.0
    ) {
        self.timeToFolderReady = timeToFolderReady
        self.timeToFirstThumbnail = timeToFirstThumbnail
        self.timeToInteractiveGrid = timeToInteractiveGrid
        self.timeToFirstAnalyzedPhoto = timeToFirstAnalyzedPhoto
        self.timeToPreliminarySelection = timeToPreliminarySelection
        self.timeToFinalSelection = timeToFinalSelection
    }
}
