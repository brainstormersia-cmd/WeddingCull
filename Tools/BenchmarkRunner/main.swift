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
        var strictMode = false

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
            case "--strict":
                strictMode = true
            default:
                break
            }
            i += 1
        }

        let targetSelectionCount = explicitTarget ?? (datasetPhotoCount >= 1000 ? 700 : min(datasetPhotoCount / 2, 700))

        print("====================================================")
        print("⏱️ WeddingCull Real Automated Benchmark Runner")
        print("====================================================")
        print("Input photo count: \(datasetPhotoCount)")
        print("Target cardinality: \(targetSelectionCount)")
        print("Strict validation: \(strictMode ? "ENABLED" : "DISABLED")")

        let datasetFolder: URL
        if let customPath = datasetPath {
            datasetFolder = URL(fileURLWithPath: customPath)
        } else {
            datasetFolder = URL(fileURLWithPath: "artifacts/benchmark_dataset_\(datasetPhotoCount)")
        }

        let fileManager = FileManager.default
        let existingFiles = (try? fileManager.contentsOfDirectory(atPath: datasetFolder.path)) ?? []
        if existingFiles.count < datasetPhotoCount {
            print("📦 Generating \(datasetPhotoCount) synthetic wedding photos at \(datasetFolder.path)...")
            try? fileManager.removeItem(at: datasetFolder)
            let generator = SyntheticWeddingGenerator()
            let config = SyntheticWeddingGenerator.GeneratorConfig(
                generateLargeImages: true,
                targetTotalPhotos: datasetPhotoCount
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
        let hardware = HardwareCapabilities()
        print("Hardware detected: \(hardware.cpuArchitecture), \(hardware.logicalProcessors) logical cores (\(hardware.recommendedConcurrency) concurrent workers)")

        let pipeline = AnalysisPipeline(hardware: hardware)
        let startTime = Date()

        do {
            let session = try await pipeline.runAnalysis(
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
            if (try? sessionManager.saveSession(session, to: sessionTempFile)) != nil {
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
            print("====================================================")

            let benchmarkData: [String: Any] = [
                "datasetType": "synthetic-wedding-benchmark",
                "inputFiles": inputFilesCount,
                "importedLogicalPhotos": processedPhotos,
                "rejectedCorrupt": corruptCount,
                "rawFileCount": rawCount,
                "jpegFileCount": jpegCount,
                "rawJpegPairs": rawJpegPairsCount,
                "totalBytes": totalBytes,
                "formatDistribution": formatCounts,
                "megapixelStats": [
                    "minMP": Double(round(minMP * 100) / 100),
                    "medianMP": Double(round(medianMP * 100) / 100),
                    "p95MP": Double(round(p95MP * 100) / 100),
                    "maxMP": Double(round(maxMP * 100) / 100)
                ],
                "hardware": [
                    "architecture": archName,
                    "logicalProcessors": hardware.logicalProcessors,
                    "physicalMemoryGB": Double(round(physicalMemGB * 10) / 10),
                    "neuralEngineAvailable": hardware.neuralEngineAvailable,
                    "metalAvailable": hardware.metalAvailable,
                    "recommendedConcurrency": hardware.recommendedConcurrency
                ],
                "classificationBackend": backendUsed,
                "datasetSize": processedPhotos,
                "totalProcessingTimeSeconds": Double(round(totalTime * 100) / 100),
                "wallClockSeconds": Double(round(totalTime * 100) / 100),
                "photosPerSecond": Double(round(throughput * 10) / 10),
                "peakMemoryMB": peakMB,
                "memoryBudgetMB": 2560,
                "memoryWithinBudget": peakMB <= 2560,
                "targetCardinality": session.targetSelectionCount,
                "finalSelectedCount": selectedCount,
                "burstGroupsDetected": session.burstGroups.count,
                "personClustersFormed": session.personClusters.count,
                "exportValidation": exportSuccess,
                "sessionPersistence": sessionReloadSuccess
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: benchmarkData, options: [.prettyPrinted, .sortedKeys]) {
                let jsonURL = URL(fileURLWithPath: outputJSONPath)
                try? fileManager.createDirectory(at: jsonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? jsonData.write(to: jsonURL)
                print("✅ Written benchmark JSON to \(outputJSONPath)")
            }

            let dateFormatter = ISO8601DateFormatter()
            let isoDate = dateFormatter.string(from: Date())
            let formatDistStr = formatCounts.sorted { $0.key < $1.key }.map { "- `\($0.key)`: \($0.value) files" }.joined(separator: "\n")

            let mdContent = """
            # WeddingCull Benchmark Results (Measured)

            * **Date**: \(isoDate)
            * **Dataset Size**: \(processedPhotos) photographs
            * **Target Cardinality**: \(session.targetSelectionCount)
            * **Final Selected**: \(selectedCount)
            * **Architecture**: `\(archName)`
            * **Throughput**: \(String(format: "%.1f photos / sec", throughput))
            * **Peak RSS**: \(peakMB) MB / 2560 MB budget

            ## Dataset Breakdown

            \(formatDistStr)

            * **Median Resolution**: \(String(format: "%.2f", medianMP)) MP
            * **p95 Resolution**: \(String(format: "%.2f", p95MP)) MP
            * **Export Verification**: \(exportSuccess ? "PASS ✅" : "FAIL ❌")
            * **Session Reload**: \(sessionReloadSuccess ? "PASS ✅" : "FAIL ❌")
            """

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
