//
//  KeyboardVisualEffectScheme.swift
//
//
//  Created by Codex on 2026/05/25.
//

import Foundation
import HamsterKeyboardKit
import HamsterKit
import UIKit

enum KeyboardVisualEffectSchemeAppearance: String, Codable, Hashable {
  case light
  case dark

  init(_ style: UIUserInterfaceStyle) {
    self = style == .dark ? .dark : .light
  }

  var userInterfaceStyle: UIUserInterfaceStyle {
    self == .dark ? .dark : .light
  }
}

struct KeyboardVisualEffectStyleSnapshot: Codable, Hashable {
  var glassIntensity: Double?
  var keySurfaceWhiteOverlayIntensity: Double?
  var keySurfaceStyle: KeyboardVisualEffectStyle?
  var keyInputCalloutStyle: KeyboardVisualEffectStyle?
  var keyLongPressMenuStyle: KeyboardVisualEffectStyle?
  var textReplacementBubbleStyle: KeyboardVisualEffectStyle?
}

struct KeyboardVisualEffectChinese26Snapshot: Codable, Hashable {
  var layoutProfile: ChineseKeyboardLayoutProfile
  var oneHandMode: ChineseKeyboardOneHandMode
  var horizontalGap: Double
  var verticalGap: Double
  var keyHeightScale: Double
  var borderWidth: Double
  var cornerRadius: Double
  var inputCalloutWidthScale: Double?
  var inputCalloutHeightScale: Double?
  var inputCalloutCornerRadius: Double?
  var backgroundColorHex: String?
  var keyBackgroundColorHex: String?
  var keyTextColorHex: String?
  var keyBorderColorHex: String?
  var keyAppearanceOverrides: [String: ChineseKeyboardKeyAppearance]
}

struct KeyboardVisualEffectScheme: Codable, Identifiable, Hashable {
  var schemaVersion: Int
  var id: String
  var name: String
  var appearance: KeyboardVisualEffectSchemeAppearance
  var keyboardTypeYAML: String
  var keyboardTypeLabel: String
  var visualEffect: KeyboardVisualEffectStyleSnapshot
  var chinese26: KeyboardVisualEffectChinese26Snapshot?
  var createdAt: Date
  var updatedAt: Date

  init(
    id: String = UUID().uuidString,
    name: String,
    appearance: KeyboardVisualEffectSchemeAppearance,
    keyboardType: KeyboardType,
    visualEffect: KeyboardVisualEffectStyleSnapshot,
    chinese26: KeyboardVisualEffectChinese26Snapshot? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.schemaVersion = 1
    self.id = id
    self.name = name
    self.appearance = appearance
    self.keyboardTypeYAML = keyboardType.yamlString
    self.keyboardTypeLabel = keyboardType.label
    self.visualEffect = visualEffect
    self.chinese26 = chinese26
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

final class KeyboardVisualEffectSchemeStore {
  static let shared = KeyboardVisualEffectSchemeStore()

  private let directoryURL: URL
  private let decoder = JSONDecoder()
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  private init() {
    directoryURL = FileManager.appGroupUserDataDirectoryURL
      .appendingPathComponent("KeyboardVisualEffectSchemes", isDirectory: true)
    decoder.dateDecodingStrategy = .iso8601
  }

  func schemes(
    appearance: KeyboardVisualEffectSchemeAppearance,
    keyboardType: KeyboardType
  ) -> [KeyboardVisualEffectScheme] {
    allSchemes()
      .filter {
        $0.appearance == appearance &&
          $0.keyboardTypeYAML == keyboardType.yamlString
      }
      .sorted {
        if $0.createdAt == $1.createdAt {
          return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return $0.createdAt < $1.createdAt
      }
  }

  func activeSchemeID(
    appearance: KeyboardVisualEffectSchemeAppearance,
    keyboardType: KeyboardType
  ) -> String? {
    UserDefaults.hamster.string(forKey: activeSchemeKey(appearance: appearance, keyboardType: keyboardType))
  }

  func setActiveSchemeID(
    _ id: String?,
    appearance: KeyboardVisualEffectSchemeAppearance,
    keyboardType: KeyboardType
  ) {
    let key = activeSchemeKey(appearance: appearance, keyboardType: keyboardType)
    if let id {
      UserDefaults.hamster.set(id, forKey: key)
    } else {
      UserDefaults.hamster.removeObject(forKey: key)
    }
  }

  func save(_ scheme: KeyboardVisualEffectScheme) throws {
    try ensureDirectoryExists()
    let data = try encoder.encode(scheme)
    try data.write(to: url(for: scheme.id), options: .atomic)
  }

  func exportURL(for scheme: KeyboardVisualEffectScheme) throws -> URL {
    try save(scheme)
    return url(for: scheme.id)
  }

  private func allSchemes() -> [KeyboardVisualEffectScheme] {
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }
    return urls
      .filter { $0.pathExtension.lowercased() == "json" }
      .compactMap { url in
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(KeyboardVisualEffectScheme.self, from: data)
      }
  }

  private func ensureDirectoryExists() throws {
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  private func url(for id: String) -> URL {
    directoryURL.appendingPathComponent("\(id).json", isDirectory: false)
  }

  private func activeSchemeKey(
    appearance: KeyboardVisualEffectSchemeAppearance,
    keyboardType: KeyboardType
  ) -> String {
    "com.XiangqingZHANG.nanomouse.UserDefault.keys.keyboardVisualEffectScheme.\(appearance.rawValue).\(keyboardType.yamlString)"
  }
}
