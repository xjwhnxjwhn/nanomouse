//
//  HamsterConstants.swift
//
//
//  Created by morse on 2023/7/3.
//

import Foundation

/// 鼠输入法应用常量
public enum HamsterConstants {
  /// AppGroup ID
  public static let appGroupName = "group.com.XiangqingZHANG.nanomouse"

  /// iCloud ID
  public static let iCloudID = "iCloud.com.XiangqingZHANG.nanomouse"

  /// keyboard Bundle ID
  public static let keyboardBundleID = "com.XiangqingZHANG.nanomouse.keyboard"

  /// 跳转至系统添加键盘URL
  public static let addKeyboardPath = "app-settings:root=General&path=Keyboard/KEYBOARDS"

  // MARK: 与Squirrel.app保持一致

  /// RIME 预先构建的数据目录中
  public static let rimeSharedSupportPathName = "SharedSupport"

  /// RIME UserData目录
  public static let rimeUserPathName = "Rime"

  /// RIME 内置输入方案及配置zip包
  public static let inputSchemaZipFile = "SharedSupport.zip"

  /// 额外输入方案 zip 包（按需下载，不随包内置）
  public static let extraInputSchemaZipFiles: [String] = []

  /// 按需下载的 zip 包基础地址（GitHub raw）
  public static let onDemandInputSchemaZipBaseURL = "https://raw.githubusercontent.com/xjwhnxjwhn/nanomouse/main/zips"

  /// 日语方案 zip 包（按需下载）
  public static let onDemandJapaneseSchemaZipMap: [String: String] = [
    "japanese": "rime-japanese.zip",
    "jaroomaji": "rime-jaroomaji.zip",
    "jaroomaji-easy": "rime-jaroomaji-easy.zip",
  ]

  /// AzooKey 方案 schemaId
  public static let azooKeySchemaId = "azookey"

  /// AzooKey 词库 zip 包（按需下载）
  public static let azooKeyDictionaryZipFile = "azookey-dictionary.zip"

  /// AzooKey Zenzai 权重文件（按需下载，.gguf 格式）
  /// Low = xsmall (20MB), High = small (70MB)
  public static let azooKeyZenzaiWeightFileLow = "zenz-v3.1-xsmall-Q5_K_M.gguf"
  public static let azooKeyZenzaiWeightFileHigh = "zenz-v3.1-small-Q5_K_M.gguf"

  /// 其他可选方案 zip 包（按需下载）
  public static let onDemandExtraZipFiles: [String] = [
    "rime-terra-pinyin.zip",
    "rime-stroke.zip",
    "rime-hangyl.zip",
    "rime-hannomps.zip",
  ]

  /// 仓内置方案 zip 包
  public static let userDataZipFile = "rime-ice.zip"

  /// APP URL
  /// 注意: 此值需要与info.plist中的参数保持一致
  public static let appURL = "nanomouse://com.XiangqingZHANG.nanomouse"

  public enum VoiceInput {
    /// 主 App 语音入口路径
    public static let deepLinkPath = "dictate"
    /// URL query: request id
    public static let requestIdQueryName = "rid"
    /// URL query: source
    public static let sourceQueryName = "source"
    public static let sourceKeyboard = "keyboard"

    /// AppGroup 下语音共享目录
    public static let rootDirectoryName = "VoiceInput"
    public static let sessionsDirectoryName = "sessions"
    public static let resultsDirectoryName = "results"
    public static let fileExtension = "json"

    /// 状态缓存键
    public static let activeRequestIdKey = "voice.input.active_request_id"
    public static let stateKey = "voice.input.state"
    public static let lastInsertedRequestIdKey = "voice.input.last_inserted_request_id"

    /// 结果保留时长（秒）
    public static let resultRetentionSeconds: TimeInterval = 60 * 60
  }
}

public enum VoiceInputState: String, Codable {
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

public struct VoiceInputSessionPayload: Codable {
  public let requestId: String
  public let state: VoiceInputState
  public let updatedAt: TimeInterval
  public let errorMessage: String?

  public init(requestId: String, state: VoiceInputState, updatedAt: TimeInterval, errorMessage: String? = nil) {
    self.requestId = requestId
    self.state = state
    self.updatedAt = updatedAt
    self.errorMessage = errorMessage
  }
}

public struct VoiceInputResultPayload: Codable {
  public let requestId: String
  public let text: String
  public let localeIdentifier: String?
  public let createdAt: TimeInterval
  public let updatedAt: TimeInterval
  public let consumed: Bool
  public let consumedAt: TimeInterval?

