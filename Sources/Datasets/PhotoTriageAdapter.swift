import Foundation

// MARK: - Dataset Adapter Protocol

public protocol DatasetAdapter: Sendable {
    func inspect(rootURL: URL) -> (isAvailable: Bool, statusMessage: String)
    func loadDataset(from rootURL: URL) throws -> RealSeriesBenchmarkDataset
}

// MARK: - Photo Triage Adapter

/// Adapter for the Princeton Photo Triage dataset ("Automatic Triage for a Photo Series", Chang et al., ACM TOG 2016).
///
/// Directly parses the official Princeton package layout:
/// - Pairlists: `val_pairlist.txt` or `train_pairlist.txt`
/// - Reviews: `reviews_trainval/reviews_trainval/%06d.json`
/// - Images: `train_val_imgs/%06d-%02d.JPG`
///
/// Preserves native pairwise preference annotations with human vote distributions:
/// `votes_a`, `votes_b`, and crowd annotator reasons.
/// Also supports canonical `manifest.json` as a backward-compatible fast path.
public final class PhotoTriageAdapter: DatasetAdapter, Sendable {
    public enum AdapterStatus: String, Sendable {
        case awaitingExternalDataset = "AWAITING_EXTERNAL_DATASET"
        case directoryNotFound = "DIRECTORY_NOT_FOUND"
        case ready = "READY"
        case invalidLayout = "INVALID_LAYOUT"
    }

    public enum AdapterError: Error, LocalizedError {
        case datasetDirectoryNotFound(String)
        case awaitingExternalDataset(String)
        case unverifiedPackageLayout(String)
        case parseFailure(String)

        public var errorDescription: String? {
            switch self {
            case .datasetDirectoryNotFound(let path):
                return "Photo Triage root directory not found at: \(path)"
            case .awaitingExternalDataset(let msg):
                return "AWAITING_EXTERNAL_DATASET: \(msg)"
            case .unverifiedPackageLayout(let msg):
                return "Photo Triage package layout requires manual verification: \(msg)"
            case .parseFailure(let msg):
                return "Failed to parse Photo Triage data: \(msg)"
            }
        }
    }

    public init() {}

    // MARK: - Review JSON Schema

    private struct RawReviewContainer: Decodable {
        let reviews: [RawReview]
    }

    private struct RawReview: Decodable {
        let compareID1: Int?
        let compareID2: Int?
        let compareFile1: String
        let compareFile2: String
        let userChoice: String
        let reason: [String]?
    }

    // MARK: - Package Layout Detection

    public struct ResolvedLayout: Sendable {
        public let pairlistURL: URL
        public let imagesDirURL: URL
        public let reviewsDirURL: URL?

        public init(pairlistURL: URL, imagesDirURL: URL, reviewsDirURL: URL?) {
            self.pairlistURL = pairlistURL
            self.imagesDirURL = imagesDirURL
            self.reviewsDirURL = reviewsDirURL
        }
    }

    /// Attempts to detect Princeton Adobe package structure under rootURL
    public func detectPackageLayout(rootURL: URL, preferTrain: Bool = false) -> ResolvedLayout? {
        let fileManager = FileManager.default

        // 1. Locate pairlist (val or train)
        let candidatePairlistPaths: [String]
        if preferTrain {
            candidatePairlistPaths = [
                "train_val/train_pairlist.txt",
                "train_pairlist.txt",
                "train_val/val_pairlist.txt",
                "val_pairlist.txt"
            ]
        } else {
            candidatePairlistPaths = [
                "train_val/val_pairlist.txt",
                "val_pairlist.txt",
                "train_val/train_pairlist.txt",
                "train_pairlist.txt"
            ]
        }

        var foundPairlistURL: URL?
        for relPath in candidatePairlistPaths {
            let u = rootURL.appendingPathComponent(relPath)
            if fileManager.fileExists(atPath: u.path) {
                foundPairlistURL = u
                break
            }
        }
        guard let pairlistURL = foundPairlistURL else { return nil }

        // 2. Locate images directory
        let candidateImagePaths = [
            "train_val/train_val_imgs",
            "train_val_imgs",
            "images"
        ]
        var foundImagesDirURL: URL?
        for relPath in candidateImagePaths {
            let u = rootURL.appendingPathComponent(relPath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                foundImagesDirURL = u
                break
            }
        }
        guard let imagesDirURL = foundImagesDirURL else { return nil }

        // 3. Locate reviews directory (optional but highly desirable for raw votes)
        let candidateReviewPaths = [
            "train_val/reviews_trainval/reviews_trainval",
            "train_val/reviews_trainval",
            "reviews_trainval/reviews_trainval",
            "reviews_trainval",
            "reviews"
        ]
        var foundReviewsDirURL: URL?
        for relPath in candidateReviewPaths {
            let u = rootURL.appendingPathComponent(relPath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                foundReviewsDirURL = u
                break
            }
        }

        return ResolvedLayout(
            pairlistURL: pairlistURL,
            imagesDirURL: imagesDirURL,
            reviewsDirURL: foundReviewsDirURL
        )
    }

