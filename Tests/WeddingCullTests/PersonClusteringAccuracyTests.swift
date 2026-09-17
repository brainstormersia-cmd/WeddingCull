import XCTest
import CoreGraphics
@testable import WeddingCullCore

final class PersonClusteringAccuracyTests: XCTestCase {

    func testSamePersonClustersTogether() {
        let clusterer = PersonClusterer()

        // Create base 64-d vector for Person A
        var baseVecA = [Float](repeating: 0.1, count: 64)
        baseVecA[0] = 0.8
        baseVecA[1] = 0.5
        let normA = sqrt(baseVecA.reduce(0) { $0 + $1 * $1 })
        let normalizedA = baseVecA.map { $0 / normA }

        // Slight perturbation for Person A across 3 photos (e.g. slight movement)
        var perturbedA1 = normalizedA
        perturbedA1[0] += 0.02
        let normA1 = sqrt(perturbedA1.reduce(0) { $0 + $1 * $1 })
        let vecA1 = perturbedA1.map { $0 / normA1 }

        var perturbedA2 = normalizedA
        perturbedA2[1] -= 0.02
        let normA2 = sqrt(perturbedA2.reduce(0) { $0 + $1 * $1 })
        let vecA2 = perturbedA2.map { $0 / normA2 }

        let item1 = PhotoItem(id: "photo_1", fileName: "photo_1.jpg", sourceURL: URL(fileURLWithPath: "/tmp/1.jpg"))
        let item2 = PhotoItem(id: "photo_2", fileName: "photo_2.jpg", sourceURL: URL(fileURLWithPath: "/tmp/2.jpg"))
        let item3 = PhotoItem(id: "photo_3", fileName: "photo_3.jpg", sourceURL: URL(fileURLWithPath: "/tmp/3.jpg"))

        let face1 = FaceInstance(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), eyeOpenness: 0.9, faceQuality: 0.9, identityEmbedding: normalizedA)
        let face2 = FaceInstance(boundingBox: CGRect(x: 0.22, y: 0.21, width: 0.29, height: 0.29), eyeOpenness: 0.85, faceQuality: 0.88, identityEmbedding: vecA1)
        let face3 = FaceInstance(boundingBox: CGRect(x: 0.21, y: 0.19, width: 0.31, height: 0.31), eyeOpenness: 0.92, faceQuality: 0.91, identityEmbedding: vecA2)

        let faceMap = [
            "photo_1": [face1],
            "photo_2": [face2],
            "photo_3": [face3]
        ]

        let clusters = clusterer.clusterPersonsWithIdentities(items: [item1, item2, item3], faceInstances: faceMap)

        // All 3 observations of Person A must group into 1 cluster
        XCTAssertEqual(clusters.count, 1, "Same person across 3 frames must form exactly 1 cluster")
        XCTAssertEqual(clusters.first?.photoIDs.count, 3, "Cluster must contain all 3 photos")
    }

    func testDistinctPersonsStayInSeparateClusters() {
        let clusterer = PersonClusterer()

        // Person A: emphasis on first dimensions
        var vecA = [Float](repeating: 0.01, count: 64)
        vecA[0] = 0.9
        vecA[1] = 0.4
        let normA = sqrt(vecA.reduce(0) { $0 + $1 * $1 })
        let normalizedA = vecA.map { $0 / normA }

        // Person B: emphasis on middle dimensions (distinct face proportions)
        var vecB = [Float](repeating: 0.01, count: 64)
        vecB[30] = 0.9
        vecB[31] = 0.4
        let normB = sqrt(vecB.reduce(0) { $0 + $1 * $1 })
        let normalizedB = vecB.map { $0 / normB }

        // Distance between A and B
        let distanceAB = FaceIdentityRecognizer.cosineDistance(normalizedA, normalizedB)
        XCTAssertGreaterThan(distanceAB, 0.4, "Synthetic distinct people must have significant cosine distance")

        let itemA = PhotoItem(id: "photo_A", fileName: "photo_A.jpg", sourceURL: URL(fileURLWithPath: "/tmp/A.jpg"))
        let itemB = PhotoItem(id: "photo_B", fileName: "photo_B.jpg", sourceURL: URL(fileURLWithPath: "/tmp/B.jpg"))

        let faceA = FaceInstance(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), eyeOpenness: 0.9, faceQuality: 0.9, identityEmbedding: normalizedA)
        let faceB = FaceInstance(boundingBox: CGRect(x: 0.5, y: 0.2, width: 0.3, height: 0.3), eyeOpenness: 0.9, faceQuality: 0.9, identityEmbedding: normalizedB)

        let faceMap = [
            "photo_A": [faceA],
            "photo_B": [faceB]
        ]

        let clusters = clusterer.clusterPersonsWithIdentities(items: [itemA, itemB], faceInstances: faceMap)

        // Must form 2 separate clusters (NO false merge)
        XCTAssertEqual(clusters.count, 2, "Distinct persons must stay in 2 separate clusters")
        let falseMergeCount = clusters.filter { $0.photoIDs.contains("photo_A") && $0.photoIDs.contains("photo_B") }.count
        XCTAssertEqual(falseMergeCount, 0, "False merge rate must be 0%")
    }

    func testMultipleFacesInSinglePhoto() {
        let clusterer = PersonClusterer()

        var vecBride = [Float](repeating: 0.02, count: 64)
        vecBride[2] = 0.95
        let normBride = sqrt(vecBride.reduce(0) { $0 + $1 * $1 })
        let normalizedBride = vecBride.map { $0 / normBride }

        var vecGroom = [Float](repeating: 0.02, count: 64)
        vecGroom[45] = 0.95
        let normGroom = sqrt(vecGroom.reduce(0) { $0 + $1 * $1 })
        let normalizedGroom = vecGroom.map { $0 / normGroom }

        let itemCouple = PhotoItem(id: "couple_1", fileName: "couple_1.jpg", sourceURL: URL(fileURLWithPath: "/tmp/c.jpg"))

        let face1 = FaceInstance(boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3), eyeOpenness: 0.9, faceQuality: 0.9, identityEmbedding: normalizedBride)
        let face2 = FaceInstance(boundingBox: CGRect(x: 0.6, y: 0.2, width: 0.3, height: 0.3), eyeOpenness: 0.9, faceQuality: 0.9, identityEmbedding: normalizedGroom)

        let faceMap = ["couple_1": [face1, face2]]

        let clusters = clusterer.clusterPersonsWithIdentities(items: [itemCouple], faceInstances: faceMap)

        // Couple photo with 2 distinct faces must form 2 person clusters
        XCTAssertEqual(clusters.count, 2)
        XCTAssertTrue(clusters.contains(where: { $0.role == .partnerA }))
        XCTAssertTrue(clusters.contains(where: { $0.role == .partnerB }))
    }

    func testPhotosWithZeroFacesDoNotCrash() {
        let clusterer = PersonClusterer()
        let landscapeItem = PhotoItem(id: "landscape_1", fileName: "landscape.jpg", sourceURL: URL(fileURLWithPath: "/tmp/l.jpg"))

        let clusters = clusterer.clusterPersonsWithIdentities(items: [landscapeItem], faceInstances: [:])
        XCTAssertEqual(clusters.count, 1, "Fallback cluster is returned when no faces exist")
        XCTAssertEqual(clusters.first?.photoIDs, ["landscape_1"])
    }
}
