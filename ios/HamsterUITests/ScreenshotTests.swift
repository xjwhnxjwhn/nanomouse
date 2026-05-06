//
//  ScreenshotTests.swift
//  HamsterUITests
//
//  Stable App Store screenshot scenarios launched directly through ScreenshotSupport.
//

import Foundation
import XCTest

final class ScreenshotTests: XCTestCase {
  private struct Scenario {
    let outputName: String
    let id: String
    let readyIdentifier: String
    let settleDelay: TimeInterval

    init(outputName: String, id: String, readyIdentifier: String, settleDelay: TimeInterval = 0) {
      self.outputName = outputName
      self.id = id
      self.readyIdentifier = readyIdentifier
      self.settleDelay = settleDelay
    }

    var isKeyboardScenario: Bool {
      id == "keyboardExtension"
        || id == "keyboardChinese"
        || id == "keyboardLongPressA"
        || id == "keyboardNumberPad"
    }
  }

  private static let bytePaste = Scenario(outputName: "01_byte_paste", id: "bytePaste", readyIdentifier: "screenshot_ready_bytePaste", settleDelay: 8)
  private static let bytePasteEditor = Scenario(outputName: "02_byte_paste_editor", id: "bytePasteEditor", readyIdentifier: "screenshot_ready_bytePasteEditor")
  private static let bytePasteImagePreview = Scenario(outputName: "03_byte_paste_image_preview", id: "bytePasteImagePreview", readyIdentifier: "screenshot_ready_bytePasteImagePreview", settleDelay: 3.5)
  private static let bytePastePDFPreview = Scenario(outputName: "04_byte_paste_pdf_preview", id: "bytePastePDFPreview", readyIdentifier: "screenshot_ready_bytePastePDFPreview", settleDelay: 4.5)
  private static let canvas = Scenario(outputName: "05_canvas", id: "canvas", readyIdentifier: "screenshot_ready_canvas")
  private static let markdown = Scenario(outputName: "06_markdown", id: "markdown", readyIdentifier: "screenshot_ready_markdown")
  private static let causal = Scenario(outputName: "07_causal", id: "causal", readyIdentifier: "screenshot_ready_causal")
  private static let home = Scenario(outputName: "08_home", id: "home", readyIdentifier: "screenshot_ready_home")
  private static let settings = Scenario(outputName: "09_settings", id: "settings", readyIdentifier: "screenshot_ready_settings")
  private static let keyboardExtension = Scenario(outputName: "10_keyboard_extension", id: "keyboardExtension", readyIdentifier: "screenshot_ready_keyboardExtension", settleDelay: 7)
  private static let keyboardChinese = Scenario(outputName: "11_keyboard_chinese", id: "keyboardChinese", readyIdentifier: "screenshot_ready_keyboardChinese", settleDelay: 7)
  private static let keyboardLongPressA = Scenario(outputName: "12_keyboard_long_press_a", id: "keyboardLongPressA", readyIdentifier: "screenshot_ready_keyboardLongPressA", settleDelay: 9)
  private static let keyboardNumberPad = Scenario(outputName: "13_keyboard_number_pad", id: "keyboardNumberPad", readyIdentifier: "screenshot_ready_keyboardNumberPad", settleDelay: 7)

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func test01BytePaste() throws {
    try capture(Self.bytePaste)
  }

  func test02BytePasteEditor() throws {
    try capture(Self.bytePasteEditor)
  }

  func test03BytePasteImagePreview() throws {
    try capture(Self.bytePasteImagePreview)
  }

  func test04BytePastePDFPreview() throws {
    try capture(Self.bytePastePDFPreview)
  }

  func test05Canvas() throws {
    try capture(Self.canvas)
  }

  func test06Markdown() throws {
    try capture(Self.markdown)
  }

  func test07Causal() throws {
    try capture(Self.causal)
  }

  func test08Home() throws {
    try capture(Self.home)
  }

  func test09Settings() throws {
    try capture(Self.settings)
  }

  func test10KeyboardExtension() throws {
    try capture(Self.keyboardExtension)
  }

  func test11KeyboardChinese() throws {
    try capture(Self.keyboardChinese)
  }

  func test12KeyboardLongPressA() throws {
    try capture(Self.keyboardLongPressA)
  }

  func test13KeyboardNumberPad() throws {
    try capture(Self.keyboardNumberPad)
  }

  private func capture(_ scenario: Scenario) throws {
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

    snapshot(scenario.outputName)
  }

  private func warmUpKeyboardScenario(_ scenario: Scenario, app: inout XCUIApplication) throws {
    RunLoop.current.run(until: Date().addingTimeInterval(max(6, scenario.settleDelay)))
    app.terminate()
    RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    app = launchApplication(for: scenario)
    try waitForScenarioReady(scenario, app: app)
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

    if let state = ProcessInfo.processInfo.environment["SCREENSHOT_STATE"] {
      app.launchArguments += ["-state", state]
      app.launchEnvironment["SCREENSHOT_STATE"] = state
    }

    app.launchEnvironment["SCREENSHOT_MODE"] = "1"
    app.launchEnvironment["SCREENSHOT_SCENARIO"] = scenario.id
    app.launch()
    return app
  }

  private func waitForScenarioReady(_ scenario: Scenario, app: XCUIApplication) throws {
    let readyElement = app.otherElements[scenario.readyIdentifier]
    XCTAssertTrue(
      readyElement.waitForExistence(timeout: 15),
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
      existsAccessibleElement("screenshot_link_preview_loaded_github", in: app)
    }
  }

  private func existsAccessibleElement(_ identifier: String, in app: XCUIApplication) -> Bool {
    app.descendants(matching: .any)
      .matching(identifier: identifier)
      .firstMatch
      .exists
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
}
