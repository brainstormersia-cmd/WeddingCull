import Foundation
import SwiftUI
import AppKit
import CoreGraphics
import ImageIO

/// Asynchronous, cache-aware thumbnail and preview loader.
/// Strictly separates pure, non-mutating cache lookups from asynchronous background loading.
@MainActor
public final class ThumbnailLoader: ObservableObject {
    public let previewPipeline: PreviewPipeline

    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let previewCache = NSCache<NSString, NSImage>()

    @Published public private(set) var loadedThumbnailKeys: Set<String> = []
    @Published public private(set) var loadedPreviewKeys: Set<String> = []

    private var activeThumbnailTasks: [String: Task<CGImage?, Never>] = [:]
    private var activePreviewTasks: [String: Task<CGImage?, Never>] = [:]

    public init(previewPipeline: PreviewPipeline = PreviewPipeline()) {
        self.previewPipeline = previewPipeline

        // Cost limit ~150 MB for 320px thumbnails
        thumbnailCache.totalCostLimit = 150 * 1024 * 1024
        thumbnailCache.countLimit = 2000

        // Cost limit ~250 MB for 1000px/1600px previews
        previewCache.totalCostLimit = 250 * 1024 * 1024
        previewCache.countLimit = 80
    }

    // MARK: - Thumbnail API

    /// Pure cache lookup: safe to call from SwiftUI body without causing side effects or mutations.
    public func cachedThumbnail(for item: PhotoItem) -> NSImage? {
        let key = item.previewCacheKey as NSString
        return thumbnailCache.object(forKey: key)
    }

    /// Asynchronously requests a thumbnail. Dispatches disk I/O and generation to background utility queue.
    public func requestThumbnail(for item: PhotoItem) async -> NSImage? {
        let key = item.previewCacheKey
        let nsKey = key as NSString

        if let cached = thumbnailCache.object(forKey: nsKey) {
            return cached
        }

        let cgImage: CGImage?
        if let existingTask = activeThumbnailTasks[key] {
            cgImage = await existingTask.value
        } else {
            let pipeline = self.previewPipeline
            let task = Task.detached(priority: .utility) { () -> CGImage? in
                if Task.isCancelled { return nil }

                // Ensure thumbnail file exists or generate it
                let thumbURL = pipeline.thumbnailURL(for: item)
                if !FileManager.default.fileExists(atPath: thumbURL.path) {
                    _ = try? await pipeline.generatePreviewAndThumbnailWithImage(for: item)
                }

                if Task.isCancelled { return nil }
                return pipeline.loadThumbnailCGImage(for: item)
            }

            activeThumbnailTasks[key] = task
            cgImage = await task.value
            activeThumbnailTasks.removeValue(forKey: key)
        }

        guard let cg = cgImage else { return nil }
        let size = NSSize(width: cg.width, height: cg.height)
        let image = NSImage(cgImage: cg, size: size)
        let cost = Int(image.size.width * image.size.height * 4)
        thumbnailCache.setObject(image, forKey: nsKey, cost: cost)
        loadedThumbnailKeys.insert(key)
        return image
    }

    // MARK: - Preview API

    /// Pure preview cache lookup for burst comparison and inspector.
    public func cachedPreview(for item: PhotoItem) -> NSImage? {
        let key = item.previewCacheKey as NSString
        return previewCache.object(forKey: key)
    }

    /// Asynchronously requests a high-resolution 1000px/1600px preview for burst comparison or loupe inspection.
    public func requestPreview(for item: PhotoItem) async -> NSImage? {
        let key = item.previewCacheKey
        let nsKey = key as NSString

        if let cached = previewCache.object(forKey: nsKey) {
            return cached
        }

        let cgImage: CGImage?
        if let existingTask = activePreviewTasks[key] {
            cgImage = await existingTask.value
        } else {
            let pipeline = self.previewPipeline
            let task = Task.detached(priority: .userInitiated) { () -> CGImage? in
                if Task.isCancelled { return nil }

                let prevURL = pipeline.previewURL(for: item)
                if !FileManager.default.fileExists(atPath: prevURL.path) {
                    _ = try? await pipeline.generatePreviewAndThumbnailWithImage(for: item)
                }

                if Task.isCancelled { return nil }
                return pipeline.loadPreviewCGImage(for: item)
            }

            activePreviewTasks[key] = task
            cgImage = await task.value
            activePreviewTasks.removeValue(forKey: key)
        }

        guard let cg = cgImage else { return nil }
        let size = NSSize(width: cg.width, height: cg.height)
        let image = NSImage(cgImage: cg, size: size)
        let cost = Int(image.size.width * image.size.height * 4)
        previewCache.setObject(image, forKey: nsKey, cost: cost)
        loadedPreviewKeys.insert(key)
        return image
    }

    // MARK: - Prefetch & Cancellation

    /// Prefetches nearby thumbnails to provide buttery-smooth scrolling.
    public func prefetchThumbnails(for items: [PhotoItem]) {
        for item in items {
            let key = item.previewCacheKey as NSString
            if thumbnailCache.object(forKey: key) == nil && activeThumbnailTasks[item.previewCacheKey] == nil {
                Task { [weak self] in
                    _ = await self?.requestThumbnail(for: item)
                }
            }
        }
    }

    /// Cancels active background work for items that left the viewport.
    public func cancelThumbnailRequest(for item: PhotoItem) {
        if let task = activeThumbnailTasks.removeValue(forKey: item.previewCacheKey) {
            task.cancel()
        }
    }
}
