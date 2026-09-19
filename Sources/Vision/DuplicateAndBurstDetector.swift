import Foundation
import CryptoKit

public struct DuplicateResult: Sendable {
    public let exactDuplicateIDs: [String: String] // duplicateID -> originalID
    public let nearDuplicatePairs: [(idA: String, idB: String, similarity: Double)]
}

public final class DuplicateAndBurstDetector: Sendable {
    public let enableFaceCaptureQuality: Bool

    public init(enableFaceCaptureQuality: Bool = true) {
        self.enableFaceCaptureQuality = enableFaceCaptureQuality
    }

    /// Detects exact duplicates using staged hashing (size -> 4KB prefix -> full SHA256)
    public func detectExactDuplicates(items: [PhotoItem]) -> [String: String] {
        var duplicates: [String: String] = [:] // itemID -> canonicalItemID

        // Group by file size
        var sizeGroups: [Int64: [PhotoItem]] = [:]
        for item in items {
            sizeGroups[item.fileSizeBytes, default: []].append(item)
        }

        for (_, group) in sizeGroups where group.count > 1 {
            // Stage 2: 4KB prefix hash
            var prefixGroups: [String: [PhotoItem]] = [:]
            for item in group {
                if let prefixHash = computeFilePrefixHash(url: item.sourceURL, bytesCount: 4096) {
                    prefixGroups[prefixHash, default: []].append(item)
                }
            }

            // Stage 3: full file hash for candidates matching prefix
            for (_, prefixCandidateGroup) in prefixGroups where prefixCandidateGroup.count > 1 {
                var fullHashGroups: [String: [PhotoItem]] = [:]
                for item in prefixCandidateGroup {
                    if let fullHash = computeFullSHA256(url: item.sourceURL) {
                        fullHashGroups[fullHash, default: []].append(item)
                    }
                }

                for (_, exactGroup) in fullHashGroups where exactGroup.count > 1 {
                    let sortedExact = exactGroup.sorted { a, b in
                        let dateA = a.metadata.captureDate ?? a.fileModificationDate
                        let dateB = b.metadata.captureDate ?? b.fileModificationDate
                        if dateA != dateB {
                            return dateA < dateB
                        }
                        let aIsDup = a.fileName.localizedCaseInsensitiveContains("dup") || a.fileName.localizedCaseInsensitiveContains("copy")
                        let bIsDup = b.fileName.localizedCaseInsensitiveContains("dup") || b.fileName.localizedCaseInsensitiveContains("copy")
                        if aIsDup != bIsDup {
                            return !aIsDup && bIsDup
                        }
                        if a.fileName != b.fileName {
                            return a.fileName < b.fileName
                        }
                        return a.id < b.id
                    }
                    let canonical = sortedExact[0]
                    for duplicate in sortedExact.dropFirst() {
                        duplicates[duplicate.id] = canonical.id
                    }
                }
            }
        }

        return duplicates
    }

    /// Detects bursts and near-duplicates based on capture timestamps, camera metadata, and visual similarity
    public func detectBursts(
        items: [PhotoItem],
        featurePrintDistances: [String: [String: Float]] = [:]
    ) -> [BurstGroup] {
        // Sort chronologically (with strict ID tie-breaker for photos taken at identical timestamp)
        let sorted = items.sorted {
            let dateA = $0.metadata.captureDate ?? $0.fileModificationDate
            let dateB = $1.metadata.captureDate ?? $1.fileModificationDate
            if dateA != dateB {
                return dateA < dateB
            }
            return $0.id < $1.id
        }

        var bursts: [BurstGroup] = []
        var currentBurstItems: [PhotoItem] = []

        for item in sorted {
            guard !item.isDuplicate else { continue }

            if currentBurstItems.isEmpty {
                currentBurstItems.append(item)
                continue
            }

            let prevItem = currentBurstItems.last!
            let prevDate = prevItem.metadata.captureDate ?? prevItem.fileModificationDate
            let currDate = item.metadata.captureDate ?? item.fileModificationDate
            let timeDiff = abs(currDate.timeIntervalSince(prevDate))

            // Check EXIF burst UUID first if available
            let sameBurstUUID = item.metadata.burstUUID != nil && item.metadata.burstUUID == prevItem.metadata.burstUUID

            // Check visual similarity via perceptual hash or feature print
            var isVisuallySimilar = false
            if let hashA = prevItem.perceptualHash, let hashB = item.perceptualHash {
                let sim = PerceptualHash.similarity(hashA, hashB)
                if sim >= 0.85 {
                    isVisuallySimilar = true
                }
            }

            if let dist = featurePrintDistances[prevItem.id]?[item.id], dist < 0.45 {
                isVisuallySimilar = true
            }

            // A burst occurs if captured within 3 seconds AND visually similar or same burst UUID
            let isBurstCandidate = (timeDiff <= 3.5 && isVisuallySimilar) || sameBurstUUID

            if isBurstCandidate {
                currentBurstItems.append(item)
            } else {
                if currentBurstItems.count >= 2 {
                    bursts.append(createBurstGroup(from: currentBurstItems))
                }
                currentBurstItems = [item]
            }
        }

        if currentBurstItems.count >= 2 {
            bursts.append(createBurstGroup(from: currentBurstItems))
        }

        return bursts
    }

