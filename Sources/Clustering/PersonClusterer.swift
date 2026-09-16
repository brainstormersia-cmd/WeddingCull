import Foundation

public final class PersonClusterer: Sendable {
    public init() {}

    /// Best-effort person clustering based on face occurrences, co-occurrences, and wedding segment patterns
    public func clusterPersons(items: [PhotoItem], faceCounts: [String: Int]) -> [PersonCluster] {
        // Group photos that contain faces
        let photosWithFaces = items.filter { (faceCounts[$0.id] ?? $0.metrics.faceCount) > 0 }
        guard !photosWithFaces.isEmpty else { return [] }

        // Find photos with exactly 1 or 2 faces (prominent portrait / couple photos)
        var soloPhotos: [PhotoItem] = []
        var couplePhotos: [PhotoItem] = []
        var groupPhotos: [PhotoItem] = []

        for item in photosWithFaces {
            let count = faceCounts[item.id] ?? item.metrics.faceCount
            if count == 1 {
                soloPhotos.append(item)
            } else if count == 2 {
                couplePhotos.append(item)
            } else {
                groupPhotos.append(item)
            }
        }

        // Primary A & B appear heavily in couple photos and solo portraits during prep/ceremony
        var clusterA = PersonCluster(
            id: "person_1",
            name: "Primary Person A",
            role: .partnerA,
            photoIDs: [],
            isSuggestedPrimary: true,
            confidence: 0.85
        )

        var clusterB = PersonCluster(
            id: "person_2",
            name: "Primary Person B",
            role: .partnerB,
            photoIDs: [],
            isSuggestedPrimary: true,
            confidence: 0.85
        )

        var guestCluster = PersonCluster(
            id: "person_guests",
            name: "Family & Guests",
            role: .guest,
            photoIDs: [],
            isSuggestedPrimary: false,
            confidence: 0.70
        )

        for item in couplePhotos {
            clusterA.photoIDs.append(item.id)
            clusterB.photoIDs.append(item.id)
        }

        for item in soloPhotos {
            if item.category == .bride || item.category == .bridePrep {
                clusterA.photoIDs.append(item.id)
            } else if item.category == .groom || item.category == .groomPrep {
                clusterB.photoIDs.append(item.id)
            } else {
                if clusterA.photoIDs.count <= clusterB.photoIDs.count {
                    clusterA.photoIDs.append(item.id)
                } else {
                    clusterB.photoIDs.append(item.id)
                }
            }
        }

        for item in groupPhotos {
            guestCluster.photoIDs.append(item.id)
            if item.category == .ceremony || item.category == .cakeAndToast {
                clusterA.photoIDs.append(item.id)
                clusterB.photoIDs.append(item.id)
            }
        }

        var clusters = [clusterA, clusterB]
        if !guestCluster.photoIDs.isEmpty {
            clusters.append(guestCluster)
        }

        return clusters
    }
}
