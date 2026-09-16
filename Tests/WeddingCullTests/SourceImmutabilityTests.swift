import XCTest
import CryptoKit
@testable import WeddingCull

final class SourceImmutabilityTests: XCTestCase {
    private func computeSHA256(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    func testSourceFilesRemainByteIdentical() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("immutability_\(UUID().uuidString)")
        let sourceDir = tempDir.appendingPathComponent("source")
        let exportDir = tempDir.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Generate synthetic mini wedding
        let generator = SyntheticWeddingGenerator()
        let config = SyntheticWeddingGenerator.GeneratorConfig(
            generateLargeImages: false,
            totalTargetCount: 15
        )
        let generatedFiles = try generator.generateDataset(at: sourceDir, config: config)

        // 1. Compute baseline SHA256 hashes of all source files
        var initialHashes: [String: String] = [:]
        for file in generatedFiles {
            initialHashes[file.path] = try computeSHA256(for: file)
        }

        // 2. Run analysis pipeline and export
        let pipeline = AnalysisPipeline()
        let session = try await pipeline.runAnalysis(sourceFolder: sourceDir, targetCount: 10)

        let exporter = PhotoExporter()
        _ = try exporter.exportSelection(
            items: session.photos,
            to: exportDir,
            folderStructure: .singleFolder,
            rawHandling: .rawAndJpegPair
        )

        // 3. Verify every source file remains byte-for-byte identical
        for file in generatedFiles {
            let currentHash = try computeSHA256(for: file)
            let initialHash = initialHashes[file.path]
            XCTAssertEqual(currentHash, initialHash, "SOURCE FILE WAS MODIFIED! Immutability violation on: \(file.lastPathComponent)")
        }
    }
}
