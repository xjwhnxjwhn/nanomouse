//
//  KeyboardVisualEffectConfiguration.swift
//
//
//  Created by Codex on 2026/05/24.
//

import Foundation
import UIKit

public enum KeyboardVisualEffectStyle: String, Codable, CaseIterable, Hashable {
  case system
  case ios18Blur
  case ios26LiquidGlass
  case ios26ClearLiquidGlass
  case transparent
}

public enum KeyboardVisualEffectTarget: String, Codable, CaseIterable, Hashable {
  case keyboardBackground
  case keySurface
  case keyInputCallout
  case keyLongPressMenu
  case textReplacementBubble
}

public struct KeyboardVisualEffectConfiguration: Codable, Hashable {
  public var defaultStyle: KeyboardVisualEffectStyle?
  public var glassIntensity: Double?
  public var keySurfaceWhiteOverlayIntensity: Double?
  public var keyboardBackgroundStyle: KeyboardVisualEffectStyle?
  public var keySurfaceStyle: KeyboardVisualEffectStyle?
  public var keyInputCalloutStyle: KeyboardVisualEffectStyle?
  public var keyLongPressMenuStyle: KeyboardVisualEffectStyle?
  public var textReplacementBubbleStyle: KeyboardVisualEffectStyle?
  public var darkDefaultStyle: KeyboardVisualEffectStyle?
  public var darkGlassIntensity: Double?
  public var darkKeySurfaceWhiteOverlayIntensity: Double?
  public var darkKeySurfaceStyle: KeyboardVisualEffectStyle?
  public var darkKeyInputCalloutStyle: KeyboardVisualEffectStyle?
  public var darkKeyLongPressMenuStyle: KeyboardVisualEffectStyle?
  public var darkTextReplacementBubbleStyle: KeyboardVisualEffectStyle?

  public init(
    defaultStyle: KeyboardVisualEffectStyle? = .system,
    glassIntensity: Double? = nil,
    keySurfaceWhiteOverlayIntensity: Double? = nil,
    keyboardBackgroundStyle: KeyboardVisualEffectStyle? = nil,
    keySurfaceStyle: KeyboardVisualEffectStyle? = nil,
    keyInputCalloutStyle: KeyboardVisualEffectStyle? = nil,
    keyLongPressMenuStyle: KeyboardVisualEffectStyle? = nil,
    textReplacementBubbleStyle: KeyboardVisualEffectStyle? = nil,
    darkDefaultStyle: KeyboardVisualEffectStyle? = nil,
    darkGlassIntensity: Double? = nil,
    darkKeySurfaceWhiteOverlayIntensity: Double? = nil,
    darkKeySurfaceStyle: KeyboardVisualEffectStyle? = nil,
    darkKeyInputCalloutStyle: KeyboardVisualEffectStyle? = nil,
    darkKeyLongPressMenuStyle: KeyboardVisualEffectStyle? = nil,
    darkTextReplacementBubbleStyle: KeyboardVisualEffectStyle? = nil
  ) {
    self.defaultStyle = defaultStyle
    self.glassIntensity = glassIntensity
    self.keySurfaceWhiteOverlayIntensity = keySurfaceWhiteOverlayIntensity
    self.keyboardBackgroundStyle = keyboardBackgroundStyle
    self.keySurfaceStyle = keySurfaceStyle
    self.keyInputCalloutStyle = keyInputCalloutStyle
    self.keyLongPressMenuStyle = keyLongPressMenuStyle
    self.textReplacementBubbleStyle = textReplacementBubbleStyle
    self.darkDefaultStyle = darkDefaultStyle
    self.darkGlassIntensity = darkGlassIntensity
    self.darkKeySurfaceWhiteOverlayIntensity = darkKeySurfaceWhiteOverlayIntensity
    self.darkKeySurfaceStyle = darkKeySurfaceStyle
    self.darkKeyInputCalloutStyle = darkKeyInputCalloutStyle
    self.darkKeyLongPressMenuStyle = darkKeyLongPressMenuStyle
    self.darkTextReplacementBubbleStyle = darkTextReplacementBubbleStyle
  }