  public init(
    requestId: String,
    text: String,
    localeIdentifier: String?,
    createdAt: TimeInterval,
    updatedAt: TimeInterval,
    consumed: Bool,
    consumedAt: TimeInterval?
  ) {
    self.requestId = requestId
    self.text = text
    self.localeIdentifier = localeIdentifier
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.consumed = consumed
    self.consumedAt = consumedAt
  }
}

/// 键盘扩展与主 App 共用的语音输入通信桥接
public enum VoiceInputBridge {
  private static let fileManager = FileManager.default

  private static var rootDirectoryURL: URL {
    FileManager.shareURL.appendingPathComponent(HamsterConstants.VoiceInput.rootDirectoryName, isDirectory: true)
  }

  private static var sessionsDirectoryURL: URL {
    rootDirectoryURL.appendingPathComponent(HamsterConstants.VoiceInput.sessionsDirectoryName, isDirectory: true)
  }

  private static var resultsDirectoryURL: URL {
    rootDirectoryURL.appendingPathComponent(HamsterConstants.VoiceInput.resultsDirectoryName, isDirectory: true)
  }

  private static func sessionFileURL(for requestId: String) -> URL {
    sessionsDirectoryURL.appendingPathComponent("session_\(requestId).\(HamsterConstants.VoiceInput.fileExtension)")
  }

  private static func resultFileURL(for requestId: String) -> URL {
    resultsDirectoryURL.appendingPathComponent("result_\(requestId).\(HamsterConstants.VoiceInput.fileExtension)")
  }

  public static func makeRequestId() -> String {
    UUID().uuidString.lowercased()
  }

  public static func dictationURL(requestId: String) -> URL? {
    guard !requestId.isEmpty else { return nil }
    let base = "\(HamsterConstants.appURL)/\(HamsterConstants.VoiceInput.deepLinkPath)"
    guard var components = URLComponents(string: base) else { return nil }
    components.queryItems = [
      URLQueryItem(name: HamsterConstants.VoiceInput.requestIdQueryName, value: requestId),
      URLQueryItem(name: HamsterConstants.VoiceInput.sourceQueryName, value: HamsterConstants.VoiceInput.sourceKeyboard)
    ]
    return components.url
  }

  public static func activeRequestId() -> String? {
    UserDefaults.hamster.string(forKey: HamsterConstants.VoiceInput.activeRequestIdKey)
  }

  public static func state() -> VoiceInputState {
    let raw = UserDefaults.hamster.string(forKey: HamsterConstants.VoiceInput.stateKey)
    return VoiceInputState(rawValue: raw ?? "") ?? .idle
  }

  public static func setState(requestId: String, state: VoiceInputState, errorMessage: String? = nil) {
    let now = Date().timeIntervalSince1970
    let payload = VoiceInputSessionPayload(
      requestId: requestId,
      state: state,
      updatedAt: now,
      errorMessage: errorMessage
    )
    write(payload, to: sessionFileURL(for: requestId))
    UserDefaults.hamster.set(requestId, forKey: HamsterConstants.VoiceInput.activeRequestIdKey)
    UserDefaults.hamster.set(state.rawValue, forKey: HamsterConstants.VoiceInput.stateKey)
  }

  public static func writeResult(requestId: String, text: String, localeIdentifier: String? = nil) {
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
    setState(requestId: requestId, state: .ready)
  }

  public static func readLatestUnconsumedResult() -> VoiceInputResultPayload? {
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

  public static func markResultConsumed(requestId: String) {
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
    UserDefaults.hamster.set(requestId, forKey: HamsterConstants.VoiceInput.lastInsertedRequestIdKey)
    UserDefaults.hamster.set(VoiceInputState.inserted.rawValue, forKey: HamsterConstants.VoiceInput.stateKey)
  }

  public static func cleanupExpiredData(maxAge: TimeInterval = HamsterConstants.VoiceInput.resultRetentionSeconds) {
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

  private static func ensureDirectories() {
    try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: resultsDirectoryURL, withIntermediateDirectories: true)
  }

  private static func write<T: Encodable>(_ payload: T, to url: URL) {
    ensureDirectories()
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(payload) else { return }
    try? data.write(to: url, options: .atomic)
  }

  private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    return try? decoder.decode(type, from: data)
  }
}
