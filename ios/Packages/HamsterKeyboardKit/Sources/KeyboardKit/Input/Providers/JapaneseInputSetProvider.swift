//
//  JapaneseInputSetProvider.swift
//  KeyboardKit
//
//  Created by Hamster on 2026-01-09.
//

import Foundation

/**
 Japanese input set provider (romaji keyboard).
 */
open class JapaneseInputSetProvider: InputSetProvider {
  /// The input set to use for alphabetic keyboards.
  public var alphabeticInputSet: AlphabeticInputSet

  /// The input set to use for numeric keyboards.
  public var numericInputSet: NumericInputSet

  /// The input set to use for symbolic keyboards.
  public var symbolicInputSet: SymbolicInputSet

  public init(
    alphabetic: AlphabeticInputSet = .japanese,
    numericCurrency: String = "$",
    symbolicCurrency: String = "£"
  ) {
    self.alphabeticInputSet = alphabetic
    // Reuse English numeric/symbolic sets for now.
    self.numericInputSet = .english(currency: numericCurrency)
    self.symbolicInputSet = .english(currency: symbolicCurrency)
  }
}

public extension AlphabeticInputSet {
  /**
   A standard Japanese romaji input set.
   */
  static let japanese = AlphabeticInputSet(rows: [
    .init(chars: "qwertyuiop"),
    .init(chars: "asdfghjklー"),
    .init(phone: "zxcvbnm", pad: "zxcvbnm,.")
  ])
}
