import Foundation

public struct BurstGroup: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var memberIDs: [String]
    public var winnerID: String
    public var alternativeIDs: [String]
    public var reviewIDs: [String]
    public var timeRangeSeconds: Double
    public var averageSimilarity: Double

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        memberIDs: [String] = [],
        winnerID: String = "",
        alternativeIDs: [String] = [],
        reviewIDs: [String] = [],
        timeRangeSeconds: Double = 0.0,
        averageSimilarity: Double = 0.0
    ) {
        self.id = id
        self.name = name.isEmpty ? "Burst \(id.prefix(6))" : name
        self.memberIDs = memberIDs
        self.winnerID = winnerID
        self.alternativeIDs = alternativeIDs
        self.reviewIDs = reviewIDs
        self.timeRangeSeconds = timeRangeSeconds
        self.averageSimilarity = averageSimilarity
    }
}
