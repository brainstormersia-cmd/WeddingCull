import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

public struct PhotoItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let fileName: String
    public let sourceURL: URL
    public var rawURL: URL?
    public var jpegURL: URL?
    public var fileSizeBytes: Int64
    public var fileModificationDate: Date
    public var metadata: PhotoMetadata
    public var metrics: QualityMetrics
    public var category: WeddingCategory
    public var categoryConfidence: Double
    public var selectionState: SelectionState
    public var burstGroupID: String?
    public var isBurstWinner: Bool
    public var temporalSegmentID: String?
    public var personClusterIDs: [String]
    public var perceptualHash: UInt64?
    public var isDuplicate: Bool
    public var duplicateOfID: String?
    public var previewCacheKey: String

    public static func deterministicSHA256Hex(_ string: String) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return string
        #endif
    }

    public static func computeStableID(relativePath: String, fileSize: Int64, modDate: Date) -> String {
        let raw = "\(relativePath):\(fileSize):\(Int(modDate.timeIntervalSince1970))"
        return deterministicSHA256Hex(raw)
    }

    public static func computePreviewCacheKey(sourcePath: String, fileSize: Int64, modDate: Date) -> String {
        let raw = "\(sourcePath):\(fileSize):\(Int(modDate.timeIntervalSince1970))"
        return "prev_" + deterministicSHA256Hex(raw)
    }

    public init(
        id: String = "",
        fileName: String,
        sourceURL: URL,
        rawURL: URL? = nil,
        jpegURL: URL? = nil,
        fileSizeBytes: Int64 = 0,
        fileModificationDate: Date = Date(),
        metadata: PhotoMetadata = PhotoMetadata(),
        metrics: QualityMetrics = QualityMetrics(),
        category: WeddingCategory = .other,
        categoryConfidence: Double = 0.5,
        selectionState: SelectionState = .alternative,
        burstGroupID: String? = nil,
        isBurstWinner: Bool = false,
        temporalSegmentID: String? = nil,
        personClusterIDs: [String] = [],
        perceptualHash: UInt64? = nil,
        isDuplicate: Bool = false,
        duplicateOfID: String? = nil,
        previewCacheKey: String = ""
    ) {
        let computedID = id.isEmpty ? PhotoItem.computeStableID(relativePath: sourceURL.lastPathComponent, fileSize: fileSizeBytes, modDate: fileModificationDate) : id
        self.id = computedID
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.rawURL = rawURL
        self.jpegURL = jpegURL
        self.fileSizeBytes = fileSizeBytes
        self.fileModificationDate = fileModificationDate
        self.metadata = metadata
        self.metrics = metrics
        self.category = category
        self.categoryConfidence = categoryConfidence
        self.selectionState = selectionState
        self.burstGroupID = burstGroupID
        self.isBurstWinner = isBurstWinner
        self.temporalSegmentID = temporalSegmentID
        self.personClusterIDs = personClusterIDs
        self.perceptualHash = perceptualHash
        self.isDuplicate = isDuplicate
        self.duplicateOfID = duplicateOfID
        self.previewCacheKey = previewCacheKey.isEmpty ? PhotoItem.computePreviewCacheKey(sourcePath: sourceURL.path, fileSize: fileSizeBytes, modDate: fileModificationDate) : previewCacheKey
    }

    public var hasRawJpegPair: Bool {
        return rawURL != nil && jpegURL != nil
    }

    public var isSelected: Bool {
        return selectionState.isIncludedInFinal
    }
}
