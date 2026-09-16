import XCTest
import CoreGraphics
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class QualityAndSharpnessMetricsTests: XCTestCase {
    private func createSharpImage() -> CGImage {
        let width = 200
        let height = 200
        var buffer = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                if ((x / 10) + (y / 10)) % 2 == 0 {
                    buffer[y * width + x] = 255
                } else {
                    buffer[y * width + x] = 0
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
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

    private func createFlatImage() -> CGImage {
        let width = 200
        let height = 200
        var buffer = [UInt8](repeating: 128, count: width * height)

        let colorSpace = CGColorSpaceCreateDeviceGray()
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

    func testSharpnessCalculation() {
        let analyzer = TechnicalQualityAnalyzer()
        let sharp = createSharpImage()
        let flat = createFlatImage()

        let resSharp = analyzer.analyze(cgImage: sharp)
        let resFlat = analyzer.analyze(cgImage: flat)

        XCTAssertGreaterThan(resSharp.rawSharpness, resFlat.rawSharpness, "Checkerboard image must have higher Laplacian variance than flat gray image")
        XCTAssertEqual(resFlat.rawSharpness, 0.0, accuracy: 0.1, "Flat gray image has near-zero Laplacian variance")
    }

    func testRobustNormalization() {
        let values = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0, 1000.0]
        let normalizer = RobustNormalizer(values: values)

        let normLow = normalizer.normalize(15.0)
        let normHigh = normalizer.normalize(90.0)

        XCTAssertGreaterThan(normHigh, normLow)
        XCTAssertLessThanOrEqual(normHigh, 1.0)
        XCTAssertGreaterThanOrEqual(normLow, 0.0)
    }

    func testQualityScoring() {
        let scorer = QualityScorer()
        var item1 = PhotoItem(fileName: "IMG_001.jpg", sourceURL: URL(fileURLWithPath: "/tmp/1.jpg"))
        item1.metrics.rawSharpness = 500.0
        item1.metrics.meanLuminance = 0.50
        item1.category = .ceremony

        var item2 = PhotoItem(fileName: "IMG_002.jpg", sourceURL: URL(fileURLWithPath: "/tmp/2.jpg"))
        item2.metrics.rawSharpness = 10.0
        item2.metrics.meanLuminance = 0.05
        item2.metrics.isSevereUnderexposed = true

        let scored = scorer.scorePhotos(items: [item1, item2])
        XCTAssertEqual(scored.count, 2)
        XCTAssertGreaterThan(scored[0].metrics.overallScore, scored[1].metrics.overallScore)
        XCTAssertFalse(scored[0].metrics.selectionReason.isEmpty)
    }
}
