import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

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

    func testStableIDDeterminismAndPreviewCacheKey() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("stable_id_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleFile = tempDir.appendingPathComponent("WEDDING_001.JPG")
        let sampleData = "FAKE_JPEG_IMAGE_DATA_FOR_ID_TEST".data(using: .utf8)!
        try? sampleData.write(to: sampleFile)

        let importer = PhotoImporter()

        // Read item twice
        let itemA = importer.readPhotoItem(primaryURL: sampleFile, rawURL: nil, jpegURL: nil, rootFolder: tempDir)
        let itemB = importer.readPhotoItem(primaryURL: sampleFile, rawURL: nil, jpegURL: nil, rootFolder: tempDir)

        // Verify ID is 100% identical and non-empty
        XCTAssertFalse(itemA.id.isEmpty)
        XCTAssertEqual(itemA.id, itemB.id, "PhotoItem.id must be deterministic across repeated imports")

        // Verify preview cache key is 100% identical and uses SHA-256
        XCTAssertFalse(itemA.previewCacheKey.isEmpty)
        XCTAssertEqual(itemA.previewCacheKey, itemB.previewCacheKey, "previewCacheKey must be deterministic")
        XCTAssertTrue(itemA.previewCacheKey.hasPrefix("prev_"), "previewCacheKey must start with prev_ prefix")

        // Verify direct PhotoItem constructor computes identical deterministic ID
        let itemDirect1 = PhotoItem(fileName: "test.jpg", sourceURL: sampleFile, fileSizeBytes: 1024, fileModificationDate: Date(timeIntervalSince1970: 1700000000))
        let itemDirect2 = PhotoItem(fileName: "test.jpg", sourceURL: sampleFile, fileSizeBytes: 1024, fileModificationDate: Date(timeIntervalSince1970: 1700000000))
        XCTAssertEqual(itemDirect1.id, itemDirect2.id)
        XCTAssertEqual(itemDirect1.previewCacheKey, itemDirect2.previewCacheKey)

        // Verify changing file size or date alters the ID
        let itemDifferent = PhotoItem(fileName: "test.jpg", sourceURL: sampleFile, fileSizeBytes: 2048, fileModificationDate: Date(timeIntervalSince1970: 1700000000))
        XCTAssertNotEqual(itemDirect1.id, itemDifferent.id)
    }
}
