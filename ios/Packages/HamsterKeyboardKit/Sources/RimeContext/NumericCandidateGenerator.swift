//
//  NumericCandidateGenerator.swift
//  HamsterKeyboardKit
//
//  Create numeric candidates aligned with AzooKey behavior.
//

import Foundation

enum NumericCandidateGenerator {
  private static let japaneseNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .spellOut
    formatter.locale = Locale(identifier: "ja-JP")
    return formatter
  }()

  static func candidateTexts(for literal: String) -> [String] {
    guard !literal.isEmpty else { return [] }
    if literal.allSatisfy({ $0.isNumber && $0.isASCII }) {
      return candidateTextsForDigits(literal)
    }

    if let split = splitNumericSuffix(literal),
       let normalized = normalizedAsciiDigits(split.digits)
    {
      let base = candidateTextsForDigits(normalized)
      if split.suffix.isEmpty { return base }
      return base.map { $0 + split.suffix }
    }

    return [literal]
  }

  private static func candidateTextsForDigits(_ literal: String) -> [String] {
    var results: [String] = []
    var seen = Set<String>()

    func appendUnique(_ text: String) {
      guard !text.isEmpty else { return }
      if seen.insert(text).inserted {
        results.append(text)
      }
    }

    if let comma = commaSeparatedNumber(literal) {
      appendUnique(comma)
    }

    appendUnique(literal)

    if let fullwidth = fullwidthString(literal), fullwidth != literal {
      appendUnique(fullwidth)
    }

    for variant in typographicalDigits(literal) {
      appendUnique(variant)
    }

    if let kansuji = japaneseNumber(literal) {
      appendUnique(kansuji)
    }

    return results
  }

  private static func splitNumericSuffix(_ literal: String) -> (digits: String, suffix: String)? {
    var digits = ""
    var suffix = ""
    var sawDigit = false
    var inSuffix = false

    for ch in literal {
      if !inSuffix {
        if let value = ch.wholeNumberValue, (0...9).contains(value) {
          digits.append(String(value))
          sawDigit = true
          continue
        }
        if isNumericSeparator(ch) {
          digits.append(ch)
          continue
        }
        if isPunctuationOrSymbol(ch) {
          if !sawDigit { return nil }
          inSuffix = true
          suffix.append(ch)
          continue
        }
        return nil
      } else {
        if isPunctuationOrSymbol(ch) {
          suffix.append(ch)
          continue
        }
        return nil
      }
    }

    return sawDigit ? (digits: digits, suffix: suffix) : nil
  }

  private static func normalizedAsciiDigits(_ text: String) -> String? {
    var result = ""
    var sawDigit = false
    for ch in text {
      if let value = ch.wholeNumberValue, (0...9).contains(value) {
        result.append(String(value))
        sawDigit = true
        continue
      }
      if isNumericSeparator(ch) { continue }
      return nil
    }
    return sawDigit ? result : nil
  }

  private static func isPunctuationOrSymbol(_ ch: Character) -> Bool {
    guard let scalar = ch.unicodeScalars.first else { return false }
    if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
    if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
      return false
    }
    return CharacterSet.punctuationCharacters.contains(scalar)
      || CharacterSet.symbols.contains(scalar)
  }

  private static func isNumericSeparator(_ ch: Character) -> Bool {
    return ch == "," || ch == "." || ch == "，" || ch == "．"
  }

  private static func commaSeparatedNumber(_ literal: String) -> String? {
    var text = literal
    var negative = false
    if text.first == "-" {
      negative = true
      text.removeFirst()
    }
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2,
          parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isNumber && $0.isASCII }) })
    else {
      return nil
    }
    let integerPart = parts[0]
    guard integerPart.count > 3 else { return nil }

    let reversed = Array(integerPart.reversed())
    var formatted = ""
    for (index, ch) in reversed.enumerated() {
      if index > 0 && index % 3 == 0 {
        formatted.append(",")
      }
      formatted.append(ch)
    }
    let integerString = String(formatted.reversed())
    var result = (negative ? "-" : "") + integerString
    if parts.count == 2 {
      result += "." + parts[1]
    }
    return result
  }

  private static func japaneseNumber(_ literal: String) -> String? {
    guard let number = Int(literal) else { return nil }
    if Double(number) > 1e12 || Double(number) < -1e12 { return nil }
    return japaneseNumberFormatter.string(from: NSNumber(value: number))
  }

  private static func fullwidthString(_ literal: String) -> String? {
    literal.applyingTransform(.fullwidthToHalfwidth, reverse: true)
  }

  private static func typographicalDigits(_ literal: String) -> [String] {
    guard literal.allSatisfy({ $0.isNumber && $0.isASCII }) else { return [] }
    let scalars = literal.unicodeScalars

    func mapDigits(offset: UInt32) -> String {
      scalars.map { scalar in
        guard scalar.value >= 0x30, scalar.value <= 0x39 else { return String(scalar) }
        let mapped = UnicodeScalar(scalar.value + offset)!
        return String(mapped)
      }.joined()
    }

    // Order mirrors AzooKey typographicalCandidates for digits.
    let bold = mapDigits(offset: 120734)
    let doubleStruck = mapDigits(offset: 120744)
    let sansSerif = mapDigits(offset: 120754)
    let sansSerifBold = mapDigits(offset: 120764)
    let monospace = mapDigits(offset: 120774)

    return [bold, doubleStruck, sansSerif, sansSerifBold, monospace]
  }
}
