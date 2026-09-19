import Foundation

public struct SelectionResult: Sendable {
    public let updatedItems: [PhotoItem]
    public let selectedCount: Int
    public let reviewCount: Int
    public let targetCount: Int
    public let message: String

    public init(
        updatedItems: [PhotoItem],
        selectedCount: Int,
        reviewCount: Int = 0,
        targetCount: Int,
        message: String
    ) {
        self.updatedItems = updatedItems
        self.selectedCount = selectedCount
        self.reviewCount = reviewCount
        self.targetCount = targetCount
        self.message = message
    }
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
            case .selected, .alternative, .review, .rejected:
                // Eligible for algorithmic selection unless exact duplicate, corrupt, or technically low quality
                if !item.isDuplicate && !item.metadata.isCorrupt && !item.metrics.isTechnicallyLowQuality {
                    candidates.append(item)
                }
            }
        }

        // Total available eligible photos including user-selected
        let totalEligibleCount = userSelectedIDs.count + candidates.count
        let effectiveTarget = min(targetCount, totalEligibleCount)

        // 2. Map burst winners, alternatives, and review candidates
        var burstWinnerIDs = Set<String>()
        var burstAlternativeIDs = Set<String>()
        var burstReviewIDs = Set<String>()
        for b in bursts {
            burstWinnerIDs.insert(b.winnerID)
            for alt in b.alternativeIDs {
                burstAlternativeIDs.insert(alt)
            }
            for rev in b.reviewIDs {
                burstReviewIDs.insert(rev)
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
            if diff > 0 {
                // Distribute extra quota starting from the largest segments (tie-break strictly on seg ID)
                let sortedSegIDs = segments.sorted {
                    if $0.photoIDs.count != $1.photoIDs.count {
                        return $0.photoIDs.count > $1.photoIDs.count
                    }
                    return $0.id < $1.id
                }.map { $0.id }
                var idx = 0
                while diff > 0 && !sortedSegIDs.isEmpty {
                    let segID = sortedSegIDs[idx % sortedSegIDs.count]
                    segmentQuotas[segID, default: 0] += 1
                    diff -= 1
                    idx += 1
                }
            } else if diff < 0 {
                // Need to reduce quotas.
                // First pass: reduce quotas that are > 1, starting from smallest segments (tie-break strictly on seg ID)
                let smallestFirst = segments.sorted {
                    if $0.photoIDs.count != $1.photoIDs.count {
                        return $0.photoIDs.count < $1.photoIDs.count
                    }
                    return $0.id < $1.id
                }.map { $0.id }
                var madeProgress = true
                while diff < 0 && madeProgress {
                    madeProgress = false
                    for segID in smallestFirst {
                        if diff < 0 && (segmentQuotas[segID] ?? 0) > 1 {
                            segmentQuotas[segID, default: 1] -= 1
                            diff += 1
                            madeProgress = true
                        }
                    }
                }
                // Second pass: if still diff < 0 (e.g. remainingTargetAfterUser < segments.count),
                // allow quotas of smallest segments to drop to 0
                if diff < 0 {
                    for segID in smallestFirst {
                        if diff < 0 && (segmentQuotas[segID] ?? 0) > 0 {
                            segmentQuotas[segID, default: 0] -= 1
                            diff += 1
                        }
                    }
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

        // Incremental maximum similarity to any selected photo
        var maxSimToSelected: [String: Double] = [:]
        maxSimToSelected.reserveCapacity(remainingCandidates.count)
        for cand in remainingCandidates {
            maxSimToSelected[cand.id] = 0.0
        }

        // Helper to register an item as selected and incrementally update maxSimToSelected
        func registerSelection(_ chosen: PhotoItem) {
            selectedIDs.insert(chosen.id)
            selectedItemsList.append(chosen)
            selectedCategories.insert(chosen.category)
            if let segID = chosen.temporalSegmentID {
                segmentSelectedCounts[segID, default: 0] += 1
            }
            if let chosenHash = chosen.perceptualHash {
                for cand in remainingCandidates where !selectedIDs.contains(cand.id) {
                    if let candHash = cand.perceptualHash {
                        let sim = PerceptualHash.similarity(candHash, chosenHash)
                        if sim > (maxSimToSelected[cand.id] ?? 0.0) {
                            maxSimToSelected[cand.id] = sim
                        }
                    }
                }
            }
        }

        // Initialize similarity against initially user-selected photos
        for userItem in selectedItemsList {
            if let userHash = userItem.perceptualHash {
                for cand in remainingCandidates {
                    if let candHash = cand.perceptualHash {
                        let sim = PerceptualHash.similarity(candHash, userHash)
                        if sim > (maxSimToSelected[cand.id] ?? 0.0) {
                            maxSimToSelected[cand.id] = sim
                        }
                    }
                }
            }
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
                    let qA = round(scoreA * 10000.0) / 10000.0
                    let qB = round(scoreB * 10000.0) / 10000.0
                    if qA != qB {
                        return qA > qB
                    }
                    return a.id < b.id
                }

            for cand in segCandidates {
                if selectedIDs.count >= effectiveTarget { break }
                if segSelectedCount >= quota { break }

                let sim = maxSimToSelected[cand.id] ?? 0.0
                // Skip if too similar to an already selected photo (unless it's a burst winner with good score)
                if sim > 0.85 && !burstWinnerIDs.contains(cand.id) {
                    continue
                }

                registerSelection(cand)
                segSelectedCount += 1
            }
        }

        // Pass B: Global MMR selection for remaining quota with category diversity bonus
        let lambda = 0.65 // Weight for quality vs diversity
        while selectedIDs.count < effectiveTarget {
            let unselected = remainingCandidates.filter { !selectedIDs.contains($0.id) }
            guard !unselected.isEmpty else { break }

            // Pre-evaluate once per outer MMR iteration: check if any unselected candidate is in a non-capped segment
            let nonCappedExist = unselected.contains { item in
                guard let s = item.temporalSegmentID else { return true }
                return (segmentSelectedCounts[s, default: 0]) < maxSegmentCap
            }

            var bestCandidate: PhotoItem? = nil
            var bestMMRScore = -Double.greatestFiniteMagnitude

            for cand in unselected {
                // Check segment cap
                if nonCappedExist, let segID = cand.temporalSegmentID, (segmentSelectedCounts[segID] ?? 0) >= maxSegmentCap {
                    continue
                }

                // Category coverage bonus for unrepresented categories
                let categoryBonus = selectedCategories.contains(cand.category) ? 0.0 : 0.20
                let burstBonus = burstWinnerIDs.contains(cand.id) ? 0.20 : 0.0
                let burstPenalty = burstAlternativeIDs.contains(cand.id) ? 0.25 : 0.0

                let quality = cand.metrics.overallScore + categoryBonus + burstBonus - burstPenalty
                let sim = maxSimToSelected[cand.id] ?? 0.0
                let mmrScore = (lambda * quality) - ((1.0 - lambda) * sim * 1.5)
                let quantizedMMR = round(mmrScore * 10000.0) / 10000.0

                if quantizedMMR > bestMMRScore || (quantizedMMR == bestMMRScore && (bestCandidate == nil || cand.id < bestCandidate!.id)) {
                    bestMMRScore = quantizedMMR
                    bestCandidate = cand
                }
            }

            guard let chosen = bestCandidate else { break }
            registerSelection(chosen)
        }

        // Pass C: EXACT TARGET COUNT GUARANTEE
        // If still below target due to strict thresholds, fill from best remaining candidates (strict total order)
        if selectedIDs.count < effectiveTarget {
            let unselected = remainingCandidates
                .filter { !selectedIDs.contains($0.id) }
                .sorted {
                    let scoreA = round($0.metrics.overallScore * 10000.0) / 10000.0
                    let scoreB = round($1.metrics.overallScore * 10000.0) / 10000.0
                    if scoreA != scoreB {
                        return scoreA > scoreB
                    }
                    return $0.id < $1.id
                }

            for cand in unselected {
                if selectedIDs.count >= effectiveTarget { break }
                registerSelection(cand)
            }
        }

        // 5. Update selection states for all items
        var finalItems: [PhotoItem] = []
        finalItems.reserveCapacity(items.count)

        var reviewCount = 0

        for var item in items {
            if item.selectionState == .userSelected {
                // User override preserved!
                finalItems.append(item)
            } else if item.selectionState == .userRejected {
                // User override preserved!
                finalItems.append(item)
            } else if item.isDuplicate || item.metadata.isCorrupt || item.metrics.isTechnicallyLowQuality {
                // Catastrophic defects, duplicates, and corrupt files are unconditionally rejected
                item.selectionState = .rejected
                finalItems.append(item)
            } else if selectedIDs.contains(item.id) {
                item.selectionState = .selected
                finalItems.append(item)
            } else if burstReviewIDs.contains(item.id) {
                // Ambiguous burst runner-up flagged for human review
                item.selectionState = .review
                reviewCount += 1
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
            message = "Successfully proposed exactly \(effectiveTarget) selected photographs (\(reviewCount) flagged for review)."
        }

        return SelectionResult(
            updatedItems: finalItems,
            selectedCount: selectedIDs.count,
            reviewCount: reviewCount,
            targetCount: targetCount,
            message: message
        )
    }
}
