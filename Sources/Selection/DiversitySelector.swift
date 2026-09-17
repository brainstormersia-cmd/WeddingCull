import Foundation

public struct SelectionResult: Sendable {
    public let updatedItems: [PhotoItem]
    public let selectedCount: Int
    public let targetCount: Int
    public let message: String
}

public final class DiversitySelector: Sendable {
    public init() {}

    /// Performs diversity-aware MMR selection aiming for the exact target count
    public func selectPhotos(
        items: [PhotoItem],
        segments: [TemporalSegment],
        bursts: [BurstGroup],
        targetCount: Int
    ) -> SelectionResult {
        guard !items.isEmpty else {
            return SelectionResult(updatedItems: [], selectedCount: 0, targetCount: targetCount, message: "No photos to select")
        }

        // 1. Separate user-forced decisions (User overrides are absolute)
        var userSelectedIDs = Set<String>()
        var userRejectedIDs = Set<String>()
        var candidates: [PhotoItem] = []

        for item in items {
            switch item.selectionState {
            case .userSelected:
                userSelectedIDs.insert(item.id)
            case .userRejected:
                userRejectedIDs.insert(item.id)
            case .selected, .alternative, .rejected:
                // Eligible for algorithmic selection unless exact duplicate or corrupt
                if !item.isDuplicate && !item.metadata.isCorrupt {
                    candidates.append(item)
                }
            }
        }

        // Total available eligible photos including user-selected
        let totalEligibleCount = userSelectedIDs.count + candidates.count
        let effectiveTarget = min(targetCount, totalEligibleCount)

        // 2. Map burst winners and alternatives
        var burstWinnerIDs = Set<String>()
        var burstAlternativeIDs = Set<String>()
        for b in bursts {
            burstWinnerIDs.insert(b.winnerID)
            for alt in b.alternativeIDs {
                burstAlternativeIDs.insert(alt)
            }
        }

        // 3. Segment coverage allocation: allocate quota proportional to segment importance
        var segmentQuotas: [String: Int] = [:]
        let remainingTargetAfterUser = max(0, effectiveTarget - userSelectedIDs.count)

        if !segments.isEmpty && remainingTargetAfterUser > 0 {
            let totalWeights: Double = segments.reduce(0.0) { sum, seg in
                let categoryWeight = seg.inferredCategory.selectionWeight
                let photoFactor = log2(Double(max(2, seg.photoIDs.count)))
                return sum + (categoryWeight * photoFactor)
            }

            var allocated = 0
            for seg in segments {
                let categoryWeight = seg.inferredCategory.selectionWeight
                let photoFactor = log2(Double(max(2, seg.photoIDs.count)))
                let segWeight = categoryWeight * photoFactor
                let share = totalWeights > 0 ? (segWeight / totalWeights) : (1.0 / Double(segments.count))
                let quota = max(1, Int(round(Double(remainingTargetAfterUser) * share)))
                segmentQuotas[seg.id] = quota
                allocated += quota
            }

            // Adjust rounding drift to match remainingTargetAfterUser
            var diff = remainingTargetAfterUser - allocated
            if diff != 0 {
                let sortedSegIDs = segments.sorted(by: { $0.photoIDs.count > $1.photoIDs.count }).map { $0.id }
                var idx = 0
                while diff != 0 && idx < sortedSegIDs.count {
                    let segID = sortedSegIDs[idx]
                    if diff > 0 {
                        segmentQuotas[segID, default: 0] += 1
                        diff -= 1
                    } else if diff < 0 && (segmentQuotas[segID] ?? 0) > 1 {
                        segmentQuotas[segID, default: 1] -= 1
                        diff += 1
                    }
                    idx = (idx + 1) % sortedSegIDs.count
                }
            }
        }

        // 4. MMR-style Greedy selection pass
        var selectedIDs = Set(userSelectedIDs)
        var selectedItemsList: [PhotoItem] = items.filter { userSelectedIDs.contains($0.id) }
        var selectedCategories = Set<WeddingCategory>(selectedItemsList.map(\.category))
        var segmentSelectedCounts: [String: Int] = [:]

        for item in selectedItemsList {
            if let segID = item.temporalSegmentID {
                segmentSelectedCounts[segID, default: 0] += 1
            }
        }

        // Hard cap: no single temporal segment may dominate more than 60% of final selection
        let maxSegmentCap = max(1, Int(ceil(Double(effectiveTarget) * 0.60)))

        // Candidate pool sorted by base utility
        let remainingCandidates = candidates.filter { !userSelectedIDs.contains($0.id) }

        // Helper: compute similarity penalty against already selected photos
        func maxSimilarityToSelected(_ candidate: PhotoItem) -> Double {
            guard let hashCand = candidate.perceptualHash else { return 0.0 }
            var maxSim = 0.0
            for sel in selectedItemsList {
                if let selHash = sel.perceptualHash {
                    let sim = PerceptualHash.similarity(hashCand, selHash)
                    if sim > maxSim {
                        maxSim = sim
                    }
                }
            }
            return maxSim
        }

        // Pass A: Quota-constrained selection per segment
        for seg in segments {
            let quota = min(segmentQuotas[seg.id] ?? 0, maxSegmentCap)
            var segSelectedCount = segmentSelectedCounts[seg.id, default: 0]
            let segCandidates = remainingCandidates
                .filter { seg.photoIDs.contains($0.id) }
                .sorted { a, b in
                    let scoreA = a.metrics.overallScore + (burstWinnerIDs.contains(a.id) ? 0.25 : 0.0) - (burstAlternativeIDs.contains(a.id) ? 0.35 : 0.0)
                    let scoreB = b.metrics.overallScore + (burstWinnerIDs.contains(b.id) ? 0.25 : 0.0) - (burstAlternativeIDs.contains(b.id) ? 0.35 : 0.0)
                    return scoreA > scoreB
                }

            for cand in segCandidates {
                if selectedIDs.count >= effectiveTarget { break }
                if segSelectedCount >= quota { break }

                let sim = maxSimilarityToSelected(cand)
                // Skip if too similar to an already selected photo (unless it's a burst winner with good score)
                if sim > 0.85 && !burstWinnerIDs.contains(cand.id) {
                    continue
                }

                selectedIDs.insert(cand.id)
                selectedItemsList.append(cand)
                selectedCategories.insert(cand.category)
                segSelectedCount += 1
                segmentSelectedCounts[seg.id] = segSelectedCount
            }
        }

        // Pass B: Global MMR selection for remaining quota with category diversity bonus
        let lambda = 0.65 // Weight for quality vs diversity
        while selectedIDs.count < effectiveTarget {
            let unselected = remainingCandidates.filter { !selectedIDs.contains($0.id) }
            guard !unselected.isEmpty else { break }

            var bestCandidate: PhotoItem? = nil
            var bestMMRScore = -Double.greatestFiniteMagnitude

            for cand in unselected {
                // Check segment cap
                if let segID = cand.temporalSegmentID, (segmentSelectedCounts[segID] ?? 0) >= maxSegmentCap {
                    // Check if other candidates from non-capped segments exist
                    let nonCappedExist = unselected.contains { item in
                        guard let s = item.temporalSegmentID else { return true }
                        return (segmentSelectedCounts[s] ?? 0) < maxSegmentCap
                    }
                    if nonCappedExist {
                        continue
                    }
                }

                // Category coverage bonus for unrepresented categories
                let categoryBonus = selectedCategories.contains(cand.category) ? 0.0 : 0.20
                let burstBonus = burstWinnerIDs.contains(cand.id) ? 0.20 : 0.0
                let burstPenalty = burstAlternativeIDs.contains(cand.id) ? 0.25 : 0.0

                let quality = cand.metrics.overallScore + categoryBonus + burstBonus - burstPenalty
                let sim = maxSimilarityToSelected(cand)
                let mmrScore = (lambda * quality) - ((1.0 - lambda) * sim * 1.5)

                if mmrScore > bestMMRScore {
                    bestMMRScore = mmrScore
                    bestCandidate = cand
                }
            }

            guard let chosen = bestCandidate else { break }
            selectedIDs.insert(chosen.id)
            selectedItemsList.append(chosen)
            selectedCategories.insert(chosen.category)
            if let segID = chosen.temporalSegmentID {
                segmentSelectedCounts[segID, default: 0] += 1
            }
        }

        // Pass C: EXACT TARGET COUNT GUARANTEE
        // If still below target due to strict thresholds, fill from best remaining candidates
        if selectedIDs.count < effectiveTarget {
            let unselected = remainingCandidates
                .filter { !selectedIDs.contains($0.id) }
                .sorted { $0.metrics.overallScore > $1.metrics.overallScore }

            for cand in unselected {
                if selectedIDs.count >= effectiveTarget { break }
                selectedIDs.insert(cand.id)
                selectedItemsList.append(cand)
                selectedCategories.insert(cand.category)
                if let segID = cand.temporalSegmentID {
                    segmentSelectedCounts[segID, default: 0] += 1
                }
            }
        }

        // 5. Update selection states for all items
        var finalItems: [PhotoItem] = []
        finalItems.reserveCapacity(items.count)

        for var item in items {
            if item.selectionState == .userSelected {
                // User override preserved!
                finalItems.append(item)
            } else if item.selectionState == .userRejected {
                // User override preserved!
                finalItems.append(item)
            } else if selectedIDs.contains(item.id) {
                item.selectionState = .selected
                finalItems.append(item)
            } else if item.isDuplicate || item.metadata.isCorrupt || item.metrics.isTechnicallyLowQuality {
                item.selectionState = .rejected
                finalItems.append(item)
            } else {
                item.selectionState = .alternative
                finalItems.append(item)
            }
        }

        let message: String
        if effectiveTarget < targetCount {
            message = "Target requested \(targetCount), but only \(effectiveTarget) usable photographs were found."
        } else {
            message = "Successfully proposed exactly \(effectiveTarget) selected photographs."
        }

        return SelectionResult(
            updatedItems: finalItems,
            selectedCount: selectedIDs.count,
            targetCount: targetCount,
            message: message
        )
    }
}