  public func style(for target: KeyboardVisualEffectTarget) -> KeyboardVisualEffectStyle {
    style(for: target, userInterfaceStyle: .light)
  }

  public func style(
    for target: KeyboardVisualEffectTarget,
    userInterfaceStyle: UIUserInterfaceStyle
  ) -> KeyboardVisualEffectStyle {
    if userInterfaceStyle == .dark {
      let legacyDarkDefaultStyle = darkDefaultStyle == .system ? nil : darkDefaultStyle
      switch target {
      case .keyboardBackground:
        return .system
      case .keySurface:
        return Self.specifiedStyle(darkKeySurfaceStyle)
          ?? legacyDarkDefaultStyle
          ?? Self.automaticStyle(for: target)
      case .keyInputCallout:
        return Self.specifiedStyle(darkKeyInputCalloutStyle)
          ?? legacyDarkDefaultStyle
          ?? Self.automaticStyle(for: target)
      case .keyLongPressMenu:
        return Self.specifiedStyle(darkKeyLongPressMenuStyle)
          ?? legacyDarkDefaultStyle
          ?? Self.automaticStyle(for: target)
      case .textReplacementBubble:
        return Self.specifiedStyle(darkTextReplacementBubbleStyle)
          ?? legacyDarkDefaultStyle
          ?? Self.automaticStyle(for: target)
      }
    }

    let legacyDefaultStyle = defaultStyle == .system ? nil : defaultStyle
    switch target {
    case .keyboardBackground:
      return .system
    case .keySurface:
      return Self.specifiedStyle(keySurfaceStyle) ?? legacyDefaultStyle ?? Self.automaticStyle(for: target)
    case .keyInputCallout:
      return Self.specifiedStyle(keyInputCalloutStyle) ?? legacyDefaultStyle ?? Self.automaticStyle(for: target)
    case .keyLongPressMenu:
      return Self.specifiedStyle(keyLongPressMenuStyle) ?? legacyDefaultStyle ?? Self.automaticStyle(for: target)
    case .textReplacementBubble:
      return Self.specifiedStyle(textReplacementBubbleStyle) ?? legacyDefaultStyle ?? Self.automaticStyle(for: target)
    }
  }

  public func glassIntensity(for userInterfaceStyle: UIUserInterfaceStyle) -> Double {
    let value = userInterfaceStyle == .dark ? (darkGlassIntensity ?? 0) : (glassIntensity ?? 0)
    guard value.isFinite else { return 1 }
    return max(0, min(1, value))
  }

  public func keySurfaceWhiteOverlayIntensity(for userInterfaceStyle: UIUserInterfaceStyle) -> Double {
    let value = userInterfaceStyle == .dark
      ? (darkKeySurfaceWhiteOverlayIntensity ?? 0.25)
      : (keySurfaceWhiteOverlayIntensity ?? 0)
    guard value.isFinite else { return 0 }
    return max(0, min(1, value))
  }

  public static func automaticStyle(for target: KeyboardVisualEffectTarget) -> KeyboardVisualEffectStyle {
    switch target {
    case .keyboardBackground:
      return .system
    case .keySurface:
      if #available(iOS 26.0, *) {
        return .ios26ClearLiquidGlass
      }
      return .ios18Blur
    case .keyInputCallout:
      if #available(iOS 26.0, *) {
        return .ios26ClearLiquidGlass
      }
      return .ios18Blur
    case .keyLongPressMenu, .textReplacementBubble:
      if #available(iOS 26.0, *) {
        return .ios26LiquidGlass
      }
      return .ios18Blur
    }
  }

  private static func specifiedStyle(_ style: KeyboardVisualEffectStyle?) -> KeyboardVisualEffectStyle? {
    guard style != .system else { return nil }
    return style
  }
}
