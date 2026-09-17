import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class FailureModeTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("fail_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testCorruptFileImportDoesNotCrashPipeline() async throws {
        let corruptFile = tempDirectory.appendingPathComponent("CORRUPT_001.JPG")
        let badData = "NOT_A_VALID_JPEG_HEADER_RANDOM_BYTES_123456789".data(using: .utf8)!
        try badData.write(to: corruptFile)

        let pipeline = AnalysisPipeline()
        let session = try await pipeline.runAnalysis(sourceFolder: tempDirectory, targetCount: 5)

        XCTAssertEqual(session.photos.count, 1)
        let photo = session.photos[0]
        XCTAssertTrue(photo.metadata.isCorrupt)
        XCTAssertEqual(photo.selectionState, .rejected)
        XCTAssertEqual(photo.metrics.overallScore, 0.0)
    }

    func testEmptyFolderAnalysisReturnsCleanEmptySession() async throws {
        let pipeline = AnalysisPipeline()
        let session = try await pipeline.runAnalysis(sourceFolder: tempDirectory, targetCount: 10)

        XCTAssertEqual(session.photos.count, 0)
        XCTAssertEqual(session.burstGroups.count, 0)
        XCTAssertEqual(session.segments.count, 0)
    }

    func testFewerPhotosThanTargetSelectsAllEligibleWithoutLooping() async throws {
        // Create 4 simple images with different patterns to avoid duplicate detection
        for i in 1...4 {
            let fileURL = tempDirectory.appendingPathComponent("PHOTO_\(i).JPG")
            try createSimpleValidJPEG(at: fileURL, index: i)
        }

        let pipeline = AnalysisPipeline()
        let session = try await pipeline.runAnalysis(sourceFolder: tempDirectory, targetCount: 25)

        let selected = session.photos.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 4, "Should select all 4 available usable photos when target is 25")
    }

    func testDuplicateOnlyFolderSelectsOnlyOne() async throws {
        let originalURL = tempDirectory.appendingPathComponent("ORIGINAL.JPG")
        try createSimpleValidJPEG(at: originalURL)

        for i in 1...5 {
            let dupURL = tempDirectory.appendingPathComponent("DUP_\(i).JPG")
            try FileManager.default.copyItem(at: originalURL, to: dupURL)
        }

        let pipeline = AnalysisPipeline()
        let session = try await pipeline.runAnalysis(sourceFolder: tempDirectory, targetCount: 10)

        XCTAssertEqual(session.photos.count, 6)
        let selected = session.photos.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 1, "Exactly one copy of the duplicate group should be selected")

        let duplicates = session.photos.filter { $0.isDuplicate }
        XCTAssertEqual(duplicates.count, 5)
    }

    func testRawAndJpegPairFormsSingleLogicalPhoto() async throws {
        let baseName = "PAIR_001"
        let jpegURL = tempDirectory.appendingPathComponent("\(baseName).JPG")
        let rawURL = tempDirectory.appendingPathComponent("\(baseName).CR2")

        try createSimpleValidJPEG(at: jpegURL)
        try createSimpleValidJPEG(at: rawURL) // Mock raw container

        let pipeline = AnalysisPipeline()
        let session = try await pipeline.runAnalysis(sourceFolder: tempDirectory, targetCount: 5)

        XCTAssertEqual(session.photos.count, 1, "RAW+JPEG pair must be imported as a single logical photo")
        let item = session.photos[0]
        XCTAssertTrue(item.hasRawJpegPair)
        XCTAssertNotNil(item.rawURL)
        XCTAssertNotNil(item.jpegURL)
    }

    private func createSimpleValidJPEG(at url: URL, index: Int = 0) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let r = CGFloat((index * 60 + 50) % 255) / 255.0
        let g = CGFloat((index * 90 + 30) % 255) / 255.0
        let b = CGFloat((index * 130 + 70) % 255) / 255.0
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        if index > 0 {
            ctx.setFillColor(red: 1.0 - r, green: 1.0 - g, blue: 1.0 - b, alpha: 1.0)
            ctx.fill(CGRect(x: index * 15, y: index * 15, width: 25, height: 25))
        }

        guard let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return
        }

        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
