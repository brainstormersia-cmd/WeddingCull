import XCTest
@testable import WeddingCull

final class BurstAndTemporalSegmentationTests: XCTestCase {
    func testBurstGroupingAndWinner() {
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        var items: [PhotoItem] = []

        // Create 4 burst frames spaced 200ms apart
        for i in 0..<4 {
            let date = baseDate.addingTimeInterval(Double(i) * 0.2)
            var item = PhotoItem(
                id: "burst_\(i)",
                fileName: "burst_\(i).jpg",
                sourceURL: URL(fileURLWithPath: "/tmp/burst_\(i).jpg"),
                metadata: PhotoMetadata(captureDate: date)
            )
            item.perceptualHash = 0b1111111100000000 // Identical hash
            item.metrics.sharpnessScore = Double(i) * 0.2 + 0.3 // Frame 3 is sharpest
            item.metrics.overallScore = item.metrics.sharpnessScore
            items.append(item)
        }

        let detector = DuplicateAndBurstDetector()
        let bursts = detector.detectBursts(items: items)

        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts[0].memberIDs.count, 4)
        // The sharpest frame (burst_3) should be chosen as winner
        XCTAssertEqual(bursts[0].winnerID, "burst_3")
        XCTAssertEqual(bursts[0].alternativeIDs.count, 3)
    }

    func testTemporalSegmentation() {
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        var items: [PhotoItem] = []

        // Moment 1: 5 photos in morning
        for i in 0..<5 {
            let date = baseDate.addingTimeInterval(Double(i) * 60)
            items.append(PhotoItem(fileName: "prep_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/prep_\(i).jpg"), metadata: PhotoMetadata(captureDate: date), category: .bridePrep))
        }

        // 45 minute gap
        let gapDate = baseDate.addingTimeInterval(45 * 60)

        // Moment 2: 5 photos in afternoon ceremony
        for i in 0..<5 {
            let date = gapDate.addingTimeInterval(Double(i) * 60)
            items.append(PhotoItem(fileName: "ceremony_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/ceremony_\(i).jpg"), metadata: PhotoMetadata(captureDate: date), category: .ceremony))
        }

        let segmenter = TemporalSegmenter()
        let segments = segmenter.segment(items: items)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].photoIDs.count, 5)
        XCTAssertEqual(segments[1].photoIDs.count, 5)
        XCTAssertEqual(segments[0].inferredCategory, .bridePrep)
        XCTAssertEqual(segments[1].inferredCategory, .ceremony)
    }
}
