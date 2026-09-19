import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

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
            item.metrics.rawSharpness = Double(i) * 200.0 + 100.0 // Realistic varying raw sharpness
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

    func testEagerVsLazyFeaturePrintEquivalence() {
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        var items: [PhotoItem] = []

        // Sequence of 50 photos:
        // - Burst 1: items 0..3 (tight time diff 0.2s, identical dHash >= 0.85)
        // - Burst 2: items 10..12 (tight time diff 0.5s, dHash diff, but low FeaturePrint distance simulated)
        // - Burst 3: items 20..22 (tight time diff 0.3s, same EXIF burst UUID)
        // - Non-bursts: items with >4s gaps or high feature distances
        for i in 0..<50 {
            let timeOffset: Double
            if i < 4 {
                timeOffset = Double(i) * 0.2
            } else if i >= 10 && i < 13 {
                timeOffset = 100.0 + Double(i - 10) * 0.5
            } else if i >= 20 && i < 23 {
                timeOffset = 200.0 + Double(i - 20) * 0.3
            } else {
                timeOffset = Double(i) * 30.0
            }

            var item = PhotoItem(
                id: "item_\(i)",
                fileName: "item_\(i).jpg",
                sourceURL: URL(fileURLWithPath: "/tmp/item_\(i).jpg"),
                metadata: PhotoMetadata(captureDate: baseDate.addingTimeInterval(timeOffset))
            )
            item.metrics.sharpnessScore = 0.5 + Double(i % 5) * 0.1
            item.metrics.overallScore = item.metrics.sharpnessScore

            if i < 4 {
                item.perceptualHash = 0xAAAAAAAAAAAAAAAA
            } else if i >= 10 && i < 13 {
                item.perceptualHash = UInt64(i * 123456789)
            } else if i >= 20 && i < 23 {
                item.metadata.burstUUID = "exif_burst_uuid_1"
                item.perceptualHash = 0x5555555555555555
            } else {
                item.perceptualHash = UInt64(i * 987654321)
            }
            items.append(item)
        }

        // Mock eager distances:
        var eagerDistances: [String: [String: Float]] = [:]
        for i in 0..<items.count {
            let itemA = items[i]
            let dateA = itemA.metadata.captureDate ?? itemA.fileModificationDate
            for j in (i + 1)..<min(items.count, i + 20) {
                let itemB = items[j]
                let dateB = itemB.metadata.captureDate ?? itemB.fileModificationDate
                if abs(dateB.timeIntervalSince(dateA)) > 4.0 { break }

                let dist: Float = (i >= 10 && j <= 12) ? 0.30 : 0.80
                eagerDistances[itemA.id, default: [:]][itemB.id] = dist
                eagerDistances[itemB.id, default: [:]][itemA.id] = dist
            }
        }

        // Mock lazy distances: only populated if needsFeaturePrint
        var lazyDistances: [String: [String: Float]] = [:]
        for i in 0..<items.count {
            let itemA = items[i]
            let dateA = itemA.metadata.captureDate ?? itemA.fileModificationDate
            for j in (i + 1)..<min(items.count, i + 20) {
                let itemB = items[j]
                let dateB = itemB.metadata.captureDate ?? itemB.fileModificationDate
                if abs(dateB.timeIntervalSince(dateA)) > 4.0 { break }

                let sameBurstUUID = itemA.metadata.burstUUID != nil && itemA.metadata.burstUUID == itemB.metadata.burstUUID
                if sameBurstUUID { continue }

                var needsFeaturePrint = true
                if let hashA = itemA.perceptualHash, let hashB = itemB.perceptualHash {
                    let sim = PerceptualHash.similarity(hashA, hashB)
                    if sim >= 0.85 {
                        needsFeaturePrint = false
                    }
                }

                guard needsFeaturePrint else { continue }

                let dist: Float = (i >= 10 && j <= 12) ? 0.30 : 0.80
                lazyDistances[itemA.id, default: [:]][itemB.id] = dist
                lazyDistances[itemB.id, default: [:]][itemA.id] = dist
            }
        }

        let detector = DuplicateAndBurstDetector()
        let eagerBursts = detector.detectBursts(items: items, featurePrintDistances: eagerDistances)
        let lazyBursts = detector.detectBursts(items: items, featurePrintDistances: lazyDistances)

        XCTAssertEqual(lazyBursts.count, eagerBursts.count, "Burst group count must match exactly")
        for (eagerB, lazyB) in zip(eagerBursts, lazyBursts) {
            XCTAssertEqual(lazyB.id, eagerB.id, "Burst group IDs must match exactly")
            XCTAssertEqual(lazyB.memberIDs, eagerB.memberIDs, "Burst member IDs must match exactly")
            XCTAssertEqual(lazyB.winnerID, eagerB.winnerID, "Burst winner ID must match exactly")
            XCTAssertEqual(lazyB.alternativeIDs, eagerB.alternativeIDs, "Burst alternative IDs must match exactly")
        }

        // Verify DiversitySelector output is 100% identical between eager and lazy bursts
        let selector = DiversitySelector()
        let eagerSelection = selector.selectPhotos(items: items, segments: [], bursts: eagerBursts, targetCount: 15)
        let lazySelection = selector.selectPhotos(items: items, segments: [], bursts: lazyBursts, targetCount: 15)

        let eagerSelectedIDs = eagerSelection.updatedItems.filter { $0.selectionState.isIncludedInFinal }.map(\.id)
        let lazySelectedIDs = lazySelection.updatedItems.filter { $0.selectionState.isIncludedInFinal }.map(\.id)
        XCTAssertEqual(lazySelectedIDs, eagerSelectedIDs, "Final selected photo IDs must match 100% between eager and lazy FeaturePrint")
    }
}
