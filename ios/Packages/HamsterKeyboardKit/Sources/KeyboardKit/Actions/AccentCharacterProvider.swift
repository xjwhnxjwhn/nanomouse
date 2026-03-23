//
//  AccentCharacterProvider.swift
//
//
//  Created by Codex on 2026/01/07.
//

import Foundation
import HamsterKit

public struct AccentCharacterProvider {
  private static let symbolsFileName = "symbols_v.yaml"
  private static let cacheLock = NSLock()
  private static var cachedAccents: [String: [String]]?

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
    accentMap()[key.lowercased()]
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
}
