import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class DiversityAndTargetSelectionTests: XCTestCase {
    func testExactTargetCountSelection() {
        var items: [PhotoItem] = []
        for i in 0..<100 {
            var item = PhotoItem(id: "photo_\(i)", fileName: "photo_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(i).jpg"))
            item.metrics.overallScore = Double(i) / 100.0
            item.perceptualHash = UInt64(i * 1000)
            items.append(item)
        }

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 40)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 40, "Must select exactly 40 photographs")
    }

    func testUserOverridesPersistence() {
        var items: [PhotoItem] = []
        for i in 0..<20 {
            var item = PhotoItem(id: "photo_\(i)", fileName: "photo_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(i).jpg"))
            item.metrics.overallScore = Double(i) / 20.0
            items.append(item)
        }

        // Force item 0 (lowest score) to be userSelected
        items[0].selectionState = .userSelected

        // Force item 19 (highest score) to be userRejected
        items[19].selectionState = .userRejected

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 5)

        let item0 = result.updatedItems.first(where: { $0.id == "photo_0" })!
        let item19 = result.updatedItems.first(where: { $0.id == "photo_19" })!

        XCTAssertEqual(item0.selectionState, .userSelected, "User selected photo must remain selected")
        XCTAssertTrue(item0.selectionState.isIncludedInFinal)

        XCTAssertEqual(item19.selectionState, .userRejected, "User rejected photo must remain rejected")
        XCTAssertFalse(item19.selectionState.isIncludedInFinal)
    }

    func testTargetCountExceedingAvailable() {
        var items: [PhotoItem] = []
        for i in 0..<15 {
            var item = PhotoItem(id: "photo_\(i)", fileName: "photo_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(i).jpg"))
            item.metrics.overallScore = 0.8
            items.append(item)
        }

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 50)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 15, "When target exceeds available, select all eligible photos without crashing")
    }

    func testTemporalSegmentDominanceCapped() {
        var items: [PhotoItem] = []
        let dominantSegID = "seg_ceremony"
        let minorSegID = "seg_reception"

        // Create 80 photos in dominant segment with high scores (0.90)
        for i in 0..<80 {
            var item = PhotoItem(id: "dom_\(i)", fileName: "dom_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/dom_\(i).jpg"))
            item.metrics.overallScore = 0.90
            item.temporalSegmentID = dominantSegID
            item.perceptualHash = UInt64(i * 100)
            items.append(item)
        }

        // Create 40 photos in minor segment with slightly lower scores (0.75)
        for i in 0..<40 {
            var item = PhotoItem(id: "min_\(i)", fileName: "min_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/min_\(i).jpg"))
            item.metrics.overallScore = 0.75
            item.temporalSegmentID = minorSegID
            item.perceptualHash = UInt64(i * 500 + 100000)
            items.append(item)
        }

        let segments = [
            TemporalSegment(id: dominantSegID, startTime: Date(), endTime: Date().addingTimeInterval(3600), photoIDs: items.filter { $0.temporalSegmentID == dominantSegID }.map(\.id)),
            TemporalSegment(id: minorSegID, startTime: Date().addingTimeInterval(3600), endTime: Date().addingTimeInterval(7200), photoIDs: items.filter { $0.temporalSegmentID == minorSegID }.map(\.id))
        ]

        let targetCount = 50
        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: segments, bursts: [], targetCount: targetCount)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, targetCount)

        let dominantSelected = selected.filter { $0.temporalSegmentID == dominantSegID }
        let maxAllowed = Int(ceil(Double(targetCount) * 0.60)) // 60% of 50 = 30
        XCTAssertLessThanOrEqual(dominantSelected.count, maxAllowed, "Dominant segment must not exceed 60% of final selection")
        XCTAssertGreaterThan(selected.filter { $0.temporalSegmentID == minorSegID }.count, 0, "Minor segment must be represented")
    }

    func testCategoryDiversityCoverage() {
        var items: [PhotoItem] = []
        let categories: [WeddingCategory] = [
            .bridePrep, .groomPrep, .ceremony, .bride, .groom, .couple, .reception, .details
        ]

        for (cIdx, cat) in categories.enumerated() {
            for i in 0..<10 {
                var item = PhotoItem(id: "photo_\(cat.rawValue)_\(i)", fileName: "photo_\(cat.rawValue)_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(cat.rawValue)_\(i).jpg"))
                // Give earlier categories much higher scores
                item.metrics.overallScore = Double(10 - cIdx) * 0.1
                item.category = cat
                item.perceptualHash = UInt64((cIdx * 10 + i) * 777)
                items.append(item)
            }
        }

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 20)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 20)

        let uniqueCategories = Set(selected.map(\.category))
        XCTAssertGreaterThanOrEqual(uniqueCategories.count, 4, "Selection must cover at least 4 distinct wedding categories when source spans 8")
    }

    func testBurstWinnerPreference() {
        var items: [PhotoItem] = []
        let burstID = "burst_1"
        let winnerID = "burst_1_frame_2"
        let memberIDs = ["burst_1_frame_1", "burst_1_frame_2", "burst_1_frame_3"]

        for id in memberIDs {
            var item = PhotoItem(id: id, fileName: "\(id).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(id).jpg"))
            item.burstGroupID = burstID
            item.metrics.overallScore = 0.85 // Identical base scores
            item.perceptualHash = 12345 // Near identical visual hash
            items.append(item)
        }

        let burst = BurstGroup(id: burstID, memberIDs: memberIDs, winnerID: winnerID, alternativeIDs: ["burst_1_frame_1", "burst_1_frame_3"])

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [burst], targetCount: 1)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.id, winnerID, "Burst winner must be preferred over burst alternatives")
    }

    func testExactDuplicateExclusion() {
        var items: [PhotoItem] = []
        var original = PhotoItem(id: "original", fileName: "original.jpg", sourceURL: URL(fileURLWithPath: "/tmp/original.jpg"))
        original.metrics.overallScore = 0.95
        original.isDuplicate = false
        items.append(original)

        var duplicate = PhotoItem(id: "duplicate", fileName: "duplicate.jpg", sourceURL: URL(fileURLWithPath: "/tmp/duplicate.jpg"))
        duplicate.metrics.overallScore = 0.99 // Higher score than original
        duplicate.isDuplicate = true
        duplicate.duplicateOfID = "original"
        items.append(duplicate)

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 1)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.id, "original", "Exact duplicates must not be selected")
        XCTAssertEqual(result.updatedItems.first(where: { $0.id == "duplicate" })?.selectionState, .rejected)
    }

    func testSelectionWhenTargetCountIsLessThanSegmentCount() {
        // Reproduce edge case: 7 segments but user requests only 4 or 6 photos (targetCount < segments.count)
        var items: [PhotoItem] = []
        var segments: [TemporalSegment] = []

        for segIdx in 0..<7 {
            let segID = "segment_\(segIdx)"
            var segPhotoIDs: [String] = []
            for p in 0..<5 {
                let photoID = "photo_\(segIdx)_\(p)"
                segPhotoIDs.append(photoID)
                var item = PhotoItem(
                    id: photoID,
                    fileName: "\(photoID).jpg",
                    sourceURL: URL(fileURLWithPath: "/tmp/\(photoID).jpg")
                )
                item.temporalSegmentID = segID
                item.metrics.overallScore = 0.5 + Double(segIdx * 5 + p) * 0.01
                item.perceptualHash = UInt64(segIdx * 1000 + p * 10)
                items.append(item)
            }
            segments.append(
                TemporalSegment(
                    id: segID,
                    startTime: Date().addingTimeInterval(Double(segIdx * 3600)),
                    endTime: Date().addingTimeInterval(Double(segIdx * 3600 + 1800)),
                    photoIDs: segPhotoIDs
                )
            )
        }

        let selector = DiversitySelector()

        // Test with target 4 (< 7 segments)
        let result4 = selector.selectPhotos(items: items, segments: segments, bursts: [], targetCount: 4)
        let selected4 = result4.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected4.count, 4, "Must select exactly 4 photos even when there are 7 segments")

        // Test with target 6 (< 7 segments, UITest condition)
        let result6 = selector.selectPhotos(items: items, segments: segments, bursts: [], targetCount: 6)
        let selected6 = result6.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected6.count, 6, "Must select exactly 6 photos even when there are 7 segments")
    }
}

