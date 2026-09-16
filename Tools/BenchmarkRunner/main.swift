import Foundation
#if canImport(WeddingCullCore)
import WeddingCullCore
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

        var targetCount = 150
        var datasetPath: String? = nil
        var outputJSONPath = "artifacts/benchmark.json"
        var outputMDPath = "BENCHMARKS.md"

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--count":
                if i + 1 < args.count, let c = Int(args[i + 1]) {
                    targetCount = c
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
            default:
                break
            }
            i += 1
        }

        print("====================================================")
        print("⏱️ WeddingCull Real Automated Benchmark Runner")
        print("====================================================")
        print("Target photo count: \(targetCount)")

        let datasetFolder: URL
        if let customPath = datasetPath {
            datasetFolder = URL(fileURLWithPath: customPath)
        } else {
            datasetFolder = URL(fileURLWithPath: "artifacts/benchmark_dataset_\(targetCount)")
        }

        // Generate synthetic dataset if not already present or count doesn't match
        let fileManager = FileManager.default
        let existingFiles = (try? fileManager.contentsOfDirectory(atPath: datasetFolder.path)) ?? []
        if existingFiles.count < targetCount {
            print("📦 Generating \(targetCount) synthetic wedding photos at \(datasetFolder.path)...")
            try? fileManager.removeItem(at: datasetFolder)
            let generator = SyntheticWeddingGenerator()
            let config = SyntheticWeddingGenerator.GeneratorConfig(
                generateLargeImages: true,
                targetTotalPhotos: targetCount
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

        // Memory sampler background task
        var peakMemoryBytes: UInt64 = getCurrentResidentMemoryBytes()
        let memorySamplingTask = Task {
            while !Task.isCancelled {
                let current = getCurrentResidentMemoryBytes()
                if current > peakMemoryBytes {
                    peakMemoryBytes = current
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // sample every 100ms
            }
        }

        print("🚀 Executing actual AnalysisPipeline on \(targetCount) photos...")
        let hardware = HardwareCapabilities()
        print("Hardware detected: \(hardware.processorName), \(hardware.physicalCoreCount) cores (\(hardware.recommendedConcurrency) concurrent workers)")

        let pipeline = AnalysisPipeline(hardware: hardware)
        let startTime = Date()

        var phaseTimes: [AnalysisPhase: TimeInterval] = [:]
        var lastPhaseTime = startTime

        do {
            let session = try await pipeline.runAnalysis(
                sourceFolder: datasetFolder,
                targetCount: min(targetCount / 2, 700)
            ) { progress in
                let now = Date()
                phaseTimes[progress.phase] = now.timeIntervalSince(lastPhaseTime)
                lastPhaseTime = now
            }

            memorySamplingTask.cancel()

            let totalTime = max(0.001, Date().timeIntervalSince(startTime))
            let processedPhotos = session.photos.count
            let throughput = Double(processedPhotos) / totalTime
            let peakMB = Int(round(Double(peakMemoryBytes) / (1024.0 * 1024.0)))

            print("\n====================================================")
            print("📊 BENCHMARK EXECUTION RESULTS (100% MEASURED)")
            print("====================================================")
            print("Dataset Size: \(processedPhotos) photos")
            print(String(format: "Total Pipeline Processing Time: %.2f seconds", totalTime))
            print(String(format: "Throughput: %.2f photos / second", throughput))
            print("Peak Resident Memory (RSS): \(peakMB) MB")
            print("Selected Count: \(session.selectedPhotos.count) / \(session.targetSelectionCount)")
            print("Burst Groups Detected: \(session.burstGroups.count)")
            print("Person Clusters Formed: \(session.personClusters.count)")
            print("====================================================")

            #if arch(arm64)
            let archName = "arm64"
            #elseif arch(x86_64)
            let archName = "x86_64"
            #else
            let archName = "unknown"
            #endif

            // Write benchmark.json
            let benchmarkData: [String: Any] = [
                "datasetSize": processedPhotos,
                "totalProcessingTimeSeconds": Double(round(totalTime * 100) / 100),
                "photosPerSecond": Double(round(throughput * 10) / 10),
                "architecture": archName,
                "peakMemoryMB": peakMB
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: benchmarkData, options: [.prettyPrinted]) {
                let jsonURL = URL(fileURLWithPath: outputJSONPath)
                try? fileManager.createDirectory(at: jsonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? jsonData.write(to: jsonURL)
                print("✅ Written benchmark JSON to \(outputJSONPath)")
            }

            // Write BENCHMARKS.md
            let dateFormatter = ISO8601DateFormatter()
            let isoDate = dateFormatter.string(from: Date())

            let mdContent = """
            # WeddingCull Benchmark Results (Measured)

            * **Date**: \(isoDate)
            * **Architecture**: `\(archName)`
            * **Concurrency**: \(hardware.recommendedConcurrency) workers
            * **Dataset Size**: \(processedPhotos) photographs (synthetic wedding shoot with raw, jpeg, bursts, and corrupt fixtures)

            ## Execution Metrics

            | Metric | Measured Value |
            | :--- | :--- |
            | **Total Processing Time** | \(String(format: "%.2f s", totalTime)) |
            | **Sustained Throughput** | \(String(format: "%.1f photos / sec", throughput)) |
            | **Peak Resident Memory (RSS)** | \(peakMB) MB (budget: < 2500 MB) |
            | **Burst Groups Identified** | \(session.burstGroups.count) |
            | **Person Identity Clusters** | \(session.personClusters.count) |
            | **Diversity Target Met** | \(session.selectedPhotos.count) / \(session.targetSelectionCount) |

            """

            let mdURL = URL(fileURLWithPath: outputMDPath)
            try? fileManager.createDirectory(at: mdURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? mdContent.data(using: .utf8)?.write(to: mdURL)
            print("✅ Written benchmark Markdown to \(outputMDPath)")

            // Check budget constraints: memory must not exceed 2.5 GB (2560 MB)
            if peakMB > 2560 {
                print("❌ MEMORY BUDGET EXCEEDED: \(peakMB) MB > 2560 MB limit!")
                exit(1)
            }

            print("✅ Benchmark successfully completed within all hardware constraints.")
            exit(0)
        } catch {
            memorySamplingTask.cancel()
            print("❌ Pipeline analysis failed: \(error)")
            exit(1)
        }
    }
}
