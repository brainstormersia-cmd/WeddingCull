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
        completedPhases: [String] = []
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
    }
}