    /// Inspects a potential Photo Triage dataset directory
    public func inspect(rootURL: URL) -> (isAvailable: Bool, statusMessage: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            return (false, "Photo Triage root directory not found at \(rootURL.path)")
        }

        // Check for direct package layout first
        if let layout = detectPackageLayout(rootURL: rootURL) {
            let revMsg = layout.reviewsDirURL != nil ? "with raw reviews" : "without raw reviews"
            return (true, "Found Princeton Photo Triage package at \(rootURL.path) (\(layout.pairlistURL.lastPathComponent), \(revMsg))")
        }

        // Check for canonical manifest.json fallback
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            return (true, "Found Photo Triage manifest at \(manifestURL.path)")
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path), !contents.isEmpty else {
            return (false, "Photo Triage directory at \(rootURL.path) is empty")
        }

        return (false, "Photo Triage directory present (\(contents.count) entries), but awaiting official package layout verification. Files: [\(contents.prefix(5).joined(separator: ", "))\(contents.count > 5 ? "..." : "")]")
    }

    /// Loads dataset from root URL. Directly parses Princeton package if found, otherwise falls back to manifest.json.
    public func loadDataset(from rootURL: URL) throws -> RealSeriesBenchmarkDataset {
        let inspection = inspect(rootURL: rootURL)
        guard inspection.isAvailable else {
            throw AdapterError.awaitingExternalDataset(inspection.statusMessage)
        }

        // 1. Direct package parsing (Primary path)
        if let layout = detectPackageLayout(rootURL: rootURL) {
            return try parsePrincetonPackage(layout: layout)
        }

        // 2. Fallback to manifest.json if present
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw AdapterError.parseFailure("Could not read manifest at \(manifestURL.path)")
        }

        return try parseCanonicalManifest(data: data, rootURL: rootURL)
    }

    // MARK: - Direct Princeton Package Parser

    public static func normalizePhotoFilename(_ raw: String, seriesId: Int? = nil) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.replacingOccurrences(of: ".jpg", with: ".JPG")
        // If already 6-digit zero-padded: 000015-01.JPG
        if upper.count == 14 && upper.contains("-") {
            return upper
        }
        let parts = upper.split(separator: "-")
        if parts.count == 2 {
            let sNum = Int(parts[0]) ?? (seriesId ?? 0)
            let fPart = parts[1].replacingOccurrences(of: ".JPG", with: "")
            let pNum = Int(fPart) ?? 0
            return String(format: "%06d-%02d.JPG", sNum, pNum)
        }
        return upper
    }

    public func parsePrincetonPackage(layout: ResolvedLayout) throws -> RealSeriesBenchmarkDataset {
        guard let pairlistContent = try? String(contentsOf: layout.pairlistURL, encoding: .utf8) else {
            throw AdapterError.parseFailure("Could not read pairlist at \(layout.pairlistURL.path)")
        }

        struct Pairline {
            let seriesId: Int
            let photo1Ind: Int
            let photo2Ind: Int
            let preferenceRatio: Double
            let rank1: Int
            let rank2: Int
            let photo1Name: String
            let photo2Name: String
        }

        var seriesPairlines: [Int: [Pairline]] = [:]
        var seriesRanks: [Int: [String: Int]] = [:]
        let lines = pairlistContent.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let tokens = trimmed.split(separator: " ").map { String($0) }
            guard tokens.count >= 6,
                  let sid = Int(tokens[0]),
                  let p1 = Int(tokens[1]),
                  let p2 = Int(tokens[2]),
                  let prefRatio = Double(tokens[3]),
                  let r1 = Int(tokens[4]),
                  let r2 = Int(tokens[5]) else {
                continue
            }

            let name1 = String(format: "%06d-%02d.JPG", sid, p1)
            let name2 = String(format: "%06d-%02d.JPG", sid, p2)

            let pl = Pairline(
                seriesId: sid,
                photo1Ind: p1,
                photo2Ind: p2,
                preferenceRatio: prefRatio,
                rank1: r1,
                rank2: r2,
                photo1Name: name1,
                photo2Name: name2
            )
            seriesPairlines[sid, default: []].append(pl)

            if seriesRanks[sid] == nil {
                seriesRanks[sid] = [:]
            }
            seriesRanks[sid]?[name1] = r1
            seriesRanks[sid]?[name2] = r2
        }

        // Cache raw reviews by series ID if available
        let decoder = JSONDecoder()
        func loadReviews(for seriesId: Int) -> [RawReview] {
            guard let revDir = layout.reviewsDirURL else { return [] }
            let candidateNames = [
                String(format: "%06d.json", seriesId),
                String(format: "%d.json", seriesId)
            ]
            for cName in candidateNames {
                let fileURL = revDir.appendingPathComponent(cName)
                if let data = try? Data(contentsOf: fileURL),
                   let container = try? decoder.decode(RawReviewContainer.self, from: data) {
                    return container.reviews
                }
            }
            return []
        }

        var realSeriesList: [RealPhotoSeries] = []

        // Sort series IDs numerically for determinism
        let sortedSeriesIds = seriesPairlines.keys.sorted()

        for sid in sortedSeriesIds {
            guard let pairlines = seriesPairlines[sid], !pairlines.isEmpty else { continue }
            let reviews = loadReviews(for: sid)

            // Collect all unique photos for this series
            var photoSet = Set<String>()
            for pl in pairlines {
                photoSet.insert(pl.photo1Name)
                photoSet.insert(pl.photo2Name)
            }
            let sortedPhotos = photoSet.sorted()

            var frames: [RealSeriesFrame] = []
            for pName in sortedPhotos {
                let imgPath = layout.imagesDirURL.appendingPathComponent(pName).path
                frames.append(RealSeriesFrame(photo_id: pName, image_path: imgPath))
            }

            // Derive pairwise comparisons
            var pairwiseList: [GroundTruthPairwiseComparison] = []

            for pl in pairlines {
                let pa = pl.photo1Name
                let pb = pl.photo2Name

                var votesA = 0
                var votesB = 0
                var posReasonsA: [String] = []
                var negReasonsA: [String] = []
                var posReasonsB: [String] = []
                var negReasonsB: [String] = []

                if !reviews.isEmpty {
                    for rev in reviews {
                        let cf1 = Self.normalizePhotoFilename(rev.compareFile1, seriesId: sid)
                        let cf2 = Self.normalizePhotoFilename(rev.compareFile2, seriesId: sid)

                        if cf1 == pa && cf2 == pb {
                            if rev.userChoice.uppercased() == "LEFT" {
                                votesA += 1
                                if let r = rev.reason, r.indices.contains(0), !r[0].isEmpty { posReasonsA.append(r[0]) }
                                if let r = rev.reason, r.indices.contains(1), !r[1].isEmpty { negReasonsB.append(r[1]) }
                            } else if rev.userChoice.uppercased() == "RIGHT" {
                                votesB += 1
                                if let r = rev.reason, r.indices.contains(0), !r[0].isEmpty { posReasonsB.append(r[0]) }
                                if let r = rev.reason, r.indices.contains(1), !r[1].isEmpty { negReasonsA.append(r[1]) }
                            }
                        } else if cf1 == pb && cf2 == pa {
                            if rev.userChoice.uppercased() == "LEFT" {
                                votesB += 1
                                if let r = rev.reason, r.indices.contains(0), !r[0].isEmpty { posReasonsB.append(r[0]) }
                                if let r = rev.reason, r.indices.contains(1), !r[1].isEmpty { negReasonsA.append(r[1]) }
                            } else if rev.userChoice.uppercased() == "RIGHT" {
                                votesA += 1
                                if let r = rev.reason, r.indices.contains(0), !r[0].isEmpty { posReasonsA.append(r[0]) }
                                if let r = rev.reason, r.indices.contains(1), !r[1].isEmpty { negReasonsB.append(r[1]) }
                            }
                        }
                    }
                }

                let hasRawVotes = (votesA + votesB) > 0
                let derivedPref: String?
                if pl.rank1 < pl.rank2 {
                    derivedPref = pa
                } else if pl.rank2 < pl.rank1 {
                    derivedPref = pb
                } else {
                    derivedPref = nil
                }

                var combinedReasons: [String] = []
                for r in posReasonsA { combinedReasons.append("pos_a: \(r)") }
                for r in negReasonsA { combinedReasons.append("neg_a: \(r)") }
                for r in posReasonsB { combinedReasons.append("pos_b: \(r)") }
                for r in negReasonsB { combinedReasons.append("neg_b: \(r)") }

                pairwiseList.append(GroundTruthPairwiseComparison(
                    photo_a: pa,
                    photo_b: pb,
                    votes_a: hasRawVotes ? votesA : nil,
                    votes_b: hasRawVotes ? votesB : nil,
                    has_raw_votes: hasRawVotes,
                    derived_order_preference: derivedPref,
                    reasons: combinedReasons.isEmpty ? nil : combinedReasons
                ))
            }

            // Derive preferred order from pairlist ranks
            var preferredOrder: [String]?
            if let ranks = seriesRanks[sid] {
                preferredOrder = ranks.keys.sorted { (p1, p2) in
                    let r1 = ranks[p1] ?? 999
                    let r2 = ranks[p2] ?? 999
                    if r1 != r2 { return r1 < r2 }
                    return p1 < p2
                }
            }

            let gt = SeriesGroundTruth(
                preferred_order: preferredOrder,
                pairwise_comparisons: pairwiseList
            )

            realSeriesList.append(RealPhotoSeries(
                series_id: String(sid),
                scene_type: "burst",
                description: "Photo Triage Series \(sid)",
                frames: frames,
                ground_truth: gt
            ))
        }

        let splitName = layout.pairlistURL.lastPathComponent.contains("val") ? "Validation" : "Train"
        return RealSeriesBenchmarkDataset(
            version: "2.0",
            dataset_name: "Photo Triage (\(splitName))",
            description: "Direct parsed Princeton Adobe Photo Triage from \(layout.pairlistURL.lastPathComponent)",
            total_series: realSeriesList.count,
            total_frames: realSeriesList.reduce(0) { $0 + $1.frames.count },
            series: realSeriesList
        )
    }

    // MARK: - Manifest Parser (Backward Compatibility)

    public func parseCanonicalManifest(data: Data, rootURL: URL) throws -> RealSeriesBenchmarkDataset {
        let decoder = JSONDecoder()
        do {
            let dataset = try decoder.decode(RealSeriesBenchmarkDataset.self, from: data)
            var resolvedSeries: [RealPhotoSeries] = []
            for s in dataset.series {
                var resolvedFrames: [RealSeriesFrame] = []
                for f in s.frames {
                    let fullPath: String
                    if f.image_path.hasPrefix("/") || (f.image_path.count >= 3 && f.image_path.contains(":")) {
                        fullPath = f.image_path
                    } else {
                        fullPath = rootURL.appendingPathComponent(f.image_path).path
                    }
                    resolvedFrames.append(RealSeriesFrame(photo_id: f.photo_id, image_path: fullPath))
                }
                resolvedSeries.append(RealPhotoSeries(
                    series_id: s.series_id,
                    scene_type: s.scene_type,
                    description: s.description,
                    frames: resolvedFrames,
                    ground_truth: s.ground_truth
                ))
            }
            return RealSeriesBenchmarkDataset(
                version: dataset.version,
                dataset_name: dataset.dataset_name,
                description: dataset.description,
                total_series: resolvedSeries.count,
                total_frames: resolvedSeries.reduce(0) { $0 + $1.frames.count },
                series: resolvedSeries
            )
        } catch {
            throw AdapterError.parseFailure("Failed to decode canonical dataset: \(error.localizedDescription)")
        }
    }
}
