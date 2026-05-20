//
//  WebsiteGuideScreenshotTests.swift
//  HamsterUITests
//
//  Website user guide screenshots. These tests are opt-in so normal App Store
//  screenshot runs stay short.
//

import Foundation
import XCTest

final class WebsiteGuideScreenshotTests: XCTestCase {
  private struct Scenario {
    let outputName: String
    let id: String
    let readyIdentifier: String
    let settleDelay: TimeInterval
    let category: String

    init(
      outputName: String,
      id: String,
      readyIdentifier: String,
      settleDelay: TimeInterval = 0,
      category: String)
    {
      self.outputName = outputName
      self.id = id
      self.readyIdentifier = readyIdentifier
      self.settleDelay = settleDelay
      self.category = category
    }

    var isKeyboardScenario: Bool {
      id == "keyboardExtension"
        || id == "keyboardChinese"
        || id == "keyboardLongPressA"
        || id == "keyboardNumberPad"
    }
  }

  private static let mainAppScenarios: [Scenario] = [
    Scenario(outputName: "ios-main-01-byte-paste-grid", id: "bytePaste", readyIdentifier: "screenshot_ready_bytePaste", settleDelay: 8, category: "ios-main"),
    Scenario(outputName: "ios-main-02-byte-paste-editor", id: "bytePasteEditor", readyIdentifier: "screenshot_ready_bytePasteEditor", category: "ios-main"),
    Scenario(outputName: "ios-main-03-image-file-preview", id: "bytePasteImagePreview", readyIdentifier: "screenshot_ready_bytePasteImagePreview", settleDelay: 3.5, category: "ios-main"),
    Scenario(outputName: "ios-main-04-pdf-file-preview", id: "bytePastePDFPreview", readyIdentifier: "screenshot_ready_bytePastePDFPreview", settleDelay: 4.5, category: "ios-main"),
    Scenario(outputName: "ios-main-05-canvas-drawing", id: "canvas", readyIdentifier: "screenshot_ready_canvas", category: "ios-main"),
    Scenario(outputName: "ios-main-06-markdown-editor", id: "markdown", readyIdentifier: "screenshot_ready_markdown", category: "ios-main"),
    Scenario(outputName: "ios-main-07-causal-diagram", id: "causal", readyIdentifier: "screenshot_ready_causal", category: "ios-main"),
    Scenario(outputName: "ios-main-08-home", id: "home", readyIdentifier: "screenshot_ready_home", category: "ios-main"),
    Scenario(outputName: "ios-main-09-settings", id: "settings", readyIdentifier: "screenshot_ready_settings", category: "ios-main"),
  ]

  private static let keyboardScenarios: [Scenario] = [
    Scenario(outputName: "ios-keyboard-01-byte-paste-panel", id: "keyboardExtension", readyIdentifier: "screenshot_ready_keyboardExtension", settleDelay: 7, category: "ios-keyboard"),
    Scenario(outputName: "ios-keyboard-02-chinese-keyboard", id: "keyboardChinese", readyIdentifier: "screenshot_ready_keyboardChinese", settleDelay: 7, category: "ios-keyboard"),
    Scenario(outputName: "ios-keyboard-03-key-long-press", id: "keyboardLongPressA", readyIdentifier: "screenshot_ready_keyboardLongPressA", settleDelay: 9, category: "ios-keyboard"),
    Scenario(outputName: "ios-keyboard-04-calculator-keypad", id: "keyboardNumberPad", readyIdentifier: "screenshot_ready_keyboardNumberPad", settleDelay: 7, category: "ios-keyboard"),
  ]

  override func setUpWithError() throws {
    continueAfterFailure = false
    guard Self.isEnabled else {
      throw XCTSkip("Set NANOMOUSE_WEBSITE_SCREENSHOTS=1 to generate website guide screenshots.")
    }
  }

  func testIOSMainAppGuideScreenshots() throws {
    try capture(Self.mainAppScenarios)
  }

  func testIOSKeyboardGuideScreenshots() throws {
    try capture(Self.keyboardScenarios)
  }

  private func capture(_ scenarios: [Scenario]) throws {
    for scenario in scenarios {
      var app = launchApplication(for: scenario)
      addTeardownBlock {
        app.terminate()
      }

      try waitForScenarioReady(scenario, app: app)

      if scenario.isKeyboardScenario {
        try warmUpKeyboardScenario(scenario, app: &app)
      } else {
        XCTAssertTrue(
          waitForScenarioContent(scenario, app: app, timeout: 25),
          "Scenario \(scenario.id) did not expose loaded screenshot content"
        )
      }

      if scenario.settleDelay > 0 {
        RunLoop.current.run(until: Date().addingTimeInterval(scenario.settleDelay))
      }

      if !scenario.isKeyboardScenario {
        XCTAssertTrue(
          waitForScenarioContent(scenario, app: app, timeout: 5),
          "Scenario \(scenario.id) content was not ready immediately before capture"
        )
      }

      webSnapshot(scenario.outputName, category: scenario.category)
      app.terminate()
    }
  }

