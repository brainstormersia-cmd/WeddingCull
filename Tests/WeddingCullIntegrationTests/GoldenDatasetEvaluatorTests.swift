import XCTest
@testable import WeddingCull

public struct GoldenSelectionManifest: Codable {
    public let shootID: String
    public let selectedPhotoNames: [String]
    public let categories: [String: String]? // filename -> category
}

public struct GoldenEvaluationResult {
    public let precision: Double
    public let recall: Double
    public let f1Score: Double
    public let overlapCount: Int
    public let totalAlgorithmicSelected: Int
    public let totalHumanSelected: Int
}

public final class GoldenDatasetEvaluator {
    public static func evaluate(algorithmicSelections: [PhotoItem], goldenManifest: GoldenSelectionManifest) -> GoldenEvaluationResult {
        let algoSelectedNames = Set(algorithmicSelections.filter { $0.selectionState.isIncludedInFinal }.map { $0.fileName })
        let humanSelectedNames = Set(goldenManifest.selectedPhotoNames)

        let overlap = algoSelectedNames.intersection(humanSelectedNames).count
        let precision = algoSelectedNames.isEmpty ? 0.0 : Double(overlap) / Double(algoSelectedNames.count)
        let recall = humanSelectedNames.isEmpty ? 0.0 : Double(overlap) / Double(humanSelectedNames.count)
        let f1 = (precision + recall) > 0 ? (2.0 * precision * recall) / (precision + recall) : 0.0

        return GoldenEvaluationResult(
            precision: precision,
            recall: recall,
            f1Score: f1,
            overlapCount: overlap,
            totalAlgorithmicSelected: algoSelectedNames.count,
            totalHumanSelected: humanSelectedNames.count
        )
    }
}

final class GoldenDatasetEvaluatorTests: XCTestCase {
    func testGoldenDatasetEvaluationCalculation() {
        let manifest = GoldenSelectionManifest(
            shootID: "wedding_01",
            selectedPhotoNames: ["IMG_0001.jpg", "IMG_0002.jpg", "IMG_0003.jpg", "IMG_0004.jpg"],
            categories: nil
        )

        var item1 = PhotoItem(fileName: "IMG_0001.jpg", sourceURL: URL(fileURLWithPath: "/tmp/1.jpg"))
        item1.selectionState = .selected

        var item2 = PhotoItem(fileName: "IMG_0002.jpg", sourceURL: URL(fileURLWithPath: "/tmp/2.jpg"))
        item2.selectionState = .selected

        var item5 = PhotoItem(fileName: "IMG_0005.jpg", sourceURL: URL(fileURLWithPath: "/tmp/5.jpg"))
        item5.selectionState = .selected

        var item6 = PhotoItem(fileName: "IMG_0006.jpg", sourceURL: URL(fileURLWithPath: "/tmp/6.jpg"))
        item6.selectionState = .rejected

        let eval = GoldenDatasetEvaluator.evaluate(
            algorithmicSelections: [item1, item2, item5, item6],
            goldenManifest: manifest
        )

        // Algo selected: 1, 2, 5 (total 3)
        // Human selected: 1, 2, 3, 4 (total 4)
        // Overlap: 1, 2 (count 2)
        XCTAssertEqual(eval.overlapCount, 2)
        XCTAssertEqual(eval.totalAlgorithmicSelected, 3)
        XCTAssertEqual(eval.totalHumanSelected, 4)
        XCTAssertEqual(eval.precision, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(eval.recall, 2.0 / 4.0, accuracy: 0.001)
    }
}
