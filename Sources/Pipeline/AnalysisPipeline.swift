import Foundation
import CoreGraphics
import Vision

public enum AnalysisPhase: String, CaseIterable, Sendable {
    case discovery = "Importazione"
    case previews = "Anteprime"
    case quality = "Qualità"
    case faces = "Volti"
    case duplicates = "Duplicati e Bursts"
    case scenes = "Segmentazione Scene"
    case classification = "Classificazione"
    case people = "Persone"
    case ranking = "Classifica"
    case selection = "Selezione"
}

public struct AnalysisProgress: Sendable {
    public let phase: AnalysisPhase
    public let completedUnits: Int
    public let totalUnits: Int
    public let message: String
    public let elapsedTime: TimeInterval
}

public actor AnalysisPipeline {
    private let hardware: HardwareCapabilities
    private let importer = PhotoImporter()
    private let previewPipeline: PreviewPipeline
    private let qualityAnalyzer = TechnicalQualityAnalyzer()
    private let faceAnalyzer = FaceAnalyzer()
    private let duplicateDetector = DuplicateAndBurstDetector()
    private let temporalSegmenter = TemporalSegmenter()
    private let classifier = VisionSceneClassifier()
    private let personClusterer = PersonClusterer()
    private let scorer = QualityScorer()
    private let selector = DiversitySelector()

    public init(hardware: HardwareCapabilities = HardwareCapabilities(), customCacheDir: URL? = nil) {
        self.hardware = hardware
        self.previewPipeline = PreviewPipeline(customCacheDirectory: customCacheDir)
    }

    public func runAnalysis(
        sourceFolder: URL,
        targetCount: Int = 700,
        progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) async throws -> SessionData {
        let startTime = Date()

        @Sendable func report(phase: AnalysisPhase, current: Int, total: Int, message: String) {
            let elapsed = Date().timeIntervalSince(startTime)
            progressHandler?(AnalysisProgress(
                phase: phase,
                completedUnits: current,
                totalUnits: total,
                message: message,
                elapsedTime: elapsed
            ))
        }

        // Phase 1: Discovery & Import
        report(phase: .discovery, current: 0, total: 100, message: "Scanning folder...")
        var items = try await importer.importPhotos(from: sourceFolder) { current, total in
            report(phase: .discovery, current: current, total: total, message: "Reading photo metadata...")
        }

        guard !items.isEmpty else {
            return SessionData(sourceFolderPath: sourceFolder.path, targetSelectionCount: targetCount)
        }

        let totalPhotos = items.count

        // Phase 2: Previews & Thumbnails
        report(phase: .previews, current: 0, total: totalPhotos, message: "Generating lightweight previews...")
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            _ = try? previewPipeline.generatePreviewAndThumbnail(for: item)
            if (index + 1) % 20 == 0 || index + 1 == totalPhotos {
                report(phase: .previews, current: index + 1, total: totalPhotos, message: "Generated preview \(index + 1)/\(totalPhotos)")
            }
        }

        // Phase 3 & 4: Technical Quality & Face Analysis
        report(phase: .quality, current: 0, total: totalPhotos, message: "Analyzing technical quality & faces...")
        var faceCounts: [String: Int] = [:]

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }

            autoreleasepool {
                guard let previewCG = previewPipeline.loadPreviewCGImage(for: item) else {
                    return
                }

                // Technical quality
                let tech = qualityAnalyzer.analyze(cgImage: previewCG)
                items[index].metrics.rawSharpness = tech.rawSharpness
                items[index].metrics.meanLuminance = tech.meanLuminance
                items[index].metrics.shadowClipping = tech.shadowClipping
                items[index].metrics.highlightClipping = tech.highlightClipping
                items[index].metrics.dynamicRangeProxy = tech.dynamicRangeProxy
                items[index].metrics.contrastProxy = tech.contrastProxy
                items[index].metrics.compositionProxyScore = tech.compositionProxyScore
                items[index].metrics.isSevereUnderexposed = tech.isSevereUnderexposed
                items[index].metrics.isSevereOverexposed = tech.isSevereOverexposed

                // Perceptual hash
                items[index].perceptualHash = PerceptualHash.computeDHash(from: previewCG)

                // Face analysis
                let faceResult = faceAnalyzer.analyzeFaces(in: previewCG)
                items[index].metrics.faceCount = faceResult.faceCount
                items[index].metrics.rawFaceSharpness = faceResult.rawFaceSharpness
                items[index].metrics.averageEyeOpenness = faceResult.averageEyeOpenness
                items[index].metrics.faceQualityScore = faceResult.faceQualityScore
                faceCounts[item.id] = faceResult.faceCount

                // Scene classification
                let (category, conf) = classifier.classify(cgImage: previewCG, metadata: item.metadata, faceCount: faceResult.faceCount)
                items[index].category = category
                items[index].categoryConfidence = conf
            }

            if (index + 1) % 25 == 0 || index + 1 == totalPhotos {
                report(phase: .quality, current: index + 1, total: totalPhotos, message: "Quality analyzed \(index + 1)/\(totalPhotos)")
            }
        }

        // Phase 5: Duplicate & Burst Detection
        report(phase: .duplicates, current: 0, total: totalPhotos, message: "Detecting duplicates and bursts...")
        let exactDuplicates = duplicateDetector.detectExactDuplicates(items: items)
        for (index, item) in items.enumerated() {
            if let canonID = exactDuplicates[item.id] {
                items[index].isDuplicate = true
                items[index].duplicateOfID = canonID
                items[index].selectionState = .rejected
            }
            if item.metadata.isCorrupt {
                items[index].selectionState = .rejected
            }
        }

        let bursts = duplicateDetector.detectBursts(items: items)
        for burst in bursts {
            for (index, item) in items.enumerated() {
                if burst.memberIDs.contains(item.id) {
                    items[index].burstGroupID = burst.id
                    if item.id == burst.winnerID {
                        items[index].isBurstWinner = true
                    }
                }
            }
        }

        // Phase 6: Temporal Segmentation
        report(phase: .scenes, current: 0, total: totalPhotos, message: "Segmenting timeline into wedding moments...")
        let segments = temporalSegmenter.segment(items: items)
        for seg in segments {
            for (index, item) in items.enumerated() {
                if seg.photoIDs.contains(item.id) {
                    items[index].temporalSegmentID = seg.id
                }
            }
        }

        // Phase 7: Person Clustering
        report(phase: .people, current: 0, total: totalPhotos, message: "Clustering primary subjects...")
        let personClusters = personClusterer.clusterPersons(items: items, faceCounts: faceCounts)
        for cluster in personClusters {
            for (index, item) in items.enumerated() {
                if cluster.photoIDs.contains(item.id) {
                    items[index].personClusterIDs.append(cluster.id)
                }
            }
        }

        // Phase 8: Robust Scoring & Ranking
        report(phase: .ranking, current: 0, total: totalPhotos, message: "Scoring and ranking photos...")
        items = scorer.scorePhotos(items: items)

        // Phase 9: Diversity-aware MMR Target Selection
        report(phase: .selection, current: 0, total: totalPhotos, message: "Proposing optimal selection of \(targetCount)...")
        let selectionResult = selector.selectPhotos(
            items: items,
            segments: segments,
            bursts: bursts,
            targetCount: targetCount
        )
        items = selectionResult.updatedItems

        report(phase: .selection, current: totalPhotos, total: totalPhotos, message: selectionResult.message)

        return SessionData(
            sourceFolderPath: sourceFolder.path,
            targetSelectionCount: targetCount,
            photos: items,
            burstGroups: bursts,
            segments: segments,
            personClusters: personClusters,
            completedPhases: AnalysisPhase.allCases.map { $0.rawValue }
        )
    }
}
