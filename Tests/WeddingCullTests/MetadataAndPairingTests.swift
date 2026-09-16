import XCTest
@testable import WeddingCull

final class MetadataAndPairingTests: XCTestCase {
    func testRawJpegPairing() {
        let importer = PhotoImporter()
        let urls = [
            URL(fileURLWithPath: "/photos/IMG_0001.CR3"),
            URL(fileURLWithPath: "/photos/IMG_0001.JPG"),
            URL(fileURLWithPath: "/photos/IMG_0002.JPG"),
            URL(fileURLWithPath: "/photos/IMG_0003.ARW")
        ]

        let paired = importer.groupRawJpegPairs(fileURLs: urls)
        XCTAssertEqual(paired.count, 3)

        // First item should be paired (both raw and jpeg present)
        let pair1 = paired.first(where: { $0.primary.lastPathComponent.contains("IMG_0001") })
        XCTAssertNotNil(pair1)
        XCTAssertNotNil(pair1?.raw)
        XCTAssertNotNil(pair1?.jpeg)

        // Second item should be JPEG only
        let pair2 = paired.first(where: { $0.primary.lastPathComponent.contains("IMG_0002") })
        XCTAssertNotNil(pair2)
        XCTAssertNil(pair2?.raw)
        XCTAssertNotNil(pair2?.jpeg)

        // Third item should be RAW only
        let pair3 = paired.first(where: { $0.primary.lastPathComponent.contains("IMG_0003") })
        XCTAssertNotNil(pair3)
        XCTAssertNotNil(pair3?.raw)
        XCTAssertNil(pair3?.jpeg)
    }

    func testMetadataFormatting() {
        var metadata = PhotoMetadata()
        metadata.aperture = 1.4
        metadata.shutterSpeed = 0.005 // 1/200s
        metadata.iso = 800
        metadata.focalLength = 85.0
        metadata.cameraModel = "Sony A7 IV"

        XCTAssertEqual(metadata.apertureFormatted, "ƒ/1.4")
        XCTAssertEqual(metadata.shutterSpeedFormatted, "1/200s")
        XCTAssertEqual(metadata.isoFormatted, "ISO 800")
        XCTAssertEqual(metadata.focalLengthFormatted, "85mm")
        XCTAssertEqual(metadata.cameraSummary, "Sony A7 IV")
    }

    func testCorruptImageHandling() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_test_\(UUID().uuidString).jpg")
        try? "THIS_IS_NOT_AN_IMAGE".data(using: .utf8)?.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = PhotoImporter()
        let metadata = importer.extractMetadata(from: tempURL)
        XCTAssertTrue(metadata.isCorrupt, "Corrupt file must be reported as corrupt without crashing")
    }
}
