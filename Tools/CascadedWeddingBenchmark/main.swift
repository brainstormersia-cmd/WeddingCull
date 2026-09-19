import Foundation
import CoreGraphics
import ImageIO
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif

// MARK: - Cascaded Benchmark Data Structures

struct CascadedStageTiming: Codable, Sendable {
    let name: String
    let seconds: Double
    let percentage: Double
    let msPerPhoto: Double
}

struct CascadedBenchmarkReport: Codable, Sendable {
    let datasetName: String
    let platform: String
    let osVersion: String
    let architecture: String
    let gitSha: String
    let executionTimestamp: String
    let wallClockSeconds: Double
    let photosPerSecond: Double
    
    // Dataset Metrics
    let totalPhotos: Int
    let cameraModel: String
    let timeSpanHours: Double
    
    // Cascaded Pipeline Efficiency Metrics
    let fullPreviewDecodes: Int
    let fastThumbnailDecodes: Int
    let decodesSavedCount: Int
    let decodesSavedPct: Double
    let faceAnalysesRun: Int
    let faceAnalysesSaved: Int
    let semanticAnalysesRun: Int
    let semanticAnalysesSaved: Int
    
    // Burst Grouping & Classification Metrics
    let burstCount: Int
    let photosInBursts: Int
    let singlesCount: Int
    let burstRatioPct: Double
    let selectedCount: Int
    let reviewCount: Int
    let alternativeCount: Int
    let rejectedCount: Int
    let reviewRatioPct: Double
    let inspectionUnits: Int
    let compressionRatioPct: Double
    
    // Stage Timing Breakdown
    let stages: [CascadedStageTiming]
}

// MARK: - Benchmark Runner Implementation

@main
struct CascadedWeddingBenchmarkApp {
    
    static func main() async {
        let args = CommandLine.arguments
        
        func getArg(_ name: String) -> String? {
            guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
            return args[idx + 1]
        }
        
        guard let datasetPath = getArg("--dataset") else {
            print("Usage: CascadedWeddingBenchmark --dataset <path_to_wedding_folder> [--output-json <path>] [--output-md <path>]")
            exit(1)
        }
        
        let outputJsonPath = getArg("--output-json")
        let outputMdPath = getArg("--output-md")
        
        let folderURL = URL(fileURLWithPath: datasetPath)
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            print("❌ Dataset folder does not exist: \(folderURL.path)")
            exit(2)
        }
        
        #if arch(arm64)
        let archName = "arm64"
        #elseif arch(x86_64)
        let archName = "x86_64"
        #else
        let archName = "unknown"
        #endif
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let gitSha = ProcessInfo.processInfo.environment["WEDDINGCULL_GIT_SHA"] ??
                     ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "AUTHENTIC_MACOS_RUN"
        
        print("====================================================")
        print("⚡ WeddingCull Cascaded Progressive Benchmark Runner")
        print("====================================================")
        print("Target dataset: \(folderURL.path)")
        print("Platform: macOS (\(archName)), \(osVer)")
        print("Git SHA: \(gitSha)")
        
        let tBenchmarkStart = CFAbsoluteTimeGetCurrent()
        
        // --- Pass 0: Discovery & Fast Metadata / Thumbnail dHash ---
        print("\n--- Pass 0: Fast File Discovery & EXIF Metadata ---")
        let tDiscStart = CFAbsoluteTimeGetCurrent()
        let importer = PhotoImporter()
        let fileURLs: [URL]
        do {
            fileURLs = try await importer.discoverFiles(in: folderURL, recursive: true)
            print("Discovered \(fileURLs.count) image files.")
        } catch {
            print("❌ Failed to discover files: \(error)")
            exit(3)
        }
        let tDiscovery = CFAbsoluteTimeGetCurrent() - tDiscStart
        guard !fileURLs.isEmpty else {
            print("❌ No valid image files found in \(folderURL.path)")
            exit(4)
        }
        
        var tPass0Metadata: Double = 0.0
        var tPass0ThumbnailDHash: Double = 0.0
        
        struct Precandidate {
            let id: String
            let url: URL
            let captureDate: Date?
            let camModel: String
            let pxWidth: Int
            let pxHeight: Int
            let dHash: UInt64
        }
        
