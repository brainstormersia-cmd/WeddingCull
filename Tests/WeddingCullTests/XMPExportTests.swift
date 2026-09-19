import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class XMPExportTests: XCTestCase {
    var tempDir: URL!
    var exporter: PhotoExporter!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xmp_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        exporter = PhotoExporter()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testEditorialRatingMappingSelected() {
        var item = PhotoItem(fileName: "IMG_0001.JPG", sourceURL: URL(fileURLWithPath: "/dummy/IMG_0001.JPG"))
        item.selectionState = .selected
        item.category = .ceremony
        item.metrics.overallScore = 0.15 // Low AI numeric score intentionally

        let (rating, label, urgency) = exporter.editorialRating(for: item.selectionState)
        XCTAssertEqual(rating, 5)
        XCTAssertEqual(label, "Green")
        XCTAssertEqual(urgency, "1")

        let xmp = exporter.generateXMP(for: item)
        XCTAssertTrue(xmp.contains("xmp:Rating=\"5\""))
        XCTAssertTrue(xmp.contains("xmp:Label=\"Green\""))
        XCTAssertTrue(xmp.contains("photoshop:Urgency=\"1\""))
        XCTAssertFalse(xmp.contains("0.15"), "AI quality scores must never be written into XMP rating or tags")
        XCTAssertTrue(xmp.contains("<rdf:li>Selected</rdf:li>"))
        XCTAssertTrue(xmp.contains("<rdf:li>Ceremony</rdf:li>"))
    }

    func testEditorialRatingMappingAlternative() {
        var item = PhotoItem(fileName: "IMG_0002.JPG", sourceURL: URL(fileURLWithPath: "/dummy/IMG_0002.JPG"))
        item.selectionState = .alternative
        item.category = .couple
        item.metrics.overallScore = 0.85

        let (rating, label, urgency) = exporter.editorialRating(for: item.selectionState)
        XCTAssertEqual(rating, 3)
        XCTAssertEqual(label, "Yellow")
        XCTAssertEqual(urgency, "2")

        let xmp = exporter.generateXMP(for: item)
        XCTAssertTrue(xmp.contains("xmp:Rating=\"3\""))
        XCTAssertTrue(xmp.contains("xmp:Label=\"Yellow\""))
        XCTAssertTrue(xmp.contains("photoshop:Urgency=\"2\""))
        XCTAssertFalse(xmp.contains("0.85"))
        XCTAssertTrue(xmp.contains("<rdf:li>Alternative</rdf:li>"))
    }

    func testEditorialRatingMappingReview() {
        var item = PhotoItem(fileName: "IMG_0002_rev.JPG", sourceURL: URL(fileURLWithPath: "/dummy/IMG_0002_rev.JPG"))
        item.selectionState = .review
        item.category = .couple

        let (rating, label, urgency) = exporter.editorialRating(for: item.selectionState)
        XCTAssertEqual(rating, 4)
        XCTAssertEqual(label, "Blue")
        XCTAssertEqual(urgency, "2")

        let xmp = exporter.generateXMP(for: item)
        XCTAssertTrue(xmp.contains("xmp:Rating=\"4\""))
        XCTAssertTrue(xmp.contains("xmp:Label=\"Blue\""))
        XCTAssertTrue(xmp.contains("photoshop:Urgency=\"2\""))
        XCTAssertTrue(xmp.contains("<rdf:li>Review</rdf:li>"))
    }

    func testEditorialRatingMappingRejected() {
        var item = PhotoItem(fileName: "IMG_0003.JPG", sourceURL: URL(fileURLWithPath: "/dummy/IMG_0003.JPG"))
        item.selectionState = .rejected
        item.category = .reception
        item.metrics.overallScore = 0.99 // High AI numeric score intentionally

        let (rating, label, urgency) = exporter.editorialRating(for: item.selectionState)
        XCTAssertEqual(rating, 1)
        XCTAssertEqual(label, "Red")
        XCTAssertEqual(urgency, "3")

        let xmp = exporter.generateXMP(for: item)
        XCTAssertTrue(xmp.contains("xmp:Rating=\"1\""))
        XCTAssertTrue(xmp.contains("xmp:Label=\"Red\""))
        XCTAssertTrue(xmp.contains("photoshop:Urgency=\"3\""))
        XCTAssertFalse(xmp.contains("0.99"))
        XCTAssertTrue(xmp.contains("<rdf:li>Rejected</rdf:li>"))
    }

    func testUserOverridesEditorialRating() {
        var selectedItem = PhotoItem(fileName: "IMG_0004.JPG", sourceURL: URL(fileURLWithPath: "/dummy/IMG_0004.JPG"))
        selectedItem.selectionState = .userSelected

        let (ratingSel, labelSel, urgencySel) = exporter.editorialRating(for: selectedItem.selectionState)
        XCTAssertEqual(ratingSel, 5)
        XCTAssertEqual(labelSel, "Green")
        XCTAssertEqual(urgencySel, "1")

        var rejectedItem = PhotoItem(fileName: "IMG_0005.JPG", sourceURL: URL(fileURLWithPath: "/dummy/IMG_0005.JPG"))
        rejectedItem.selectionState = .userRejected

        let (ratingRej, labelRej, urgencyRej) = exporter.editorialRating(for: rejectedItem.selectionState)
        XCTAssertEqual(ratingRej, 1)
        XCTAssertEqual(labelRej, "Red")
        XCTAssertEqual(urgencyRej, "3")
    }

    func testXMPXMLStructureAndNamespaces() {
        var item = PhotoItem(fileName: "IMG_0006.JPG", sourceURL: URL(fileURLWithPath: "/dummy/IMG_0006.JPG"))
        item.selectionState = .selected
        item.category = .cakeAndToast
        item.temporalSegmentID = "Reception_Dinner"

        let xmp = exporter.generateXMP(for: item)
        XCTAssertTrue(xmp.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xmp.contains("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"WeddingCull\">"))
        XCTAssertTrue(xmp.contains("<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">"))
        XCTAssertTrue(xmp.contains("xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\""))
        XCTAssertTrue(xmp.contains("xmlns:photoshop=\"http://ns.adobe.com/photoshop/1.0/\""))
        XCTAssertTrue(xmp.contains("xmlns:dc=\"http://purl.org/dc/elements/1.1/\""))
        XCTAssertTrue(xmp.contains("<dc:subject>"))
        XCTAssertTrue(xmp.contains("<rdf:li>Reception_Dinner</rdf:li>"))
        XCTAssertTrue(xmp.hasSuffix("</x:xmpmeta>"))
    }

    func testRawAndJpegPairSingleSidecarExport() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let exportDir = tempDir.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let jpegFile = sourceDir.appendingPathComponent("IMG_0100.JPG")
        let rawFile = sourceDir.appendingPathComponent("IMG_0100.CR3")
        let fakeJpegData = "FAKE_JPEG_DATA_123".data(using: .utf8)!
        let fakeRawData = "FAKE_RAW_DATA_456".data(using: .utf8)!
        try fakeJpegData.write(to: jpegFile)
        try fakeRawData.write(to: rawFile)

        var item = PhotoItem(
            fileName: "IMG_0100.JPG",
            sourceURL: jpegFile,
            rawURL: rawFile,
            jpegURL: jpegFile
        )
        item.selectionState = .selected
        item.category = .ceremony

        let result = try exporter.exportSelection(
            items: [item],
            to: exportDir,
            folderStructure: .singleFolder,
            rawHandling: .rawAndJpegPair,
            exportXMPSidecars: true
        )

        XCTAssertEqual(result.exportedCount, 2, "Should export both RAW and JPEG files")

        // Verify files in export directory
        let exportedFiles = try FileManager.default.contentsOfDirectory(atPath: exportDir.path)
        XCTAssertTrue(exportedFiles.contains("IMG_0100.JPG"))
        XCTAssertTrue(exportedFiles.contains("IMG_0100.CR3"))

        // Exactly ONE .xmp sidecar should be created for this base name
        let xmpFiles = exportedFiles.filter { $0.hasSuffix(".xmp") || $0.hasSuffix(".XMP") }
        XCTAssertEqual(xmpFiles.count, 1, "RAW and JPEG pair must share exactly ONE .xmp sidecar")
        XCTAssertEqual(xmpFiles.first, "IMG_0100.xmp")

        let xmpContent = try String(contentsOf: exportDir.appendingPathComponent("IMG_0100.xmp"))
        XCTAssertTrue(xmpContent.contains("xmp:Rating=\"5\""))
        XCTAssertTrue(xmpContent.contains("xmp:Label=\"Green\""))
    }

    func testInPlaceSidecarExportPreservesOriginalPhotos() throws {
        let sourceDir = tempDir.appendingPathComponent("inplace_test")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let originalPhoto = sourceDir.appendingPathComponent("PHOTO_0001.JPG")
        let originalContent = "IMMUTABLE_ORIGINAL_PHOTO_DATA_BYTES".data(using: .utf8)!
        try originalContent.write(to: originalPhoto)

        var item = PhotoItem(fileName: "PHOTO_0001.JPG", sourceURL: originalPhoto)
        item.selectionState = .selected
        item.category = .details

        let written = try exporter.exportXMPSidecarsInPlace(for: [item])
        XCTAssertEqual(written, 1)

        let sidecarURL = sourceDir.appendingPathComponent("PHOTO_0001.xmp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))

        // Original file must be bit-for-bit unchanged
        let currentPhotoData = try Data(contentsOf: originalPhoto)
        XCTAssertEqual(currentPhotoData, originalContent, "Original photo data must be 100% untouched")
    }

    func testInPlaceSidecarExportSharesSidecarForPair() throws {
        let sourceDir = tempDir.appendingPathComponent("inplace_pair")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let jpegFile = sourceDir.appendingPathComponent("IMG_0500.JPG")
        let rawFile = sourceDir.appendingPathComponent("IMG_0500.CR3")
        try "JPEG".data(using: .utf8)?.write(to: jpegFile)
        try "RAW".data(using: .utf8)?.write(to: rawFile)

        let pairItem = PhotoItem(
            fileName: "IMG_0500.CR3",
            sourceURL: rawFile,
            rawURL: rawFile,
            jpegURL: jpegFile
        )

        let written = try exporter.exportXMPSidecarsInPlace(for: [pairItem])
        XCTAssertEqual(written, 1)

        let files = try FileManager.default.contentsOfDirectory(atPath: sourceDir.path)
        let xmpFiles = files.filter { $0.lowercased().hasSuffix(".xmp") }
        XCTAssertEqual(xmpFiles.count, 1)
        XCTAssertEqual(xmpFiles.first, "IMG_0500.xmp")
    }
}
