import Foundation
import ImageIO

public actor PhotoImporter {
    public static let standardExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif"
    ]

    public static let rawExtensions: Set<String> = [
        "cr2", "cr3", "nef", "nrw", "arw", "raf", "orf", "rw2", "dng"
    ]

    public static var allSupportedExtensions: Set<String> {
        return standardExtensions.union(rawExtensions)
    }

    public init() {}

    public func discoverFiles(
        in folderURL: URL,
        recursive: Bool = true,
        progressHandler: (@Sendable (Int) -> Void)? = nil
    ) async throws -> [URL] {
        var discoveredURLs: [URL] = []
        let fileManager = FileManager.default

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]

        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            return []
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            let ext = fileURL.pathExtension.lowercased()
            if Self.allSupportedExtensions.contains(ext) {
                discoveredURLs.append(fileURL)
                count += 1
                if count % 100 == 0 {
                    progressHandler?(count)
                }
            }
        }
        progressHandler?(discoveredURLs.count)
        return discoveredURLs
    }

    public func groupRawJpegPairs(fileURLs: [URL]) -> [(primary: URL, raw: URL?, jpeg: URL?)] {
        // Group by directory + lowercase base filename
        var grouped: [String: (raw: URL?, jpeg: URL?, other: URL?)] = [:]

        for url in fileURLs {
            let dir = url.deletingLastPathComponent().path
            let baseName = url.deletingPathExtension().lastPathComponent.lowercased()
            let key = "\(dir)/\(baseName)"
            let ext = url.pathExtension.lowercased()

            var entry = grouped[key] ?? (raw: nil, jpeg: nil, other: nil)
            if Self.rawExtensions.contains(ext) {
                entry.raw = url
            } else if ext == "jpg" || ext == "jpeg" {
                entry.jpeg = url
            } else {
                entry.other = url
            }
            grouped[key] = entry
        }

        var results: [(primary: URL, raw: URL?, jpeg: URL?)] = []
        for (_, entry) in grouped {
            if let raw = entry.raw, let jpeg = entry.jpeg {
                // Pair found! Primary defaults to RAW (preserves maximum quality and metadata)
                results.append((primary: raw, raw: raw, jpeg: jpeg))
            } else if let raw = entry.raw {
                results.append((primary: raw, raw: raw, jpeg: nil))
            } else if let jpeg = entry.jpeg {
                results.append((primary: jpeg, raw: nil, jpeg: jpeg))
            } else if let other = entry.other {
                results.append((primary: other, raw: nil, jpeg: nil))
            }
        }

        // Sort by file path for deterministic order
        return results.sorted { $0.primary.path < $1.primary.path }
    }

    public func importPhotos(
        from folderURL: URL,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [PhotoItem] {
        let discoveredURLs = try await discoverFiles(in: folderURL, recursive: true)
        let paired = groupRawJpegPairs(fileURLs: discoveredURLs)
        var items: [PhotoItem] = []
        items.reserveCapacity(paired.count)

        let total = paired.count
        for (index, pair) in paired.enumerated() {
            if Task.isCancelled { break }

            let primaryURL = pair.primary
            let item = readPhotoItem(primaryURL: primaryURL, rawURL: pair.raw, jpegURL: pair.jpeg, rootFolder: folderURL)
            items.append(item)

            if (index + 1) % 50 == 0 || index + 1 == total {
                progress?(index + 1, total)
            }
        }

        return items
    }

    public func readPhotoItem(primaryURL: URL, rawURL: URL?, jpegURL: URL?, rootFolder: URL) -> PhotoItem {
        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: primaryURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modDate = (attributes?[.modificationDate] as? Date) ?? Date()

        // Extract metadata using ImageIO (never load full bitmap!)
        let metadata = extractMetadata(from: primaryURL)

        // Stable ID: relative path + size + modDate
        let relativePath = primaryURL.path.replacingOccurrences(of: rootFolder.path, with: "")
        let idString = "\(relativePath)_\(fileSize)_\(Int(modDate.timeIntervalSince1970))"
        let stableID = UUID(uuidString: idString) ?? UUID()

        let cacheKey = "\(idString.hashValue)_\(fileSize)_\(Int(modDate.timeIntervalSince1970))"

        return PhotoItem(
            id: stableID.uuidString,
            fileName: primaryURL.lastPathComponent,
            sourceURL: primaryURL,
            rawURL: rawURL,
            jpegURL: jpegURL,
            fileSizeBytes: fileSize,
            fileModificationDate: modDate,
            metadata: metadata,
            previewCacheKey: cacheKey
        )
    }

    public func extractMetadata(from url: URL) -> PhotoMetadata {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return PhotoMetadata(isCorrupt: true)
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options as CFDictionary) as? [CFString: Any] else {
            return PhotoMetadata(isCorrupt: false)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1

        var captureDate: Date? = nil
        var cameraMake: String? = nil
        var cameraModel: String? = nil
        var lensModel: String? = nil
        var focalLength: Double? = nil
        var aperture: Double? = nil
        var shutterSpeed: Double? = nil
        var iso: Int? = nil
        var burstUUID: String? = nil
        let hasGPS = properties[kCGImagePropertyGPSDictionary] != nil

        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            lensModel = exif[kCGImagePropertyExifLensModel] as? String
            focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
            aperture = exif[kCGImagePropertyExifFNumber] as? Double
            shutterSpeed = exif[kCGImagePropertyExifExposureTime] as? Double
            if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let firstIso = isoArray.first {
                iso = firstIso
            } else if let singleIso = exif[kCGImagePropertyExifISOSpeedRatings] as? Int {
                iso = singleIso
            }

            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                captureDate = formatter.date(from: dateString)
            }
        }

        if let makerApple = properties["{MakerApple}" as CFString] as? [CFString: Any] {
            burstUUID = makerApple["11" as CFString] as? String
        }

        return PhotoMetadata(
            width: width,
            height: height,
            orientation: orientation,
            captureDate: captureDate,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensModel: lensModel,
            focalLength: focalLength,
            aperture: aperture,
            shutterSpeed: shutterSpeed,
            iso: iso,
            hasGPS: hasGPS,
            burstUUID: burstUUID,
            isCorrupt: width == 0 && height == 0
        )
    }
}
