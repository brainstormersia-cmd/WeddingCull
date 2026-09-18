import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class SessionAndExportTests: XCTestCase {
    func testSessionSerializationRoundTrip() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("session_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var item = PhotoItem(fileName: "IMG_001.jpg", sourceURL: URL(fileURLWithPath: "/photos/IMG_001.jpg"))
        item.category = .ceremony
        item.selectionState = .userSelected
        item.metrics.overallScore = 0.88

        let session = SessionData(
            sourceFolderPath: "/photos",
            targetSelectionCount: 500,
            photos: [item],
            completedPhases: ["Importazione", "Selezione"]
        )

        let manager = SessionManager()
        try manager.saveSession(session, to: tempFile)

        let loaded = try manager.loadSession(from: tempFile)
        XCTAssertEqual(loaded.sourceFolderPath, "/photos")
        XCTAssertEqual(loaded.targetSelectionCount, 500)
        XCTAssertEqual(loaded.photos.count, 1)
        XCTAssertEqual(loaded.photos[0].category, .ceremony)
        XCTAssertEqual(loaded.photos[0].selectionState, .userSelected)
        XCTAssertEqual(loaded.photos[0].metrics.overallScore, 0.88, accuracy: 0.001)
    }

    func testExportManifests() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDir = tempDir.appendingPathComponent("sources")
        let exportDir = tempDir.appendingPathComponent("exported")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleFile = sourceDir.appendingPathComponent("test.jpg")
        try "FAKE_IMAGE_DATA".data(using: .utf8)?.write(to: sampleFile)

        var item = PhotoItem(fileName: "test.jpg", sourceURL: sampleFile)
        item.selectionState = .selected
        item.category = .cakeAndToast
        item.metrics.overallScore = 0.92

        let exporter = PhotoExporter()
        let result = try exporter.exportSelection(
            items: [item],
            to: exportDir,
            folderStructure: .singleFolder,
            rawHandling: .jpegOnly
        )

        XCTAssertEqual(result.exportedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.manifestJSONURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.manifestCSVURL.path))

        let jsonContent = try String(contentsOf: result.manifestJSONURL)
        XCTAssertTrue(jsonContent.contains("cakeAndToast"))

        let csvContent = try String(contentsOf: result.manifestCSVURL)
        XCTAssertTrue(csvContent.contains("originalPath"))
        XCTAssertTrue(csvContent.contains("cakeAndToast"))
    }

    func testSessionReopenPerformance() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("session_bench_1500_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var items: [PhotoItem] = []
        items.reserveCapacity(1500)
        let categories = WeddingCategory.allCases
        for i in 0..<1500 {
            var item = PhotoItem(fileName: "IMG_\(i).jpg", sourceURL: URL(fileURLWithPath: "/photos/IMG_\(i).jpg"))
            item.category = categories[i % categories.count]
            item.selectionState = (i % 2 == 0) ? .selected : .rejected
            item.metrics.overallScore = 0.5 + Double(i % 50) * 0.01
            items.append(item)
        }

        let readiness = PipelineReadinessMetrics(
            timeToFolderReady: 0.05,
            timeToFirstThumbnail: 0.12,
            timeToInteractiveGrid: 0.45,
            timeToFirstAnalyzedPhoto: 0.48,
            timeToPreliminarySelection: 1.20,
            timeToFinalSelection: 2.10
        )

        let session = SessionData(
            sourceFolderPath: "/photos",
            targetSelectionCount: 700,
            photos: items,
            completedPhases: ["Importazione", "Qualità", "Selezione"],
            pipelineReadinessMetrics: readiness
        )

        let manager = SessionManager()
        try manager.saveSession(session, to: tempFile)

        let tStart = CFAbsoluteTimeGetCurrent()
        let loaded = try manager.loadSession(from: tempFile)
        let tElapsed = CFAbsoluteTimeGetCurrent() - tStart

        XCTAssertEqual(loaded.photos.count, 1500)
        XCTAssertEqual(loaded.pipelineReadinessMetrics?.timeToFirstThumbnail, 0.12)
        XCTAssertEqual(loaded.perceivedSpeedMetrics?.timeToFirstThumbnail, 0.12)
        XCTAssertLessThan(tElapsed, 2.0, "Session reopen for 1,500 photos must complete in < 2.0s (measured: \(tElapsed)s)")
    }
}
