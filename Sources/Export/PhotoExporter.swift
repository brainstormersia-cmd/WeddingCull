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

    public func editorialRating(for state: SelectionState) -> (rating: Int, label: String, urgency: String) {
        switch state {
        case .selected, .userSelected:
            return (5, "Green", "1")
        case .review:
            return (4, "Blue", "2")
        case .alternative:
            return (3, "Yellow", "2")
        case .rejected, .userRejected:
            return (1, "Red", "3")
        }
    }

    private func xmlEscape(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }

    /// Generates standard XMP Dublin Core and IPTC sidecar XML content for a photo item.
    /// Strictly uses editorial ratings:
    /// - Selected / UserSelected -> 5 stars, Green label, Urgency 1
    /// - Alternative -> 3 stars, Yellow label, Urgency 2
    /// - Rejected / UserRejected -> 1 star, Red label, Urgency 3
    /// AI numeric quality scores are NEVER injected into xmp:Rating.
    public func generateXMP(for item: PhotoItem) -> String {
        let (rating, label, urgency) = editorialRating(for: item.selectionState)
        let statusTag = xmlEscape(item.selectionState.displayName)
        let categoryTag = xmlEscape(item.category.localizedNameEN)

        var tags: [String] = [statusTag, categoryTag]
        if let segment = item.temporalSegmentID, !segment.isEmpty {
            tags.append(xmlEscape(segment))
        }

        let tagsXML = tags.map { "     <rdf:li>\($0)</rdf:li>" }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="WeddingCull">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmp:Rating="\(rating)"
            xmp:Label="\(label)"
            photoshop:Urgency="\(urgency)">
           <dc:subject>
            <rdf:Bag>
        \(tagsXML)
            </rdf:Bag>
           </dc:subject>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }

    /// Writes an XMP sidecar file for a photo item at the specified URL.
    public func writeXMPSidecar(for item: PhotoItem, at sidecarURL: URL) throws {
        let xmpContent = generateXMP(for: item)
        let parentDir = sidecarURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try xmpContent.write(to: sidecarURL, atomically: true, encoding: .utf8)
    }

    /// Exports XMP sidecars in-place alongside the original photos in their source folders.
    /// Original photos are NEVER modified; only non-destructive .xmp sidecars are created.
    /// For RAW+JPEG pairs sharing a folder and base filename, exactly one shared .xmp sidecar is written.
    @discardableResult
    public func exportXMPSidecarsInPlace(
        for items: [PhotoItem],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> Int {
        var writtenSidecarsCount = 0
        var writtenPaths = Set<String>()

        let total = items.count
        for (index, item) in items.enumerated() {
            let sidecarURL = item.sourceURL.deletingPathExtension().appendingPathExtension("xmp")
            let canonicalPath = sidecarURL.standardizedFileURL.path

            if !writtenPaths.contains(canonicalPath) {
                try writeXMPSidecar(for: item, at: sidecarURL)
                writtenPaths.insert(canonicalPath)
                writtenSidecarsCount += 1
            }

            progress?(index + 1, total)
        }

        return writtenSidecarsCount
    }

    public func exportSelection(
        items: [PhotoItem],
        to destinationDirectory: URL,
        folderStructure: ExportFolderStructure,
        rawHandling: ExportRawHandling,
        exportXMPSidecars: Bool = true,
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

            var exportedStems = Set<String>()

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
                exportedStems.insert(finalDestFile.deletingPathExtension().lastPathComponent)

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

            if exportXMPSidecars {
                for stem in exportedStems {
                    let xmpURL = targetFolder.appendingPathComponent("\(stem).xmp")
                    try writeXMPSidecar(for: item, at: xmpURL)
                }
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
