//
//  VoiceWorkspaceDocumentStore.swift
//
//
//  Created by Codex on 2026/4/20.
//

import Foundation
import HamsterKit
import PencilKit
import UIKit

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
      try? fileManager.startDownloadingUbiquitousItem(at: directoryURL)
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
      urls.forEach { url in
        try? fileManager.startDownloadingUbiquitousItem(at: url)
      }
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
  func createCanvasDocument(
    named rawName: String,
    drawing: PKDrawing,
    pathComponents: [String],
    traitCollection: UITraitCollection = .current
  ) throws -> URL {
    let url = try targetFileURL(for: .canvas, rawName: rawName, pathComponents: pathComponents)
    try saveCanvas(drawing: drawing, to: url, traitCollection: traitCollection)
    return url
  }

  func saveCanvas(
    drawing: PKDrawing,
    to url: URL,
    traitCollection: UITraitCollection = .current
  ) throws {
    try ensureParentDirectory(for: url)
    try drawing.dataRepresentation().write(to: url, options: .atomic)
    try Self.writeCanvasMetadata(for: drawing, canvasURL: url, traitCollection: traitCollection)
    try Self.writeCanvasPreview(for: drawing, canvasURL: url, traitCollection: traitCollection)
  }

  func loadCanvas(from url: URL) throws -> PKDrawing {
    try loadCanvas(from: url, traitCollection: .current)
  }

  func loadRawCanvas(from url: URL) throws -> PKDrawing {
    try prepareUbiquitousItemIfNeeded(at: url)
    let data = try Data(contentsOf: url, options: [])
    return try PKDrawing(data: data)
  }

  func loadCanvas(from url: URL, traitCollection: UITraitCollection) throws -> PKDrawing {
    try prepareUbiquitousItemIfNeeded(at: url)
    let data = try Data(contentsOf: url, options: [])
    let drawing = try PKDrawing(data: data)
    return Self.drawingWithResolvedCanvasColors(drawing, canvasURL: url, traitCollection: traitCollection)
  }

  static func writeCanvasSemanticArtifacts(
    for drawing: PKDrawing,
    canvasURL: URL,
    traitCollection: UITraitCollection
  ) throws {
    try drawing.dataRepresentation().write(to: canvasURL, options: .atomic)
    try writeCanvasMetadata(for: drawing, canvasURL: canvasURL, traitCollection: traitCollection)
    try writeCanvasPreview(for: drawing, canvasURL: canvasURL, traitCollection: traitCollection)
  }

  static func drawingWithResolvedCanvasColors(_ drawing: PKDrawing, traitCollection: UITraitCollection) -> PKDrawing {
    guard !drawing.strokes.isEmpty else {
      return drawing
    }
    let rebuilt = drawing.strokes.map { stroke in
      guard let metadata = inferredCanvasColorMetadata(for: stroke) else {
        return stroke
      }
      let resolvedColor: UIColor
      switch metadata.semantic {
      case .label:
        resolvedColor = UIColor.label.resolvedColor(with: traitCollection).withAlphaComponent(metadata.alpha)
      }
      let ink = PKInk(stroke.ink.inkType, color: resolvedColor)
      if #available(iOS 16.0, *) {
        return PKStroke(
          ink: ink,
          path: stroke.path,
          transform: stroke.transform,
          mask: stroke.mask,
          randomSeed: stroke.randomSeed
        )
      } else {
        return PKStroke(
          ink: ink,
          path: stroke.path,
          transform: stroke.transform,
          mask: stroke.mask
        )
      }
    }
    return PKDrawing(strokes: rebuilt)
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
    if !item.isDirectory {
      try? fileManager.removeItem(at: Self.canvasPreviewSidecarURL(for: item.url))
      try? fileManager.removeItem(at: Self.canvasMetadataSidecarURL(for: item.url))
    }
    try fileManager.removeItem(at: item.url)
  }

  @discardableResult
  func renameItem(_ item: VoiceWorkspaceDocumentItem, to rawName: String, kind: VoiceWorkspaceDocumentKind) throws -> VoiceWorkspaceDocumentItem {
    let sanitizedBase = item.isDirectory ? sanitizeFolderName(rawName) : sanitizeFileName(rawName)
    guard !sanitizedBase.isEmpty else { return item }

    let targetURL: URL
    if item.isDirectory {
      targetURL = item.url.deletingLastPathComponent().appendingPathComponent(sanitizedBase, isDirectory: true)
    } else {
      let finalName: String
      if sanitizedBase.lowercased().hasSuffix(".\(kind.fileExtension.lowercased())") {
        finalName = sanitizedBase
      } else {
        finalName = "\(sanitizedBase).\(kind.fileExtension)"
      }
      targetURL = item.url.deletingLastPathComponent().appendingPathComponent(finalName, isDirectory: false)
    }

    if targetURL == item.url {
      return item
    }
    if fileManager.fileExists(atPath: targetURL.path) {
      throw CocoaError(.fileWriteFileExists)
    }
    if kind == .canvas, !item.isDirectory {
      let sourceMetadataURL = Self.canvasMetadataSidecarURL(for: item.url)
      let targetMetadataURL = Self.canvasMetadataSidecarURL(for: targetURL)
      if fileManager.fileExists(atPath: sourceMetadataURL.path) {
        try? fileManager.removeItem(at: targetMetadataURL)
        try? fileManager.moveItem(at: sourceMetadataURL, to: targetMetadataURL)
      }
    }
    if kind == .canvas, !item.isDirectory {
      let sourcePreviewURL = Self.canvasPreviewSidecarURL(for: item.url)
      let targetPreviewURL = Self.canvasPreviewSidecarURL(for: targetURL)
      if fileManager.fileExists(atPath: sourcePreviewURL.path) {
        try? fileManager.removeItem(at: targetPreviewURL)
        try? fileManager.moveItem(at: sourcePreviewURL, to: targetPreviewURL)
      }
    }
    try fileManager.moveItem(at: item.url, to: targetURL)
    return try makeItem(for: targetURL, kind: kind) ?? item
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
    if url.pathExtension.lowercased() == VoiceWorkspaceDocumentKind.canvas.fileExtension {
      try? fileManager.startDownloadingUbiquitousItem(at: Self.canvasMetadataSidecarURL(for: url))
      try? fileManager.startDownloadingUbiquitousItem(at: Self.canvasPreviewSidecarURL(for: url))
    }
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

  static func canvasPreviewSidecarURL(for canvasURL: URL) -> URL {
    let baseName = canvasURL.deletingPathExtension().lastPathComponent
    return canvasURL
      .deletingLastPathComponent()
      .appendingPathComponent(".\(baseName).preview.jpg", isDirectory: false)
  }

  static func canvasMetadataSidecarURL(for canvasURL: URL) -> URL {
    let baseName = canvasURL.deletingPathExtension().lastPathComponent
    return canvasURL
      .deletingLastPathComponent()
      .appendingPathComponent(".\(baseName).canvasmeta.json", isDirectory: false)
  }

  static func canvasPreviewImage(for drawing: PKDrawing, traitCollection: UITraitCollection) -> UIImage? {
    guard !drawing.bounds.isEmpty else { return nil }
    let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
    let size = bounds.size
    guard size.width > 1, size.height > 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let backgroundColor = UIColor.secondarySystemBackground.resolvedColor(with: traitCollection)
    return renderer.image { context in
      context.cgContext.setFillColor(backgroundColor.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: size))
      context.cgContext.setShouldAntialias(true)
      context.cgContext.setAllowsAntialiasing(true)
      for stroke in drawing.strokes {
        drawCanvasPreviewStroke(
          stroke,
          in: context.cgContext,
          translatingBy: CGPoint(x: -bounds.origin.x, y: -bounds.origin.y)
        )
      }
    }
  }

  static func canvasPreviewImage(forCanvasAt url: URL, traitCollection: UITraitCollection) -> UIImage? {
    guard let data = try? Data(contentsOf: url),
          let drawing = try? PKDrawing(data: data) else {
      return UIImage(contentsOfFile: canvasPreviewSidecarURL(for: url).path)
    }
    let resolvedDrawing = drawingWithResolvedCanvasColors(drawing, canvasURL: url, traitCollection: traitCollection)
    return canvasPreviewImage(for: resolvedDrawing, traitCollection: traitCollection)
  }

  private static func writeCanvasPreview(for drawing: PKDrawing, canvasURL: URL, traitCollection: UITraitCollection) throws {
    let previewURL = canvasPreviewSidecarURL(for: canvasURL)
    let resolvedDrawing = drawingWithResolvedCanvasColors(drawing, canvasURL: canvasURL, traitCollection: traitCollection)
    guard let image = canvasPreviewImage(for: resolvedDrawing, traitCollection: traitCollection),
          let data = image.jpegData(compressionQuality: 0.86) else {
      try? FileManager.default.removeItem(at: previewURL)
      return
    }
    try data.write(to: previewURL, options: .atomic)
  }

  private static func writeCanvasMetadata(for drawing: PKDrawing, canvasURL: URL, traitCollection: UITraitCollection) throws {
    let metadataURL = canvasMetadataSidecarURL(for: canvasURL)
    let strokes = drawing.strokes.map { stroke -> CanvasColorMetadata? in
      detectedCanvasColorMetadata(for: stroke, traitCollection: traitCollection)
    }
    guard strokes.contains(where: { $0 != nil }) else {
      try? FileManager.default.removeItem(at: metadataURL)
      return
    }
    let sidecar = CanvasMetadataSidecar(version: 1, strokes: strokes)
    let data = try JSONEncoder().encode(sidecar)
    try data.write(to: metadataURL, options: .atomic)
  }

  private static func loadCanvasMetadata(for canvasURL: URL) -> CanvasMetadataSidecar? {
    guard let data = try? Data(contentsOf: canvasMetadataSidecarURL(for: canvasURL)) else {
      return nil
    }
    return try? JSONDecoder().decode(CanvasMetadataSidecar.self, from: data)
  }

  private static func drawingWithResolvedCanvasColors(
    _ drawing: PKDrawing,
    canvasURL: URL,
    traitCollection: UITraitCollection
  ) -> PKDrawing {
    guard !drawing.strokes.isEmpty else {
      return drawing
    }
    let sidecar = loadCanvasMetadata(for: canvasURL)
    let rebuilt = drawing.strokes.enumerated().map { index, stroke in
      let metadata =
        if let sidecar, index < sidecar.strokes.count, let stored = sidecar.strokes[index] {
          stored
        } else {
          inferredCanvasColorMetadata(for: stroke)
        }
      guard let metadata else {
        return stroke
      }
      let resolvedColor: UIColor
      switch metadata.semantic {
      case .label:
        resolvedColor = UIColor.label.resolvedColor(with: traitCollection).withAlphaComponent(metadata.alpha)
      }
      let ink = PKInk(stroke.ink.inkType, color: resolvedColor)
      if #available(iOS 16.0, *) {
        return PKStroke(
          ink: ink,
          path: stroke.path,
          transform: stroke.transform,
          mask: stroke.mask,
          randomSeed: stroke.randomSeed
        )
      } else {
        return PKStroke(
          ink: ink,
          path: stroke.path,
          transform: stroke.transform,
          mask: stroke.mask
        )
      }
    }
    return PKDrawing(strokes: rebuilt)
  }


  private static func detectedCanvasColorMetadata(
    for stroke: PKStroke,
    traitCollection: UITraitCollection
  ) -> CanvasColorMetadata? {
    inferredCanvasColorMetadata(for: stroke)
      ?? detectDynamicCanvasColorMetadata(for: stroke.ink.color, traitCollection: traitCollection)
  }

  private static func inferredCanvasColorMetadata(for stroke: PKStroke) -> CanvasColorMetadata? {
    guard inferredSemanticColor(for: stroke.ink.inkType) != nil else {
      return nil
    }
    return CanvasColorMetadata(semantic: .label, alpha: stroke.ink.color.cgColor.alpha)
  }

  private static func inferredSemanticColor(for inkType: PKInk.InkType) -> CanvasColorMetadata.Semantic? {
    switch inkType {
    case .pen, .pencil, .marker:
      return .label
    default:
      if #available(iOS 17.0, *), inkType == .monoline || inkType == .fountainPen {
        return .label
      }
      return nil
    }
  }

  private static func detectDynamicCanvasColorMetadata(
    for color: UIColor,
    traitCollection: UITraitCollection
  ) -> CanvasColorMetadata? {
    let resolved = color.resolvedColor(with: traitCollection)
    let label = UIColor.label.resolvedColor(with: traitCollection)
    guard colorsMatchIgnoringAlpha(resolved, label) else {
      return nil
    }
    return CanvasColorMetadata(semantic: .label, alpha: resolved.cgColor.alpha)
  }

  private static func colorsMatchIgnoringAlpha(_ lhs: UIColor, _ rhs: UIColor, tolerance: CGFloat = 0.02) -> Bool {
    guard let left = normalizedRGBAComponents(for: lhs),
          let right = normalizedRGBAComponents(for: rhs) else {
      return false
    }
    return abs(left.red - right.red) <= tolerance &&
      abs(left.green - right.green) <= tolerance &&
      abs(left.blue - right.blue) <= tolerance
  }

  private static func normalizedRGBAComponents(for color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
      return (red, green, blue, alpha)
    }

    var white: CGFloat = 0
    if color.getWhite(&white, alpha: &alpha) {
      return (white, white, white, alpha)
    }

    let cgColor = color.cgColor
    let rgbSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    if let converted = cgColor.converted(to: rgbSpace, intent: .defaultIntent, options: nil),
       let components = converted.components {
      switch components.count {
      case 2:
        return (components[0], components[0], components[0], components[1])
      case 4:
        return (components[0], components[1], components[2], components[3])
      default:
        break
      }
    }

    return nil
  }

  private static func drawCanvasPreviewStroke(
    _ stroke: PKStroke,
    in context: CGContext,
    translatingBy translation: CGPoint
  ) {
    let lineWidth = canvasPreviewLineWidth(for: stroke)
    let points = stroke.path
      .interpolatedPoints(by: .distance(max(2, lineWidth / 2)))
      .map(\.location)
    guard points.count > 1 else { return }

    context.saveGState()
    context.setBlendMode(.normal)
    context.setStrokeColor(stroke.ink.color.cgColor)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.beginPath()
    context.move(to: CGPoint(x: points[0].x + translation.x, y: points[0].y + translation.y))
    for point in points.dropFirst() {
      context.addLine(to: CGPoint(x: point.x + translation.x, y: point.y + translation.y))
    }
    context.strokePath()
    context.restoreGState()
  }

  private static func canvasPreviewLineWidth(for stroke: PKStroke) -> CGFloat {
    if stroke.ink.inkType == .marker {
      return 12
    }
    if stroke.ink.inkType == .pencil {
      return 4
    }
    if #available(iOS 17.0, *), stroke.ink.inkType == .monoline {
      return 7
    }
    if #available(iOS 17.0, *), stroke.ink.inkType == .fountainPen {
      return 8
    }
    if #available(iOS 17.0, *), stroke.ink.inkType == .watercolor {
      return 16
    }
    if #available(iOS 17.0, *), stroke.ink.inkType == .crayon {
      return 10
    }
    return 6
  }
}
  private struct CanvasColorMetadata: Codable {
    enum Semantic: String, Codable {
      case label
    }

    let semantic: Semantic
    let alpha: CGFloat
  }

  private struct CanvasMetadataSidecar: Codable {
    let version: Int
    let strokes: [CanvasColorMetadata?]
  }