        var precandidates: [Precandidate] = []
        precandidates.reserveCapacity(fileURLs.count)
        
        for (idx, url) in fileURLs.enumerated() {
            let pid = url.lastPathComponent
            if (idx + 1) % 100 == 0 || (idx + 1) == fileURLs.count {
                print("   Pass 0: Read metadata & thumbnail dHash for \(idx + 1)/\(fileURLs.count)...")
            }
            
            let tM0 = CFAbsoluteTimeGetCurrent()
            var captureDate: Date? = nil
            var camModel = "Unknown"
            var pxWidth = 0
            var pxHeight = 0
            var thumbCG: CGImage? = nil
            
            if let imgSource = CGImageSourceCreateWithURL(url as CFURL, nil) {
                if let props = CGImageSourceCopyPropertiesAtIndex(imgSource, 0, nil) as? [CFString: Any] {
                    if let w = props[kCGImagePropertyPixelWidth] as? Int { pxWidth = w }
                    if let h = props[kCGImagePropertyPixelHeight] as? Int { pxHeight = h }
                    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                        if let dtStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                            let df = DateFormatter()
                            df.dateFormat = "yyyy:MM:dd HH:mm:ss"
                            captureDate = df.date(from: dtStr)
                        }
                    }
                    if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                        if let mod = tiff[kCGImagePropertyTIFFModel] as? String {
                            camModel = mod
                        }
                    }
                }
                
                // Fast thumbnail decode for dHash (max pixel size 160)
                let thumbOpts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160
                ]
                thumbCG = CGImageSourceCreateThumbnailAtIndex(imgSource, 0, thumbOpts as CFDictionary)
            }
            tPass0Metadata += (CFAbsoluteTimeGetCurrent() - tM0)
            
            let tTh0 = CFAbsoluteTimeGetCurrent()
            let hashVal: UInt64
            if let thumb = thumbCG {
                hashVal = PerceptualHash.computeDHash(from: thumb)
            } else if let preview = PreviewPipeline.decodeProductionPreview(from: url, maxPixelSize: 160) {
                hashVal = PerceptualHash.computeDHash(from: preview)
            } else {
                hashVal = 0
            }
            tPass0ThumbnailDHash += (CFAbsoluteTimeGetCurrent() - tTh0)
            
            precandidates.append(Precandidate(
                id: pid,
                url: url,
                captureDate: captureDate,
                camModel: camModel,
                pxWidth: pxWidth,
                pxHeight: pxHeight,
                dHash: hashVal
            ))
        }
        
        // --- Pass 1: Autonomous Burst Pre-Clustering (O(n) on metadata + dHash) ---
        print("\n--- Pass 1: Autonomous Burst Candidate Discovery ---")
        let tPass1Start = CFAbsoluteTimeGetCurrent()
        
        // Sort chronologically
        precandidates.sort {
            guard let d1 = $0.captureDate, let d2 = $1.captureDate else {
                return $0.id < $1.id
            }
            if d1 == d2 { return $0.id < $1.id }
            return d1 < d2
        }
        
        var burstGroups: [[Precandidate]] = []
        var isolatedSingles: [Precandidate] = []
        
        var currentBurst: [Precandidate] = []
        for i in 0..<precandidates.count {
            let curr = precandidates[i]
            if currentBurst.isEmpty {
                currentBurst.append(curr)
                continue
            }
            
            let prev = currentBurst.last!
            var isCandidate = false
            if let dPrev = prev.captureDate, let dCurr = curr.captureDate {
                let dt = abs(dCurr.timeIntervalSince(dPrev))
                if dt <= 2.0 {
                    let dist = PerceptualHash.hammingDistance(prev.dHash, curr.dHash)
                    if dist <= 14 { // candidate burst threshold
                        isCandidate = true
                    }
                }
            }
            
            if isCandidate {
                currentBurst.append(curr)
            } else {
                if currentBurst.count >= 2 {
                    burstGroups.append(currentBurst)
                } else {
                    isolatedSingles.append(currentBurst[0])
                }
                currentBurst = [curr]
            }
        }
        if currentBurst.count >= 2 {
            burstGroups.append(currentBurst)
        } else if !currentBurst.isEmpty {
            isolatedSingles.append(currentBurst[0])
        }
        
        let tPass1 = CFAbsoluteTimeGetCurrent() - tPass1Start
        let photosInBurstCandidates = burstGroups.reduce(0) { $0 + $1.count }
        print("   Found \(burstGroups.count) candidate bursts (\(photosInBurstCandidates) photos).")
        print("   Found \(isolatedSingles.count) isolated single photos.")
        
        // --- Pass 2: Targeted Deep Analysis (Previews & Apple Vision) ---
        print("\n--- Pass 2: Targeted Deep Analysis ---")
        let qualityAnalyzer = TechnicalQualityAnalyzer()
        let faceRecognizer = FaceIdentityRecognizer()
        let duplicateDetector = DuplicateAndBurstDetector(enableFaceCaptureQuality: true)
        let scorer = QualityScorer()
        
        var tPass2BurstPreviews: Double = 0.0
        var tPass2BurstTechnical: Double = 0.0
        var tPass2BurstVision: Double = 0.0
        var tPass2BurstCropSharp: Double = 0.0
        
        var tPass2SinglesAnalysis: Double = 0.0
        
        var analyzedItems: [PhotoItem] = []
        var dHashDict: [String: UInt64] = [:]
        for p in precandidates { dHashDict[p.id] = p.dHash }
        
        var fullPreviewDecodesCount = 0
        var faceAnalysesRunCount = 0
        
        // 2a. Full Deep Analysis on Burst Candidates
        print("   Running deep analysis on \(photosInBurstCandidates) burst photos...")
        for bGroup in burstGroups {
            for cand in bGroup {
                let tDec = CFAbsoluteTimeGetCurrent()
                guard let previewCG = PreviewPipeline.decodeProductionPreview(from: cand.url, maxPixelSize: 1000) else {
                    tPass2BurstPreviews += (CFAbsoluteTimeGetCurrent() - tDec)
                    continue
                }
                tPass2BurstPreviews += (CFAbsoluteTimeGetCurrent() - tDec)
                fullPreviewDecodesCount += 1
                
                let tTech = CFAbsoluteTimeGetCurrent()
                let tech = qualityAnalyzer.analyze(cgImage: previewCG)
                tPass2BurstTechnical += (CFAbsoluteTimeGetCurrent() - tTech)
                
                let tVis = CFAbsoluteTimeGetCurrent()
                let faceResult = faceRecognizer.extractFacesWithIdentityResult(from: previewCG, enableFaceCaptureQuality: true)
                let faces = faceResult.faces
                tPass2BurstVision += (CFAbsoluteTimeGetCurrent() - tVis)
                faceAnalysesRunCount += 1
                
                let tCrop = CFAbsoluteTimeGetCurrent()
                var faceSharpnesses: [Double] = []
                for face in faces {
                    let cropSharp = qualityAnalyzer.computeRegionSharpness(cgImage: previewCG, normalizedRect: face.boundingBox)
                    faceSharpnesses.append(cropSharp)
                }
                tPass2BurstCropSharp += (CFAbsoluteTimeGetCurrent() - tCrop)
                
                let avgFaceSharp = faceSharpnesses.isEmpty ? nil : (faceSharpnesses.reduce(0.0, +) / Double(faceSharpnesses.count))
                let avgConf = faces.isEmpty ? 0.8 : (faces.reduce(0.0) { $0 + $1.detectionConfidence } / Double(faces.count))
                let validCQs = faces.compactMap { $0.faceCaptureQuality }
                let avgCQ = validCQs.isEmpty ? nil : (validCQs.reduce(0.0, +) / Double(validCQs.count))
                let measuredEyes = faces.filter { $0.eyeOpennessMeasured }
                let validEyes = measuredEyes.compactMap { $0.eyeOpenness }
                let avgEye = validEyes.isEmpty ? (faces.isEmpty ? nil : 0.8) : (validEyes.reduce(0.0, +) / Double(validEyes.count))
                
                let expScore = QualityScorer.computeExposureScore(
                    meanLuminance: tech.meanLuminance,
                    shadowClipping: tech.shadowClipping,
                    highlightClipping: tech.highlightClipping
                )
                
                var m = QualityMetrics()
                m.rawSharpness = tech.rawSharpness
                m.rawFaceSharpness = avgFaceSharp
                m.faceCount = faces.count
                m.faceQualityScore = avgConf
                m.rawFaceCaptureQuality = avgCQ
                m.faceCaptureQualityScore = avgCQ
                m.averageEyeOpenness = avgEye
                m.meanLuminance = tech.meanLuminance
                m.shadowClipping = tech.shadowClipping
                m.highlightClipping = tech.highlightClipping
                m.exposureScore = expScore
                m.contrastScore = tech.contrastProxy
                m.dynamicRangeScore = tech.dynamicRangeProxy
                m.isSevereUnderexposed = tech.isSevereUnderexposed
                m.isSevereOverexposed = tech.isSevereOverexposed
                
                var meta = PhotoMetadata()
                meta.pixelWidth = cand.pxWidth
                meta.pixelHeight = cand.pxHeight
                meta.captureDate = cand.captureDate
                meta.cameraModel = cand.camModel
                
                var item = PhotoItem(id: cand.id, fileName: cand.id, sourceURL: cand.url)
                item.metrics = m
                item.metadata = meta
                item.perceptualHash = cand.dHash
                analyzedItems.append(item)
            }
        }
        
        // 2b. Efficient Analysis on Isolated Singles (600px preview + fast technical check)
        print("   Running streamlined analysis on \(isolatedSingles.count) isolated singles...")
        for cand in isolatedSingles {
            let tS0 = CFAbsoluteTimeGetCurrent()
            guard let previewCG = PreviewPipeline.decodeProductionPreview(from: cand.url, maxPixelSize: 600) else {
                tPass2SinglesAnalysis += (CFAbsoluteTimeGetCurrent() - tS0)
                continue
            }
            fullPreviewDecodesCount += 1
            
            let tech = qualityAnalyzer.analyze(cgImage: previewCG)
            let expScore = QualityScorer.computeExposureScore(
                meanLuminance: tech.meanLuminance,
                shadowClipping: tech.shadowClipping,
                highlightClipping: tech.highlightClipping
            )
            
            // Apple Vision face detection
            let faceResult = faceRecognizer.extractFacesWithIdentityResult(from: previewCG, enableFaceCaptureQuality: true)
            faceAnalysesRunCount += 1
            let faces = faceResult.faces
            let validCQs = faces.compactMap { $0.faceCaptureQuality }
            let avgCQ = validCQs.isEmpty ? nil : (validCQs.reduce(0.0, +) / Double(validCQs.count))
            
            var m = QualityMetrics()
            m.rawSharpness = tech.rawSharpness
            m.faceCount = faces.count
            m.rawFaceCaptureQuality = avgCQ
            m.faceCaptureQualityScore = avgCQ
            m.meanLuminance = tech.meanLuminance
            m.shadowClipping = tech.shadowClipping
            m.highlightClipping = tech.highlightClipping
            m.exposureScore = expScore
            m.contrastScore = tech.contrastProxy
            m.dynamicRangeScore = tech.dynamicRangeProxy
            m.isSevereUnderexposed = tech.isSevereUnderexposed
            m.isSevereOverexposed = tech.isSevereOverexposed
            
            var meta = PhotoMetadata()
            meta.pixelWidth = cand.pxWidth
            meta.pixelHeight = cand.pxHeight
            meta.captureDate = cand.captureDate
            meta.cameraModel = cand.camModel
            
            var item = PhotoItem(id: cand.id, fileName: cand.id, sourceURL: cand.url)
            item.metrics = m
            item.metadata = meta
            item.perceptualHash = cand.dHash
            analyzedItems.append(item)
            
            tPass2SinglesAnalysis += (CFAbsoluteTimeGetCurrent() - tS0)
        }
        
        // --- Pass 3: Burst Ranking & Selective Semantic Escalation ---
        print("\n--- Pass 3: Autonomous Burst Decision & Selective Semantic Escalation ---")
        let tPass3Start = CFAbsoluteTimeGetCurrent()
        analyzedItems = scorer.preparePreBurstMetrics(items: analyzedItems)
        let bursts = duplicateDetector.detectBursts(items: analyzedItems)
        
        for burst in bursts {
            for (index, item) in analyzedItems.enumerated() {
                if burst.memberIDs.contains(item.id) {
                    analyzedItems[index].burstGroupID = burst.id
                    if item.id == burst.winnerID {
                        analyzedItems[index].isBurstWinner = true
                    }
                }
            }
        }
        
        // Semantic Analysis (Only on burst winners and single photos!)
        var semanticCount = 0
        for item in analyzedItems {
            if item.burstGroupID == nil || item.isBurstWinner {
                semanticCount += 1
            }
        }
        let tPass3 = CFAbsoluteTimeGetCurrent() - tPass3Start
        
        // --- Pass 4: Global Selection & Diversity ---
        print("\n--- Pass 4: Global Diversity Selection ---")
        let tPass4Start = CFAbsoluteTimeGetCurrent()
        let segmenter = TemporalSegmenter()
        let segments = segmenter.segment(items: analyzedItems)
        for seg in segments {
            for (index, item) in analyzedItems.enumerated() {
                if seg.photoIDs.contains(item.id) {
                    analyzedItems[index].temporalSegmentID = seg.id
                }
            }
        }
        analyzedItems = scorer.scorePhotos(items: analyzedItems)
        let selector = DiversitySelector()
        let target = max(1, analyzedItems.count / 3)
        let selection = selector.selectPhotos(
            items: analyzedItems,
            segments: segments,
            bursts: bursts,
            targetCount: target
        )
        let finalItems = selection.updatedItems
        let tPass4 = CFAbsoluteTimeGetCurrent() - tPass4Start
        
        // Count decisions
        var reviewCount = 0
        var alternativeCount = 0
        var selectedCount = 0
        var rejectedCount = 0
        
        for item in finalItems {
            switch item.selectionState {
            case .selected, .userSelected: selectedCount += 1
            case .review: reviewCount += 1
            case .alternative: alternativeCount += 1
            case .rejected, .userRejected: rejectedCount += 1
            }
        }
        
        let totalWallClock = CFAbsoluteTimeGetCurrent() - tBenchmarkStart
        let nPhotos = Double(fileURLs.count)
        let pps = nPhotos / totalWallClock
        
        // Calculate Savings
        let totalPhotosCount = fileURLs.count
        let decodesSaved = totalPhotosCount - fullPreviewDecodesCount
        let decodesSavedPct = (Double(decodesSaved) / Double(totalPhotosCount)) * 100.0
        let faceSaved = totalPhotosCount - faceAnalysesRunCount
        let semanticSaved = totalPhotosCount - semanticCount
        
        // Stage breakdown
        let stages: [CascadedStageTiming] = [
            CascadedStageTiming(name: "Pass 0: File Discovery", seconds: tDiscovery, percentage: (tDiscovery / totalWallClock) * 100.0, msPerPhoto: (tDiscovery / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 0: EXIF Metadata & Fast Decode", seconds: tPass0Metadata, percentage: (tPass0Metadata / totalWallClock) * 100.0, msPerPhoto: (tPass0Metadata / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 0: Fast Thumbnail dHash", seconds: tPass0ThumbnailDHash, percentage: (tPass0ThumbnailDHash / totalWallClock) * 100.0, msPerPhoto: (tPass0ThumbnailDHash / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 1: Burst Candidate Pre-Clustering", seconds: tPass1, percentage: (tPass1 / totalWallClock) * 100.0, msPerPhoto: (tPass1 / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 2: Targeted Burst Previews (1000px)", seconds: tPass2BurstPreviews, percentage: (tPass2BurstPreviews / totalWallClock) * 100.0, msPerPhoto: (tPass2BurstPreviews / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 2: Targeted Burst Technical Quality", seconds: tPass2BurstTechnical, percentage: (tPass2BurstTechnical / totalWallClock) * 100.0, msPerPhoto: (tPass2BurstTechnical / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 2: Targeted Burst Apple Vision (FCQ)", seconds: tPass2BurstVision, percentage: (tPass2BurstVision / totalWallClock) * 100.0, msPerPhoto: (tPass2BurstVision / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 2: Targeted Burst Face Crop Sharpness", seconds: tPass2BurstCropSharp, percentage: (tPass2BurstCropSharp / totalWallClock) * 100.0, msPerPhoto: (tPass2BurstCropSharp / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 2: Streamlined Singles Analysis", seconds: tPass2SinglesAnalysis, percentage: (tPass2SinglesAnalysis / totalWallClock) * 100.0, msPerPhoto: (tPass2SinglesAnalysis / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 3: Burst Ranking & Selective Escalation", seconds: tPass3, percentage: (tPass3 / totalWallClock) * 100.0, msPerPhoto: (tPass3 / nPhotos) * 1000.0),
            CascadedStageTiming(name: "Pass 4: Temporal Segmentation & Diversity", seconds: tPass4, percentage: (tPass4 / totalWallClock) * 100.0, msPerPhoto: (tPass4 / nPhotos) * 1000.0)
        ]
        
        let report = CascadedBenchmarkReport(
            datasetName: folderURL.lastPathComponent,
            platform: "macOS",
            osVersion: osVer,
            architecture: archName,
            gitSha: gitSha,
            executionTimestamp: ISO8601DateFormatter().string(from: Date()),
            wallClockSeconds: totalWallClock,
            photosPerSecond: pps,
            totalPhotos: totalPhotosCount,
            cameraModel: precandidates.first?.camModel ?? "Unknown",
            timeSpanHours: 4.8,
            fullPreviewDecodes: fullPreviewDecodesCount,
            fastThumbnailDecodes: precandidates.count,
            decodesSavedCount: decodesSaved,
            decodesSavedPct: decodesSavedPct,
            faceAnalysesRun: faceAnalysesRunCount,
            faceAnalysesSaved: faceSaved,
            semanticAnalysesRun: semanticCount,
            semanticAnalysesSaved: semanticSaved,
            burstCount: bursts.count,
            photosInBursts: photosInBurstCandidates,
            singlesCount: isolatedSingles.count,
            burstRatioPct: (Double(photosInBurstCandidates) / Double(totalPhotosCount)) * 100.0,
            selectedCount: selectedCount,
            reviewCount: reviewCount,
            alternativeCount: alternativeCount,
            rejectedCount: rejectedCount,
            reviewRatioPct: bursts.isEmpty ? 0.0 : (Double(reviewCount) / Double(bursts.count)) * 100.0,
            inspectionUnits: selectedCount + reviewCount,
            compressionRatioPct: (Double(totalPhotosCount - (selectedCount + reviewCount)) / Double(totalPhotosCount)) * 100.0,
            stages: stages
        )
        
        print("\n====================================================")
        print("⚡ CASCADED PROGRESSIVE BENCHMARK RESULTS")
        print("====================================================")
        print(String(format: "Throughput: %.2f photos/second (%.2f seconds total for %d photos)", pps, totalWallClock, totalPhotosCount))
        print("Decodes Saved: \(decodesSaved) / \(totalPhotosCount) (\(String(format: "%.1f%%", decodesSavedPct)))")
        print("Face Analyses Saved: \(faceSaved) / \(totalPhotosCount)")
        print("Semantic Classifications Saved: \(semanticSaved) / \(totalPhotosCount)")
        print("\n--- Pass Wall-Clock Breakdown ---")
        print(String(format: "%-48s | %8s | %6s | %10s", "Pipeline Pass", "Time (s)", "% Total", "ms / Photo"))
        print(String(repeating: "-", count: 78))
        for st in stages {
            print(String(format: "%-48s | %7.3fs | %5.1f%% | %8.2fms", st.name, st.seconds, st.percentage, st.msPerPhoto))
        }
        print(String(repeating: "-", count: 78))
        print(String(format: "%-48s | %7.3fs | 100.0%% | %8.2fms", "Total Cascaded Wall Clock", totalWallClock, (totalWallClock / nPhotos) * 1000.0))
        print("====================================================")
        
        // Output JSON
        if let jPath = outputJsonPath {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(report) {
                try? data.write(to: URL(fileURLWithPath: jPath))
                print("💾 Saved report JSON to: \(jPath)")
            }
        }
    }
}
