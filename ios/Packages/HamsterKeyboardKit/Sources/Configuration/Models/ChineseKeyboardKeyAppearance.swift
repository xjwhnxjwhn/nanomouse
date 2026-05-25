//
//  ChineseKeyboardKeyAppearance.swift
//
//
//  Created by Codex on 2026/05/24.
//

import Foundation
import HamsterKit
import UIKit

public struct ChineseKeyboardKeyAppearance: Codable, Hashable {
  public var backgroundColorHex: String?
  public var textColorHex: String?
  public var borderColorHex: String?
  public var backgroundImagePath: String?

  public init(
    backgroundColorHex: String? = nil,
    textColorHex: String? = nil,
    borderColorHex: String? = nil,
    backgroundImagePath: String? = nil
  ) {
    self.backgroundColorHex = backgroundColorHex
    self.textColorHex = textColorHex
    self.borderColorHex = borderColorHex
    self.backgroundImagePath = backgroundImagePath
  }

  public var isEmpty: Bool {
    backgroundColorHex?.isEmpty != false &&
      textColorHex?.isEmpty != false &&
      borderColorHex?.isEmpty != false &&
      backgroundImagePath?.isEmpty != false
  }
}

public extension Dictionary where Key == String, Value == ChineseKeyboardKeyAppearance {
  func appearance(forActionID actionID: String) -> ChineseKeyboardKeyAppearance? {
    if let appearance = self[actionID] {
      return appearance
    }
    guard actionID.hasPrefix("character(") || actionID.hasPrefix("symbol(") else {
      return nil
    }
    return self[actionID.lowercased()]
  }
}

public extension UserDefaults {
  var chineseKeyboardKeyAppearanceOverrides: [String: ChineseKeyboardKeyAppearance] {
    get {
      guard let data = data(forKey: Self.chineseKeyboardKeyAppearanceOverridesKey),
            let value = try? JSONDecoder().decode([String: ChineseKeyboardKeyAppearance].self, from: data)
      else {
        return [:]
      }
      return value
    }
    set {
      let cleaned = newValue.filter { !$0.value.isEmpty }
      guard !cleaned.isEmpty else {
        removeObject(forKey: Self.chineseKeyboardKeyAppearanceOverridesKey)
        return
      }
      if let data = try? JSONEncoder().encode(cleaned) {
        set(data, forKey: Self.chineseKeyboardKeyAppearanceOverridesKey)
      }
    }
  }

  private static var chineseKeyboardKeyAppearanceOverridesKey: String {
    "com.XiangqingZHANG.nanomouse.UserDefault.keys.chineseKeyboardKeyAppearanceOverrides"
  }
}

public extension ChineseKeyboardKeyAppearance {
  var backgroundUIColor: UIColor? {
    backgroundColorHex?.keyboardAppearanceUIColor
  }

  var textUIColor: UIColor? {
    textColorHex?.keyboardAppearanceUIColor
  }

  var borderUIColor: UIColor? {
    borderColorHex?.keyboardAppearanceUIColor
  }

  var backgroundImageURL: URL? {
    guard let path = backgroundImagePath, !path.isEmpty else { return nil }
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path)
    }
    return FileManager.appGroupUserDataDirectoryURL.appendingPathComponent(path)
  }
}

private extension String {
  var keyboardAppearanceUIColor: UIColor? {
    var value = trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6 || value.count == 8, let hex = UInt64(value, radix: 16) else { return nil }
    let hasAlpha = value.count == 8
    let alpha = hasAlpha ? CGFloat((hex & 0xff00_0000) >> 24) / 255 : 1
    let red = CGFloat((hex & (hasAlpha ? 0x00ff_0000 : 0xff_0000)) >> 16) / 255
    let green = CGFloat((hex & (hasAlpha ? 0x0000_ff00 : 0x00_ff00)) >> 8) / 255
    let blue = CGFloat(hex & 0x0000_00ff) / 255
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}
