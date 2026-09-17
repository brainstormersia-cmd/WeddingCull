import Foundation

public final class PersonClusterer: Sendable {
    public init() {}

    private struct InternalCluster {
        var id: String
        var centroid: [Float]
        var photoIDs: Set<String>
        var soloCount: Int = 0
        var coupleCount: Int = 0
        var totalFaces: Int = 0
        var distancesToCentroid: [Float] = []
    }

    /// Clusters wedding subjects based on facial biometric descriptors (geometric landmark proportions or learned embeddings).
    /// Uses conservative cosine distance threshold (0.28) to prevent false identity merges.
    public func clusterPersonsWithIdentities(
        items: [PhotoItem],
        faceInstances: [String: [FaceInstance]]
    ) -> [PersonCluster] {
        var clusters: [InternalCluster] = []
        let matchThreshold: Float = 0.28 // Conservative cosine distance threshold to prevent false merges

        // 1. Process all photos chronologically
        for item in items {
            guard let faces = faceInstances[item.id], !faces.isEmpty else { continue }
            let isSolo = faces.count == 1
            let isCouple = faces.count == 2

            for face in faces {
                guard !face.identityEmbedding.isEmpty else { continue }

                var bestClusterIndex: Int? = nil
                var bestDistance: Float = Float.greatestFiniteMagnitude

                for (idx, cluster) in clusters.enumerated() {
                    let dist = FaceIdentityRecognizer.cosineDistance(face.identityEmbedding, cluster.centroid)
                    if dist < matchThreshold && dist < bestDistance {
                        bestDistance = dist
                        bestClusterIndex = idx
                    }
                }

                if let idx = bestClusterIndex {
                    // Update existing cluster
                    clusters[idx].photoIDs.insert(item.id)
                    clusters[idx].totalFaces += 1
                    clusters[idx].distancesToCentroid.append(bestDistance)
                    if isSolo { clusters[idx].soloCount += 1 }
                    if isCouple { clusters[idx].coupleCount += 1 }

                    // Update centroid with running average
                    let n = Float(clusters[idx].totalFaces)
                    var newCentroid: [Float] = []
                    for i in 0..<face.identityEmbedding.count {
                        let updated = (clusters[idx].centroid[i] * (n - 1) + face.identityEmbedding[i]) / n
                        newCentroid.append(updated)
                    }
                    clusters[idx].centroid = newCentroid
                } else {
                    // Create new identity cluster
                    var newCluster = InternalCluster(
                        id: "person_\(clusters.count + 1)",
                        centroid: face.identityEmbedding,
                        photoIDs: [item.id],
                        soloCount: isSolo ? 1 : 0,
                        coupleCount: isCouple ? 1 : 0,
                        totalFaces: 1,
                        distancesToCentroid: [0.0]
                    )
                    clusters.append(newCluster)
                }
            }
        }

        guard !clusters.isEmpty else {
            return fallbackCluster(items: items)
        }

        // 2. Rank clusters by wedding prominence (solo portraits + couple co-presence + overall count)
        let ranked = clusters.sorted {
            let scoreA = Double($0.soloCount * 3 + $0.coupleCount * 2 + $0.photoIDs.count)
            let scoreB = Double($1.soloCount * 3 + $1.coupleCount * 2 + $1.photoIDs.count)
            return scoreA > scoreB
        }

        var resultClusters: [PersonCluster] = []

        // Primary Subject A (Bride / Partner A)
        if let primaryA = ranked.first {
            let avgDist = primaryA.distancesToCentroid.isEmpty ? 0.0 : (primaryA.distancesToCentroid.reduce(0, +) / Float(primaryA.distancesToCentroid.count))
            let conf = Double(max(0.65, min(0.98, 1.0 - (avgDist * 1.2))))
            resultClusters.append(PersonCluster(
                id: primaryA.id,
                name: "Primary Person A",
                role: .partnerA,
                photoIDs: Array(primaryA.photoIDs),
                isSuggestedPrimary: true,
                confidence: conf
            ))
        }

        // Primary Subject B (Groom / Partner B)
        if ranked.count > 1 {
            let primaryB = ranked[1]
            let avgDist = primaryB.distancesToCentroid.isEmpty ? 0.0 : (primaryB.distancesToCentroid.reduce(0, +) / Float(primaryB.distancesToCentroid.count))
            let conf = Double(max(0.65, min(0.98, 1.0 - (avgDist * 1.2))))
            resultClusters.append(PersonCluster(
                id: primaryB.id,
                name: "Primary Person B",
                role: .partnerB,
                photoIDs: Array(primaryB.photoIDs),
                isSuggestedPrimary: true,
                confidence: conf
            ))
        }

        // Key Family / Bridal Party (recurring identities with at least 4 photos)
        for (idx, cluster) in ranked.dropFirst(2).enumerated() {
            if cluster.photoIDs.count >= 4 {
                resultClusters.append(PersonCluster(
                    id: cluster.id,
                    name: "Key Person #\(idx + 1)",
                    role: .weddingParty,
                    photoIDs: Array(cluster.photoIDs),
                    isSuggestedPrimary: false,
                    confidence: 0.80
                ))
            }
        }

        // All other guests aggregated
        var guestPhotoIDs = Set<String>()
        for cluster in ranked.dropFirst(2) where cluster.photoIDs.count < 4 {
            guestPhotoIDs.formUnion(cluster.photoIDs)
        }
        if !guestPhotoIDs.isEmpty {
            resultClusters.append(PersonCluster(
                id: "person_guests",
                name: "Guests & Attendees",
                role: .guest,
                photoIDs: Array(guestPhotoIDs),
                isSuggestedPrimary: false,
                confidence: 0.70
            ))
        }

        return resultClusters
    }

    /// Backward compatibility fallback when face instances are not pre-extracted
    public func clusterPersons(items: [PhotoItem], faceCounts: [String: Int]) -> [PersonCluster] {
        let photosWithFaces = items.filter { (faceCounts[$0.id] ?? $0.metrics.faceCount) > 0 }
        guard !photosWithFaces.isEmpty else { return [] }
        return fallbackCluster(items: items)
    }

    private func fallbackCluster(items: [PhotoItem]) -> [PersonCluster] {
        let photosWithFaces = items.filter { $0.metrics.faceCount > 0 }
        guard !photosWithFaces.isEmpty else { return [] }

        var clusterA = PersonCluster(id: "person_1", name: "Primary Person A", role: .partnerA, photoIDs: [], isSuggestedPrimary: true, confidence: 0.70)
        var clusterB = PersonCluster(id: "person_2", name: "Primary Person B", role: .partnerB, photoIDs: [], isSuggestedPrimary: true, confidence: 0.70)

        for item in photosWithFaces {
            if item.metrics.faceCount == 1 {
                if item.category == .bride || item.category == .bridePrep {
                    clusterA.photoIDs.append(item.id)
                } else if item.category == .groom || item.category == .groomPrep {
                    clusterB.photoIDs.append(item.id)
                } else {
                    clusterA.photoIDs.append(item.id)
                }
            } else if item.metrics.faceCount == 2 {
                clusterA.photoIDs.append(item.id)
                clusterB.photoIDs.append(item.id)
            }
        }
        return [clusterA, clusterB]
    }
}
