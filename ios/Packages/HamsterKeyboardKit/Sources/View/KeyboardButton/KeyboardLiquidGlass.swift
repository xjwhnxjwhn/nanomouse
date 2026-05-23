//
//  KeyboardLiquidGlass.swift
//
//
//  Created by Codex on 2026/05/23.
//

import UIKit

enum KeyboardLiquidGlass {
  static func effect(userInterfaceStyle: UIUserInterfaceStyle) -> UIVisualEffect {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .regular)
      effect.tintColor = style == .dark
        ? UIColor.white.withAlphaComponent(0.16)
        : UIColor.white.withAlphaComponent(0.34)
      effect.isInteractive = true
      return effect
    }
    return UIBlurEffect(style: style == .dark ? .systemThickMaterialDark : .systemThickMaterialLight)
  }

  static func tintColor(userInterfaceStyle: UIUserInterfaceStyle) -> UIColor {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    if #available(iOS 26.0, *) {
      return style == .dark
        ? UIColor.black.withAlphaComponent(0.22)
        : UIColor.white.withAlphaComponent(0.18)
    }
    return style == .dark
      ? UIColor.black.withAlphaComponent(0.36)
      : UIColor.white.withAlphaComponent(0.42)
  }

  static func strokeColor(userInterfaceStyle: UIUserInterfaceStyle) -> UIColor {
    resolvedUserInterfaceStyle(userInterfaceStyle) == .dark
      ? UIColor.white.withAlphaComponent(0.22)
      : UIColor.white.withAlphaComponent(0.62)
  }

  static func shadowOpacity(userInterfaceStyle: UIUserInterfaceStyle) -> Float {
    resolvedUserInterfaceStyle(userInterfaceStyle) == .dark ? 0.42 : 0.22
  }

  static func selectionColor(textColor: UIColor, userInterfaceStyle: UIUserInterfaceStyle) -> UIColor {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    return style == .dark
      ? UIColor.white.withAlphaComponent(0.16)
      : textColor.withAlphaComponent(0.10)
  }

  private static func resolvedUserInterfaceStyle(_ style: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
    style == .dark ? .dark : .light
  }
}
