import Foundation
import CoreGraphics
@preconcurrency import Vision

public enum AnalysisPhase: String, CaseIterable, Sendable {
    case discovery = "Importazione"
    case previews = "Anteprime"
    case quality = "Qualità e Volti"
    case duplicates = "Duplicati e Bursts"
    case scenes = "Segmentazione Scene"
    case classification = "Classificazione"
    case people = "Riconoscimento Persone"
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

public struct PhotoAnalysisResult: Sendable {
    public let id: String
    public let previewGenerated: Bool
    public let metrics: QualityMetrics
    public let perceptualHash: UInt64?
    public let featurePrint: VNFeaturePrintObservation?
    public let faces: [FaceInstance]
    public let category: WeddingCategory
    public let categoryConfidence: Double
    public let previewDurationSeconds: Double
    public let qualityDurationSeconds: Double
    public let faceDurationSeconds: Double
    public let featurePrintDurationSeconds: Double
    public var visionDurationSeconds: Double { faceDurationSeconds + featurePrintDurationSeconds }
    public let classificationDurationSeconds: Double
}

public actor AnalysisCoordinator {
    private var isPaused = false
    private var resumeContinuations: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
        releaseAllContinuations()
    }

    public func cancel() {
        isPaused = false
        releaseAllContinuations()
    }

    public func waitIfPaused() async throws {
        guard isPaused else {
            try Task.checkCancellation()
            return
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if self.isPaused {
                    self.resumeContinuations.append(cont)
                } else {
                    cont.resume()
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancel()
            }
        }

        try Task.checkCancellation()
    }

    private func releaseAllContinuations() {
        for cont in resumeContinuations {
            cont.resume()
        }
        resumeContinuations.removeAll()
    }

    public func getIsPaused() -> Bool {
        return isPaused
    }
}

public enum VisionExecutionMode: String, Codable, Sendable {
    case separate
    case combined
}

