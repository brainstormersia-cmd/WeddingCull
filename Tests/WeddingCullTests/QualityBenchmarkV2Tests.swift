import XCTest
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

    func testFaceCaptureQualityInFaceInstance() throws {
        let face = FaceInstance(
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
            eyeOpenness: 0.95,
            faceQuality: 0.88,
            faceCaptureQuality: 0.85,
            identityEmbedding: [Float](repeating: 0.1, count: 64)
        )

        XCTAssertEqual(face.faceCaptureQuality, 0.85)
        XCTAssertEqual(face.faceQuality, 0.88)

        // Verify JSON round-trip
        let encoder = JSONEncoder()
        let data = try encoder.encode(face)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FaceInstance.self, from: data)

        XCTAssertEqual(decoded.faceCaptureQuality, 0.85)
    }

    func testBurstRankingWithAndWithoutFaceCaptureQuality() {
        let baseDate = Date(timeIntervalSince1970: 1700000000)

        // Frame A: High detector confidence (0.98) but blurry face / poor capture quality (0.35)
        var metricsA = QualityMetrics()
        metricsA.faceCount = 1
        metricsA.faceQualityScore = 0.98 // Confidence
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
        metricsB.faceQualityScore = 0.93 // Confidence
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

    func testGroundTruthDatasetIntegrity() throws {
        // Find dataset file
        let datasetPath = "docs/datasets/wedding-photo-series-ground-truth.json"
        let datasetURL = URL(fileURLWithPath: datasetPath)
        guard FileManager.default.fileExists(atPath: datasetURL.path) else {
            XCTFail("Ground truth dataset missing at \(datasetPath)")
            return
        }

        let data = try Data(contentsOf: datasetURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["version"] as? String, "1.0")

        let seriesList = json?["series"] as? [[String: Any]]
        XCTAssertNotNil(seriesList)
        XCTAssertGreaterThanOrEqual(seriesList?.count ?? 0, 8, "Expected at least 8 real photo series")

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

            // #1 preferred keeper must never be in unacceptable rejects
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
