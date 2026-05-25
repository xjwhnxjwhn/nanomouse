//
//  AccentCharacterProvider.swift
//
//
//  Created by Codex on 2026/01/07.
//

import Foundation
import HamsterKit

public struct AccentCharacterOption: Equatable {
  public let character: String
  public let widthLabel: String?

  public init(character: String, widthLabel: String? = nil) {
    self.character = character
    self.widthLabel = widthLabel
  }
}

public struct AccentCharacterProvider {
  private static let symbolsFileName = "symbols_v.yaml"
  private static let cacheLock = NSLock()
  private static var cachedAccents: [String: [String]]?

  private enum WidthKind {
    case half
    case full

    var label: String {
      switch self {
      case .half:
        return "半"
      case .full:
        return "全"
      }
    }
  }

  private static let fallbackAccents: [String: [String]] = {
    var accents = AccentSymbolsVSingle.letterAccents
    accents["$"] = ["¥", "€", "£", "¢", "₽", "₩"]
    accents["\""] = ["“", "”", "„", "«", "»"]
    accents["'"] = ["‘", "’", "`"]
    accents["."] = ["…"]
    accents["?"] = ["¿"]
    accents["!"] = ["¡"]
    accents["-"] = ["–", "—", "•"]
    accents["/"] = ["\\"]
    accents["%"] = ["‰"]
    return accents
  }()

  /// 获取按键对应的变音符号列表
  public static func accents(for key: String) -> [String]? {
    accentOptions(for: key)?.map(\.character)
  }

  /// 获取按键对应的变音符号列表，并标注半角/全角符号。
  public static func accentOptions(for key: String) -> [AccentCharacterOption]? {
    let keyForLookup = key.lowercased()
    let configuredAccents = accentMap()[keyForLookup] ?? []
    let widthVariants = halfAndFullWidthVariantOptions(for: key)
    let configuredOptions = configuredAccents.map { value in
      AccentCharacterOption(character: value, widthLabel: widthKind(for: value)?.label)
    }
    let options = uniqueOptions(widthVariants + configuredOptions)
    return options.isEmpty ? nil : options
  }

  static func buildAccentMap(symbolsVYaml: String?) -> [String: [String]] {
    var accents = fallbackAccents
    guard let symbolsVYaml else { return accents }

    for line in symbolsVYaml.split(whereSeparator: \.isNewline) {
      guard let (key, values) = parseSymbolsLine(String(line)) else { continue }
      accents[key] = values
    }
    return accents
  }

  private static func accentMap() -> [String: [String]] {
    cacheLock.lock()
    defer { cacheLock.unlock() }

    if let cachedAccents {
      return cachedAccents
    }

    let yaml = FileManager.loadRimeUserDataTextFile(named: symbolsFileName)
    let accents = buildAccentMap(symbolsVYaml: yaml)
    cachedAccents = accents
    return accents
  }

  private static func parseSymbolsLine(_ line: String) -> (String, [String])? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("'v"), trimmed.contains(": ["), trimmed.hasSuffix("]") else {
      return nil
    }

