//
//  VoiceSpeechRecognizerEngine.swift
//
//
//  Created by Codex on 2026/2/6.
//

import AVFoundation
import Foundation
import Network
import Security
import Speech
#if canImport(WhisperKit)
import WhisperKit
#endif

struct VoiceWhisperModelOption: Hashable {
  let id: String
  let displayName: String
  let sizeText: String
  let summary: String

  static let supported: [VoiceWhisperModelOption] = [
    .init(
      id: "openai_whisper-tiny",
      displayName: "Tiny（极速）",
      sizeText: "约 75MB",
      summary: "速度最快，准确率基础"
    ),
    .init(
      id: "openai_whisper-small",
      displayName: "Small（推荐）",
      sizeText: "约 216MB",
      summary: "中文与中英混说更稳"
    ),
    .init(
      id: "distil-whisper_distil-large-v3_turbo",
      displayName: "Distil Large Turbo（高精度）",
      sizeText: "约 600MB",
      summary: "效果更好，资源占用更高"
    )
  ]
}

struct VoiceWhisperModelStatus: Hashable {
  let option: VoiceWhisperModelOption
  let isDownloaded: Bool
  let isSelected: Bool
}

struct VoiceWhisperModelSelection: Equatable {
  let modelID: String
  let modelFolderURL: URL
}

enum VoiceWhisperModelStoreError: LocalizedError {
  case unsupportedModel
  case whisperEngineUnavailable
  case downloadFailed(message: String)
  case deleteFailed(message: String)

  var errorDescription: String? {
    switch self {
    case .unsupportedModel:
      return "不支持该模型"
    case .whisperEngineUnavailable:
      return "当前构建未启用 WhisperKit"
    case .downloadFailed(let message):
      return "模型下载失败：\(message)"
    case .deleteFailed(let message):
      return "模型删除失败：\(message)"
    }
  }
}

final class VoiceWhisperModelStore {
  static let shared = VoiceWhisperModelStore()

  private enum Constants {
    static let manifestKey = "voice.whisper.manifest.v1"
    static let selectedModelIDKey = "voice.whisper.selected_model_id"
    static let rootDirectoryName = "VoiceInput"
    static let modelsDirectoryName = "WhisperModels"
  }

  private struct StoredModelRecord: Codable, Equatable {
    let modelID: String
    let modelFolderPath: String
    let downloadedAt: TimeInterval
  }

  private let storageQueue = DispatchQueue(label: "nanomouse.voice.whisper.model-store")
  private let fileManager: FileManager
  private let userDefaults: UserDefaults

  init(fileManager: FileManager = .default, userDefaults: UserDefaults = .hamster) {
    self.fileManager = fileManager
    self.userDefaults = userDefaults
  }

  func availableModelStatuses() -> [VoiceWhisperModelStatus] {
    storageQueue.sync {
      var records = compactManifestLocked()
      records.sort { $0.downloadedAt > $1.downloadedAt }
      let selectedID = validSelectedModelIDLocked(records: records)
      let downloadedIDs = Set(records.map(\.modelID))
      return VoiceWhisperModelOption.supported.map { option in
        VoiceWhisperModelStatus(
          option: option,
          isDownloaded: downloadedIDs.contains(option.id),
          isSelected: selectedID == option.id
        )
      }
    }
  }

  func selectedDownloadedModel() -> VoiceWhisperModelSelection? {
    storageQueue.sync {
      let records = compactManifestLocked()
      guard let selectedID = validSelectedModelIDLocked(records: records) else { return nil }
      guard let record = records.first(where: { $0.modelID == selectedID }) else { return nil }
      return VoiceWhisperModelSelection(modelID: selectedID, modelFolderURL: URL(fileURLWithPath: record.modelFolderPath))
    }
  }

  func modelFolderURL(for modelID: String) -> URL? {
    storageQueue.sync {
      let records = compactManifestLocked()
      guard let record = records.first(where: { $0.modelID == modelID }) else { return nil }
      return URL(fileURLWithPath: record.modelFolderPath)
    }
  }

  func setSelectedModel(_ modelID: String?) {
    storageQueue.sync {
      let records = compactManifestLocked()
      if let modelID {
        guard records.contains(where: { $0.modelID == modelID }) else { return }
        userDefaults.set(modelID, forKey: Constants.selectedModelIDKey)
      } else {
        userDefaults.removeObject(forKey: Constants.selectedModelIDKey)
      }
    }
  }

  @discardableResult
  func downloadModel(_ modelID: String) async throws -> URL {
    guard VoiceWhisperModelOption.supported.contains(where: { $0.id == modelID }) else {
      throw VoiceWhisperModelStoreError.unsupportedModel
    }
    #if canImport(WhisperKit)
    let rootURL = modelsRootDirectoryURL
    try ensureModelsDirectory()
    do {
      // 使用固定 variant 标识下载，避免 tiny/tiny.en 这类模糊匹配导致结果不确定。
      let modelFolder = try await WhisperKit.download(variant: modelID, downloadBase: rootURL)
      storageQueue.sync {
        var records = compactManifestLocked()
        if let index = records.firstIndex(where: { $0.modelID == modelID }) {
          records[index] = StoredModelRecord(
            modelID: modelID,
            modelFolderPath: modelFolder.path,
            downloadedAt: Date().timeIntervalSince1970
          )
        } else {
          records.append(
            StoredModelRecord(
              modelID: modelID,
              modelFolderPath: modelFolder.path,
              downloadedAt: Date().timeIntervalSince1970
            )
          )
        }
        saveManifestLocked(records)
        userDefaults.set(modelID, forKey: Constants.selectedModelIDKey)
      }
      return modelFolder
    } catch {
      throw VoiceWhisperModelStoreError.downloadFailed(message: error.localizedDescription)
    }
    #else
    throw VoiceWhisperModelStoreError.whisperEngineUnavailable
    #endif
  }

  func deleteModel(_ modelID: String) throws {
    try storageQueue.sync {
      var records = compactManifestLocked()
      guard let index = records.firstIndex(where: { $0.modelID == modelID }) else { return }
      let record = records[index]
      let modelFolderURL = URL(fileURLWithPath: record.modelFolderPath)
      do {
        if fileManager.fileExists(atPath: modelFolderURL.path) {
          try fileManager.removeItem(at: modelFolderURL)
        }
      } catch {
        throw VoiceWhisperModelStoreError.deleteFailed(message: error.localizedDescription)
      }
      records.remove(at: index)
      saveManifestLocked(records)

      // 如果用户删掉了当前选中模型，则自动切换到最近下载的模型；全部删除时回退 Apple Speech。
      let selectedID = userDefaults.string(forKey: Constants.selectedModelIDKey)
      if selectedID == modelID {
        let fallbackID = records.sorted(by: { $0.downloadedAt > $1.downloadedAt }).first?.modelID
        if let fallbackID {
          userDefaults.set(fallbackID, forKey: Constants.selectedModelIDKey)
        } else {
          userDefaults.removeObject(forKey: Constants.selectedModelIDKey)
        }
      }
    }
  }
}

private extension VoiceWhisperModelStore {
  var modelsRootDirectoryURL: URL {
    FileManager.shareURL
      .appendingPathComponent(Constants.rootDirectoryName, isDirectory: true)
      .appendingPathComponent(Constants.modelsDirectoryName, isDirectory: true)
  }

  func ensureModelsDirectory() throws {
    try fileManager.createDirectory(at: modelsRootDirectoryURL, withIntermediateDirectories: true)
  }

  private func loadManifestLocked() -> [StoredModelRecord] {
    guard let data = userDefaults.data(forKey: Constants.manifestKey) else { return [] }
    let decoder = JSONDecoder()
    return (try? decoder.decode([StoredModelRecord].self, from: data)) ?? []
  }

  private func saveManifestLocked(_ records: [StoredModelRecord]) {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(records) else { return }
    userDefaults.set(data, forKey: Constants.manifestKey)
  }

  private func compactManifestLocked() -> [StoredModelRecord] {
    let records = loadManifestLocked().filter { fileManager.fileExists(atPath: $0.modelFolderPath) }
    saveManifestLocked(records)
    _ = validSelectedModelIDLocked(records: records)
    return records
  }

  @discardableResult
  private func validSelectedModelIDLocked(records: [StoredModelRecord]) -> String? {
    let downloadedIDs = Set(records.map(\.modelID))
    guard !downloadedIDs.isEmpty else {
      userDefaults.removeObject(forKey: Constants.selectedModelIDKey)
      return nil
    }
    if let selectedID = userDefaults.string(forKey: Constants.selectedModelIDKey),
      downloadedIDs.contains(selectedID)
    {
      return selectedID
    }
    let fallbackID = records.sorted(by: { $0.downloadedAt > $1.downloadedAt }).first?.modelID
    if let fallbackID {
      userDefaults.set(fallbackID, forKey: Constants.selectedModelIDKey)
    } else {
      userDefaults.removeObject(forKey: Constants.selectedModelIDKey)
    }
    return fallbackID
  }
}

enum VoicePersonalWordSource: String, Codable, CaseIterable {
  case auto
  case manual
}

struct VoicePersonalWord: Codable, Hashable {
  let word: String
  let source: VoicePersonalWordSource
  let score: Int
  let updatedAt: TimeInterval
}

final class VoicePersonalDictionaryStore {
  static let shared = VoicePersonalDictionaryStore()

  private enum Constants {
    static let storageKey = "voice.personal.dictionary.v1"
    static let maxWordCount = 400
  }

  private struct StoredWordRecord: Codable {
    let word: String
    var source: VoicePersonalWordSource
    var score: Int
    var updatedAt: TimeInterval
  }

  private let queue = DispatchQueue(label: "nanomouse.voice.personal-dictionary")
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .hamster) {
    self.userDefaults = userDefaults
  }

  func words(filter: VoicePersonalWordSource?) -> [VoicePersonalWord] {
    queue.sync {
      let all = loadRecordsLocked()
      return all
        .filter { filter == nil || $0.source == filter }
        .sorted { lhs, rhs in
          if lhs.score == rhs.score {
            return lhs.updatedAt > rhs.updatedAt
          }
          return lhs.score > rhs.score
        }
        .map {
          VoicePersonalWord(
            word: $0.word,
            source: $0.source,
            score: $0.score,
            updatedAt: $0.updatedAt
          )
        }
    }
  }

  func hotwords(limit: Int) -> [String] {
    queue.sync {
      let positiveLimit = max(0, limit)
      guard positiveLimit > 0 else { return [] }
      return loadRecordsLocked()
        .sorted { lhs, rhs in
          if lhs.score == rhs.score {
            return lhs.updatedAt > rhs.updatedAt
          }
          return lhs.score > rhs.score
        }
        .prefix(positiveLimit)
        .map(\.word)
    }
  }

  func addManualWord(_ rawWord: String) {
    let normalizedWord = normalizeWord(rawWord)
    guard !normalizedWord.isEmpty else { return }
    queue.sync {
      var records = loadRecordsLocked()
      let now = Date().timeIntervalSince1970
      if let index = records.firstIndex(where: { $0.word == normalizedWord }) {
        records[index].source = .manual
        records[index].score = max(records[index].score, 12)
        records[index].updatedAt = now
      } else {
        records.append(
          StoredWordRecord(
            word: normalizedWord,
            source: .manual,
            score: 12,
            updatedAt: now
          )
        )
      }
      saveRecordsLocked(trim(records: records))
    }
  }

  func removeWord(_ rawWord: String) {
    let normalizedWord = normalizeWord(rawWord)
    guard !normalizedWord.isEmpty else { return }
    queue.sync {
      let filtered = loadRecordsLocked().filter { $0.word != normalizedWord }
      saveRecordsLocked(filtered)
    }
  }

  @discardableResult
  func learnWords(from text: String, localeIdentifier: String?) -> [String] {
    // 自动学习词典：把高频专有词沉淀成热词，供下一次识别注入 contextualStrings。
    let candidates = extractCandidates(from: text, localeIdentifier: localeIdentifier)
    guard !candidates.isEmpty else { return [] }
    return queue.sync {
      var records = loadRecordsLocked()
      let now = Date().timeIntervalSince1970
      var inserted: [String] = []
      for candidate in candidates {
        if let index = records.firstIndex(where: { $0.word == candidate }) {
          if records[index].source == .manual {
            records[index].score += 1
          } else {
            records[index].score = min(99, records[index].score + 2)
          }
          records[index].updatedAt = now
        } else {
          records.append(
            StoredWordRecord(
              word: candidate,
              source: .auto,
              score: 3,
              updatedAt: now
            )
          )
          inserted.append(candidate)
        }
      }
      saveRecordsLocked(trim(records: records))
      return inserted
    }
  }
}

