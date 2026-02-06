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

enum VoiceLLMAuthMode: String, Codable, CaseIterable {
  case proxy
  case byok
}

enum VoiceLLMProvider: String, Codable, CaseIterable {
  case openAI = "openai"
  case qwen
  case glm
  case custom

  var displayName: String {
    switch self {
    case .openAI:
      return "OpenAI"
    case .qwen:
      return "Qwen"
    case .glm:
      return "智谱 GLM"
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
    case .custom:
      return ""
    }
  }

  var defaultModel: String {
    switch self {
    case .openAI:
      return "gpt-4o-mini"
    case .qwen:
      return "qwen-plus"
    case .glm:
      return "glm-4-flash"
    case .custom:
      return ""
    }
  }
}

struct VoiceLLMRuntimeConfig {
  let authMode: VoiceLLMAuthMode
  let provider: VoiceLLMProvider
  let proxyEndpoint: String
  let byokBaseURL: String
  let model: String
  let apiKey: String?
}

final class VoiceLLMSettingsStore {
  static let shared = VoiceLLMSettingsStore()

  private enum Constants {
    static let authModeKey = "voice.llm.auth.mode"
    static let providerKey = "voice.llm.provider"
    static let proxyEndpointKey = "voice.llm.proxy.endpoint"
    static let byokBaseURLKey = "voice.llm.byok.base_url"
    static let byokModelKey = "voice.llm.byok.model"
    static let keychainService = "com.XiangqingZHANG.nanomouse.voice.llm"
    static let keychainAccount = "byok_api_key"
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
      let byokBaseURLStored = (userDefaults.string(forKey: Constants.byokBaseURLKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let byokBaseURL = byokBaseURLStored.isEmpty ? provider.defaultBaseURL : byokBaseURLStored
      let modelStored = (userDefaults.string(forKey: Constants.byokModelKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let model = modelStored.isEmpty ? provider.defaultModel : modelStored
      return VoiceLLMRuntimeConfig(
        authMode: authMode,
        provider: provider,
        proxyEndpoint: proxyEndpoint,
        byokBaseURL: byokBaseURL,
        model: model,
        apiKey: self.readAPIKeyLocked()
      )
    }
  }

  func setAuthMode(_ mode: VoiceLLMAuthMode) {
    queue.sync {
      userDefaults.set(mode.rawValue, forKey: Constants.authModeKey)
    }
  }

  func setProvider(_ provider: VoiceLLMProvider) {
    queue.sync {
      userDefaults.set(provider.rawValue, forKey: Constants.providerKey)
      if (userDefaults.string(forKey: Constants.byokBaseURLKey) ?? "").isEmpty {
        userDefaults.set(provider.defaultBaseURL, forKey: Constants.byokBaseURLKey)
      }
      if (userDefaults.string(forKey: Constants.byokModelKey) ?? "").isEmpty {
        userDefaults.set(provider.defaultModel, forKey: Constants.byokModelKey)
      }
    }
  }

  func setProxyEndpoint(_ endpoint: String) {
    queue.sync {
      userDefaults.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Constants.proxyEndpointKey)
    }
  }

  func setByokBaseURL(_ baseURL: String) {
    queue.sync {
      userDefaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Constants.byokBaseURLKey)
    }
  }

  func setByokModel(_ model: String) {
    queue.sync {
      userDefaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Constants.byokModelKey)
    }
  }

