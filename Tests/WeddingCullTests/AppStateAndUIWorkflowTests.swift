import XCTest
#if canImport(WeddingCull)
@testable import WeddingCull
#elseif canImport(WeddingCullCore)
@testable import WeddingCullCore
#endif

@MainActor
final class AppStateAndUIWorkflowTests: XCTestCase {
    func testInitialAppState() {
        let appState = AppState()
        XCTAssertEqual(appState.navigationState, .start)
        XCTAssertFalse(appState.isAnalyzing)
        XCTAssertFalse(appState.isPaused)
        XCTAssertNil(appState.selectedPhotoID)
        XCTAssertEqual(appState.currentFilter, .smartAlbum("all"))
    }

    func testPhotoMarkingAndFiltering() {
        let appState = AppState()

        var photo1 = PhotoItem(id: "photo_1", fileName: "IMG_0001.jpg", sourceURL: URL(fileURLWithPath: "/tmp/1.jpg"), category: .ceremony)
        photo1.selectionState = .selected

        var photo2 = PhotoItem(id: "photo_2", fileName: "IMG_0002.jpg", sourceURL: URL(fileURLWithPath: "/tmp/2.jpg"), category: .reception)
        photo2.selectionState = .rejected

        var photo3 = PhotoItem(id: "photo_3", fileName: "IMG_0003.jpg", sourceURL: URL(fileURLWithPath: "/tmp/3.jpg"), category: .couple)
        photo3.selectionState = .alternative

        appState.session = SessionData(
            sourceFolderPath: "/tmp",
            targetSelectionCount: 2,
            photos: [photo1, photo2, photo3]
        )
        appState.navigationState = .review

        // Test selected photo resolution
        appState.selectedPhotoID = "photo_1"
        XCTAssertEqual(appState.selectedPhoto?.id, "photo_1")

        // Test marking photo
        appState.markPhoto(id: "photo_1", state: .userRejected)
        XCTAssertEqual(appState.session.photos.first(where: { .id == "photo_1" })?.selectionState, .userRejected)

        appState.markPhoto(id: "photo_2", state: .userSelected)
        XCTAssertEqual(appState.session.photos.first(where: { .id == "photo_2" })?.selectionState, .userSelected)

        // Test smart album filtering
        appState.currentFilter = .smartAlbum("all")
        XCTAssertEqual(appState.filteredPhotos.count, 3)

        appState.currentFilter = .smartAlbum("selected")
        XCTAssertEqual(appState.filteredPhotos.count, 1)
        XCTAssertEqual(appState.filteredPhotos.first?.id, "photo_2")

        appState.currentFilter = .smartAlbum("alternative")
        XCTAssertEqual(appState.filteredPhotos.count, 1)
        XCTAssertEqual(appState.filteredPhotos.first?.id, "photo_3")

        appState.currentFilter = .category(.couple)
        XCTAssertEqual(appState.filteredPhotos.count, 1)
        XCTAssertEqual(appState.filteredPhotos.first?.id, "photo_3")
    }

    func testPauseResumeAndCancelWorkflow() {
        let appState = AppState()

        // Test pause/resume when not analyzing is a no-op
        appState.pauseAnalysis()
        XCTAssertFalse(appState.isPaused)

        // Set analyzing state
        appState.isAnalyzing = true
        appState.navigationState = .analyzing

        appState.pauseAnalysis()
        XCTAssertTrue(appState.isPaused)
        XCTAssertEqual(appState.statusMessage, "Analisi in pausa.")

        appState.resumeAnalysis()
        XCTAssertFalse(appState.isPaused)
        XCTAssertEqual(appState.statusMessage, "Analisi ripresa.")

        // Cancel analysis resets state to start
        appState.cancelAnalysis()
        XCTAssertFalse(appState.isAnalyzing)
        XCTAssertFalse(appState.isPaused)
        XCTAssertEqual(appState.navigationState, .start)
    }
}
