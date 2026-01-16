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

  func reset() {
    composingText = ComposingText()
    lastCandidates = []
    converter?.stopComposition()
  }

  func handleInput(_ text: String, inputStyle: InputStyle) -> [CandidateSuggestion] {
    composingText.insertAtCursorPosition(text, inputStyle: inputStyle)
    guard let converter = ensureConverter() else { return [] }
    let result = converter.requestCandidates(composingText, options: makeOptions())
    lastCandidates = result.mainResults
    return suggestions(from: lastCandidates)
  }

  func deleteBackward() -> [CandidateSuggestion] {
    composingText.deleteBackwardFromCursorPosition(count: 1)
    if composingText.convertTarget.isEmpty {
      lastCandidates = []
      ensureConverter()?.stopComposition()
      return []
    }
    guard let converter = ensureConverter() else { return [] }
    let result = converter.requestCandidates(composingText, options: makeOptions())
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
    converter.setCompletedData(candidate)
    if candidate.isLearningTarget {
      converter.updateLearningData(candidate)
      converter.commitUpdateLearningData()
    }
    converter.stopComposition()
    composingText = ComposingText()
    lastCandidates = []
    return candidate.text
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

    if converter == nil || cachedDictionaryURL != dictionaryURL {
      converter = KanaKanjiConverter(dictionaryURL: dictionaryURL, preloadDictionary: false)
      converter?.setKeyboardLanguage(.ja_JP)
      cachedDictionaryURL = dictionaryURL
    }
    return converter
  }

  private func makeOptions() -> ConvertRequestOptions {
    let memoryDirectoryURL = FileManager.appGroupAzooKeyMemoryDirectoryURL
    let sharedContainerURL = FileManager.appGroupAzooKeyDirectoryURL
    let zenzaiEnabled = UserDefaults.hamster.azooKeyMode == .zenzai
    let weightURL = FileManager.azooKeyZenzaiWeightURL()
    let resolvedZenzaiEnabled = zenzaiEnabled && weightURL != nil

    // 仅当开关与权重同时满足时启用 Zenzai
    if cachedZenzaiEnabled != resolvedZenzaiEnabled || cachedZenzaiWeightURL != weightURL {
      cachedZenzaiEnabled = resolvedZenzaiEnabled
      cachedZenzaiWeightURL = weightURL
    }

    let zenzaiMode: ConvertRequestOptions.ZenzaiMode
    if resolvedZenzaiEnabled, let weightURL {
      zenzaiMode = .on(weight: weightURL, inferenceLimit: 10, requestRichCandidates: false, personalizationMode: nil)
    } else {
      zenzaiMode = .off
    }

    return ConvertRequestOptions(
      N_best: 10,
      needTypoCorrection: nil,
      requireJapanesePrediction: .autoMix,
      requireEnglishPrediction: .disabled,
      keyboardLanguage: .ja_JP,
      englishCandidateInRoman2KanaInput: false,
      fullWidthRomanCandidate: false,
      halfWidthKanaCandidate: false,
      learningType: .inputAndOutput,
      maxMemoryCount: 65536,
      shouldResetMemory: false,
      memoryDirectoryURL: memoryDirectoryURL,
      sharedContainerURL: sharedContainerURL,
      textReplacer: .empty,
      specialCandidateProviders: nil,
      zenzaiMode: zenzaiMode,
      preloadDictionary: false,
      metadata: ConvertRequestOptions.Metadata(versionString: "NanoMouse AzooKey")
    )
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
