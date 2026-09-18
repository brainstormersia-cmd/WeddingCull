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

public enum PipelineArchitecture: String, Codable, Sendable {
    case unified
    case twoStage
}

actor BoundedChannel<T: Sendable> {
    private let capacity: Int
    private var buffer: [T] = []
    private var isClosed = false
    private var readWaiters: [CheckedContinuation<T?, Never>] = []
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func send(_ element: T) async {
        if isClosed { return }
        while buffer.count >= capacity && !isClosed {
            await withCheckedContinuation { cont in
                writeWaiters.append(cont)
            }
        }
        if isClosed { return }
        buffer.append(element)
        if let reader = readWaiters.first {
            readWaiters.removeFirst()
            let val = buffer.removeFirst()
            reader.resume(returning: val)
            if let writer = writeWaiters.first {
                writeWaiters.removeFirst()
                writer.resume()
            }
        }
    }

    func receive() async -> T? {
        if !buffer.isEmpty {
            let val = buffer.removeFirst()
            if let writer = writeWaiters.first {
                writeWaiters.removeFirst()
                writer.resume()
            }
            return val
        }
        if isClosed {
            return nil
        }
        return await withCheckedContinuation { cont in
            readWaiters.append(cont)
        }
    }

    func close() {
        isClosed = true
        while !readWaiters.isEmpty {
            let reader = readWaiters.removeFirst()
            reader.resume(returning: nil)
        }
        while !writeWaiters.isEmpty {
            let writer = writeWaiters.removeFirst()
            writer.resume()
        }
    }
}

actor PhotoItemFeeder {
    private let items: [PhotoItem]
    private var index = 0

    init(items: [PhotoItem]) {
        self.items = items
    }

    func nextItem() -> PhotoItem? {
        guard index < items.count else { return nil }
        let item = items[index]
        index += 1
        return item
    }
}
typealias StageAFeeder = PhotoItemFeeder

actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) {
        self.permits = max(1, permits)
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        } else {
            permits += 1
        }
    }
}

public struct StageAOutput: Sendable {
    public let item: PhotoItem
    public let previewDurationSeconds: Double
    public let qualityDurationSeconds: Double
    public let faceDurationSeconds: Double
    public let featurePrintDurationSeconds: Double
    public let previewCG: CGImage?
    public let faceCG: CGImage?
    public let sceneCG: CGImage?
    public let metrics: QualityMetrics
    public let perceptualHash: UInt64?
    public let featurePrint: VNFeaturePrintObservation?
    public let faces: [FaceInstance]
    public let cachedRecord: CachedAnalysisRecord?
}
public typealias StageAResult = StageAOutput

public struct AnalysisCollectionSummary: Sendable {
    public let items: [PhotoItem]
    public let analysisResults: [String: PhotoAnalysisResult]
    public let faceInstancesMap: [String: [FaceInstance]]
    public let featurePrintsMap: [String: VNFeaturePrintObservation]
    public let completedCount: Int
    public let totalPreviewSeconds: Double
    public let totalQualitySeconds: Double
    public let totalFaceSeconds: Double
    public let totalFeaturePrintSeconds: Double
    public let totalVisionSeconds: Double
    public let totalClassificationSeconds: Double
    public let timeToFirstThumbnail: Double
    public let timeToInteractiveGrid: Double
    public let timeToFirstAnalyzedPhoto: Double
}

