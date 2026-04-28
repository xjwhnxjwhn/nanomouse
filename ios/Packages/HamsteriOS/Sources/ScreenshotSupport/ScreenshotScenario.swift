//
//  ScreenshotScenario.swift
//
//
//  Screenshot automation scenarios for App Store screenshot capture.
//

import Foundation

public enum ScreenshotScenario: String, CaseIterable, Sendable {
  case home
  case editor
  case settings
  case bytePaste
  case bytePasteEditor
  case canvas
  case markdown
  case causal
  case keyboardExtension
  case premium
  case onboarding
  case emptyState
  case errorState

  public var readyIdentifier: String {
    "screenshot_ready_\(rawValue)"
  }

  public var outputName: String {
    switch self {
    case .home:
      return "01_home"
    case .editor:
      return "02_editor"
    case .settings:
      return "03_settings"
    case .bytePaste:
      return "04_byte_paste"
    case .bytePasteEditor:
      return "05_byte_paste_editor"
    case .canvas:
      return "06_canvas"
    case .markdown:
      return "07_markdown"
    case .causal:
      return "08_causal"
    case .keyboardExtension:
      return "09_keyboard_extension"
    case .premium:
      return "10_premium"
    case .onboarding:
      return "11_onboarding"
    case .emptyState:
      return "12_empty_state"
    case .errorState:
      return "13_error_state"
    }
  }

  public var readyDelayNanoseconds: UInt64 {
    switch self {
    case .bytePasteEditor:
      return 1_500_000_000
    case .keyboardExtension:
      return 1_800_000_000
    default:
      return 700_000_000
    }
  }
}