  private func warmUpKeyboardScenario(_ scenario: Scenario, app: inout XCUIApplication) throws {
    RunLoop.current.run(until: Date().addingTimeInterval(max(6, scenario.settleDelay)))
    XCTAssertTrue(
      ensureNanoMouseKeyboardIsActive(in: app),
      "Scenario \(scenario.id) did not switch to the real NanoMouse keyboard extension"
    )
    app.terminate()
    RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    app = launchApplication(for: scenario)
    try waitForScenarioReady(scenario, app: app)
    focusKeyboardTextView(in: app)
    XCTAssertTrue(
      ensureNanoMouseKeyboardIsActive(in: app),
      "Scenario \(scenario.id) did not keep the real NanoMouse keyboard extension active"
    )
  }

  private func launchApplication(for scenario: Scenario) -> XCUIApplication {
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
    return app
  }

  private func waitForScenarioReady(_ scenario: Scenario, app: XCUIApplication) throws {
    let readyElement = app.otherElements[scenario.readyIdentifier]
    XCTAssertTrue(
      readyElement.waitForExistence(timeout: 45),
      "Scenario \(scenario.id) did not expose \(scenario.readyIdentifier)"
    )
  }

  private func waitForScenarioContent(_ scenario: Scenario, app: XCUIApplication, timeout: TimeInterval) -> Bool {
    switch scenario.id {
    case "bytePaste":
      return waitForGitHubPreviewLoaded(in: app, timeout: timeout)
    default:
      return true
    }
  }

  private func waitForGitHubPreviewLoaded(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
    waitUntil(timeout: timeout, pollInterval: 0.35) {
      app.descendants(matching: .any)
        .matching(identifier: "screenshot_link_preview_loaded_github")
        .firstMatch
        .exists
    }
  }

  private func ensureNanoMouseKeyboardIsActive(in app: XCUIApplication) -> Bool {
    focusKeyboardTextView(in: app)
    if waitForNanoMouseKeyboard(in: app, timeout: 10) {
      return true
    }

    for _ in 0..<6 {
      tapNextKeyboardKey(in: app)
      if waitForNanoMouseKeyboard(in: app, timeout: 2.5) {
        return true
      }
    }

    return false
  }

  private func focusKeyboardTextView(in app: XCUIApplication) {
    let textView = app.textViews["screenshot_keyboard_text_view"]
    guard textView.waitForExistence(timeout: 5) else { return }
    textView.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
  }

  private func waitForNanoMouseKeyboard(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
    waitUntil(timeout: timeout, pollInterval: 0.25) {
      nanoMouseKeyboardMarkerExists(in: app)
    }
  }

  private func nanoMouseKeyboardMarkerExists(in app: XCUIApplication) -> Bool {
    if app.descendants(matching: .any)
      .matching(identifier: "nanomouse_keyboard_traditionalize_hotspot")
      .firstMatch
      .exists
    {
      return true
    }
    if app.descendants(matching: .any)
      .matching(identifier: "nanomouse_keyboard_embedded_module")
      .firstMatch
      .exists
    {
      return true
    }

    let labels = ["繁简切换", "字节粘贴", "扩展模块"]
    for label in labels {
      if app.descendants(matching: .any)
        .matching(NSPredicate(format: "label == %@", label))
        .firstMatch
        .exists
      {
        return true
      }
    }
    return false
  }

  private func tapNextKeyboardKey(in app: XCUIApplication) {
    let keyboard = app.keyboards.firstMatch
    if keyboard.exists, keyboard.frame.width > 0, keyboard.frame.height > 0 {
      let frame = keyboard.frame
      let x = frame.minX + max(26, frame.width * 0.085)
      let y = frame.maxY - max(30, min(44, frame.height * 0.12))
      app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        .withOffset(CGVector(dx: x, dy: y))
        .tap()
    } else {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.105, dy: 0.955)).tap()
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.9))
  }

  @discardableResult
  private func waitUntil(
    timeout: TimeInterval,
    pollInterval: TimeInterval,
    condition: () -> Bool
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
    }
    return condition()
  }

  private static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["NANOMOUSE_WEBSITE_SCREENSHOTS"] == "1"
      || FileManager.default.fileExists(atPath: "/tmp/nanomouse_run_website_screenshots")
  }
}
