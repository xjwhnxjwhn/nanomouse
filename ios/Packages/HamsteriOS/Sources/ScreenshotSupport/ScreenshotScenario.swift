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
  case keyboardChinese
  case keyboardLongPressA
  case keyboardNumberPad
  case bytePasteImagePreview
  case bytePastePDFPreview
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
    case .keyboardChinese:
      return "10_keyboard_chinese"
    case .keyboardLongPressA:
      return "11_keyboard_long_press_a"
    case .keyboardNumberPad:
      return "12_keyboard_number_pad"
    case .bytePasteImagePreview:
      return "13_byte_paste_image_preview"
    case .bytePastePDFPreview:
      return "14_byte_paste_pdf_preview"
    case .premium:
      return "15_premium"
    case .onboarding:
      return "16_onboarding"
    case .emptyState:
      return "17_empty_state"
    case .errorState:
      return "18_error_state"
    }
  }

  public var readyDelayNanoseconds: UInt64 {
    switch self {
    case .bytePasteEditor:
      return 1_500_000_000
    case .bytePasteImagePreview:
      return 2_500_000_000
    case .bytePastePDFPreview:
      return 3_500_000_000
    case .keyboardExtension, .keyboardChinese, .keyboardNumberPad:
      return 2_400_000_000
    case .keyboardLongPressA:
      return 3_400_000_000
    default:
      return 700_000_000
    }
  }

  public var isKeyboardScreenshot: Bool {
    switch self {
    case .keyboardExtension, .keyboardChinese, .keyboardLongPressA, .keyboardNumberPad:
      return true
    default:
      return false
    }
  }
}
