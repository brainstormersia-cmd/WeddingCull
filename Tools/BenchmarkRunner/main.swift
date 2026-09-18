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
        var lazyFeaturePrint = true
        var visionExecutionMode: VisionExecutionMode = .separate
        var facePixelSize = 1000
        var scenePixelSize = 1000
        var sweepVisionConfigs = false
        var outputVisionConfigsJSONPath: String? = nil
        var classifySlots: Int? = nil
        var sweepClassifyMatrix = false
        var outputClassifyMatrixJSONPath: String? = nil
        var diagnoseDeterminism = false
        var outputDeterminismJSONPath: String? = nil
        var sweepTwoStage = false
        var outputTwoStageJSONPath: String? = nil
        var useTwoStageArchitecture = false
        var stageAWorkers: Int? = nil
        var stageBWorkers: Int? = nil
        var queueCapacity = 8
        var classificationBackendArg = "auto"
        var strictModel = false
        var compareBaselineJSONPath: String? = nil
        var customCachePath: String? = nil
        var cleanCache = false

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
            case "--lazy-feature-print":
                if i + 1 < args.count {
                    lazyFeaturePrint = (args[i + 1].lowercased() != "false" && args[i + 1] != "0")
                    i += 1
                }
            case "--eager-feature-print":
                lazyFeaturePrint = false
            case "--vision-mode":
                if i + 1 < args.count {
                    let modeStr = args[i + 1].lowercased()
                    visionExecutionMode = (modeStr == "combined") ? .combined : .separate
                    i += 1
                }
            case "--face-pixel-size":
                if i + 1 < args.count, let s = Int(args[i + 1]) {
                    facePixelSize = s
                    i += 1
                }
            case "--scene-pixel-size":
                if i + 1 < args.count, let s = Int(args[i + 1]) {
                    scenePixelSize = s
                    i += 1
                }
            case "--sweep-vision-configs":
                sweepVisionConfigs = true
                if i + 1 < args.count, let c = Int(args[i + 1]) {
                    datasetPhotoCount = c
                    i += 1
                }
            case "--output-vision-configs-json":
                if i + 1 < args.count {
                    outputVisionConfigsJSONPath = args[i + 1]
                    i += 1
                }
            case "--classify-slots":
                if i + 1 < args.count, let slots = Int(args[i + 1]) {
                    classifySlots = slots
                    i += 1
                }
            case "--sweep-classify-matrix":
                sweepClassifyMatrix = true
                if i + 1 < args.count, let c = Int(args[i + 1]) {
                    datasetPhotoCount = c
                    i += 1
                }
            case "--output-classify-matrix-json":
                if i + 1 < args.count {
                    outputClassifyMatrixJSONPath = args[i + 1]
                    i += 1
                }
            case "--diagnose-determinism":
                diagnoseDeterminism = true
                if i + 1 < args.count, let c = Int(args[i + 1]) {
                    datasetPhotoCount = c
                    i += 1
                }
            case "--output-determinism-json":
                if i + 1 < args.count {
                    outputDeterminismJSONPath = args[i + 1]
                    i += 1
                }
            case "--sweep-two-stage":
                sweepTwoStage = true
                if i + 1 < args.count, let c = Int(args[i + 1]) {
                    datasetPhotoCount = c
                    i += 1
                }
            case "--output-two-stage-json":
                if i + 1 < args.count {
                    outputTwoStageJSONPath = args[i + 1]
                    i += 1
                }
            case "--two-stage":
                useTwoStageArchitecture = true
            case "--stage-a-workers":
                if i + 1 < args.count, let w = Int(args[i + 1]) {
                    stageAWorkers = w
                    i += 1
                }
            case "--stage-b-workers":
                if i + 1 < args.count, let w = Int(args[i + 1]) {
                    stageBWorkers = w
                    i += 1
                }
            case "--queue-capacity":
                if i + 1 < args.count, let q = Int(args[i + 1]) {
                    queueCapacity = q
                    i += 1
                }
            case "--classification-backend":
                if i + 1 < args.count {
                    classificationBackendArg = args[i + 1].lowercased()
                    i += 1
                }
            case "--strict-model":
                strictModel = true
            case "--compare-baseline-json":
                if i + 1 < args.count {
                    compareBaselineJSONPath = args[i + 1]
                    i += 1
                }
            case "--custom-cache-dir":
                if i + 1 < args.count {
                    customCachePath = args[i + 1]
                    i += 1
                }
            case "--clean-cache":
                cleanCache = true
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
                let pipe = AnalysisPipeline(
                    hardware: hw,
                    lazyFeaturePrint: lazyFeaturePrint,
                    visionExecutionMode: visionExecutionMode,
                    faceInputMaxPixelSize: facePixelSize,
                    sceneInputMaxPixelSize: scenePixelSize
                )
                let tStart = Date()
                let sess: SessionData
                do {
                    sess = try await pipe.runAnalysis(
                        sourceFolder: sweepFolder,
                        targetCount: min(sweepTargetCount / 2, 700)
                    ) { _ in }
                } catch {
                    samplingTask.cancel()
                    print("❌ Concurrency sweep failed for \(w) worker(s): \(error)")
                    continue
                }
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

        if sweepVisionConfigs {
            let sweepFolder = datasetFolder
            let sweepTargetCount = targetSelectionCount
            print("\n🔬 ====================================================")
            print("🔬 EXECUTING VISION CONFIGURATIONS SWEEP")
            print("🔬 ====================================================")

            struct VisionConfigDef {
                let name: String
                let mode: VisionExecutionMode
                let faceSize: Int
                let sceneSize: Int
                let lazyFP: Bool
            }

            let configsToTest: [VisionConfigDef] = [
                VisionConfigDef(name: "Separate (1000px, Eager FP)", mode: .separate, faceSize: 1000, sceneSize: 1000, lazyFP: false),
                VisionConfigDef(name: "Separate (1000px, Lazy FP) [Baseline]", mode: .separate, faceSize: 1000, sceneSize: 1000, lazyFP: true),
                VisionConfigDef(name: "Combined perform() (1000px, Lazy FP)", mode: .combined, faceSize: 1000, sceneSize: 1000, lazyFP: true),
                VisionConfigDef(name: "Scene 800px (Face 1000px, Lazy FP)", mode: .separate, faceSize: 1000, sceneSize: 800, lazyFP: true),
                VisionConfigDef(name: "Scene 640px (Face 1000px, Lazy FP)", mode: .separate, faceSize: 1000, sceneSize: 640, lazyFP: true),
                VisionConfigDef(name: "Face 800px (Scene 1000px, Lazy FP)", mode: .separate, faceSize: 800, sceneSize: 1000, lazyFP: true),
                VisionConfigDef(name: "Face 640px (Scene 1000px, Lazy FP)", mode: .separate, faceSize: 640, sceneSize: 1000, lazyFP: true),
                VisionConfigDef(name: "Combined (800px, Lazy FP)", mode: .combined, faceSize: 800, sceneSize: 800, lazyFP: true),
                VisionConfigDef(name: "Combined (640px, Lazy FP)", mode: .combined, faceSize: 640, sceneSize: 640, lazyFP: true)
            ]

            struct VisionConfigResult: Codable {
                let configName: String
                let mode: String
                let facePixelSize: Int
                let scenePixelSize: Int
                let wallClockSeconds: Double
                let throughputPPS: Double
                let faceMsPerPhoto: Double
                let sceneMsPerPhoto: Double
                let fpMsPerPhoto: Double
                let categoryAgreementPct: Double
                let faceCountAgreementPct: Double
            }

            var results: [VisionConfigResult] = []
            var baselineCategories: [String: WeddingCategory] = [:]
            var baselineFaceCounts: [String: Int] = [:]

            for cfg in configsToTest {
                print("\n--- Testing: \(cfg.name) ---")
                let hw = HardwareCapabilities(concurrencyOverride: workerOverride)
                let pipe = AnalysisPipeline(
                    hardware: hw,
                    lazyFeaturePrint: cfg.lazyFP,
                    visionExecutionMode: cfg.mode,
                    faceInputMaxPixelSize: cfg.faceSize,
                    sceneInputMaxPixelSize: cfg.sceneSize
                )
                let tStart = Date()
                let sess: SessionData
                do {
                    sess = try await pipe.runAnalysis(
                        sourceFolder: sweepFolder,
                        targetCount: min(sweepTargetCount / 2, 700)
                    ) { _ in }
                } catch {
                    print("❌ Vision config test failed for \(cfg.name): \(error)")
                    continue
                }
                let tWall = max(0.001, Date().timeIntervalSince(tStart))
                let pps = Double(sess.photos.count) / tWall
                let count = Double(max(1, sess.photos.count))
                let pt = sess.phaseTimings ?? PhaseTimings()

                let currentCategories = Dictionary(uniqueKeysWithValues: sess.photos.map { ($0.id, $0.category) })
                let currentFaceCounts = Dictionary(uniqueKeysWithValues: sess.photos.map { ($0.id, $0.metrics.faceCount) })

                if baselineCategories.isEmpty {
                    baselineCategories = currentCategories
                    baselineFaceCounts = currentFaceCounts
                }

                var catMatch = 0
                var faceMatch = 0
                for (id, cat) in currentCategories {
                    if baselineCategories[id] == cat { catMatch += 1 }
                    if baselineFaceCounts[id] == currentFaceCounts[id] { faceMatch += 1 }
                }
                let catAgrPct = Double(round((Double(catMatch) / count) * 1000) / 10)
                let faceAgrPct = Double(round((Double(faceMatch) / count) * 1000) / 10)

                let res = VisionConfigResult(
                    configName: cfg.name,
                    mode: cfg.mode.rawValue,
                    facePixelSize: cfg.faceSize,
                    scenePixelSize: cfg.sceneSize,
                    wallClockSeconds: Double(round(tWall * 100) / 100),
                    throughputPPS: Double(round(pps * 100) / 100),
                    faceMsPerPhoto: Double(round((pt.faceDetectionSeconds / count) * 10000) / 10),
                    sceneMsPerPhoto: Double(round((pt.sceneClassificationSeconds / count) * 10000) / 10),
                    fpMsPerPhoto: Double(round((pt.featurePrintSeconds / count) * 10000) / 10),
                    categoryAgreementPct: catAgrPct,
                    faceCountAgreementPct: faceAgrPct
                )
                results.append(res)
                print(String(format: "  %.2fs wall, %.2f PPS | Face: %.1f ms/p (%.1f%% agr), Scene: %.1f ms/p (%.1f%% agr), FP: %.1f ms/p",
                             tWall, pps, res.faceMsPerPhoto, res.faceCountAgreementPct, res.sceneMsPerPhoto, res.categoryAgreementPct, res.fpMsPerPhoto))
            }

            print("\n====================================================")
            print("📊 VISION CONFIGURATIONS SWEEP SUMMARY")
            print("====================================================")
            print("| Configuration | Wall (s) | Throughput (PPS) | Face (ms/p) | Face Agr % | Scene (ms/p) | Scene Agr % | FP (ms/p) |")
            print("| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
            for r in results {
                print(String(format: "| %@ | %.2f | %.2f | %.1f | %.1f%% | %.1f | %.1f%% | %.1f |",
                             r.configName, r.wallClockSeconds, r.throughputPPS, r.faceMsPerPhoto, r.faceCountAgreementPct, r.sceneMsPerPhoto, r.categoryAgreementPct, r.fpMsPerPhoto))
            }
            print("====================================================\n")

            if let outPath = outputVisionConfigsJSONPath {
                let url = URL(fileURLWithPath: outPath)
                try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? enc.encode(results) {
                    try? data.write(to: url)
                    print("✅ Saved vision configs JSON to \(outPath)")
                }
            }

            if sweepOnly {
                print("✅ Sweep-only mode completed successfully.")
                return
            }
        }

        if sweepClassifyMatrix {
            let sweepFolder = datasetFolder
            let sweepTargetCount = targetSelectionCount
            print("\n🔬 ==================================================================================")
            print("🔬 EXECUTING DECOUPLED CONCURRENCY MATRIX SWEEP (Pipeline Workers x Classify Slots)")
            print("🔬 ==================================================================================")

            struct ClassifyMatrixConfig {
                let pipelineWorkers: Int
                let classifySlots: Int
            }

            let matrixConfigs: [ClassifyMatrixConfig] = [
                ClassifyMatrixConfig(pipelineWorkers: 2, classifySlots: 1),
                ClassifyMatrixConfig(pipelineWorkers: 2, classifySlots: 2),
                ClassifyMatrixConfig(pipelineWorkers: 3, classifySlots: 1),
                ClassifyMatrixConfig(pipelineWorkers: 3, classifySlots: 2),
                ClassifyMatrixConfig(pipelineWorkers: 4, classifySlots: 1),
                ClassifyMatrixConfig(pipelineWorkers: 4, classifySlots: 2)
            ]

            struct ClassifyMatrixResult: Codable {
                let pipelineWorkers: Int
                let classifySlots: Int
                let wallClockSeconds: Double
                let throughputPPS: Double
                let faceMsPerPhoto: Double
                let sceneMsPerPhoto: Double
                let fpMsPerPhoto: Double
                let previewMsPerPhoto: Double
                let qualityMsPerPhoto: Double
                let categoryAgreementPct: Double
                let faceCountAgreementPct: Double
                let selectedIDsMatch: Bool
            }

            var results: [ClassifyMatrixResult] = []
            var baselineCategories: [String: WeddingCategory] = [:]
            var baselineFaceCounts: [String: Int] = [:]
            var baselineSelectedIDs: Set<String> = []

            for cfg in matrixConfigs {
                print("\n--- Testing: Pipeline \(cfg.pipelineWorkers) workers / Classify \(cfg.classifySlots) slot(s) ---")
                let isolatedCache = URL(fileURLWithPath: "artifacts/cache_matrix_w\(cfg.pipelineWorkers)_s\(cfg.classifySlots)")
                try? fileManager.removeItem(at: isolatedCache)
                defer { try? fileManager.removeItem(at: isolatedCache) }

                let hw = HardwareCapabilities(concurrencyOverride: cfg.pipelineWorkers)
                let pipe = AnalysisPipeline(
                    hardware: hw,
                    customCacheDir: isolatedCache,
                    lazyFeaturePrint: true,
                    visionExecutionMode: .separate,
                    faceInputMaxPixelSize: 1000,
                    sceneInputMaxPixelSize: 1000,
                    sceneClassificationConcurrency: cfg.classifySlots
                )
                let tStart = Date()
                let sess: SessionData
                do {
                    sess = try await pipe.runAnalysis(
                        sourceFolder: sweepFolder,
                        targetCount: min(sweepTargetCount / 2, 700)
                    ) { _ in }
                } catch {
                    print("❌ Matrix sweep test failed for (w: \(cfg.pipelineWorkers), s: \(cfg.classifySlots)): \(error)")
                    continue
                }
                let tWall = max(0.001, Date().timeIntervalSince(tStart))
                let pps = Double(sess.photos.count) / tWall
                let count = Double(max(1, sess.photos.count))
                let pt = sess.phaseTimings ?? PhaseTimings()

                let currentCategories = Dictionary(uniqueKeysWithValues: sess.photos.map { ($0.id, $0.category) })
                let currentFaceCounts = Dictionary(uniqueKeysWithValues: sess.photos.map { ($0.id, $0.metrics.faceCount) })
                let currentSelectedIDs = Set(sess.photos.filter { $0.selectionState == .selected }.map(\.id))

                if baselineCategories.isEmpty {
                    baselineCategories = currentCategories
                    baselineFaceCounts = currentFaceCounts
                    baselineSelectedIDs = currentSelectedIDs
                }

                var catMatch = 0
                var faceMatch = 0
                for (id, cat) in currentCategories {
                    if baselineCategories[id] == cat { catMatch += 1 }
                    if baselineFaceCounts[id] == currentFaceCounts[id] { faceMatch += 1 }
                }
                let catAgrPct = Double(round((Double(catMatch) / count) * 1000) / 10)
                let faceAgrPct = Double(round((Double(faceMatch) / count) * 1000) / 10)
                let idsMatch = (currentSelectedIDs == baselineSelectedIDs)

                let res = ClassifyMatrixResult(
                    pipelineWorkers: cfg.pipelineWorkers,
                    classifySlots: cfg.classifySlots,
                    wallClockSeconds: Double(round(tWall * 100) / 100),
                    throughputPPS: Double(round(pps * 100) / 100),
                    faceMsPerPhoto: Double(round((pt.faceDetectionSeconds / count) * 10000) / 10),
                    sceneMsPerPhoto: Double(round((pt.sceneClassificationSeconds / count) * 10000) / 10),
                    fpMsPerPhoto: Double(round((pt.featurePrintSeconds / count) * 10000) / 10),
                    previewMsPerPhoto: Double(round((pt.previewGenerationSeconds / count) * 10000) / 10),
                    qualityMsPerPhoto: Double(round((pt.qualityScoringSeconds / count) * 10000) / 10),
                    categoryAgreementPct: catAgrPct,
                    faceCountAgreementPct: faceAgrPct,
                    selectedIDsMatch: idsMatch
                )
                results.append(res)
                print(String(format: "  %.2fs wall, %.2f PPS | Scene: %.1f ms/p (%.1f%% agr), Face: %.1f ms/p, IDs match: %@",
                             tWall, pps, res.sceneMsPerPhoto, res.categoryAgreementPct, res.faceMsPerPhoto, idsMatch ? "YES" : "NO"))
            }

            print("\n==================================================================================")
            print("📊 DECOUPLED CONCURRENCY MATRIX SWEEP SUMMARY")
            print("==================================================================================")
            print("| Pipeline Workers | Classify Slots | Wall (s) | Throughput (PPS) | Scene (ms/p) | Face (ms/p) | Cat Agr % | IDs Match |")
            print("| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
            for r in results {
                print(String(format: "| %d | %d | %.2f | %.2f | %.1f | %.1f | %.1f%% | %@ |",
                             r.pipelineWorkers, r.classifySlots, r.wallClockSeconds, r.throughputPPS, r.sceneMsPerPhoto, r.faceMsPerPhoto, r.categoryAgreementPct, r.selectedIDsMatch ? "YES" : "NO"))
            }
            if let best = results.max(by: { $0.throughputPPS < $1.throughputPPS }) {
                print("----------------------------------------------------------------------------------")
                print(String(format: "🏆 Optimal Decoupled Configuration: Pipeline %d / Classify Slots %d (%.2f PPS, %.2fs wall)",
                             best.pipelineWorkers, best.classifySlots, best.throughputPPS, best.wallClockSeconds))
            }
            print("==================================================================================\n")

            if let outPath = outputClassifyMatrixJSONPath {
                let url = URL(fileURLWithPath: outPath)
                try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? enc.encode(results) {
                    try? data.write(to: url)
                    print("✅ Saved classify matrix JSON to \(outPath)")
                }
            }

            if sweepOnly {
                print("✅ Sweep-only mode completed successfully.")
                return
            }
        }

        if diagnoseDeterminism {
            let diagCount = datasetPhotoCount
            let diagFolder = datasetFolder
            let diagTarget = targetSelectionCount
            print("\n🔬 ==================================================================================")
            print("🔬 EXECUTING DETERMINISM DIAGNOSTICS SUITE (\(diagCount) photos, target: \(diagTarget))")
            print("🔬 ==================================================================================")

            struct RunSnapshot {
                let name: String
                let photos: [PhotoItem]
                let session: SessionData
                let wallClockSeconds: Double
                let throughputPPS: Double
            }

            func executeDiagRun(name: String, workers: Int, slots: Int, cacheDir: URL, cleanCache: Bool) async throws -> RunSnapshot {
                if cleanCache {
                    try? fileManager.removeItem(at: cacheDir)
                }
                try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                let hw = HardwareCapabilities(concurrencyOverride: workers)
                let pipe = AnalysisPipeline(
                    hardware: hw,
                    customCacheDir: cacheDir,
                    lazyFeaturePrint: true,
                    visionExecutionMode: .separate,
                    faceInputMaxPixelSize: 1000,
                    sceneInputMaxPixelSize: 1000,
                    sceneClassificationConcurrency: slots
                )
                let tStart = Date()
                let sess = try await pipe.runAnalysis(sourceFolder: diagFolder, targetCount: diagTarget) { _ in }
                let wall = max(0.001, Date().timeIntervalSince(tStart))
                let pps = Double(sess.photos.count) / wall
                return RunSnapshot(name: name, photos: sess.photos, session: sess, wallClockSeconds: wall, throughputPPS: pps)
            }

            struct DeterminismComparison: Codable {
                let comparisonName: String
                let runAName: String
                let runBName: String
                let selectedIDsMatch: Bool
                let selectedCountA: Int
                let selectedCountB: Int
                let symmetricDifferenceCount: Int
                let idsOnlyInA: [String]
                let idsOnlyInB: [String]
                let categoryAgreementPct: Double
                let categoryMismatchCount: Int
                let categoryMismatches: [String: String]
                let faceCountAgreementPct: Double
                let faceCountMismatchCount: Int
                let burstGroupsCountA: Int
                let burstGroupsCountB: Int
                let burstWinnersMatch: Bool
                let burstWinnerMismatchCount: Int
                let segmentsCountA: Int
                let segmentsCountB: Int
                let maxOverallScoreDiff: Double
                let meanOverallScoreDiff: Double
                let isByteIdentical: Bool
                let summaryNote: String
            }

            func compareSnapshots(name: String, runA: RunSnapshot, runB: RunSnapshot, note: String) -> DeterminismComparison {
                let idsA = Set(runA.photos.filter { $0.selectionState == .selected }.map(\.id))
                let idsB = Set(runB.photos.filter { $0.selectionState == .selected }.map(\.id))
                let onlyA = Array(idsA.subtracting(idsB)).sorted()
                let onlyB = Array(idsB.subtracting(idsA)).sorted()
                let symDiff = onlyA.count + onlyB.count

                let mapA = Dictionary(uniqueKeysWithValues: runA.photos.map { ($0.id, $0) })
                let mapB = Dictionary(uniqueKeysWithValues: runB.photos.map { ($0.id, $0) })

                var catMatches = 0
                var catMismatches: [String: String] = [:]
                var faceMatches = 0
                var faceMismatchCount = 0
                var scoreDiffs: [Double] = []

                for id in mapA.keys.sorted() {
                    guard let itemA = mapA[id], let itemB = mapB[id] else { continue }
                    if itemA.category == itemB.category {
                        catMatches += 1
                    } else {
                        catMismatches[id] = "\(itemA.category.rawValue) vs \(itemB.category.rawValue)"
                    }
                    if itemA.metrics.faceCount == itemB.metrics.faceCount {
                        faceMatches += 1
                    } else {
                        faceMismatchCount += 1
                    }
                    let diff = abs(itemA.metrics.overallScore - itemB.metrics.overallScore)
                    scoreDiffs.append(diff)
                }

                let totalCount = max(1, Double(mapA.count))
                let catPct = Double(round((Double(catMatches) / totalCount) * 1000) / 10)
                let facePct = Double(round((Double(faceMatches) / totalCount) * 1000) / 10)
                let maxScoreDiff = scoreDiffs.max() ?? 0.0
                let meanScoreDiff = scoreDiffs.isEmpty ? 0.0 : (scoreDiffs.reduce(0.0, +) / Double(scoreDiffs.count))

                let bgA = Dictionary(uniqueKeysWithValues: runA.session.burstGroups.map { ($0.id, $0) })
                let bgB = Dictionary(uniqueKeysWithValues: runB.session.burstGroups.map { ($0.id, $0) })
                var burstWinnerMismatches = 0
                for (id, groupA) in bgA {
                    if let groupB = bgB[id] {
                        if groupA.winnerID != groupB.winnerID {
                            burstWinnerMismatches += 1
                        }
                    } else {
                        burstWinnerMismatches += 1
                    }
                }

                let isByteIdentical = (idsA == idsB) && (catMismatches.isEmpty) && (faceMismatchCount == 0) && (burstWinnerMismatches == 0) && (maxScoreDiff < 0.0001)

                return DeterminismComparison(
                    comparisonName: name,
                    runAName: runA.name,
                    runBName: runB.name,
                    selectedIDsMatch: idsA == idsB,
                    selectedCountA: idsA.count,
                    selectedCountB: idsB.count,
                    symmetricDifferenceCount: symDiff,
                    idsOnlyInA: onlyA,
                    idsOnlyInB: onlyB,
                    categoryAgreementPct: catPct,
                    categoryMismatchCount: catMismatches.count,
                    categoryMismatches: catMismatches,
                    faceCountAgreementPct: facePct,
                    faceCountMismatchCount: faceMismatchCount,
                    burstGroupsCountA: bgA.count,
                    burstGroupsCountB: bgB.count,
                    burstWinnersMatch: (burstWinnerMismatches == 0 && bgA.count == bgB.count),
                    burstWinnerMismatchCount: burstWinnerMismatches,
                    segmentsCountA: runA.session.segments.count,
                    segmentsCountB: runB.session.segments.count,
                    maxOverallScoreDiff: Double(round(maxScoreDiff * 100000) / 100000),
                    meanOverallScoreDiff: Double(round(meanScoreDiff * 100000) / 100000),
                    isByteIdentical: isByteIdentical,
                    summaryNote: note
                )
            }

            var comparisons: [DeterminismComparison] = []
            do {
                print("1️⃣ Running Cold Run 1 (Workers: 2, Classify Slots: 2)...")
                let cold1Dir = URL(fileURLWithPath: "artifacts/cache_diag_cold1")
                let cold1 = try await executeDiagRun(name: "Cold 1 (2/2)", workers: 2, slots: 2, cacheDir: cold1Dir, cleanCache: true)
                defer { try? fileManager.removeItem(at: cold1Dir) }
                print(String(format: "   Done: %.2fs wall, %.2f PPS, %d selected", cold1.wallClockSeconds, cold1.throughputPPS, cold1.photos.filter { $0.selectionState == .selected }.count))

                print("2️⃣ Running Cold Run 2 (Workers: 2, Classify Slots: 2)...")
                let cold2Dir = URL(fileURLWithPath: "artifacts/cache_diag_cold2")
                let cold2 = try await executeDiagRun(name: "Cold 2 (2/2)", workers: 2, slots: 2, cacheDir: cold2Dir, cleanCache: true)
                defer { try? fileManager.removeItem(at: cold2Dir) }
                print(String(format: "   Done: %.2fs wall, %.2f PPS, %d selected", cold2.wallClockSeconds, cold2.throughputPPS, cold2.photos.filter { $0.selectionState == .selected }.count))

                print("3️⃣ Running Warm Run 1 (populating warm cache, Workers: 2, Classify Slots: 2)...")
                let warmDir = URL(fileURLWithPath: "artifacts/cache_diag_warm")
                let warm1 = try await executeDiagRun(name: "Warm 1 (2/2)", workers: 2, slots: 2, cacheDir: warmDir, cleanCache: true)
                print(String(format: "   Done: %.2fs wall, %.2f PPS, %d selected", warm1.wallClockSeconds, warm1.throughputPPS, warm1.photos.filter { $0.selectionState == .selected }.count))

                print("4️⃣ Running Warm Run 2 (reusing warm cache, Workers: 2, Classify Slots: 2)...")
                let warm2 = try await executeDiagRun(name: "Warm 2 (2/2)", workers: 2, slots: 2, cacheDir: warmDir, cleanCache: false)
                defer { try? fileManager.removeItem(at: warmDir) }
                print(String(format: "   Done: %.2fs wall, %.2f PPS, %d selected", warm2.wallClockSeconds, warm2.throughputPPS, warm2.photos.filter { $0.selectionState == .selected }.count))

                print("5️⃣ Running Cold Run (Workers: 2, Classify Slots: 1)...")
                let cold21Dir = URL(fileURLWithPath: "artifacts/cache_diag_cold_2_1")
                let cold21 = try await executeDiagRun(name: "Cold (2/1)", workers: 2, slots: 1, cacheDir: cold21Dir, cleanCache: true)
                defer { try? fileManager.removeItem(at: cold21Dir) }
                print(String(format: "   Done: %.2fs wall, %.2f PPS, %d selected", cold21.wallClockSeconds, cold21.throughputPPS, cold21.photos.filter { $0.selectionState == .selected }.count))

                // Comparisons
                comparisons.append(compareSnapshots(
                    name: "Cold 1 vs Cold 2 (Identical 2/2)",
                    runA: cold1,
                    runB: cold2,
                    note: "Identical cold starts under concurrency. Tests scheduling, timing, and sorting determinism."
                ))
                comparisons.append(compareSnapshots(
                    name: "Warm 1 vs Warm 2 (Identical 2/2)",
                    runA: warm1,
                    runB: warm2,
                    note: "Identical warm starts reading cached disk JPEGs. Tests cache-reload determinism."
                ))
                comparisons.append(compareSnapshots(
                    name: "Cold (2, 1) vs Cold (2, 2)",
                    runA: cold21,
                    runB: cold1,
                    note: "Decoupled concurrency slots variation with clean cold cache. Tests concurrency independence."
                ))
                comparisons.append(compareSnapshots(
                    name: "Cold 1 vs Warm 2 (Cold vs Warm)",
                    runA: cold1,
                    runB: warm2,
                    note: "Cold start (fresh decode) vs Warm start (cached analysis reuse). Tests authoritative cache fidelity."
                ))

            } catch {
                print("❌ Determinism diagnostic execution failed: \(error)")
            }

            print("\n==================================================================================")
            print("📊 DETERMINISM DIAGNOSTICS SUMMARY REPORT")
            print("==================================================================================")
            print("| Comparison | Selected IDs Match | Cat Agr % | Face Agr % | Burst Winners | Max Score Diff | Byte-Identical? |")
            print("| :--- | :---: | :---: | :---: | :---: | :---: | :---: |")
            for c in comparisons {
                print(String(format: "| %@ | %@ (%d diff) | %.1f%% | %.1f%% | %@ | %.5f | %@ |",
                             c.comparisonName,
                             c.selectedIDsMatch ? "YES ✅" : "NO ❌",
                             c.symmetricDifferenceCount,
                             c.categoryAgreementPct,
                             c.faceCountAgreementPct,
                             c.burstWinnersMatch ? "MATCH ✅" : "DIFF ❌",
                             c.maxOverallScoreDiff,
                             c.isByteIdentical ? "YES ✅" : "NO ⚠️"))
            }
            print("==================================================================================\n")

            let outPath = outputDeterminismJSONPath ?? "artifacts/determinism_diagnostics.json"
            let url = URL(fileURLWithPath: outPath)
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(comparisons) {
                try? data.write(to: url)
                print("✅ Saved determinism diagnostics JSON to \(outPath)")
            }

            if strictMode {
                let warmWarm = comparisons.first(where: { $0.comparisonName.contains("Warm 1 vs Warm 2") })
                let coldCold = comparisons.first(where: { $0.comparisonName.contains("Cold 1 vs Cold 2") })
                let coldWarm = comparisons.first(where: { $0.comparisonName.contains("Cold 1 vs Warm 2") })

                var determinismFailures: [String] = []
                if let ww = warmWarm, ww.symmetricDifferenceCount > 0 {
                    determinismFailures.append("Warm vs Warm determinism failed: \(ww.symmetricDifferenceCount) symmetric difference (expected 0)")
                }
                if let cc = coldCold, cc.symmetricDifferenceCount > 0 {
                    determinismFailures.append("Cold vs Cold determinism failed: \(cc.symmetricDifferenceCount) symmetric difference (expected 0)")
                }
                if let cw = coldWarm, cw.symmetricDifferenceCount > 0 {
                    determinismFailures.append("Cold vs Warm determinism failed: \(cw.symmetricDifferenceCount) symmetric difference (expected 0)")
                }
                if !determinismFailures.isEmpty {
                    print("\n❌ STRICT DETERMINISM VALIDATION FAILED:")
                    for f in determinismFailures {
                        print("  - \(f)")
                    }
                    exit(1)
                }
                print("✅ Strict determinism validation PASSED: 0 symmetric differences across Cold/Cold, Warm/Warm, and Cold/Warm.")
            }

            if sweepOnly {
                print("✅ Determinism diagnostics completed successfully.")
                return
            }
        }

        if sweepTwoStage {
            let sweepCount = datasetPhotoCount
            let sweepFolder = datasetFolder
            let sweepTarget = targetSelectionCount
            print("\n🔬 ==================================================================================")
            print("🔬 EXECUTING TWO-STAGE PIPELINE SWEEP (Producer-Consumer Backpressure)")
            print("🔬 ==================================================================================")

            struct TwoStageConfigDef {
                let name: String
                let stageAWorkers: Int
                let stageBWorkers: Int
                let queueCapacity: Int
            }

            let configurations: [TwoStageConfigDef] = [
                TwoStageConfigDef(name: "Stage A: 2 / Stage B: 1 / Queue: 8", stageAWorkers: 2, stageBWorkers: 1, queueCapacity: 8),
                TwoStageConfigDef(name: "Stage A: 2 / Stage B: 2 / Queue: 8", stageAWorkers: 2, stageBWorkers: 2, queueCapacity: 8),
                TwoStageConfigDef(name: "Stage A: 3 / Stage B: 1 / Queue: 8", stageAWorkers: 3, stageBWorkers: 1, queueCapacity: 8),
                TwoStageConfigDef(name: "Stage A: 3 / Stage B: 2 / Queue: 8", stageAWorkers: 3, stageBWorkers: 2, queueCapacity: 8),
                TwoStageConfigDef(name: "Stage A: 4 / Stage B: 1 / Queue: 8", stageAWorkers: 4, stageBWorkers: 1, queueCapacity: 8),
                TwoStageConfigDef(name: "Stage A: 4 / Stage B: 2 / Queue: 8", stageAWorkers: 4, stageBWorkers: 2, queueCapacity: 8),
                TwoStageConfigDef(name: "Stage A: 2 / Stage B: 2 / Queue: 4", stageAWorkers: 2, stageBWorkers: 2, queueCapacity: 4),
                TwoStageConfigDef(name: "Stage A: 2 / Stage B: 2 / Queue: 16", stageAWorkers: 2, stageBWorkers: 2, queueCapacity: 16),
                TwoStageConfigDef(name: "Stage A: 3 / Stage B: 2 / Queue: 4", stageAWorkers: 3, stageBWorkers: 2, queueCapacity: 4),
                TwoStageConfigDef(name: "Stage A: 3 / Stage B: 2 / Queue: 16", stageAWorkers: 3, stageBWorkers: 2, queueCapacity: 16)
            ]

            struct TwoStageResult: Codable {
                let configName: String
                let stageAWorkers: Int
                let stageBWorkers: Int
                let queueCapacity: Int
                let wallClockSeconds: Double
                let throughputPPS: Double
                let peakMemoryMB: Int
                let previewMsPerPhoto: Double
                let qualityMsPerPhoto: Double
                let faceMsPerPhoto: Double
                let sceneMsPerPhoto: Double
                let categoryAgreementPct: Double
                let faceCountAgreementPct: Double
                let selectedIDsMatch: Bool
            }

            var results: [TwoStageResult] = []
            var baselineCategories: [String: WeddingCategory] = [:]
            var baselineFaceCounts: [String: Int] = [:]
            var baselineSelectedIDs: Set<String> = []

            for cfg in configurations {
                print("\n--- Testing: \(cfg.name) ---")
                let isolatedCache = URL(fileURLWithPath: "artifacts/cache_twostage_a\(cfg.stageAWorkers)_b\(cfg.stageBWorkers)_q\(cfg.queueCapacity)")
                try? fileManager.removeItem(at: isolatedCache)
                defer { try? fileManager.removeItem(at: isolatedCache) }

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

                let pipe = AnalysisPipeline(
                    hardware: HardwareCapabilities(concurrencyOverride: cfg.stageAWorkers),
                    customCacheDir: isolatedCache,
                    lazyFeaturePrint: true,
                    visionExecutionMode: .separate,
                    faceInputMaxPixelSize: 1000,
                    sceneInputMaxPixelSize: 1000,
                    pipelineArchitecture: .twoStage,
                    stageAWorkers: cfg.stageAWorkers,
                    stageBWorkers: cfg.stageBWorkers,
                    queueCapacity: cfg.queueCapacity
                )

                let tStart = Date()
                let sess: SessionData
                do {
                    sess = try await pipe.runAnalysis(
                        sourceFolder: sweepFolder,
                        targetCount: sweepTarget
                    ) { _ in }
                } catch {
                    samplingTask.cancel()
                    print("❌ Two-stage test failed for \(cfg.name): \(error)")
                    continue
                }
                samplingTask.cancel()
                let tWall = max(0.001, Date().timeIntervalSince(tStart))
                let pps = Double(sess.photos.count) / tWall
                let peakMB = Int(round(Double(currentPeak) / (1024.0 * 1024.0)))
                let count = Double(max(1, sess.photos.count))
                let pt = sess.phaseTimings ?? PhaseTimings()

                let currentCategories = Dictionary(uniqueKeysWithValues: sess.photos.map { ($0.id, $0.category) })
                let currentFaceCounts = Dictionary(uniqueKeysWithValues: sess.photos.map { ($0.id, $0.metrics.faceCount) })
                let currentSelectedIDs = Set(sess.photos.filter { $0.selectionState == .selected }.map(\.id))

                if baselineCategories.isEmpty {
                    baselineCategories = currentCategories
                    baselineFaceCounts = currentFaceCounts
                    baselineSelectedIDs = currentSelectedIDs
                }

                var catMatch = 0
                var faceMatch = 0
                for (id, cat) in currentCategories {
                    if baselineCategories[id] == cat { catMatch += 1 }
                    if baselineFaceCounts[id] == currentFaceCounts[id] { faceMatch += 1 }
                }
                let catAgrPct = Double(round((Double(catMatch) / count) * 1000) / 10)
                let faceAgrPct = Double(round((Double(faceMatch) / count) * 1000) / 10)
                let idsMatch = (currentSelectedIDs == baselineSelectedIDs)

                let res = TwoStageResult(
                    configName: cfg.name,
                    stageAWorkers: cfg.stageAWorkers,
                    stageBWorkers: cfg.stageBWorkers,
                    queueCapacity: cfg.queueCapacity,
                    wallClockSeconds: Double(round(tWall * 100) / 100),
                    throughputPPS: Double(round(pps * 100) / 100),
                    peakMemoryMB: peakMB,
                    previewMsPerPhoto: Double(round((pt.previewGenerationSeconds / count) * 10000) / 10),
                    qualityMsPerPhoto: Double(round((pt.qualityScoringSeconds / count) * 10000) / 10),
                    faceMsPerPhoto: Double(round((pt.faceDetectionSeconds / count) * 10000) / 10),
                    sceneMsPerPhoto: Double(round((pt.sceneClassificationSeconds / count) * 10000) / 10),
                    categoryAgreementPct: catAgrPct,
                    faceCountAgreementPct: faceAgrPct,
                    selectedIDsMatch: idsMatch
                )
                results.append(res)
                print(String(format: "  %.2fs wall, %.2f PPS, %d MB RSS | Scene: %.1f ms/p, Face: %.1f ms/p, IDs match: %@",
                             tWall, pps, peakMB, res.sceneMsPerPhoto, res.faceMsPerPhoto, idsMatch ? "YES" : "NO"))
            }

            print("\n==================================================================================")
            print("📊 TWO-STAGE PIPELINE SWEEP SUMMARY")
            print("==================================================================================")
            print("| Configuration | Wall (s) | Throughput (PPS) | Peak RSS (MB) | Scene (ms/p) | Face (ms/p) | IDs Match |")
            print("| :--- | :---: | :---: | :---: | :---: | :---: | :---: |")
            for r in results {
                print(String(format: "| %@ | %.2f | %.2f | %d | %.1f | %.1f | %@ |",
                             r.configName, r.wallClockSeconds, r.throughputPPS, r.peakMemoryMB, r.sceneMsPerPhoto, r.faceMsPerPhoto, r.selectedIDsMatch ? "YES" : "NO"))
            }
            if let best = results.max(by: { $0.throughputPPS < $1.throughputPPS }) {
                print("----------------------------------------------------------------------------------")
                print(String(format: "🏆 Optimal Two-Stage Configuration: %@ (%.2f PPS, %.2fs wall)",
                             best.configName, best.throughputPPS, best.wallClockSeconds))
            }
            print("==================================================================================\n")

            let outPath = outputTwoStageJSONPath ?? "artifacts/two_stage_sweep.json"
            let url = URL(fileURLWithPath: outPath)
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(results) {
                try? data.write(to: url)
                print("✅ Saved two-stage sweep JSON to \(outPath)")
            }

            if sweepOnly {
                print("✅ Two-stage sweep completed successfully.")
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

        let forceVisionFallback = (classificationBackendArg == "vision")

        let cacheDirURL: URL?
        if let custom = customCachePath {
            let u = URL(fileURLWithPath: custom)
            if cleanCache {
                try? fileManager.removeItem(at: u)
            }
            try? fileManager.createDirectory(at: u, withIntermediateDirectories: true)
            cacheDirURL = u
        } else if cleanCache {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let defaultDir = appSupport.appendingPathComponent("WeddingCull/Previews", isDirectory: true)
            try? fileManager.removeItem(at: defaultDir)
            cacheDirURL = nil
        } else {
            cacheDirURL = nil
        }

        let pipeline = AnalysisPipeline(
            hardware: hardware,
            customCacheDir: cacheDirURL,
            lazyFeaturePrint: lazyFeaturePrint,
            visionExecutionMode: visionExecutionMode,
            faceInputMaxPixelSize: facePixelSize,
            sceneInputMaxPixelSize: scenePixelSize,
            sceneClassificationConcurrency: classifySlots,
            pipelineArchitecture: useTwoStageArchitecture ? .twoStage : .unified,
            stageAWorkers: stageAWorkers,
            stageBWorkers: stageBWorkers,
            queueCapacity: queueCapacity,
            forceVisionFallback: forceVisionFallback
        )
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

            let selectedPhotos = session.photos.filter { $0.isSelected }
            let expectedExportFiles = selectedPhotos.reduce(0) { $0 + ($1.hasRawJpegPair ? 2 : 1) }
            let exportedFileCount = exportResult?.exportedCount ?? 0
            let exportSuccess = (exportedFileCount > 0) && (exportedFileCount == expectedExportFiles || selectedCount == 0)
            print("  Exported files: \(exportedFileCount), Expected files: \(expectedExportFiles) (\(selectedCount) selected photos), Status: \(exportSuccess ? "PASS" : "FAIL")")

            // Test Session Persistence
            print("💾 Verifying SessionManager save/reload round-trip...")
            let sessionTempFile = fileManager.temporaryDirectory.appendingPathComponent("bench_session_\(UUID().uuidString).weddingcull")
            defer { try? fileManager.removeItem(at: sessionTempFile) }

            let sessionManager = SessionManager()
            var sessionReloadSuccess = false
            var sessionReopenLatencySeconds: Double = 0.0
            let tSaveStart = CFAbsoluteTimeGetCurrent()
            if (try? sessionManager.saveSession(session, to: sessionTempFile)) != nil {
                let saveDuration = CFAbsoluteTimeGetCurrent() - tSaveStart
                session.phaseTimings?.sessionPersistenceSeconds = Double(round(saveDuration * 100) / 100)
                let tLoadStart = CFAbsoluteTimeGetCurrent()
                if let reloaded = try? sessionManager.loadSession(from: sessionTempFile) {
                    sessionReopenLatencySeconds = CFAbsoluteTimeGetCurrent() - tLoadStart
                    sessionReloadSuccess = (reloaded.photos.count == session.photos.count &&
                                            reloaded.targetSelectionCount == session.targetSelectionCount &&
                                            reloaded.burstGroups.count == session.burstGroups.count)
                }
            }
            print(String(format: "  Session round-trip status: %@ (Reopen Latency: %.3f s, Target: < 2.0s)", sessionReloadSuccess ? "PASS" : "FAIL", sessionReopenLatencySeconds))

            let backendUsed = await pipeline.classifierBackendUsed.rawValue

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
            print(String(format: "Session Reopen Latency: %.3f s (< 2.0s target)", sessionReopenLatencySeconds))
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
            let readiness = session.pipelineReadinessMetrics ?? session.perceivedSpeedMetrics
            if let psm = readiness {
                print("--- Pipeline Readiness Metrics ---")
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
                let sceneClassificationSlots: Int?
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
                let actualBackendUsed: String
                let modelLoaded: Bool
                let datasetSize: Int
                let totalProcessingTimeSeconds: Double
                let wallClockSeconds: Double
                let photosPerSecond: Double
                let classificationMsPerPhoto: Double
                let peakMemoryMB: Int
                let rssMB: Int
                let memoryBudgetMB: Int
                let memoryWithinBudget: Bool
                let targetCardinality: Int
                let finalSelectedCount: Int
                let burstGroupsDetected: Int
                let personClustersFormed: Int
                let exportValidation: Bool
                let sessionPersistence: Bool
                let sessionReopenLatencySeconds: Double
                let selectedIDs: [String]
                let selectedIDAgreementPct: Double?
                let selectedIDsMatch: Bool?
                let selectedIDsSymmetricDifference: Int?
                let phaseTimings: PhaseTimings?
                let pipelineReadinessMetrics: PipelineReadinessMetrics?
                let perceivedSpeedMetrics: PipelineReadinessMetrics?
            }

            let isModelLoaded = await pipeline.isCoreMLModelLoaded
            let actualBackend = await pipeline.classifierBackendUsed
            let actualBackendString = actualBackend.rawValue
            let sceneClassSeconds = session.phaseTimings?.sceneClassificationSeconds ?? 0.0
            let classMsPerPhoto = processedPhotos > 0 ? Double(round(((sceneClassSeconds / Double(processedPhotos)) * 1000.0) * 10) / 10) : 0.0

            let selectedIDs = session.photos.filter { $0.selectionState.isIncludedInFinal }.map(\.id).sorted()
            var selectedIDAgreementPct: Double? = nil
            var selectedIDsMatch: Bool? = nil
            var selectedIDsSymmetricDifference: Int? = nil

            if let baselinePath = compareBaselineJSONPath {
                if let baselineData = try? Data(contentsOf: URL(fileURLWithPath: baselinePath)),
                   let baselineJSON = try? JSONSerialization.jsonObject(with: baselineData) as? [String: Any] {
                    let baselineList = (baselineJSON["selectedIDs"] as? [String]) ?? []
                    let baselineSet = Set(baselineList)
                    let currentSet = Set(selectedIDs)
                    if !baselineSet.isEmpty {
                        let intersect = currentSet.intersection(baselineSet).count
                        let union = currentSet.union(baselineSet).count
                        selectedIDAgreementPct = union > 0 ? Double(round((Double(intersect) / Double(union)) * 1000) / 10) : 100.0
                        selectedIDsMatch = (currentSet == baselineSet)
                        selectedIDsSymmetricDifference = currentSet.symmetricDifference(baselineSet).count
                        print("🔍 Baseline Comparison against \(baselinePath):")
                        print(String(format: "   Selected ID Agreement: %.1f%% (%d / %d match, Symmetric Diff: %d)",
                                     selectedIDAgreementPct ?? 0.0, intersect, baselineSet.count, selectedIDsSymmetricDifference ?? 0))
                    }
                }
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
                    recommendedConcurrency: hardware.recommendedConcurrency,
                    sceneClassificationSlots: classifySlots
                ),
                classificationBackend: backendUsed,
                actualBackendUsed: actualBackendString,
                modelLoaded: isModelLoaded,
                datasetSize: processedPhotos,
                totalProcessingTimeSeconds: Double(round(totalTime * 100) / 100),
                wallClockSeconds: Double(round(totalTime * 100) / 100),
                photosPerSecond: Double(round(throughput * 10) / 10),
                classificationMsPerPhoto: classMsPerPhoto,
                peakMemoryMB: peakMB,
                rssMB: peakMB,
                memoryBudgetMB: 2560,
                memoryWithinBudget: peakMB <= 2560,
                targetCardinality: session.targetSelectionCount,
                finalSelectedCount: selectedCount,
                burstGroupsDetected: session.burstGroups.count,
                personClustersFormed: session.personClusters.count,
                exportValidation: exportSuccess,
                sessionPersistence: sessionReloadSuccess,
                sessionReopenLatencySeconds: Double(round(sessionReopenLatencySeconds * 1000) / 1000),
                selectedIDs: selectedIDs,
                selectedIDAgreementPct: selectedIDAgreementPct,
                selectedIDsMatch: selectedIDsMatch,
                selectedIDsSymmetricDifference: selectedIDsSymmetricDifference,
                phaseTimings: session.phaseTimings,
                pipelineReadinessMetrics: session.pipelineReadinessMetrics ?? session.perceivedSpeedMetrics,
                perceivedSpeedMetrics: session.pipelineReadinessMetrics ?? session.perceivedSpeedMetrics
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
                    let sessionReopenLatencySeconds: Double
                    let phaseTimings: PhaseTimings?
                    let pipelineReadinessMetrics: PipelineReadinessMetrics?
                    let perceivedSpeedMetrics: PipelineReadinessMetrics?
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
                    sessionReopenLatencySeconds: Double(round(sessionReopenLatencySeconds * 1000) / 1000),
                    phaseTimings: session.phaseTimings,
                    pipelineReadinessMetrics: session.pipelineReadinessMetrics ?? session.perceivedSpeedMetrics,
                    perceivedSpeedMetrics: session.pipelineReadinessMetrics ?? session.perceivedSpeedMetrics
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

            if let psm = readiness {
                mdContent += """


                ## Pipeline Readiness & Responsiveness Metrics

                | Milestone | Measured Time | Target / Status |
                | :--- | :--- | :--- |
                | **timeToFolderReady** (metadata indexed, placeholders visible) | \(psm.timeToFolderReady) s | Instant metadata presentation |
                | **timeToFirstThumbnail** (first visible image in UI) | \(psm.timeToFirstThumbnail) s | Progressive thumbnail streaming |
                | **timeToInteractiveGrid** (user can browse & scroll 24 cells) | \(psm.timeToInteractiveGrid) s | Non-blocking grid interactivity |
                | **timeToFirstAnalyzedPhoto** (first scored photo ready) | \(psm.timeToFirstAnalyzedPhoto) s | Incremental pipeline stream |
                | **timeToPreliminarySelection** (initial keepers visible) | \(psm.timeToPreliminarySelection) s | Early cull visibility |
                | **timeToFinalSelection** (full analysis complete) | **\(psm.timeToFinalSelection) s** | Full selection finalized |
                | **sessionReopenLatencySeconds** (reopening shoot from disk) | **\(String(format: "%.3f", sessionReopenLatencySeconds)) s** | Target: < 2.0s (\(sessionReopenLatencySeconds < 2.0 ? "PASS" : "FAIL")) |
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

            if strictModel && classificationBackendArg == "mobileclip" {
                let modelLoaded = await pipeline.isCoreMLModelLoaded
                if !modelLoaded {
                    print("\n❌ STRICT MODEL ERROR: MobileCLIP-S0 Core ML model is not loaded!")
                    exit(1)
                }
                let actualBackend = await pipeline.classifierBackendUsed
                if actualBackend != .mobileCLIP {
                    print("\n❌ STRICT MODEL ERROR: Classifier fell back to \(actualBackend.rawValue) instead of MobileCLIP-S0!")
                    exit(1)
                }
                print("✅ Strict model validation PASSED: MobileCLIP-S0 ran authentically via Core ML.")
            }

            exit(0)
        } catch {
            memorySamplingTask.cancel()
            print("❌ Pipeline analysis failed: \(error)")
            exit(1)
        }
    }
}
