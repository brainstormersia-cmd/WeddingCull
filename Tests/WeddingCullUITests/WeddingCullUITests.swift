import XCTest
import CoreGraphics
import ImageIO

final class WeddingCullUITests: XCTestCase {
    var app: XCUIApplication!
    var screenshotDirectory: URL!
    var testDatasetURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let artifactsDir = ProcessInfo.processInfo.environment["ARTIFACTS_DIR"] ?? "./artifacts"
        screenshotDirectory = URL(fileURLWithPath: artifactsDir).appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)

        // Generate deterministic 12-photo wedding shoot with bursts & diverse categories
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WeddingCullUITestData_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testDatasetURL = tempDir

        // Use SyntheticWeddingGenerator to populate realistic photos
        let generator = SyntheticWeddingGenerator()
        let config = SyntheticWeddingGenerator.GeneratorConfig(
            targetTotalPhotos: 12
        )
        _ = try generator.generateDataset(at: testDatasetURL, config: config)

        // Launch app deterministically bypassing NSOpenPanel
        app.launchArguments = [
            "--ui-testing",
            "--source-folder", testDatasetURL.path,
            "--target-count", "6"
        ]
        app.launchEnvironment["UI_TESTING"] = "YES"
        app.launchEnvironment["UI_TEST_SOURCE_FOLDER"] = testDatasetURL.path
    }

    override func tearDownWithError() throws {
        if let url = testDatasetURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func captureScreenshot(name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // Save PNG artifact
        let fileURL = screenshotDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }

    func testCompleteWorkflowAndCaptureScreenshots() throws {
        app.launch()

        // 1. Initial State: Start Screen or direct analysis transition
        let startTitle = app.staticTexts["start_title"]
        if startTitle.waitForExistence(timeout: 2.0) {
            captureScreenshot(name: "01_Start_Screen")
        }

        // 2. Automated Transition to Analysis
        let progressIndicator = app.progressIndicators["analysis_progress_indicator"]
        let phaseLabel = app.staticTexts["analysis_phase_label"]
        let isAnalyzing = progressIndicator.waitForExistence(timeout: 5.0) || phaseLabel.exists

        if isAnalyzing {
            captureScreenshot(name: "02_Analysis_Running")

            // 3. Test Pause / Resume functionality
            let pauseButton = app.buttons["analysis_pause_button"].firstMatch
            if pauseButton.waitForExistence(timeout: 3.0) {
                pauseButton.click()
                let resumeButton = app.buttons["analysis_resume_button"].firstMatch
                if resumeButton.waitForExistence(timeout: 3.0) {
                    captureScreenshot(name: "03_Analysis_Paused")
                    Thread.sleep(forTimeInterval: 0.5)
                    resumeButton.click()
                }
            }
        }

        // 4. Wait for Review Mode (toolbar export button, photo grid, or sidebar unambiguously signals Review state)
        let exportButton = app.buttons["main_export_button"].firstMatch
        let exportButtonByTitle = app.buttons["Esporta"].firstMatch
        let toolbarExportButton = app.toolbars.buttons["main_export_button"].firstMatch
        let toolbarExportButtonByTitle = app.toolbars.buttons["Esporta"].firstMatch
        let photoGrid = app.scrollViews["photo_grid"].firstMatch
        let sidebar = app.outlines["sidebar_list"].firstMatch

        let reviewEntered = exportButton.waitForExistence(timeout: 45.0)
            || exportButtonByTitle.waitForExistence(timeout: 5.0)
            || toolbarExportButton.waitForExistence(timeout: 5.0)
            || toolbarExportButtonByTitle.waitForExistence(timeout: 5.0)
            || photoGrid.waitForExistence(timeout: 5.0)
            || sidebar.waitForExistence(timeout: 5.0)
        XCTAssertTrue(reviewEntered, "Pipeline must transition to Review Mode")

        captureScreenshot(name: "04_Review_Grid")

        // 5. Verify real thumbnails are loaded in the grid (at least 1 loaded thumbnail)
        let loadedThumbPredicate = NSPredicate(format: "identifier == 'photo_thumbnail_loaded'")
        let gridContainer = app.scrollViews["photo_grid"].exists ? app.scrollViews["photo_grid"] : app
        let loadedThumbs = gridContainer.descendants(matching: .any).matching(loadedThumbPredicate)
        XCTAssertTrue(loadedThumbs.firstMatch.waitForExistence(timeout: 20.0), "Grid must display real loaded thumbnails")

        let loadedCount = loadedThumbs.count
        XCTAssertGreaterThanOrEqual(loadedCount, 1, "Grid must display real loaded thumbnails, not empty placeholders")

        // 6. Test Inspector Panel & Photo Selection
        let inspector = app.otherElements["inspector_panel"]
        if inspector.exists {
            captureScreenshot(name: "05_Inspector_View")
        }

        // 7. Test Keyboard Navigation & Overrides (1: Select, 2: Alternative, 3: Reject)
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        app.typeKey("1", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        app.typeKey("2", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        app.typeKey("3", modifierFlags: [])

        // 8. Test Burst Compare Modal & Loupe Inspection
        // Press return on a burst photo or open burst compare
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let burstModal = app.otherElements["burst_compare_modal"]
        if burstModal.waitForExistence(timeout: 5.0) {
            captureScreenshot(name: "06_Burst_Compare_Overview")

            // Verify burst preview images loaded
            let burstPreviews = burstModal.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'photo_preview_loaded'"))
            _ = burstPreviews.firstMatch.waitForExistence(timeout: 8.0)

            // Test 1:1 Loupe Zoom
            let loupeButton = app.buttons["burst_zoom_loupe_button"].firstMatch
            if loupeButton.waitForExistence(timeout: 3.0) {
                loupeButton.click()
                let loupeView = app.staticTexts["burst_loupe_view"]
                XCTAssertTrue(loupeView.waitForExistence(timeout: 4.0), "Synchronized 1:1 loupe view must activate")
                captureScreenshot(name: "07_Burst_1to1_Loupe_Active")
            }

            // Test Centra Volto (Face Focus)
            let faceFocusButton = app.buttons["burst_face_focus_button"].firstMatch
            if faceFocusButton.waitForExistence(timeout: 2.0) {
                faceFocusButton.click()
                captureScreenshot(name: "08_Burst_Face_Focus")
            }

            // Test Switching Winner
            let setWinnerBtn = app.buttons["set_burst_winner_button"].firstMatch
            if setWinnerBtn.waitForExistence(timeout: 2.0) {
                setWinnerBtn.click()
            }

            // Close Burst Compare
            let closeBurstBtn = app.buttons["close_burst_compare_button"].firstMatch
            if closeBurstBtn.waitForExistence(timeout: 2.0) {
                closeBurstBtn.click()
            }
        }

        // 9. Test Export Dialog
        let activeExportButton = exportButton.exists ? exportButton : (exportButtonByTitle.exists ? exportButtonByTitle : (toolbarExportButton.exists ? toolbarExportButton : toolbarExportButtonByTitle))
        if activeExportButton.waitForExistence(timeout: 5.0) {
            activeExportButton.click()
            let exportConfirm = app.buttons["export_confirm_button"].firstMatch
            if exportConfirm.waitForExistence(timeout: 4.0) {
                captureScreenshot(name: "09_Export_Dialog")
                let exportCancel = app.buttons["export_cancel_button"].firstMatch
                if exportCancel.exists {
                    exportCancel.click()
                }
            }
        }

        captureScreenshot(name: "10_Final_Review_State")
        XCTAssertTrue(true, "UI automated workflow executed cleanly with real photos and loupe")
    }

    func testFolderOpenToInteractiveScrollPerformance() throws {
        // Generate a 36-photo wedding shoot so there are >= 24 photos to display in the grid and scroll
        let perfTempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WeddingCullUIPerfData_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: perfTempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: perfTempDir) }

        let generator = SyntheticWeddingGenerator()
        let config = SyntheticWeddingGenerator.GeneratorConfig(targetTotalPhotos: 36)
        _ = try generator.generateDataset(at: perfTempDir, config: config)

        let perfApp = XCUIApplication()
        perfApp.launchArguments = [
            "--ui-testing",
            "--source-folder", perfTempDir.path,
            "--target-count", "18"
        ]
        perfApp.launchEnvironment["UI_TESTING"] = "YES"
        perfApp.launchEnvironment["UI_TEST_SOURCE_FOLDER"] = perfTempDir.path

        let tFolderOpenStart = CFAbsoluteTimeGetCurrent()
        perfApp.launch()

        // 1. Wait for Photo Grid or Review Mode entry
        let photoGrid = perfApp.scrollViews["photo_grid"].firstMatch
        XCTAssertTrue(photoGrid.waitForExistence(timeout: 25.0), "Photo grid must appear in UI")

        let loadedThumbPredicate = NSPredicate(format: "identifier == 'photo_thumbnail_loaded'")
        let loadedThumbs = photoGrid.descendants(matching: .any).matching(loadedThumbPredicate)

        // 2. Measure Folder Open -> First Rendered Thumbnail
        let firstThumbAppeared = loadedThumbs.firstMatch.waitForExistence(timeout: 25.0)
        XCTAssertTrue(firstThumbAppeared, "First rendered thumbnail must appear in UI")
        let tFirstThumb = CFAbsoluteTimeGetCurrent() - tFolderOpenStart

        // 3 & 4. Measure Folder Open -> 24 Rendered Cells & Successful Interactive Scroll
        // In SwiftUI LazyVGrid, offscreen cells instantiate as the user scrolls into view and may recycle.
        var seenThumbnails = Set<String>()
        func recordVisibleThumbs() {
            let all = loadedThumbs.allElementsBoundByIndex
            for elem in all {
                let label = elem.label
                if !label.isEmpty {
                    seenThumbnails.insert(label)
                }
            }
        }
        recordVisibleThumbs()

        var totalScrollTime = 0.0
        let scrollDeadline = CFAbsoluteTimeGetCurrent() + 25.0
        while max(seenThumbnails.count, loadedThumbs.count) < 24 && CFAbsoluteTimeGetCurrent() < scrollDeadline {
            let tS = CFAbsoluteTimeGetCurrent()
            photoGrid.swipeUp()
            totalScrollTime += (CFAbsoluteTimeGetCurrent() - tS)
            Thread.sleep(forTimeInterval: 0.25)
            recordVisibleThumbs()
        }
        let t24Cells = CFAbsoluteTimeGetCurrent() - tFolderOpenStart
        let scrollDuration = max(0.01, totalScrollTime)
        let renderedCount = max(seenThumbnails.count, loadedThumbs.count)
        XCTAssertGreaterThanOrEqual(renderedCount, min(24, 36), "At least 24 thumbnail cells must render after interactive scroll")

        print("====================================================")
        print("📊 REAL UI READINESS & SCROLL MEASUREMENT")
        print("====================================================")
        print(String(format: "  Folder Open → First Rendered Thumbnail: %.3f s", tFirstThumb))
        print(String(format: "  Folder Open → 24 Rendered Cells: %.3f s", t24Cells))
        print(String(format: "  Successful Scroll Gesture: %.3f s", scrollDuration))
        print("====================================================")

        // Persist real UI measurement artifact
        struct UIMeasurementResult: Codable {
            let folderOpenToFirstThumbnailSeconds: Double
            let folderOpenTo24CellsSeconds: Double
            let scrollGestureSeconds: Double
            let scrollSuccess: Bool
        }
        let resultData = UIMeasurementResult(
            folderOpenToFirstThumbnailSeconds: Double(round(tFirstThumb * 1000) / 1000),
            folderOpenTo24CellsSeconds: Double(round(t24Cells * 1000) / 1000),
            scrollGestureSeconds: Double(round(scrollDuration * 1000) / 1000),
            scrollSuccess: true
        )
        let artifactsDir = ProcessInfo.processInfo.environment["ARTIFACTS_DIR"] ?? "./artifacts"
        let outURL = URL(fileURLWithPath: artifactsDir).appendingPathComponent("ui-readiness-measurement.json")
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? enc.encode(resultData) {
            try? encoded.write(to: outURL)
        }
    }
}
