//
//  ScreenshotMode.swift
//
//
//  Reads UI-test screenshot launch arguments without affecting normal launches.
//

import Foundation
import UIKit

public enum ScreenshotTheme: String, Sendable {
  case light
  case dark

  var userInterfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .light:
      return .light
    case .dark:
      return .dark
    }
  }
}

public struct ScreenshotMode: Sendable {
  public static var isEnabled: Bool {
    #if DEBUG
    CommandLine.arguments.contains("-screenshotMode")
      || ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
    #else
    false
    #endif
  }

  public static var scenario: ScreenshotScenario? {
    #if DEBUG
    stringValue(argument: "-scenario", environmentKey: "SCREENSHOT_SCENARIO")
      .flatMap(ScreenshotScenario.init(rawValue:))
    #else
    nil
    #endif
  }

  public static var localeIdentifier: String? {
    #if DEBUG
    stringValue(argument: "-locale", environmentKey: "SCREENSHOT_LOCALE")
    #else
    nil
    #endif
  }

  public static var theme: ScreenshotTheme? {
    #if DEBUG
    stringValue(argument: "-theme", environmentKey: "SCREENSHOT_THEME")
      .flatMap { ScreenshotTheme(rawValue: $0.lowercased()) }
    #else
    nil
    #endif
  }

  public static var stateIdentifier: String? {
    #if DEBUG
    stringValue(argument: "-state", environmentKey: "SCREENSHOT_STATE")
    #else
    nil
    #endif
  }

  private static func stringValue(argument: String, environmentKey: String) -> String? {
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: argument),
       arguments.indices.contains(index + 1) {
      return arguments[index + 1]
    }
    return ProcessInfo.processInfo.environment[environmentKey]
  }
}
