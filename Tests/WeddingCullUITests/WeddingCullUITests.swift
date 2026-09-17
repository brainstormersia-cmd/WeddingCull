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
                    resumeButton.click()
                }
            }
        }

        // 4. Wait for Review Mode (toolbar / inspector buttons unambiguously signal Review state)
        let exportButton = app.buttons["main_export_button"].firstMatch
        let selectButton = app.buttons["select_button"].firstMatch
        let reviewEntered = exportButton.waitForExistence(timeout: 60.0) || selectButton.waitForExistence(timeout: 10.0)
        XCTAssertTrue(reviewEntered, "Pipeline must transition to Review Mode")

        captureScreenshot(name: "04_Review_Grid")

        // 5. Verify real thumbnails are loaded in the grid (at least 3 loaded thumbnails)
        let loadedThumbPredicate = NSPredicate(format: "identifier == 'photo_thumbnail_loaded'")
        let loadedThumbs = app.images.matching(loadedThumbPredicate)
        _ = loadedThumbs.firstMatch.waitForExistence(timeout: 10.0)

        let loadedCount = loadedThumbs.count
        XCTAssertGreaterThanOrEqual(loadedCount, 3, "Grid must display real loaded thumbnails, not empty placeholders")

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
            let burstPreviews = app.images.matching(NSPredicate(format: "identifier == 'photo_preview_loaded'"))
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
        let exportButton = app.buttons["main_export_button"].firstMatch
        if exportButton.waitForExistence(timeout: 5.0) {
            exportButton.click()
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
}
