//
//  VoiceWorkspaceDocumentStore.swift
//
//
//  Created by Codex on 2026/4/20.
//

import Foundation
import HamsterKit
import PencilKit

enum VoiceWorkspaceDocumentKind: String {
  case markdown
  case canvas
  case causal

  var directoryName: String {
    switch self {
    case .markdown:
      return "Markdown"
    case .canvas:
      return "Canvas"
    case .causal:
      return "Causal"
    }
  }

  var panelTitle: String {
    switch self {
    case .markdown:
      return "Markdown 文件"
    case .canvas:
      return "画布文件"
    case .causal:
      return "因果图文件"
    }
  }

  var defaultBaseName: String {
    switch self {
    case .markdown:
      return "Markdown"
    case .canvas:
      return "Canvas"
    case .causal:
      return "Causal"
    }
  }

  var fileExtension: String {
    switch self {
    case .markdown:
      return "md"
    case .canvas:
      return "pkdrawing"
    case .causal:
      return "causal.json"
    }
  }

  var allowedExtensions: [String] {
    switch self {
    case .markdown:
      return ["md"]
    case .canvas:
      return ["pkdrawing"]
    case .causal:
      return ["causal.json"]
    }
  }
}

struct VoiceWorkspaceDocumentItem: Hashable {
  let url: URL
  let isDirectory: Bool
  let fileName: String
  let modifiedAt: Date?
  let fileSize: Int64
}

final class VoiceWorkspaceDocumentStore {
  static let shared = VoiceWorkspaceDocumentStore()

  private enum Constants {
    static let rootDirectoryName = "NanoMouse Studio"
  }

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  var isICloudAvailable: Bool {
    URL.iCloudDocumentURL != nil
  }

  var workspaceRootURL: URL {
    let base = URL.iCloudDocumentURL ?? FileManager.sandboxDirectory.appendingPathComponent("iCloudDocumentsFallback", isDirectory: true)
    return base.appendingPathComponent(Constants.rootDirectoryName, isDirectory: true)
  }

