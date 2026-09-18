import Foundation

public final class TemporalSegmenter: Sendable {
    public init() {}

    public func segment(items: [PhotoItem]) -> [TemporalSegment] {
        guard !items.isEmpty else { return [] }

        // Sort chronologically (with strict ID tie-breaker for photos taken at identical timestamp)
        let sorted = items.sorted {
            let dateA = $0.metadata.captureDate ?? $0.fileModificationDate
            let dateB = $1.metadata.captureDate ?? $1.fileModificationDate
            if dateA != dateB {
                return dateA < dateB
            }
            return $0.id < $1.id
        }

        var segments: [TemporalSegment] = []
        var currentItems: [PhotoItem] = []

        // Break if time gap > 20 minutes (1200 seconds)
        let timeGapThreshold: TimeInterval = 1200.0

        for item in sorted {
            if currentItems.isEmpty {
                currentItems.append(item)
                continue
            }

            let prevItem = currentItems.last!
            let prevDate = prevItem.metadata.captureDate ?? prevItem.fileModificationDate
            let currDate = item.metadata.captureDate ?? item.fileModificationDate
            let gap = abs(currDate.timeIntervalSince(prevDate))

            let shouldBreak = gap > timeGapThreshold

            if shouldBreak {
                segments.append(createSegment(from: currentItems, index: segments.count + 1))
                currentItems = [item]
            } else {
                currentItems.append(item)
            }
        }

        if !currentItems.isEmpty {
            segments.append(createSegment(from: currentItems, index: segments.count + 1))
        }

        return segments
    }

    private func createSegment(from items: [PhotoItem], index: Int) -> TemporalSegment {
        let firstDate = items.first?.metadata.captureDate ?? items.first?.fileModificationDate ?? Date()
        let lastDate = items.last?.metadata.captureDate ?? items.last?.fileModificationDate ?? Date()

        // Majority vote for segment category (with deterministic rawValue tie-breaker)
        var categoryCounts: [WeddingCategory: Int] = [:]
        for item in items {
            categoryCounts[item.category, default: 0] += 1
        }
        let dominantCategory = categoryCounts.max { a, b in
            if a.value != b.value {
                return a.value < b.value
            }
            return a.key.rawValue < b.key.rawValue
        }?.key ?? .other

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeLabel = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
        let name = "Moment \(index): \(dominantCategory.displayName) (\(timeLabel))"

        return TemporalSegment(
            id: "segment_\(index)_\(Int(firstDate.timeIntervalSince1970))",
            name: name,
            startTime: firstDate,
            endTime: lastDate,
            photoIDs: items.map { $0.id },
            inferredCategory: dominantCategory,
            confidence: 0.8,
            selectionQuota: 0
        )
    }
}
