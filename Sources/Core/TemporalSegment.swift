import Foundation

public struct TemporalSegment: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var startTime: Date
    public var endTime: Date
    public var photoIDs: [String]
    public var inferredCategory: WeddingCategory
    public var confidence: Double
    public var selectionQuota: Int

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        startTime: Date = Date(),
        endTime: Date = Date(),
        photoIDs: [String] = [],
        inferredCategory: WeddingCategory = .other,
        confidence: Double = 0.5,
        selectionQuota: Int = 0
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.photoIDs = photoIDs
        self.inferredCategory = inferredCategory
        self.confidence = confidence
        self.selectionQuota = selectionQuota
    }

    public var durationMinutes: Double {
        return max(1.0, endTime.timeIntervalSince(startTime) / 60.0)
    }

    public var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
}
