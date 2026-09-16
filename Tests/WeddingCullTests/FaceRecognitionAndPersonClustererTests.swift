import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class FaceRecognitionAndPersonClustererTests: XCTestCase {
    func testCosineDistanceCalculation() {
        let vecA: [Float] = [1.0, 0.0, 0.0]
        let vecB: [Float] = [1.0, 0.0, 0.0]
        let vecC: [Float] = [0.0, 1.0, 0.0]

        // Identical vectors -> distance 0.0
        let distIdentical = FaceIdentityRecognizer.cosineDistance(vecA, vecB)
        XCTAssertLessThan(distIdentical, 0.001)

        // Orthogonal vectors -> distance 1.0
        let distOrthogonal = FaceIdentityRecognizer.cosineDistance(vecA, vecC)
        XCTAssertEqual(distOrthogonal, 1.0, accuracy: 0.01)
    }

    func testPersonClustererWithIdentityEmbeddings() {
        let clusterer = PersonClusterer()

        // Create 2 distinct person identities
        let personAEmbedding: [Float] = [0.9, 0.1, 0.0, 0.0]
        let personBEmbedding: [Float] = [0.0, 0.0, 0.9, 0.1]
        let guestEmbedding: [Float]   = [0.1, 0.9, 0.0, 0.0]

        var items: [PhotoItem] = []
        var faceInstances: [String: [FaceInstance]] = [:]

        // 5 solo photos of Person A
        for i in 0..<5 {
            let id = "photo_A_\(i)"
            var item = PhotoItem(id: id, fileName: "\(id).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(id).jpg"), category: .bride)
            item.metrics.faceCount = 1
            items.append(item)
            faceInstances[id] = [FaceInstance(boundingBox: .zero, eyeOpenness: 0.9, faceQuality: 0.95, identityEmbedding: personAEmbedding)]
        }

        // 4 solo photos of Person B
        for i in 0..<4 {
            let id = "photo_B_\(i)"
            var item = PhotoItem(id: id, fileName: "\(id).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(id).jpg"), category: .groom)
            item.metrics.faceCount = 1
            items.append(item)
            faceInstances[id] = [FaceInstance(boundingBox: .zero, eyeOpenness: 0.85, faceQuality: 0.90, identityEmbedding: personBEmbedding)]
        }

        // 3 couple photos of Person A & B
        for i in 0..<3 {
            let id = "photo_couple_\(i)"
            var item = PhotoItem(id: id, fileName: "\(id).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(id).jpg"), category: .couple)
            item.metrics.faceCount = 2
            items.append(item)
            faceInstances[id] = [
                FaceInstance(boundingBox: .zero, eyeOpenness: 0.9, faceQuality: 0.95, identityEmbedding: personAEmbedding),
                FaceInstance(boundingBox: .zero, eyeOpenness: 0.85, faceQuality: 0.90, identityEmbedding: personBEmbedding)
            ]
        }

        // 2 guest photos
        for i in 0..<2 {
            let id = "photo_guest_\(i)"
            var item = PhotoItem(id: id, fileName: "\(id).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(id).jpg"), category: .guestsCandid)
            item.metrics.faceCount = 1
            items.append(item)
            faceInstances[id] = [FaceInstance(boundingBox: .zero, eyeOpenness: 0.8, faceQuality: 0.8, identityEmbedding: guestEmbedding)]
        }

        let clusters = clusterer.clusterPersonsWithIdentities(items: items, faceInstances: faceInstances)

        XCTAssertGreaterThanOrEqual(clusters.count, 2)

        // Verify Primary Person A is identified
        let primaryA = clusters.first(where: { $0.role == .partnerA })
        XCTAssertNotNil(primaryA)
        XCTAssertTrue(primaryA!.isSuggestedPrimary)
        XCTAssertGreaterThanOrEqual(primaryA!.confidence, 0.70)
        // Person A appears in 5 solo + 3 couple = 8 photos
        XCTAssertEqual(primaryA!.photoIDs.count, 8)

        // Verify Primary Person B is identified
        let primaryB = clusters.first(where: { $0.role == .partnerB })
        XCTAssertNotNil(primaryB)
        XCTAssertTrue(primaryB!.isSuggestedPrimary)
        XCTAssertGreaterThanOrEqual(primaryB!.confidence, 0.70)
        // Person B appears in 4 solo + 3 couple = 7 photos
        XCTAssertEqual(primaryB!.photoIDs.count, 7)
    }

    func testFaceIdentityExtractionFromImage() {
        let recognizer = FaceIdentityRecognizer()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 800,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let testImage = ctx.makeImage()!

        let faces = recognizer.extractFacesWithIdentity(from: testImage)
        XCTAssertNotNil(faces)
    }
}