private extension VoicePersonalDictionaryStore {
  private func loadRecordsLocked() -> [StoredWordRecord] {
    guard let data = userDefaults.data(forKey: Constants.storageKey) else { return [] }
    let decoder = JSONDecoder()
    return (try? decoder.decode([StoredWordRecord].self, from: data)) ?? []
  }

  private func saveRecordsLocked(_ records: [StoredWordRecord]) {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(records) else { return }
    userDefaults.set(data, forKey: Constants.storageKey)
  }

  private func trim(records: [StoredWordRecord]) -> [StoredWordRecord] {
    if records.count <= Constants.maxWordCount {
      return records
    }
    let sorted = records.sorted { lhs, rhs in
      if lhs.source != rhs.source {
        return lhs.source == .manual
      }
      if lhs.score == rhs.score {
        return lhs.updatedAt > rhs.updatedAt
      }
      return lhs.score > rhs.score
    }
    return Array(sorted.prefix(Constants.maxWordCount))
  }

  private func normalizeWord(_ rawWord: String) -> String {
    let trimmed = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    let collapsed = trimmed.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    return collapsed
  }

  private func extractCandidates(from text: String, localeIdentifier: String?) -> [String] {
    let normalizedText = normalizeWord(text)
    guard !normalizedText.isEmpty else { return [] }

    var candidates: [String] = []
    let hanPattern = "[\\p{Han}]{2,8}"
    candidates.append(contentsOf: matches(pattern: hanPattern, in: normalizedText))

    let latinPattern = "[A-Za-z][A-Za-z0-9_\\-]{2,}"
    candidates.append(
      contentsOf: matches(pattern: latinPattern, in: normalizedText)
        .map { $0.lowercased() }
    )

    let locale = (localeIdentifier ?? "").lowercased()
    let stopwords: Set<String>
    if locale.hasPrefix("zh") || locale.hasPrefix("ja") {
      stopwords = ["这个", "那个", "我们", "你们", "他们", "就是", "然后", "可以", "一个", "一下"]
    } else {
      stopwords = ["the", "and", "for", "with", "this", "that", "you", "your", "from", "into"]
    }

    var seen = Set<String>()
    var result: [String] = []
    for candidate in candidates {
      let word = normalizeWord(candidate)
      guard !word.isEmpty, !stopwords.contains(word), !seen.contains(word) else { continue }
      seen.insert(word)
      result.append(word)
    }
    return result
  }

  private func matches(pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, options: [], range: range)
    return matches.compactMap { match in
      guard let swiftRange = Range(match.range, in: text) else { return nil }
      return String(text[swiftRange])
    }
  }
}

enum VoiceASRMode: String, Codable, CaseIterable {
  case disabled
  case fallback
  case preferred

  var displayName: String {
    switch self {
    case .disabled:
      return "关闭"
    case .fallback:
      return "兜底"
    case .preferred:
      return "优先"
    }
  }
}

enum VoiceASREnginePreference: String, Codable, CaseIterable {
  case auto
  case apple
  case whisper
  case cloud

  var displayName: String {
    switch self {
    case .auto:
      return "自动"
    case .apple:
      return "Apple"
    case .whisper:
      return "Whisper"
    case .cloud:
      return "在线"
    }
  }
}

private enum VoiceASRDirectCallType {
  case openAITranscriptions
  case deepgramListen
  case proxyOnly
}

enum VoiceASRProvider: String, Codable, CaseIterable {
  case openAI = "openai"
  case qwen
  case glm
  case baiduQianfan = "baidu_qianfan"
  case doubao
  case tencentHunyuan = "tencent_hunyuan"
  case deepgram
  case assemblyAI = "assemblyai"
  case speechmatics
  case googleSpeech = "google_speech"
  case azureSpeech = "azure_speech"
  case awsTranscribe = "aws_transcribe"
  case groq
  case custom

  var displayName: String {
    switch self {
    case .openAI:
      return "OpenAI"
    case .qwen:
      return "Qwen"
    case .glm:
      return "智谱 GLM-ASR"
    case .baiduQianfan:
      return "百度语音/千帆"
    case .doubao:
      return "豆包语音"
    case .tencentHunyuan:
      return "腾讯语音/混元"
    case .deepgram:
      return "Deepgram"
    case .assemblyAI:
      return "AssemblyAI"
    case .speechmatics:
      return "Speechmatics"
    case .googleSpeech:
      return "Google Speech-to-Text"
    case .azureSpeech:
      return "Azure Speech"
    case .awsTranscribe:
      return "AWS Transcribe"
    case .groq:
      return "Groq Whisper API"
    case .custom:
      return "自定义"
    }
  }

  var defaultBaseURL: String {
    switch self {
    case .openAI:
      return "https://api.openai.com/v1"
    case .qwen:
      return "https://dashscope.aliyuncs.com/compatible-mode/v1"
    case .glm:
      return "https://open.bigmodel.cn/api/paas/v4"
    case .baiduQianfan:
      return ""
    case .doubao:
      return "https://ark.cn-beijing.volces.com/api/v3"
    case .tencentHunyuan:
      return "https://api.hunyuan.cloud.tencent.com/v1"
    case .deepgram:
      return "https://api.deepgram.com/v1"
    case .assemblyAI:
      return "https://api.assemblyai.com/v2"
    case .speechmatics:
      return "https://asr.api.speechmatics.com/v2"
    case .googleSpeech:
      return ""
    case .azureSpeech:
      return ""
    case .awsTranscribe:
      return ""
    case .groq:
      return "https://api.groq.com/openai/v1"
    case .custom:
      return ""
    }
  }

  var defaultModel: String {
    switch self {
    case .openAI:
      return "gpt-4o-mini-transcribe"
    case .qwen:
      return "qwen3-asr-flash"
    case .glm:
      return "glm-asr"
    case .baiduQianfan:
      return "asr"
    case .doubao:
      return "doubao-asr"
    case .tencentHunyuan:
      return "hunyuan-asr"
    case .deepgram:
      return "nova-3"
    case .assemblyAI:
      return "best"
    case .speechmatics:
      return "latest"
    case .googleSpeech:
      return "latest_long"
    case .azureSpeech:
      return "latest"
    case .awsTranscribe:
      return "standard"
    case .groq:
      return "whisper-large-v3-turbo"
    case .custom:
      return ""
    }
  }

  var staticModelCandidates: [String] {
    switch self {
    case .openAI:
      return ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"]
    case .qwen:
      return ["qwen3-asr-flash", "qwen3-asr-flash-realtime", "qwen3-asr-flash-filetrans"]
    case .glm:
      return ["glm-asr", "glm-asr-2512"]
    case .baiduQianfan:
      return ["asr", "极速版", "高精度版"]
    case .doubao:
      return ["doubao-asr", "doubao-asr-realtime"]
    case .tencentHunyuan:
      return ["hunyuan-asr", "hunyuan-stream-asr"]
    case .deepgram:
      return ["nova-3", "nova-2", "flux-general-en"]
    case .assemblyAI:
      return ["best", "nano"]
    case .speechmatics:
      return ["latest", "enhanced"]
    case .googleSpeech:
      return ["latest_long", "latest_short", "chirp_2"]
    case .azureSpeech:
      return ["latest", "conversation", "dictation"]
    case .awsTranscribe:
      return ["standard", "medical"]
    case .groq:
      return ["whisper-large-v3-turbo", "whisper-large-v3"]
    case .custom:
      return []
    }
  }

  var integrationHint: String {
    switch directCallType {
    case .openAITranscriptions:
      return "当前支持应用内直连（OpenAI 兼容 /audio/transcriptions）。"
    case .deepgramListen:
      return "当前支持应用内直连（Deepgram /listen）。"
    case .proxyOnly:
      return "该供应商建议走服务端代理；若要应用内直连，请先确认官方 iOS 直连鉴权方式。"
    }
  }

  fileprivate var directCallType: VoiceASRDirectCallType {
    switch self {
    case .openAI, .groq:
      return .openAITranscriptions
    case .deepgram:
      return .deepgramListen
    case .qwen, .glm, .baiduQianfan, .doubao, .tencentHunyuan, .assemblyAI, .speechmatics, .googleSpeech, .azureSpeech, .awsTranscribe, .custom:
      return .proxyOnly
    }
  }
}

struct VoiceASRRuntimeConfig {
  let enginePreference: VoiceASREnginePreference
  let mode: VoiceASRMode
  let provider: VoiceASRProvider
  let proxyEndpoint: String
  let byokBaseURL: String
  let model: String
  let apiKey: String?
}

final class VoiceASRSettingsStore {
  static let shared = VoiceASRSettingsStore()

  private enum Constants {
    static let enginePreferenceKey = "voice.asr.engine.preference"
    static let modeKey = "voice.asr.mode"
    static let providerKey = "voice.asr.provider"
    static let proxyEndpointKey = "voice.asr.proxy.endpoint"
    static let byokBaseURLKeyPrefix = "voice.asr.byok.base_url."
    static let byokModelKeyPrefix = "voice.asr.byok.model."
    static let keychainService = "com.XiangqingZHANG.nanomouse.voice.asr"
    static let keychainAccountPrefix = "byok_asr_api_key."
  }

