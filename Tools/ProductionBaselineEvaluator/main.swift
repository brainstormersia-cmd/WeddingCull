import Foundation
import CoreGraphics
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif

// MARK: - Canonical Ranking Output Schema

struct CanonicalPhotoRankOutput: Codable, Sendable {
    let series_id: String
    let winner_id: String
    let ranked_photo_ids: [String]
    let review_ids: [String]
    let member_count: Int
    let has_faces: Bool
}

struct CanonicalBaselineReport: Codable, Sendable {
    let tool_name: String
    let git_sha: String
    let platform: String
    let os_version: String
    let architecture: String
    let execution_timestamp: String
    let dataset_description: String
    let total_series: Int
    let series_evaluations: [CanonicalPhotoRankOutput]
}

@main
struct ProductionBaselineEvaluatorApp {
    
    static func main() async {
        let args = CommandLine.arguments
        
        func getArg(_ name: String) -> String? {
            guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
            return args[idx + 1]
        }
        
        guard let manifestPath = getArg("--manifest") else {
            print("Usage: ProductionBaselineEvaluator --manifest <manifest.json> [--features <features.jsonl>] [--output <output.json>]")
            print("Example: ProductionBaselineEvaluator --manifest X:/WeddingCullDatasets/derived/manifests/photo_triage_val.json --features photo_triage_val_features_authentic.jsonl --output artifacts/phototriage_canonical_swift_baseline.json")
            exit(1)
        }
        
        let featuresPath = getArg("--features")
        let outputPath = getArg("--output") ?? "artifacts/phototriage_canonical_swift_baseline.json"
        
        #if arch(arm64)
        let archName = "arm64"
        #elseif arch(x86_64)
        let archName = "x86_64"
        #else
        let archName = "unknown"
        #endif
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let gitSha = ProcessInfo.processInfo.environment["WEDDINGCULL_GIT_SHA"] ??
                     ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "CANONICAL_SWIFT_LOCAL"
        
        print("===================================================================")
        print("🎯 WeddingCull Canonical Native Production Baseline Evaluator")
        print("===================================================================")
        print("Manifest: \(manifestPath)")
        print("Features: \(featuresPath ?? "Direct Image Extraction")")
        print("Output:   \(outputPath)")
        print("Platform: macOS (\(archName)), \(osVer)")
        print("Git SHA:  \(gitSha)")
        
        // 1. Load Manifest
        let mURL = URL(fileURLWithPath: manifestPath)
        guard let mData = try? Data(contentsOf: mURL),
              let mJson = try? JSONSerialization.jsonObject(with: mData) as? [String: Any],
              let seriesDict = mJson["series"] as? [String: [String: Any]] else {
            print("❌ Failed to load manifest at \(manifestPath)")
            exit(2)
        }
        print("Loaded \(seriesDict.count) series from manifest.")
        
        // 2. Load Features Cache if provided
        var featuresCache: [String: [String: Any]] = [:]
        if let fPath = featuresPath {
            let fURL = URL(fileURLWithPath: fPath)
            if let fString = try? String(contentsOf: fURL, encoding: .utf8) {
                let lines = fString.split(separator: "\n")
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty,
                          let lData = trimmed.data(using: .utf8),
                          let lJson = try? JSONSerialization.jsonObject(with: lData) as? [String: Any] else {
                        continue
                    }
                    if let pid = lJson["photo_id"] as? String {
                        featuresCache[pid] = lJson
                    }
                }
            }
            print("Loaded authentic features for \(featuresCache.count) photos from cache.")
        }
        
        // 3. Initialize Production DuplicateAndBurstDetector
        // Authoritative production detector with enableFaceCaptureQuality = true
        let detector = DuplicateAndBurstDetector(enableFaceCaptureQuality: true)
        
        var outputs: [CanonicalPhotoRankOutput] = []
        let sortedSeriesKeys = seriesDict.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        
        for sid in sortedSeriesKeys {
            guard let sData = seriesDict[sid] else { continue }
            let photoList = sData["photos"] as? [Any] ?? []
            var items: [PhotoItem] = []
            
            for pItem in photoList {
                let filename: String
                if let pDict = pItem as? [String: Any] {
                    filename = (pDict["filename"] as? String) ?? ""
                } else if let pStr = pItem as? String {
                    filename = pStr
                } else {
                    continue
                }
                guard !filename.isEmpty else { continue }
                
                var item = PhotoItem(id: filename, fileName: filename, sourceURL: URL(fileURLWithPath: filename))
                var metrics = QualityMetrics()
                
                if let feat = featuresCache[filename] {
                    metrics.rawSharpness = (feat["rawSharpness"] as? Double) ?? 0.0
                    metrics.rawFaceSharpness = feat["rawFaceSharpness"] as? Double
                    metrics.faceCount = (feat["face_count"] as? Int) ?? (feat["faceCount"] as? Int) ?? 0
                    metrics.rawFaceCaptureQuality = feat["faceCaptureQuality"] as? Double
                    metrics.faceCaptureQualityScore = feat["faceCaptureQuality"] as? Double
                    metrics.faceQualityScore = (feat["faceQualityScore"] as? Double) ?? 0.8
                    metrics.averageEyeOpenness = feat["averageEyeOpenness"] as? Double
                    metrics.meanLuminance = (feat["meanLuminance"] as? Double) ?? 0.5
                    metrics.shadowClipping = (feat["shadowClipping"] as? Double) ?? 0.0
                    metrics.highlightClipping = (feat["highlightClipping"] as? Double) ?? 0.0
                    metrics.exposureScore = (feat["exposureScore"] as? Double) ?? 0.5
                    metrics.contrastProxy = (feat["contrast"] as? Double) ?? 0.5
                    metrics.dynamicRangeProxy = (feat["dynamicRange"] as? Double) ?? 0.5
                    metrics.isSevereUnderexposed = (feat["severeUnderexposure"] as? Bool) ?? false
                    metrics.isSevereOverexposed = (feat["severeOverexposure"] as? Bool) ?? false
                }
                
                item.metrics = metrics
                items.append(item)
            }
            
            guard !items.isEmpty else { continue }
            
            // AUTHORITATIVE PRODUCTION OPERATION:
            // createBurstGroup(from:) ranks the frames and returns winnerID and alternativeIDs
            let burstGroup = detector.createBurstGroup(from: items)
            let rankedPhotoIDs = [burstGroup.winnerID] + burstGroup.alternativeIDs
            let hasFaces = items.contains { $0.metrics.faceCount > 0 }
            
            outputs.append(CanonicalPhotoRankOutput(
                series_id: sid,
                winner_id: burstGroup.winnerID,
                ranked_photo_ids: rankedPhotoIDs,
                review_ids: burstGroup.reviewIDs,
                member_count: items.count,
                has_faces: hasFaces
            ))
        }
        
        print("✅ Computed canonical rankings for \(outputs.count) series.")
        
        let report = CanonicalBaselineReport(
            tool_name: "ProductionBaselineEvaluator",
            git_sha: gitSha,
            platform: "macOS",
            os_version: osVer,
            architecture: archName,
            execution_timestamp: ISO8601DateFormatter().string(from: Date()),
            dataset_description: "Photo Triage within-series ranking evaluated via DuplicateAndBurstDetector.createBurstGroup(from:)",
            total_series: outputs.count,
            series_evaluations: outputs
        )
        
        // Write Output JSON
        let outURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            try? data.write(to: outURL)
            print("💾 Saved canonical baseline JSON to: \(outputPath)")
        } else {
            print("❌ Failed to encode canonical report JSON.")
            exit(3)
        }
    }
}
