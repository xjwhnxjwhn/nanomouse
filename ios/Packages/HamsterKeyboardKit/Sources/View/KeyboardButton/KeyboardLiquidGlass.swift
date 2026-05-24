//
//  KeyboardLiquidGlass.swift
//
//
//  Created by Codex on 2026/05/23.
//

import UIKit

enum KeyboardLiquidGlass {
  private enum RenderProfile: Equatable {
    case nativeLiquidGlass
    case ios18Blur
    case liquidGlassFallback
  }

  static func effect(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyInputCallout
  ) -> UIVisualEffect {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    let profile = renderProfile(configuration: configuration, target: target)
    if profile == .nativeLiquidGlass, #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .regular)
      effect.tintColor = style == .dark
        ? UIColor.white.withAlphaComponent(0.16)
        : UIColor.white.withAlphaComponent(0.34)
      effect.isInteractive = true
      return effect
    }

    return UIBlurEffect(style: blurStyle(userInterfaceStyle: style, profile: profile))
  }

  static func tintColor(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyInputCallout
  ) -> UIColor {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    let profile = renderProfile(configuration: configuration, target: target)
    if profile == .nativeLiquidGlass, #available(iOS 26.0, *) {
      return style == .dark
        ? UIColor.black.withAlphaComponent(0.22)
        : UIColor.white.withAlphaComponent(0.18)
    }

    if profile == .liquidGlassFallback {
      return style == .dark
        ? UIColor.white.withAlphaComponent(0.07)
        : UIColor.white.withAlphaComponent(0.18)
    }

    return style == .dark
      ? UIColor.white.withAlphaComponent(0.05)
      : UIColor.white.withAlphaComponent(target == .keyInputCallout ? 0.08 : 0.12)
  }

  static func strokeColor(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyInputCallout
  ) -> UIColor {
    let profile = renderProfile(configuration: configuration, target: target)
    if profile == .liquidGlassFallback {
      return resolvedUserInterfaceStyle(userInterfaceStyle) == .dark
        ? UIColor.white.withAlphaComponent(0.20)
        : UIColor.white.withAlphaComponent(0.56)
    }

    return resolvedUserInterfaceStyle(userInterfaceStyle) == .dark
      ? UIColor.white.withAlphaComponent(0.18)
      : UIColor.white.withAlphaComponent(0.62)
  }

  static func shadowOpacity(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyInputCallout
  ) -> Float {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    let profile = renderProfile(configuration: configuration, target: target)
    if profile == .ios18Blur {
      return style == .dark ? 0.28 : 0.14
    }
    return style == .dark ? 0.42 : 0.22
  }

  static func selectionColor(
    textColor: UIColor,
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyLongPressMenu
  ) -> UIColor {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    return style == .dark
      ? UIColor.white.withAlphaComponent(0.16)
      : textColor.withAlphaComponent(0.10)
  }

  private static func renderProfile(
    configuration: KeyboardVisualEffectConfiguration?,
    target: KeyboardVisualEffectTarget
  ) -> RenderProfile {
    let effectStyle = configuration?.style(for: target) ?? .system
    switch effectStyle {
    case .system:
      if #available(iOS 26.0, *) {
        return .nativeLiquidGlass
      }
      return .ios18Blur
    case .ios18Blur:
      return .ios18Blur
    case .ios26LiquidGlass:
      if #available(iOS 26.0, *) {
        return .nativeLiquidGlass
      }
      return .liquidGlassFallback
    }
  }

  private static func blurStyle(
    userInterfaceStyle: UIUserInterfaceStyle,
    profile: RenderProfile
  ) -> UIBlurEffect.Style {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    switch profile {
    case .nativeLiquidGlass:
      return style == .dark ? .systemThinMaterialDark : .systemThinMaterialLight
    case .ios18Blur:
      return style == .dark ? .systemThinMaterialDark : .systemThinMaterialLight
    case .liquidGlassFallback:
      return style == .dark ? .systemMaterialDark : .systemThinMaterialLight
    }
  }

  private static func resolvedUserInterfaceStyle(_ style: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
    style == .dark ? .dark : .light
  }
}
