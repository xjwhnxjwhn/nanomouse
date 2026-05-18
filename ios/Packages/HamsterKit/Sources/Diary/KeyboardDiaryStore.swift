//
//  KeyboardDiaryStore.swift
//
//
//  Created by OpenAI on 2026/5/14.
//

import CryptoKit
import Foundation
import OSLog
import Security

public enum KeyboardDiarySegmentTrigger: String, Codable, CaseIterable {
  case returnKey
  case candidateSelection
  case keyboardDismiss
  case manualSave
}

public enum KeyboardDiarySegmentConfidence: String, Codable, CaseIterable {
  case high
  case medium
  case low
}

public enum KeyboardDiarySensitiveLevel: String, Codable, CaseIterable {
  case none
  case low
  case medium
  case high
}

public struct KeyboardDiarySegment: Codable, Identifiable, Hashable {
  public var id: UUID
  public var createdAt: Date
  public var text: String
  public var redactedText: String
  public var trigger: KeyboardDiarySegmentTrigger
  public var confidence: KeyboardDiarySegmentConfidence
  public var diaryModeState: String
  public var sensitiveLevel: KeyboardDiarySensitiveLevel
  public var source: String
  public var isFavorite: Bool
  public var isDeleted: Bool
  public var metadata: [String: String]

  public init(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    text: String,
    redactedText: String,
    trigger: KeyboardDiarySegmentTrigger,
    confidence: KeyboardDiarySegmentConfidence,
    diaryModeState: String = "on",
    sensitiveLevel: KeyboardDiarySensitiveLevel,
    source: String = "keyboardExtension",
    isFavorite: Bool = false,
    isDeleted: Bool = false,
    metadata: [String: String] = [:])
  {
    self.id = id
    self.createdAt = createdAt
    self.text = text
    self.redactedText = redactedText
    self.trigger = trigger
    self.confidence = confidence
    self.diaryModeState = diaryModeState
    self.sensitiveLevel = sensitiveLevel
    self.source = source
    self.isFavorite = isFavorite
    self.isDeleted = isDeleted
    self.metadata = metadata
  }

  public var displayText: String {
    redactedText.isEmpty ? text : redactedText
  }
}

public final class KeyboardDiaryStore {
  public static let shared = KeyboardDiaryStore()

  private struct SegmentDecodeResult {
    var segments: [KeyboardDiarySegment]
    var containsPlaintext: Bool
  }

  private struct EncryptedSegmentLine: Codable {
    var version: Int
    var kind: String
    var algorithm: String
    var sealedBox: String
  }

  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let queue = DispatchQueue(label: "com.XiangqingZHANG.nanomouse.keyboardDiaryStore")
  private static let encryptedLineKind = "nanomouse.diary.segment"
  private static let encryptedLineAlgorithm = "AES.GCM"

  private init() {
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public var segmentsFileURL: URL {
    FileManager.appGroupDiarySegmentsFileURL
  }

  public func append(
    rawText: String,
    trigger: KeyboardDiarySegmentTrigger,
    confidence: KeyboardDiarySegmentConfidence,
    metadata: [String: String] = [:]) throws -> KeyboardDiarySegment?
  {
    let filtered = Self.filter(rawText)
    guard filtered.shouldSave else { return nil }
    let persistedText = filtered.level == .none ? filtered.original : filtered.redacted
    let segment = KeyboardDiarySegment(
      text: persistedText,
      redactedText: filtered.redacted,
      trigger: trigger,
      confidence: confidence,
      sensitiveLevel: filtered.level,
      metadata: metadata
    )
    try append(segment)
    return segment
  }

  public func append(_ segment: KeyboardDiarySegment) throws {
    try queue.sync {
      try prepareDiaryStorageUnlocked()
      try migratePlaintextFileIfNeededUnlocked()
      let line = try encodedEncryptedLineData(for: segment)
      let fileURL = segmentsFileURL
      if FileManager.default.fileExists(atPath: fileURL.path) {
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.close()
      } else {
        try writeProtectedDataUnlocked(line, to: fileURL)
      }
      try applyFileProtectionUnlocked()
    }
  }

  public func loadSegments(includeDeleted: Bool = false) -> [KeyboardDiarySegment] {
    queue.sync {
      loadSegmentsUnlocked(includeDeleted: includeDeleted)
    }
  }

  public func segments(on day: Date, calendar: Calendar = .current) -> [KeyboardDiarySegment] {
    loadSegments().filter { calendar.isDate($0.createdAt, inSameDayAs: day) }
  }

  public func dayBuckets(calendar: Calendar = .current) -> [(day: Date, segments: [KeyboardDiarySegment])] {
    let grouped = Dictionary(grouping: loadSegments()) { segment in
      calendar.startOfDay(for: segment.createdAt)
    }
    return grouped
      .map { (day: $0.key, segments: $0.value.sorted { $0.createdAt > $1.createdAt }) }
      .sorted { $0.day > $1.day }
  }

  public func update(_ segment: KeyboardDiarySegment) throws {
    try rewrite { segments in
      guard let index = segments.firstIndex(where: { $0.id == segment.id }) else { return segments }
      var mutable = segments
      mutable[index] = segment
      return mutable
    }
  }

  public func markDeleted(id: UUID) throws {
    try rewrite { segments in
      segments.map { segment in
        guard segment.id == id else { return segment }
        var copy = segment
        copy.isDeleted = true
        return copy
      }
    }
  }

  public func clearAll() throws {
    try queue.sync {
      let fileURL = segmentsFileURL
      if FileManager.default.fileExists(atPath: fileURL.path) {
        try FileManager.default.removeItem(at: fileURL)
      }
      try? KeyboardDiaryEncryption.deleteKey()
    }
  }

  private func rewrite(_ transform: ([KeyboardDiarySegment]) -> [KeyboardDiarySegment]) throws {
    try queue.sync {
      let current = try loadSegmentDecodeResultUnlocked().segments
      let updated = transform(current)
      try writeEncryptedSegmentsUnlocked(updated)
    }
  }

  private func loadSegmentsUnlocked(includeDeleted: Bool) -> [KeyboardDiarySegment] {
    let fileURL = segmentsFileURL
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }

    do {
      try applyFileProtectionUnlocked()
      let result = try loadSegmentDecodeResultUnlocked()
      if result.containsPlaintext {
        do {
          try writeEncryptedSegmentsUnlocked(result.segments)
        } catch {
          Logger.statistics.error("KeyboardDiary plaintext migration failed: \(error.localizedDescription)")
        }
      }
      return result.segments
        .filter { includeDeleted || !$0.isDeleted }
        .sorted { $0.createdAt > $1.createdAt }
    } catch {
      Logger.statistics.error("KeyboardDiary load failed: \(error.localizedDescription)")
      return []
    }
  }

