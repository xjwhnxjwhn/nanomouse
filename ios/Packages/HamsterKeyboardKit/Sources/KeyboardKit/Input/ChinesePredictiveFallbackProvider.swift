//
//  ChinesePredictiveFallbackProvider.swift
//

import Foundation
import HamsterKit

final class ChinesePredictiveFallbackProvider {
  static let shared = ChinesePredictiveFallbackProvider()
  static let sourceID = "chinese_suffix_fallback"

  private var table: [String: [String]]?
  private var didAttemptLoad = false

  private init() {}

  func suggestions(for documentContext: String?, maxCandidates: Int) -> [CandidateSuggestion] {
    guard let table = loadTableIfNeeded() else { return [] }
    let keys = lookupKeys(from: documentContext)
    guard !keys.isEmpty else { return [] }

    var result: [CandidateSuggestion] = []
    var seen = Set<String>()
    let limit = max(1, min(maxCandidates, 50))
    for key in keys {
      for value in table[key] ?? [] {
        guard !value.isEmpty, seen.insert(value).inserted else { continue }
        result.append(CandidateSuggestion(
          index: result.count,
          label: "\(result.count + 1)",
          text: value,
          title: value,
          additionalInfo: ["predictionSource": Self.sourceID]
        ))
        if result.count >= limit {
          return result
        }
      }
    }
    return result
  }

  private func loadTableIfNeeded() -> [String: [String]]? {
    if let table {
      return table
    }
    guard !didAttemptLoad else {
      return nil
    }
    didAttemptLoad = true
    let url = FileManager.appGroupRimePredictFallbackURL
    guard FileManager.default.fileExists(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
    else {
      return nil
    }
    table = decoded
    return decoded
  }

  private func lookupKeys(from documentContext: String?) -> [String] {
    guard let documentContext, !documentContext.isEmpty else { return [] }
    var tailCharacters: [Character] = []
    for character in documentContext.reversed() {
      guard character.isSingleHanCharacter else { break }
      tailCharacters.append(character)
      if tailCharacters.count >= 2 { break }
    }
    let tail = String(tailCharacters.reversed())
    guard !tail.isEmpty else { return [] }
    if tail.count >= 2 {
      return [tail, String(tail.suffix(1))]
    }
    return [tail]
  }
}

private extension Character {
  var isSingleHanCharacter: Bool {
    unicodeScalars.count == 1 && unicodeScalars.allSatisfy {
      (0x4E00...0x9FFF).contains($0.value)
    }
  }
}
