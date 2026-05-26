//
//  RimeSchema.swift
//
//
//  Created by morse on 2023/6/30.
//

import Foundation

/// RIME 输入方案
public struct RimeSchema: Identifiable, Equatable, Hashable, Comparable, Codable {
  public var id: String
  public var schemaId: String
  public var schemaName: String

  public init(schemaId: String, schemaName: String) {
    self.id = schemaId
    self.schemaId = schemaId
    self.schemaName = schemaName
  }
}

public extension RimeSchema {
  static func < (lhs: RimeSchema, rhs: RimeSchema) -> Bool {
    lhs.schemaId <= rhs.schemaId
  }

  static func == (lhs: RimeSchema, rhs: RimeSchema) -> Bool {
    return lhs.schemaId == rhs.schemaId
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(schemaId)
  }

  var isJapaneseSchema: Bool {
    let id = schemaId.lowercased()
    let name = schemaName.lowercased()
    let keywords = [
      "japanese",
      "nihongo",
      "romaji",
      "kana",
      "hifumi",
      "jaroomaji",
      "jaromaji",
      "azookey",
    ]
    return keywords.contains(where: { id.contains($0) || name.contains($0) })
  }

  var isBopomofoSchema: Bool {
    let id = schemaId.lowercased()
    return id == "bopomofo"
      || id == "bopomofo_tw"
      || id == "bopomofo_express"
  }

  /// 判断是否是罗马字日语方案（优先使用26键键盘）
  var isRomajiJapaneseSchema: Bool {
    guard isJapaneseSchema else { return false }
    let id = schemaId.lowercased()
    let name = schemaName.lowercased()
    let romajiKeywords = ["romaji", "jaroomaji", "jaromaji", "ローマ字"]
    return romajiKeywords.contains(where: { id.contains($0) || name.contains($0) })
  }

  /// 判断是否是中文九键（T9）方案。
  ///
  /// 说明：
  /// 仅用于布局与方案联动时的启发式匹配，避免把中文九宫格布局错误绑定到普通26键方案。
  var isChineseNineGridSchema: Bool {
    guard !isJapaneseSchema else { return false }

    let id = schemaId.lowercased()
    let name = schemaName.lowercased()
    let englishKeywords = [
      "t9",
      "9key",
      "ninekey",
      "nine_grid",
      "nine-grid",
      "ninegrid",
      "jiugong",
      "jiugongge",
      "jiu_gong",
      "jiu_gong_ge",
    ]
    if englishKeywords.contains(where: { id.contains($0) || name.contains($0) }) {
      return true
    }

    let chineseKeywords = ["九键", "九宮", "九宫", "九宮格", "九宫格", "9键"]
    if chineseKeywords.contains(where: { schemaId.contains($0) || schemaName.contains($0) }) {
      return true
    }

    if id.hasSuffix("_9") || id.hasSuffix("-9") || id.contains("_9_") || id.contains("-9-") {
      return true
    }
    return false
  }
}
