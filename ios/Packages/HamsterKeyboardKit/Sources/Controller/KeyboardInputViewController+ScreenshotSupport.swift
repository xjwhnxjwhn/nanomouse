//
//  KeyboardInputViewController+ScreenshotSupport.swift
//
//  Drives the real keyboard UI into deterministic states for screenshot tests.
//

import UIKit
import HamsterKit

public extension KeyboardInputViewController {
  func prepareScreenshotBaseKeyboard(
    type: KeyboardType = .chinese(.lowercased),
    forceInputModeSwitchKey: Bool = false
  ) {
    normalizeScreenshotKeyboardConfiguration()
    if forceInputModeSwitchKey {
      keyboardContext.needsInputModeSwitchKey = true
    }
    setKeyboardType(.chineseNumeric)
    if forceInputModeSwitchKey {
      keyboardContext.needsInputModeSwitchKey = true
    }
    setKeyboardType(type)
    if forceInputModeSwitchKey {
      keyboardContext.needsInputModeSwitchKey = true
    }
    view.setNeedsLayout()
    view.layoutIfNeeded()
  }

  func prepareScreenshotKeyboardState(identifier: String, forceInputModeSwitchKey: Bool = false) {
    prepareScreenshotBaseKeyboard(type: .chinese(.lowercased), forceInputModeSwitchKey: forceInputModeSwitchKey)
    resetScreenshotTransientKeyboardState()
    applyScreenshotKeyboardState(identifier: identifier)
  }

  func applySharedScreenshotStateIfNeeded() {
    #if DEBUG
    guard KeyboardScreenshotRuntime.isEnabled else { return }
    let identifier = KeyboardScreenshotRuntime.scenarioIdentifier ?? "keyboardChinese"

    func schedule(_ delays: [TimeInterval], action: @escaping (KeyboardInputViewController) -> Void) {
      for delay in delays {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
          guard let self else { return }
          guard KeyboardScreenshotRuntime.scenarioIdentifier == identifier else { return }
          action(self)
        }
      }
    }

    if identifier == "keyboardExtension" {
      schedule([0.35, 0.9, 1.5]) {
        $0.prepareScreenshotKeyboardState(identifier: "keyboardChinese", forceInputModeSwitchKey: false)
      }
      schedule([2.2, 3.0, 4.2]) {
        $0.applyScreenshotKeyboardState(identifier: identifier)
      }
    } else if identifier == "keyboardLongPressA" {
      schedule([0.35, 0.9, 1.5]) {
        $0.prepareScreenshotKeyboardState(identifier: "keyboardChinese", forceInputModeSwitchKey: false)
      }
      schedule([2.2, 3.0, 4.2]) {
        $0.showScreenshotLongPressWhenReady(for: "a")
      }
    } else {
      schedule([0.35, 0.9, 1.5, 2.2]) {
        $0.prepareScreenshotKeyboardState(identifier: identifier, forceInputModeSwitchKey: false)
      }
    }
    #endif
  }
}

private extension KeyboardInputViewController {
  func normalizeScreenshotKeyboardConfiguration() {
    var configuration = keyboardContext.hamsterConfiguration ?? HamsterConfiguration()
    configuration.keyboard = configuration.keyboard ?? KeyboardConfiguration()
    configuration.toolbar = configuration.toolbar ?? KeyboardToolbarConfiguration()
    configuration.keyboard?.disableSwipeLabel = true
    configuration.keyboard?.displayButtonBubbles = true
    configuration.toolbar?.displayKeyboardDismissButton = true
    keyboardContext.hamsterConfiguration = configuration
  }