actor AnalysisCollector {
    private var items: [PhotoItem]
    private var itemIndices: [String: Int]
    private var analysisResults: [String: PhotoAnalysisResult] = [:]
    private var faceInstancesMap: [String: [FaceInstance]] = [:]
    private var featurePrintsMap: [String: VNFeaturePrintObservation] = [:]
    private var completedCount: Int = 0
    private var thumbnailCount: Int = 0
    private var totalPreviewSeconds: Double = 0.0
    private var totalQualitySeconds: Double = 0.0
    private var totalFaceSeconds: Double = 0.0
    private var totalFeaturePrintSeconds: Double = 0.0
    private var totalVisionSeconds: Double = 0.0
    private var totalClassificationSeconds: Double = 0.0
    private var timeToFirstThumbnail: Double = 0.0
    private var timeToInteractiveGrid: Double = 0.0
    private var timeToFirstAnalyzedPhoto: Double = 0.0
    private var updateBatch: [PhotoItem] = []

    private let totalPhotos: Int
    private let wallStart: CFAbsoluteTime
    private let progressMessage: (@Sendable (Int, Int) -> String)?
    private let onPhotosUpdated: (@Sendable ([PhotoItem]) -> Void)?
    private let progressReporter: (@Sendable (AnalysisPhase, Int, Int, String) -> Void)?

    init(
        items: [PhotoItem],
        wallStart: CFAbsoluteTime,
        progressMessage: (@Sendable (Int, Int) -> String)?,
        onPhotosUpdated: (@Sendable ([PhotoItem]) -> Void)?,
        progressReporter: (@Sendable (AnalysisPhase, Int, Int, String) -> Void)?
    ) {
        self.items = items
        var indices: [String: Int] = [:]
        indices.reserveCapacity(items.count)
        for (i, item) in items.enumerated() {
            indices[item.id] = i
        }
        self.itemIndices = indices
        self.analysisResults.reserveCapacity(items.count)
        self.faceInstancesMap.reserveCapacity(items.count)
        self.featurePrintsMap.reserveCapacity(items.count)
        self.totalPhotos = items.count
        self.wallStart = wallStart
        self.progressMessage = progressMessage
        self.onPhotosUpdated = onPhotosUpdated
        self.progressReporter = progressReporter
    }

    func recordThumbnailGenerated(for id: String) {
        thumbnailCount += 1
        let elapsedSoFar = CFAbsoluteTimeGetCurrent() - wallStart
        if timeToFirstThumbnail == 0.0 {
            timeToFirstThumbnail = elapsedSoFar
        }
        if thumbnailCount >= min(24, totalPhotos) && timeToInteractiveGrid == 0.0 {
            timeToInteractiveGrid = elapsedSoFar
        }
    }

    func collect(_ res: PhotoAnalysisResult) {
        completedCount += 1
        analysisResults[res.id] = res
        totalPreviewSeconds += res.previewDurationSeconds
        totalQualitySeconds += res.qualityDurationSeconds
        totalFaceSeconds += res.faceDurationSeconds
        totalFeaturePrintSeconds += res.featurePrintDurationSeconds
        totalVisionSeconds += res.visionDurationSeconds
        totalClassificationSeconds += res.classificationDurationSeconds

        faceInstancesMap[res.id] = res.faces
        if let fp = res.featurePrint {
            featurePrintsMap[res.id] = fp
        }

        let elapsedSoFar = CFAbsoluteTimeGetCurrent() - wallStart
        if timeToFirstThumbnail == 0.0 {
            timeToFirstThumbnail = elapsedSoFar
        }
        if timeToFirstAnalyzedPhoto == 0.0 {
            timeToFirstAnalyzedPhoto = elapsedSoFar
        }
        if timeToInteractiveGrid == 0.0 && (completedCount >= min(24, totalPhotos) || thumbnailCount >= min(24, totalPhotos)) {
            timeToInteractiveGrid = elapsedSoFar
        }

        if let idx = itemIndices[res.id] {
            items[idx].metrics = res.metrics
            items[idx].perceptualHash = res.perceptualHash
            items[idx].category = res.category
            items[idx].categoryConfidence = res.categoryConfidence
            updateBatch.append(items[idx])
        }

        if updateBatch.count >= 10 || completedCount == totalPhotos {
            if !updateBatch.isEmpty {
                onPhotosUpdated?(updateBatch)
                updateBatch.removeAll(keepingCapacity: true)
            }
        }

        if totalPhotos <= 20 || completedCount % 10 == 0 || completedCount == totalPhotos {
            let msg = progressMessage?(completedCount, totalPhotos) ?? "Analyzed \(completedCount)/\(totalPhotos) photos"
            progressReporter?(.quality, completedCount, totalPhotos, msg)
        }
    }

    func finalize() -> AnalysisCollectionSummary {
        if timeToInteractiveGrid == 0.0 {
            timeToInteractiveGrid = CFAbsoluteTimeGetCurrent() - wallStart
        }
        return AnalysisCollectionSummary(
            items: items,
            analysisResults: analysisResults,
            faceInstancesMap: faceInstancesMap,
            featurePrintsMap: featurePrintsMap,
            completedCount: completedCount,
            totalPreviewSeconds: totalPreviewSeconds,
            totalQualitySeconds: totalQualitySeconds,
            totalFaceSeconds: totalFaceSeconds,
            totalFeaturePrintSeconds: totalFeaturePrintSeconds,
            totalVisionSeconds: totalVisionSeconds,
            totalClassificationSeconds: totalClassificationSeconds,
            timeToFirstThumbnail: timeToFirstThumbnail,
            timeToInteractiveGrid: timeToInteractiveGrid,
            timeToFirstAnalyzedPhoto: timeToFirstAnalyzedPhoto
        )
    }
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
    private let pipelineArchitecture: PipelineArchitecture
    private let stageAWorkers: Int
    private let stageBWorkers: Int
    private let queueCapacity: Int

    public init(
        hardware: HardwareCapabilities = HardwareCapabilities(),
        previewPipeline: PreviewPipeline? = nil,
        customCacheDir: URL? = nil,
        lazyFeaturePrint: Bool = true,
        visionExecutionMode: VisionExecutionMode = .separate,
        faceInputMaxPixelSize: Int = 1000,
        sceneInputMaxPixelSize: Int = 1000,
        sceneClassificationConcurrency: Int? = nil,
        pipelineArchitecture: PipelineArchitecture = .unified,
        stageAWorkers: Int? = nil,
        stageBWorkers: Int? = nil,
        queueCapacity: Int = 8,
        forceVisionFallback: Bool = false
    ) {
        self.hardware = hardware
        self.previewPipeline = previewPipeline ?? PreviewPipeline(customCacheDirectory: customCacheDir)
        self.classifier = MobileCLIPClassifier(hardwareCapabilities: hardware, forceVisionFallback: forceVisionFallback)
        self.lazyFeaturePrint = lazyFeaturePrint
        self.visionExecutionMode = visionExecutionMode
        self.faceInputMaxPixelSize = faceInputMaxPixelSize
        self.sceneInputMaxPixelSize = sceneInputMaxPixelSize
        self.sceneClassificationConcurrency = sceneClassificationConcurrency
        self.pipelineArchitecture = pipelineArchitecture
        self.stageAWorkers = stageAWorkers ?? hardware.recommendedConcurrency
        self.stageBWorkers = stageBWorkers ?? (sceneClassificationConcurrency ?? 1)
        self.queueCapacity = max(1, queueCapacity)
    }

    public var classifierBackendUsed: ClassificationBackend {
        return classifier.lastUsedBackend
    }

    public var isCoreMLModelLoaded: Bool {
        return classifier.isCoreMLModelLoaded
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
        progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil,
        onPhotosDiscovered: (@Sendable ([PhotoItem]) -> Void)? = nil,
        onPhotosUpdated: (@Sendable ([PhotoItem]) -> Void)? = nil
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

        // Ensure deterministic chronological ordering by capture date (strict total order)
        items.sort {
            let dateA = $0.metadata.captureDate ?? $0.fileModificationDate
            let dateB = $1.metadata.captureDate ?? $1.fileModificationDate
            if dateA != dateB {
                return dateA < dateB
            }
            if $0.fileName != $1.fileName {
                return $0.fileName < $1.fileName
            }
            return $0.id < $1.id
        }

        // Publish discovered photos immediately for progressive UI display
        onPhotosDiscovered?(items)

        let totalPhotos = items.count

        // Phase 2, 3 & 4: Concurrent Preview, Technical Quality, Faces & FeaturePrints
        report(phase: .quality, current: 0, total: totalPhotos, message: "Starting concurrent analysis...")
        
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

        let summary: AnalysisCollectionSummary

        if self.pipelineArchitecture == .twoStage {
            // True Two-Stage Producer-Consumer Pipeline:
            // Stage A: Preview + Quality + Face Recognition -> BoundedChannel (backpressure)
            // Stage B: Dedicated Scene Classification Workers
            let channel = BoundedChannel<StageAOutput>(capacity: self.queueCapacity)
            let stageAWorkerCount = max(1, self.stageAWorkers)
            let stageBWorkerCount = max(1, self.stageBWorkers)
            let queueCap = self.queueCapacity

            let collector = AnalysisCollector(
                items: items,
                wallStart: wallStart,
                progressMessage: { count, total in
                    "Two-stage analyzed \(count)/\(total) photos (A: \(stageAWorkerCount)w, B: \(stageBWorkerCount)w, Q: \(queueCap))"
                },
                onPhotosUpdated: onPhotosUpdated,
                progressReporter: report
            )

            let feeder = PhotoItemFeeder(items: items)
            let stageATask = Task {
                await withTaskGroup(of: Void.self) { aGroup in
                    for _ in 0..<stageAWorkerCount {
                        aGroup.addTask {
                            while let item = await feeder.nextItem() {
                                if Task.isCancelled { break }
                                do {
                                    let stageAOut = try await Self.processStageA(
                                        item: item,
                                        coordinator: pipelineCoordinator,
                                        previewPipeline: previewPipe,
                                        qualityAnalyzer: qualityAn,
                                        faceRecognizer: faceRec,
                                        featurePrintProvider: fpProv,
                                        lazyFeaturePrint: isLazyFP,
                                        faceInputMaxPixelSize: facePixelSize,
                                        sceneInputMaxPixelSize: scenePixelSize,
                                        expectedBackend: mlClassifier.targetBackend.rawValue,
                                        onThumbnailReady: { id in
                                            Task { await collector.recordThumbnailGenerated(for: id) }
                                        }
                                    )
                                    await channel.send(stageAOut)
                                } catch {
                                    break
                                }
                            }
                        }
                    }
                }
                await channel.close()
            }

            let task = stageATask
            summary = try await withTaskCancellationHandler {
                await withTaskGroup(of: Void.self) { bGroup in
                    for _ in 0..<stageBWorkerCount {
                        bGroup.addTask {
                            while let stageAOut = await channel.receive() {
                                if Task.isCancelled { break }
                                do {
                                    let res = try await Self.processStageB(
                                        stageA: stageAOut,
                                        coordinator: pipelineCoordinator,
                                        classifier: mlClassifier,
                                        previewPipeline: previewPipe
                                    )
                                    await collector.collect(res)
                                } catch {
                                    break
                                }
                            }
                        }
                    }
                }
                _ = try await task.value
                return await collector.finalize()
            } onCancel: {
                task.cancel()
                Task {
                    await channel.close()
                }
            }
        } else {
            // Unified Execution Engine with progressive stream
            let maxConcurrency = hardware.recommendedConcurrency
            let classifierGate: AsyncSemaphore?
            if let slots = self.sceneClassificationConcurrency {
                classifierGate = AsyncSemaphore(permits: max(1, slots))
            } else {
                classifierGate = nil
            }

            let collector = AnalysisCollector(
                items: items,
                wallStart: wallStart,
                progressMessage: { count, total in
                    "Analyzed \(count)/\(total) photos (\(maxConcurrency) concurrent workers)"
                },
                onPhotosUpdated: onPhotosUpdated,
                progressReporter: report
            )

            let feeder = PhotoItemFeeder(items: items)
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<maxConcurrency {
                    group.addTask {
                        while let currentItem = await feeder.nextItem() {
                            if Task.isCancelled { break }
                            do {
                                let res = try await Self.processItem(
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
                                    classifierGate: classifierGate,
                                    onThumbnailReady: { id in
                                        Task { await collector.recordThumbnailGenerated(for: id) }
                                    }
                                )
                                await collector.collect(res)
                            } catch {
                                break
                            }
                        }
                    }
                }
            }

            summary = await collector.finalize()
        }

        try Task.checkCancellation()

        items = summary.items
        var faceInstancesMap = summary.faceInstancesMap
        var featurePrintsMap = summary.featurePrintsMap
        let timeToFirstThumbnail = summary.timeToFirstThumbnail
        let timeToInteractiveGrid = summary.timeToInteractiveGrid
        let timeToFirstAnalyzedPhoto = summary.timeToFirstAnalyzedPhoto
        let totalPreviewSeconds = summary.totalPreviewSeconds
        let totalQualitySeconds = summary.totalQualitySeconds
        let totalFaceSeconds = summary.totalFaceSeconds
        var totalFeaturePrintSeconds = summary.totalFeaturePrintSeconds
        let totalVisionSeconds = summary.totalVisionSeconds
        let totalClassificationSeconds = summary.totalClassificationSeconds

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

    private static func processStageA(
        item: PhotoItem,
        coordinator: AnalysisCoordinator,
        previewPipeline: PreviewPipeline,
        qualityAnalyzer: TechnicalQualityAnalyzer,
        faceRecognizer: FaceIdentityRecognizer,
        featurePrintProvider: FeaturePrintProvider,
        lazyFeaturePrint: Bool,
        faceInputMaxPixelSize: Int,
        sceneInputMaxPixelSize: Int,
        expectedBackend: String? = nil,
        onThumbnailReady: (@Sendable (String) -> Void)? = nil
    ) async throws -> StageAOutput {
        try await coordinator.waitIfPaused()
        try Task.checkCancellation()

        let cached = previewPipeline.loadAnalysisRecord(for: item, expectedBackend: expectedBackend)

        let tPrevStart = CFAbsoluteTimeGetCurrent()
        let previewResult = try? await previewPipeline.generatePreviewAndThumbnailWithImage(for: item)
        let tPrevEnd = CFAbsoluteTimeGetCurrent()
        let prevDuration = max(0.0, tPrevEnd - tPrevStart)

        onThumbnailReady?(item.id)

        if let cached = cached {
            var fPrint: VNFeaturePrintObservation? = nil
            if let fpData = cached.featurePrintData {
                fPrint = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: fpData)
            }
            return StageAOutput(
                item: item,
                previewDurationSeconds: prevDuration,
                qualityDurationSeconds: 0.0,
                faceDurationSeconds: 0.0,
                featurePrintDurationSeconds: 0.0,
                previewCG: previewResult?.previewImage ?? previewPipeline.loadPreviewCGImage(for: item),
                faceCG: nil,
                sceneCG: nil,
                metrics: cached.metrics,
                perceptualHash: cached.perceptualHash,
                featurePrint: fPrint,
                faces: cached.faces,
                cachedRecord: cached
            )
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let out = autoreleasepool { () -> StageAOutput in
                    let previewCG = previewResult?.previewImage ?? previewPipeline.loadPreviewCGImage(for: item)
                    guard let previewCG = previewCG else {
                        return StageAOutput(
                            item: item,
                            previewDurationSeconds: prevDuration,
                            qualityDurationSeconds: 0,
                            faceDurationSeconds: 0,
                            featurePrintDurationSeconds: 0,
                            previewCG: nil,
                            faceCG: nil,
                            sceneCG: nil,
                            metrics: item.metrics,
                            perceptualHash: nil,
                            featurePrint: nil,
                            faces: [],
                            cachedRecord: nil
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

                    // Dedicated downscaled Vision inputs
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

                    // Face Detection & Identity Landmarks
                    let tFaceStart = CFAbsoluteTimeGetCurrent()
                    let faceHandler = VNImageRequestHandler(cgImage: faceCG, options: [:])
                    let faceRequest = VNDetectFaceLandmarksRequest()
                    try? faceHandler.perform([faceRequest])
                    let faces = faceRecognizer.processObservations(faceRequest.results ?? [])
                    metrics.faceCount = faces.count
                    if !faces.isEmpty {
                        let totalQuality = faces.reduce(0.0) { $0 + $1.faceQuality }
                        metrics.faceQualityScore = totalQuality / Double(faces.count)
                        let totalEyes = faces.reduce(0.0) { $0 + $1.eyeOpenness }
                        metrics.averageEyeOpenness = totalEyes / Double(faces.count)
                        metrics.rawFaceSharpness = tech.rawSharpness * 1.2
                    }
                    let tFaceEnd = CFAbsoluteTimeGetCurrent()
                    let faceDuration = max(0.0, tFaceEnd - tFaceStart)

                    // FeaturePrint (eager mode only)
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

                    return StageAOutput(
                        item: item,
                        previewDurationSeconds: prevDuration,
                        qualityDurationSeconds: qualDuration,
                        faceDurationSeconds: faceDuration,
                        featurePrintDurationSeconds: fpDuration,
                        previewCG: previewCG,
                        faceCG: faceCG,
                        sceneCG: sceneCG,
                        metrics: metrics,
                        perceptualHash: pHash,
                        featurePrint: fPrint,
                        faces: faces,
                        cachedRecord: nil
                    )
                }
                continuation.resume(returning: out)
            }
        }
    }

    private static func processStageB(
        stageA: StageAOutput,
        coordinator: AnalysisCoordinator,
        classifier: MobileCLIPClassifier,
        previewPipeline: PreviewPipeline? = nil,
        classifierGate: AsyncSemaphore? = nil
    ) async throws -> PhotoAnalysisResult {
        try await coordinator.waitIfPaused()
        try Task.checkCancellation()

        if let cached = stageA.cachedRecord {
            return PhotoAnalysisResult(
                id: stageA.item.id,
                previewGenerated: true,
                metrics: stageA.metrics,
                perceptualHash: stageA.perceptualHash,
                featurePrint: stageA.featurePrint,
                faces: stageA.faces,
                category: cached.category,
                categoryConfidence: cached.categoryConfidence,
                previewDurationSeconds: stageA.previewDurationSeconds,
                qualityDurationSeconds: stageA.qualityDurationSeconds,
                faceDurationSeconds: stageA.faceDurationSeconds,
                featurePrintDurationSeconds: stageA.featurePrintDurationSeconds,
                classificationDurationSeconds: 0.0
            )
        }

        guard let sceneCG = stageA.sceneCG ?? stageA.previewCG else {
            return PhotoAnalysisResult(
                id: stageA.item.id,
                previewGenerated: false,
                metrics: stageA.metrics,
                perceptualHash: stageA.perceptualHash,
                featurePrint: stageA.featurePrint,
                faces: stageA.faces,
                category: stageA.item.category,
                categoryConfidence: 0.3,
                previewDurationSeconds: stageA.previewDurationSeconds,
                qualityDurationSeconds: stageA.qualityDurationSeconds,
                faceDurationSeconds: stageA.faceDurationSeconds,
                featurePrintDurationSeconds: stageA.featurePrintDurationSeconds,
                classificationDurationSeconds: 0
            )
        }

        if let gate = classifierGate {
            await gate.acquire()
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = autoreleasepool { () -> PhotoAnalysisResult in
                    let tClassStart = CFAbsoluteTimeGetCurrent()
                    var category = stageA.item.category
                    var conf = 0.3
                    var scores: [WeddingCategory: Double] = [:]

                    if classifier.isCoreMLModelLoaded {
                        let res = classifier.classifyWithBackend(cgImage: sceneCG, metadata: stageA.item.metadata, faceCount: stageA.faces.count)
                        category = res.category
                        conf = res.confidence
                        scores[res.category] = res.confidence
                    } else {
                        let sceneHandler = VNImageRequestHandler(cgImage: sceneCG, options: [:])
                        let sceneRequest = VNClassifyImageRequest()
                        try? sceneHandler.perform([sceneRequest])
                        let res = classifier.classifyWithObservations(sceneRequest.results, metadata: stageA.item.metadata, faceCount: stageA.faces.count)
                        category = res.0
                        conf = res.1
                        scores[res.0] = res.1
                    }
                    let tClassEnd = CFAbsoluteTimeGetCurrent()
                    let classDuration = max(0.0, tClassEnd - tClassStart)

                    if let gate = classifierGate {
                        Task { await gate.release() }
                    }

                    // Save authoritative analysis record for deterministic warm cache reuse
                    var fpData: Data? = nil
                    if let fp = stageA.featurePrint {
                        fpData = try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true)
                    }
                    let record = CachedAnalysisRecord(
                        photoID: stageA.item.id,
                        previewCacheKey: stageA.item.previewCacheKey,
                        fileSizeBytes: stageA.item.fileSizeBytes,
                        fileModificationDate: stageA.item.fileModificationDate,
                        metrics: stageA.metrics,
                        perceptualHash: stageA.perceptualHash,
                        category: category,
                        categoryConfidence: conf,
                        visionScores: scores,
                        faces: stageA.faces,
                        featurePrintData: fpData,
                        classificationBackend: classifier.lastUsedBackend.rawValue
                    )
                    previewPipeline?.saveAnalysisRecord(record)

                    return PhotoAnalysisResult(
                        id: stageA.item.id,
                        previewGenerated: true,
                        metrics: stageA.metrics,
                        perceptualHash: stageA.perceptualHash,
                        featurePrint: stageA.featurePrint,
                        faces: stageA.faces,
                        category: category,
                        categoryConfidence: conf,
                        previewDurationSeconds: stageA.previewDurationSeconds,
                        qualityDurationSeconds: stageA.qualityDurationSeconds,
                        faceDurationSeconds: stageA.faceDurationSeconds,
                        featurePrintDurationSeconds: stageA.featurePrintDurationSeconds,
                        classificationDurationSeconds: classDuration
                    )
                }
                continuation.resume(returning: result)
            }
        }
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
        classifierGate: AsyncSemaphore? = nil,
        onThumbnailReady: (@Sendable (String) -> Void)? = nil
    ) async throws -> PhotoAnalysisResult {
        try await coordinator.waitIfPaused()
        try Task.checkCancellation()

        let stageA = try await processStageA(
            item: item,
            coordinator: coordinator,
            previewPipeline: previewPipeline,
            qualityAnalyzer: qualityAnalyzer,
            faceRecognizer: faceRecognizer,
            featurePrintProvider: featurePrintProvider,
            lazyFeaturePrint: lazyFeaturePrint,
            faceInputMaxPixelSize: faceInputMaxPixelSize,
            sceneInputMaxPixelSize: sceneInputMaxPixelSize,
            expectedBackend: classifier.targetBackend.rawValue,
            onThumbnailReady: onThumbnailReady
        )

        // If cached record exists, skip vision requests
        if let cached = stageA.cachedRecord {
            return PhotoAnalysisResult(
                id: item.id,
                previewGenerated: true,
                metrics: stageA.metrics,
                perceptualHash: stageA.perceptualHash,
                featurePrint: stageA.featurePrint,
                faces: stageA.faces,
                category: cached.category,
                categoryConfidence: cached.categoryConfidence,
                previewDurationSeconds: stageA.previewDurationSeconds,
                qualityDurationSeconds: stageA.qualityDurationSeconds,
                faceDurationSeconds: stageA.faceDurationSeconds,
                featurePrintDurationSeconds: stageA.featurePrintDurationSeconds,
                classificationDurationSeconds: 0.0
            )
        }

        // If combined vision perform mode is requested and supported
        if visionExecutionMode == .combined && !classifier.isCoreMLModelLoaded,
           let faceCG = stageA.faceCG, let sceneCG = stageA.sceneCG, faceCG === sceneCG {
            let handler = VNImageRequestHandler(cgImage: faceCG, options: [:])
            let faceRequest = VNDetectFaceLandmarksRequest()
            let sceneRequest = VNClassifyImageRequest()
            let tVisionStart = CFAbsoluteTimeGetCurrent()
            if let gate = classifierGate {
                await gate.acquire()
                try? handler.perform([faceRequest, sceneRequest])
                await gate.release()
            } else {
                try? handler.perform([faceRequest, sceneRequest])
            }
            let tVisionEnd = CFAbsoluteTimeGetCurrent()
            let totalVisionDur = max(0.0, tVisionEnd - tVisionStart)

            var metrics = stageA.metrics
            let faces = faceRecognizer.processObservations(faceRequest.results ?? [])
            metrics.faceCount = faces.count
            if !faces.isEmpty {
                let totalQuality = faces.reduce(0.0) { $0 + $1.faceQuality }
                metrics.faceQualityScore = totalQuality / Double(faces.count)
                let totalEyes = faces.reduce(0.0) { $0 + $1.eyeOpenness }
                metrics.averageEyeOpenness = totalEyes / Double(faces.count)
                metrics.rawFaceSharpness = metrics.rawSharpness * 1.2
            }

            let res = classifier.classifyWithObservations(sceneRequest.results, metadata: item.metadata, faceCount: faces.count)
            var scores: [WeddingCategory: Double] = [:]
            scores[res.0] = res.1

            var fpData: Data? = nil
            if let fp = stageA.featurePrint {
                fpData = try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true)
            }
            let record = CachedAnalysisRecord(
                photoID: item.id,
                previewCacheKey: item.previewCacheKey,
                fileSizeBytes: item.fileSizeBytes,
                fileModificationDate: item.fileModificationDate,
                metrics: metrics,
                perceptualHash: stageA.perceptualHash,
                category: res.0,
                categoryConfidence: res.1,
                visionScores: scores,
                faces: faces,
                featurePrintData: fpData,
                classificationBackend: classifier.lastUsedBackend.rawValue
            )
            previewPipeline.saveAnalysisRecord(record)

            return PhotoAnalysisResult(
                id: item.id,
                previewGenerated: true,
                metrics: metrics,
                perceptualHash: stageA.perceptualHash,
                featurePrint: stageA.featurePrint,
                faces: faces,
                category: res.0,
                categoryConfidence: res.1,
                previewDurationSeconds: stageA.previewDurationSeconds,
                qualityDurationSeconds: stageA.qualityDurationSeconds,
                faceDurationSeconds: totalVisionDur * 0.5,
                featurePrintDurationSeconds: stageA.featurePrintDurationSeconds,
                classificationDurationSeconds: totalVisionDur * 0.5
            )
        }

        return try await processStageB(
            stageA: stageA,
            coordinator: coordinator,
            classifier: classifier,
            previewPipeline: previewPipeline,
            classifierGate: classifierGate
        )
    }
}
