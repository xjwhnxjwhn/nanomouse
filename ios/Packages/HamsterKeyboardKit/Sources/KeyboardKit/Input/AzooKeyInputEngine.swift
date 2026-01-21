//
//  AzooKeyInputEngine.swift
//
//
//  Created by Codex on 2026/01/16.
//

import Foundation
import HamsterKit
import KanaKanjiConverterModule
import OSLog

final class AzooKeyInputEngine {
  private var converter: KanaKanjiConverter?
  private var composingText = ComposingText()
  private var lastCandidates: [Candidate] = []
  private var cachedDictionaryURL: URL?
  private var cachedZenzaiWeightURL: URL?
  private var cachedZenzaiEnabled = false
  private var lastInputStyle: InputStyle = .direct
  private var hasPrewarmed = false
  private var prewarmInProgress = false
  private let converterLock = NSLock()
  private let conversionLock = NSLock()
  private let prewarmQueue = DispatchQueue(label: "com.XiangqingZHANG.nanomouse.azookey.prewarm", qos: .userInitiated)

  var isComposing: Bool {
    !composingText.convertTarget.isEmpty || !composingText.input.isEmpty
  }

  var currentDisplayText: String {
    let preedit = composingText.convertTarget
    if !preedit.isEmpty {
      return preedit
    }
    return composingText.input.compactMap { element in
      switch element.piece {
      case .character(let value):
        return value
      case .key(let intention, let input, _):
        return intention ?? input
      case .compositionSeparator:
        return nil
      }
    }
    .map(String.init)
    .joined()
  }

  var requiresLeftSideContext: Bool {
    let zenzaiEnabled = UserDefaults.hamster.azooKeyMode == .zenzai
    return zenzaiEnabled && FileManager.azooKeyZenzaiWeightURL() != nil
  }

  func reset() {
    composingText = ComposingText()
    lastCandidates = []
    conversionLock.lock()
    converter?.stopComposition()
    conversionLock.unlock()
  }

  func prewarmIfNeeded() {
    converterLock.lock()
    if hasPrewarmed || prewarmInProgress {
      converterLock.unlock()
      return
    }
    prewarmInProgress = true
    converterLock.unlock()

    prewarmQueue.async { [weak self] in
      guard let self else { return }
      defer {
        self.converterLock.lock()
        self.prewarmInProgress = false
        self.converterLock.unlock()
      }
      guard FileManager.isAzooKeyDictionaryAvailable() else {
        return
      }
      let zenzaiEnabled = UserDefaults.hamster.azooKeyMode == .zenzai && FileManager.azooKeyZenzaiWeightURL() != nil
      if zenzaiEnabled {
        let dictionaryURL = FileManager.appGroupAzooKeyDictionaryDirectoryURL
        _ = try? Data(contentsOf: dictionaryURL.appendingPathComponent("mm.binary"), options: [.uncached])
        _ = try? Data(contentsOf: dictionaryURL.appendingPathComponent("louds/charID.chid"), options: [.uncached])
        self.converterLock.lock()
        self.hasPrewarmed = true
        self.converterLock.unlock()
        return
      }
      var warmupText = ComposingText()
      // 触发罗马音输入路径（真实首键更接近），而不是直入日文字符。
      warmupText.insertAtCursorPosition("a", inputStyle: .roman2kana)
      let options = self.makeOptions(inputStyle: .roman2kana, leftSideContext: nil)
      guard let converter = self.ensureConverter() else { return }
      guard self.conversionLock.try() else { return }
      converter.setKeyboardLanguage(.ja_JP)
      _ = converter.requestCandidates(warmupText, options: options)
      converter.stopComposition()
      self.conversionLock.unlock()
      self.converterLock.lock()
      self.hasPrewarmed = true
      self.converterLock.unlock()
    }
  }

  func handleInput(_ text: String, inputStyle: InputStyle, leftSideContext: String? = nil) -> [CandidateSuggestion] {
    composingText.insertAtCursorPosition(text, inputStyle: inputStyle)
    guard let converter = ensureConverter() else { return [] }
    lastInputStyle = inputStyle
    let inputData = composingText.prefixToCursorPosition()
    conversionLock.lock()
    let result = converter.requestCandidates(inputData, options: makeOptions(inputStyle: inputStyle, leftSideContext: leftSideContext))
    conversionLock.unlock()
    lastCandidates = result.mainResults
    return suggestions(from: lastCandidates)
  }

  func deleteBackward(leftSideContext: String? = nil) -> [CandidateSuggestion] {
    composingText.deleteBackwardFromCursorPosition(count: 1)
    if composingText.convertTarget.isEmpty {
      lastCandidates = []
      conversionLock.lock()
      converter?.stopComposition()
      conversionLock.unlock()
      return []
    }
    guard let converter = ensureConverter() else { return [] }
    let inputData = composingText.prefixToCursorPosition()
    conversionLock.lock()
    let result = converter.requestCandidates(inputData, options: makeOptions(inputStyle: lastInputStyle, leftSideContext: leftSideContext))
    conversionLock.unlock()
    lastCandidates = result.mainResults
    return suggestions(from: lastCandidates)
  }

  func candidate(at index: Int) -> Candidate? {
    guard index >= 0, index < lastCandidates.count else { return nil }
    return lastCandidates[index]
  }

  func currentSuggestions() -> [CandidateSuggestion] {
    suggestions(from: lastCandidates)
  }

