import Foundation
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif
#if canImport(TestDatasetGeneratorLibrary)
import TestDatasetGeneratorLibrary
#endif
#if canImport(Darwin)
import Darwin
#endif

@main
struct BenchmarkRunner {
    static func getCurrentResidentMemoryBytes() -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
        #else
        return 0
        #endif
    }

    static func main() async {
        let args = CommandLine.arguments

        var datasetPhotoCount = 150
        var explicitTarget: Int? = nil
        var datasetPath: String? = nil
        var outputJSONPath = "artifacts/benchmark.json"
        var outputMDPath = "BENCHMARKS.md"
        var phaseTimingsJSONPath: String? = nil
        var strictMode = false
        var datasetMode = "LOW_RES_SCALE"
        var explicitGitSHA: String? = nil
        var explicitBuildConfig: String? = nil
        var workerOverride: Int? = nil
        var sweepConcurrency = false
        var sweepWorkersList: [Int] = [1, 2, 3, 4]
        var outputSweepJSONPath: String? = nil
        var sweepPhotoCount: Int? = nil
        var sweepOnly = false

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--count":
                if i + 1 < args.count, let c = Int(args[i + 1]) {
                    datasetPhotoCount = c
                    i += 1
                }
            case "--target":
                if i + 1 < args.count, let t = Int(args[i + 1]) {
                    explicitTarget = t
                    i += 1
                }
            case "--dataset-dir":
                if i + 1 < args.count {
                    datasetPath = args[i + 1]
                    i += 1
                }
            case "--output-json":
                if i + 1 < args.count {
                    outputJSONPath = args[i + 1]
                    i += 1
                }
            case "--output-md":
                if i + 1 < args.count {
                    outputMDPath = args[i + 1]
                    i += 1
                }
            case "--phase-timings-json":
                if i + 1 < args.count {
                    phaseTimingsJSONPath = args[i + 1]
                    i += 1
                }
            case "--dataset-mode":
                if i + 1 < args.count {
                    datasetMode = args[i + 1]
                    i += 1
                }
            case "--git-sha":
                if i + 1 < args.count {
                    explicitGitSHA = args[i + 1]
                    i += 1
                }
            case "--build-config":
                if i + 1 < args.count {
                    explicitBuildConfig = args[i + 1]
                    i += 1
                }
            case "--workers":
                if i + 1 < args.count, let w = Int(args[i + 1]) {
                    workerOverride = w
                    i += 1
                }
            case "--sweep-concurrency":
                sweepConcurrency = true
                if i + 1 < args.count, let count = Int(args[i + 1]) {
                    sweepPhotoCount = count
                    i += 1
                }
            case "--sweep-workers":
                if i + 1 < args.count {
                    sweepWorkersList = args[i + 1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    i += 1
                }
            case "--output-sweep-json":
                if i + 1 < args.count {
                    outputSweepJSONPath = args[i + 1]
                    i += 1
                }
            case "--sweep-only":
                sweepOnly = true
            case "--strict":
                strictMode = true
            default:
                break
            }
            i += 1
        }

        #if DEBUG
        let autoBuildConfig = "debug"
        #else
        let autoBuildConfig = "release"
        #endif
        let buildConfiguration = explicitBuildConfig ?? autoBuildConfig
        let finalGitSHA = explicitGitSHA ?? (ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "unknown")
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let targetSelectionCount = explicitTarget ?? (datasetPhotoCount >= 1000 ? 700 : min(datasetPhotoCount / 2, 700))

        print("====================================================")
        print("⏱️ WeddingCull Real Automated Benchmark Runner")
        print("====================================================")
        print("Build configuration: \(buildConfiguration)")
        print("Git SHA: \(finalGitSHA)")
        print("macOS: \(osVersion)")
        print("Dataset mode: \(datasetMode)")
        print("Input photo count: \(datasetPhotoCount)")
        print("Target cardinality: \(targetSelectionCount)")
        print("Strict validation: \(strictMode ? "ENABLED" : "DISABLED")")

        let datasetFolder: URL
        if let customPath = datasetPath {
            datasetFolder = URL(fileURLWithPath: customPath)
        } else {
            let modeSuffix = datasetMode == "HIGH_RES" ? "_highres" : ""
            datasetFolder = URL(fileURLWithPath: "artifacts/benchmark_dataset_\(datasetPhotoCount)\(modeSuffix)")
        }

        let fileManager = FileManager.default
        let existingFiles = (try? fileManager.contentsOfDirectory(atPath: datasetFolder.path)) ?? []
        if existingFiles.count < datasetPhotoCount {
            print("📦 Generating \(datasetPhotoCount) synthetic wedding photos at \(datasetFolder.path)...")
            try? fileManager.removeItem(at: datasetFolder)
            let generator = SyntheticWeddingGenerator()
            let config = SyntheticWeddingGenerator.GeneratorConfig(
                generateLargeImages: true,
                targetTotalPhotos: datasetPhotoCount,
                datasetMode: datasetMode
            )
            do {
                let files = try generator.generateDataset(at: datasetFolder, config: config)
                print("✅ Generated \(files.count) synthetic image files.")
            } catch {
                print("❌ Failed to generate synthetic dataset: \(error)")
                exit(1)
            }
        } else {
            print("ℹ️ Using existing dataset at \(datasetFolder.path) (\(existingFiles.count) files).")
        }

        if sweepConcurrency {
            let sweepTargetCount = sweepPhotoCount ?? datasetPhotoCount
            let sweepFolder: URL
            if let customPath = datasetPath {
                sweepFolder = URL(fileURLWithPath: customPath)
            } else if sweepPhotoCount != nil {
                sweepFolder = URL(fileURLWithPath: "artifacts/benchmark_dataset_sweep_\(sweepTargetCount)")
            } else {
                sweepFolder = datasetFolder
            }

            let sweepExisting = (try? fileManager.contentsOfDirectory(atPath: sweepFolder.path)) ?? []
            if sweepExisting.count < sweepTargetCount {
                print("📦 Generating \(sweepTargetCount) photos for concurrency sweep...")
                try? fileManager.removeItem(at: sweepFolder)
                let generator = SyntheticWeddingGenerator()
                let config = SyntheticWeddingGenerator.GeneratorConfig(
                    generateLargeImages: true,
                    targetTotalPhotos: sweepTargetCount,
                    datasetMode: datasetMode
                )
                _ = try? generator.generateDataset(at: sweepFolder, config: config)
            }

            print("\n🔄 Running Concurrency Sweep across workers: \(sweepWorkersList) on \(sweepTargetCount) photos...")
            struct ConcurrencyResult: Codable {
                let workers: Int
                let wallClockSeconds: Double
                let throughputPPS: Double
                let peakMemoryMB: Int
                let faceDetectionSeconds: Double
                let faceMsPerPhoto: Double
                let featurePrintSeconds: Double
                let fpMsPerPhoto: Double
                let sceneClassificationSeconds: Double
                let sceneMsPerPhoto: Double
                let rankingAndSelectionSeconds: Double
            }
            var sweepResults: [ConcurrencyResult] = []

            for w in sweepWorkersList {
                print("\n--- Testing with \(w) worker(s) ---")
                var currentPeak: UInt64 = 0
                let samplingTask = Task {
                    while !Task.isCancelled {
                        let usage = getCurrentResidentMemoryBytes()
                        if usage > currentPeak {
                            currentPeak = usage
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }

                let hw = HardwareCapabilities(concurrencyOverride: w)
                let pipe = AnalysisPipeline(hardware: hw)
                let tStart = Date()
                let sess = try await pipe.runAnalysis(
                    sourceFolder: sweepFolder,
                    targetCount: min(sweepTargetCount / 2, 700)
                ) { _ in }
                samplingTask.cancel()
                let tWall = max(0.001, Date().timeIntervalSince(tStart))
                let pps = Double(sess.photos.count) / tWall
                let peakMB = Int(round(Double(currentPeak) / (1024.0 * 1024.0)))
                let count = Double(max(1, sess.photos.count))
                let pt = sess.phaseTimings ?? PhaseTimings()

                let res = ConcurrencyResult(
                    workers: w,
                    wallClockSeconds: Double(round(tWall * 100) / 100),
                    throughputPPS: Double(round(pps * 100) / 100),
                    peakMemoryMB: peakMB,
                    faceDetectionSeconds: pt.faceDetectionSeconds,
                    faceMsPerPhoto: Double(round((pt.faceDetectionSeconds / count) * 10000) / 10),
                    featurePrintSeconds: pt.featurePrintSeconds,
                    fpMsPerPhoto: Double(round((pt.featurePrintSeconds / count) * 10000) / 10),
                    sceneClassificationSeconds: pt.sceneClassificationSeconds,
                    sceneMsPerPhoto: Double(round((pt.sceneClassificationSeconds / count) * 10000) / 10),
                    rankingAndSelectionSeconds: pt.rankingAndSelectionSeconds
                )
                sweepResults.append(res)
                print(String(format: "  Worker count %d: %.2fs wall, %.2f PPS, %d MB RSS | Face: %.1f ms/photo, FP: %.1f ms/photo, Scene: %.1f ms/photo",
                             w, tWall, pps, peakMB, res.faceMsPerPhoto, res.fpMsPerPhoto, res.sceneMsPerPhoto))
            }

            #if arch(arm64)
            let sweepArchName = "arm64"
            #elseif arch(x86_64)
            let sweepArchName = "x86_64"
            #else
            let sweepArchName = "unknown"
            #endif

            print("\n====================================================")
            print("📊 CONCURRENCY SWEEP SUMMARY (\(sweepArchName))")
            print("====================================================")
            print("| Workers | Wall (s) | Throughput (PPS) | Peak RSS (MB) | Face (ms/p) | FeaturePrint (ms/p) | Scene (ms/p) | Diversity (s) |")
            print("| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
            for r in sweepResults {
                print(String(format: "| %d | %.2f | %.2f | %d | %.1f | %.1f | %.1f | %.2f |",
                             r.workers, r.wallClockSeconds, r.throughputPPS, r.peakMemoryMB,
                             r.faceMsPerPhoto, r.fpMsPerPhoto, r.sceneMsPerPhoto, r.rankingAndSelectionSeconds))
            }
            print("====================================================\n")

            if let best = sweepResults.max(by: { $0.throughputPPS < $1.throughputPPS }) {
                print("🏆 Best measured configuration: \(best.workers) worker(s) at \(best.throughputPPS) PPS (Wall: \(best.wallClockSeconds)s)")
                if workerOverride == nil {
                    workerOverride = best.workers
                }
            }

            if let outPath = outputSweepJSONPath {
                let url = URL(fileURLWithPath: outPath)
                try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? enc.encode(sweepResults) {
                    try? data.write(to: url)
                    print("✅ Saved concurrency sweep JSON to \(outPath)")
                }
            }

            if sweepOnly {
                print("✅ Sweep-only mode completed successfully.")
                return
            }
        }

        var peakMemoryBytes: UInt64 = getCurrentResidentMemoryBytes()
        let memorySamplingTask = Task {
            while !Task.isCancelled {
                let current = getCurrentResidentMemoryBytes()
                if current > peakMemoryBytes {
                    peakMemoryBytes = current
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        print("🚀 Executing actual AnalysisPipeline on \(datasetPhotoCount) photos...")
        let hardware = HardwareCapabilities(concurrencyOverride: workerOverride)
        print("Hardware detected: \(hardware.cpuArchitecture), \(hardware.logicalProcessors) logical cores (\(hardware.recommendedConcurrency) concurrent workers)")

        let pipeline = AnalysisPipeline(hardware: hardware)
        let startTime = Date()

        do {
            var session = try await pipeline.runAnalysis(
                sourceFolder: datasetFolder,
                targetCount: targetSelectionCount
            ) { progress in
                if progress.completedUnits % 100 == 0 || progress.completedUnits == progress.totalUnits {
                    print("  [\(progress.phase.rawValue)] \(progress.completedUnits)/\(progress.totalUnits) - \(progress.message)")
                }
            }

            memorySamplingTask.cancel()

            let totalTime = max(0.001, Date().timeIntervalSince(startTime))
            let processedPhotos = session.photos.count
            let throughput = Double(processedPhotos) / totalTime
            let peakMB = Int(round(Double(peakMemoryBytes) / (1024.0 * 1024.0)))
            let selectedCount = session.photos.filter { $0.selectionState.isIncludedInFinal }.count

            // Input inspection
            let allFiles = (try? fileManager.contentsOfDirectory(atPath: datasetFolder.path)) ?? []
            let inputFilesCount = allFiles.count
            var rawCount = 0
            var jpegCount = 0
            var totalBytes: Int64 = 0
            var mpValues: [Double] = []
            var formatCounts: [String: Int] = [:]

            for photo in session.photos {
                totalBytes += photo.fileSizeBytes
                let ext = photo.sourceURL.pathExtension.uppercased()
                let key = ext.isEmpty ? "UNKNOWN" : ext
                formatCounts[key, default: 0] += 1

                if ["CR2", "CR3", "NEF", "ARW", "DNG", "RAF", "RW2"].contains(ext) {
                    rawCount += 1
                } else if ["JPG", "JPEG"].contains(ext) {
                    jpegCount += 1
                }

                if photo.metadata.width > 0 && photo.metadata.height > 0 {
                    let mp = Double(photo.metadata.width * photo.metadata.height) / 1_000_000.0
                    mpValues.append(mp)
                }
            }

            mpValues.sort()
            let minMP = mpValues.first ?? 0.0
            let maxMP = mpValues.last ?? 0.0
            let medianMP: Double
            let p95MP: Double

            if mpValues.isEmpty {
                medianMP = 0.0
                p95MP = 0.0
            } else {
                medianMP = mpValues[mpValues.count / 2]
                let p95Idx = min(mpValues.count - 1, Int(Double(mpValues.count) * 0.95))
                p95MP = mpValues[p95Idx]
            }

            #if arch(arm64)
            let archName = "arm64"
            #elseif arch(x86_64)
            let archName = "x86_64"
            #else
            let archName = "unknown"
            #endif

            let physicalMemGB = Double(hardware.physicalMemoryBytes) / (1024.0 * 1024.0 * 1024.0)
            let corruptCount = session.photos.filter { $0.metadata.isCorrupt }.count
            let rawJpegPairsCount = session.photos.filter { $0.hasRawJpegPair }.count

            // Test Export Validation
            print("📦 Verifying PhotoExporter on final selection...")
            let exportTempDir = fileManager.temporaryDirectory.appendingPathComponent("bench_export_\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: exportTempDir) }

            let exporter = PhotoExporter()
            let exportResult = try? exporter.exportSelection(
                items: session.photos,
                to: exportTempDir,
                folderStructure: .byCategory,
                rawHandling: .rawAndJpegPair
            )

            let exportedFileCount = exportResult?.exportedCount ?? 0
            let exportSuccess = (exportedFileCount > 0) && (exportedFileCount == selectedCount || selectedCount == 0)
            print("  Exported files: \(exportedFileCount), Expected selection: \(selectedCount), Status: \(exportSuccess ? "PASS" : "FAIL")")

            // Test Session Persistence
            print("💾 Verifying SessionManager save/reload round-trip...")
            let sessionTempFile = fileManager.temporaryDirectory.appendingPathComponent("bench_session_\(UUID().uuidString).weddingcull")
            defer { try? fileManager.removeItem(at: sessionTempFile) }

            let sessionManager = SessionManager()
            var sessionReloadSuccess = false
            let tSaveStart = CFAbsoluteTimeGetCurrent()
            if (try? sessionManager.saveSession(session, to: sessionTempFile)) != nil {
                let saveDuration = CFAbsoluteTimeGetCurrent() - tSaveStart
                session.phaseTimings?.sessionPersistenceSeconds = Double(round(saveDuration * 100) / 100)
                if let reloaded = try? sessionManager.loadSession(from: sessionTempFile) {
                    sessionReloadSuccess = (reloaded.photos.count == session.photos.count &&
                                            reloaded.targetSelectionCount == session.targetSelectionCount &&
                                            reloaded.burstGroups.count == session.burstGroups.count)
                }
            }
            print("  Session round-trip status: \(sessionReloadSuccess ? "PASS" : "FAIL")")

            let backendUsed = (FileManager.default.fileExists(atPath: "models/mobileclip_s0_image.mlmodelc") ||
                               FileManager.default.fileExists(atPath: "models/mobileclip_s0_image.mlpackage")) ? "MobileCLIP-S0" : "Apple Vision (Built-in)"

            print("\n====================================================")
            print("📊 BENCHMARK EXECUTION RESULTS (100% MEASURED)")
            print("====================================================")
            print("Build Configuration: \(buildConfiguration)")
            print("Git SHA: \(finalGitSHA)")
            print("Dataset Mode: \(datasetMode)")
            print("Input Files: \(inputFilesCount)")
            print("Imported Logical Photos: \(processedPhotos)")
            print("Rejected Corrupt: \(corruptCount)")
            print("RAW Files: \(rawCount), JPEG Files: \(jpegCount), RAW+JPEG Pairs: \(rawJpegPairsCount)")
            print(String(format: "Total Dataset Size: %.2f MB", Double(totalBytes) / (1024.0 * 1024.0)))
            print(String(format: "Megapixel Stats: Min %.2f MP, Median %.2f MP, p95 %.2f MP, Max %.2f MP", minMP, medianMP, p95MP, maxMP))
            print("Hardware: \(archName), \(hardware.logicalProcessors) cores, \(String(format: "%.1f", physicalMemGB)) GB RAM")
            print("Classification Backend: \(backendUsed)")
            print(String(format: "Wall-clock Time: %.2f seconds", totalTime))
            print(String(format: "Throughput: %.2f photos / second", throughput))
            print("Peak Resident Memory (RSS): \(peakMB) MB (Budget: < 2560 MB)")
            print("Target Cardinality: \(session.targetSelectionCount)")
            print("Final Selected Count: \(selectedCount)")
            print("Export Validation: \(exportSuccess ? "PASS" : "FAIL")")
            print("Session Persistence: \(sessionReloadSuccess ? "PASS" : "FAIL")")
            if let pt = session.phaseTimings {
                let photoCount = Double(max(1, session.photos.count))
                let faceMs = (pt.faceDetectionSeconds / photoCount) * 1000.0
                let fpMs = (pt.featurePrintSeconds / photoCount) * 1000.0
                let sceneMs = (pt.sceneClassificationSeconds / photoCount) * 1000.0
                let previewMs = (pt.previewGenerationSeconds / photoCount) * 1000.0
                let qualMs = (pt.qualityScoringSeconds / photoCount) * 1000.0
                let visionMs = (pt.faceAndFeatureSeconds / photoCount) * 1000.0

                print("--- Phase Timings (Worker Cumulative & Per-Photo) ---")
                print("  Discovery & Metadata: \(pt.discoverySeconds) s")
                print(String(format: "  Preview Generation (cumulative worker): %.2f s (%.1f ms/photo)", pt.previewGenerationSeconds, previewMs))
                print(String(format: "  Face Detection & Landmarks (cumulative worker): %.2f s (%.1f ms/photo)", pt.faceDetectionSeconds, faceMs))
                print(String(format: "  FeaturePrint Generation (cumulative worker): %.2f s (%.1f ms/photo)", pt.featurePrintSeconds, fpMs))
                print(String(format: "  Total Face & Feature (cumulative worker): %.2f s (%.1f ms/photo)", pt.faceAndFeatureSeconds, visionMs))
                print(String(format: "  Quality Scoring (cumulative worker): %.2f s (%.1f ms/photo)", pt.qualityScoringSeconds, qualMs))
                print(String(format: "  Scene Classification (cumulative worker): %.2f s (%.1f ms/photo)", pt.sceneClassificationSeconds, sceneMs))
                print("  Burst & Duplicate Detection: \(pt.burstAndDuplicateSeconds) s")
                print("  Clustering & Segmentation: \(pt.clusteringAndSegmentationSeconds) s")
                print(String(format: "  Ranking & Diversity Selection: %.2f s (%.1f ms/photo)", pt.rankingAndSelectionSeconds, (pt.rankingAndSelectionSeconds / photoCount) * 1000.0))
                print("  Session Persistence Write: \(pt.sessionPersistenceSeconds) s")
                print("  Total Wall Clock: \(pt.totalWallClockSeconds) s")
            }
            if let psm = session.perceivedSpeedMetrics {
                print("--- Perceived Speed Metrics ---")
                print("  Time to Folder Ready: \(psm.timeToFolderReady) s")
                print("  Time to First Thumbnail: \(psm.timeToFirstThumbnail) s")
                print("  Time to Interactive Grid: \(psm.timeToInteractiveGrid) s")
                print("  Time to First Analyzed Photo: \(psm.timeToFirstAnalyzedPhoto) s")
                print("  Time to Preliminary Selection: \(psm.timeToPreliminarySelection) s")
                print("  Time to Final Selection: \(psm.timeToFinalSelection) s")
            }
            print("====================================================")

            struct MegapixelStats: Codable {
                let minMP: Double
                let medianMP: Double
                let p95MP: Double
                let maxMP: Double
            }

            struct HardwareReport: Codable {
                let architecture: String
                let logicalProcessors: Int
                let physicalMemoryGB: Double
                let neuralEngineAvailable: Bool
                let metalAvailable: Bool
                let recommendedConcurrency: Int
            }

            struct BenchmarkReportData: Codable {
                let buildConfiguration: String
                let architecture: String
                let gitSHA: String
                let macOSVersion: String
                let datasetMode: String
                let datasetType: String
                let inputCount: Int
                let logicalPhotoCount: Int
                let inputFiles: Int
                let importedLogicalPhotos: Int
                let rejectedCorrupt: Int
                let rawFileCount: Int
                let jpegFileCount: Int
                let rawJpegPairs: Int
                let totalBytes: Int64
                let formatDistribution: [String: Int]
                let megapixelStats: MegapixelStats
                let hardware: HardwareReport
                let classificationBackend: String
                let datasetSize: Int
                let totalProcessingTimeSeconds: Double
                let wallClockSeconds: Double
                let photosPerSecond: Double
                let peakMemoryMB: Int
                let memoryBudgetMB: Int
                let memoryWithinBudget: Bool
                let targetCardinality: Int
                let finalSelectedCount: Int
                let burstGroupsDetected: Int
                let personClustersFormed: Int
                let exportValidation: Bool
                let sessionPersistence: Bool
                let phaseTimings: PhaseTimings?
                let perceivedSpeedMetrics: PerceivedSpeedMetrics?
            }

            let reportData = BenchmarkReportData(
                buildConfiguration: buildConfiguration,
                architecture: archName,
                gitSHA: finalGitSHA,
                macOSVersion: osVersion,
                datasetMode: datasetMode,
                datasetType: "synthetic-wedding-benchmark",
                inputCount: inputFilesCount,
                logicalPhotoCount: processedPhotos,
                inputFiles: inputFilesCount,
                importedLogicalPhotos: processedPhotos,
                rejectedCorrupt: corruptCount,
                rawFileCount: rawCount,
                jpegFileCount: jpegCount,
                rawJpegPairs: rawJpegPairsCount,
                totalBytes: totalBytes,
                formatDistribution: formatCounts,
                megapixelStats: MegapixelStats(
                    minMP: Double(round(minMP * 100) / 100),
                    medianMP: Double(round(medianMP * 100) / 100),
                    p95MP: Double(round(p95MP * 100) / 100),
                    maxMP: Double(round(maxMP * 100) / 100)
                ),
                hardware: HardwareReport(
                    architecture: archName,
                    logicalProcessors: hardware.logicalProcessors,
                    physicalMemoryGB: Double(round(physicalMemGB * 10) / 10),
                    neuralEngineAvailable: hardware.neuralEngineAvailable,
                    metalAvailable: hardware.metalAvailable,
                    recommendedConcurrency: hardware.recommendedConcurrency
                ),
                classificationBackend: backendUsed,
                datasetSize: processedPhotos,
                totalProcessingTimeSeconds: Double(round(totalTime * 100) / 100),
                wallClockSeconds: Double(round(totalTime * 100) / 100),
                photosPerSecond: Double(round(throughput * 10) / 10),
                peakMemoryMB: peakMB,
                memoryBudgetMB: 2560,
                memoryWithinBudget: peakMB <= 2560,
                targetCardinality: session.targetSelectionCount,
                finalSelectedCount: selectedCount,
                burstGroupsDetected: session.burstGroups.count,
                personClustersFormed: session.personClusters.count,
                exportValidation: exportSuccess,
                sessionPersistence: sessionReloadSuccess,
                phaseTimings: session.phaseTimings,
                perceivedSpeedMetrics: session.perceivedSpeedMetrics
            )

            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let jsonData = try? jsonEncoder.encode(reportData) {
                let jsonURL = URL(fileURLWithPath: outputJSONPath)
                try? fileManager.createDirectory(at: jsonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? jsonData.write(to: jsonURL)
                print("✅ Written benchmark JSON to \(outputJSONPath)")
            }

            // Export standalone Phase Timings JSON if requested
            if let phasePath = phaseTimingsJSONPath {
                struct PhaseTimingsReport: Codable {
                    let gitSHA: String
                    let architecture: String
                    let buildConfiguration: String
                    let datasetMode: String
                    let inputFiles: Int
                    let logicalPhotos: Int
                    let wallClockSeconds: Double
                    let photosPerSecond: Double
                    let peakMemoryMB: Int
                    let phaseTimings: PhaseTimings?
                    let perceivedSpeedMetrics: PerceivedSpeedMetrics?
                }

                let ptReport = PhaseTimingsReport(
                    gitSHA: finalGitSHA,
                    architecture: archName,
                    buildConfiguration: buildConfiguration,
                    datasetMode: datasetMode,
                    inputFiles: inputFilesCount,
                    logicalPhotos: processedPhotos,
                    wallClockSeconds: Double(round(totalTime * 100) / 100),
                    photosPerSecond: Double(round(throughput * 10) / 10),
                    peakMemoryMB: peakMB,
                    phaseTimings: session.phaseTimings,
                    perceivedSpeedMetrics: session.perceivedSpeedMetrics
                )
                if let ptData = try? jsonEncoder.encode(ptReport) {
                    let ptURL = URL(fileURLWithPath: phasePath)
                    try? fileManager.createDirectory(at: ptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? ptData.write(to: ptURL)
                    print("✅ Written phase timings JSON to \(phasePath)")
                }
            }

            let dateFormatter = ISO8601DateFormatter()
            let isoDate = dateFormatter.string(from: Date())
            let formatDistStr = formatCounts.sorted { $0.key < $1.key }.map { "- `\($0.key)`: \($0.value) files" }.joined(separator: "\n")

            var mdContent = """
            # WeddingCull Benchmark Results (Measured)

            * **Date**: \(isoDate)
            * **Build Configuration**: `\(buildConfiguration)`
            * **Git SHA**: `\(finalGitSHA)`
            * **Architecture**: `\(archName)`
            * **macOS**: `\(osVersion)`
            * **Dataset Mode**: `\(datasetMode)`
            * **Dataset Size**: \(processedPhotos) photographs (Input: \(inputFilesCount) files)
            * **Target Cardinality**: \(session.targetSelectionCount)
            * **Final Selected**: \(selectedCount)
            * **Throughput**: \(String(format: "%.1f photos / sec", throughput))
            * **Peak RSS**: \(peakMB) MB / 2560 MB budget

            ## Dataset Breakdown

            \(formatDistStr)

            * **Median Resolution**: \(String(format: "%.2f", medianMP)) MP
            * **p95 Resolution**: \(String(format: "%.2f", p95MP)) MP
            * **Export Verification**: \(exportSuccess ? "PASS ✅" : "FAIL ❌")
            * **Session Reload**: \(sessionReloadSuccess ? "PASS ✅" : "FAIL ❌")
            """

            if let pt = session.phaseTimings {
                let count = Double(max(1, session.photos.count))
                let faceMs = (pt.faceDetectionSeconds / count) * 1000.0
                let fpMs = (pt.featurePrintSeconds / count) * 1000.0
                let sceneMs = (pt.sceneClassificationSeconds / count) * 1000.0
                let previewMs = (pt.previewGenerationSeconds / count) * 1000.0
                let qualMs = (pt.qualityScoringSeconds / count) * 1000.0
                let visionMs = (pt.faceAndFeatureSeconds / count) * 1000.0
                let divMs = (pt.rankingAndSelectionSeconds / count) * 1000.0
                let wallMs = (pt.totalWallClockSeconds / count) * 1000.0

                mdContent += """


                ## Phase Timings Breakdown

                | Pipeline Phase | Cumulative Worker Time | Per-Photo Time |
                | :--- | :--- | :--- |
                | **Discovery & Metadata Indexing** | \(pt.discoverySeconds) s | - |
                | **Preview & Thumbnail Generation (worker cumulative)** | \(pt.previewGenerationSeconds) s | \(String(format: "%.1f", previewMs)) ms |
                | **Face Detection & Landmarks (worker cumulative)** | \(pt.faceDetectionSeconds) s | \(String(format: "%.1f", faceMs)) ms |
                | **FeaturePrint Generation (worker cumulative)** | \(pt.featurePrintSeconds) s | \(String(format: "%.1f", fpMs)) ms |
                | **Total Face & Feature (combined)** | \(pt.faceAndFeatureSeconds) s | \(String(format: "%.1f", visionMs)) ms |
                | **Quality & Sharpness Scoring (worker cumulative)** | \(pt.qualityScoringSeconds) s | \(String(format: "%.1f", qualMs)) ms |
                | **Scene & Semantic Classification (worker cumulative)** | \(pt.sceneClassificationSeconds) s | \(String(format: "%.1f", sceneMs)) ms |
                | **Burst & Duplicate Detection** | \(pt.burstAndDuplicateSeconds) s | - |
                | **Temporal Segmentation & Grouping** | \(pt.clusteringAndSegmentationSeconds) s | - |
                | **Ranking & Diversity Selection** | \(pt.rankingAndSelectionSeconds) s | \(String(format: "%.1f", divMs)) ms |
                | **Session Persistence Write** | \(pt.sessionPersistenceSeconds) s | - |
                | **Total Wall Clock Time** | **\(pt.totalWallClockSeconds) s** | **\(String(format: "%.1f", wallMs)) ms** |
                """
            }

            if let psm = session.perceivedSpeedMetrics {
                mdContent += """


                ## Perceived Speed & Responsiveness Metrics

                | Milestone | Measured Time |
                | :--- | :--- |
                | **timeToFolderReady** (metadata indexed, placeholders visible) | \(psm.timeToFolderReady) s |
                | **timeToFirstThumbnail** (first visible image in UI) | \(psm.timeToFirstThumbnail) s |
                | **timeToInteractiveGrid** (user can browse & scroll) | \(psm.timeToInteractiveGrid) s |
                | **timeToFirstAnalyzedPhoto** (first scored photo ready) | \(psm.timeToFirstAnalyzedPhoto) s |
                | **timeToPreliminarySelection** (initial keepers visible) | \(psm.timeToPreliminarySelection) s |
                | **timeToFinalSelection** (full analysis complete) | **\(psm.timeToFinalSelection) s** |
                """
            }

            let mdURL = URL(fileURLWithPath: outputMDPath)
            try? fileManager.createDirectory(at: mdURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(mdContent.utf8).write(to: mdURL)
            print("✅ Written benchmark Markdown to \(outputMDPath)")

            if strictMode {
                var strictFailures: [String] = []
                if peakMB > 2560 {
                    strictFailures.append("Peak memory \(peakMB) MB exceeded 2560 MB budget")
                }
                let eligible = session.photos.filter { !$0.isDuplicate && !$0.metadata.isCorrupt }.count
                let expectedSelected = min(session.targetSelectionCount, eligible)
                if selectedCount != expectedSelected {
                    strictFailures.append("Selected count (\(selectedCount)) did not match expected target cardinality (\(expectedSelected))")
                }
                if !exportSuccess {
                    strictFailures.append("Export verification failed")
                }
                if !sessionReloadSuccess {
                    strictFailures.append("Session persistence round-trip failed")
                }

                if !strictFailures.isEmpty {
                    print("\n❌ STRICT BENCHMARK VALIDATION FAILED:")
                    for f in strictFailures {
                        print("  - \(f)")
                    }
                    exit(1)
                }
                print("✅ Strict benchmark validation PASSED with zero anomalies.")
            }

            exit(0)
        } catch {
            memorySamplingTask.cancel()
            print("❌ Pipeline analysis failed: \(error)")
            exit(1)
        }
    }
}