public actor AnalysisPipeline {
    private let hardware: HardwareCapabilities
    private let importer = PhotoImporter()
    private let previewPipeline: PreviewPipeline
    private let qualityAnalyzer = TechnicalQualityAnalyzer()
    private let faceIdentityRecognizer = FaceIdentityRecognizer()
    private let featurePrintProvider = FeaturePrintProvider()
    private let duplicateDetector = DuplicateAndBurstDetector()
    private let temporalSegmenter = TemporalSegmenter()
    private let classifier: MobileCLIPClassifier
    private let personClusterer = PersonClusterer()
    private let scorer = QualityScorer()
    private let selector = DiversitySelector()
    private let coordinator = AnalysisCoordinator()
    private let lazyFeaturePrint: Bool
    private let visionExecutionMode: VisionExecutionMode
    private let faceInputMaxPixelSize: Int
    private let sceneInputMaxPixelSize: Int
    private let sceneClassificationConcurrency: Int?

    public init(
        hardware: HardwareCapabilities = HardwareCapabilities(),
        previewPipeline: PreviewPipeline? = nil,
        customCacheDir: URL? = nil,
        lazyFeaturePrint: Bool = true,
        visionExecutionMode: VisionExecutionMode = .separate,
        faceInputMaxPixelSize: Int = 1000,
        sceneInputMaxPixelSize: Int = 1000,
        sceneClassificationConcurrency: Int? = nil
    ) {
        self.hardware = hardware
        self.previewPipeline = previewPipeline ?? PreviewPipeline(customCacheDirectory: customCacheDir)
        self.classifier = MobileCLIPClassifier(hardwareCapabilities: hardware)
        self.lazyFeaturePrint = lazyFeaturePrint
        self.visionExecutionMode = visionExecutionMode
        self.faceInputMaxPixelSize = faceInputMaxPixelSize
        self.sceneInputMaxPixelSize = sceneInputMaxPixelSize
        self.sceneClassificationConcurrency = sceneClassificationConcurrency
    }

    public func pause() async {
        await coordinator.pause()
    }

    public func resume() async {
        await coordinator.resume()
    }

    public func cancel() async {
        await coordinator.cancel()
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

        let wallStart = CFAbsoluteTimeGetCurrent()

        // Phase 1: Discovery & Import
        report(phase: .discovery, current: 0, total: 100, message: "Scanning folder...")
        let tDiscStart = CFAbsoluteTimeGetCurrent()
        var items = try await importer.importPhotos(from: sourceFolder) { current, total in
            report(phase: .discovery, current: current, total: total, message: "Reading photo metadata...")
        }
        let discoveryDuration = CFAbsoluteTimeGetCurrent() - tDiscStart
        let timeToFolderReady = CFAbsoluteTimeGetCurrent() - wallStart

        try Task.checkCancellation()

        guard !items.isEmpty else {
            return SessionData(sourceFolderPath: sourceFolder.path, targetSelectionCount: targetCount)
        }

        // Ensure deterministic chronological ordering by capture date
        items.sort {
            let dateA = $0.metadata.captureDate ?? $0.fileModificationDate
            let dateB = $1.metadata.captureDate ?? $1.fileModificationDate
            if dateA == dateB {
                return $0.fileName < $1.fileName
            }
            return dateA < dateB
        }

        let totalPhotos = items.count

        // Phase 2, 3 & 4: Concurrent Preview, Technical Quality, Faces & FeaturePrints
        report(phase: .quality, current: 0, total: totalPhotos, message: "Starting concurrent analysis...")
        
        let maxConcurrency = hardware.recommendedConcurrency
        var analysisResults: [String: PhotoAnalysisResult] = [:]
        analysisResults.reserveCapacity(totalPhotos)

        var itemIndex = 0
        let pipelineCoordinator = self.coordinator
        let previewPipe = self.previewPipeline
        let qualityAn = self.qualityAnalyzer
        let faceRec = self.faceIdentityRecognizer
        let fpProv = self.featurePrintProvider
        let mlClassifier = self.classifier
        let isLazyFP = self.lazyFeaturePrint
        let visMode = self.visionExecutionMode
        let facePixelSize = self.faceInputMaxPixelSize
        let scenePixelSize = self.sceneInputMaxPixelSize

        var timeToFirstThumbnail: Double = 0.0
        var timeToInteractiveGrid: Double = 0.0
        var timeToFirstAnalyzedPhoto: Double = 0.0

        let classifierGate: DispatchSemaphore?
        if let slots = self.sceneClassificationConcurrency {
            classifierGate = DispatchSemaphore(value: max(1, slots))
        } else {
            classifierGate = nil
        }

        // Progressive first-page thumbnail delivery: render first 24 thumbs immediately so grid is ready
        let firstBatchCount = min(24, totalPhotos)
        for i in 0..<firstBatchCount {
            _ = try? previewPipe.generatePreviewAndThumbnail(for: items[i])
            let elapsed = CFAbsoluteTimeGetCurrent() - wallStart
            if i == 0 && timeToFirstThumbnail == 0.0 {
                timeToFirstThumbnail = elapsed
            }
        }
        if timeToInteractiveGrid == 0.0 {
            timeToInteractiveGrid = CFAbsoluteTimeGetCurrent() - wallStart
        }

        var totalPreviewSeconds = 0.0
        var totalQualitySeconds = 0.0
        var totalFaceSeconds = 0.0
        var totalFeaturePrintSeconds = 0.0
        var totalVisionSeconds = 0.0
        var totalClassificationSeconds = 0.0

        try await withThrowingTaskGroup(of: PhotoAnalysisResult.self) { group in
            // Initial task submission up to maxConcurrency
            while itemIndex < min(maxConcurrency, totalPhotos) {
                let currentItem = items[itemIndex]
                itemIndex += 1
                group.addTask {
                    return try await Self.processItem(
                        item: currentItem,
                        coordinator: pipelineCoordinator,
                        previewPipeline: previewPipe,
                        qualityAnalyzer: qualityAn,
                        faceRecognizer: faceRec,
                        featurePrintProvider: fpProv,
                        classifier: mlClassifier,
                        lazyFeaturePrint: isLazyFP,
                        visionExecutionMode: visMode,
                        faceInputMaxPixelSize: facePixelSize,
                        sceneInputMaxPixelSize: scenePixelSize,
                        classifierGate: classifierGate
                    )
                }
            }

            var completedCount = 0
            while let result = try await group.next() {
                completedCount += 1
                analysisResults[result.id] = result
                totalPreviewSeconds += result.previewDurationSeconds
                totalQualitySeconds += result.qualityDurationSeconds
                totalFaceSeconds += result.faceDurationSeconds
                totalFeaturePrintSeconds += result.featurePrintDurationSeconds
                totalVisionSeconds += result.visionDurationSeconds
                totalClassificationSeconds += result.classificationDurationSeconds

                let elapsedSoFar = CFAbsoluteTimeGetCurrent() - wallStart
                if completedCount == 1 {
                    if timeToFirstThumbnail == 0.0 {
                        timeToFirstThumbnail = elapsedSoFar
                    }
                    timeToFirstAnalyzedPhoto = elapsedSoFar
                }
                if completedCount == min(24, totalPhotos) && timeToInteractiveGrid == 0.0 {
                    timeToInteractiveGrid = elapsedSoFar
                }

                if totalPhotos <= 20 || completedCount % 10 == 0 || completedCount == totalPhotos {
                    report(
                        phase: .quality,
                        current: completedCount,
                        total: totalPhotos,
                        message: "Analyzed \(completedCount)/\(totalPhotos) photos (\(maxConcurrency) concurrent workers)"
                    )
                }

                // Submit next item if available
                if itemIndex < totalPhotos {
                    let nextItem = items[itemIndex]
                    itemIndex += 1
                    group.addTask {
                        return try await Self.processItem(
                            item: nextItem,
                            coordinator: pipelineCoordinator,
                            previewPipeline: previewPipe,
                            qualityAnalyzer: qualityAn,
                            faceRecognizer: faceRec,
                            featurePrintProvider: fpProv,
                            classifier: mlClassifier,
                            lazyFeaturePrint: isLazyFP,
                            visionExecutionMode: visMode,
                            faceInputMaxPixelSize: facePixelSize,
                            sceneInputMaxPixelSize: scenePixelSize,
                            classifierGate: classifierGate
                        )
                    }
                }
            }
        }

        if timeToInteractiveGrid == 0.0 {
            timeToInteractiveGrid = CFAbsoluteTimeGetCurrent() - wallStart
        }

        try Task.checkCancellation()

        // Apply collected results safely without concurrent mutations
        var faceInstancesMap: [String: [FaceInstance]] = [:]
        var featurePrintsMap: [String: VNFeaturePrintObservation] = [:]

        for (idx, item) in items.enumerated() {
            guard let result = analysisResults[item.id] else { continue }
            items[idx].metrics = result.metrics
            items[idx].perceptualHash = result.perceptualHash
            items[idx].category = result.category
            items[idx].categoryConfidence = result.categoryConfidence
            faceInstancesMap[item.id] = result.faces
            if let fp = result.featurePrint {
                featurePrintsMap[item.id] = fp
            }
        }

        // Phase 5: FeaturePrint Distance Computation & Burst/Duplicate Detection
        let tBurstStart = CFAbsoluteTimeGetCurrent()
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

        // Compute FeaturePrint distance matrix between temporally proximate shots (within 4 seconds)
        var featurePrintDistances: [String: [String: Float]] = [:]
        var lazyFeaturePrintSeconds = 0.0

        if lazyFeaturePrint {
            // Lazy FeaturePrint generation: compute only for temporally proximate eligible pairs
            // where visual similarity could affect burst detection:
            // - within 4.0 seconds (and up to 20 forward items)
            // - burstUUID is nil or distinct
            // - dHash is missing OR dHash similarity < 0.85
            func getOrComputeFeaturePrint(for item: PhotoItem) -> VNFeaturePrintObservation? {
                if let existing = featurePrintsMap[item.id] {
                    return existing
                }
                guard let cg = previewPipeline.loadPreviewCGImage(for: item) else {
                    return nil
                }
                let tStart = CFAbsoluteTimeGetCurrent()
                let req = VNGenerateImageFeaturePrintRequest()
                let h = VNImageRequestHandler(cgImage: cg, options: [:])
                try? h.perform([req])
                lazyFeaturePrintSeconds += max(0.0, CFAbsoluteTimeGetCurrent() - tStart)
                if let obs = req.results?.first as? VNFeaturePrintObservation {
                    featurePrintsMap[item.id] = obs
                    return obs
                }
                return nil
            }

            for i in 0..<items.count {
                let itemA = items[i]
                let dateA = itemA.metadata.captureDate ?? itemA.fileModificationDate

                for j in (i + 1)..<min(items.count, i + 20) {
                    let itemB = items[j]
                    let dateB = itemB.metadata.captureDate ?? itemB.fileModificationDate
                    if abs(dateB.timeIntervalSince(dateA)) > 4.0 { break }

                    // Check if FeaturePrint is needed:
                    // If same EXIF burst UUID is present, burst is confirmed without visual similarity.
                    let sameBurstUUID = itemA.metadata.burstUUID != nil && itemA.metadata.burstUUID == itemB.metadata.burstUUID
                    if sameBurstUUID { continue }

                    // If dHash similarity is >= 0.85, visual similarity is already confirmed.
                    var needsFeaturePrint = true
                    if let hashA = itemA.perceptualHash, let hashB = itemB.perceptualHash {
                        let sim = PerceptualHash.similarity(hashA, hashB)
                        if sim >= 0.85 {
                            needsFeaturePrint = false
                        }
                    }

                    guard needsFeaturePrint else { continue }

                    guard let fpA = getOrComputeFeaturePrint(for: itemA),
                          let fpB = getOrComputeFeaturePrint(for: itemB) else { continue }

                    if let dist = featurePrintProvider.computeDistance(between: fpA, and: fpB) {
                        featurePrintDistances[itemA.id, default: [:]][itemB.id] = dist
                        featurePrintDistances[itemB.id, default: [:]][itemA.id] = dist
                    }
                }
            }
        } else {
            // Eager mode: compute distance matrix using precomputed featurePrintsMap
            for i in 0..<items.count {
                let itemA = items[i]
                guard let fpA = featurePrintsMap[itemA.id] else { continue }
                let dateA = itemA.metadata.captureDate ?? itemA.fileModificationDate

                for j in (i + 1)..<min(items.count, i + 20) {
                    let itemB = items[j]
                    let dateB = itemB.metadata.captureDate ?? itemB.fileModificationDate
                    if abs(dateB.timeIntervalSince(dateA)) > 4.0 { break }

                    guard let fpB = featurePrintsMap[itemB.id] else { continue }
                    if let dist = featurePrintProvider.computeDistance(between: fpA, and: fpB) {
                        featurePrintDistances[itemA.id, default: [:]][itemB.id] = dist
                        featurePrintDistances[itemB.id, default: [:]][itemA.id] = dist
                    }
                }
            }
        }

        totalFeaturePrintSeconds += lazyFeaturePrintSeconds

        let bursts = duplicateDetector.detectBursts(items: items, featurePrintDistances: featurePrintDistances)
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
        let burstDuration = CFAbsoluteTimeGetCurrent() - tBurstStart
        let timeToPreliminarySelection = CFAbsoluteTimeGetCurrent() - wallStart

        try Task.checkCancellation()

        // Phase 6: Temporal Segmentation
        let tSegStart = CFAbsoluteTimeGetCurrent()
        report(phase: .scenes, current: 0, total: totalPhotos, message: "Segmenting timeline into wedding moments...")
        let segments = temporalSegmenter.segment(items: items)
        for seg in segments {
            for (index, item) in items.enumerated() {
                if seg.photoIDs.contains(item.id) {
                    items[index].temporalSegmentID = seg.id
                }
            }
        }

        try Task.checkCancellation()

        // Phase 7: Real Person Recognition with Identity Embeddings
        report(phase: .people, current: 0, total: totalPhotos, message: "Clustering primary subjects via identity embeddings...")
        let personClusters = personClusterer.clusterPersonsWithIdentities(items: items, faceInstances: faceInstancesMap)
        for cluster in personClusters {
            for (index, item) in items.enumerated() {
                if cluster.photoIDs.contains(item.id) {
                    items[index].personClusterIDs.append(cluster.id)
                }
            }
        }
        let segAndClusteringDuration = CFAbsoluteTimeGetCurrent() - tSegStart

        try Task.checkCancellation()

        // Phase 8: Robust Scoring & Ranking
        let tRankStart = CFAbsoluteTimeGetCurrent()
        report(phase: .ranking, current: 0, total: totalPhotos, message: "Scoring and ranking photos...")
        items = scorer.scorePhotos(items: items)

        try Task.checkCancellation()

        // Phase 9: Diversity-aware MMR Target Selection
        report(phase: .selection, current: 0, total: totalPhotos, message: "Proposing optimal selection of \(targetCount)...")
        let selectionResult = selector.selectPhotos(
            items: items,
            segments: segments,
            bursts: bursts,
            targetCount: targetCount
        )
        items = selectionResult.updatedItems
        let rankingAndSelectionDuration = CFAbsoluteTimeGetCurrent() - tRankStart
        let timeToFinalSelection = CFAbsoluteTimeGetCurrent() - wallStart
        let totalWallClock = CFAbsoluteTimeGetCurrent() - wallStart

        let timings = PhaseTimings(
            discoverySeconds: Double(round(discoveryDuration * 100) / 100),
            previewGenerationSeconds: Double(round(totalPreviewSeconds * 100) / 100),
            faceDetectionSeconds: Double(round(totalFaceSeconds * 100) / 100),
            featurePrintSeconds: Double(round(totalFeaturePrintSeconds * 100) / 100),
            faceAndFeatureSeconds: Double(round(totalVisionSeconds * 100) / 100),
            qualityScoringSeconds: Double(round(totalQualitySeconds * 100) / 100),
            sceneClassificationSeconds: Double(round(totalClassificationSeconds * 100) / 100),
            burstAndDuplicateSeconds: Double(round(burstDuration * 100) / 100),
            clusteringAndSegmentationSeconds: Double(round(segAndClusteringDuration * 100) / 100),
            rankingAndSelectionSeconds: Double(round(rankingAndSelectionDuration * 100) / 100),
            sessionPersistenceSeconds: 0.0,
            totalWallClockSeconds: Double(round(totalWallClock * 100) / 100)
        )

        let readinessMetrics = PipelineReadinessMetrics(
            timeToFolderReady: Double(round(timeToFolderReady * 100) / 100),
            timeToFirstThumbnail: Double(round(timeToFirstThumbnail * 100) / 100),
            timeToInteractiveGrid: Double(round(timeToInteractiveGrid * 100) / 100),
            timeToFirstAnalyzedPhoto: Double(round(timeToFirstAnalyzedPhoto * 100) / 100),
            timeToPreliminarySelection: Double(round(timeToPreliminarySelection * 100) / 100),
            timeToFinalSelection: Double(round(timeToFinalSelection * 100) / 100)
        )

        report(phase: .selection, current: totalPhotos, total: totalPhotos, message: selectionResult.message)

        return SessionData(
            sourceFolderPath: sourceFolder.path,
            targetSelectionCount: targetCount,
            photos: items,
            burstGroups: bursts,
            segments: segments,
            personClusters: personClusters,
            completedPhases: AnalysisPhase.allCases.map { $0.rawValue },
            phaseTimings: timings,
            pipelineReadinessMetrics: readinessMetrics
        )
    }

    private static func processItem(
        item: PhotoItem,
        coordinator: AnalysisCoordinator,
        previewPipeline: PreviewPipeline,
        qualityAnalyzer: TechnicalQualityAnalyzer,
        faceRecognizer: FaceIdentityRecognizer,
        featurePrintProvider: FeaturePrintProvider,
        classifier: MobileCLIPClassifier,
        lazyFeaturePrint: Bool,
        visionExecutionMode: VisionExecutionMode,
        faceInputMaxPixelSize: Int,
        sceneInputMaxPixelSize: Int,
        classifierGate: DispatchSemaphore? = nil
    ) async throws -> PhotoAnalysisResult {
        // Handle pause and cancellation
        try await coordinator.waitIfPaused()
        try Task.checkCancellation()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = autoreleasepool { () -> PhotoAnalysisResult in
                    let tPrevStart = CFAbsoluteTimeGetCurrent()
                    let previewResult = try? previewPipeline.generatePreviewAndThumbnailWithImage(for: item)
                    let tPrevEnd = CFAbsoluteTimeGetCurrent()
                    let prevDuration = max(0.0, tPrevEnd - tPrevStart)

                    let previewCG = previewResult?.previewImage ?? previewPipeline.loadPreviewCGImage(for: item)
                    guard let previewCG = previewCG else {
                        return PhotoAnalysisResult(
                            id: item.id,
                            previewGenerated: false,
                            metrics: item.metrics,
                            perceptualHash: nil,
                            featurePrint: nil,
                            faces: [],
                            category: item.category,
                            categoryConfidence: 0.3,
                            previewDurationSeconds: prevDuration,
                            qualityDurationSeconds: 0,
                            faceDurationSeconds: 0,
                            featurePrintDurationSeconds: 0,
                            classificationDurationSeconds: 0
                        )
                    }

                    // Technical quality metrics
                    let tQualStart = CFAbsoluteTimeGetCurrent()
                    let tech = qualityAnalyzer.analyze(cgImage: previewCG)
                    var metrics = item.metrics
                    metrics.rawSharpness = tech.rawSharpness
                    metrics.meanLuminance = tech.meanLuminance
                    metrics.shadowClipping = tech.shadowClipping
                    metrics.highlightClipping = tech.highlightClipping
                    metrics.dynamicRangeProxy = tech.dynamicRangeProxy
                    metrics.contrastProxy = tech.contrastProxy
                    metrics.compositionProxyScore = tech.compositionProxyScore
                    metrics.isSevereUnderexposed = tech.isSevereUnderexposed
                    metrics.isSevereOverexposed = tech.isSevereOverexposed

                    // Perceptual dHash
                    let pHash = PerceptualHash.computeDHash(from: previewCG)
                    let tQualEnd = CFAbsoluteTimeGetCurrent()
                    let qualDuration = max(0.0, tQualEnd - tQualStart)

                    // Dedicated downscaled Vision inputs (if configured smaller than 1000px)
                    let faceCG: CGImage
                    if faceInputMaxPixelSize < 1000, let down = previewPipeline.downsample(cgImage: previewCG, maxPixelSize: faceInputMaxPixelSize) {
                        faceCG = down
                    } else {
                        faceCG = previewCG
                    }

                    let sceneCG: CGImage
                    if sceneInputMaxPixelSize < 1000, let down = previewPipeline.downsample(cgImage: previewCG, maxPixelSize: sceneInputMaxPixelSize) {
                        sceneCG = down
                    } else {
                        sceneCG = previewCG
                    }

                    var faces: [FaceInstance] = []
                    var faceDuration: Double = 0.0
                    var (category, conf): (WeddingCategory, Double) = (item.category, 0.3)
                    var classDuration: Double = 0.0

                    if visionExecutionMode == .combined && !classifier.isCoreMLModelLoaded && faceCG === sceneCG {
                        // Combined perform([faceRequest, sceneRequest]) restoration
                        let handler = VNImageRequestHandler(cgImage: faceCG, options: [:])
                        let faceRequest = VNDetectFaceLandmarksRequest()
                        let sceneRequest = VNClassifyImageRequest()
                        let tVisionStart = CFAbsoluteTimeGetCurrent()
                        if let gate = classifierGate {
                            gate.wait()
                            try? handler.perform([faceRequest, sceneRequest])
                            gate.signal()
                        } else {
                            try? handler.perform([faceRequest, sceneRequest])
                        }
                        let tVisionEnd = CFAbsoluteTimeGetCurrent()
                        let totalVisionDur = max(0.0, tVisionEnd - tVisionStart)

                        faces = faceRecognizer.processObservations(faceRequest.results ?? [])
                        metrics.faceCount = faces.count
                        if !faces.isEmpty {
                            let totalQuality = faces.reduce(0.0) { $0 + $1.faceQuality }
                            metrics.faceQualityScore = totalQuality / Double(faces.count)
                            let totalEyes = faces.reduce(0.0) { $0 + $1.eyeOpenness }
                            metrics.averageEyeOpenness = totalEyes / Double(faces.count)
                            metrics.rawFaceSharpness = tech.rawSharpness * 1.2
                        }

                        let res = classifier.classifyWithObservations(sceneRequest.results, metadata: item.metadata, faceCount: faces.count)
                        category = res.0
                        conf = res.1

                        faceDuration = totalVisionDur * 0.5
                        classDuration = totalVisionDur * 0.5
                    } else {
                        // Separate perform() calls
                        // 1. Face Detection & Identity Landmarks
                        let tFaceStart = CFAbsoluteTimeGetCurrent()
                        let faceHandler = VNImageRequestHandler(cgImage: faceCG, options: [:])
                        let faceRequest = VNDetectFaceLandmarksRequest()
                        try? faceHandler.perform([faceRequest])
                        faces = faceRecognizer.processObservations(faceRequest.results ?? [])
                        metrics.faceCount = faces.count
                        if !faces.isEmpty {
                            let totalQuality = faces.reduce(0.0) { $0 + $1.faceQuality }
                            metrics.faceQualityScore = totalQuality / Double(faces.count)
                            let totalEyes = faces.reduce(0.0) { $0 + $1.eyeOpenness }
                            metrics.averageEyeOpenness = totalEyes / Double(faces.count)
                            metrics.rawFaceSharpness = tech.rawSharpness * 1.2
                        }
                        let tFaceEnd = CFAbsoluteTimeGetCurrent()
                        faceDuration = max(0.0, tFaceEnd - tFaceStart)

                        // 3. Scene & Concept Classification
                        let tClassStart = CFAbsoluteTimeGetCurrent()
                        if classifier.isCoreMLModelLoaded {
                            let res = classifier.classifyWithBackend(cgImage: sceneCG, metadata: item.metadata, faceCount: faces.count)
                            category = res.category
                            conf = res.confidence
                        } else {
                            let sceneHandler = (sceneCG === faceCG) ? faceHandler : VNImageRequestHandler(cgImage: sceneCG, options: [:])
                            let sceneRequest = VNClassifyImageRequest()
                            if let gate = classifierGate {
                                gate.wait()
                                try? sceneHandler.perform([sceneRequest])
                                gate.signal()
                            } else {
                                try? sceneHandler.perform([sceneRequest])
                            }
                            let res = classifier.classifyWithObservations(sceneRequest.results, metadata: item.metadata, faceCount: faces.count)
                            category = res.0
                            conf = res.1
                        }
                        let tClassEnd = CFAbsoluteTimeGetCurrent()
                        classDuration = max(0.0, tClassEnd - tClassStart)
                    }

                    // 2. FeaturePrint Generation (eager mode only)
                    var fPrint: VNFeaturePrintObservation? = nil
                    var fpDuration: Double = 0.0
                    if !lazyFeaturePrint {
                        let tFpStart = CFAbsoluteTimeGetCurrent()
                        let fpHandler = VNImageRequestHandler(cgImage: previewCG, options: [:])
                        let fpRequest = VNGenerateImageFeaturePrintRequest()
                        try? fpHandler.perform([fpRequest])
                        fPrint = fpRequest.results?.first as? VNFeaturePrintObservation
                        let tFpEnd = CFAbsoluteTimeGetCurrent()
                        fpDuration = max(0.0, tFpEnd - tFpStart)
                    }

                    return PhotoAnalysisResult(
                        id: item.id,
                        previewGenerated: true,
                        metrics: metrics,
                        perceptualHash: pHash,
                        featurePrint: fPrint,
                        faces: faces,
                        category: category,
                        categoryConfidence: conf,
                        previewDurationSeconds: prevDuration,
                        qualityDurationSeconds: qualDuration,
                        faceDurationSeconds: faceDuration,
                        featurePrintDurationSeconds: fpDuration,
                        classificationDurationSeconds: classDuration
                    )
                }
                continuation.resume(returning: result)
            }
        }
    }
}
