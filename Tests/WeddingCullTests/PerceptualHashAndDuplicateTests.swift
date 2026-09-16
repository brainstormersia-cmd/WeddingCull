import XCTest
import CoreGraphics
@testable import WeddingCull

final class PerceptualHashAndDuplicateTests: XCTestCase {
    private func createTestCGImage(width: Int, height: Int, color: CGFloat) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var buffer = [UInt8](repeating: UInt8(color * 255), count: width * height)
        let ctx = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return ctx.makeImage()!
    }

    func testPerceptualHashHammingDistance() {
        let hashA: UInt64 = 0b1111000011110000
        let hashB: UInt64 = 0b1111000011110000 // identical
        let hashC: UInt64 = 0b1111000000000000 // 4 bits different

        XCTAssertEqual(PerceptualHash.hammingDistance(hashA, hashB), 0)
        XCTAssertEqual(PerceptualHash.similarity(hashA, hashB), 1.0)

        XCTAssertEqual(PerceptualHash.hammingDistance(hashA, hashC), 4)
        XCTAssertGreaterThan(PerceptualHash.similarity(hashA, hashC), 0.9)
    }

    func testExactDuplicateDetection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = tempDir.appendingPathComponent("PhotoA.jpg")
        let fileB = tempDir.appendingPathComponent("PhotoB_Copy.jpg")
        let fileC = tempDir.appendingPathComponent("PhotoC_Different.jpg")

        let contentA = "DETERMINISTIC_PHOTO_BYTES_IDENTICAL_12345".data(using: .utf8)!
        let contentC = "DETERMINISTIC_PHOTO_BYTES_DIFFERENT_67890".data(using: .utf8)!

        try contentA.write(to: fileA)
        try contentA.write(to: fileB) // Exact duplicate of A
        try contentC.write(to: fileC)

        let itemA = PhotoItem(fileName: "PhotoA.jpg", sourceURL: fileA, fileSizeBytes: Int64(contentA.count))
        let itemB = PhotoItem(fileName: "PhotoB_Copy.jpg", sourceURL: fileB, fileSizeBytes: Int64(contentA.count))
        let itemC = PhotoItem(fileName: "PhotoC_Different.jpg", sourceURL: fileC, fileSizeBytes: Int64(contentC.count))

        let detector = DuplicateAndBurstDetector()
        let duplicates = detector.detectExactDuplicates(items: [itemA, itemB, itemC])

        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates[itemB.id], itemA.id)
        XCTAssertNil(duplicates[itemC.id])
    }
}