    let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }

    let rawKey = parts[0]
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    guard rawKey.count == 2,
          rawKey.hasPrefix("v"),
          let letter = rawKey.last,
          ("a"..."z").contains(String(letter))
    else {
      return nil
    }

    let rawValues = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard rawValues.first == "[", rawValues.last == "]" else { return nil }

    let body = String(rawValues.dropFirst().dropLast())
    let values = normalizedEntries(from: body)
    guard !values.isEmpty else { return nil }
    return (String(letter), values)
  }

  private static func normalizedEntries(from body: String) -> [String] {
    var entries: [String] = []
    var seen = Set<String>()

    for rawValue in body.split(separator: ",", omittingEmptySubsequences: false) {
      let value = rawValue
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
      guard !value.isEmpty else { continue }
      guard seen.insert(value).inserted else { continue }
      entries.append(value)
    }

    return entries
  }

  private static func halfAndFullWidthVariantOptions(for key: String) -> [AccentCharacterOption] {
    guard key.count == 1 else { return [] }
    let half = halfWidthEquivalent(for: key)
    let full = fullWidthEquivalents(for: key)
    guard half != nil || !full.isEmpty else { return [] }
    var variants: [AccentCharacterOption] = []
    if let half {
      variants.append(.init(character: half, widthLabel: widthKind(for: half)?.label))
    }
    variants.append(.init(character: key, widthLabel: widthKind(for: key)?.label))
    variants.append(contentsOf: full.map { .init(character: $0, widthLabel: WidthKind.full.label) })
    return uniqueOptions(variants)
  }

  private static func halfWidthEquivalent(for key: String) -> String? {
    if let mapped = preferredHalfWidthEquivalents[key] {
      return mapped
    }
    guard let scalar = key.unicodeScalars.first else { return nil }
    let value = scalar.value
    if (0xFF01...0xFF5E).contains(value), let ascii = UnicodeScalar(value - 0xFEE0) {
      return String(ascii)
    }
    return nil
  }

  private static func fullWidthEquivalents(for key: String) -> [String] {
    var variants = preferredFullWidthEquivalents[key] ?? []
    guard let scalar = key.unicodeScalars.first else { return variants }
    let value = scalar.value
    if isAsciiDigit(value) || isAsciiSymbol(value),
       let fullWidthScalar = UnicodeScalar(value + 0xFEE0)
    {
      variants.insert(String(fullWidthScalar), at: 0)
    }
    return uniqueEntries(variants)
  }

  private static func widthKind(for value: String) -> WidthKind? {
    guard value.count == 1, let scalar = value.unicodeScalars.first else { return nil }
    let scalarValue = scalar.value
    if isAsciiDigit(scalarValue) || isAsciiSymbol(scalarValue) {
      return .half
    }
    if (0xFF01...0xFF5E).contains(scalarValue) || preferredHalfWidthEquivalents[value] != nil {
      return .full
    }
    return nil
  }

  private static func isAsciiDigit(_ value: UInt32) -> Bool {
    (0x30...0x39).contains(value)
  }

  private static func isAsciiSymbol(_ value: UInt32) -> Bool {
    guard (0x21...0x7E).contains(value) else { return false }
    return !(0x41...0x5A).contains(value) && !(0x61...0x7A).contains(value)
  }

  private static func uniqueEntries(_ values: [String]) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for value in values {
      guard !value.isEmpty, seen.insert(value).inserted else { continue }
      result.append(value)
    }
    return result
  }

  private static func uniqueOptions(_ options: [AccentCharacterOption]) -> [AccentCharacterOption] {
    var result: [AccentCharacterOption] = []
    var seen = Set<String>()
    for option in options {
      guard !option.character.isEmpty, seen.insert(option.character).inserted else { continue }
      result.append(option)
    }
    return result
  }

  private static let preferredFullWidthEquivalents: [String: [String]] = [
    ",": ["，", "、"],
    ".": ["．", "。"],
    ":": ["："],
    ";": ["；"],
    "?": ["？"],
    "!": ["！"],
    "(": ["（"],
    ")": ["）"],
    "[": ["［", "【", "「", "『"],
    "]": ["］", "】", "」", "』"],
    "{": ["｛"],
    "}": ["｝"],
    "<": ["＜", "《", "〈"],
    ">": ["＞", "》", "〉"],
    "$": ["＄"],
    "&": ["＆"],
    "@": ["＠"],
    "\"": ["＂", "“", "”"],
    "'": ["＇", "‘", "’"],
    "-": ["－", "—"],
    "/": ["／"],
    "\\": ["＼"],
    "|": ["｜"],
    "~": ["～"],
    "¥": ["￥"],
    "･": ["・"]
  ]

  private static let preferredHalfWidthEquivalents: [String: String] = [
    "，": ",",
    "、": ",",
    "．": ".",
    "。": ".",
    "：": ":",
    "；": ";",
    "？": "?",
    "！": "!",
    "（": "(",
    "）": ")",
    "【": "[",
    "】": "]",
    "「": "[",
    "」": "]",
    "『": "[",
    "』": "]",
    "《": "<",
    "》": ">",
    "〈": "<",
    "〉": ">",
    "￥": "¥",
    "｜": "|",
    "＂": "\"",
    "“": "\"",
    "”": "\"",
    "＇": "'",
    "‘": "'",
    "’": "'",
    "－": "-",
    "—": "-",
    "／": "/",
    "＼": "\\",
    "～": "~",
    "・": "･"
  ]
}
