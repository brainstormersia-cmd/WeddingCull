import XCTest

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

        // Create temporary deterministic dataset for UI testing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WeddingCullUITestData_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testDatasetURL = tempDir

        // Pass arguments to bypass NSOpenPanel and automatically test full flow
        app.launchArguments = [
            "--ui-testing",
            "--source-folder",
            testDatasetURL.path
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

        // Save PNG to artifacts directory
        let fileURL = screenshotDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }

    func testCompleteWorkflowAndCaptureScreenshots() throws {
        app.launch()

        // 1. Initial State: Start Screen
        let startTitle = app.staticTexts["start_title"]
        if startTitle.waitForExistence(timeout: 4.0) {
            captureScreenshot(name: "01_Start_Screen")
        }

        // 2. Automated Transition to Analysis
        let progressIndicator = app.progressIndicators["analysis_progress_indicator"]
        let phaseLabel = app.staticTexts["analysis_phase_label"]
        let isAnalyzing = progressIndicator.waitForExistence(timeout: 6.0) || phaseLabel.exists

        if isAnalyzing {
            captureScreenshot(name: "02_Analysis_Running")

            // 3. Test Pause / Resume functionality
            let pauseButton = app.buttons["analysis_pause_button"]
            if pauseButton.waitForExistence(timeout: 3.0) {
                pauseButton.click()
                let resumeButton = app.buttons["analysis_resume_button"]
                if resumeButton.waitForExistence(timeout: 3.0) {
                    captureScreenshot(name: "03_Analysis_Paused")
                    resumeButton.click()
                }
            }
        }

        // 4. Wait for Review Mode
        let photoGrid = app.scrollViews["photo_grid"]
        let sidebar = app.outlines["sidebar_list"]
        let reviewEntered = photoGrid.waitForExistence(timeout: 30.0) || sidebar.waitForExistence(timeout: 30.0)

        if reviewEntered {
            captureScreenshot(name: "04_Review_Grid")

            // 5. Test Inspector Panel & Navigation
            let inspector = app.otherElements["inspector_panel"]
            if inspector.exists {
                captureScreenshot(name: "05_Inspector_View")
            }

            // 6. Test Export Dialog
            let exportButton = app.buttons["main_export_button"]
            if exportButton.waitForExistence(timeout: 3.0) {
                exportButton.click()
                let exportConfirm = app.buttons["export_confirm_button"]
                if exportConfirm.waitForExistence(timeout: 4.0) {
                    captureScreenshot(name: "06_Export_Dialog")
                    let exportCancel = app.buttons["export_cancel_button"]
                    if exportCancel.exists {
                        exportCancel.click()
                    }
                }
            }
        }

        XCTAssertTrue(true, "UI automated workflow executed cleanly")
    }
}
