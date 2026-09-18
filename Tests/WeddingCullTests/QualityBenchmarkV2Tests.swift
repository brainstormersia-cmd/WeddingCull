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

    func testPreBurstPreparationChangesOnlyIntendedFields() {
        let scorer = QualityScorer()
        var metrics = QualityMetrics()
        metrics.rawSharpness = 420.0
        metrics.rawFaceSharpness = 380.0
        metrics.meanLuminance = 0.80 // High luminance
        metrics.shadowClipping = 0.05
        metrics.highlightClipping = 0.10
        metrics.faceCount = 1
        metrics.exposureScore = 0.50 // Uninitialized default
        metrics.overallScore = 0.123
        metrics.selectionReason = "test_unscored"
        metrics.sharpnessScore = 0.234
        metrics.technicalScore = 0.345

        let initialItem = PhotoItem(
            id: "test_pre_burst",
            fileName: "test.jpg",
            sourceURL: URL(fileURLWithPath: "/tmp/test.jpg"),
            metrics: metrics
        )

        XCTAssertEqual(initialItem.metrics.overallScore, 0.123)
        XCTAssertEqual(initialItem.metrics.selectionReason, "test_unscored")
        XCTAssertEqual(initialItem.metrics.sharpnessScore, 0.234)
        XCTAssertEqual(initialItem.metrics.technicalScore, 0.345)
        XCTAssertEqual(initialItem.metrics.exposureScore, 0.50)

        let preparedItems = scorer.preparePreBurstMetrics(items: [initialItem])
        XCTAssertEqual(preparedItems.count, 1)
        let prepared = preparedItems[0]

        // Exposure score must be updated to the true calculated exposure score
        let expectedExposure = QualityScorer.computeExposureScore(
            meanLuminance: 0.80,
            shadowClipping: 0.05,
            highlightClipping: 0.10
        )
        XCTAssertEqual(prepared.metrics.exposureScore, expectedExposure, accuracy: 0.0001)
        XCTAssertNotEqual(prepared.metrics.exposureScore, 0.50)

        // ALL other derived scoring fields must remain untouched!
        XCTAssertEqual(prepared.metrics.overallScore, 0.123, "overallScore must NOT be modified by pre-burst preparation")
        XCTAssertEqual(prepared.metrics.selectionReason, "test_unscored", "selectionReason must NOT be modified by pre-burst preparation")
        XCTAssertEqual(prepared.metrics.sharpnessScore, 0.234, "sharpnessScore must NOT be modified by pre-burst preparation")
        XCTAssertEqual(prepared.metrics.technicalScore, 0.345, "technicalScore must NOT be modified by pre-burst preparation")
        XCTAssertEqual(prepared.metrics.rawSharpness, 420.0)
        XCTAssertEqual(prepared.metrics.rawFaceSharpness, 380.0)
    }

    func testPairwiseVoteDistributionAndAmbiguitySchema() throws {
        // Test 1: Decisive majority (8 vs 2)
        let pairA = GroundTruthPairwiseComparison(
            photo_a: "img_001",
            photo_b: "img_002",
            votes_a: 8,
            votes_b: 2,
            reasons: ["sharper focus", "better smile"]
        )
        XCTAssertEqual(pairA.totalVotes, 10)
        XCTAssertEqual(pairA.majorityWinner, "img_001")
        XCTAssertEqual(pairA.preferenceProbabilityA, 0.80, accuracy: 0.001)
        XCTAssertEqual(pairA.annotatorAgreement, 0.80, accuracy: 0.001)
        XCTAssertFalse(pairA.isAmbiguous)
        XCTAssertEqual(pairA.reasons?.count, 2)

        // Test 2: Ambiguous division (6 vs 4)
        let pairB = GroundTruthPairwiseComparison(
            photo_a: "img_003",
            photo_b: "img_004",
            votes_a: 6,
            votes_b: 4
        )
        XCTAssertEqual(pairB.totalVotes, 10)
        XCTAssertEqual(pairB.majorityWinner, "img_003")
        XCTAssertEqual(pairB.annotatorAgreement, 0.60, accuracy: 0.001)
        XCTAssertTrue(pairB.isAmbiguous, "Pair with 60% agreement must be classified as ambiguous (< 70%)")

        // Test 3: Dead tie (5 vs 5)
        let pairC = GroundTruthPairwiseComparison(
            photo_a: "img_005",
            photo_b: "img_006",
            votes_a: 5,
            votes_b: 5
        )
        XCTAssertEqual(pairC.totalVotes, 10)
        XCTAssertNil(pairC.majorityWinner, "Tie must produce nil majority winner")
        XCTAssertEqual(pairC.annotatorAgreement, 0.50, accuracy: 0.001)
        XCTAssertTrue(pairC.isAmbiguous)

        // Test JSON round-trip
        let encoder = JSONEncoder()
        let data = try encoder.encode(pairA)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GroundTruthPairwiseComparison.self, from: data)
        XCTAssertEqual(decoded.photo_a, "img_001")
        XCTAssertEqual(decoded.votes_a, 8)
        XCTAssertEqual(decoded.votes_b, 2)
        XCTAssertEqual(decoded.majorityWinner, "img_001")
        XCTAssertEqual(decoded.annotatorAgreement, 0.80)
    }

    func testPhotoTriageAdapterInspectionAndMissingDataset() throws {
        let adapter = PhotoTriageAdapter()
        let missingURL = URL(fileURLWithPath: "/tmp/nonexistent_photo_triage_root_\(UUID().uuidString)")
        let inspection = adapter.inspect(rootURL: missingURL)

        XCTAssertFalse(inspection.isAvailable)
        XCTAssertTrue(inspection.statusMessage.contains("not found"))

        // Verify that loading missing root throws awaitingExternalDataset error
        XCTAssertThrowsError(try adapter.loadDataset(from: missingURL)) { error in
            guard let adapterErr = error as? PhotoTriageAdapter.AdapterError else {
                XCTFail("Expected PhotoTriageAdapter.AdapterError, got \(error)")
                return
            }
            if case .awaitingExternalDataset = adapterErr {
                // Expected
            } else {
                XCTFail("Expected .awaitingExternalDataset, got \(adapterErr)")
            }
        }

        // Test canonical manifest parsing
        let sampleJSON = """
        {
          "version": "2.0",
          "dataset_name": "PhotoTriage Synthetic Canonical Test",
          "total_series": 1,
          "total_frames": 2,
          "series": [
            {
              "series_id": "pt_series_01",
              "scene_type": "burst",
              "frames": [
                { "photo_id": "p1", "image_path": "images/p1.jpg" },
                { "photo_id": "p2", "image_path": "images/p2.jpg" }
              ],
              "ground_truth": {
                "pairwise_comparisons": [
                  { "photo_a": "p1", "photo_b": "p2", "votes_a": 9, "votes_b": 1 }
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let rootURL = URL(fileURLWithPath: "/datasets/phototriage")
        let parsed = try adapter.parseCanonicalManifest(data: sampleJSON, rootURL: rootURL)

        XCTAssertEqual(parsed.total_series, 1)
        XCTAssertEqual(parsed.series.count, 1)
        XCTAssertEqual(parsed.series[0].frames.count, 2)
        XCTAssertEqual(parsed.series[0].ground_truth.pairwise_comparisons?.count, 1)
        XCTAssertEqual(parsed.series[0].ground_truth.pairwise_comparisons?[0].majorityWinner, "p1")
        XCTAssertEqual(parsed.series[0].ground_truth.pairwise_comparisons?[0].annotatorAgreement, 0.90)
    }

    func testProductionPreviewDownsampleStatic() {
        let width = 400
        let height = 300
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        ctx.setFillColor(gray: 0.5, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!

        let downsampled = PreviewPipeline.downsample(cgImage: img, maxPixelSize: 100)
        XCTAssertNotNil(downsampled)
        XCTAssertEqual(max(downsampled!.width, downsampled!.height), 100)
    }
}