  private let queue = DispatchQueue(label: "nanomouse.voice.asr.settings")
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .hamster) {
    self.userDefaults = userDefaults
  }

  func runtimeConfig() -> VoiceASRRuntimeConfig {
    queue.sync {
      let provider = providerLocked()
      return VoiceASRRuntimeConfig(
        enginePreference: enginePreferenceLocked(),
        mode: modeLocked(),
        provider: provider,
        proxyEndpoint: (userDefaults.string(forKey: Constants.proxyEndpointKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
        byokBaseURL: loadByokBaseURLLocked(for: provider),
        model: loadByokModelLocked(for: provider),
        apiKey: readAPIKeyLocked(for: provider)
      )
    }
  }

  func mode() -> VoiceASRMode {
    queue.sync { modeLocked() }
  }

  func enginePreference() -> VoiceASREnginePreference {
    queue.sync { enginePreferenceLocked() }
  }

  func setEnginePreference(_ preference: VoiceASREnginePreference) {
    queue.sync {
      userDefaults.set(preference.rawValue, forKey: Constants.enginePreferenceKey)
    }
  }

  func setMode(_ mode: VoiceASRMode) {
    queue.sync {
      userDefaults.set(mode.rawValue, forKey: Constants.modeKey)
    }
  }

  func provider() -> VoiceASRProvider {
    queue.sync { providerLocked() }
  }

  func setProvider(_ provider: VoiceASRProvider) {
    queue.sync {
      userDefaults.set(provider.rawValue, forKey: Constants.providerKey)
    }
  }

  func proxyEndpoint() -> String {
    queue.sync {
      (userDefaults.string(forKey: Constants.proxyEndpointKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  func setProxyEndpoint(_ endpoint: String) {
    queue.sync {
      userDefaults.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Constants.proxyEndpointKey)
    }
  }

  func byokBaseURL(for provider: VoiceASRProvider) -> String {
    queue.sync { loadByokBaseURLLocked(for: provider) }
  }

  func setByokBaseURL(_ baseURL: String, for provider: VoiceASRProvider) {
    queue.sync {
      saveByokBaseURLLocked(baseURL, for: provider)
    }
  }

  func byokModel(for provider: VoiceASRProvider) -> String {
    queue.sync { loadByokModelLocked(for: provider) }
  }

  func setByokModel(_ model: String, for provider: VoiceASRProvider) {
    queue.sync {
      saveByokModelLocked(model, for: provider)
    }
  }

  func apiKey(for provider: VoiceASRProvider) -> String? {
    queue.sync { readAPIKeyLocked(for: provider) }
  }

  func setAPIKey(_ apiKey: String?, for provider: VoiceASRProvider) {
    queue.sync {
      saveAPIKeyLocked(
        apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
        for: provider
      )
    }
  }
}

private extension VoiceASRSettingsStore {
  func byokBaseURLKeyLocked(for provider: VoiceASRProvider) -> String {
    Constants.byokBaseURLKeyPrefix + provider.rawValue
  }

  func byokModelKeyLocked(for provider: VoiceASRProvider) -> String {
    Constants.byokModelKeyPrefix + provider.rawValue
  }

  func enginePreferenceLocked() -> VoiceASREnginePreference {
    let raw = userDefaults.string(forKey: Constants.enginePreferenceKey) ?? VoiceASREnginePreference.auto.rawValue
    return VoiceASREnginePreference(rawValue: raw) ?? .auto
  }

  func modeLocked() -> VoiceASRMode {
    let raw = userDefaults.string(forKey: Constants.modeKey) ?? VoiceASRMode.disabled.rawValue
    return VoiceASRMode(rawValue: raw) ?? .disabled
  }

  func providerLocked() -> VoiceASRProvider {
    let raw = userDefaults.string(forKey: Constants.providerKey) ?? VoiceASRProvider.openAI.rawValue
    return VoiceASRProvider(rawValue: raw) ?? .openAI
  }

  func loadByokBaseURLLocked(for provider: VoiceASRProvider) -> String {
    let key = byokBaseURLKeyLocked(for: provider)
    let value = (userDefaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty {
      return value
    }
    return provider.defaultBaseURL
  }

  func saveByokBaseURLLocked(_ baseURL: String, for provider: VoiceASRProvider) {
    let key = byokBaseURLKeyLocked(for: provider)
    userDefaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
  }

  func loadByokModelLocked(for provider: VoiceASRProvider) -> String {
    let key = byokModelKeyLocked(for: provider)
    let value = (userDefaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty {
      return value
    }
    return provider.defaultModel
  }

  func saveByokModelLocked(_ model: String, for provider: VoiceASRProvider) {
    let key = byokModelKeyLocked(for: provider)
    userDefaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
  }

  func keychainAccountLocked(for provider: VoiceASRProvider) -> String {
    Constants.keychainAccountPrefix + provider.rawValue
  }

  func keychainQueryLocked(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Constants.keychainService,
      kSecAttrAccount as String: account
    ]
  }

  func readRawAPIKeyLocked(account: String) -> String? {
    var query = keychainQueryLocked(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func saveRawAPIKeyLocked(_ apiKey: String?, account: String) {
    let query = keychainQueryLocked(account: account)
    SecItemDelete(query as CFDictionary)
    guard let apiKey, !apiKey.isEmpty else { return }
    var insert = query
    insert[kSecValueData as String] = apiKey.data(using: .utf8)
    SecItemAdd(insert as CFDictionary, nil)
  }

  func readAPIKeyLocked(for provider: VoiceASRProvider) -> String? {
    let account = keychainAccountLocked(for: provider)
    return readRawAPIKeyLocked(account: account)
  }

  func saveAPIKeyLocked(_ apiKey: String?, for provider: VoiceASRProvider) {
    let account = keychainAccountLocked(for: provider)
    saveRawAPIKeyLocked(apiKey, account: account)
  }
}

enum VoiceASRServiceError: LocalizedError {
  case disabled
  case proxyEndpointMissing
  case byokEndpointMissing
  case byokAPIKeyMissing
  case providerDirectUnsupported(provider: VoiceASRProvider)
  case invalidResponse
  case emptyResponse
  case requestFailed(message: String)

  var errorDescription: String? {
    switch self {
    case .disabled:
      return "在线 ASR 未开启"
    case .proxyEndpointMissing:
      return "ASR 代理地址未配置"
    case .byokEndpointMissing:
      return "ASR Base URL 未配置"
    case .byokAPIKeyMissing:
      return "ASR API Key 未配置"
    case .providerDirectUnsupported(let provider):
      return "\(provider.displayName) 当前不支持应用内直连，请改用代理模式。"
    case .invalidResponse:
      return "ASR 返回格式异常"
    case .emptyResponse:
      return "ASR 返回为空"
    case .requestFailed(let message):
      return "ASR 请求失败：\(message)"
    }
  }
}

final class VoiceASRService {
  static let shared = VoiceASRService()

  private let settingsStore: VoiceASRSettingsStore
  private let session: URLSession

  init(settingsStore: VoiceASRSettingsStore = .shared, session: URLSession = .shared) {
    self.settingsStore = settingsStore
    self.session = session
  }

  func transcribe(audioFileURL: URL, localeIdentifier: String?) async throws -> String {
    let config = settingsStore.runtimeConfig()
    return try await transcribe(audioFileURL: audioFileURL, localeIdentifier: localeIdentifier, config: config)
  }

  func transcribe(
    audioFileURL: URL,
    localeIdentifier: String?,
    config: VoiceASRRuntimeConfig
  ) async throws -> String {
    guard config.mode != .disabled else { throw VoiceASRServiceError.disabled }
    switch config.provider.directCallType {
    case .openAITranscriptions:
      return try await transcribeViaOpenAICompatible(
        audioFileURL: audioFileURL,
        localeIdentifier: localeIdentifier,
        config: config
      )
    case .deepgramListen:
      return try await transcribeViaDeepgram(
        audioFileURL: audioFileURL,
        localeIdentifier: localeIdentifier,
        config: config
      )
    case .proxyOnly:
      return try await transcribeViaProxy(
        audioFileURL: audioFileURL,
        localeIdentifier: localeIdentifier,
        config: config
      )
    }
  }
}

private extension VoiceASRService {
  struct SimpleTextResponse: Decodable {
    let text: String?
  }

  struct ErrorResponseBody: Decodable {
    struct ErrorMessage: Decodable {
      let message: String?
    }
    let error: ErrorMessage?
    let message: String?
  }

  struct DeepgramResponseBody: Decodable {
    struct ResultBody: Decodable {
      struct Channel: Decodable {
        struct Alternative: Decodable {
          let transcript: String?
        }
        let alternatives: [Alternative]?
      }
      let channels: [Channel]?
    }
    let results: ResultBody?
  }

  func transcribeViaProxy(
    audioFileURL: URL,
    localeIdentifier: String?,
    config: VoiceASRRuntimeConfig
  ) async throws -> String {
    let endpoint = config.proxyEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !endpoint.isEmpty else {
      throw VoiceASRServiceError.providerDirectUnsupported(provider: config.provider)
    }
    guard let endpointURL = URL(string: endpoint) else {
      throw VoiceASRServiceError.requestFailed(message: "ASR 代理地址无效")
    }

    let audioData = try Data(contentsOf: audioFileURL)
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? config.provider.defaultModel
      : config.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let fields = [
      "provider": config.provider.rawValue,
      "model": model,
      "locale": normalizedLanguageCode(from: localeIdentifier)
    ]
    request.httpBody = buildMultipartBody(
      boundary: boundary,
      fields: fields,
      fileFieldName: "file",
      fileName: "dictation.wav",
      mimeType: "audio/wav",
      fileData: audioData
    )

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceASRServiceError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = decodeErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
      throw VoiceASRServiceError.requestFailed(message: message)
    }
    let payload = try JSONDecoder().decode(SimpleTextResponse.self, from: data)
    let text = (payload.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw VoiceASRServiceError.emptyResponse }
    return text
  }

  func transcribeViaOpenAICompatible(
    audioFileURL: URL,
    localeIdentifier: String?,
    config: VoiceASRRuntimeConfig
  ) async throws -> String {
    let baseURL = config.byokBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !baseURL.isEmpty else {
      throw VoiceASRServiceError.byokEndpointMissing
    }
    guard let apiKey = config.apiKey, !apiKey.isEmpty else {
      throw VoiceASRServiceError.byokAPIKeyMissing
    }

    let endpointString = baseURL.hasSuffix("/") ? (baseURL + "audio/transcriptions") : (baseURL + "/audio/transcriptions")
    guard let endpointURL = URL(string: endpointString) else {
      throw VoiceASRServiceError.requestFailed(message: "ASR Base URL 无效")
    }

    let audioData = try Data(contentsOf: audioFileURL)
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 35
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? config.provider.defaultModel
      : config.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let fields = [
      "model": model,
      "response_format": "json",
      "language": normalizedLanguageCode(from: localeIdentifier)
    ]
    request.httpBody = buildMultipartBody(
      boundary: boundary,
      fields: fields,
      fileFieldName: "file",
      fileName: "dictation.wav",
      mimeType: "audio/wav",
      fileData: audioData
    )

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceASRServiceError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = decodeErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
      throw VoiceASRServiceError.requestFailed(message: message)
    }

    let payload = try JSONDecoder().decode(SimpleTextResponse.self, from: data)
    let text = (payload.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw VoiceASRServiceError.emptyResponse }
    return text
  }

  func transcribeViaDeepgram(
    audioFileURL: URL,
    localeIdentifier: String?,
    config: VoiceASRRuntimeConfig
  ) async throws -> String {
    let baseURL = config.byokBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !baseURL.isEmpty else {
      throw VoiceASRServiceError.byokEndpointMissing
    }
    guard let apiKey = config.apiKey, !apiKey.isEmpty else {
      throw VoiceASRServiceError.byokAPIKeyMissing
    }

    let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? config.provider.defaultModel
      : config.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let language = normalizedLanguageCode(from: localeIdentifier)
    let endpointString = "\(baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL)/listen?model=\(model)&smart_format=true&punctuate=true&language=\(language)"
    guard let endpointURL = URL(string: endpointString) else {
      throw VoiceASRServiceError.requestFailed(message: "Deepgram 地址无效")
    }

    let audioData = try Data(contentsOf: audioFileURL)
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 35
    request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
    request.httpBody = audioData

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceASRServiceError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = decodeErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
      throw VoiceASRServiceError.requestFailed(message: message)
    }

    let payload = try JSONDecoder().decode(DeepgramResponseBody.self, from: data)
    let transcript = payload.results?.channels?.first?.alternatives?.first?.transcript?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !transcript.isEmpty else { throw VoiceASRServiceError.emptyResponse }
    return transcript
  }

  func buildMultipartBody(
    boundary: String,
    fields: [String: String],
    fileFieldName: String,
    fileName: String,
    mimeType: String,
    fileData: Data
  ) -> Data {
    var body = Data()
    let lineBreak = "\r\n"

    for (key, value) in fields where !value.isEmpty {
      body.append("--\(boundary)\(lineBreak)")
      body.append("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)")
      body.append("\(value)\(lineBreak)")
    }

    body.append("--\(boundary)\(lineBreak)")
    body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\(lineBreak)")
    body.append("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)")
    body.append(fileData)
    body.append(lineBreak)
    body.append("--\(boundary)--\(lineBreak)")
    return body
  }

  func normalizedLanguageCode(from localeIdentifier: String?) -> String {
    let locale = (localeIdentifier ?? "").lowercased()
    if locale.hasPrefix("zh") {
      return "zh"
    }
    if locale.hasPrefix("ja") {
      return "ja"
    }
    if locale.hasPrefix("en") {
      return "en"
    }
    return "auto"
  }

  func decodeErrorMessage(data: Data) -> String? {
    if let payload = try? JSONDecoder().decode(ErrorResponseBody.self, from: data) {
      let message = payload.error?.message ?? payload.message
      if let message {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          return trimmed
        }
      }
    }
    if let text = String(data: data, encoding: .utf8) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return trimmed
      }
    }
    return nil
  }
}

private extension Data {
  mutating func append(_ string: String) {
    if let data = string.data(using: .utf8) {
      append(data)
    }
  }
}

enum VoiceLLMAuthMode: String, Codable, CaseIterable {
  case proxy
  case byok
}

enum VoiceLLMProvider: String, Codable, CaseIterable {
  case openAI = "openai"
  case qwen
  case glm
  case baiduQianfan = "baidu_qianfan"
  case doubao
  case tencentHunyuan = "tencent_hunyuan"
  case gemini
  case deepseek
  case claude
  case minimax
  case moonshot
  case custom

  var displayName: String {
    switch self {
    case .openAI:
      return "OpenAI"
    case .qwen:
      return "Qwen"
    case .glm:
      return "智谱 GLM"
    case .baiduQianfan:
      return "百度千帆"
    case .doubao:
      return "豆包"
    case .tencentHunyuan:
      return "腾讯混元"
    case .gemini:
      return "Google Gemini"
    case .deepseek:
      return "DeepSeek"
    case .claude:
      return "Anthropic Claude"
    case .minimax:
      return "MiniMax"
    case .moonshot:
      return "Moonshot"
    case .custom:
      return "自定义"
    }
  }

  var defaultBaseURL: String {
    switch self {
    case .openAI:
      return "https://api.openai.com/v1"
    case .qwen:
      return "https://dashscope.aliyuncs.com/compatible-mode/v1"
    case .glm:
      return "https://open.bigmodel.cn/api/paas/v4"
    case .baiduQianfan:
      return "https://qianfan.baidubce.com/v2"
    case .doubao:
      return "https://ark.cn-beijing.volces.com/api/v3"
    case .tencentHunyuan:
      return "https://api.hunyuan.cloud.tencent.com/v1"
    case .gemini:
      return "https://generativelanguage.googleapis.com/v1beta/openai"
    case .deepseek:
      return "https://api.deepseek.com/v1"
    case .claude:
      return "https://api.anthropic.com/v1"
    case .minimax:
      return "https://api.minimax.chat/v1"
    case .moonshot:
      return "https://api.moonshot.cn/v1"
    case .custom:
      return ""
    }
  }

  var defaultModel: String {
    switch self {
    case .openAI:
      return "gpt-5-nano"
    case .qwen:
      return "qwen-plus"
    case .glm:
      return "glm-4-flash"
    case .baiduQianfan:
      return "ernie-4.5-0.3b"
    case .doubao:
      return "doubao-seed-1.6-lite"
    case .tencentHunyuan:
      return "hunyuan-a13b"
    case .gemini:
      return "gemini-2.0-flash-lite"
    case .deepseek:
      return "deepseek-chat"
    case .claude:
      return "claude-3-haiku-20240307"
    case .minimax:
      return "minimax-m2.1"
    case .moonshot:
      return "moonshot-v1-8k"
    case .custom:
      return ""
    }
  }

  // 静态候选模型：用于 BYOK 未配置 API Key 时的离线兜底展示。
  var staticModelCandidates: [String] {
    switch self {
    case .openAI:
      return [
        "gpt-5-nano",
        "gpt-4o-mini",
        "gpt-4o",
        "gpt-4.1-mini",
        "gpt-4.1"
      ]
    case .qwen:
      return [
        "qwen-plus",
        "qwen-max",
        "qwen-turbo"
      ]
    case .glm:
      return [
        "glm-4-flash",
        "glm-4-plus",
        "glm-4-air"
      ]
    case .baiduQianfan:
      return [
        "ernie-4.5-0.3b",
        "ernie-4.5-8b",
        "ernie-4.0-8k"
      ]
    case .doubao:
      return [
        "doubao-seed-1.6-lite",
        "doubao-seed-1.6",
        "doubao-pro-32k"
      ]
    case .tencentHunyuan:
      return [
        "hunyuan-a13b",
        "hunyuan-lite",
        "hunyuan-standard"
      ]
    case .gemini:
      return [
        "gemini-2.0-flash-lite",
        "gemini-2.0-flash",
        "gemini-1.5-flash"
      ]
    case .deepseek:
      return [
        "deepseek-chat",
        "deepseek-reasoner"
      ]
    case .claude:
      return [
        "claude-3-haiku-20240307",
        "claude-3-5-haiku-latest",
        "claude-3-5-sonnet-latest"
      ]
    case .minimax:
      return [
        "minimax-m2.1",
        "minimax-m1",
        "abab6.5s-chat"
      ]
    case .moonshot:
      return [
        "moonshot-v1-8k",
        "moonshot-v1-32k",
        "moonshot-v1-128k"
      ]
    case .custom:
      return []
    }
  }

  // 官方公开文档源：用于 BYOK 未配置 API Key 时在线抓取候选模型。
  var officialCatalogURLs: [String] {
    switch self {
    case .openAI:
      return [
        "https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml"
      ]
    case .qwen:
      return [
        "https://help.aliyun.com/zh/model-studio/models"
      ]
    case .glm:
      return [
        "https://docs.bigmodel.cn/cn/guide/start/model-overview",
        "https://docs.bigmodel.cn/llms.txt"
      ]
    case .baiduQianfan:
      return [
        "https://cloud.baidu.com/doc/qianfan/s/wmh4sv6ya"
      ]
    case .doubao:
      return [
        "https://www.volcengine.com/product/doubao/"
      ]
    case .tencentHunyuan:
      return [
        "https://cloud.tencent.com/document/product/1729/97731"
      ]
    case .gemini:
      return [
        "https://ai.google.dev/gemini-api/docs/pricing"
      ]
    case .deepseek:
      return [
        "https://api-docs.deepseek.com/quick_start/pricing/"
      ]
    case .claude:
      return [
        "https://platform.claude.com/docs/en/about-claude/pricing"
      ]
    case .minimax:
      return [
        "https://platform.minimaxi.com/docs/guides/pricing-paygo"
      ]
    case .moonshot:
      return [
        "https://platform.moonshot.cn/docs/pricing/chat"
      ]
    case .custom:
      return []
    }
  }

  var byokCompatibilityHint: String {
    switch self {
    case .openAI, .qwen, .glm, .deepseek, .moonshot:
      return "当前客户端按 OpenAI 兼容格式调用。"
    case .baiduQianfan, .doubao, .tencentHunyuan, .gemini, .minimax:
      return "该供应商接口版本可能存在差异；若失败请改用代理模式。"
    case .claude:
      return "当前客户端按 OpenAI 兼容格式调用，Claude 官方原生接口建议走代理模式。"
    case .custom:
      return "请填写你自己的 OpenAI 兼容地址与模型。"
    }
  }
}

struct VoiceLLMPromptPreset: Codable, Equatable {
  let id: String
  var name: String
  var instruction: String

  static let defaultPresets: [VoiceLLMPromptPreset] = [
    .init(
      id: "balanced",
      name: "平衡优化",
      instruction: "保留原意并修正语法与标点，输出自然、清晰、可直接发送的文本。"
    ),
    .init(
      id: "structured",
      name: "条理清晰",
      instruction: "保持原意并重组结构，优先使用短句或条目，让信息层次更清楚。"
    ),
    .init(
      id: "concise",
      name: "简洁专业",
      instruction: "删除口语化和重复表达，尽量精炼，但不要丢失关键信息。"
    ),
    .init(
      id: "polite",
      name: "礼貌友好",
      instruction: "保持内容准确，并将语气调整为礼貌、友好、专业。"
    ),
    .init(
      id: "actionable",
      name: "行动导向",
      instruction: "优先突出结论、待办事项和下一步动作，必要时整理为列表。"
    ),
    .init(
      id: "proofread",
      name: "纠错优先",
      instruction: "优先修正错别字、专有名词、数字与时间表达，避免语义偏移。"
    ),
  ]
}

struct VoiceLLMRuntimeConfig {
  let authMode: VoiceLLMAuthMode
  let provider: VoiceLLMProvider
  let proxyEndpoint: String
  let proxyModelsEndpoint: String
  let byokBaseURL: String
  let model: String
  let apiKey: String?
}

final class VoiceLLMSettingsStore {
  static let shared = VoiceLLMSettingsStore()

  private enum Constants {
    static let llmEnabledKey = "voice.llm.enabled"
    static let authModeKey = "voice.llm.auth.mode"
    static let providerKey = "voice.llm.provider"
    static let proxyEndpointKey = "voice.llm.proxy.endpoint"
    static let proxyModelsEndpointKey = "voice.llm.proxy.models.endpoint"
    static let byokBaseURLKeyLegacy = "voice.llm.byok.base_url"
    static let byokModelKeyLegacy = "voice.llm.byok.model"
    static let byokBaseURLKeyPrefix = "voice.llm.byok.base_url."
    static let byokModelKeyPrefix = "voice.llm.byok.model."
    static let promptPresetsKey = "voice.llm.prompt.presets"
    static let selectedPromptPresetIDKey = "voice.llm.prompt.selected_id"
    static let cachedModelsKey = "voice.llm.cached.models"
    static let cachedModelsUpdatedAtKey = "voice.llm.cached.models.updated_at"
    static let keychainService = "com.XiangqingZHANG.nanomouse.voice.llm"
    static let keychainAccountLegacy = "byok_api_key"
    static let keychainAccountPrefix = "byok_api_key."
  }

  private let queue = DispatchQueue(label: "nanomouse.voice.llm.settings")
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .hamster) {
    self.userDefaults = userDefaults
  }

  func runtimeConfig() -> VoiceLLMRuntimeConfig {
    queue.sync {
      let provider = self.providerLocked()
      let authMode = self.authModeLocked()
      let proxyEndpoint = (userDefaults.string(forKey: Constants.proxyEndpointKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let proxyModelsEndpoint = (userDefaults.string(forKey: Constants.proxyModelsEndpointKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let byokBaseURL = loadByokBaseURLLocked(for: provider)
      let model = loadByokModelLocked(for: provider)
      return VoiceLLMRuntimeConfig(
        authMode: authMode,
        provider: provider,
        proxyEndpoint: proxyEndpoint,
        proxyModelsEndpoint: proxyModelsEndpoint,
        byokBaseURL: byokBaseURL,
        model: model,
        apiKey: self.readAPIKeyLocked(for: provider)
      )
    }
  }

  func setLLMEnabled(_ enabled: Bool) {
    queue.sync {
      userDefaults.set(enabled, forKey: Constants.llmEnabledKey)
    }
  }

  func isLLMEnabled() -> Bool {
    queue.sync { llmEnabledLocked() }
  }

  func setAuthMode(_ mode: VoiceLLMAuthMode) {
    queue.sync {
      userDefaults.set(mode.rawValue, forKey: Constants.authModeKey)
    }
  }

  func setProvider(_ provider: VoiceLLMProvider) {
    queue.sync {
      userDefaults.set(provider.rawValue, forKey: Constants.providerKey)
    }
  }

  func setProxyEndpoint(_ endpoint: String) {
    queue.sync {
      userDefaults.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Constants.proxyEndpointKey)
    }
  }

  func setProxyModelsEndpoint(_ endpoint: String) {
    queue.sync {
      userDefaults.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Constants.proxyModelsEndpointKey)
    }
  }

  func setByokBaseURL(_ baseURL: String) {
    queue.sync {
      let provider = providerLocked()
      saveByokBaseURLLocked(baseURL, for: provider)
    }
  }

  func setByokBaseURL(_ baseURL: String, for provider: VoiceLLMProvider) {
    queue.sync {
      saveByokBaseURLLocked(baseURL, for: provider)
    }
  }

  func setByokModel(_ model: String) {
    queue.sync {
      let provider = providerLocked()
      saveByokModelLocked(model, for: provider)
    }
  }

  func setByokModel(_ model: String, for provider: VoiceLLMProvider) {
    queue.sync {
      saveByokModelLocked(model, for: provider)
    }
  }

  func setAPIKey(_ apiKey: String?) {
    queue.sync {
      let provider = providerLocked()
      saveAPIKeyLocked(
        apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
        for: provider
      )
    }
  }

  func setAPIKey(_ apiKey: String?, for provider: VoiceLLMProvider) {
    queue.sync {
      saveAPIKeyLocked(
        apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
        for: provider
      )
    }
  }

  func authMode() -> VoiceLLMAuthMode {
    queue.sync { authModeLocked() }
  }

  func provider() -> VoiceLLMProvider {
    queue.sync { providerLocked() }
  }

  func proxyEndpoint() -> String {
    queue.sync {
      (userDefaults.string(forKey: Constants.proxyEndpointKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  func proxyModelsEndpoint() -> String {
    queue.sync {
      (userDefaults.string(forKey: Constants.proxyModelsEndpointKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  func byokBaseURL() -> String {
    queue.sync {
      let provider = providerLocked()
      return loadByokBaseURLLocked(for: provider)
    }
  }

  func byokBaseURL(for provider: VoiceLLMProvider) -> String {
    queue.sync { loadByokBaseURLLocked(for: provider) }
  }

  func byokModel() -> String {
    queue.sync {
      let provider = providerLocked()
      return loadByokModelLocked(for: provider)
    }
  }

  func byokModel(for provider: VoiceLLMProvider) -> String {
    queue.sync { loadByokModelLocked(for: provider) }
  }

  func apiKey() -> String? {
    queue.sync {
      let provider = providerLocked()
      return readAPIKeyLocked(for: provider)
    }
  }

  func apiKey(for provider: VoiceLLMProvider) -> String? {
    queue.sync { readAPIKeyLocked(for: provider) }
  }

  func promptPresets() -> [VoiceLLMPromptPreset] {
    queue.sync { loadPromptPresetsLocked() }
  }

  func selectedPromptPresetID() -> String {
    queue.sync {
      let presets = loadPromptPresetsLocked()
      return selectedPromptPresetIDLocked(presets: presets)
    }
  }

  func selectedPromptPreset() -> VoiceLLMPromptPreset {
    queue.sync {
      let presets = loadPromptPresetsLocked()
      let selectedID = selectedPromptPresetIDLocked(presets: presets)
      return presets.first(where: { $0.id == selectedID }) ?? presets[0]
    }
  }

  @discardableResult
  func setSelectedPromptPresetID(_ presetID: String) -> Bool {
    queue.sync {
      let presets = loadPromptPresetsLocked()
      guard presets.contains(where: { $0.id == presetID }) else { return false }
      userDefaults.set(presetID, forKey: Constants.selectedPromptPresetIDKey)
      return true
    }
  }

  @discardableResult
  func updatePromptPreset(
    id: String,
    name: String,
    instruction: String
  ) -> VoiceLLMPromptPreset? {
    queue.sync {
      var presets = loadPromptPresetsLocked()
      guard let index = presets.firstIndex(where: { $0.id == id }) else { return nil }
      let fallback = presets[index]
      presets[index].name = sanitizedPresetName(name, fallback: fallback.name)
      presets[index].instruction = sanitizedPresetInstruction(instruction, fallback: fallback.instruction)
      savePromptPresetsLocked(presets)
      return presets[index]
    }
  }

  func resetPromptPresetsToDefault() {
    queue.sync {
      let defaults = VoiceLLMPromptPreset.defaultPresets
      savePromptPresetsLocked(defaults)
      if let first = defaults.first {
        userDefaults.set(first.id, forKey: Constants.selectedPromptPresetIDKey)
      }
    }
  }

  func cachedModelIDs() -> [String] {
    queue.sync {
      guard let data = userDefaults.data(forKey: Constants.cachedModelsKey) else { return [] }
      let decoder = JSONDecoder()
      return (try? decoder.decode([String].self, from: data)) ?? []
    }
  }

  func cachedModelsUpdatedAt() -> TimeInterval? {
    queue.sync {
      userDefaults.object(forKey: Constants.cachedModelsUpdatedAtKey) as? TimeInterval
    }
  }

  func setCachedModelIDs(_ modelIDs: [String]) {
    queue.sync {
      let normalized = Array(Set(modelIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).filter { !$0.isEmpty }.sorted()
      let encoder = JSONEncoder()
      if let data = try? encoder.encode(normalized) {
        userDefaults.set(data, forKey: Constants.cachedModelsKey)
      }
      userDefaults.set(Date().timeIntervalSince1970, forKey: Constants.cachedModelsUpdatedAtKey)
    }
  }
}

private extension VoiceLLMSettingsStore {
  func byokBaseURLKeyLocked(for provider: VoiceLLMProvider) -> String {
    Constants.byokBaseURLKeyPrefix + provider.rawValue
  }

  func byokModelKeyLocked(for provider: VoiceLLMProvider) -> String {
    Constants.byokModelKeyPrefix + provider.rawValue
  }

  func loadByokBaseURLLocked(for provider: VoiceLLMProvider) -> String {
    let providerKey = byokBaseURLKeyLocked(for: provider)
    let stored = (userDefaults.string(forKey: providerKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !stored.isEmpty {
      return stored
    }

    // 兼容旧版本：旧版本只有一份 baseURL，这里迁移到当前 provider。
    let legacy = (userDefaults.string(forKey: Constants.byokBaseURLKeyLegacy) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !legacy.isEmpty {
      userDefaults.set(legacy, forKey: providerKey)
      userDefaults.removeObject(forKey: Constants.byokBaseURLKeyLegacy)
      return legacy
    }
    return provider.defaultBaseURL
  }

  func saveByokBaseURLLocked(_ baseURL: String, for provider: VoiceLLMProvider) {
    let providerKey = byokBaseURLKeyLocked(for: provider)
    userDefaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: providerKey)
    userDefaults.removeObject(forKey: Constants.byokBaseURLKeyLegacy)
  }

  func loadByokModelLocked(for provider: VoiceLLMProvider) -> String {
    let providerKey = byokModelKeyLocked(for: provider)
    let stored = (userDefaults.string(forKey: providerKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !stored.isEmpty {
      return stored
    }

    // 兼容旧版本：旧版本只有一份 model，这里迁移到当前 provider。
    let legacy = (userDefaults.string(forKey: Constants.byokModelKeyLegacy) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !legacy.isEmpty {
      userDefaults.set(legacy, forKey: providerKey)
      userDefaults.removeObject(forKey: Constants.byokModelKeyLegacy)
      return legacy
    }
    return provider.defaultModel
  }

  func saveByokModelLocked(_ model: String, for provider: VoiceLLMProvider) {
    let providerKey = byokModelKeyLocked(for: provider)
    userDefaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: providerKey)
    userDefaults.removeObject(forKey: Constants.byokModelKeyLegacy)
  }

  func loadPromptPresetsLocked() -> [VoiceLLMPromptPreset] {
    if let data = userDefaults.data(forKey: Constants.promptPresetsKey),
      let decoded = try? JSONDecoder().decode([VoiceLLMPromptPreset].self, from: data),
      !decoded.isEmpty
    {
      let normalized = normalizedPromptPresets(decoded)
      if normalized != decoded {
        savePromptPresetsLocked(normalized)
      }
      _ = selectedPromptPresetIDLocked(presets: normalized)
      return normalized
    }

    let defaults = VoiceLLMPromptPreset.defaultPresets
    savePromptPresetsLocked(defaults)
    if let first = defaults.first {
      userDefaults.set(first.id, forKey: Constants.selectedPromptPresetIDKey)
    }
    return defaults
  }

  func savePromptPresetsLocked(_ presets: [VoiceLLMPromptPreset]) {
    guard let data = try? JSONEncoder().encode(presets) else { return }
    userDefaults.set(data, forKey: Constants.promptPresetsKey)
  }

  func selectedPromptPresetIDLocked(presets: [VoiceLLMPromptPreset]) -> String {
    let storedID = (userDefaults.string(forKey: Constants.selectedPromptPresetIDKey) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if presets.contains(where: { $0.id == storedID }) {
      return storedID
    }
    let fallback = presets[0].id
    userDefaults.set(fallback, forKey: Constants.selectedPromptPresetIDKey)
    return fallback
  }

  func normalizedPromptPresets(_ presets: [VoiceLLMPromptPreset]) -> [VoiceLLMPromptPreset] {
    let mapped = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
    return VoiceLLMPromptPreset.defaultPresets.map { preset in
      guard let stored = mapped[preset.id] else { return preset }
      return VoiceLLMPromptPreset(
        id: preset.id,
        name: sanitizedPresetName(stored.name, fallback: preset.name),
        instruction: sanitizedPresetInstruction(stored.instruction, fallback: preset.instruction)
      )
    }
  }

  func sanitizedPresetName(_ name: String, fallback: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }
    return String(trimmed.prefix(20))
  }

  func sanitizedPresetInstruction(_ instruction: String, fallback: String) -> String {
    let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }
    return String(trimmed.prefix(240))
  }

  func llmEnabledLocked() -> Bool {
    // 兼容旧版本：未写入开关时，默认保持“开启”以避免行为突变。
    if userDefaults.object(forKey: Constants.llmEnabledKey) == nil {
      return true
    }
    return userDefaults.bool(forKey: Constants.llmEnabledKey)
  }

  func authModeLocked() -> VoiceLLMAuthMode {
    let raw = userDefaults.string(forKey: Constants.authModeKey) ?? VoiceLLMAuthMode.proxy.rawValue
    return VoiceLLMAuthMode(rawValue: raw) ?? .proxy
  }

  func providerLocked() -> VoiceLLMProvider {
    let raw = userDefaults.string(forKey: Constants.providerKey) ?? VoiceLLMProvider.openAI.rawValue
    return VoiceLLMProvider(rawValue: raw) ?? .openAI
  }

  func keychainAccountLocked(for provider: VoiceLLMProvider) -> String {
    Constants.keychainAccountPrefix + provider.rawValue
  }

  func keychainQueryLocked(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Constants.keychainService,
      kSecAttrAccount as String: account
    ]
  }

  func readRawAPIKeyLocked(account: String) -> String? {
    var query = keychainQueryLocked(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func saveRawAPIKeyLocked(_ apiKey: String?, account: String) {
    let query = keychainQueryLocked(account: account)
    SecItemDelete(query as CFDictionary)
    guard let apiKey, !apiKey.isEmpty else { return }
    var insert = query
    insert[kSecValueData as String] = apiKey.data(using: .utf8)
    SecItemAdd(insert as CFDictionary, nil)
  }

  // 兼容旧版本：旧版本只保存一把 key，这里在首次读取时迁移到当前 provider 分桶。
  func readAPIKeyLocked(for provider: VoiceLLMProvider) -> String? {
    let providerAccount = keychainAccountLocked(for: provider)
    if let providerKey = readRawAPIKeyLocked(account: providerAccount), !providerKey.isEmpty {
      return providerKey
    }

    if let legacy = readRawAPIKeyLocked(account: Constants.keychainAccountLegacy), !legacy.isEmpty {
      saveRawAPIKeyLocked(legacy, account: providerAccount)
      saveRawAPIKeyLocked(nil, account: Constants.keychainAccountLegacy)
      return legacy
    }
    return nil
  }

  func saveAPIKeyLocked(_ apiKey: String?, for provider: VoiceLLMProvider) {
    let providerAccount = keychainAccountLocked(for: provider)
    saveRawAPIKeyLocked(apiKey, account: providerAccount)
    // 清理旧账户，避免未来再次误读。
    saveRawAPIKeyLocked(nil, account: Constants.keychainAccountLegacy)
  }
}

enum VoiceLLMTask: String {
  case speakToEdit = "speak_to_edit"
  case translation = "translation"
}

enum VoiceLLMServiceError: LocalizedError {
  case proxyEndpointMissing
  case proxyModelsEndpointMissing
  case byokEndpointMissing
  case byokAPIKeyMissing
  case modelListUnavailable
  case invalidResponse
  case emptyResponse
  case requestFailed(message: String)

  var errorDescription: String? {
    switch self {
    case .proxyEndpointMissing:
      return "服务端代理地址未配置"
    case .proxyModelsEndpointMissing:
      return "代理模型列表地址未配置"
    case .byokEndpointMissing:
      return "BYOK Base URL 未配置"
    case .byokAPIKeyMissing:
      return "BYOK API Key 未配置"
    case .modelListUnavailable:
      return "未读取到可用模型列表"
    case .invalidResponse:
      return "LLM 返回格式异常"
    case .emptyResponse:
      return "LLM 返回为空"
    case .requestFailed(let message):
      return "LLM 请求失败：\(message)"
    }
  }
}

final class VoiceLLMService {
  static let shared = VoiceLLMService()

  private let settingsStore: VoiceLLMSettingsStore
  private let session: URLSession

  init(settingsStore: VoiceLLMSettingsStore = .shared, session: URLSession = .shared) {
    self.settingsStore = settingsStore
    self.session = session
  }

  func transform(
    task: VoiceLLMTask,
    sourceText: String,
    instruction: String?,
    localeIdentifier: String?
  ) async throws -> String {
    let config = settingsStore.runtimeConfig()
    let userInstruction = normalizeUserInstruction(instruction)
    let proxyInstruction = buildProxyInstruction(task: task, userInstruction: userInstruction)
    switch config.authMode {
    case .proxy:
      return try await requestViaProxy(
        task: task,
        sourceText: sourceText,
        instruction: proxyInstruction,
        localeIdentifier: localeIdentifier,
        config: config
      )
    case .byok:
      return try await requestViaByok(
        task: task,
        sourceText: sourceText,
        instruction: userInstruction,
        localeIdentifier: localeIdentifier,
        config: config
      )
    }
  }

  func fetchAvailableModels() async throws -> [String] {
    let config = settingsStore.runtimeConfig()
    switch config.authMode {
    case .proxy:
      return try await requestModelListViaProxy(config: config)
    case .byok:
      return try await requestModelListViaByok(config: config)
    }
  }

  func fetchOfficialCatalogModels(provider: VoiceLLMProvider) async throws -> [String] {
    let sourceURLs = provider.officialCatalogURLs
    guard !sourceURLs.isEmpty else {
      throw VoiceLLMServiceError.modelListUnavailable
    }

    var lastError: Error?
    for source in sourceURLs {
      do {
        let modelIDs = try await requestOfficialCatalogModels(
          sourceURLString: source,
          provider: provider
        )
        if !modelIDs.isEmpty {
          return prioritizeModelIDs(modelIDs, provider: provider)
        }
      } catch {
        lastError = error
      }
    }

    if let lastError {
      throw VoiceLLMServiceError.requestFailed(message: "官方模型页面抓取失败：\(lastError.localizedDescription)")
    }
    throw VoiceLLMServiceError.modelListUnavailable
  }
}

private extension VoiceLLMService {
  struct ProxyRequestBody: Codable {
    let task: String
    let sourceText: String
    let instruction: String?
    let localeIdentifier: String?
    let model: String?
  }

  struct ProxyResponseBody: Codable {
    let text: String
  }

  struct ChatCompletionsRequestBody: Codable {
    struct Message: Codable {
      let role: String
      let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
  }

  struct ChatCompletionsResponseBody: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable {
        struct ContentPart: Decodable {
          let text: String?
        }
        let textContent: String

        enum CodingKeys: String, CodingKey {
          case content
        }

        init(from decoder: Decoder) throws {
          let container = try decoder.container(keyedBy: CodingKeys.self)
          if let rawString = try? container.decode(String.self, forKey: .content) {
            textContent = rawString
            return
          }
          if let parts = try? container.decode([ContentPart].self, forKey: .content) {
            textContent = parts.compactMap(\.text).joined()
            return
          }
          textContent = ""
        }
      }
      let message: Message
    }
    let choices: [Choice]
  }

  struct ErrorResponseBody: Decodable {
    struct ErrorMessage: Decodable {
      let message: String?
    }
    let error: ErrorMessage?
    let message: String?
  }

  struct ModelListResponseBody: Decodable {
    struct ModelItem: Decodable {
      let id: String?
      let name: String?

      enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownedBy = "owned_by"
      }

      init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
          let value = try? single.decode(String.self)
        {
          id = value
          name = nil
          return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
      }
    }

    let data: [ModelItem]?
    let models: [ModelItem]?
  }

  func requestViaProxy(
    task: VoiceLLMTask,
    sourceText: String,
    instruction: String?,
    localeIdentifier: String?,
    config: VoiceLLMRuntimeConfig
  ) async throws -> String {
    guard !config.proxyEndpoint.isEmpty else {
      throw VoiceLLMServiceError.proxyEndpointMissing
    }
    guard let endpointURL = URL(string: config.proxyEndpoint) else {
      throw VoiceLLMServiceError.requestFailed(message: "代理地址无效")
    }

    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 25
    let body = ProxyRequestBody(
      task: task.rawValue,
      sourceText: sourceText,
      instruction: instruction,
      localeIdentifier: localeIdentifier,
      model: config.model.isEmpty ? nil : config.model
    )
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceLLMServiceError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = decodeErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
      throw VoiceLLMServiceError.requestFailed(message: message)
    }
    let payload = try JSONDecoder().decode(ProxyResponseBody.self, from: data)
    let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw VoiceLLMServiceError.emptyResponse }
    return text
  }

  func requestViaByok(
    task: VoiceLLMTask,
    sourceText: String,
    instruction: String?,
    localeIdentifier: String?,
    config: VoiceLLMRuntimeConfig
  ) async throws -> String {
    let baseURL = config.byokBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !baseURL.isEmpty else {
      throw VoiceLLMServiceError.byokEndpointMissing
    }
    guard let apiKey = config.apiKey, !apiKey.isEmpty else {
      throw VoiceLLMServiceError.byokAPIKeyMissing
    }
    let endpointString: String
    if baseURL.hasSuffix("/") {
      endpointString = baseURL + "chat/completions"
    } else {
      endpointString = baseURL + "/chat/completions"
    }
    guard let endpointURL = URL(string: endpointString) else {
      throw VoiceLLMServiceError.requestFailed(message: "BYOK 地址无效")
    }

    let prompts = buildPrompts(
      task: task,
      sourceText: sourceText,
      instruction: instruction,
      localeIdentifier: localeIdentifier
    )
    let model = config.model.isEmpty ? config.provider.defaultModel : config.model
    let requestBody = ChatCompletionsRequestBody(
      model: model,
      messages: [
        .init(role: "system", content: prompts.systemPrompt),
        .init(role: "user", content: prompts.userPrompt)
      ],
      temperature: 0.2
    )

    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 25
    request.httpBody = try JSONEncoder().encode(requestBody)

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceLLMServiceError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = decodeErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
      throw VoiceLLMServiceError.requestFailed(message: message)
    }

    let payload = try JSONDecoder().decode(ChatCompletionsResponseBody.self, from: data)
    let text = payload.choices.first?.message.textContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !text.isEmpty else { throw VoiceLLMServiceError.emptyResponse }
    return text
  }

  func requestModelListViaProxy(config: VoiceLLMRuntimeConfig) async throws -> [String] {
    let endpointString: String
    if !config.proxyModelsEndpoint.isEmpty {
      endpointString = config.proxyModelsEndpoint
    } else {
      endpointString = inferProxyModelsEndpoint(from: config.proxyEndpoint)
    }
    guard !endpointString.isEmpty else {
      if config.proxyEndpoint.isEmpty {
        throw VoiceLLMServiceError.proxyEndpointMissing
      }
      throw VoiceLLMServiceError.proxyModelsEndpointMissing
    }
    guard let endpointURL = URL(string: endpointString) else {
      throw VoiceLLMServiceError.requestFailed(message: "代理模型列表地址无效")
    }

    var request = URLRequest(url: endpointURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 20

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceLLMServiceError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = decodeErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
      throw VoiceLLMServiceError.requestFailed(message: message)
    }
    return try decodeModelIDs(data: data)
  }

  func requestModelListViaByok(config: VoiceLLMRuntimeConfig) async throws -> [String] {
    let baseURL = config.byokBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !baseURL.isEmpty else {
      throw VoiceLLMServiceError.byokEndpointMissing
    }
    guard let apiKey = config.apiKey, !apiKey.isEmpty else {
      throw VoiceLLMServiceError.byokAPIKeyMissing
    }
    let endpointString: String
    if baseURL.hasSuffix("/") {
      endpointString = baseURL + "models"
    } else {
      endpointString = baseURL + "/models"
    }
    guard let endpointURL = URL(string: endpointString) else {
      throw VoiceLLMServiceError.requestFailed(message: "BYOK 模型列表地址无效")
    }

    var request = URLRequest(url: endpointURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceLLMServiceError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = decodeErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
      throw VoiceLLMServiceError.requestFailed(message: message)
    }
    return try decodeModelIDs(data: data)
  }

  func decodeModelIDs(data: Data) throws -> [String] {
    let payload = try JSONDecoder().decode(ModelListResponseBody.self, from: data)
    var values: [String] = []
    let arrays = [payload.data ?? [], payload.models ?? []]
    for array in arrays {
      for item in array {
        let id = (item.id ?? item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty {
          values.append(id)
        }
      }
    }
    let deduped = Array(Set(values)).sorted()
    guard !deduped.isEmpty else { throw VoiceLLMServiceError.modelListUnavailable }
    return deduped
  }

  func inferProxyModelsEndpoint(from endpoint: String) -> String {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    if trimmed.hasSuffix("/transform") {
      return String(trimmed.dropLast("/transform".count)) + "/models"
    }
    if trimmed.hasSuffix("/") {
      return trimmed + "models"
    }
    return trimmed + "/models"
  }

  func requestOfficialCatalogModels(
    sourceURLString: String,
    provider: VoiceLLMProvider
  ) async throws -> [String] {
    guard let sourceURL = URL(string: sourceURLString) else {
      throw VoiceLLMServiceError.requestFailed(message: "官方模型地址无效")
    }
    var request = URLRequest(url: sourceURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw VoiceLLMServiceError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw VoiceLLMServiceError.requestFailed(message: "HTTP \(httpResponse.statusCode)")
    }

    // 尝试先按 JSON 模型列表解析；不命中再按文档文本解析。
    if let jsonModelIDs = try? decodeModelIDs(data: data), !jsonModelIDs.isEmpty {
      return jsonModelIDs
    }
    guard let text = decodeTextPayload(data: data), !text.isEmpty else {
      throw VoiceLLMServiceError.modelListUnavailable
    }
    let modelIDs = extractModelIDs(from: text, provider: provider)
    guard !modelIDs.isEmpty else {
      throw VoiceLLMServiceError.modelListUnavailable
    }
    return modelIDs
  }

  func decodeTextPayload(data: Data) -> String? {
    if let text = String(data: data, encoding: .utf8) {
      return text
    }
    if let text = String(data: data, encoding: .unicode) {
      return text
    }
    if let text = String(data: data, encoding: .ascii) {
      return text
    }
    return String(data: data, encoding: .isoLatin1)
  }

  func extractModelIDs(from text: String, provider: VoiceLLMProvider) -> [String] {
    let patterns: [String]
    switch provider {
    case .openAI:
      patterns = [
        "\\b(?:gpt|o[134]|text-embedding|whisper)-[a-z0-9\\.-]+\\b"
      ]
    case .qwen:
      patterns = [
        "\\bqwen[a-z0-9\\.-]+\\b"
      ]
    case .glm:
      patterns = [
        "\\bglm-[a-z0-9\\.-]+\\b"
      ]
    case .baiduQianfan:
      patterns = [
        "\\bernie-[a-z0-9\\.-]+\\b"
      ]
    case .doubao:
      patterns = [
        "\\bdoubao-[a-z0-9\\.-]+\\b"
      ]
    case .tencentHunyuan:
      patterns = [
        "\\bhunyuan-[a-z0-9\\.-]+\\b"
      ]
    case .gemini:
      patterns = [
        "\\bgemini-[a-z0-9\\.-]+\\b"
      ]
    case .deepseek:
      patterns = [
        "\\bdeepseek-[a-z0-9\\.-]+\\b"
      ]
    case .claude:
      patterns = [
        "\\bclaude-[a-z0-9\\.-]+\\b"
      ]
    case .minimax:
      patterns = [
        "\\bminimax-[a-z0-9\\.-]+\\b",
        "\\babab[a-z0-9\\.-]+\\b"
      ]
    case .moonshot:
      patterns = [
        "\\bmoonshot-[a-z0-9\\.-]+\\b",
        "\\bkimi-[a-z0-9\\.-]+\\b"
      ]
    case .custom:
      return []
    }

    var candidates: [String] = []
    for pattern in patterns {
      candidates.append(contentsOf: regexMatches(pattern: pattern, in: text))
    }
    let normalized = candidates
      .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return prioritizeModelIDs(filterModelIDs(normalized, provider: provider), provider: provider)
  }

  func filterModelIDs(_ modelIDs: [String], provider: VoiceLLMProvider) -> [String] {
    let unique = Array(Set(modelIDs))
    switch provider {
    case .openAI:
      return unique.filter { id in
        guard !id.contains("and-"), !id.contains("audio-preview"), !id.contains("vision-preview") else {
          return false
        }
        return id.hasPrefix("gpt-") || id.hasPrefix("o1-") || id.hasPrefix("o3-") || id.hasPrefix("o4-")
      }
    case .qwen:
      return unique.filter { id in
        guard id.contains("-"), !id.contains("api"), !id.contains("reference"),
          !id.contains("guide"), !id.contains("doc"), !id.contains("case")
        else {
          return false
        }
        return id.hasPrefix("qwen-")
      }
    case .glm:
      return unique.filter { id in
        guard id.hasPrefix("glm-"), !id.contains("-new"), !id.contains("api") else { return false }
        return true
      }
    case .baiduQianfan:
      return unique.filter { id in
        id.hasPrefix("ernie-")
      }
    case .doubao:
      return unique.filter { id in
        id.hasPrefix("doubao-")
      }
    case .tencentHunyuan:
      return unique.filter { id in
        id.hasPrefix("hunyuan-")
      }
    case .gemini:
      return unique.filter { id in
        id.hasPrefix("gemini-")
      }
    case .deepseek:
      return unique.filter { id in
        id.hasPrefix("deepseek-")
      }
    case .claude:
      return unique.filter { id in
        id.hasPrefix("claude-")
      }
    case .minimax:
      return unique.filter { id in
        id.hasPrefix("minimax-") || id.hasPrefix("abab")
      }
    case .moonshot:
      return unique.filter { id in
        id.hasPrefix("moonshot-") || id.hasPrefix("kimi-")
      }
    case .custom:
      return unique
    }
  }

  func prioritizeModelIDs(_ modelIDs: [String], provider: VoiceLLMProvider) -> [String] {
    var values = Array(Set(modelIDs)).sorted()
    let defaults = ([provider.defaultModel] + provider.staticModelCandidates).map { $0.lowercased() }
    for target in defaults.reversed() {
      guard let index = values.firstIndex(of: target) else { continue }
      let value = values.remove(at: index)
      values.insert(value, at: 0)
    }
    return Array(values.prefix(80))
  }

  func regexMatches(pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, options: [], range: range)
    return matches.compactMap { match in
      guard let swiftRange = Range(match.range, in: text) else { return nil }
      return String(text[swiftRange])
    }
  }

  func decodeErrorMessage(data: Data) -> String? {
    guard let payload = try? JSONDecoder().decode(ErrorResponseBody.self, from: data) else { return nil }
    if let message = payload.error?.message, !message.isEmpty {
      return message
    }
    if let message = payload.message, !message.isEmpty {
      return message
    }
    return nil
  }

  func normalizeUserInstruction(_ instruction: String?) -> String? {
    let value = (instruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  func buildProxyInstruction(task: VoiceLLMTask, userInstruction: String?) -> String? {
    let preset = settingsStore.selectedPromptPreset()
    let presetInstruction = sanitizedPresetInstruction(preset.instruction)
    let role: String
    switch task {
    case .speakToEdit:
      role = "输入法文本整理助手"
    case .translation:
      role = "输入法双语翻译整理助手"
    }

    var instruction = """
    角色：\(role)
    目标风格：\(preset.name)
    风格要求：\(presetInstruction)
    """
    if let userInstruction, !userInstruction.isEmpty {
      instruction += """

      用户附加要求：\(userInstruction)
      """
    }
    return instruction
  }

  func sanitizedPresetInstruction(_ rawValue: String) -> String {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty {
      return "保留原意并修正语法、标点与结构。"
    }
    return value
  }

  func buildPrompts(
    task: VoiceLLMTask,
    sourceText: String,
    instruction: String?,
    localeIdentifier: String?
  ) -> (systemPrompt: String, userPrompt: String) {
    let preset = settingsStore.selectedPromptPreset()
    let presetInstruction = sanitizedPresetInstruction(preset.instruction)
    let localeLine = "locale=\(localeIdentifier ?? "unknown")"
    let normalizedInstruction = normalizeUserInstruction(instruction)
    switch task {
    case .speakToEdit:
      let systemPrompt = """
      你是一个输入法文本整理助手。
      用户将给你一段口述转写文本，你需要把文本整理成“\(preset.name)”风格。
      风格要求：\(presetInstruction)
      你必须遵守以下约束：
      1) 你必须保留原意，不得编造事实，不得引入原文没有的新信息。
      2) 你应优先修正口语化、错别字、标点和结构问题。
      3) 你必须只输出最终文本，不要解释，不要步骤，不要 markdown。
      """
      var userPrompt = """
      \(localeLine)
      原文:
      \(sourceText)
      """
      if let normalizedInstruction, !normalizedInstruction.isEmpty {
        userPrompt += """

        用户附加要求:
        \(normalizedInstruction)
        """
      }
      return (systemPrompt, userPrompt)
    case .translation:
      let systemPrompt = """
      你是一个输入法双语翻译整理助手。
      用户将给你一段口述转写文本，你需要先完成中英文翻译，再整理成“\(preset.name)”风格。
      风格要求：\(presetInstruction)
      你必须遵守以下约束：
      1) 你必须保留原意和语气，不得编造事实。
      2) 你应在中文和英文之间做准确翻译；如果文本不适合翻译，你可以保持原文并做最小整理。
      3) 你必须只输出最终文本，不要解释，不要步骤，不要 markdown。
      """
      var userPrompt = """
      \(localeLine)
      待翻译文本:
      \(sourceText)
      """
      if let normalizedInstruction, !normalizedInstruction.isEmpty {
        userPrompt += """

        用户附加要求:
        \(normalizedInstruction)
        """
      }
      return (systemPrompt, userPrompt)
    }
  }
}

final class VoiceSpeechRecognizerEngine {
  enum Route: String {
    case appleOnDevice
    case appleNetwork
    case whisperOnDevice
    case cloudNetwork
  }

  struct StartStrategy {
    let localeIdentifier: String
    let prefersOnDevice: Bool
    let allowNetworkFallback: Bool
    let allowWhisperFallback: Bool
    let enginePreference: VoiceASREnginePreference
    let cloudMode: VoiceASRMode
    let cloudRuntimeConfig: VoiceASRRuntimeConfig
    let retryCount: Int
    let whisperModelID: String?
    let contextualStrings: [String]

    static func recommended(for localeIdentifier: String) -> StartStrategy {
      let normalized = localeIdentifier.lowercased()
      let prefersOnDevice = normalized.hasPrefix("zh") || normalized.hasPrefix("en") || normalized.hasPrefix("ja")
      let selectedWhisperModel = VoiceWhisperModelStore.shared.selectedDownloadedModel()
      let contextualStrings = VoicePersonalDictionaryStore.shared.hotwords(limit: 40)
      let cloudRuntimeConfig = VoiceASRSettingsStore.shared.runtimeConfig()
      return StartStrategy(
        localeIdentifier: localeIdentifier,
        prefersOnDevice: prefersOnDevice,
        allowNetworkFallback: true,
        allowWhisperFallback: selectedWhisperModel != nil,
        enginePreference: cloudRuntimeConfig.enginePreference,
        cloudMode: cloudRuntimeConfig.mode,
        cloudRuntimeConfig: cloudRuntimeConfig,
        retryCount: 1,
        whisperModelID: selectedWhisperModel?.modelID,
        contextualStrings: contextualStrings
      )
    }
  }

  enum EngineError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case recognizerUnavailable
    case inputNodeUnavailable
    case onDeviceRecognitionUnavailable
    case networkUnavailable
    case whisperUnavailable
    case emptyAudio
    case runtimeFailure(message: String)

    var errorDescription: String? {
      switch self {
      case .microphonePermissionDenied:
        return "麦克风权限未开启"
      case .speechPermissionDenied:
        return "语音识别权限未开启"
      case .recognizerUnavailable:
        return "语音识别服务不可用"
      case .inputNodeUnavailable:
        return "音频输入不可用"
      case .onDeviceRecognitionUnavailable:
        return "设备暂不支持离线语音识别"
      case .networkUnavailable:
        return "网络不可用，无法使用在线识别"
      case .whisperUnavailable:
        return "Whisper 离线引擎不可用"
      case .emptyAudio:
        return "未检测到有效语音"
      case .runtimeFailure(let message):
        return message
      }
    }
  }

  private enum ActivePipeline {
    case none
    case apple(requiresOnDevice: Bool)
    case whisper(model: String?)
    case cloud(config: VoiceASRRuntimeConfig)
  }

  private let audioEngine = AVAudioEngine()
  private var recognitionTask: SFSpeechRecognitionTask?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognizer: SFSpeechRecognizer?
  private let networkMonitor = NWPathMonitor()
  private let networkMonitorQueue = DispatchQueue(label: "nanomouse.voice.network")
  private let whisperBufferQueue = DispatchQueue(label: "nanomouse.voice.whisper.buffer")
  private var onResultHandler: ((String, Bool) -> Void)?
  private var onErrorHandler: ((EngineError) -> Void)?
  private var activePipeline: ActivePipeline = .none
  private var whisperSamples: [Float] = []
  private var whisperConverter: AVAudioConverter?
  private var whisperOutputFormat: AVAudioFormat?
  private var whisperTranscribeTask: Task<Void, Never>?
  private var cloudTranscribeTask: Task<Void, Never>?
  #if canImport(WhisperKit)
  private var whisperKit: WhisperKit?
  private var whisperLoadedModelID: String?
  #endif
  private let cloudASRService: VoiceASRService
  private var isNetworkAvailable = true
  private var activeLocaleIdentifier = "zh-CN"

  init(cloudASRService: VoiceASRService = .shared) {
    self.cloudASRService = cloudASRService
    networkMonitor.pathUpdateHandler = { [weak self] path in
      self?.isNetworkAvailable = (path.status == .satisfied)
    }
    networkMonitor.start(queue: networkMonitorQueue)
  }

  deinit {
    networkMonitor.cancel()
    stop(cancel: true)
  }

  func start(
    localeIdentifier: String,
    strategy: StartStrategy? = nil,
    onResult: @escaping (String, Bool) -> Void,
    onRouteChanged: @escaping (Route) -> Void = { _ in },
    onError: @escaping (EngineError) -> Void = { _ in }
  ) async throws {
    try await requestMicrophonePermission()
    stop(cancel: true)
    onResultHandler = onResult
    onErrorHandler = onError

    let resolvedStrategy = strategy ?? .recommended(for: localeIdentifier)
    activeLocaleIdentifier = resolvedStrategy.localeIdentifier
    let attempts = max(1, resolvedStrategy.retryCount + 1)
    var startErrors: [EngineError] = []
    var canUseSpeechFramework = false

    let speechRecognitionNeeded: Bool
    switch resolvedStrategy.enginePreference {
    case .apple:
      speechRecognitionNeeded = true
    case .auto:
      speechRecognitionNeeded = resolvedStrategy.prefersOnDevice || resolvedStrategy.allowNetworkFallback
    case .whisper, .cloud:
      speechRecognitionNeeded = false
    }

    if speechRecognitionNeeded {
      do {
        try await requestSpeechPermission()
        canUseSpeechFramework = true
      } catch let error as EngineError {
        startErrors.append(error)
      } catch {
        startErrors.append(.runtimeFailure(message: error.localizedDescription))
      }
    }

    switch resolvedStrategy.enginePreference {
    case .cloud:
      do {
        try startCloudRecording(config: resolvedStrategy.cloudRuntimeConfig)
        activePipeline = .cloud(config: resolvedStrategy.cloudRuntimeConfig)
        onRouteChanged(.cloudNetwork)
        return
      } catch let error as EngineError {
        startErrors.append(error)
      } catch {
        startErrors.append(.runtimeFailure(message: error.localizedDescription))
      }
      throw composeStartError(from: startErrors)

    case .whisper:
      guard let whisperModelID = resolvedStrategy.whisperModelID, !whisperModelID.isEmpty else {
        throw EngineError.runtimeFailure(message: "当前固定使用 Whisper，但未下载可用 Whisper 模型。")
      }
      do {
        try startWhisperRecording(modelID: whisperModelID)
        activePipeline = .whisper(model: whisperModelID)
        onRouteChanged(.whisperOnDevice)
        return
      } catch let error as EngineError {
        startErrors.append(error)
      } catch {
        startErrors.append(.runtimeFailure(message: error.localizedDescription))
      }
      throw composeStartError(from: startErrors)

    case .apple:
      guard canUseSpeechFramework else {
        throw composeStartError(from: startErrors)
      }
      if tryStartApplePipelines(
        strategy: resolvedStrategy,
        attempts: attempts,
        onResult: onResult,
        onRouteChanged: onRouteChanged,
        onError: onError,
        startErrors: &startErrors
      ) {
        return
      }
      throw composeStartError(from: startErrors)

    case .auto:
      if resolvedStrategy.cloudMode == .preferred {
        do {
          try startCloudRecording(config: resolvedStrategy.cloudRuntimeConfig)
          activePipeline = .cloud(config: resolvedStrategy.cloudRuntimeConfig)
          onRouteChanged(.cloudNetwork)
          return
        } catch let error as EngineError {
          startErrors.append(error)
        } catch {
          startErrors.append(.runtimeFailure(message: error.localizedDescription))
        }
      }

      // 自动模式：优先离线 Apple，再回退在线 Apple，最后回退 Whisper 离线。
      if canUseSpeechFramework,
        tryStartApplePipelines(
          strategy: resolvedStrategy,
          attempts: attempts,
          onResult: onResult,
          onRouteChanged: onRouteChanged,
          onError: onError,
          startErrors: &startErrors
        )
      {
        return
      }

      if resolvedStrategy.allowWhisperFallback, let whisperModelID = resolvedStrategy.whisperModelID {
        do {
          try startWhisperRecording(modelID: whisperModelID)
          activePipeline = .whisper(model: whisperModelID)
          onRouteChanged(.whisperOnDevice)
          return
        } catch let error as EngineError {
          startErrors.append(error)
        } catch {
          startErrors.append(.runtimeFailure(message: error.localizedDescription))
        }
      }

      if resolvedStrategy.cloudMode == .fallback {
        do {
          try startCloudRecording(config: resolvedStrategy.cloudRuntimeConfig)
          activePipeline = .cloud(config: resolvedStrategy.cloudRuntimeConfig)
          onRouteChanged(.cloudNetwork)
          return
        } catch let error as EngineError {
          startErrors.append(error)
        } catch {
          startErrors.append(.runtimeFailure(message: error.localizedDescription))
        }
      }

      throw composeStartError(from: startErrors)
    }
  }

  func stop(cancel: Bool) {
    if cancel {
      whisperTranscribeTask?.cancel()
      whisperTranscribeTask = nil
      cloudTranscribeTask?.cancel()
      cloudTranscribeTask = nil
    }
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    audioEngine.inputNode.removeTap(onBus: 0)

    switch activePipeline {
    case .apple:
      if cancel {
        recognitionTask?.cancel()
      } else {
        recognitionRequest?.endAudio()
      }
    case .whisper(let model):
      if cancel {
        clearWhisperState()
      } else {
        transcribeWhisperResult(using: model)
      }
    case .cloud(let config):
      if cancel {
        clearWhisperState()
      } else {
        transcribeCloudResult(config: config)
      }
    case .none:
      break
    }

    if cancel {
      recognitionTask = nil
      recognitionRequest = nil
      recognizer = nil
      activePipeline = .none
      clearWhisperState()
    }

    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func tryStartApplePipelines(
    strategy: StartStrategy,
    attempts: Int,
    onResult: @escaping (String, Bool) -> Void,
    onRouteChanged: @escaping (Route) -> Void,
    onError: @escaping (EngineError) -> Void,
    startErrors: inout [EngineError]
  ) -> Bool {
    if strategy.prefersOnDevice {
      for _ in 0..<attempts {
        do {
          try startSpeechRecognition(
            localeIdentifier: strategy.localeIdentifier,
            requiresOnDevice: true,
            contextualStrings: strategy.contextualStrings,
            onResult: onResult,
            onError: onError
          )
          activePipeline = .apple(requiresOnDevice: true)
          onRouteChanged(.appleOnDevice)
          return true
        } catch let error as EngineError {
          startErrors.append(error)
        } catch {
          startErrors.append(.runtimeFailure(message: error.localizedDescription))
        }
      }
    }

    if strategy.allowNetworkFallback {
      if !isNetworkAvailable {
        startErrors.append(.networkUnavailable)
      } else {
        for _ in 0..<attempts {
          do {
            try startSpeechRecognition(
              localeIdentifier: strategy.localeIdentifier,
              requiresOnDevice: false,
              contextualStrings: strategy.contextualStrings,
              onResult: onResult,
              onError: onError
            )
            activePipeline = .apple(requiresOnDevice: false)
            onRouteChanged(.appleNetwork)
            return true
          } catch let error as EngineError {
            startErrors.append(error)
          } catch {
            startErrors.append(.runtimeFailure(message: error.localizedDescription))
          }
        }
      }
    }
    return false
  }

  private func startSpeechRecognition(
    localeIdentifier: String,
    requiresOnDevice: Bool,
    contextualStrings: [String],
    onResult: @escaping (String, Bool) -> Void,
    onError: @escaping (EngineError) -> Void
  ) throws {
    let locale = Locale(identifier: localeIdentifier)
    let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    guard let recognizer, recognizer.isAvailable else {
      throw EngineError.recognizerUnavailable
    }
    if requiresOnDevice && !recognizer.supportsOnDeviceRecognition {
      throw EngineError.onDeviceRecognitionUnavailable
    }
    if !requiresOnDevice && !isNetworkAvailable {
      throw EngineError.networkUnavailable
    }
    self.recognizer = recognizer

    clearWhisperState()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = requiresOnDevice
    request.contextualStrings = contextualStrings
    self.recognitionRequest = request

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    guard recordingFormat.channelCount > 0 else {
      throw EngineError.inputNodeUnavailable
    }

    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      if let result {
        let text = result.bestTranscription.formattedString
        DispatchQueue.main.async {
          onResult(text, result.isFinal)
        }
        if result.isFinal {
          self?.recognitionTask = nil
          self?.recognitionRequest = nil
          self?.activePipeline = .none
        }
      }
      if let error {
        let mappedError = self?.mapRuntimeError(error, requiresOnDevice: requiresOnDevice)
          ?? EngineError.runtimeFailure(message: error.localizedDescription)
        DispatchQueue.main.async {
          onError(mappedError)
        }
        self?.recognitionTask = nil
        self?.recognitionRequest = nil
        self?.activePipeline = .none
      }
    }
  }

  private func startWhisperRecording(modelID: String) throws {
    #if !canImport(WhisperKit)
    throw EngineError.whisperUnavailable
    #else
    guard VoiceWhisperModelStore.shared.modelFolderURL(for: modelID) != nil else {
      throw EngineError.whisperUnavailable
    }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.channelCount > 0 else {
      throw EngineError.inputNodeUnavailable
    }
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16_000,
      channels: 1,
      interleaved: false
    ) else {
      throw EngineError.runtimeFailure(message: "无法创建 Whisper 音频格式")
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw EngineError.runtimeFailure(message: "无法初始化 Whisper 音频转换器")
    }

    clearWhisperState()
    whisperOutputFormat = outputFormat
    whisperConverter = converter

    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      self?.appendWhisperBuffer(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()
    #endif
  }

  private func startCloudRecording(config: VoiceASRRuntimeConfig) throws {
    try validateCloudConfig(config)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.channelCount > 0 else {
      throw EngineError.inputNodeUnavailable
    }
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16_000,
      channels: 1,
      interleaved: false
    ) else {
      throw EngineError.runtimeFailure(message: "无法创建云端 ASR 音频格式")
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw EngineError.runtimeFailure(message: "无法初始化云端 ASR 音频转换器")
    }

    clearWhisperState()
    whisperOutputFormat = outputFormat
    whisperConverter = converter

    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      self?.appendWhisperBuffer(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()
  }

  private func validateCloudConfig(_ config: VoiceASRRuntimeConfig) throws {
    if config.mode == .disabled {
      throw EngineError.runtimeFailure(message: "在线 ASR 已关闭")
    }
    switch config.provider.directCallType {
    case .openAITranscriptions, .deepgramListen:
      let baseURL = config.byokBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      let apiKey = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if baseURL.isEmpty {
        throw EngineError.runtimeFailure(message: "在线 ASR Base URL 未配置")
      }
      if apiKey.isEmpty {
        throw EngineError.runtimeFailure(message: "在线 ASR API Key 未配置")
      }
    case .proxyOnly:
      let proxy = config.proxyEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      if proxy.isEmpty {
        throw EngineError.runtimeFailure(message: "\(config.provider.displayName) 需通过代理调用，请先配置 ASR 代理地址")
      }
    }
  }

  private func appendWhisperBuffer(_ inputBuffer: AVAudioPCMBuffer) {
    guard let converter = whisperConverter, let outputFormat = whisperOutputFormat else { return }
    let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
    let expectedFrames = max(1, Int(Double(inputBuffer.frameLength) * ratio) + 8)
    guard
      let convertedBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: AVAudioFrameCount(expectedFrames)
      )
    else {
      return
    }

    var conversionError: NSError?
    var didProvideInput = false
    let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
      if didProvideInput {
        outStatus.pointee = .noDataNow
        return nil
      }
      didProvideInput = true
      outStatus.pointee = .haveData
      return inputBuffer
    }

    if status == .error {
      if let conversionError {
        notifyError(.runtimeFailure(message: conversionError.localizedDescription))
      }
      return
    }

    guard
      convertedBuffer.frameLength > 0,
      let channelData = convertedBuffer.floatChannelData?[0]
    else {
      return
    }
    let frameLength = Int(convertedBuffer.frameLength)
    let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    whisperBufferQueue.sync {
      whisperSamples.append(contentsOf: samples)
    }
  }

  private func transcribeWhisperResult(using model: String?) {
    guard let modelID = model, !modelID.isEmpty else {
      notifyError(.whisperUnavailable)
      activePipeline = .none
      return
    }
    let samples = whisperBufferQueue.sync { whisperSamples }
    clearWhisperState()

    guard !samples.isEmpty else {
      notifyError(.emptyAudio)
      activePipeline = .none
      return
    }

    whisperTranscribeTask?.cancel()
    whisperTranscribeTask = Task { [weak self] in
      guard let self else { return }
      do {
        let text = try await self.transcribeWithWhisper(samples: samples, modelID: modelID)
        try Task.checkCancellation()
        await MainActor.run {
          self.onResultHandler?(text, true)
        }
      } catch is CancellationError {
        return
      } catch let error as EngineError {
        self.notifyError(error)
      } catch {
        self.notifyError(.runtimeFailure(message: error.localizedDescription))
      }
      self.activePipeline = .none
    }
  }

  private func transcribeCloudResult(config: VoiceASRRuntimeConfig) {
    let samples = whisperBufferQueue.sync { whisperSamples }
    clearWhisperState()

    guard !samples.isEmpty else {
      notifyError(.emptyAudio)
      activePipeline = .none
      return
    }

    cloudTranscribeTask?.cancel()
    cloudTranscribeTask = Task { [weak self] in
      guard let self else { return }
      do {
        let audioFileURL = try self.writeTemporaryWAVFile(samples: samples)
        defer {
          try? FileManager.default.removeItem(at: audioFileURL)
        }

        let text = try await self.cloudASRService.transcribe(
          audioFileURL: audioFileURL,
          localeIdentifier: self.activeLocaleIdentifier,
          config: config
        )
        try Task.checkCancellation()
        await MainActor.run {
          self.onResultHandler?(text, true)
        }
      } catch is CancellationError {
        return
      } catch let error as VoiceASRServiceError {
        self.notifyError(.runtimeFailure(message: error.localizedDescription))
      } catch {
        self.notifyError(.runtimeFailure(message: error.localizedDescription))
      }
      self.activePipeline = .none
    }
  }

  private func writeTemporaryWAVFile(samples: [Float]) throws -> URL {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("nanomouse_asr_\(UUID().uuidString)")
      .appendingPathExtension("wav")
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
      throw EngineError.runtimeFailure(message: "无法创建 WAV 输出格式")
    }
    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: format,
      frameCapacity: AVAudioFrameCount(samples.count)
    ) else {
      throw EngineError.runtimeFailure(message: "无法创建 WAV 缓冲区")
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    if let channelData = buffer.floatChannelData?[0] {
      for (index, sample) in samples.enumerated() {
        channelData[index] = sample
      }
    }
    let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
    try file.write(from: buffer)
    return tempURL
  }

  private func transcribeWithWhisper(samples: [Float], modelID: String) async throws -> String {
    #if canImport(WhisperKit)
    let whisper = try await loadWhisperKit(modelID: modelID)
    let results = try await whisper.transcribe(audioArray: samples)
    let mergedText = results
      .map(\.text)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !mergedText.isEmpty else {
      throw EngineError.emptyAudio
    }
    return mergedText
    #else
    throw EngineError.whisperUnavailable
    #endif
  }

  #if canImport(WhisperKit)
  private func loadWhisperKit(modelID: String) async throws -> WhisperKit {
    if let whisperKit, whisperLoadedModelID == modelID {
      return whisperKit
    }

    guard let folderURL = VoiceWhisperModelStore.shared.modelFolderURL(for: modelID) else {
      throw EngineError.whisperUnavailable
    }
    let config = WhisperKitConfig(
      model: modelID,
      modelFolder: folderURL.path,
      download: false
    )
    let instance = try await WhisperKit(config)
    whisperKit = instance
    whisperLoadedModelID = modelID
    return instance
  }
  #endif

  private func clearWhisperState() {
    whisperBufferQueue.sync {
      whisperSamples.removeAll(keepingCapacity: false)
    }
    whisperConverter = nil
    whisperOutputFormat = nil
  }

  private func notifyError(_ error: EngineError) {
    DispatchQueue.main.async { [weak self] in
      self?.onErrorHandler?(error)
    }
  }

  private func composeStartError(from errors: [EngineError]) -> EngineError {
    guard !errors.isEmpty else { return .recognizerUnavailable }
    if errors.count == 1, let first = errors.first {
      return first
    }
    let merged = errors
      .map(\.localizedDescription)
      .filter { !$0.isEmpty }
      .joined(separator: "; ")
    return .runtimeFailure(message: merged)
  }

  private func mapRuntimeError(_ error: Error, requiresOnDevice: Bool) -> EngineError {
    let nsError = error as NSError
    let message = nsError.localizedDescription
    let lowercased = message.lowercased()
    if !requiresOnDevice && (lowercased.contains("network") || lowercased.contains("internet")) {
      return .networkUnavailable
    }
    if message.contains("not available") {
      return .recognizerUnavailable
    }
    return .runtimeFailure(message: message)
  }

  private func requestMicrophonePermission() async throws {
    let microphoneGranted = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    guard microphoneGranted else { throw EngineError.microphonePermissionDenied }
  }

  private func requestSpeechPermission() async throws {
    let speechAuthorization = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
    guard speechAuthorization == .authorized else {
      throw EngineError.speechPermissionDenied
    }
  }
}
