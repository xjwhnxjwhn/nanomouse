//
//  SystemTextReplacementManager.swift
//
//  Created by Nanomouse on 2026/1/6.
//

import OSLog
import UIKit

/// 系统文本替换管理器
/// 负责读取和应用 iOS 系统的「文本替换」设置
public class SystemTextReplacementManager {
  
  /// 缓存的 lexicon 条目（userInput -> [documentText]）
  /// 支持一个 key 对应多个 value
  private var replacements: [String: [String]] = [:]
  
  /// 是否已加载
  private(set) var isLoaded = false
  
  public init() {}
  
  /// 加载系统 lexicon
  /// - Parameters:
  ///   - controller: UIInputViewController 实例
  ///   - completion: 加载完成回调
  public func loadLexicon(from controller: UIInputViewController, completion: @escaping () -> Void = {}) {
    Logger.statistics.info("SystemTextReplacement: loading lexicon...")
    controller.requestSupplementaryLexicon { [weak self] lexicon in
      var dict: [String: [String]] = [:]
      for entry in lexicon.entries {
        // 只存储用户定义的文本替换（过滤掉联系人名字等）
        // 用户定义的替换 userInput 和 documentText 会不同
        if entry.userInput != entry.documentText {
          if dict[entry.userInput] == nil {
            dict[entry.userInput] = []
          }
          dict[entry.userInput]?.append(entry.documentText)
          Logger.statistics.info("SystemTextReplacement: loaded entry '\(entry.userInput, privacy: .public)' -> '\(entry.documentText, privacy: .public)'")
        }
      }
      self?.replacements = dict
      self?.isLoaded = true
      Logger.statistics.info("SystemTextReplacement: loaded \(dict.count) keys")
      completion()
    }
  }
  
  /// 检查是否有匹配的替换
  /// - Parameter input: 用户输入的文本
  /// - Returns: 替换后的文本数组，如果没有匹配则返回 nil
  public func replacements(for input: String) -> [String]? {
    return replacements[input]
  }
  
  /// 检查是否有匹配的替换（返回第一个）
  /// - Parameter input: 用户输入的文本
  /// - Returns: 替换后的文本，如果没有匹配则返回 nil
  public func replacement(for input: String) -> String? {
    return replacements[input]?.first
  }
  
  /// 尝试执行文本替换
  /// - Parameter proxy: 文本文档代理
  /// - Returns: 如果执行了替换返回 true
  public func tryReplace(in proxy: UITextDocumentProxy) -> Bool {
    Logger.statistics.info("SystemTextReplacement: tryReplace called, isLoaded=\(self.isLoaded), count=\(self.replacements.count)")
    
    guard isLoaded else {
      Logger.statistics.info("SystemTextReplacement: not loaded yet")
      return false
    }
    
    // 获取光标前的文本
    guard let beforeInput = proxy.documentContextBeforeInput,
          !beforeInput.isEmpty else {
      Logger.statistics.info("SystemTextReplacement: no text before cursor")
      return false
    }
    
    Logger.statistics.info("SystemTextReplacement: beforeInput='\(beforeInput, privacy: .public)'")
    
    // 提取最后一个单词
    let lastWord = extractLastWord(from: beforeInput)
    Logger.statistics.info("SystemTextReplacement: lastWord='\(lastWord, privacy: .public)'")
    
    guard !lastWord.isEmpty else { return false }
    
    // 查找替换（使用第一个匹配）
    guard let replacement = replacements[lastWord]?.first else {
      Logger.statistics.info("SystemTextReplacement: no replacement found for '\(lastWord, privacy: .public)'")
      return false
    }
    
    Logger.statistics.info("SystemTextReplacement: found replacement '\(replacement, privacy: .public)' for '\(lastWord, privacy: .public)'")
    
    // 执行替换：删除原词，插入替换文本
    for _ in 0..<lastWord.count {
      proxy.deleteBackward()
    }
    proxy.insertText(replacement)
    
    Logger.statistics.info("SystemTextReplacement: replacement done")
    return true
  }
  
  /// 从文本中提取最后一个单词
  /// - Parameter text: 输入文本
  /// - Returns: 最后一个单词
  private func extractLastWord(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return "" }
    
    var wordStartIndex = trimmed.endIndex
    for index in trimmed.indices.reversed() {
      let char = trimmed[index]
      if char.isWhitespace || char.isNewline {
        wordStartIndex = trimmed.index(after: index)
        break
      }
      if index == trimmed.startIndex {
        wordStartIndex = index
      }
    }
    
    return String(trimmed[wordStartIndex...])
  }
  
  /// 清空缓存
  public func clear() {
    replacements.removeAll()
    isLoaded = false
  }
  
  /// 获取当前加载的替换条目数量
  public var count: Int {
    return replacements.count
  }
  
  /// 获取当前输入匹配的所有文本替换建议
  /// - Parameter input: 当前用户输入的文本（光标前的最后一个单词）
  /// - Returns: 如果匹配返回 [(shortcut, replacement)]，否则返回空数组
  public func getAllSuggestions(for input: String) -> [(shortcut: String, replacement: String)] {
    guard isLoaded, !input.isEmpty else { return [] }
    guard let values = replacements[input] else { return [] }
    return values.map { (input, $0) }
  }
}
