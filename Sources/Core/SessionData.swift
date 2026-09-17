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
        self.faceAndFeatureSeconds = faceAndFeatureSeconds
        self.qualityScoringSeconds = qualityScoringSeconds
        self.sceneClassificationSeconds = sceneClassificationSeconds
        self.burstAndDuplicateSeconds = burstAndDuplicateSeconds
        self.clusteringAndSegmentationSeconds = clusteringAndSegmentationSeconds
        self.rankingAndSelectionSeconds = rankingAndSelectionSeconds
        self.sessionPersistenceSeconds = sessionPersistenceSeconds
        self.totalWallClockSeconds = totalWallClockSeconds
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
