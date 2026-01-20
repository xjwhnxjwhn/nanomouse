//
//  EnglishInputEngine.swift
//
//
//  Created by Codex on 2026/01/20.
//

import Foundation
import UIKit

/// 英语输入引擎，使用 iOS UITextChecker 提供候选词
final class EnglishInputEngine {
  private let textChecker = UITextChecker()
  private var composingText: String = ""
  private var lastSuggestions: [CandidateSuggestion] = []

  var isComposing: Bool {
    !composingText.isEmpty
  }

  var currentDisplayText: String {
    composingText
  }

  func reset() {
    composingText = ""
    lastSuggestions = []
  }

  func handleInput(_ text: String) -> [CandidateSuggestion] {
    // 只处理字母输入
    if text.rangeOfCharacter(from: CharacterSet.letters.inverted) != nil {
      // 非字母输入，先提交当前词，再处理
      return []
    }
    composingText += text
    return generateSuggestions()
  }

  func deleteBackward() -> [CandidateSuggestion] {
    guard !composingText.isEmpty else { return [] }
    composingText.removeLast()
    if composingText.isEmpty {
      lastSuggestions = []
      return []
    }
    return generateSuggestions()
  }

  func currentSuggestions() -> [CandidateSuggestion] {
    lastSuggestions
  }

  /// 提交指定索引的候选词，返回要插入的文本
  func commitCandidate(at index: Int) -> String? {
    guard index >= 0, index < lastSuggestions.count else { return nil }
    let text = lastSuggestions[index].text
    reset()
    return text
  }

  /// 提交当前输入的原始文本
  func commitRawText() -> String? {
    guard !composingText.isEmpty else { return nil }
    let text = composingText
    reset()
    return text
  }

  private func generateSuggestions() -> [CandidateSuggestion] {
    var suggestions: [CandidateSuggestion] = []
    let word = composingText

    // 第一个候选：用户输入的原始文本
    suggestions.append(CandidateSuggestion(
      index: 0,
      label: "1",
      text: word,
      title: word,
      isAutocomplete: true
    ))

    // 使用 UITextChecker 获取补全建议
    let range = NSRange(location: 0, length: word.utf16.count)
    if let completions = textChecker.completions(forPartialWordRange: range, in: word, language: "en_US") {
      for (i, completion) in completions.prefix(5).enumerated() {
        // 跳过与原始输入相同的补全
        if completion.lowercased() == word.lowercased() { continue }
        suggestions.append(CandidateSuggestion(
          index: suggestions.count,
          label: "\(suggestions.count + 1)",
          text: completion,
          title: completion,
          isAutocomplete: false
        ))
      }
    }

    // 使用 UITextChecker 获取拼写纠正建议
    let misspelledRange = textChecker.rangeOfMisspelledWord(
      in: word,
      range: range,
      startingAt: 0,
      wrap: false,
      language: "en_US"
    )

    if misspelledRange.location != NSNotFound {
      if let guesses = textChecker.guesses(forWordRange: misspelledRange, in: word, language: "en_US") {
        for guess in guesses.prefix(3) {
          // 避免重复
          if suggestions.contains(where: { $0.text.lowercased() == guess.lowercased() }) { continue }
          suggestions.append(CandidateSuggestion(
            index: suggestions.count,
            label: "\(suggestions.count + 1)",
            text: guess,
            title: guess,
            isAutocomplete: false
          ))
        }
      }
    }

    // 限制总数
    lastSuggestions = Array(suggestions.prefix(9))
    return lastSuggestions
  }
}
