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
  }

  private static let home = Scenario(outputName: "01_home", id: "home", readyIdentifier: "screenshot_ready_home")
  private static let editor = Scenario(outputName: "02_editor", id: "editor", readyIdentifier: "screenshot_ready_editor")
  private static let settings = Scenario(outputName: "03_settings", id: "settings", readyIdentifier: "screenshot_ready_settings")
  private static let bytePaste = Scenario(outputName: "04_byte_paste", id: "bytePaste", readyIdentifier: "screenshot_ready_bytePaste", settleDelay: 8)
  private static let bytePasteEditor = Scenario(outputName: "05_byte_paste_editor", id: "bytePasteEditor", readyIdentifier: "screenshot_ready_bytePasteEditor")
  private static let canvas = Scenario(outputName: "06_canvas", id: "canvas", readyIdentifier: "screenshot_ready_canvas")
  private static let markdown = Scenario(outputName: "07_markdown", id: "markdown", readyIdentifier: "screenshot_ready_markdown")
  private static let causal = Scenario(outputName: "08_causal", id: "causal", readyIdentifier: "screenshot_ready_causal")
  private static let keyboardExtension = Scenario(outputName: "09_keyboard_extension", id: "keyboardExtension", readyIdentifier: "screenshot_ready_keyboardExtension", settleDelay: 4)
  private static let keyboardChinese = Scenario(outputName: "10_keyboard_chinese", id: "keyboardChinese", readyIdentifier: "screenshot_ready_keyboardChinese", settleDelay: 4)
  private static let keyboardLongPressA = Scenario(outputName: "11_keyboard_long_press_a", id: "keyboardLongPressA", readyIdentifier: "screenshot_ready_keyboardLongPressA", settleDelay: 7)
  private static let keyboardNumberPad = Scenario(outputName: "12_keyboard_number_pad", id: "keyboardNumberPad", readyIdentifier: "screenshot_ready_keyboardNumberPad", settleDelay: 4)
  private static let bytePasteImagePreview = Scenario(outputName: "13_byte_paste_image_preview", id: "bytePasteImagePreview", readyIdentifier: "screenshot_ready_bytePasteImagePreview", settleDelay: 1.5)
  private static let bytePastePDFPreview = Scenario(outputName: "14_byte_paste_pdf_preview", id: "bytePastePDFPreview", readyIdentifier: "screenshot_ready_bytePastePDFPreview", settleDelay: 1.5)

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func test01Home() throws {
    try capture(Self.home)
  }

  func test02Editor() throws {
    try capture(Self.editor)
  }

  func test03Settings() throws {
    try capture(Self.settings)
  }

  func test04BytePaste() throws {
    try capture(Self.bytePaste)
  }

  func test05BytePasteEditor() throws {
    try capture(Self.bytePasteEditor)
  }

  func test06Canvas() throws {
    try capture(Self.canvas)
  }

  func test07Markdown() throws {
    try capture(Self.markdown)
  }

  func test08Causal() throws {
    try capture(Self.causal)
  }

  func test09KeyboardExtension() throws {
    try capture(Self.keyboardExtension)
  }

  func test10KeyboardChinese() throws {
    try capture(Self.keyboardChinese)
  }

  func test11KeyboardLongPressA() throws {
    try capture(Self.keyboardLongPressA)
  }

  func test12KeyboardNumberPad() throws {
    try capture(Self.keyboardNumberPad)
  }

  func test13BytePasteImagePreview() throws {
    try capture(Self.bytePasteImagePreview)
  }

  func test14BytePastePDFPreview() throws {
    try capture(Self.bytePastePDFPreview)
  }

  private func capture(_ scenario: Scenario) throws {
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
    addTeardownBlock {
      app.terminate()
    }

    let readyElement = app.otherElements[scenario.readyIdentifier]
    XCTAssertTrue(
      readyElement.waitForExistence(timeout: 15),
      "Scenario \(scenario.id) did not expose \(scenario.readyIdentifier)"
    )

    if scenario.settleDelay > 0 {
      RunLoop.current.run(until: Date().addingTimeInterval(scenario.settleDelay))
    }

    snapshot(scenario.outputName)
  }
}