  func applyScreenshotKeyboardState(identifier: String) {
    view.setNeedsLayout()
    view.layoutIfNeeded()

    switch identifier {
    case "keyboardExtension":
      NotificationCenter.default.post(
        name: KeyboardEmbeddedModuleNotification.toggle,
        object: nil,
        userInfo: [
          KeyboardEmbeddedModuleNotification.moduleIdentifierUserInfoKey: "clipboard",
          KeyboardEmbeddedModuleNotification.forceOpenUserInfoKey: true
        ]
      )
    case "keyboardLongPressA":
      showScreenshotLongPressWhenReady(for: "a")
    case "keyboardNumberPad":
      showScreenshotNumericKeypad()
    default:
      break
    }

    view.setNeedsLayout()
    view.layoutIfNeeded()
  }

  func resetScreenshotTransientKeyboardState() {
    for button in keyboardButtons(in: view) {
      button.isPressed = false
      button.updateButtonStyle(isPressed: false)
      button.removeInputCallout()
      button.superview?.viewWithTag(KeyboardButton.accentMenuOverlayTag)?.removeFromSuperview()
      button.superview?.viewWithTag(KeyboardButton.numericKeypadOverlayTag)?.removeFromSuperview()
    }
  }

  func showScreenshotLongPressWhenReady(for text: String, remainingRetries: Int = 18) {
    guard showScreenshotLongPress(for: text) else {
      guard remainingRetries > 0 else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
        self?.showScreenshotLongPressWhenReady(for: text, remainingRetries: remainingRetries - 1)
      }
      return
    }
  }

  @discardableResult
  func showScreenshotLongPress(for text: String) -> Bool {
    guard let button = findKeyboardButton(displaying: text) else {
      return false
    }
    guard let accents = AccentCharacterProvider.accents(for: text) else {
      return false
    }
    button.isPressed = true
    button.updateButtonStyle(isPressed: true)
    button.removeInputCallout()
    button.shouldApplyReleaseAction = false
    button.presentAccentMenu(for: accents)
    button.superview?.viewWithTag(KeyboardButton.accentMenuOverlayTag)?.layer.zPosition = 10_000
    return true
  }

  func showScreenshotNumericKeypad() {
    guard let button = findKeyboardButton(where: { $0.buttonText == "123" }) else { return }
    button.presentNumericKeypad()
  }

  func findKeyboardButton(displaying text: String) -> KeyboardButton? {
    findKeyboardButton { $0.buttonText.caseInsensitiveCompare(text) == .orderedSame }
  }

  func findKeyboardButton(where predicate: (KeyboardButton) -> Bool) -> KeyboardButton? {
    keyboardButtons(in: view).first { button in
      predicate(button) && button.isVisibleForScreenshot
    }
  }

  func keyboardButtons(in root: UIView) -> [KeyboardButton] {
    var result: [KeyboardButton] = []
    if let button = root as? KeyboardButton {
      result.append(button)
    }
    for subview in root.subviews {
      result.append(contentsOf: keyboardButtons(in: subview))
    }
    return result
  }
}

private enum KeyboardScreenshotRuntime {
  private static let modeKey = "NanoMouseScreenshotKeyboardMode"
  private static let scenarioKey = "NanoMouseScreenshotKeyboardScenario"

  static var isEnabled: Bool {
    #if DEBUG
    if CommandLine.arguments.contains("-screenshotMode") {
      return true
    }
    if ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1" {
      return true
    }
    return UserDefaults(suiteName: HamsterConstants.appGroupName)?.bool(forKey: modeKey) == true
    #else
    return false
    #endif
  }

  static var scenarioIdentifier: String? {
    #if DEBUG
    if let sharedValue = UserDefaults(suiteName: HamsterConstants.appGroupName)?.string(forKey: scenarioKey),
       !sharedValue.isEmpty {
      return sharedValue
    }
    if let environmentValue = ProcessInfo.processInfo.environment["SCREENSHOT_SCENARIO"],
       !environmentValue.isEmpty {
      return environmentValue
    }
    return nil
    #else
    return nil
    #endif
  }
}

private extension KeyboardButton {
  var isVisibleForScreenshot: Bool {
    guard window != nil else { return false }
    guard !isHidden, alpha > 0.01 else { return false }
    guard bounds.width > 1, bounds.height > 1 else { return false }
    return true
  }
}
