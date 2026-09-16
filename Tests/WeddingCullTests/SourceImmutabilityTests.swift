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

        let generator = SyntheticWeddingGenerator()
        let config = SyntheticWeddingGenerator.GeneratorConfig(
            generateLargeImages: false,
            totalTargetCount: 15
        )
        let generatedFiles = try generator.generateDataset(at: sourceDir, config: config)

        var initialHashes: [String: String] = [:]
        for file in generatedFiles {
            initialHashes[file.path] = try computeSHA256(for: file)
        }

        let pipeline = AnalysisPipeline()
        let session = try await pipeline.runAnalysis(sourceFolder: sourceDir, targetCount: 10)

        let exporter = PhotoExporter()
        _ = try exporter.exportSelection(
            items: session.photos,
            to: exportDir,
            folderStructure: .singleFolder,
            rawHandling: .rawAndJpegPair
        )

        for file in generatedFiles {
            let currentHash = try computeSHA256(for: file)
            let initialHash = initialHashes[file.path]
            XCTAssertEqual(currentHash, initialHash, "SOURCE FILE WAS MODIFIED! Immutability violation on: \(file.lastPathComponent)")
        }
    }
}
