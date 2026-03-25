//
//  AppCanvasBridge.swift
//
//
//  Created by Codex on 2026/2/13.
//

import Foundation
import HamsterKit

public enum AppCanvasInputState: String, Codable {
  case idle
  case launching
  case drawing
  case processing
  case ready
  case inserted
  case cancelled
  case failed
}

private struct AppCanvasSessionPayload: Codable {
  let requestId: String
  let state: AppCanvasInputState
  let updatedAt: TimeInterval
  let errorMessage: String?
}

private struct AppCanvasResultPayload: Codable {
  let requestId: String
  let imageRelativePath: String
  let createdAt: TimeInterval
  let updatedAt: TimeInterval
  let consumed: Bool
  let consumedAt: TimeInterval?
}

/// 主 App 侧画布桥接，负责深链路由与结果落盘。
public final class AppCanvasBridge {
  public static let shared = AppCanvasBridge()

  private enum Constants {
    static let deepLinkPath = "canvas"
    static let markdownDeepLinkPath = "markdown"
    static let requestIdQueryName = "rid"
    static let sourceQueryName = "source"
    static let sourceKeyboard = "keyboard"

    static let rootDirectoryName = "CanvasInput"
    static let sessionsDirectoryName = "sessions"
    static let resultsDirectoryName = "results"
    static let fileExtension = "json"

    static let activeRequestIdKey = "canvas.input.active_request_id"
    static let stateKey = "canvas.input.state"
  }

  private let fileManager: FileManager
  private let userDefaults: UserDefaults

  init(fileManager: FileManager = .default, userDefaults: UserDefaults = .hamster) {
    self.fileManager = fileManager
    self.userDefaults = userDefaults
  }

  public func makeRequestId() -> String {
    UUID().uuidString.lowercased()
  }

  public func makeCanvasURL(requestId: String) -> URL? {
    guard !requestId.isEmpty else { return nil }
    let base = "\(HamsterConstants.appURL)/\(Constants.deepLinkPath)"
    guard var components = URLComponents(string: base) else { return nil }
    components.queryItems = [
      URLQueryItem(name: Constants.requestIdQueryName, value: requestId),
      URLQueryItem(name: Constants.sourceQueryName, value: Constants.sourceKeyboard),
    ]
    return components.url
  }

  public func makeMarkdownURL(requestId: String) -> URL? {
    guard !requestId.isEmpty else { return nil }
    let base = "\(HamsterConstants.appURL)/\(Constants.markdownDeepLinkPath)"
    guard var components = URLComponents(string: base) else { return nil }
    components.queryItems = [
      URLQueryItem(name: Constants.requestIdQueryName, value: requestId),
      URLQueryItem(name: Constants.sourceQueryName, value: Constants.sourceKeyboard),
    ]
    return components.url
  }

  public func isCanvasURL(_ url: URL) -> Bool {
    url.lastPathComponent.lowercased() == Constants.deepLinkPath
  }

  public func isMarkdownURL(_ url: URL) -> Bool {
    url.lastPathComponent.lowercased() == Constants.markdownDeepLinkPath
  }

  public func parseRequestId(from url: URL) -> String? {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return components?.queryItems?.first(where: { $0.name == Constants.requestIdQueryName })?.value
  }

  public func setState(requestId: String, state: AppCanvasInputState, errorMessage: String? = nil) {
    let payload = AppCanvasSessionPayload(
      requestId: requestId,
      state: state,
      updatedAt: Date().timeIntervalSince1970,
      errorMessage: errorMessage
    )
    write(payload, to: sessionFileURL(for: requestId))
    userDefaults.set(requestId, forKey: Constants.activeRequestIdKey)
    userDefaults.set(state.rawValue, forKey: Constants.stateKey)
  }

  public func writeResult(requestId: String, imageRelativePath: String) {
    let now = Date().timeIntervalSince1970
    let payload = AppCanvasResultPayload(
      requestId: requestId,
      imageRelativePath: imageRelativePath,
      createdAt: now,
      updatedAt: now,
      consumed: false,
      consumedAt: nil
    )
    write(payload, to: resultFileURL(for: requestId))
    setState(requestId: requestId, state: .ready)
  }
}

private extension AppCanvasBridge {
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
}
