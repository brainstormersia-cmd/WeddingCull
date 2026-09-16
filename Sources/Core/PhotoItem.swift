import Foundation

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

    public init(
        id: String = UUID().uuidString,
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
        self.id = id
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
        self.previewCacheKey = previewCacheKey.isEmpty ? "\(sourceURL.path.hashValue)_\(fileSizeBytes)_\(fileModificationDate.timeIntervalSince1970)" : previewCacheKey
    }

    public var hasRawJpegPair: Bool {
        return rawURL != nil && jpegURL != nil
    }

    public var isSelected: Bool {
        return selectionState.isIncludedInFinal
    }
}
