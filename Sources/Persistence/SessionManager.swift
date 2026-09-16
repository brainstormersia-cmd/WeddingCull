import Foundation

public final class SessionManager: Sendable {
    public init() {}

    public func saveSession(_ session: SessionData, to fileURL: URL) throws {
        var mutableSession = session
        mutableSession.modifiedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(mutableSession)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadSession(from fileURL: URL) throws -> SessionData {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var session = try decoder.decode(SessionData.self, from: data)

        // Schema migration check
        if session.schemaVersion < SessionData.currentSchemaVersion {
            session = migrate(session: session, from: session.schemaVersion, to: SessionData.currentSchemaVersion)
        }

        return session
    }

    public func validateCacheIntegrity(for items: [PhotoItem]) -> (valid: [PhotoItem], needsReanalysis: [PhotoItem]) {
        let fileManager = FileManager.default
        var valid: [PhotoItem] = []
        var needsReanalysis: [PhotoItem] = []

        for item in items {
            guard let attributes = try? fileManager.attributesOfItem(atPath: item.sourceURL.path) else {
                needsReanalysis.append(item)
                continue
            }

            let currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let currentModDate = (attributes[.modificationDate] as? Date) ?? Date()

            // Invalidate if size changed or modified more than 1 second apart
            let sizeMatches = currentSize == item.fileSizeBytes
            let dateMatches = abs(currentModDate.timeIntervalSince(item.fileModificationDate)) < 1.0

            if sizeMatches && dateMatches {
                valid.append(item)
            } else {
                needsReanalysis.append(item)
            }
        }

        return (valid, needsReanalysis)
    }

    private func migrate(session: SessionData, from oldVersion: Int, to newVersion: Int) -> SessionData {
        var migrated = session
        migrated.schemaVersion = newVersion
        // Hook for future schema migrations
        return migrated
    }
}