  private func prepareDiaryStorageUnlocked() throws {
    try FileManager.createDirectory(override: false, dst: FileManager.appGroupDiaryDirectoryURL)
    try applyFileProtectionUnlocked()
  }

  private func applyFileProtectionUnlocked() throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: FileManager.appGroupDiaryDirectoryURL.path) {
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: FileManager.appGroupDiaryDirectoryURL.path
      )
    }
    if fileManager.fileExists(atPath: segmentsFileURL.path) {
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: segmentsFileURL.path
      )
    }
  }

  private func writeEncryptedSegmentsUnlocked(_ segments: [KeyboardDiarySegment]) throws {
    try prepareDiaryStorageUnlocked()
    let payload = try encryptedPayloadData(for: segments)
    try writeProtectedDataUnlocked(payload, to: segmentsFileURL)
  }

  private func writeProtectedDataUnlocked(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    try applyFileProtectionUnlocked()
  }

  private func encryptedPayloadData(for segments: [KeyboardDiarySegment]) throws -> Data {
    var payload = Data()
    for segment in segments {
      payload.append(try encodedEncryptedLineData(for: segment))
    }
    return payload
  }

  private func encodedEncryptedLineData(for segment: KeyboardDiarySegment) throws -> Data {
    let plaintext = try encoder.encode(segment)
    let sealedBox = try KeyboardDiaryEncryption.seal(plaintext)
    let line = EncryptedSegmentLine(
      version: 1,
      kind: Self.encryptedLineKind,
      algorithm: Self.encryptedLineAlgorithm,
      sealedBox: sealedBox.base64EncodedString()
    )
    var data = try encoder.encode(line)
    data.append(0x0A)
    return data
  }

  private func migratePlaintextFileIfNeededUnlocked() throws {
    guard FileManager.default.fileExists(atPath: segmentsFileURL.path) else { return }
    let result = try loadSegmentDecodeResultUnlocked()
    guard result.containsPlaintext else { return }
    try writeEncryptedSegmentsUnlocked(result.segments)
  }

  private func loadSegmentDecodeResultUnlocked() throws -> SegmentDecodeResult {
    let fileURL = segmentsFileURL
    guard let data = try? Data(contentsOf: fileURL),
          let text = String(data: data, encoding: .utf8)
    else {
      return SegmentDecodeResult(segments: [], containsPlaintext: false)
    }

    var segments: [KeyboardDiarySegment] = []
    var containsPlaintext = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let data = Data(line.utf8)
      if let encryptedLine = try? decoder.decode(EncryptedSegmentLine.self, from: data),
         encryptedLine.version == 1,
         encryptedLine.kind == Self.encryptedLineKind,
         encryptedLine.algorithm == Self.encryptedLineAlgorithm {
        let plaintext = try KeyboardDiaryEncryption.open(encryptedLine.sealedBox)
        let segment = try decoder.decode(KeyboardDiarySegment.self, from: plaintext)
        segments.append(segment)
        continue
      }
      if let segment = try? decoder.decode(KeyboardDiarySegment.self, from: data) {
        containsPlaintext = true
        segments.append(segment)
      }
    }

    return SegmentDecodeResult(
      segments: segments.sorted { $0.createdAt > $1.createdAt },
      containsPlaintext: containsPlaintext
    )
  }

  public static func extractCurrentParagraph(before: String, after: String) -> String {
    let beforeLine = before.components(separatedBy: CharacterSet.newlines).last ?? before
    let afterLine = after.components(separatedBy: CharacterSet.newlines).first ?? after
    return normalize("\(beforeLine)\(afterLine)")
  }

  public static func normalize(_ text: String) -> String {
    let collapsed = text
      .replacingOccurrences(of: "\u{00A0}", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard collapsed.count > 2000 else { return collapsed }
    return String(collapsed.suffix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func filter(_ rawText: String) -> (shouldSave: Bool, original: String, redacted: String, level: KeyboardDiarySensitiveLevel) {
    let original = normalize(rawText)
    guard original.count >= 2 else { return (false, "", "", .none) }
    if original.rangeOfCharacter(from: CharacterSet.alphanumerics.union(.letters)) == nil {
      return (false, "", "", .none)
    }
    if original.count <= 4,
       original.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) || CharacterSet.punctuationCharacters.contains($0) })
    {
      return (false, "", "", .none)
    }

    var redacted = original
    var level: KeyboardDiarySensitiveLevel = .none

    let highRiskPatterns = [
      #"(?i)(password|passwd|pwd|api[_-]?key|token|secret)\s*[:=]\s*\S+"#,
      #"\b\d{6}\b"#,
      #"\b\d{13,19}\b"#,
    ]
    for pattern in highRiskPatterns where redacted.range(of: pattern, options: .regularExpression) != nil {
      level = .high
      redacted = redacted.replacingOccurrences(of: pattern, with: "[敏感内容]", options: .regularExpression)
    }
    guard level != .high else {
      return (false, "", "", .high)
    }

    let mediumRiskPatterns = [
      #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
      #"\b1[3-9]\d{9}\b"#,
      #"(?i)(https?://\S*(token|key|code|auth)\S*)"#,
    ]
    for pattern in mediumRiskPatterns where redacted.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
      if level != .high { level = .medium }
      redacted = redacted.replacingOccurrences(of: pattern, with: "[已脱敏]", options: [.regularExpression, .caseInsensitive])
    }

    return (true, original, redacted, level)
  }
}

