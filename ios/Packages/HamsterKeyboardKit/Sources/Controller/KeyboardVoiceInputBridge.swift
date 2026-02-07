//
//  KeyboardVoiceInputBridge.swift
//
//
//  Created by Codex on 2026/2/6.
//

import Foundation
import HamsterKit

enum KeyboardVoiceInputState: String, Codable {
  case idle
  case launching
  case recording
  case processing
  case ready
  case inserted
  case undoWindow
  case cancelled
  case failed
}

struct KeyboardVoiceInputResultPayload: Codable {
  let requestId: String
  let text: String
  let localeIdentifier: String?
  let createdAt: TimeInterval
  let updatedAt: TimeInterval
  let consumed: Bool
  let consumedAt: TimeInterval?
}

private struct KeyboardVoiceInputSessionPayload: Codable {
  let requestId: String
  let state: KeyboardVoiceInputState
  let updatedAt: TimeInterval
  let errorMessage: String?
}

/// 键盘侧语音桥接，避免键盘模块直接依赖主 App 语音实现细节。
final class KeyboardVoiceInputBridge {
  static let shared = KeyboardVoiceInputBridge()

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

  init(fileManager: FileManager = .default, userDefaults: UserDefaults = .hamster) {
    self.fileManager = fileManager
    self.userDefaults = userDefaults
  }

  func makeRequestId() -> String {
    UUID().uuidString.lowercased()
  }

  func makeDictationURL(requestId: String) -> URL? {
    guard !requestId.isEmpty else { return nil }
    let base = "\(HamsterConstants.appURL)/\(Constants.deepLinkPath)"
    guard var components = URLComponents(string: base) else { return nil }
    components.queryItems = [
      URLQueryItem(name: Constants.requestIdQueryName, value: requestId),
      URLQueryItem(name: Constants.sourceQueryName, value: Constants.sourceKeyboard)
    ]
    return components.url
  }

  func setState(requestId: String, state: KeyboardVoiceInputState, errorMessage: String? = nil) {
    let payload = KeyboardVoiceInputSessionPayload(
      requestId: requestId,
      state: state,
      updatedAt: Date().timeIntervalSince1970,
      errorMessage: errorMessage
    )
    write(payload, to: sessionFileURL(for: requestId))
    userDefaults.set(requestId, forKey: Constants.activeRequestIdKey)
    userDefaults.set(state.rawValue, forKey: Constants.stateKey)
  }

  func activeRequestId() -> String? {
    userDefaults.string(forKey: Constants.activeRequestIdKey)
  }

  func state() -> KeyboardVoiceInputState {
    let raw = userDefaults.string(forKey: Constants.stateKey)
    return KeyboardVoiceInputState(rawValue: raw ?? "") ?? .idle
  }

  func readLatestUnconsumedResult() -> KeyboardVoiceInputResultPayload? {
    ensureDirectories()

    // 只消费当前 activeRequestId 对应结果，禁止回退扫描历史结果，
    // 否则会把旧会话文本误插入到当前宿主输入框中。
    guard let activeRequestId = activeRequestId() else {
      return nil
    }

    guard let payload = read(KeyboardVoiceInputResultPayload.self, from: resultFileURL(for: activeRequestId)) else {
      return nil
    }
    guard payload.consumed == false else { return nil }
    guard !payload.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return payload
  }

  func markResultConsumed(requestId: String) {
    guard var payload = read(KeyboardVoiceInputResultPayload.self, from: resultFileURL(for: requestId)) else { return }
    guard payload.consumed == false else { return }

    let now = Date().timeIntervalSince1970
    payload = KeyboardVoiceInputResultPayload(
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
    userDefaults.set(KeyboardVoiceInputState.inserted.rawValue, forKey: Constants.stateKey)
  }

  func cleanupExpiredData() {
    cleanupExpiredData(maxAge: Constants.resultRetentionSeconds)
  }

  func cleanupExpiredData(maxAge: TimeInterval) {
    ensureDirectories()
    let now = Date().timeIntervalSince1970

    for directory in [sessionsDirectoryURL, resultsDirectoryURL] {
      guard let fileURLs = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      ) else {
        continue
      }

      for fileURL in fileURLs {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        if now - modifiedAt > maxAge {
          try? fileManager.removeItem(at: fileURL)
        }
      }
    }
  }
}

private extension KeyboardVoiceInputBridge {
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
