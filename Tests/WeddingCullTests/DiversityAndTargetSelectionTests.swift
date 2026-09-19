import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

final class DiversityAndTargetSelectionTests: XCTestCase {
    func testExactTargetCountSelection() {
        var items: [PhotoItem] = []
        for i in 0..<100 {
            var item = PhotoItem(id: "photo_\(i)", fileName: "photo_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(i).jpg"))
            item.metrics.overallScore = Double(i) / 100.0
            item.perceptualHash = UInt64(i * 1000)
            items.append(item)
        }

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 40)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 40, "Must select exactly 40 photographs")
    }

    func testUserOverridesPersistence() {
        var items: [PhotoItem] = []
        for i in 0..<20 {
            var item = PhotoItem(id: "photo_\(i)", fileName: "photo_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(i).jpg"))
            item.metrics.overallScore = Double(i) / 20.0
            items.append(item)
        }

        // Force item 0 (lowest score) to be userSelected
        items[0].selectionState = .userSelected

        // Force item 19 (highest score) to be userRejected
        items[19].selectionState = .userRejected

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 5)

        let item0 = result.updatedItems.first(where: { $0.id == "photo_0" })!
        let item19 = result.updatedItems.first(where: { $0.id == "photo_19" })!

        XCTAssertEqual(item0.selectionState, .userSelected, "User selected photo must remain selected")
        XCTAssertTrue(item0.selectionState.isIncludedInFinal)

        XCTAssertEqual(item19.selectionState, .userRejected, "User rejected photo must remain rejected")
        XCTAssertFalse(item19.selectionState.isIncludedInFinal)
    }

    func testTargetCountExceedingAvailable() {
        var items: [PhotoItem] = []
        for i in 0..<15 {
            var item = PhotoItem(id: "photo_\(i)", fileName: "photo_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(i).jpg"))
            item.metrics.overallScore = 0.8
            items.append(item)
        }

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 50)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 15, "When target exceeds available, select all eligible photos without crashing")
    }

    func testTemporalSegmentDominanceCapped() {
        var items: [PhotoItem] = []
        let dominantSegID = "seg_ceremony"
        let minorSegID = "seg_reception"

        // Create 80 photos in dominant segment with high scores (0.90)
        for i in 0..<80 {
            var item = PhotoItem(id: "dom_\(i)", fileName: "dom_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/dom_\(i).jpg"))
            item.metrics.overallScore = 0.90
            item.temporalSegmentID = dominantSegID
            item.perceptualHash = UInt64(i * 100)
            items.append(item)
        }

        // Create 40 photos in minor segment with slightly lower scores (0.75)
        for i in 0..<40 {
            var item = PhotoItem(id: "min_\(i)", fileName: "min_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/min_\(i).jpg"))
            item.metrics.overallScore = 0.75
            item.temporalSegmentID = minorSegID
            item.perceptualHash = UInt64(i * 500 + 100000)
            items.append(item)
        }

        let segments = [
            TemporalSegment(id: dominantSegID, startTime: Date(), endTime: Date().addingTimeInterval(3600), photoIDs: items.filter { $0.temporalSegmentID == dominantSegID }.map(\.id)),
            TemporalSegment(id: minorSegID, startTime: Date().addingTimeInterval(3600), endTime: Date().addingTimeInterval(7200), photoIDs: items.filter { $0.temporalSegmentID == minorSegID }.map(\.id))
        ]

        let targetCount = 50
        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: segments, bursts: [], targetCount: targetCount)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, targetCount)

        let dominantSelected = selected.filter { $0.temporalSegmentID == dominantSegID }
        let maxAllowed = Int(ceil(Double(targetCount) * 0.60)) // 60% of 50 = 30
        XCTAssertLessThanOrEqual(dominantSelected.count, maxAllowed, "Dominant segment must not exceed 60% of final selection")
        XCTAssertGreaterThan(selected.filter { $0.temporalSegmentID == minorSegID }.count, 0, "Minor segment must be represented")
    }

    func testCategoryDiversityCoverage() {
        var items: [PhotoItem] = []
        let categories: [WeddingCategory] = [
            .bridePrep, .groomPrep, .ceremony, .bride, .groom, .couple, .reception, .details
        ]

        for (cIdx, cat) in categories.enumerated() {
            for i in 0..<10 {
                var item = PhotoItem(id: "photo_\(cat.rawValue)_\(i)", fileName: "photo_\(cat.rawValue)_\(i).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(cat.rawValue)_\(i).jpg"))
                // Give earlier categories much higher scores
                item.metrics.overallScore = Double(10 - cIdx) * 0.1
                item.category = cat
                item.perceptualHash = UInt64((cIdx * 10 + i) * 777)
                items.append(item)
            }
        }

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 20)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 20)

        let uniqueCategories = Set(selected.map(\.category))
        XCTAssertGreaterThanOrEqual(uniqueCategories.count, 4, "Selection must cover at least 4 distinct wedding categories when source spans 8")
    }

    func testBurstWinnerPreference() {
        var items: [PhotoItem] = []
        let burstID = "burst_1"
        let winnerID = "burst_1_frame_2"
        let memberIDs = ["burst_1_frame_1", "burst_1_frame_2", "burst_1_frame_3"]

        for id in memberIDs {
            var item = PhotoItem(id: id, fileName: "\(id).jpg", sourceURL: URL(fileURLWithPath: "/tmp/\(id).jpg"))
            item.burstGroupID = burstID
            item.metrics.overallScore = 0.85 // Identical base scores
            item.perceptualHash = 12345 // Near identical visual hash
            items.append(item)
        }

        let burst = BurstGroup(id: burstID, memberIDs: memberIDs, winnerID: winnerID, alternativeIDs: ["burst_1_frame_1", "burst_1_frame_3"])

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [burst], targetCount: 1)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.id, winnerID, "Burst winner must be preferred over burst alternatives")
    }

    func testExactDuplicateExclusion() {
        var items: [PhotoItem] = []
        var original = PhotoItem(id: "original", fileName: "original.jpg", sourceURL: URL(fileURLWithPath: "/tmp/original.jpg"))
        original.metrics.overallScore = 0.95
        original.isDuplicate = false
        items.append(original)

        var duplicate = PhotoItem(id: "duplicate", fileName: "duplicate.jpg", sourceURL: URL(fileURLWithPath: "/tmp/duplicate.jpg"))
        duplicate.metrics.overallScore = 0.99 // Higher score than original
        duplicate.isDuplicate = true
        duplicate.duplicateOfID = "original"
        items.append(duplicate)

        let selector = DiversitySelector()
        let result = selector.selectPhotos(items: items, segments: [], bursts: [], targetCount: 1)

        let selected = result.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.id, "original", "Exact duplicates must not be selected")
        XCTAssertEqual(result.updatedItems.first(where: { $0.id == "duplicate" })?.selectionState, .rejected)
    }

    func testSelectionWhenTargetCountIsLessThanSegmentCount() {
        // Reproduce edge case: 7 segments but user requests only 4 or 6 photos (targetCount < segments.count)
        var items: [PhotoItem] = []
        var segments: [TemporalSegment] = []

        for segIdx in 0..<7 {
            let segID = "segment_\(segIdx)"
            var segPhotoIDs: [String] = []
            for p in 0..<5 {
                let photoID = "photo_\(segIdx)_\(p)"
                segPhotoIDs.append(photoID)
                var item = PhotoItem(
                    id: photoID,
                    fileName: "\(photoID).jpg",
                    sourceURL: URL(fileURLWithPath: "/tmp/\(photoID).jpg")
                )
                item.temporalSegmentID = segID
                item.metrics.overallScore = 0.5 + Double(segIdx * 5 + p) * 0.01
                item.perceptualHash = UInt64(segIdx * 1000 + p * 10)
                items.append(item)
            }
            segments.append(
                TemporalSegment(
                    id: segID,
                    startTime: Date().addingTimeInterval(Double(segIdx * 3600)),
                    endTime: Date().addingTimeInterval(Double(segIdx * 3600 + 1800)),
                    photoIDs: segPhotoIDs
                )
            )
        }

        let selector = DiversitySelector()

        // Test with target 4 (< 7 segments)
        let result4 = selector.selectPhotos(items: items, segments: segments, bursts: [], targetCount: 4)
        let selected4 = result4.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected4.count, 4, "Must select exactly 4 photos even when there are 7 segments")

        // Test with target 6 (< 7 segments, UITest condition)
        let result6 = selector.selectPhotos(items: items, segments: segments, bursts: [], targetCount: 6)
        let selected6 = result6.updatedItems.filter { $0.selectionState.isIncludedInFinal }
        XCTAssertEqual(selected6.count, 6, "Must select exactly 6 photos even when there are 7 segments")
    }

    // MARK: - Legacy Reference Implementation for Equivalence Proof

    private func legacySelectPhotos(
        items: [PhotoItem],
        segments: [TemporalSegment],
        bursts: [BurstGroup],
        targetCount: Int
    ) -> SelectionResult {
        guard !items.isEmpty else {
            return SelectionResult(updatedItems: [], selectedCount: 0, targetCount: targetCount, message: "No photos to select")
        }

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
                if !item.isDuplicate && !item.metadata.isCorrupt && !item.metrics.isTechnicallyLowQuality {
                    candidates.append(item)
                }
            }
        }

        let totalEligibleCount = userSelectedIDs.count + candidates.count
        let effectiveTarget = min(targetCount, totalEligibleCount)

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

            var diff = remainingTargetAfterUser - allocated
            if diff > 0 {
                let sortedSegIDs = segments.sorted(by: { $0.photoIDs.count > $1.photoIDs.count }).map { $0.id }
                var idx = 0
                while diff > 0 && !sortedSegIDs.isEmpty {
                    let segID = sortedSegIDs[idx % sortedSegIDs.count]
                    segmentQuotas[segID, default: 0] += 1
                    diff -= 1
                    idx += 1
                }
            } else if diff < 0 {
                let smallestFirst = segments.sorted(by: { $0.photoIDs.count < $1.photoIDs.count }).map { $0.id }
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

        var selectedIDs = Set(userSelectedIDs)
        var selectedItemsList: [PhotoItem] = items.filter { userSelectedIDs.contains($0.id) }
        var selectedCategories = Set<WeddingCategory>(selectedItemsList.map(\.category))
        var segmentSelectedCounts: [String: Int] = [:]

        for item in selectedItemsList {
            if let segID = item.temporalSegmentID {
                segmentSelectedCounts[segID, default: 0] += 1
            }
        }

        let maxSegmentCap = max(1, Int(ceil(Double(effectiveTarget) * 0.60)))
        let remainingCandidates = candidates.filter { !userSelectedIDs.contains($0.id) }

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

        for seg in segments {
            let quota = min(segmentQuotas[seg.id] ?? 0, maxSegmentCap)
            guard quota > 0 else { continue }
            let segCandidates = remainingCandidates
                .filter { seg.photoIDs.contains($0.id) }
                .sorted { a, b in
                    let scoreA = a.metrics.overallScore + (burstWinnerIDs.contains(a.id) ? 0.25 : 0.0) - (burstAlternativeIDs.contains(a.id) ? 0.35 : 0.0)
                    let scoreB = b.metrics.overallScore + (burstWinnerIDs.contains(b.id) ? 0.25 : 0.0) - (burstAlternativeIDs.contains(b.id) ? 0.35 : 0.0)
                    return scoreA > scoreB
                }

            var segSelectedCount = segmentSelectedCounts[seg.id] ?? 0

            for cand in segCandidates {
                if selectedIDs.count >= effectiveTarget { break }
                if segSelectedCount >= quota { break }

                let sim = maxSimilarityToSelected(cand)
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

        let lambda = 0.65
        while selectedIDs.count < effectiveTarget {
            let unselected = remainingCandidates.filter { !selectedIDs.contains($0.id) }
            guard !unselected.isEmpty else { break }

            var bestCandidate: PhotoItem? = nil
            var bestMMRScore = -Double.greatestFiniteMagnitude

            for cand in unselected {
                if let segID = cand.temporalSegmentID, (segmentSelectedCounts[segID] ?? 0) >= maxSegmentCap {
                    let nonCappedExist = unselected.contains { item in
                        guard let s = item.temporalSegmentID else { return true }
                        return (segmentSelectedCounts[s] ?? 0) < maxSegmentCap
                    }
                    if nonCappedExist {
                        continue
                    }
                }

                let categoryBonus = selectedCategories.contains(cand.category) ? 0.0 : 0.15
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
                segmentSelectedCounts[segID] = (segmentSelectedCounts[segID] ?? 0) + 1
            }
        }

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
                    segmentSelectedCounts[segID] = (segmentSelectedCounts[segID] ?? 0) + 1
                }
            }
        }

        var finalItems: [PhotoItem] = []
        finalItems.reserveCapacity(items.count)

        var reviewCount = 0

        for var item in items {
            if item.selectionState == .userSelected {
                finalItems.append(item)
            } else if item.selectionState == .userRejected {
                finalItems.append(item)
            } else if item.isDuplicate || item.metadata.isCorrupt || item.metrics.isTechnicallyLowQuality {
                item.selectionState = .rejected
                finalItems.append(item)
            } else if selectedIDs.contains(item.id) {
                item.selectionState = .selected
                finalItems.append(item)
            } else if burstReviewIDs.contains(item.id) {
                item.selectionState = .review
                reviewCount += 1
                finalItems.append(item)
            } else {
                item.selectionState = .alternative
                finalItems.append(item)
            }
        }

        return SelectionResult(
            updatedItems: finalItems,
            selectedCount: selectedIDs.count,
            reviewCount: reviewCount,
            targetCount: targetCount,
            message: "Legacy selection"
        )
    }

    func testEquivalenceBetweenIncrementalAndLegacySelection() {
        var items: [PhotoItem] = []
        var segments: [TemporalSegment] = []
        var bursts: [BurstGroup] = []

        let categories: [WeddingCategory] = [
            .bridePrep, .groomPrep, .ceremony, .bride, .groom, .couple, .reception, .details
        ]

        // Create 300 test photos across 6 temporal segments
        let segmentCount = 6
        var segPhotoMap: [String: [String]] = [:]
        for s in 0..<segmentCount {
            segPhotoMap["seg_\(s)"] = []
        }

        for i in 0..<300 {
            let photoID = "photo_\(i)"
            var item = PhotoItem(
                id: photoID,
                fileName: "\(photoID).jpg",
                sourceURL: URL(fileURLWithPath: "/tmp/\(photoID).jpg")
            )
            let segID = "seg_\(i % segmentCount)"
            segPhotoMap[segID]?.append(photoID)
            item.temporalSegmentID = segID
            item.category = categories[(i / 10) % categories.count]
            item.metrics.overallScore = 0.20 + Double(i) / 400.0
            // Realistic varying perceptual hashes
            item.perceptualHash = UInt64((i * 1234567) & 0xFFFFFFFF)

            // Inject a few user decisions
            if i == 5 { item.selectionState = .userSelected }
            if i == 15 { item.selectionState = .userRejected }

            items.append(item)
        }

        for s in 0..<segmentCount {
            let segID = "seg_\(s)"
            segments.append(TemporalSegment(
                id: segID,
                startTime: Date().addingTimeInterval(Double(s * 1800)),
                endTime: Date().addingTimeInterval(Double((s + 1) * 1800)),
                photoIDs: segPhotoMap[segID] ?? []
            ))
        }

        // Create 5 burst groups
        for b in 0..<5 {
            let burstID = "burst_\(b)"
            let memberIDs = ["photo_\(b * 10)", "photo_\(b * 10 + 1)", "photo_\(b * 10 + 2)"]
            bursts.append(BurstGroup(
                id: burstID,
                memberIDs: memberIDs,
                winnerID: memberIDs[1],
                alternativeIDs: [memberIDs[0], memberIDs[2]]
            ))
        }

        let selector = DiversitySelector()

        // Test at multiple target counts
        for target in [25, 75, 120, 200] {
            let legacyResult = legacySelectPhotos(items: items, segments: segments, bursts: bursts, targetCount: target)
            let incrementalResult = selector.selectPhotos(items: items, segments: segments, bursts: bursts, targetCount: target)

            let legacySelected = legacyResult.updatedItems.filter { $0.selectionState.isIncludedInFinal }
            let incrementalSelected = incrementalResult.updatedItems.filter { $0.selectionState.isIncludedInFinal }

            XCTAssertEqual(
                incrementalSelected.count,
                legacySelected.count,
                "Target \(target): Selected counts must match exactly"
            )

            let legacyIDs = legacySelected.map(\.id)
            let incrementalIDs = incrementalSelected.map(\.id)

            XCTAssertEqual(
                incrementalIDs,
                legacyIDs,
                "Target \(target): Selected photo IDs must be 100% identical between incremental and legacy selection"
            )

            for (idx, (inc, leg)) in zip(incrementalResult.updatedItems, legacyResult.updatedItems).enumerated() {
                XCTAssertEqual(
                    inc.id,
                    leg.id,
                    "Item \(idx) ID mismatch"
                )
                XCTAssertEqual(
                    inc.selectionState,
                    leg.selectionState,
                    "Item \(inc.id) selectionState must match exactly: incremental=\(inc.selectionState), legacy=\(leg.selectionState)"
                )
            }
        }
    }
}

