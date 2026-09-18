import Foundation

// MARK: - Dataset Adapter Protocol

public protocol DatasetAdapter: Sendable {
    func inspect(rootURL: URL) -> (isAvailable: Bool, statusMessage: String)
    func loadDataset(from rootURL: URL) throws -> RealSeriesBenchmarkDataset
}

// MARK: - Photo Triage Adapter

/// Adapter for the Princeton Photo Triage dataset ("Automatic Triage for a Photo Series", Chang et al., ACM TOG 2016).
///
/// Preserves native pairwise preference annotations with human vote distributions:
/// `votes_a`, `votes_b`, and optional annotator reasoning.
///
/// NOTE: Concrete parsing of package files is isolated until the official package layout is inspected.
/// When external files are missing or unverified, reports `AWAITING_EXTERNAL_DATASET`.
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

    /// Inspects a potential Photo Triage dataset directory
    public func inspect(rootURL: URL) -> (isAvailable: Bool, statusMessage: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            return (false, "Photo Triage root directory not found at \(rootURL.path)")
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path), !contents.isEmpty else {
            return (false, "Photo Triage directory at \(rootURL.path) is empty")
        }

        // Check for canonical manifest format if exported, or report pending official verification
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            return (true, "Found Photo Triage manifest at \(manifestURL.path)")
        }

        return (false, "Photo Triage directory present (\(contents.count) entries), but awaiting official package layout verification. Files: [\(contents.prefix(5).joined(separator: ", "))\(contents.count > 5 ? "..." : "")]")
    }

    /// Loads dataset from root URL. Throws an informative awaitingExternalDataset error if layout is not verified.
    public func loadDataset(from rootURL: URL) throws -> RealSeriesBenchmarkDataset {
        let inspection = inspect(rootURL: rootURL)
        guard inspection.isAvailable else {
            throw AdapterError.awaitingExternalDataset(inspection.statusMessage)
        }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw AdapterError.parseFailure("Could not read manifest at \(manifestURL.path)")
        }

        return try parseCanonicalManifest(data: data, rootURL: rootURL)
    }

    /// Parses canonical manifest JSON data
    public func parseCanonicalManifest(data: Data, rootURL: URL) throws -> RealSeriesBenchmarkDataset {
        let decoder = JSONDecoder()
        do {
            let dataset = try decoder.decode(RealSeriesBenchmarkDataset.self, from: data)
            // Resolve relative image paths if necessary
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