  func commitCandidate(at index: Int) -> String? {
    guard var candidate = candidate(at: index), let converter = ensureConverter() else { return nil }
    candidate.parseTemplate()
    conversionLock.lock()
    converter.setCompletedData(candidate)
    if candidate.isLearningTarget {
      converter.updateLearningData(candidate)
      converter.commitUpdateLearningData()
    }
    converter.stopComposition()
    let committedText = candidate.text
    conversionLock.unlock()
    composingText = ComposingText()
    lastCandidates = []
    return committedText
  }

  private func ensureConverter() -> KanaKanjiConverter? {
    let dictionaryURL = FileManager.appGroupAzooKeyDictionaryDirectoryURL
    guard FileManager.isAzooKeyDictionaryAvailable() else {
      Logger.statistics.info("AzooKey dictionary unavailable, skip init")
      return nil
    }

    try? FileManager.createDirectory(override: false, dst: FileManager.appGroupAzooKeyDirectoryURL)
    try? FileManager.createDirectory(override: false, dst: FileManager.appGroupAzooKeyMemoryDirectoryURL)
    try? FileManager.createDirectory(override: false, dst: FileManager.appGroupAzooKeyZenzaiDirectoryURL)

    converterLock.lock()
    let existingConverter = converter
    let existingDictionaryURL = cachedDictionaryURL
    converterLock.unlock()

    if let existingConverter, existingDictionaryURL == dictionaryURL {
      return existingConverter
    }

    let newConverter = KanaKanjiConverter(dictionaryURL: dictionaryURL, preloadDictionary: false)
    newConverter.setKeyboardLanguage(.ja_JP)

    converterLock.lock()
    if converter == nil || cachedDictionaryURL != dictionaryURL {
      converter = newConverter
      cachedDictionaryURL = dictionaryURL
    }
    let result = converter
    converterLock.unlock()
    return result
  }

  private func makeOptions(inputStyle: InputStyle, leftSideContext: String?) -> ConvertRequestOptions {
    let memoryDirectoryURL = FileManager.appGroupAzooKeyMemoryDirectoryURL
    let sharedContainerURL = FileManager.appGroupAzooKeyDirectoryURL
    let zenzaiEnabled = UserDefaults.hamster.azooKeyMode == .zenzai
    let weightURL = FileManager.azooKeyZenzaiWeightURL()
    let resolvedZenzaiEnabled = zenzaiEnabled && weightURL != nil

    let requireJapanesePrediction: Bool
    let requireEnglishPrediction: Bool
    switch inputStyle {
    case .direct:
      requireJapanesePrediction = true
      requireEnglishPrediction = true
    case .roman2kana:
      requireJapanesePrediction = true
      requireEnglishPrediction = false
    case .mapped:
      requireJapanesePrediction = true
      requireEnglishPrediction = false
    }

    // 仅当开关与权重同时满足时启用 Zenzai
    if cachedZenzaiEnabled != resolvedZenzaiEnabled || cachedZenzaiWeightURL != weightURL {
      cachedZenzaiEnabled = resolvedZenzaiEnabled
      cachedZenzaiWeightURL = weightURL
    }

    let zenzaiMode: ConvertRequestOptions.ZenzaiMode
    if resolvedZenzaiEnabled, let weightURL {
      let inferenceLimit = inferenceLimitForWeightURL(weightURL)
      zenzaiMode = .on(
        weight: weightURL,
        inferenceLimit: inferenceLimit,
        requestRichCandidates: false,
        personalizationMode: nil,
        versionDependentMode: .v3(.init(leftSideContext: leftSideContext, maxLeftSideContextLength: 20))
      )
    } else {
      zenzaiMode = .off
    }

    var providers = KanaKanjiConverter.defaultSpecialCandidateProviders
    if UserDefaults.hamster.azooKeyTypographyLetter {
      providers.append(.typography)
    }

    return ConvertRequestOptions(
      N_best: 10,
      needTypoCorrection: nil,
      requireJapanesePrediction: requireJapanesePrediction,
      requireEnglishPrediction: requireEnglishPrediction,
      keyboardLanguage: .ja_JP,
      englishCandidateInRoman2KanaInput: UserDefaults.hamster.azooKeyEnglishCandidate,
      fullWidthRomanCandidate: true,
      halfWidthKanaCandidate: true,
      learningType: .inputAndOutput,
      maxMemoryCount: 65536,
      shouldResetMemory: false,
      memoryDirectoryURL: memoryDirectoryURL,
      sharedContainerURL: sharedContainerURL,
      textReplacer: .empty,
      specialCandidateProviders: providers,
      zenzaiMode: zenzaiMode,
      preloadDictionary: false,
      metadata: ConvertRequestOptions.Metadata(versionString: "NanoMouse AzooKey")
    )
  }

  private func inferenceLimitForWeightURL(_ url: URL) -> Int {
    let name = url.lastPathComponent.lowercased()
    if name.contains("xsmall") {
      return 5
    }
    if name.contains("small") {
      return 8
    }
    return 5
  }

  private func suggestions(from candidates: [Candidate]) -> [CandidateSuggestion] {
    candidates.enumerated().map { index, item in
      let text = Candidate.parseTemplate(item.text)
      return CandidateSuggestion(
        index: index,
        label: "\(index + 1)",
        text: text,
        title: text,
        isAutocomplete: index == 0
      )
    }
  }
}
