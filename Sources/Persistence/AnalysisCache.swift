import Foundation
#if canImport(Vision)
import Vision
#endif

public struct CachedAnalysisRecord: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let photoID: String
    public let previewCacheKey: String
    public let fileSizeBytes: Int64
    public let fileModificationDate: Date
    public let metrics: QualityMetrics
    public let perceptualHash: UInt64?
    public let category: WeddingCategory
    public let categoryConfidence: Double
    public let visionScores: [String: Double]
    public let faces: [FaceInstance]
    public let featurePrintData: Data?
    public let classificationBackend: String

    public init(
        schemaVersion: Int = CachedAnalysisRecord.currentSchemaVersion,
        photoID: String,
        previewCacheKey: String,
        fileSizeBytes: Int64,
        fileModificationDate: Date,
        metrics: QualityMetrics,
        perceptualHash: UInt64?,
        category: WeddingCategory,
        categoryConfidence: Double,
        visionScores: [WeddingCategory: Double],
        faces: [FaceInstance],
        featurePrintData: Data? = nil,
        classificationBackend: String
    ) {
        self.schemaVersion = schemaVersion
        self.photoID = photoID
        self.previewCacheKey = previewCacheKey
        self.fileSizeBytes = fileSizeBytes
        self.fileModificationDate = fileModificationDate
        self.metrics = metrics
        self.perceptualHash = perceptualHash
        self.category = category
        self.categoryConfidence = categoryConfidence
        var strScores: [String: Double] = [:]
        for (cat, score) in visionScores {
            strScores[cat.rawValue] = score
        }
        self.visionScores = strScores
        self.faces = faces
        self.featurePrintData = featurePrintData
        self.classificationBackend = classificationBackend
    }

    public var typedVisionScores: [WeddingCategory: Double] {
        var result: [WeddingCategory: Double] = [:]
        for (key, val) in visionScores {
            if let cat = WeddingCategory(rawValue: key) {
                result[cat] = val
            }
        }
        return result
    }
}

public final class AnalysisCache: Sendable {
    public let cacheDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseCacheDirectory: URL) {
        self.cacheDirectory = baseCacheDirectory.appendingPathComponent("analysis", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func recordURL(for cacheKey: String, backend: String? = nil) -> URL {
        if let b = backend {
            let sanitized = b.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")
            return cacheDirectory.appendingPathComponent("\(cacheKey)_\(sanitized)_analysis.json")
        }
        return cacheDirectory.appendingPathComponent("\(cacheKey)_analysis.json")
    }

    public func loadRecord(for item: PhotoItem, expectedBackend: String? = nil) -> CachedAnalysisRecord? {
        let fileURL = recordURL(for: item.previewCacheKey, backend: expectedBackend)
        let resolvedURL: URL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            resolvedURL = fileURL
        } else {
            let fallbackURL = recordURL(for: item.previewCacheKey, backend: nil)
            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                resolvedURL = fallbackURL
            } else {
                return nil
            }
        }

        guard let data = try? Data(contentsOf: resolvedURL),
              let record = try? decoder.decode(CachedAnalysisRecord.self, from: data) else {
            return nil
        }

        // Validate integrity against source photo attributes
        guard record.schemaVersion == CachedAnalysisRecord.currentSchemaVersion,
              record.fileSizeBytes == item.fileSizeBytes,
              abs(record.fileModificationDate.timeIntervalSince(item.fileModificationDate)) < 1.0 else {
            return nil
        }

        if let expected = expectedBackend, record.classificationBackend != expected {
            return nil
        }

        return record
    }

    public func saveRecord(_ record: CachedAnalysisRecord) {
        let fileURL = recordURL(for: record.previewCacheKey, backend: record.classificationBackend)
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
