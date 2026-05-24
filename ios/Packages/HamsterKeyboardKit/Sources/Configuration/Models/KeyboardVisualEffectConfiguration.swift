//
//  KeyboardVisualEffectConfiguration.swift
//
//
//  Created by Codex on 2026/05/24.
//

import Foundation

public enum KeyboardVisualEffectStyle: String, Codable, CaseIterable, Hashable {
  case system
  case ios18Blur
  case ios26LiquidGlass
}

public enum KeyboardVisualEffectTarget: String, Codable, CaseIterable, Hashable {
  case keyInputCallout
  case keyLongPressMenu
  case textReplacementBubble
}

public struct KeyboardVisualEffectConfiguration: Codable, Hashable {
  public var defaultStyle: KeyboardVisualEffectStyle?
  public var keyInputCalloutStyle: KeyboardVisualEffectStyle?
  public var keyLongPressMenuStyle: KeyboardVisualEffectStyle?
  public var textReplacementBubbleStyle: KeyboardVisualEffectStyle?

  public init(
    defaultStyle: KeyboardVisualEffectStyle? = .system,
    keyInputCalloutStyle: KeyboardVisualEffectStyle? = nil,
    keyLongPressMenuStyle: KeyboardVisualEffectStyle? = nil,
    textReplacementBubbleStyle: KeyboardVisualEffectStyle? = nil
  ) {
    self.defaultStyle = defaultStyle
    self.keyInputCalloutStyle = keyInputCalloutStyle
    self.keyLongPressMenuStyle = keyLongPressMenuStyle
    self.textReplacementBubbleStyle = textReplacementBubbleStyle
  }

  public func style(for target: KeyboardVisualEffectTarget) -> KeyboardVisualEffectStyle {
    switch target {
    case .keyInputCallout:
      return keyInputCalloutStyle ?? defaultStyle ?? .system
    case .keyLongPressMenu:
      return keyLongPressMenuStyle ?? defaultStyle ?? .system
    case .textReplacementBubble:
      return textReplacementBubbleStyle ?? defaultStyle ?? .system
    }
  }
}
