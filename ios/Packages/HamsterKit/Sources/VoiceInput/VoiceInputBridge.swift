//
//  VoiceInputBridge.swift
//
//
//  Created by Codex on 2026/2/6.
//

import Foundation

public protocol VoiceInputBridgeProtocol: AnyObject {
  func makeRequestId() -> String
  func makeDictationURL(requestId: String) -> URL?
  func isDictationURL(_ url: URL) -> Bool
  func parseRequestId(from url: URL) -> String?

  func activeRequestId() -> String?
  func state() -> VoiceInputState
  func setState(requestId: String, state: VoiceInputState, errorMessage: String?)

  func writeResult(requestId: String, text: String, localeIdentifier: String?)
  func readLatestUnconsumedResult() -> VoiceInputResultPayload?
  func markResultConsumed(requestId: String)
  func cleanupExpiredData()
  func cleanupExpiredData(maxAge: TimeInterval)
}

public extension VoiceInputBridgeProtocol {
  func setState(requestId: String, state: VoiceInputState) {
    setState(requestId: requestId, state: state, errorMessage: nil)
  }
}

/// 键盘扩展与主 App 的语音输入桥接层。
/// 该实现统一管理深链路由、状态持久化和结果信箱，避免上层直接依赖文件细节。
public final class VoiceInputBridge: VoiceInputBridgeProtocol {
  public static let shared = VoiceInputBridge()

  private enum Constants {
    static let deepLinkPath = "dictate"
    static let requestIdQueryName = "rid"
    static let sourceQueryName = "source"
    static let sourceKeyboard = "keyboard"

    static let rootDirectoryName = "VoiceInput"
    static let sessionsDirectoryName = "sessions"
    static let resultsDirectoryName = "results"
    static let fileExtension = "json"

    static let activeRequestIdKey = "voice.input.active_request_id"
    static let stateKey = "voice.input.state"
    static let lastInsertedRequestIdKey = "voice.input.last_inserted_request_id"
    static let resultRetentionSeconds: TimeInterval = 60 * 60
  }

  private let fileManager: FileManager
  private let userDefaults: UserDefaults

  public init(fileManager: FileManager = .default, userDefaults: UserDefaults = .hamster) {
    self.fileManager = fileManager
    self.userDefaults = userDefaults
  }

  public func makeRequestId() -> String {
    UUID().uuidString.lowercased()
  }

  public func makeDictationURL(requestId: String) -> URL? {
    guard !requestId.isEmpty else { return nil }
    let base = "\(HamsterConstants.appURL)/\(Constants.deepLinkPath)"
    guard var components = URLComponents(string: base) else { return nil }
    components.queryItems = [
      URLQueryItem(name: Constants.requestIdQueryName, value: requestId),
      URLQueryItem(name: Constants.sourceQueryName, value: Constants.sourceKeyboard)
    ]
    return components.url
  }

  public func isDictationURL(_ url: URL) -> Bool {
    url.lastPathComponent.lowercased() == Constants.deepLinkPath
  }

  public func parseRequestId(from url: URL) -> String? {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return components?.queryItems?.first(where: { $0.name == Constants.requestIdQueryName })?.value
  }

  public func activeRequestId() -> String? {
    userDefaults.string(forKey: Constants.activeRequestIdKey)
  }

  public func state() -> VoiceInputState {
    let raw = userDefaults.string(forKey: Constants.stateKey)
    return VoiceInputState(rawValue: raw ?? "") ?? .idle
  }

  public func setState(requestId: String, state: VoiceInputState, errorMessage: String? = nil) {
    let now = Date().timeIntervalSince1970
    let payload = VoiceInputSessionPayload(
      requestId: requestId,
      state: state,
      updatedAt: now,
      errorMessage: errorMessage
    )
    write(payload, to: sessionFileURL(for: requestId))
    userDefaults.set(requestId, forKey: Constants.activeRequestIdKey)
    userDefaults.set(state.rawValue, forKey: Constants.stateKey)
  }

  public func writeResult(requestId: String, text: String, localeIdentifier: String? = nil) {
    let now = Date().timeIntervalSince1970
    let payload = VoiceInputResultPayload(
      requestId: requestId,
      text: text,
      localeIdentifier: localeIdentifier,
      createdAt: now,
      updatedAt: now,
      consumed: false,
      consumedAt: nil
    )
    write(payload, to: resultFileURL(for: requestId))
    setState(requestId: requestId, state: .ready, errorMessage: nil)
  }

  public func readLatestUnconsumedResult() -> VoiceInputResultPayload? {
    ensureDirectories()
    guard let fileURLs = try? fileManager.contentsOfDirectory(
      at: resultsDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return nil
    }

    let payloads = fileURLs.compactMap { read(VoiceInputResultPayload.self, from: $0) }
    return payloads
      .filter { !$0.consumed && !$0.text.isEmpty }
      .sorted(by: { $0.updatedAt > $1.updatedAt })
      .first
  }

  public func markResultConsumed(requestId: String) {
    guard var payload = read(VoiceInputResultPayload.self, from: resultFileURL(for: requestId)) else { return }
    guard payload.consumed == false else { return }
    let now = Date().timeIntervalSince1970
    payload = VoiceInputResultPayload(
      requestId: payload.requestId,
      text: payload.text,
      localeIdentifier: payload.localeIdentifier,
      createdAt: payload.createdAt,
      updatedAt: now,
      consumed: true,
      consumedAt: now
    )
    write(payload, to: resultFileURL(for: requestId))
    userDefaults.set(requestId, forKey: Constants.lastInsertedRequestIdKey)
    userDefaults.set(VoiceInputState.inserted.rawValue, forKey: Constants.stateKey)
  }

  public func cleanupExpiredData() {
    cleanupExpiredData(maxAge: Constants.resultRetentionSeconds)
  }

  public func cleanupExpiredData(maxAge: TimeInterval = Constants.resultRetentionSeconds) {
    ensureDirectories()
    let now = Date().timeIntervalSince1970
    let directories = [sessionsDirectoryURL, resultsDirectoryURL]

    for directory in directories {
      guard let fileURLs = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      ) else {
        continue
      }
      for fileURL in fileURLs {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        if now - modified > maxAge {
          try? fileManager.removeItem(at: fileURL)
        }
      }
    }
  }
}

private extension VoiceInputBridge {
  var rootDirectoryURL: URL {
    FileManager.shareURL.appendingPathComponent(Constants.rootDirectoryName, isDirectory: true)
  }

  var sessionsDirectoryURL: URL {
    rootDirectoryURL.appendingPathComponent(Constants.sessionsDirectoryName, isDirectory: true)
  }

  var resultsDirectoryURL: URL {
    rootDirectoryURL.appendingPathComponent(Constants.resultsDirectoryName, isDirectory: true)
  }

  func sessionFileURL(for requestId: String) -> URL {
    sessionsDirectoryURL.appendingPathComponent("session_\(requestId).\(Constants.fileExtension)")
  }

  func resultFileURL(for requestId: String) -> URL {
    resultsDirectoryURL.appendingPathComponent("result_\(requestId).\(Constants.fileExtension)")
  }

  func ensureDirectories() {
    try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: resultsDirectoryURL, withIntermediateDirectories: true)
  }

  func write<T: Encodable>(_ payload: T, to url: URL) {
    ensureDirectories()
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(payload) else { return }
    try? data.write(to: url, options: .atomic)
  }

  func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    return try? decoder.decode(type, from: data)
  }
}
