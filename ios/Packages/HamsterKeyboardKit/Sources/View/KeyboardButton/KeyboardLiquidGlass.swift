//
//  KeyboardLiquidGlass.swift
//
//
//  Created by Codex on 2026/05/23.
//

import UIKit

public enum KeyboardLiquidGlass {
  private enum RenderProfile: Equatable {
    case nativeLiquidGlassRegular
    case nativeLiquidGlassClear
    case ios18Blur
    case liquidGlassFallbackRegular
    case liquidGlassFallbackClear
    case transparent
  }

  public static func effect(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyInputCallout
  ) -> UIVisualEffect? {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    let profile = renderProfile(configuration: configuration, target: target, userInterfaceStyle: style)
    let intensity = glassIntensity(configuration, userInterfaceStyle: style)
    if profile == .transparent {
      return nil
    }
    if (profile == .nativeLiquidGlassRegular || profile == .nativeLiquidGlassClear), #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: nativeGlassStyle(for: profile))
      if target == .keyboardBackground {
        effect.tintColor = style == .dark
          ? UIColor.white.withAlphaComponent(0.04 * intensity)
          : UIColor.white.withAlphaComponent(0.24 * intensity)
      } else if target == .keySurface {
        effect.tintColor = style == .dark
          ? UIColor.white.withAlphaComponent(0.03 * intensity)
          : UIColor.white.withAlphaComponent(0.26 * intensity)
      } else {
        effect.tintColor = style == .dark
          ? UIColor.white.withAlphaComponent(0.10 * intensity)
          : UIColor.white.withAlphaComponent(0.30 * intensity)
      }
      effect.isInteractive = true
      return effect
    }

