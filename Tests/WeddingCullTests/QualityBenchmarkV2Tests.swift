import XCTest
import CoreGraphics
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class QualityBenchmarkV2Tests: XCTestCase {
    func testFaceCaptureQualityFieldsInQualityMetrics() throws {
        var metrics = QualityMetrics()
        XCTAssertNil(metrics.rawFaceCaptureQuality)
        XCTAssertNil(metrics.faceCaptureQualityScore)

        metrics.rawFaceCaptureQuality = 0.875
        metrics.faceCaptureQualityScore = 0.875

        XCTAssertEqual(metrics.rawFaceCaptureQuality, 0.875)
        XCTAssertEqual(metrics.faceCaptureQualityScore, 0.875)

        // Verify JSON round-trip serialization
        let encoder = JSONEncoder()
        let data = try encoder.encode(metrics)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(QualityMetrics.self, from: data)

        XCTAssertEqual(decoded.rawFaceCaptureQuality, 0.875)
        XCTAssertEqual(decoded.faceCaptureQualityScore, 0.875)
    }

    func testFaceInstanceIndependentFields() throws {
        let face = FaceInstance(
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
            eyeOpenness: 0.95,
            detectionConfidence: 0.99,
            faceQuality: 0.99,
            faceCaptureQuality: 0.72,
            faceSharpness: 450.0,
            identityEmbedding: [Float](repeating: 0.1, count: 64)
        )

        // Verification of clean feature separation:
        // detectionConfidence must NOT be overwritten by faceCaptureQuality
        XCTAssertEqual(face.detectionConfidence, 0.99)
        XCTAssertEqual(face.faceQuality, 0.99)
        XCTAssertEqual(face.faceCaptureQuality, 0.72)
        XCTAssertEqual(face.faceSharpness, 450.0)

        // Verify JSON round-trip
        let encoder = JSONEncoder()
        let data = try encoder.encode(face)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FaceInstance.self, from: data)

        XCTAssertEqual(decoded.detectionConfidence, 0.99)
        XCTAssertEqual(decoded.faceQuality, 0.99)
        XCTAssertEqual(decoded.faceCaptureQuality, 0.72)
        XCTAssertEqual(decoded.faceSharpness, 450.0)
    }

    func testBurstRankingWithAndWithoutFaceCaptureQuality() {
        let baseDate = Date(timeIntervalSince1970: 1700000000)

        // Frame A: High detector confidence (0.98) but blurry face / poor capture quality (0.35)
        var metricsA = QualityMetrics()
        metricsA.faceCount = 1
        metricsA.faceQualityScore = 0.98 // Detection confidence
        metricsA.rawFaceCaptureQuality = 0.35
        metricsA.faceCaptureQualityScore = 0.35
        metricsA.faceSharpnessScore = 0.70
        metricsA.rawFaceSharpness = 350.0
        metricsA.averageEyeOpenness = 0.85
        metricsA.exposureScore = 0.85

        let itemA = PhotoItem(
            id: "frame_A_blurry_confident",
            fileName: "frame_A.jpg",
            sourceURL: URL(fileURLWithPath: "/tmp/frame_A.jpg"),
            metadata: PhotoMetadata(captureDate: baseDate),
            metrics: metricsA
        )

        // Frame B: Slightly lower detector confidence (0.93) but excellent authentic face capture quality (0.92)
        var metricsB = QualityMetrics()
        metricsB.faceCount = 1
        metricsB.faceQualityScore = 0.93 // Detection confidence
        metricsB.rawFaceCaptureQuality = 0.92
        metricsB.faceCaptureQualityScore = 0.92
        metricsB.faceSharpnessScore = 0.72
        metricsB.rawFaceSharpness = 360.0
        metricsB.averageEyeOpenness = 0.85
        metricsB.exposureScore = 0.85

        let itemB = PhotoItem(
            id: "frame_B_sharp_high_cq",
            fileName: "frame_B.jpg",
            sourceURL: URL(fileURLWithPath: "/tmp/frame_B.jpg"),
            metadata: PhotoMetadata(captureDate: baseDate.addingTimeInterval(0.25)),
            metrics: metricsB
        )

        // 1. Baseline detector (enableFaceCaptureQuality: false)
        let baselineDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: false)
        let scoreA_baseline = baselineDetector.computeBurstFrameQuality(itemA)
        let scoreB_baseline = baselineDetector.computeBurstFrameQuality(itemB)

        // In baseline, Frame A wins because 0.98 * 0.40 > 0.93 * 0.40
        XCTAssertGreaterThan(scoreA_baseline, scoreB_baseline, "Baseline must favor Frame A due to uncalibrated confidence")
        let burstBaseline = baselineDetector.createBurstGroup(from: [itemA, itemB])
        XCTAssertEqual(burstBaseline.winnerID, "frame_A_blurry_confident")

        // 2. Experimental detector (enableFaceCaptureQuality: true)
        let experimentalDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: true)
        let scoreA_exp = experimentalDetector.computeBurstFrameQuality(itemA)
        let scoreB_exp = experimentalDetector.computeBurstFrameQuality(itemB)

        // In experimental, Frame B wins because authentic capture quality (0.92) strongly beats (0.35)
        XCTAssertGreaterThan(scoreB_exp, scoreA_exp, "Experimental must favor Frame B due to authentic FaceCaptureQuality")
        let burstExp = experimentalDetector.createBurstGroup(from: [itemA, itemB])
        XCTAssertEqual(burstExp.winnerID, "frame_B_sharp_high_cq")
    }

    func testDivergentFaceAndGlobalSharpness() {
        let analyzer = TechnicalQualityAnalyzer()
        let width = 300
        let height = 300
        let faceRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4) // Center 40%

        // Helper to create test bitmap context
        func createContext() -> CGContext {
            let colorSpace = CGColorSpaceCreateDeviceGray()
            return CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )!
        }

        // Test Scenario 1: Shallow Depth-of-Field (Bokeh Portrait)
        // Background is smooth and uniform (gray 128), while face region has sharp high-frequency edges
        let ctxBokeh = createContext()
        ctxBokeh.setFillColor(gray: 0.5, alpha: 1.0)
        ctxBokeh.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw sharp high-frequency checkerboard in face region
        let facePixelX = Int(faceRect.origin.x * Double(width))
        let facePixelY = Int((1.0 - faceRect.origin.y - faceRect.size.height) * Double(height))
        let facePixelW = Int(faceRect.size.width * Double(width))
        let facePixelH = Int(faceRect.size.height * Double(height))

        for y in stride(from: facePixelY, to: facePixelY + facePixelH, by: 4) {
            for x in stride(from: facePixelX, to: facePixelX + facePixelW, by: 4) {
                if ((x / 4) + (y / 4)) % 2 == 0 {
                    ctxBokeh.setFillColor(gray: 0.0, alpha: 1.0)
                } else {
                    ctxBokeh.setFillColor(gray: 1.0, alpha: 1.0)
                }
                ctxBokeh.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        let bokehImage = ctxBokeh.makeImage()!

        let globalSharpBokeh = analyzer.analyze(cgImage: bokehImage).rawSharpness
        let faceSharpBokeh = analyzer.computeRegionSharpness(cgImage: bokehImage, normalizedRect: faceRect)

        // In a bokeh portrait, the face region sharpness MUST be significantly higher than the global sharpness
        XCTAssertGreaterThan(faceSharpBokeh, globalSharpBokeh * 2.0, "Face sharpness must exceed global sharpness in shallow DoF scenes")
        XCTAssertNotEqual(faceSharpBokeh, globalSharpBokeh * 1.2, accuracy: 1.0, "Face sharpness must not be locked to globalSharpness * 1.2")

        // Test Scenario 2: Missed Focus (Sharp Cluttered Background, Blurry/Smooth Face)
        let ctxMissed = createContext()
        // Fill entire background with high-frequency checkerboard
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                if ((x / 4) + (y / 4)) % 2 == 0 {
                    ctxMissed.setFillColor(gray: 0.0, alpha: 1.0)
                } else {
                    ctxMissed.setFillColor(gray: 1.0, alpha: 1.0)
                }
                ctxMissed.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        // Smooth blurred face region
        ctxMissed.setFillColor(gray: 0.5, alpha: 1.0)
        ctxMissed.fill(CGRect(x: facePixelX, y: facePixelY, width: facePixelW, height: facePixelH))
        let missedFocusImage = ctxMissed.makeImage()!

        let globalSharpMissed = analyzer.analyze(cgImage: missedFocusImage).rawSharpness
        let faceSharpMissed = analyzer.computeRegionSharpness(cgImage: missedFocusImage, normalizedRect: faceRect)

        // In missed focus, face sharpness MUST be significantly lower than the cluttered background sharpness
        XCTAssertLessThan(faceSharpMissed, globalSharpMissed * 0.5, "Face sharpness must be far lower than global background sharpness when focus is missed")
        XCTAssertNotEqual(faceSharpMissed, globalSharpMissed * 1.2, accuracy: 1.0, "Face sharpness must not be locked to globalSharpness * 1.2")
    }

    func testSyntheticFixtureIntegrity() throws {
        let fixturePath = "docs/datasets/synthetic-ranking-fixture.json"
        let fixtureURL = URL(fileURLWithPath: fixturePath)
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            XCTFail("Synthetic fixture missing at \(fixturePath)")
            return
        }

        let data = try Data(contentsOf: fixtureURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["fixture_type"] as? String, "SYNTHETIC_UNIT_TEST_FIXTURE")

        let seriesList = json?["series"] as? [[String: Any]]
        XCTAssertNotNil(seriesList)
        XCTAssertEqual(seriesList?.count, 8)

        for series in seriesList ?? [] {
            let seriesId = series["series_id"] as? String ?? ""
            XCTAssertFalse(seriesId.isEmpty)

            let gt = series["ground_truth"] as? [String: Any]
            XCTAssertNotNil(gt)

            let preferredOrder = gt?["preferred_order"] as? [String] ?? []
            let unacceptableRejects = gt?["unacceptable_rejects"] as? [String] ?? []
            let acceptableKeepers = gt?["acceptable_keepers"] as? [String] ?? []

            XCTAssertFalse(preferredOrder.isEmpty, "Series \(seriesId) missing preferred order")
            XCTAssertFalse(acceptableKeepers.isEmpty, "Series \(seriesId) missing acceptable keepers")

            if let first = preferredOrder.first {
                XCTAssertFalse(unacceptableRejects.contains(first), "Winner \(first) cannot be an unacceptable reject in \(seriesId)")
            }

            let frames = series["frames"] as? [[String: Any]] ?? []
            let frameIds = Set(frames.compactMap { $0["photo_id"] as? String })
            for prefId in preferredOrder {
                XCTAssertTrue(frameIds.contains(prefId), "Preferred frame \(prefId) not in frame definitions for \(seriesId)")
            }
        }
    }
}