  func ensureWorkspaceDirectories() throws {
    try fileManager.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true, attributes: nil)
    for kind in [VoiceWorkspaceDocumentKind.markdown, .canvas, .causal] {
      try fileManager.createDirectory(at: rootDirectoryURL(for: kind), withIntermediateDirectories: true, attributes: nil)
    }
  }

  func rootDirectoryURL(for kind: VoiceWorkspaceDocumentKind) -> URL {
    workspaceRootURL.appendingPathComponent(kind.directoryName, isDirectory: true)
  }

  func directoryURL(for kind: VoiceWorkspaceDocumentKind, pathComponents: [String]) -> URL {
    pathComponents.reduce(rootDirectoryURL(for: kind)) { partial, component in
      partial.appendingPathComponent(component, isDirectory: true)
    }
  }

  func listItems(for kind: VoiceWorkspaceDocumentKind, pathComponents: [String]) -> [VoiceWorkspaceDocumentItem] {
    do {
      try ensureWorkspaceDirectories()
      let directoryURL = directoryURL(for: kind, pathComponents: pathComponents)
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
      let urls = try fileManager.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [
          .isDirectoryKey,
          .contentModificationDateKey,
          .fileSizeKey,
          .ubiquitousItemDownloadingStatusKey,
        ],
        options: [.skipsHiddenFiles]
      )
      return urls
        .compactMap { url in
          try? makeItem(for: url, kind: kind)
        }
        .sorted { lhs, rhs in
          if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
          }
          return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }
    } catch {
      return []
    }
  }

  func createFolder(named rawName: String, for kind: VoiceWorkspaceDocumentKind, pathComponents: [String]) throws {
    try ensureWorkspaceDirectories()
    let sanitized = sanitizeFolderName(rawName)
    guard !sanitized.isEmpty else { return }
    let url = directoryURL(for: kind, pathComponents: pathComponents).appendingPathComponent(sanitized, isDirectory: true)
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
  }

  @discardableResult
  func createMarkdownDocument(named rawName: String, content: String, pathComponents: [String]) throws -> URL {
    let url = try targetFileURL(for: .markdown, rawName: rawName, pathComponents: pathComponents)
    try saveMarkdown(content: content, to: url)
    return url
  }

  func saveMarkdown(content: String, to url: URL) throws {
    try ensureParentDirectory(for: url)
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  func loadMarkdown(from url: URL) throws -> String {
    try prepareUbiquitousItemIfNeeded(at: url)
    return try String(contentsOf: url, encoding: .utf8)
  }

  @discardableResult
  func createCanvasDocument(named rawName: String, drawing: PKDrawing, pathComponents: [String]) throws -> URL {
    let url = try targetFileURL(for: .canvas, rawName: rawName, pathComponents: pathComponents)
    try saveCanvas(drawing: drawing, to: url)
    return url
  }

  func saveCanvas(drawing: PKDrawing, to url: URL) throws {
    try ensureParentDirectory(for: url)
    try drawing.dataRepresentation().write(to: url, options: .atomic)
  }

  func loadCanvas(from url: URL) throws -> PKDrawing {
    try prepareUbiquitousItemIfNeeded(at: url)
    let data = try Data(contentsOf: url, options: [])
    return try PKDrawing(data: data)
  }

  @discardableResult
  func createCausalDocument(named rawName: String, edges: [VoiceCausalEdgeDraft], pathComponents: [String]) throws -> URL {
    let url = try targetFileURL(for: .causal, rawName: rawName, pathComponents: pathComponents)
    try saveCausal(edges: edges, to: url)
    return url
  }

  func saveCausal(edges: [VoiceCausalEdgeDraft], to url: URL) throws {
    try ensureParentDirectory(for: url)
    let data = try JSONEncoder().encode(edges)
    try data.write(to: url, options: .atomic)
  }

  func loadCausal(from url: URL) throws -> [VoiceCausalEdgeDraft] {
    try prepareUbiquitousItemIfNeeded(at: url)
    let data = try Data(contentsOf: url, options: [])
    return try JSONDecoder().decode([VoiceCausalEdgeDraft].self, from: data)
  }

  func deleteItem(_ item: VoiceWorkspaceDocumentItem) throws {
    try fileManager.removeItem(at: item.url)
  }

  func relativeDisplayPath(for kind: VoiceWorkspaceDocumentKind, pathComponents: [String]) -> String {
    let suffix = pathComponents.joined(separator: "/")
    if suffix.isEmpty {
      return "\(Constants.rootDirectoryName)/\(kind.directoryName)"
    }
    return "\(Constants.rootDirectoryName)/\(kind.directoryName)/\(suffix)"
  }

  func suggestedFileName(for kind: VoiceWorkspaceDocumentKind) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return "\(kind.defaultBaseName)_\(formatter.string(from: Date()))"
  }

  private func targetFileURL(
    for kind: VoiceWorkspaceDocumentKind,
    rawName: String,
    pathComponents: [String]
  ) throws -> URL {
    try ensureWorkspaceDirectories()
    let sanitized = sanitizeFileName(rawName)
    let baseURL = directoryURL(for: kind, pathComponents: pathComponents)
    try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)

    let finalName: String
    if sanitized.lowercased().hasSuffix(".\(kind.fileExtension.lowercased())") {
      finalName = sanitized
    } else {
      finalName = "\(sanitized).\(kind.fileExtension)"
    }
    return baseURL.appendingPathComponent(finalName, isDirectory: false)
  }

  private func sanitizeFolderName(_ rawName: String) -> String {
    rawName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/", with: "-")
  }

  private func sanitizeFileName(_ rawName: String) -> String {
    let trimmed = sanitizeFolderName(rawName)
    return trimmed.isEmpty ? "Untitled" : trimmed
  }

  private func ensureParentDirectory(for url: URL) throws {
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
  }

  private func prepareUbiquitousItemIfNeeded(at url: URL) throws {
    try? fileManager.startDownloadingUbiquitousItem(at: url)
  }

  private func makeItem(for url: URL, kind: VoiceWorkspaceDocumentKind) throws -> VoiceWorkspaceDocumentItem? {
    let values = try url.resourceValues(forKeys: [
      .isDirectoryKey,
      .contentModificationDateKey,
      .fileSizeKey,
      .ubiquitousItemDownloadingStatusKey,
    ])
    let isDirectory = values.isDirectory ?? false
    if !isDirectory {
      let lowercasedName = url.lastPathComponent.lowercased()
      guard kind.allowedExtensions.contains(where: { lowercasedName.hasSuffix(".\($0.lowercased())") }) else {
        return nil
      }
    }
    return VoiceWorkspaceDocumentItem(
      url: url,
      isDirectory: isDirectory,
      fileName: url.lastPathComponent,
      modifiedAt: values.contentModificationDate,
      fileSize: Int64(values.fileSize ?? 0)
    )
  }
}
