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
  private let conversionStateLock = NSLock()
  private var conversionGeneration: Int = 0
  private let conversionQueue = DispatchQueue(label: "com.XiangqingZHANG.nanomouse.azookey.convert", qos: .userInitiated)
  private let prewarmQueue = DispatchQueue(label: "com.XiangqingZHANG.nanomouse.azookey.prewarm", qos: .userInitiated)
  private let zenzaiPrewarmQueue = DispatchQueue(label: "com.XiangqingZHANG.nanomouse.azookey.zenzai.prewarm", qos: .utility)
  private let zenzaiLock = NSLock()
  private var zenzaiReady = false
  private var zenzaiPrewarmInProgress = false
  private let zenzaiMinInputLength = 4

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

  var currentRawInputText: String {
    composingText.input.compactMap { element in
      switch element.piece {
      case .character(let value):
        return String(value)
      case .key(_, let input, _):
        return String(input)
      case .compositionSeparator:
        return nil
      }
    }
    .joined()
  }

  var requiresLeftSideContext: Bool {
    let zenzaiEnabled = UserDefaults.hamster.azooKeyMode == .zenzai
    guard zenzaiEnabled, FileManager.azooKeyZenzaiWeightURL() != nil else { return false }
    zenzaiLock.lock()
    let ready = zenzaiReady
    zenzaiLock.unlock()
    return ready
  }

  func reset() {
    composingText = ComposingText()
    lastCandidates = []
    invalidatePendingConversions()
    conversionLock.lock()
    converter?.stopComposition()
    conversionLock.unlock()
  }

  func releaseResources() {
    invalidatePendingConversions()
    conversionLock.lock()
    converter?.stopComposition()
    conversionLock.unlock()
    converterLock.lock()
    converter = nil
    cachedDictionaryURL = nil
    cachedZenzaiWeightURL = nil
    cachedZenzaiEnabled = false
    hasPrewarmed = false
    prewarmInProgress = false
    converterLock.unlock()
    zenzaiLock.lock()
    zenzaiReady = false
    zenzaiPrewarmInProgress = false
    zenzaiLock.unlock()
    composingText = ComposingText()
    lastCandidates = []
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
        self.prewarmZenzaiIfNeeded()
        return
      }
      var warmupText = ComposingText()
      // 触发罗马音输入路径（真实首键更接近），而不是直入日文字符。
      warmupText.insertAtCursorPosition("a", inputStyle: .roman2kana)
      let (options, _) = self.makeOptions(inputStyle: .roman2kana, leftSideContext: nil, forceZenzai: false)
      guard let converter = self.ensureConverter() else { return }
      guard self.conversionLock.try() else { return }
      converter.setKeyboardLanguage(.ja_JP)
      _ = converter.requestCandidates(warmupText, options: options)
      converter.stopComposition()
      self.conversionLock.unlock()
      self.converterLock.lock()
      self.hasPrewarmed = true
      self.converterLock.unlock()
      if self.isZenzaiEnabledAndAvailable() {
        self.prewarmZenzaiIfNeeded()
      }
    }
  }

  func handleInput(_ text: String, inputStyle: InputStyle, leftSideContext: String? = nil) -> [CandidateSuggestion] {
    composingText.insertAtCursorPosition(text, inputStyle: inputStyle)
    guard let converter = ensureConverter() else { return [] }
    lastInputStyle = inputStyle
    let inputData = composingText.prefixToCursorPosition()
    let generation = nextConversionGeneration()
    if shouldConvertAsync() {
      let snapshot = inputData
      conversionQueue.async { [weak self] in
        guard let self else { return }
        guard let converter = self.ensureConverter() else { return }
        guard self.conversionLock.try() else { return }
        defer { self.conversionLock.unlock() }
        let (options, usedZenzai) = self.makeOptions(inputStyle: inputStyle, leftSideContext: leftSideContext)
        let result = converter.requestCandidates(snapshot, options: options)
        let candidates = result.mainResults
        if candidates.isEmpty, usedZenzai, !self.lastCandidates.isEmpty {
          return
        }
        self.lastCandidates = candidates
        guard self.isLatestConversion(generation) else { return }
        DispatchQueue.main.async {
          self.onCandidatesUpdated?(self.suggestions(from: candidates))
        }
      }
      return suggestions(from: lastCandidates)
    }
    guard conversionLock.try() else {
      return suggestions(from: lastCandidates)
    }
    defer { conversionLock.unlock() }
    let (options, usedZenzai) = makeOptions(inputStyle: inputStyle, leftSideContext: leftSideContext)
    let result = converter.requestCandidates(inputData, options: options)
    let candidates = result.mainResults
    if candidates.isEmpty, usedZenzai, !lastCandidates.isEmpty {
      return suggestions(from: lastCandidates)
    }
    lastCandidates = candidates
    return suggestions(from: lastCandidates)
  }

  func deleteBackward(leftSideContext: String? = nil) -> [CandidateSuggestion] {
    composingText.deleteBackwardFromCursorPosition(count: 1)
    if composingText.convertTarget.isEmpty {
      lastCandidates = []
      invalidatePendingConversions()
      guard conversionLock.try() else { return [] }
      defer { conversionLock.unlock() }
      converter?.stopComposition()
      return []
    }
    guard let converter = ensureConverter() else { return [] }
    let inputData = composingText.prefixToCursorPosition()
    let generation = nextConversionGeneration()
    if shouldConvertAsync() {
      let snapshot = inputData
      conversionQueue.async { [weak self] in
        guard let self else { return }
        guard let converter = self.ensureConverter() else { return }
        guard self.conversionLock.try() else { return }
        defer { self.conversionLock.unlock() }
        let (options, usedZenzai) = self.makeOptions(inputStyle: self.lastInputStyle, leftSideContext: leftSideContext)
        let result = converter.requestCandidates(snapshot, options: options)
        let candidates = result.mainResults
        if candidates.isEmpty, usedZenzai, !self.lastCandidates.isEmpty {
          return
        }
        self.lastCandidates = candidates
        guard self.isLatestConversion(generation) else { return }
        DispatchQueue.main.async {
          self.onCandidatesUpdated?(self.suggestions(from: candidates))
        }
      }
      return suggestions(from: lastCandidates)
    }
    guard conversionLock.try() else {
      return suggestions(from: lastCandidates)
    }
    defer { conversionLock.unlock() }
    let (options, usedZenzai) = makeOptions(inputStyle: lastInputStyle, leftSideContext: leftSideContext)
    let result = converter.requestCandidates(inputData, options: options)
    let candidates = result.mainResults
    if candidates.isEmpty, usedZenzai, !lastCandidates.isEmpty {
      return suggestions(from: lastCandidates)
    }
    lastCandidates = candidates
    return suggestions(from: lastCandidates)
  }

  func candidate(at index: Int) -> Candidate? {
    guard index >= 0, index < lastCandidates.count else { return nil }
    return lastCandidates[index]
  }

  func currentSuggestions() -> [CandidateSuggestion] {
    suggestions(from: lastCandidates)
  }

  var onCandidatesUpdated: (([CandidateSuggestion]) -> Void)?

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
      zenzaiLock.lock()
      zenzaiReady = false
      zenzaiLock.unlock()
    }
    let result = converter
    converterLock.unlock()
    return result
  }

  private func makeOptions(
    inputStyle: InputStyle,
    leftSideContext: String?,
    forceZenzai: Bool = false
  ) -> (ConvertRequestOptions, Bool) {
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
    updateZenzaiStateIfNeeded(resolvedEnabled: resolvedZenzaiEnabled, weightURL: weightURL)
    if resolvedZenzaiEnabled, !forceZenzai {
      prewarmZenzaiIfNeeded()
    }

    let shouldUseZenzai: Bool = {
      guard resolvedZenzaiEnabled, let weightURL else { return false }
      if forceZenzai { return true }
      zenzaiLock.lock()
      let ready = zenzaiReady
      zenzaiLock.unlock()
      guard ready else { return false }
      guard composingText.convertTarget.count >= zenzaiMinInputLength else { return false }
      return true
    }()

    let zenzaiMode: ConvertRequestOptions.ZenzaiMode
    if shouldUseZenzai, let weightURL {
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

    let options = ConvertRequestOptions(
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
    return (options, shouldUseZenzai)
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

  private func isZenzaiEnabledAndAvailable() -> Bool {
    UserDefaults.hamster.azooKeyMode == .zenzai && FileManager.azooKeyZenzaiWeightURL() != nil
  }

  private func updateZenzaiStateIfNeeded(resolvedEnabled: Bool, weightURL: URL?) {
    if cachedZenzaiEnabled != resolvedEnabled || cachedZenzaiWeightURL != weightURL {
      cachedZenzaiEnabled = resolvedEnabled
      cachedZenzaiWeightURL = weightURL
      zenzaiLock.lock()
      zenzaiReady = false
      zenzaiPrewarmInProgress = false
      zenzaiLock.unlock()
    }
  }

  private func prewarmZenzaiIfNeeded() {
    zenzaiLock.lock()
    if zenzaiReady || zenzaiPrewarmInProgress {
      zenzaiLock.unlock()
      return
    }
    zenzaiPrewarmInProgress = true
    zenzaiLock.unlock()

    zenzaiPrewarmQueue.async { [weak self] in
      guard let self else { return }
      self.runZenzaiPrewarm()
    }
  }

  private func runZenzaiPrewarm() {
    guard isZenzaiEnabledAndAvailable() else {
      zenzaiLock.lock()
      zenzaiPrewarmInProgress = false
      zenzaiLock.unlock()
      return
    }
    guard let converter = ensureConverter() else {
      zenzaiLock.lock()
      zenzaiPrewarmInProgress = false
      zenzaiLock.unlock()
      return
    }
    if !composingText.convertTarget.isEmpty || !composingText.input.isEmpty {
      zenzaiPrewarmQueue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        self?.runZenzaiPrewarm()
      }
      return
    }
    if !conversionLock.try() {
      zenzaiPrewarmQueue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        self?.runZenzaiPrewarm()
      }
      return
    }
    var warmupText = ComposingText()
    warmupText.insertAtCursorPosition("a", inputStyle: .roman2kana)
    let (options, _) = makeOptions(inputStyle: .roman2kana, leftSideContext: nil, forceZenzai: true)
    _ = converter.requestCandidates(warmupText, options: options)
    converter.stopComposition()
    conversionLock.unlock()
    zenzaiLock.lock()
    zenzaiReady = true
    zenzaiLock.unlock()
    zenzaiLock.lock()
    zenzaiPrewarmInProgress = false
    zenzaiLock.unlock()
  }

  private func shouldConvertAsync() -> Bool {
    UserDefaults.hamster.azooKeyMode == .zenzai && FileManager.azooKeyZenzaiWeightURL() != nil
  }

  private func nextConversionGeneration() -> Int {
    conversionStateLock.lock()
    conversionGeneration += 1
    let value = conversionGeneration
    conversionStateLock.unlock()
    return value
  }

  private func isLatestConversion(_ generation: Int) -> Bool {
    conversionStateLock.lock()
    let latest = conversionGeneration == generation
    conversionStateLock.unlock()
    return latest
  }

  private func invalidatePendingConversions() {
    conversionStateLock.lock()
    conversionGeneration += 1
    conversionStateLock.unlock()
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
