//
//  CandidateSuggestion.swift
//
//
//  Created by morse on 2023/7/4.
//

import Foundation

/// 键盘UI候选栏显示文字
public struct CandidateSuggestion: Identifiable, Equatable, Hashable {
  public var id = UUID()

  /// 候选文字索引
  public var index: Int

  /// 索引 label
  public var label: String

  /// 应该发送至 documentProxy 的文本。
  public var text: String

  /// UI呈现的文本
  public var title: String

  /// 可选的副标题
  public var subtitle: String?

  /// 这是否是一个自动完成的建议。
  /// 这些建议在iOS系统键盘中呈现时，通常显示为白色的圆形方块。
  public var isAutocomplete: Bool

  /// 这是否是一个未知的建议。
  /// 这些建议在iOS系统键盘中呈现时，通常被引号所包围。
  public var isUnknown: Bool

  /// 一个可选的字典，可以包含额外的信息。
  public var additionalInfo: [String: Any]

  public init(
    index: Int,
    label: String,
    text: String,
    title: String? = nil,
    isAutocomplete: Bool = false,
    isUnknown: Bool = false,
    subtitle: String? = nil,
    additionalInfo: [String: Any] = [:]
  ) {
    self.index = index
    self.label = label
    self.text = text
    self.title = title ?? text
    self.isAutocomplete = isAutocomplete
    self.isUnknown = isUnknown
    self.subtitle = subtitle
    self.additionalInfo = additionalInfo
  }
}

public extension CandidateSuggestion {
  static func == (lhs: CandidateSuggestion, rhs: CandidateSuggestion) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

public extension CandidateSuggestion {
  var firstRenderableText: String {
    for value in [title, text, subtitle ?? ""] {
      let renderable = value.hamsterRenderableCandidateText
      if !renderable.isEmpty {
        return renderable
      }
    }
    return ""
  }

  func normalizedForPredictionDisplay() -> CandidateSuggestion {
    var candidate = self
    candidate.isAutocomplete = false
    if candidate.title.hamsterRenderableCandidateText.isEmpty {
      let renderable = candidate.firstRenderableText
      if !renderable.isEmpty {
        candidate.title = renderable
      }
    }
    if candidate.text.hamsterRenderableCandidateText.isEmpty,
       !candidate.title.hamsterRenderableCandidateText.isEmpty
    {
      candidate.text = candidate.title
    }
    return candidate
  }
}

public extension String {
  var hamsterRenderableCandidateText: String {
    String(unicodeScalars.filter { scalar in
      let value = scalar.value
      if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
      if CharacterSet.controlCharacters.contains(scalar) { return false }
      if (0x200B...0x200F).contains(value) { return false }
      if (0x202A...0x202E).contains(value) { return false }
      if (0x2060...0x206F).contains(value) { return false }
      if value == 0xFEFF || value == 0xFFFC { return false }
      if scalar.properties.generalCategory == .format { return false }
      return true
    })
  }
}