    /// Selects the best frame in a burst based on sharpness, face quality, eye openness, and exposure
    public func createBurstGroup(from burstMembers: [PhotoItem]) -> BurstGroup {
        guard !burstMembers.isEmpty else {
            return BurstGroup()
        }

        // Rank members to choose recommended winner (strict total order with ID tie-breaker)
        // Compute relative sharpness context strictly on non-face members to avoid contamination from faces
        let nonFaceMembers = burstMembers.filter { $0.metrics.faceCount == 0 }
        let burstCtx: (minLogSharp: Double, maxLogSharp: Double)?
        if !nonFaceMembers.isEmpty {
            let logSharps = nonFaceMembers.map { log1p(max(0.0, $0.metrics.rawSharpness)) }
            burstCtx = (minLogSharp: logSharps.min() ?? 0.0, maxLogSharp: logSharps.max() ?? 0.0)
        } else {
            burstCtx = nil
        }

        let ranked = burstMembers.sorted { a, b in
            let scoreA = computeBurstFrameQuality(a, burstContext: burstCtx)
            let scoreB = computeBurstFrameQuality(b, burstContext: burstCtx)
            let qA = round(scoreA * 10000.0) / 10000.0
            let qB = round(scoreB * 10000.0) / 10000.0
            if qA != qB {
                return qA > qB
            }
            return a.id < b.id
        }

        let winner = ranked[0]
        let winnerScore = computeBurstFrameQuality(winner, burstContext: burstCtx)
        let alternatives = ranked.dropFirst().map { $0.id }
        var reviewCandidates: [String] = []

        // Ambiguity check: if runner-up is within 0.05 of the winner and not low quality, flag for review
        if ranked.count > 1 {
            let runnerUp = ranked[1]
            let runnerUpScore = computeBurstFrameQuality(runnerUp, burstContext: burstCtx)
            if abs(winnerScore - runnerUpScore) <= 0.05 && !runnerUp.metrics.isTechnicallyLowQuality {
                reviewCandidates.append(runnerUp.id)
            }
        }

        let firstDate = burstMembers.first?.metadata.captureDate ?? Date()
        let lastDate = burstMembers.last?.metadata.captureDate ?? Date()
        let duration = abs(lastDate.timeIntervalSince(firstDate))
        let burstID = "burst_" + PhotoItem.deterministicSHA256Hex(burstMembers.map(\.id).sorted().joined(separator: ","))
        return BurstGroup(
            id: burstID,
            name: "Burst (\(burstMembers.count) photos)",
            memberIDs: burstMembers.map { $0.id },
            winnerID: winner.id,
            alternativeIDs: alternatives,
            reviewIDs: reviewCandidates,
            timeRangeSeconds: duration,
            averageSimilarity: 0.9
        )
    }

    public func computeBurstFrameQuality(
        _ item: PhotoItem,
        burstContext: (minLogSharp: Double, maxLogSharp: Double)? = nil
    ) -> Double {
        var score: Double = 0.0

        // 1. Face quality & sharpness take precedence
        if item.metrics.faceCount > 0 {
            if enableFaceCaptureQuality, let fcq = item.metrics.rawFaceCaptureQuality {
                score += fcq * 0.40
            } else {
                score += item.metrics.faceQualityScore * 0.40
            }
            let faceSharp = (item.metrics.rawFaceSharpness != nil ? min(1.0, item.metrics.rawFaceSharpness! / 500.0) : item.metrics.faceSharpnessScore)
            score += faceSharp * 0.30
            if let eye = item.metrics.averageEyeOpenness {
                score += eye * 0.15
            }
            // Exposure & technical quality (0.15, summing to 1.00 with face metrics)
            score += item.metrics.exposureScore * 0.15
        } else {
            // Non-face: log1p sharpness with relative within-burst normalization (0.50) and exposure (0.50) summing to 1.00
            let sharp: Double
            let curLog = log1p(max(0.0, item.metrics.rawSharpness))
            if let ctx = burstContext {
                let spread = ctx.maxLogSharp - ctx.minLogSharp
                if spread > 0.18 {
                    sharp = min(1.0, max(0.0, (curLog - ctx.minLogSharp) / spread))
                } else {
                    // Spread is negligible (<= ~20%): sharpness is considered equivalent across burst frames
                    sharp = 0.50
                }
            } else if item.metrics.rawSharpness > 0.0 {
                sharp = min(1.0, curLog / log1p(2500.0))
            } else {
                sharp = item.metrics.sharpnessScore
            }
            score += sharp * 0.50
            score += item.metrics.exposureScore * 0.50
        }

        // Penalize severe clipping or low quality
        if item.metrics.isSevereUnderexposed || item.metrics.isSevereOverexposed {
            score -= 0.25
        }

        return max(0.0, score)
    }

    private func computeFilePrefixHash(url: URL, bytesCount: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: bytesCount)
        guard !data.isEmpty else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func computeFullSHA256(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65536)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
