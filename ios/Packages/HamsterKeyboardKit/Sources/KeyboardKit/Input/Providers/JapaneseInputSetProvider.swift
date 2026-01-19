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
    alphabetic: AlphabeticInputSet = .japanese
  ) {
    self.alphabeticInputSet = alphabetic
    self.numericInputSet = .japanese
    self.symbolicInputSet = .japanese
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

public extension NumericInputSet {
  /// 日语键盘数字（参考 AzooKey）
  static let japanese = NumericInputSet(rows: [
    .init(chars: "1234567890"),
    .init(phone: "-/:@()「」¥&", pad: "-/:@()「」¥&"),
    .init(phone: "。、？！・~", pad: "。、？！・~")
  ])
}

public extension SymbolicInputSet {
  /// 日语键盘符号（参考 AzooKey）
  static let japanese = SymbolicInputSet(rows: [
    .init(phone: "[]{}#%^*+=", pad: "[]{}#%^*+="),
    .init(phone: "_\\;|<>\"'$€", pad: "_\\;|<>\"'$€"),
    .init(phone: ".,?!…`", pad: ".,?!…`")
  ])
}