    return UIBlurEffect(style: blurStyle(userInterfaceStyle: style, profile: profile, intensity: intensity))
  }

  public static func tintColor(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyInputCallout
  ) -> UIColor {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    let profile = renderProfile(configuration: configuration, target: target, userInterfaceStyle: style)
    let intensity = glassIntensity(configuration, userInterfaceStyle: style)
    if profile == .transparent {
      return .clear
    }

    if profile == .nativeLiquidGlassRegular || profile == .nativeLiquidGlassClear, #available(iOS 26.0, *) {
      if target == .keyboardBackground {
        return style == .dark
          ? UIColor.black.withAlphaComponent(0.08 * intensity)
          : UIColor.white.withAlphaComponent(0.14 * intensity)
      }
      if target == .keySurface {
        return style == .dark
          ? UIColor.black.withAlphaComponent(0.10 * intensity)
          : UIColor.white.withAlphaComponent(0.16 * intensity)
      }
      return style == .dark
        ? UIColor.black.withAlphaComponent(0.12 * intensity)
        : UIColor.white.withAlphaComponent(0.18 * intensity)
    }

    if profile == .liquidGlassFallbackRegular || profile == .liquidGlassFallbackClear {
      if target == .keyboardBackground {
        return style == .dark
          ? UIColor.white.withAlphaComponent(0.08 * intensity)
          : UIColor.white.withAlphaComponent(0.20 * intensity)
      }
      if target == .keySurface {
        if profile == .liquidGlassFallbackClear {
          return style == .dark
            ? UIColor.white.withAlphaComponent(0.05 * intensity)
            : UIColor.white.withAlphaComponent(0.20 * intensity)
        }
        return style == .dark
          ? UIColor.white.withAlphaComponent(0.10 * intensity)
          : UIColor.white.withAlphaComponent(0.36 * intensity)
      }
      return style == .dark
        ? UIColor.white.withAlphaComponent(0.07 * intensity)
        : UIColor.white.withAlphaComponent(0.18 * intensity)
    }

    return style == .dark
      ? UIColor.white.withAlphaComponent(0.05)
      : UIColor.white.withAlphaComponent(target == .keyInputCallout ? 0.08 : 0.12)
  }

  public static func strokeColor(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyInputCallout
  ) -> UIColor {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    let profile = renderProfile(configuration: configuration, target: target, userInterfaceStyle: style)
    let intensity = glassIntensity(configuration, userInterfaceStyle: style)
    if profile == .transparent {
      return .clear
    }

    if profile == .liquidGlassFallbackRegular || profile == .liquidGlassFallbackClear {
      return style == .dark
        ? UIColor.white.withAlphaComponent((target == .keySurface ? 0.08 : 0.20) * intensity)
        : UIColor.white.withAlphaComponent((target == .keySurface ? 0.72 : target == .keyboardBackground ? 0.36 : 0.56) * intensity)
    }

    if (profile == .nativeLiquidGlassRegular || profile == .nativeLiquidGlassClear), target == .keyboardBackground {
      return style == .dark
        ? UIColor.white.withAlphaComponent(0.08 * intensity)
        : UIColor.white.withAlphaComponent(0.34 * intensity)
    }

    if profile == .nativeLiquidGlassRegular, target == .keySurface {
      return style == .dark
        ? UIColor.white.withAlphaComponent(0.035 * intensity)
        : UIColor.white.withAlphaComponent(0.64 * intensity)
    }

    if profile == .nativeLiquidGlassClear, target == .keySurface {
      return style == .dark
        ? UIColor.white.withAlphaComponent(0.06 * intensity)
        : UIColor.white.withAlphaComponent(0.42 * intensity)
    }

    return style == .dark
      ? UIColor.white.withAlphaComponent(0.18)
      : UIColor.white.withAlphaComponent(0.62)
  }

  public static func shadowOpacity(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keyInputCallout
  ) -> Float {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    let profile = renderProfile(configuration: configuration, target: target, userInterfaceStyle: style)
    let intensity = Float(glassIntensity(configuration, userInterfaceStyle: style))
    if profile == .transparent {
      return 0
    }
    if profile == .ios18Blur {
      return style == .dark ? 0.28 : 0.14
    }
    if target == .keyboardBackground {
      return (style == .dark ? 0.16 : 0.10) * intensity
    }
    if target == .keySurface {
      return (style == .dark ? 0.22 : 0.14) * intensity
    }
    return (style == .dark ? 0.32 : 0.22) * intensity
  }

  public static func defaultKeySurfaceStrokeWidth(
    userInterfaceStyle: UIUserInterfaceStyle = .light,
    configuration: KeyboardVisualEffectConfiguration? = nil
  ) -> CGFloat {
    let profile = renderProfile(
      configuration: configuration,
      target: .keySurface,
      userInterfaceStyle: resolvedUserInterfaceStyle(userInterfaceStyle)
    )
    switch profile {
    case .nativeLiquidGlassRegular, .liquidGlassFallbackRegular:
      return 1 / UIScreen.main.scale
    case .nativeLiquidGlassClear, .liquidGlassFallbackClear, .ios18Blur, .transparent:
      return 0
    }
  }

  public static func selectionColor(
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

  public static func keySurfaceWhiteOverlayColor(
    userInterfaceStyle: UIUserInterfaceStyle,
    configuration: KeyboardVisualEffectConfiguration? = nil
  ) -> UIColor {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    let intensity = CGFloat(configuration?.keySurfaceWhiteOverlayIntensity(for: style) ?? 0)
    guard intensity > 0 else { return .clear }
    let maximumAlpha: CGFloat = style == .dark ? 0.34 : 0.44
    return UIColor.white.withAlphaComponent(maximumAlpha * intensity)
  }

  public static func shouldRenderVisualSurface(
    configuration: KeyboardVisualEffectConfiguration? = nil,
    target: KeyboardVisualEffectTarget = .keySurface,
    userInterfaceStyle: UIUserInterfaceStyle = .light
  ) -> Bool {
    let profile = renderProfile(
      configuration: configuration,
      target: target,
      userInterfaceStyle: resolvedUserInterfaceStyle(userInterfaceStyle)
    )
    switch profile {
    case .nativeLiquidGlassRegular, .nativeLiquidGlassClear, .liquidGlassFallbackRegular, .liquidGlassFallbackClear:
      return true
    case .ios18Blur:
      return target == .keyboardBackground
    case .transparent:
      return false
    }
  }

  private static func renderProfile(
    configuration: KeyboardVisualEffectConfiguration?,
    target: KeyboardVisualEffectTarget,
    userInterfaceStyle: UIUserInterfaceStyle
  ) -> RenderProfile {
    let effectStyle = configuration?.style(for: target, userInterfaceStyle: userInterfaceStyle) ?? .system
    switch effectStyle {
    case .system:
      if #available(iOS 26.0, *) {
        return .nativeLiquidGlassRegular
      }
      return .ios18Blur
    case .ios18Blur:
      return .ios18Blur
    case .ios26LiquidGlass:
      if #available(iOS 26.0, *) {
        return .nativeLiquidGlassRegular
      }
      return .liquidGlassFallbackRegular
    case .ios26ClearLiquidGlass:
      if #available(iOS 26.0, *) {
        return .nativeLiquidGlassClear
      }
      return .liquidGlassFallbackClear
    case .transparent:
      return .transparent
    }
  }

  private static func blurStyle(
    userInterfaceStyle: UIUserInterfaceStyle,
    profile: RenderProfile,
    intensity: CGFloat
  ) -> UIBlurEffect.Style {
    let style = resolvedUserInterfaceStyle(userInterfaceStyle)
    switch profile {
    case .nativeLiquidGlassRegular, .nativeLiquidGlassClear:
      return style == .dark ? .systemThinMaterialDark : .systemThinMaterialLight
    case .ios18Blur:
      return style == .dark ? .systemThinMaterialDark : .systemThinMaterialLight
    case .liquidGlassFallbackRegular:
      if intensity < 0.35 {
        return style == .dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
      }
      if intensity < 0.75 {
        return style == .dark ? .systemThinMaterialDark : .systemThinMaterialLight
      }
      return style == .dark ? .systemMaterialDark : .systemMaterialLight
    case .liquidGlassFallbackClear, .transparent:
      return style == .dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
    }
  }

  private static func glassIntensity(
    _ configuration: KeyboardVisualEffectConfiguration?,
    userInterfaceStyle: UIUserInterfaceStyle
  ) -> CGFloat {
    CGFloat(configuration?.glassIntensity(for: userInterfaceStyle) ?? 1)
  }

  @available(iOS 26.0, *)
  private static func nativeGlassStyle(for profile: RenderProfile) -> UIGlassEffect.Style {
    profile == .nativeLiquidGlassClear ? .clear : .regular
  }

  private static func resolvedUserInterfaceStyle(_ style: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
    style == .dark ? .dark : .light
  }
}