private enum KeyboardDiaryEncryptionError: LocalizedError {
  case invalidSealedBox
  case invalidKeyData
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidSealedBox:
      return "日记密文格式无效"
    case .invalidKeyData:
      return "日记加密密钥无效"
    case let .keychain(status):
      return "日记密钥访问失败：\(status)"
    }
  }
}

private enum KeyboardDiaryEncryption {
  private static let keychainService = "com.XiangqingZHANG.nanomouse.diary"
  private static let keychainAccount = "segments-jsonl-aes-gcm-v1"

  static func seal(_ plaintext: Data) throws -> Data {
    let sealedBox = try AES.GCM.seal(plaintext, using: loadOrCreateKey())
    guard let combined = sealedBox.combined else {
      throw KeyboardDiaryEncryptionError.invalidSealedBox
    }
    return combined
  }

  static func open(_ sealedBoxBase64: String) throws -> Data {
    guard let combined = Data(base64Encoded: sealedBoxBase64) else {
      throw KeyboardDiaryEncryptionError.invalidSealedBox
    }
    let sealedBox = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(sealedBox, using: loadOrCreateKey())
  }

  static func deleteKey() throws {
    let status = SecItemDelete(baseKeychainQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeyboardDiaryEncryptionError.keychain(status)
    }
  }

  private static func loadOrCreateKey() throws -> SymmetricKey {
    if let data = try readKeyData() {
      guard data.count == 32 else {
        throw KeyboardDiaryEncryptionError.invalidKeyData
      }
      return SymmetricKey(data: data)
    }

    let key = SymmetricKey(size: .bits256)
    let keyData = key.withUnsafeBytes { Data($0) }
    try storeKeyData(keyData)
    return key
  }

  private static func readKeyData() throws -> Data? {
    var query = baseKeychainQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw KeyboardDiaryEncryptionError.keychain(status)
    }
    guard let data = result as? Data else {
      throw KeyboardDiaryEncryptionError.invalidKeyData
    }
    return data
  }

  private static func storeKeyData(_ data: Data) throws {
    var insert = baseKeychainQuery()
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
    insert[kSecValueData as String] = data

    let status = SecItemAdd(insert as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateStatus = SecItemUpdate(
        baseKeychainQuery() as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
      )
      guard updateStatus == errSecSuccess else {
        throw KeyboardDiaryEncryptionError.keychain(updateStatus)
      }
      return
    }
    guard status == errSecSuccess else {
      throw KeyboardDiaryEncryptionError.keychain(status)
    }
  }

  private static func baseKeychainQuery() -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount
    ]
    if let accessGroup = sharedKeychainAccessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  private static let sharedKeychainAccessGroup: String? = {
    guard let prefix = Bundle.main.object(forInfoDictionaryKey: "NanomouseAppIdentifierPrefix") as? String,
          !prefix.isEmpty,
          !prefix.contains("$")
    else {
      return nil
    }
    return prefix + HamsterConstants.appGroupName
  }()
}
