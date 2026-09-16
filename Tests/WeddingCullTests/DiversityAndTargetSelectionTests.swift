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
}
