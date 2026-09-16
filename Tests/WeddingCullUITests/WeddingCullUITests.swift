import XCTest

final class WeddingCullUITests: XCTestCase {
    var app: XCUIApplication!
    var screenshotDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let artifactsDir = ProcessInfo.processInfo.environment["ARTIFACTS_DIR"] ?? "./artifacts"
        screenshotDirectory = URL(fileURLWithPath: artifactsDir).appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
    }

    private func captureScreenshot(name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // Save to artifacts directory
        let fileURL = screenshotDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }

    func testCompleteWorkflowAndCaptureScreenshots() throws {
        app.launch()

        // 1. Start Screen
        XCTAssertTrue(app.staticTexts["start_title"].waitForExistence(timeout: 5.0))
        captureScreenshot(name: "01_Start_Screen")

        // Check import & open session buttons exist
        XCTAssertTrue(app.buttons["start_import_button"].exists)
        XCTAssertTrue(app.buttons["start_open_session_button"].exists)
    }
}
