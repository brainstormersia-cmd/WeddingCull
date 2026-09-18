import XCTest
import Foundation
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class PhotoTriageAdapterDirectTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testFilenameNormalization() {
        XCTAssertEqual(PhotoTriageAdapter.normalizePhotoFilename("15-1.JPG", seriesId: 15), "000015-01.JPG")
        XCTAssertEqual(PhotoTriageAdapter.normalizePhotoFilename("15-2.jpg", seriesId: 15), "000015-02.JPG")
        XCTAssertEqual(PhotoTriageAdapter.normalizePhotoFilename("1-4.JPG", seriesId: 1), "000001-04.JPG")
        XCTAssertEqual(PhotoTriageAdapter.normalizePhotoFilename("000015-01.JPG", seriesId: 15), "000015-01.JPG")
        XCTAssertEqual(PhotoTriageAdapter.normalizePhotoFilename("4560-3.JPG", seriesId: 4560), "004560-03.JPG")
    }

    func testDirectPrincetonPackageParsing() throws {
        // Setup synthetic Princeton directory layout
        let tvDir = tempDirectory.appendingPathComponent("train_val")
        let imgDir = tvDir.appendingPathComponent("train_val_imgs")
        let revDir = tvDir.appendingPathComponent("reviews_trainval/reviews_trainval")
        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: revDir, withIntermediateDirectories: true)

        // 1. Create pairlist: val_pairlist.txt
        let pairlistURL = tvDir.appendingPathComponent("val_pairlist.txt")
        let pairlistData = """
        15 1 2 0.123 2 1
        15 1 3 0.546 2 3
        15 2 3 0.896 1 3
        """.data(using: .utf8)!
        try pairlistData.write(to: pairlistURL)

        // 2. Create review JSON: 000015.json
        let reviewURL = revDir.appendingPathComponent("000015.json")
        let reviewJSON = """
        {
          "reviews": [
            {
              "compareID1": 0,
              "compareID2": 1,
              "compareFile1": "15-1.JPG",
              "compareFile2": "15-2.JPG",
              "userChoice": "RIGHT",
              "reason": ["", "the window takes away from view"]
            },
            {
              "compareID1": 1,
              "compareID2": 0,
              "compareFile1": "15-2.JPG",
              "compareFile2": "15-1.JPG",
              "userChoice": "LEFT",
              "reason": ["crisp subject", "it blocks the image"]
            },
            {
              "compareID1": 0,
              "compareID2": 2,
              "compareFile1": "15-1.JPG",
              "compareFile2": "15-3.JPG",
              "userChoice": "LEFT",
              "reason": ["good light", "blurry"]
            }
          ]
        }
        """.data(using: .utf8)!
        try reviewJSON.write(to: reviewURL)

        // 3. Create dummy image files
        for p in ["000015-01.JPG", "000015-02.JPG", "000015-03.JPG"] {
            let pURL = imgDir.appendingPathComponent(p)
            try "dummy_jpeg".data(using: .utf8)!.write(to: pURL)
        }

        let adapter = PhotoTriageAdapter()
        let inspection = adapter.inspect(rootURL: tempDirectory)
        XCTAssertTrue(inspection.isAvailable, "Package layout must be recognized")

        let dataset = try adapter.loadDataset(from: tempDirectory)
        XCTAssertEqual(dataset.total_series, 1)
        XCTAssertEqual(dataset.series.count, 1)

        let s15 = dataset.series[0]
        XCTAssertEqual(s15.series_id, "15")
        XCTAssertEqual(s15.frames.count, 3)
        XCTAssertEqual(s15.ground_truth.preferred_order, ["000015-02.JPG", "000015-01.JPG", "000015-03.JPG"])

        let pairs = s15.ground_truth.pairwise_comparisons ?? []
        XCTAssertEqual(pairs.count, 3)

        // Pair 1 vs 2: 2 votes for 2 (RIGHT in rev 1, LEFT in rev 2)
        let pair12 = pairs.first { $0.photo_a == "000015-01.JPG" && $0.photo_b == "000015-02.JPG" }
        XCTAssertNotNil(pair12)
        XCTAssertTrue(pair12?.has_raw_votes ?? false)
        XCTAssertEqual(pair12?.votes_a, 0)
        XCTAssertEqual(pair12?.votes_b, 2)
        XCTAssertEqual(pair12?.majorityWinner, "000015-02.JPG")
        XCTAssertEqual(pair12?.annotatorAgreement, 1.0)
        XCTAssertFalse(pair12?.isAmbiguous ?? true)

        // Pair 1 vs 3: 1 vote for 1 (LEFT in rev 3)
        let pair13 = pairs.first { $0.photo_a == "000015-01.JPG" && $0.photo_b == "000015-03.JPG" }
        XCTAssertNotNil(pair13)
        XCTAssertTrue(pair13?.has_raw_votes ?? false)
        XCTAssertEqual(pair13?.votes_a, 1)
        XCTAssertEqual(pair13?.votes_b, 0)
        XCTAssertEqual(pair13?.majorityWinner, "000015-01.JPG")

        // Pair 2 vs 3: No reviews present in review JSON -> has_raw_votes must be false, votes nil, derived order preserved
        let pair23 = pairs.first { $0.photo_a == "000015-02.JPG" && $0.photo_b == "000015-03.JPG" }
        XCTAssertNotNil(pair23)
        XCTAssertFalse(pair23?.has_raw_votes ?? true)
        XCTAssertNil(pair23?.votes_a)
        XCTAssertNil(pair23?.votes_b)
        XCTAssertEqual(pair23?.derived_order_preference, "000015-02.JPG")
        XCTAssertEqual(pair23?.majorityWinner, "000015-02.JPG")
    }
}
