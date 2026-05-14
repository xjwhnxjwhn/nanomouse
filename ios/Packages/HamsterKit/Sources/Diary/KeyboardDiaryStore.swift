//
//  KeyboardDiaryStore.swift
//
//
//  Created by OpenAI on 2026/5/14.
//

import Foundation
import OSLog

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

  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let queue = DispatchQueue(label: "com.XiangqingZHANG.nanomouse.keyboardDiaryStore")

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
      try FileManager.createDirectory(override: false, dst: FileManager.appGroupDiaryDirectoryURL)
      let data = try encoder.encode(segment)
      var line = Data()
      line.append(data)
      line.append(0x0A)
      let fileURL = segmentsFileURL
      if FileManager.default.fileExists(atPath: fileURL.path) {
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.close()
      } else {
        try line.write(to: fileURL, options: .atomic)
      }
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
    }
  }

  private func rewrite(_ transform: ([KeyboardDiarySegment]) -> [KeyboardDiarySegment]) throws {
    try queue.sync {
      let current = loadSegmentsUnlocked(includeDeleted: true)
      let updated = transform(current)
      try FileManager.createDirectory(override: false, dst: FileManager.appGroupDiaryDirectoryURL)
      let lines = try updated.map { segment in
        String(data: try encoder.encode(segment), encoding: .utf8) ?? ""
      }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
      let payload = lines.isEmpty ? Data() : Data((lines + "\n").utf8)
      try payload.write(to: segmentsFileURL, options: .atomic)
    }
  }

  private func loadSegmentsUnlocked(includeDeleted: Bool) -> [KeyboardDiarySegment] {
    let fileURL = segmentsFileURL
    guard let data = try? Data(contentsOf: fileURL),
          let text = String(data: data, encoding: .utf8)
    else {
      return []
    }
    return text
      .split(separator: "\n", omittingEmptySubsequences: true)
      .compactMap { line -> KeyboardDiarySegment? in
        guard let data = String(line).data(using: .utf8) else { return nil }
        return try? decoder.decode(KeyboardDiarySegment.self, from: data)
      }
      .filter { includeDeleted || !$0.isDeleted }
      .sorted { $0.createdAt > $1.createdAt }
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
