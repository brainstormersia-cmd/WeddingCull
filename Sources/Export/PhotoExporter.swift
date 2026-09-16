import Foundation

public enum ExportFolderStructure: String, Codable, Sendable, CaseIterable {
    case singleFolder
    case byCategory
    case byEventSegment

    public var displayName: String {
        switch self {
        case .singleFolder: return "Single Folder"
        case .byCategory: return "By Category"
        case .byEventSegment: return "By Event Moment"
        }
    }
}

public enum ExportRawHandling: String, Codable, Sendable, CaseIterable {
    case rawOnly
    case jpegOnly
    case rawAndJpegPair

    public var displayName: String {
        switch self {
        case .rawOnly: return "RAW Only"
        case .jpegOnly: return "JPEG Only"
        case .rawAndJpegPair: return "RAW + JPEG (When Available)"
        }
    }
}

public struct ExportManifestEntry: Codable, Sendable {
    public let originalPath: String
    public let exportedFilename: String
    public let category: String
    public let selectionState: String
    public let overallScore: Double
    public let timestamp: String
    public let burstID: String?
    public let segmentID: String?
}

public final class PhotoExporter: Sendable {
    public init() {}

    public func exportSelection(
        items: [PhotoItem],
        to destinationDirectory: URL,
        folderStructure: ExportFolderStructure,
        rawHandling: ExportRawHandling,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> (exportedCount: Int, manifestJSONURL: URL, manifestCSVURL: URL) {
        let fileManager = FileManager.default

        // Ensure destination folder exists
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let selectedItems = items.filter { $0.selectionState.isIncludedInFinal }
        let total = selectedItems.count

        var manifestEntries: [ExportManifestEntry] = []
        var exportedFilesCount = 0

        let dateFormatter = ISO8601DateFormatter()

        for (index, item) in selectedItems.enumerated() {
            // Determine target subfolder based on structure option
            let subfolderName: String?
            switch folderStructure {
            case .singleFolder:
                subfolderName = nil
            case .byCategory:
                subfolderName = item.category.localizedNameEN
            case .byEventSegment:
                subfolderName = item.temporalSegmentID ?? "General"
            }

            let targetFolder: URL
            if let sub = subfolderName {
                targetFolder = destinationDirectory.appendingPathComponent(sub, isDirectory: true)
                try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            } else {
                targetFolder = destinationDirectory
            }

            // Determine which files to copy (RAW, JPEG, or both)
            var filesToCopy: [URL] = []
            switch rawHandling {
            case .rawOnly:
                if let raw = item.rawURL {
                    filesToCopy.append(raw)
                } else {
                    filesToCopy.append(item.sourceURL)
                }
            case .jpegOnly:
                if let jpeg = item.jpegURL {
                    filesToCopy.append(jpeg)
                } else {
                    filesToCopy.append(item.sourceURL)
                }
            case .rawAndJpegPair:
                if let raw = item.rawURL, let jpeg = item.jpegURL {
                    filesToCopy.append(raw)
                    filesToCopy.append(jpeg)
                } else {
                    filesToCopy.append(item.sourceURL)
                }
            }

            for sourceFile in filesToCopy {
                let destFile = targetFolder.appendingPathComponent(sourceFile.lastPathComponent)

                // If file already exists, do not overwrite; create unique name
                var finalDestFile = destFile
                var counter = 1
                while fileManager.fileExists(atPath: finalDestFile.path) {
                    let base = sourceFile.deletingPathExtension().lastPathComponent
                    let ext = sourceFile.pathExtension
                    finalDestFile = targetFolder.appendingPathComponent("\(base)_\(counter).\(ext)")
                    counter += 1
                }

                // Copy file byte-for-byte; NEVER touch or modify original!
                try fileManager.copyItem(at: sourceFile, to: finalDestFile)
                exportedFilesCount += 1

                let dateStr = item.metadata.captureDate != nil ? dateFormatter.string(from: item.metadata.captureDate!) : ""
                manifestEntries.append(ExportManifestEntry(
                    originalPath: sourceFile.path,
                    exportedFilename: finalDestFile.lastPathComponent,
                    category: item.category.rawValue,
                    selectionState: item.selectionState.rawValue,
                    overallScore: item.metrics.overallScore,
                    timestamp: dateStr,
                    burstID: item.burstGroupID,
                    segmentID: item.temporalSegmentID
                ))
            }

            progress?(index + 1, total)
        }

        // Write WeddingCull-selection.json
        let jsonURL = destinationDirectory.appendingPathComponent("WeddingCull-selection.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(manifestEntries)
        try jsonData.write(to: jsonURL)

        // Write WeddingCull-selection.csv
        let csvURL = destinationDirectory.appendingPathComponent("WeddingCull-selection.csv")
        var csvContent = "originalPath,exportedFilename,category,selectionState,overallScore,timestamp,burstID,segmentID\n"
        for entry in manifestEntries {
            let burst = entry.burstID ?? ""
            let seg = entry.segmentID ?? ""
            csvContent += "\"\(entry.originalPath)\",\"\(entry.exportedFilename)\",\"\(entry.category)\",\"\(entry.selectionState)\",\(String(format: "%.3f", entry.overallScore)),\"\(entry.timestamp)\",\"\(burst)\",\"\(seg)\"\n"
        }
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        return (exportedFilesCount, jsonURL, csvURL)
    }
}
