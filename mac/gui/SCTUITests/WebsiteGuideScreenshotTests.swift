//
//  WebsiteGuideScreenshotTests.swift
//  SCTUITests
//
//  Website user guide screenshots for the macOS app.
//

import XCTest

final class WebsiteGuideScreenshotTests: XCTestCase {
    private struct Scenario {
        let outputName: String
        let id: String
        let readyIdentifier: String
    }

    private let scenarios: [Scenario] = [
        Scenario(outputName: "mac-main-01-byte-paste-grid", id: "bytePaste", readyIdentifier: "screenshot_ready_bytePaste"),
        Scenario(outputName: "mac-main-02-byte-paste-editor", id: "bytePasteEditor", readyIdentifier: "screenshot_ready_bytePasteEditor"),
        Scenario(outputName: "mac-main-03-canvas-drawing", id: "canvas", readyIdentifier: "screenshot_ready_canvas"),
        Scenario(outputName: "mac-main-04-markdown-editor", id: "markdown", readyIdentifier: "screenshot_ready_markdown"),
        Scenario(outputName: "mac-main-05-causal-diagram", id: "causal", readyIdentifier: "screenshot_ready_causal"),
        Scenario(outputName: "mac-main-06-image-file-preview", id: "bytePasteImagePreview", readyIdentifier: "screenshot_ready_bytePasteImagePreview"),
        Scenario(outputName: "mac-main-07-pdf-file-preview", id: "bytePastePDFPreview", readyIdentifier: "screenshot_ready_bytePastePDFPreview"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard Self.isEnabled else {
            throw XCTSkip("Set NANOMOUSE_WEBSITE_SCREENSHOTS=1 to generate website guide screenshots.")
        }
        try openSnapshotDesktopBackgroundFullScreen()
        addTeardownBlock {
            closeSnapshotDesktopBackground()
        }
    }

    func testMacMainAppGuideScreenshots() throws {
        for scenario in scenarios {
            try openSnapshotDesktopBackgroundFullScreen()

            let app = XCUIApplication()
            setupSnapshot(app)

            app.launchArguments += [
                "-screenshotMode",
                "-scenario", scenario.id,
            ]

            if let locale = ProcessInfo.processInfo.environment["SCREENSHOT_LOCALE"] {
                app.launchArguments += [
                    "-locale", locale,
                    "-AppleLanguages", "(\(locale))",
                    "-AppleLocale", locale,
                ]
                app.launchEnvironment["SCREENSHOT_LOCALE"] = locale
            }

            if let theme = ProcessInfo.processInfo.environment["SCREENSHOT_THEME"] {
                app.launchArguments += ["-theme", theme]
                app.launchEnvironment["SCREENSHOT_THEME"] = theme
            }

            app.launchEnvironment["SCREENSHOT_MODE"] = "1"
            app.launchEnvironment["SCREENSHOT_SCENARIO"] = scenario.id
            app.launch()

            let readyElement = app.descendants(matching: .any)
                .matching(identifier: scenario.readyIdentifier)
                .firstMatch
            XCTAssertTrue(
                readyElement.waitForExistence(timeout: 45),
                "Scenario \(scenario.id) did not expose \(scenario.readyIdentifier)"
            )

            webSnapshot(scenario.outputName, category: "desktop-main")
            app.terminate()
        }
    }

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["NANOMOUSE_WEBSITE_SCREENSHOTS"] == "1"
            || FileManager.default.fileExists(atPath: "/tmp/nanomouse_run_website_screenshots")
    }
}
