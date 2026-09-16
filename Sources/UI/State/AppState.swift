import Foundation
import SwiftUI

public enum AppNavigationState: Equatable {
    case start
    case analyzing
    case review
}

public enum SidebarFilter: Hashable {
    case smartAlbum(String) // "all", "selected", "alternative", "rejected", "duplicates", "lowQuality"
    case category(WeddingCategory)
    case segment(String)
    case person(String)
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var navigationState: AppNavigationState = .start
    @Published public var session: SessionData = SessionData()
    @Published public var selectedPhotoID: String? = nil
    @Published public var currentFilter: SidebarFilter = .smartAlbum("all")
    @Published public var analysisProgress: AnalysisProgress? = nil
    @Published public var isAnalyzing: Bool = false
    @Published public var activeBurstForComparison: BurstGroup? = nil
    @Published public var isExportSheetPresented: Bool = false
    @Published public var statusMessage: String = ""

    private var analysisTask: Task<Void, Never>? = nil
    private let pipeline = AnalysisPipeline()
    private let selector = DiversitySelector()
    private let sessionManager = SessionManager()

    public init() {}

    public var selectedPhoto: PhotoItem? {
        guard let id = selectedPhotoID else { return session.photos.first }
        return session.photos.first(where: { $0.id == id })
    }

    public var filteredPhotos: [PhotoItem] {
        switch currentFilter {
        case .smartAlbum(let album):
            switch album {
            case "all":
                return session.photos
            case "selected":
                return session.photos.filter { $0.selectionState.isIncludedInFinal }
            case "alternative":
                return session.photos.filter { $0.selectionState == .alternative }
            case "rejected":
                return session.photos.filter { $0.selectionState == .rejected || $0.selectionState == .userRejected }
            case "duplicates":
                return session.photos.filter { $0.isDuplicate }
            case "lowQuality":
                return session.photos.filter { $0.metrics.isTechnicallyLowQuality }
            default:
                return session.photos
            }
        case .category(let cat):
            return session.photos.filter { $0.category == cat }
        case .segment(let segID):
            return session.photos.filter { $0.temporalSegmentID == segID }
        case .person(let personID):
            return session.photos.filter { $0.personClusterIDs.contains(personID) }
        }
    }

    public func startAnalysis(folderURL: URL, targetCount: Int = 700) {
        navigationState = .analyzing
        isAnalyzing = true
        statusMessage = "Starting analysis..."

        analysisTask = Task {
            do {
                let result = try await pipeline.runAnalysis(sourceFolder: folderURL, targetCount: targetCount) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.analysisProgress = progress
                        self?.statusMessage = "\(progress.phase.rawValue): \(progress.message)"
                    }
                }

                self.session = result
                self.selectedPhotoID = result.photos.first?.id
                self.isAnalyzing = false
                self.navigationState = .review
                self.statusMessage = "Analysis complete: \(result.photos.count) photos processed."
            } catch {
                self.isAnalyzing = false
                self.statusMessage = "Analysis failed: \(error.localizedDescription)"
                self.navigationState = .start
            }
        }
    }

    public func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        navigationState = .start
        statusMessage = "Analysis cancelled."
    }

    public func markPhoto(id: String, state: SelectionState) {
        if let idx = session.photos.firstIndex(where: { $0.id == id }) {
            session.photos[idx].selectionState = state
        }
    }

    public func selectNextPhoto() {
        let currentList = filteredPhotos
        guard let currentID = selectedPhotoID,
              let idx = currentList.firstIndex(where: { $0.id == currentID }),
              idx + 1 < currentList.count else { return }
        selectedPhotoID = currentList[idx + 1].id
    }

    public func selectPreviousPhoto() {
        let currentList = filteredPhotos
        guard let currentID = selectedPhotoID,
              let idx = currentList.firstIndex(where: { $0.id == currentID }),
              idx > 0 else { return }
        selectedPhotoID = currentList[idx - 1].id
    }

    public func updateTargetCount(_ newTarget: Int) {
        session.targetSelectionCount = newTarget
        recalculateSelection()
    }

    public func recalculateSelection() {
        let result = selector.selectPhotos(
            items: session.photos,
            segments: session.segments,
            bursts: session.burstGroups,
            targetCount: session.targetSelectionCount
        )
        session.photos = result.updatedItems
        statusMessage = result.message
    }

    public func setBurstWinner(burstID: String, newWinnerID: String) {
        guard let bIdx = session.burstGroups.firstIndex(where: { $0.id == burstID }) else { return }
        session.burstGroups[bIdx].winnerID = newWinnerID
        session.burstGroups[bIdx].alternativeIDs = session.burstGroups[bIdx].memberIDs.filter { $0 != newWinnerID }

        for (index, item) in session.photos.enumerated() {
            if item.burstGroupID == burstID {
                let isWinner = (item.id == newWinnerID)
                session.photos[index].isBurstWinner = isWinner
                if isWinner {
                    session.photos[index].selectionState = .userSelected
                } else if session.photos[index].selectionState == .selected {
                    session.photos[index].selectionState = .alternative
                }
            }
        }
        recalculateSelection()
    }

    public func saveSession(to fileURL: URL) throws {
        try sessionManager.saveSession(session, to: fileURL)
        statusMessage = "Session saved successfully."
    }

    public func loadSession(from fileURL: URL) throws {
        session = try sessionManager.loadSession(from: fileURL)
        selectedPhotoID = session.photos.first?.id
        navigationState = .review
        statusMessage = "Session loaded: \(session.photos.count) photos."
    }
}
