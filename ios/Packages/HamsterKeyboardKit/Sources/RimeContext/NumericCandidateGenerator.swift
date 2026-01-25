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
    if !literal.allSatisfy({ $0.isNumber && $0.isASCII }) {
      return [literal]
    }

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