  func setAPIKey(_ apiKey: String?) {
    queue.sync {
      saveAPIKeyLocked(apiKey?.trimmingCharacters(in: .whitespacesAndNewlines))
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

  func byokBaseURL() -> String {
    queue.sync {
      let provider = providerLocked()
      let stored = (userDefaults.string(forKey: Constants.byokBaseURLKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return stored.isEmpty ? provider.defaultBaseURL : stored
    }
  }

  func byokModel() -> String {
    queue.sync {
      let provider = providerLocked()
      let stored = (userDefaults.string(forKey: Constants.byokModelKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return stored.isEmpty ? provider.defaultModel : stored
    }
  }

  func apiKey() -> String? {
    queue.sync { readAPIKeyLocked() }
  }
}

private extension VoiceLLMSettingsStore {
  func authModeLocked() -> VoiceLLMAuthMode {
    let raw = userDefaults.string(forKey: Constants.authModeKey) ?? VoiceLLMAuthMode.proxy.rawValue
    return VoiceLLMAuthMode(rawValue: raw) ?? .proxy
  }

  func providerLocked() -> VoiceLLMProvider {
    let raw = userDefaults.string(forKey: Constants.providerKey) ?? VoiceLLMProvider.openAI.rawValue
    return VoiceLLMProvider(rawValue: raw) ?? .openAI
  }

  func keychainQueryLocked() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Constants.keychainService,
      kSecAttrAccount as String: Constants.keychainAccount
    ]
  }

  func readAPIKeyLocked() -> String? {
    var query = keychainQueryLocked()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func saveAPIKeyLocked(_ apiKey: String?) {
    let query = keychainQueryLocked()
    SecItemDelete(query as CFDictionary)
    guard let apiKey, !apiKey.isEmpty else { return }
    var insert = query
    insert[kSecValueData as String] = apiKey.data(using: .utf8)
    SecItemAdd(insert as CFDictionary, nil)
  }
}

enum VoiceLLMTask: String {
  case speakToEdit = "speak_to_edit"
  case translation = "translation"
}

enum VoiceLLMServiceError: LocalizedError {
  case proxyEndpointMissing
  case byokEndpointMissing
  case byokAPIKeyMissing
  case invalidResponse
  case emptyResponse
  case requestFailed(message: String)

  var errorDescription: String? {
    switch self {
    case .proxyEndpointMissing:
      return "服务端代理地址未配置"
    case .byokEndpointMissing:
      return "BYOK Base URL 未配置"
    case .byokAPIKeyMissing:
      return "BYOK API Key 未配置"
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
    switch config.authMode {
    case .proxy:
      return try await requestViaProxy(
        task: task,
        sourceText: sourceText,
        instruction: instruction,
        localeIdentifier: localeIdentifier,
        config: config
      )
    case .byok:
      return try await requestViaByok(
        task: task,
        sourceText: sourceText,
        instruction: instruction,
        localeIdentifier: localeIdentifier,
        config: config
      )
    }
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

  func buildPrompts(
    task: VoiceLLMTask,
    sourceText: String,
    instruction: String?,
    localeIdentifier: String?
  ) -> (systemPrompt: String, userPrompt: String) {
    let localeLine = "locale=\(localeIdentifier ?? "unknown")"
    switch task {
    case .speakToEdit:
      let systemPrompt = """
      你是输入法中的文本编辑器。你必须严格根据用户命令编辑原文，并且只返回最终文本，不要解释。
      你不能凭空添加事实，也不能输出 markdown。
      """
      let userPrompt = """
      \(localeLine)
      原文:
      \(sourceText)

      命令:
      \(instruction ?? "")
      """
      return (systemPrompt, userPrompt)
    case .translation:
      let systemPrompt = """
      你是输入法中的翻译器。请在中英文之间做准确直译，保持原意和语气，只返回翻译后的文本，不要解释。
      """
      let userPrompt = """
      \(localeLine)
      待翻译文本:
      \(sourceText)
      """
      return (systemPrompt, userPrompt)
    }
  }
}

final class VoiceSpeechRecognizerEngine {
  enum Route: String {
    case appleOnDevice
    case appleNetwork
    case whisperOnDevice
  }

  struct StartStrategy {
    let localeIdentifier: String
    let prefersOnDevice: Bool
    let allowNetworkFallback: Bool
    let allowWhisperFallback: Bool
    let retryCount: Int
    let whisperModelID: String?
    let contextualStrings: [String]

    static func recommended(for localeIdentifier: String) -> StartStrategy {
      let normalized = localeIdentifier.lowercased()
      let prefersOnDevice = normalized.hasPrefix("zh") || normalized.hasPrefix("en") || normalized.hasPrefix("ja")
      let selectedWhisperModel = VoiceWhisperModelStore.shared.selectedDownloadedModel()
      let contextualStrings = VoicePersonalDictionaryStore.shared.hotwords(limit: 40)
      return StartStrategy(
        localeIdentifier: localeIdentifier,
        prefersOnDevice: prefersOnDevice,
        allowNetworkFallback: true,
        allowWhisperFallback: selectedWhisperModel != nil,
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
  #if canImport(WhisperKit)
  private var whisperKit: WhisperKit?
  private var whisperLoadedModelID: String?
  #endif
  private var isNetworkAvailable = true

  init() {
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
    try await requestPermissions()
    stop(cancel: true)
    onResultHandler = onResult
    onErrorHandler = onError

    let resolvedStrategy = strategy ?? .recommended(for: localeIdentifier)
    let attempts = max(1, resolvedStrategy.retryCount + 1)
    var startErrors: [EngineError] = []

    // 阶段2：优先离线 Apple，再回退在线 Apple，最后回退 Whisper 离线，保障可恢复性。
    if resolvedStrategy.prefersOnDevice {
      for _ in 0..<attempts {
        do {
          try startSpeechRecognition(
            localeIdentifier: resolvedStrategy.localeIdentifier,
            requiresOnDevice: true,
            contextualStrings: resolvedStrategy.contextualStrings,
            onResult: onResult,
            onError: onError
          )
          activePipeline = .apple(requiresOnDevice: true)
          onRouteChanged(.appleOnDevice)
          return
        } catch let error as EngineError {
          startErrors.append(error)
        } catch {
          startErrors.append(.runtimeFailure(message: error.localizedDescription))
        }
      }
    }

    if resolvedStrategy.allowNetworkFallback {
      if isNetworkAvailable {
        for _ in 0..<attempts {
          do {
            try startSpeechRecognition(
              localeIdentifier: resolvedStrategy.localeIdentifier,
              requiresOnDevice: false,
              contextualStrings: resolvedStrategy.contextualStrings,
              onResult: onResult,
              onError: onError
            )
            activePipeline = .apple(requiresOnDevice: false)
            onRouteChanged(.appleNetwork)
            return
          } catch let error as EngineError {
            startErrors.append(error)
          } catch {
            startErrors.append(.runtimeFailure(message: error.localizedDescription))
          }
        }
      } else {
        startErrors.append(.networkUnavailable)
      }
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

    throw composeStartError(from: startErrors)
  }

  func stop(cancel: Bool) {
    if cancel {
      whisperTranscribeTask?.cancel()
      whisperTranscribeTask = nil
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

  private func requestPermissions() async throws {
    let microphoneGranted = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    guard microphoneGranted else { throw EngineError.microphonePermissionDenied }

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
