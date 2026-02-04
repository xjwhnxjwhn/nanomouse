//
//  SymbolCandidateGenerator.swift
//  HamsterKeyboardKit
//
//  Create symbol candidates aligned with AzooKey behavior.
//

import Foundation

enum SymbolCandidateGenerator {
  static func candidateTexts(for literal: String) -> [String] {
    guard !literal.isEmpty else { return [] }
    var results: [String] = []
    var seen = Set<String>()
    func appendUnique(_ text: String) {
      guard !text.isEmpty else { return }
      if seen.insert(text).inserted {
        results.append(text)
      }
    }

    let normalized = literal.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? literal
    let normalizedFullwidth = normalized.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? normalized

    appendUnique(literal)
    if normalized != literal {
      appendUnique(normalized)
    }
    if normalizedFullwidth != literal {
      appendUnique(normalizedFullwidth)
    }

    let group = symbolLookup[literal] ?? symbolLookup[normalized] ?? symbolLookup[normalizedFullwidth]
    if let group {
      for symbol in group {
        appendUnique(symbol)
        if symbol.count == 1 {
          if let transformed = symbol.applyingTransform(.fullwidthToHalfwidth, reverse: true),
             transformed != symbol
          {
            appendUnique(transformed)
          }
          if let transformed = symbol.applyingTransform(.fullwidthToHalfwidth, reverse: false),
             transformed != symbol
          {
            appendUnique(transformed)
          }
        }
      }
    }

    if normalized.count == 1, let ch = normalized.first {
      switch ch {
      case "!":
        ["!!", "‼", "❗", "❣", "❕", "‼︎", "⁉︎", "‼️", "⁉️", "¡", "！"].forEach { appendUnique($0) }
      case "?":
        ["??", "⁇", "❓", "❔", "⁉︎", "⁉️", "¿", "？"].forEach { appendUnique($0) }
      default:
        break
      }
    }

    return results
  }

  private static let symbolGroups: [[String]] = [
    ["☆", "★", "♡", "☾", "☽"],
    ["^", "＾"],
    ["¥", "$", "¢", "€", "£", "₿"],
    ["%", "‰"],
    ["°", "℃", "℉"],
    ["◯"],
    ["*", "※", "✳︎", "✴︎"],
    ["、", "。", "，", "．", "・", "…", "‥", "•"],
    ["+", "±", "⊕"],
    ["×", "❌", "✖️"],
    ["÷", "➗"],
    ["<", "≦", "≪", "〈", "《", "‹", "«"],
    [">", "≧", "≫", "〉", "》", "›", "»"],
    ["「", "『", "（", "［", "《", "【"],
    ["」", "』", "）", "］", "》", "】"],
    ["「」", "『』", "（）", "［］", "《》", "【】"],
    ["(", "{", "<", "["],
    [")", "}", ">", "]"],
    ["()", "{}", "<>", "[]"],
    ["’", "“", "”", "„", "\"", "`", "'"],
    ["\"\"\"", "'''", "```"],
    ["=", "≒", "≠", "≡"],
    [":", ";"],
    ["!", "❗️", "❣️", "‼︎", "⁉︎", "❕", "‼️", "⁉️", "¡"],
    ["?", "❓", "⁉︎", "⁇", "❔", "⁉️", "¿"],
    ["〒", "〠", "℡", "☎︎"],
    ["々", "ヾ", "ヽ", "ゝ", "ゞ", "〃", "仝", "〻"],
    ["〆", "〼", "ゟ", "ヿ"],
    ["♂", "♀", "⚢", "⚣", "⚤", "⚥", "⚦", "⚧", "⚨", "⚩", "⚪︎", "⚲"],
    ["→", "↑", "←", "↓", "↙︎", "↖︎", "↘︎", "↗︎", "↔︎", "↕︎", "↪︎", "↩︎", "⇆"],
    ["♯", "♭", "♪", "♮", "♫", "♬", "♩", "𝄞", "𝄞"],
    ["√", "∛", "∜"]
  ]

  private static let symbolLookup: [String: [String]] = {
    var map: [String: [String]] = [:]
    for group in symbolGroups {
      for symbol in group {
        map[symbol, default: []].append(contentsOf: group)
      }
    }
    return map.mapValues { list in
      var seen = Set<String>()
      var result: [String] = []
      for item in list {
        if seen.insert(item).inserted {
          result.append(item)
        }
      }
      return result
    }
  }()
}
