import Foundation
import CoreGraphics
import ImageIO

public final class PreviewPipeline: Sendable {
    public let cacheDirectory: URL
    public let previewsDirectory: URL
    public let thumbnailsDirectory: URL

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

        try? FileManager.default.createDirectory(at: previewsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
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

    public func generatePreviewAndThumbnail(for item: PhotoItem) throws -> (previewURL: URL, thumbnailURL: URL) {
        let pURL = previewURL(for: item)
        let tURL = thumbnailURL(for: item)

        if FileManager.default.fileExists(atPath: pURL.path) && FileManager.default.fileExists(atPath: tURL.path) {
            return (pURL, tURL)
        }

        try autoreleasepool {
            let sourceURL = item.sourceURL
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]

            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, options as CFDictionary) else {
                throw NSError(domain: "PreviewPipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open image source"])
            }

            // 1. Generate 1600px analysis preview
            let previewOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
            ]

            guard let previewCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, previewOptions as CFDictionary) else {
                throw NSError(domain: "PreviewPipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate preview"])
            }

            try saveCGImage(previewCGImage, to: pURL, compressionQuality: 0.85)

            // 2. Generate 320px grid thumbnail
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320
            ]

            guard let thumbCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbOptions as CFDictionary) else {
                throw NSError(domain: "PreviewPipeline", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail"])
            }

            try saveCGImage(thumbCGImage, to: tURL, compressionQuality: 0.75)
        }

        return (pURL, tURL)
    }

    public func loadPreviewCGImage(for item: PhotoItem) -> CGImage? {
        let pURL = previewURL(for: item)
        guard FileManager.default.fileExists(atPath: pURL.path) else { return nil }

        let options: [CFString: Any] = [kCGImageSourceShouldCache: true]
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
        try? FileManager.default.createDirectory(at: previewsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }
}
