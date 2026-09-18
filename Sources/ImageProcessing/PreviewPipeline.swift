import Foundation
import CoreGraphics
import ImageIO

private actor InFlightManager {
    private var inFlight: [String: Task<(previewURL: URL, thumbnailURL: URL, previewImage: CGImage?), Error>] = [:]

    func execute(
        key: String,
        operation: @Sendable @escaping () throws -> (previewURL: URL, thumbnailURL: URL, previewImage: CGImage?)
    ) async throws -> (previewURL: URL, thumbnailURL: URL, previewImage: CGImage?) {
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task.detached(priority: .userInitiated) {
            return try operation()
        }
        inFlight[key] = task
        defer {
            inFlight.removeValue(forKey: key)
        }
        return try await task.value
    }
}

public final class PreviewPipeline: Sendable {
    public let cacheDirectory: URL
    public let previewsDirectory: URL
    public let thumbnailsDirectory: URL
    public let analysisCache: AnalysisCache

    private let inFlightManager = InFlightManager()

    public init(customCacheDirectory: URL? = nil) {
        let baseDir: URL
        if let custom = customCacheDirectory {
            baseDir = custom
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            baseDir = caches.appendingPathComponent("WeddingCull", isDirectory: true)
        }
        self.cacheDirectory = baseDir
        self.previewsDirectory = baseDir.appendingPathComponent("previews", isDirectory: true)
        self.thumbnailsDirectory = baseDir.appendingPathComponent("thumbs", isDirectory: true)
        self.analysisCache = AnalysisCache(baseCacheDirectory: baseDir)

        try? FileManager.default.createDirectory(at: previewsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    public func loadAnalysisRecord(for item: PhotoItem, expectedBackend: String? = nil) -> CachedAnalysisRecord? {
        return analysisCache.loadRecord(for: item, expectedBackend: expectedBackend)
    }

    public func saveAnalysisRecord(_ record: CachedAnalysisRecord) {
        analysisCache.saveRecord(record)
    }

    public func previewURL(for item: PhotoItem) -> URL {
        return previewsDirectory.appendingPathComponent("\(item.previewCacheKey).jpg")
    }

    public func thumbnailURL(for item: PhotoItem) -> URL {
        return thumbnailsDirectory.appendingPathComponent("\(item.previewCacheKey)_thumb.jpg")
    }

    public func hasPreview(for item: PhotoItem) -> Bool {
        return FileManager.default.fileExists(atPath: previewURL(for: item).path)
    }

    @discardableResult
    public func generatePreviewAndThumbnail(for item: PhotoItem) throws -> (previewURL: URL, thumbnailURL: URL) {
        let result = try performGeneratePreviewAndThumbnail(for: item)
        return (result.previewURL, result.thumbnailURL)
    }

    public func generatePreviewAndThumbnailWithImage(for item: PhotoItem) throws -> (previewURL: URL, thumbnailURL: URL, previewImage: CGImage?) {
        return try performGeneratePreviewAndThumbnail(for: item)
    }

    /// Asynchronous convenience calling the pure decoding and downsampling engine with in-flight deduplication.
    public func generatePreviewAndThumbnailWithImage(for item: PhotoItem) async throws -> (previewURL: URL, thumbnailURL: URL, previewImage: CGImage?) {
        let pURL = previewURL(for: item)
        let tURL = thumbnailURL(for: item)

        if FileManager.default.fileExists(atPath: pURL.path) && FileManager.default.fileExists(atPath: tURL.path) {
            let cachedImage = loadPreviewCGImage(for: item)
            return (pURL, tURL, cachedImage)
        }

        return try await inFlightManager.execute(key: item.previewCacheKey) { [self] in
            return try self.performGeneratePreviewAndThumbnail(for: item)
        }
    }

    public func performGeneratePreviewAndThumbnail(for item: PhotoItem) throws -> (previewURL: URL, thumbnailURL: URL, previewImage: CGImage?) {
        let pURL = previewURL(for: item)
        let tURL = thumbnailURL(for: item)

        if FileManager.default.fileExists(atPath: pURL.path) && FileManager.default.fileExists(atPath: tURL.path) {
            let cachedImage = loadPreviewCGImage(for: item)
            return (pURL, tURL, cachedImage)
        }

        var inMemoryPreview: CGImage? = nil

        try autoreleasepool {
            let sourceURL = item.sourceURL
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]

            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, options as CFDictionary) else {
                throw NSError(domain: "PreviewPipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open image source"])
            }

            // Fallback chain for 1000px preview:
            // 1. Try standard thumbnail generation
            var previewCGImage: CGImage? = nil
            let previewOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1000
            ]
            previewCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, previewOptions as CFDictionary)

            // 2. If thumbnail fails, try full image decode and downsample
            if previewCGImage == nil {
                let fullOptions: [CFString: Any] = [
                    kCGImageSourceShouldCache: false
                ]
                if let fullImage = CGImageSourceCreateImageAtIndex(imageSource, 0, fullOptions as CFDictionary) {
                    previewCGImage = downsample(cgImage: fullImage, maxPixelSize: 1000)
                }
            }

            guard let finalPreview = previewCGImage else {
                throw NSError(domain: "PreviewPipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate preview: RAW/image decode unsupported on this configuration"])
            }

            try saveCGImage(finalPreview, to: pURL, compressionQuality: 0.85)
            inMemoryPreview = finalPreview

            // 2. Generate 320px grid thumbnail directly from in-memory preview
            var thumbCGImage = downsample(cgImage: finalPreview, maxPixelSize: 320)
            if thumbCGImage == nil {
                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320
                ]
                thumbCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbOptions as CFDictionary)
            }

            guard let finalThumb = thumbCGImage else {
                throw NSError(domain: "PreviewPipeline", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail"])
            }

            try saveCGImage(finalThumb, to: tURL, compressionQuality: 0.75)
        }

        return (pURL, tURL, inMemoryPreview)
    }

    public func downsample(cgImage: CGImage, maxPixelSize: Int) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return nil }

        let maxDim = max(width, height)
        if maxDim <= maxPixelSize {
            return cgImage
        }

        let scale = Double(maxPixelSize) / Double(maxDim)
        let targetWidth = max(1, Int(Double(width) * scale))
        let targetHeight = max(1, Int(Double(height) * scale))

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    public func loadThumbnailCGImage(for item: PhotoItem) -> CGImage? {
        let tURL = thumbnailURL(for: item)
        guard FileManager.default.fileExists(atPath: tURL.path) else { return nil }

        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(tURL as CFURL, options as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    public func loadPreviewCGImage(for item: PhotoItem) -> CGImage? {
        let pURL = previewURL(for: item)
        guard FileManager.default.fileExists(atPath: pURL.path) else { return nil }

        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(pURL as CFURL, options as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    private func saveCGImage(_ cgImage: CGImage, to fileURL: URL, compressionQuality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "PreviewPipeline", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "PreviewPipeline", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination"])
        }
    }

    public func clearCache() {
        try? FileManager.default.removeItem(at: previewsDirectory)
        try? FileManager.default.removeItem(at: thumbnailsDirectory)
        analysisCache.clear()
        try? FileManager.default.createDirectory(at: previewsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }
}
