import XCTest
import CryptoKit
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif
#if canImport(TestDatasetGeneratorLibrary)
import TestDatasetGeneratorLibrary
#endif

final class HeadlessPipelineIntegrationTests: XCTestCase {
    private func computeSHA256(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    func testEndToEndHeadlessPipeline() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("e2e_\(UUID().uuidString)")
        let sourceDir = tempDir.appendingPathComponent("source_wedding")
        let exportDir = tempDir.appendingPathComponent("exported_wedding")
        let sessionFile = tempDir.appendingPathComponent("session.weddingcull")

        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Step 1: Generate synthetic wedding photos
        let generator = SyntheticWeddingGenerator()
        let files = try generator.generateDataset(at: sourceDir)
        XCTAssertGreaterThan(files.count, 50, "Should generate sufficient synthetic photos")

        // Step 2: Compute initial hashes for source immutability verification
        var initialHashes: [String: String] = [:]
        for file in files {
            initialHashes[file.path] = try computeSHA256(for: file)
        }

        // Step 3: Run complete analysis pipeline
        let pipeline = AnalysisPipeline()
        let targetCount = 30
        let session = try await pipeline.runAnalysis(sourceFolder: sourceDir, targetCount: targetCount)

        // Assertions on analysis results
        XCTAssertGreaterThan(session.photos.count, 0)
        XCTAssertFalse(session.burstGroups.isEmpty, "Burst groups must be detected")
        XCTAssertFalse(session.segments.isEmpty, "Temporal segments must be detected")
        XCTAssertFalse(session.personClusters.isEmpty, "Person clusters must be detected via face recognition")

        // Step 4: Verify duplicate detection & corrupt handling
        let corruptItem = session.photos.first(where: { $0.fileName == "CORRUPT_IMAGE.jpg" })
        XCTAssertNotNil(corruptItem, "Corrupt file must be imported")
        XCTAssertTrue(corruptItem?.metadata.isCorrupt == true, "Corrupt file must be flagged")
        XCTAssertEqual(corruptItem?.selectionState, .rejected, "Corrupt file must be rejected")

        let dupItem = session.photos.first(where: { $0.fileName == "IMG_EXACT_DUP.jpg" })
        XCTAssertNotNil(dupItem, "Duplicate file must be imported")
        XCTAssertTrue(dupItem?.isDuplicate == true, "Duplicate file must be flagged")

        // Step 5: Verify target count proposed
        let selectedPhotos = session.photos.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selectedPhotos.count, targetCount, "Must select exactly the requested target count")

        // Step 6: Export selection
        let exporter = PhotoExporter()
        let exportResult = try exporter.exportSelection(
            items: session.photos,
            to: exportDir,
            folderStructure: .byCategory,
            rawHandling: .rawAndJpegPair
        )

        XCTAssertGreaterThan(exportResult.exportedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportResult.manifestJSONURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportResult.manifestCSVURL.path))

        // Step 7: Save & Reload session
        let sessionManager = SessionManager()
        try sessionManager.saveSession(session, to: sessionFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFile.path))

        let reloadedSession = try sessionManager.loadSession(from: sessionFile)
        XCTAssertEqual(reloadedSession.photos.count, session.photos.count)
        XCTAssertEqual(reloadedSession.targetSelectionCount, session.targetSelectionCount)
        XCTAssertEqual(reloadedSession.burstGroups.count, session.burstGroups.count)

        // Step 8: Verify source files were NEVER modified (absolute immutability)
        for file in files {
            let finalHash = try computeSHA256(for: file)
            XCTAssertEqual(finalHash, initialHashes[file.path], "Source immutability violated on \(file.lastPathComponent)")
        }
    }
}
