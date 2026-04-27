//
//  ScreenshotTests.swift
//  HamsterUITests
//
//  Stable App Store screenshot scenarios launched directly through ScreenshotSupport.
//

import XCTest

final class ScreenshotTests: XCTestCase {
  private struct Scenario {
    let outputName: String
    let id: String
    let readyIdentifier: String
  }

  private let scenarios: [Scenario] = [
    Scenario(outputName: "01_home", id: "home", readyIdentifier: "screenshot_ready_home"),
    Scenario(outputName: "02_editor", id: "editor", readyIdentifier: "screenshot_ready_editor"),
    Scenario(outputName: "03_settings", id: "settings", readyIdentifier: "screenshot_ready_settings"),
    Scenario(outputName: "04_byte_paste", id: "bytePaste", readyIdentifier: "screenshot_ready_bytePaste"),
    Scenario(outputName: "05_byte_paste_editor", id: "bytePasteEditor", readyIdentifier: "screenshot_ready_bytePasteEditor"),
    Scenario(outputName: "06_canvas", id: "canvas", readyIdentifier: "screenshot_ready_canvas"),
    Scenario(outputName: "07_markdown", id: "markdown", readyIdentifier: "screenshot_ready_markdown"),
    Scenario(outputName: "08_causal", id: "causal", readyIdentifier: "screenshot_ready_causal"),
  ]

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testAppStoreScreenshots() throws {
    for scenario in scenarios {
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

      if let state = ProcessInfo.processInfo.environment["SCREENSHOT_STATE"] {
        app.launchArguments += ["-state", state]
        app.launchEnvironment["SCREENSHOT_STATE"] = state
      }

      app.launchEnvironment["SCREENSHOT_MODE"] = "1"
      app.launchEnvironment["SCREENSHOT_SCENARIO"] = scenario.id
      app.launch()

      let readyElement = app.otherElements[scenario.readyIdentifier]
      XCTAssertTrue(
        readyElement.waitForExistence(timeout: 15),
        "Scenario \(scenario.id) did not expose \(scenario.readyIdentifier)"
      )

      snapshot(scenario.outputName)
      app.terminate()
    }
  }
}
