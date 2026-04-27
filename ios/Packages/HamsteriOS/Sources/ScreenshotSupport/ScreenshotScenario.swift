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
    case .premium:
      return "09_premium"
    case .onboarding:
      return "10_onboarding"
    case .emptyState:
      return "11_empty_state"
    case .errorState:
      return "12_error_state"
    }
  }

  public var readyDelayNanoseconds: UInt64 {
    switch self {
    case .bytePasteEditor:
      return 1_500_000_000
    default:
      return 700_000_000
    }
  }
}
