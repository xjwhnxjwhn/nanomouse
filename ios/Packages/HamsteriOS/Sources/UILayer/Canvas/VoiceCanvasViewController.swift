//
//  VoiceCanvasViewController.swift
//
//
//  Created by Codex on 2026/2/13.
//

import HamsterKit
import HamsterUIKit
import PencilKit
import UniformTypeIdentifiers
import UIKit
import WebKit

struct VoiceCanvasFileItem: Hashable {
  let url: URL
  let fileName: String
  let fileSize: Int64
  let modifiedAt: Date
}

enum VoiceCanvasStoreError: LocalizedError {
  case imageEncodingFailed
  case textEncodingFailed

  var errorDescription: String? {
    switch self {
    case .imageEncodingFailed:
      return "图片编码失败，请重试。"
    case .textEncodingFailed:
      return "文本编码失败，请重试。"
    }
  }
}

struct VoiceCausalEdgeDraft: Codable, Hashable {
  let id: String
  var from: String
  var to: String
  var note: String

  init(id: String = UUID().uuidString.lowercased(), from: String = "", to: String = "", note: String = "") {
    self.id = id
    self.from = from
    self.to = to
    self.note = note
  }
}

private final class VoiceCausalDraftStore {
  static let shared = VoiceCausalDraftStore()

  private enum Constants {
    static let edgesKey = "voice.canvas.causal.edges"
  }

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .hamster) {
    self.userDefaults = userDefaults
  }

  func loadEdges() -> [VoiceCausalEdgeDraft] {
    guard let data = userDefaults.data(forKey: Constants.edgesKey) else { return [] }
    let decoder = JSONDecoder()
    return (try? decoder.decode([VoiceCausalEdgeDraft].self, from: data)) ?? []
  }

  func saveEdges(_ edges: [VoiceCausalEdgeDraft]) {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(edges) else { return }
    userDefaults.set(data, forKey: Constants.edgesKey)
  }
}

final class VoiceCanvasStorageStore {
  static let shared = VoiceCanvasStorageStore()

  private enum Constants {
    static let rootDirectoryName = "CanvasExports"
    static let defaultJPEGQuality: CGFloat = 0.28
  }

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  var rootDirectoryURL: URL {
    FileManager.shareURL.appendingPathComponent(Constants.rootDirectoryName, isDirectory: true)
  }

  var rootDisplayPath: String {
    rootDirectoryURL.path
  }

  var defaultJPEGQuality: CGFloat {
    Constants.defaultJPEGQuality
  }

  func ensureDirectory() throws {
    try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
  }

  @discardableResult
  func saveJPEG(image: UIImage, compressionQuality: CGFloat = Constants.defaultJPEGQuality) throws -> VoiceCanvasFileItem {
    try ensureDirectory()
    let quality = min(max(compressionQuality, 0.05), 0.95)
    guard let data = image.jpegData(compressionQuality: quality) else {
      throw VoiceCanvasStoreError.imageEncodingFailed
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let name = "canvas_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(8)).jpg"
    let url = rootDirectoryURL.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url, options: .atomic)
    return try makeFileItem(from: url)
  }

  @discardableResult
  func saveTextFile(content: String, fileExtension: String = "mmd", prefix: String = "causal_mermaid") throws -> VoiceCanvasFileItem {
    try ensureDirectory()
    guard let data = content.data(using: .utf8) else {
      throw VoiceCanvasStoreError.textEncodingFailed
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let name = "\(prefix)_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(8)).\(fileExtension)"
    let url = rootDirectoryURL.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url, options: .atomic)
    return try makeFileItem(from: url)
  }

  func relativePath(for item: VoiceCanvasFileItem) -> String {
    "\(Constants.rootDirectoryName)/\(item.fileName)"
  }

  func resolveURL(relativePath: String) -> URL {
    FileManager.shareURL.appendingPathComponent(relativePath)
  }

  func loadFiles() -> [VoiceCanvasFileItem] {
    try? ensureDirectory()
    guard let fileURLs = try? fileManager.contentsOfDirectory(
      at: rootDirectoryURL,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return fileURLs.compactMap { try? makeFileItem(from: $0) }
      .sorted { $0.modifiedAt > $1.modifiedAt }
  }

  func deleteFile(_ item: VoiceCanvasFileItem) {
    try? fileManager.removeItem(at: item.url)
  }

  func deleteAllFiles() {
    let files = loadFiles()
    for item in files {
      deleteFile(item)
    }
  }

  private func makeFileItem(from url: URL) throws -> VoiceCanvasFileItem {
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw CocoaError(.fileNoSuchFile)
    }
    let name = url.lastPathComponent
    let size = Int64(values.fileSize ?? 0)
    let modifiedAt = values.contentModificationDate ?? Date.distantPast
    return VoiceCanvasFileItem(url: url, fileName: name, fileSize: size, modifiedAt: modifiedAt)
  }
}

@MainActor
final class VoiceCanvasViewController: NibLessViewController {
  private enum CanvasMode: Int {
    case draw = 0
    case markdown = 1
    case causal = 2
  }

  private let canvasStore: VoiceCanvasStorageStore = .shared
  private let workspaceStore: VoiceWorkspaceDocumentStore = .shared
  private let canvasBridge: AppCanvasBridge = .shared
  private let causalDraftStore: VoiceCausalDraftStore = .shared
  private let markdownDraftDefaults: UserDefaults = .hamster
  private var activeRequestId: String?
  private var hasCompletedCurrentKeyboardSession = false
  private var toolPicker: PKToolPicker?
  private var isToolPickerVisible = true
  private var currentMode: CanvasMode = .draw
  private var causalEdges: [VoiceCausalEdgeDraft] = []
  private var causalRows: [VoiceCausalEdgeRowView] = []
  private var pendingCausalRenderWorkItem: DispatchWorkItem?
  private var isCausalRendererReady = false
  private var pendingMarkdownRenderWorkItem: DispatchWorkItem?
  private var isMarkdownRendererReady = false
  private var suppressDoneTapOnce = false
  private var canvasDocumentItems: [VoiceWorkspaceDocumentItem] = []
  private var canvasPathComponents: [String] = []
  private var markdownPathComponents: [String] = []
  private var causalPathComponents: [String] = []
  private var activeCanvasDocumentURL: URL?
  private var activeMarkdownDocumentURL: URL?
  private var activeCausalDocumentURL: URL?
  private var lastSavedCanvasSignature: Data?
  private var lastSavedMarkdownSignature: String?
  private var lastSavedCausalSignature: Data?
  private var markdownQuickActionButtons: [UIButton] = []
  private var availableMarkdownFontOptions: [MarkdownFontOption] = []
  private var selectedMarkdownFontOption: MarkdownFontOption = .systemDefault

  private enum MarkdownDraftConstants {
    static let contentKey = "voice.markdown.draft.content"
    static let fontKey = "voice.markdown.draft.font"
  }

  private enum MarkdownQuickAction: CaseIterable {
    case h1
    case h2
    case bold
    case italic
    case blockquote
    case unorderedList
    case orderedList
    case todo
    case inlineCode
    case codeBlock
    case link
    case image
    case table
    case mermaid

    var title: String {
      switch self {
      case .h1: return "H1"
      case .h2: return "H2"
      case .bold: return "B"
      case .italic: return "I"
      case .blockquote: return "引"
      case .unorderedList: return "•"
      case .orderedList: return "1."
      case .todo: return "☑"
      case .inlineCode: return "` `"
      case .codeBlock: return "```"
      case .link: return "链"
      case .image: return "图"
      case .table: return "表"
      case .mermaid: return "Mer"
      }
    }
  }

  private struct MarkdownFontOption: Equatable {
    static let systemIdentifier = "__system__"
    static let systemDefault = MarkdownFontOption(
      identifier: systemIdentifier,
      displayName: "系统默认",
      editorFont: .systemFont(ofSize: 15, weight: .regular),
      cssFontFamily: "-apple-system, BlinkMacSystemFont, 'PingFang SC', 'SF Pro Text', sans-serif"
    )

    let identifier: String
    let displayName: String
    let editorFont: UIFont
    let cssFontFamily: String
  }

  private struct MarkdownFontPreset {
    let displayName: String
    let candidates: [String]
    let cssFallback: String
  }

  private static let markdownRendererFallbackHTML: String = """
  <!doctype html>
  <html lang="zh-CN">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <style>
        html, body {
          margin: 0;
          padding: 0;
          width: 100%;
          height: 100%;
          background: transparent;
          font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "SF Pro Text", sans-serif;
        }
        #content {
          box-sizing: border-box;
          width: 100%;
          height: 100%;
          overflow: auto;
          white-space: pre-wrap;
          line-height: 1.55;
          padding: 12px;
          font-size: 14px;
          color: #111827;
        }
      </style>
    </head>
    <body>
      <div id="content"></div>
      <script>
        window.__markdownRenderReady = false;
        window.renderMarkdown = function renderMarkdown(source, _isDark, fontFamily) {
          const el = document.getElementById("content");
          if (fontFamily && typeof fontFamily === "string") {
            el.style.fontFamily = fontFamily;
          }
          el.textContent = source || "";
          window.__markdownRenderReady = true;
        };
        window.isMarkdownReady = function isMarkdownReady() {
          return window.__markdownRenderReady === true;
        };
      </script>
    </body>
  </html>
  """

  private static let markdownFontPresets: [MarkdownFontPreset] = [
    .init(displayName: "PingFang SC", candidates: ["PingFangSC-Regular", "PingFang SC"], cssFallback: "-apple-system, sans-serif"),
    .init(displayName: "PingFang TC", candidates: ["PingFangTC-Regular", "PingFang TC"], cssFallback: "-apple-system, sans-serif"),
    .init(displayName: "Songti SC", candidates: ["SongtiSC-Regular", "Songti SC"], cssFallback: "'Noto Serif CJK SC', serif"),
    .init(displayName: "Kaiti SC", candidates: ["KaitiSC-Regular", "Kaiti SC"], cssFallback: "'STKaiti', serif"),
    .init(displayName: "Heiti SC", candidates: ["STHeitiSC-Light", "Heiti SC"], cssFallback: "'Hiragino Sans GB', sans-serif"),
    .init(displayName: "Hiragino Sans GB", candidates: ["HiraginoSansGB-W3", "Hiragino Sans GB"], cssFallback: "'PingFang SC', sans-serif"),
    .init(displayName: "STFangsong", candidates: ["STFangsong", "FangSong"], cssFallback: "'Songti SC', serif"),
    .init(displayName: "STSong", candidates: ["STSongti-SC-Regular", "STSong"], cssFallback: "'Songti SC', serif"),
    .init(displayName: "Helvetica Neue", candidates: ["HelveticaNeue", "Helvetica Neue"], cssFallback: "Helvetica, Arial, sans-serif"),
    .init(displayName: "Avenir Next", candidates: ["AvenirNext-Regular", "Avenir Next"], cssFallback: "-apple-system, sans-serif"),
    .init(displayName: "Georgia", candidates: ["Georgia"], cssFallback: "'Times New Roman', serif"),
    .init(displayName: "Times New Roman", candidates: ["TimesNewRomanPSMT", "Times New Roman"], cssFallback: "Times, serif"),
    .init(displayName: "Menlo", candidates: ["Menlo-Regular", "Menlo"], cssFallback: "ui-monospace, monospace"),
    .init(displayName: "Courier New", candidates: ["CourierNewPSMT", "Courier New"], cssFallback: "Courier, monospace"),
    .init(displayName: "SF Mono", candidates: ["SFMono-Regular"], cssFallback: "Menlo, ui-monospace, monospace"),
  ]

  private lazy var screenTapGestureRecognizer: UITapGestureRecognizer = {
    let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleScreenTap(_:)))
    recognizer.cancelsTouchesInView = false
    return recognizer
  }()

  private lazy var canvasWakeOverlayView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.isHidden = true
    view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleCanvasWakeTap)))
    return view
  }()

  private lazy var canvasWakeHintLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .medium)
    label.textColor = .tertiaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    label.text = nil
    label.isHidden = true
    return label
  }()

  private lazy var titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 34, weight: .bold)
    label.textColor = .label
    label.text = "画布"
    return label
  }()

  private lazy var documentsButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.tinted()
    configuration.image = UIImage(systemName: "folder")
    configuration.title = "文件"
    configuration.imagePadding = 6
    configuration.baseForegroundColor = .label
    configuration.baseBackgroundColor = .secondarySystemFill
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    button.configuration = configuration
    button.addTarget(self, action: #selector(handleDocumentsTap), for: .touchUpInside)
    return button
  }()

  private lazy var statusLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .secondaryLabel
    label.numberOfLines = 1
    label.lineBreakMode = .byClipping
    label.text = ""
    return label
  }()

  private lazy var statusScrollView: UIScrollView = {
    let view = UIScrollView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.alwaysBounceHorizontal = true
    view.showsHorizontalScrollIndicator = false
    view.showsVerticalScrollIndicator = false
    return view
  }()

  private lazy var statusContentView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var modeSegmentedControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["画布", "Markdown", "因果图"])
    control.translatesAutoresizingMaskIntoConstraints = false
    control.selectedSegmentIndex = CanvasMode.draw.rawValue
    control.addTarget(self, action: #selector(handleModeChanged(_:)), for: .valueChanged)
    return control
  }()

  private lazy var canvasContainerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .secondarySystemBackground
    view.layer.cornerRadius = 14
    view.layer.masksToBounds = true
    return view
  }()

  private lazy var canvasView: PKCanvasView = {
    let view = PKCanvasView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.drawingPolicy = .anyInput
    view.isScrollEnabled = false
    view.alwaysBounceVertical = false
    view.alwaysBounceHorizontal = false
    view.isOpaque = false
    return view
  }()

  private lazy var causalContainerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.isHidden = true
    return view
  }()

  private lazy var markdownContainerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.isHidden = true
    return view
  }()

  private lazy var markdownEditorContainerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .secondarySystemBackground
    view.layer.cornerRadius = 12
    view.layer.masksToBounds = true
    return view
  }()

  private lazy var markdownToolbarScrollView: UIScrollView = {
    let view = UIScrollView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.showsHorizontalScrollIndicator = false
    view.alwaysBounceHorizontal = true
    return view
  }()

  private lazy var markdownToolbarStackView: UIStackView = {
    let view = UIStackView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.axis = .horizontal
    view.alignment = .fill
    view.spacing = 8
    return view
  }()

  private lazy var markdownToolbarDividerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .separator
    return view
  }()

  private lazy var markdownFontPickerButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("字体", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.setTitleColor(.label, for: .normal)
    button.backgroundColor = .tertiarySystemFill
    button.layer.cornerRadius = 10
    button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
    button.addTarget(self, action: #selector(handleMarkdownFontPickerTap(_:)), for: .touchUpInside)
    return button
  }()

  private lazy var markdownTextView: UITextView = {
    let view = UITextView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.textColor = .label
    view.font = .systemFont(ofSize: 15, weight: .regular)
    view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    view.autocapitalizationType = .sentences
    view.autocorrectionType = .default
    view.keyboardDismissMode = .interactive
    view.delegate = self
    return view
  }()

  private lazy var markdownPlaceholderLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .regular)
    label.textColor = .tertiaryLabel
    label.numberOfLines = 2
    label.text = "输入 Markdown，例如：\n```mermaid\\nflowchart TD\\nA --> B\\n```"
    return label
  }()

  private lazy var markdownPreviewTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .secondaryLabel
    label.text = "预览"
    return label
  }()

  private lazy var markdownPreviewContainerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .tertiarySystemBackground
    view.layer.cornerRadius = 12
    view.layer.masksToBounds = true
    return view
  }()

  private lazy var markdownPreviewWebView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.navigationDelegate = self
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.backgroundColor = .clear
    view.scrollView.isScrollEnabled = false
    return view
  }()

  private lazy var causalHintLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "添加“原因→结果”关系后，系统会自动生成关系图。"
    return label
  }()

  private lazy var causalRowsScrollView: UIScrollView = {
    let view = UIScrollView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.showsVerticalScrollIndicator = true
    view.keyboardDismissMode = .onDrag
    return view
  }()

  private lazy var causalRowsContentView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var causalRowsStackView: UIStackView = {
    let stack = UIStackView(frame: .zero)
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 10
    stack.alignment = .fill
    return stack
  }()

  private lazy var addCausalEdgeButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
    button.setTitle(" 添加关系", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    button.addTarget(self, action: #selector(handleAddCausalEdgeTap), for: .touchUpInside)
    return button
  }()

  private lazy var causalPreviewTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .secondaryLabel
    label.text = "关系图预览"
    return label
  }()

  private lazy var causalPreviewContainerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .tertiarySystemBackground
    view.layer.cornerRadius = 10
    view.layer.masksToBounds = true
    return view
  }()

  private lazy var causalPreviewWebView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.navigationDelegate = self
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.backgroundColor = .clear
    view.scrollView.isScrollEnabled = false
    return view
  }()

  private lazy var clearButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("清空", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
    button.addTarget(self, action: #selector(handleClearTap), for: .touchUpInside)
    return button
  }()

  private lazy var undoButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
    button.tintColor = .label
    button.backgroundColor = .tertiarySystemFill
    button.layer.cornerRadius = 16
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    button.widthAnchor.constraint(equalToConstant: 32).isActive = true
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    button.addTarget(self, action: #selector(handleUndoTap), for: .touchUpInside)
    button.isEnabled = false
    button.alpha = 0.4
    return button
  }()

  private lazy var redoButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "arrow.uturn.forward"), for: .normal)
    button.tintColor = .label
    button.backgroundColor = .tertiarySystemFill
    button.layer.cornerRadius = 16
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    button.widthAnchor.constraint(equalToConstant: 32).isActive = true
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    button.addTarget(self, action: #selector(handleRedoTap), for: .touchUpInside)
    button.isEnabled = false
    button.alpha = 0.4
    return button
  }()

  private lazy var historyButtonStackView: UIStackView = {
    let stack = UIStackView(arrangedSubviews: [undoButton, redoButton])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .center
    stack.distribution = .fill
    stack.spacing = 8
    return stack
  }()

  private lazy var copyButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.tinted()
    configuration.image = UIImage(systemName: "doc.on.doc.fill")
    configuration.title = nil
    configuration.baseForegroundColor = .label
    configuration.baseBackgroundColor = .secondarySystemFill
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    button.configuration = configuration
    button.setTitle(nil, for: .normal)
    button.setTitle(nil, for: .highlighted)
    button.setTitle(nil, for: .selected)
    button.setTitle(nil, for: .disabled)
    button.widthAnchor.constraint(equalToConstant: 42).isActive = true
    button.heightAnchor.constraint(equalToConstant: 42).isActive = true
    button.accessibilityLabel = "复制到剪贴板"
    button.addTarget(self, action: #selector(handleCopyTap), for: .touchUpInside)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDoneLongPress(_:)))
    longPress.minimumPressDuration = 0.45
    longPress.cancelsTouchesInView = true
    button.addGestureRecognizer(longPress)
    return button
  }()

  private lazy var newDocumentButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.tinted()
    configuration.image = UIImage(systemName: "plus")
    configuration.title = nil
    configuration.baseForegroundColor = .label
    configuration.baseBackgroundColor = .secondarySystemFill
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    button.configuration = configuration
    button.setTitle(nil, for: .normal)
    button.setTitle(nil, for: .highlighted)
    button.setTitle(nil, for: .selected)
    button.setTitle(nil, for: .disabled)
    button.widthAnchor.constraint(equalToConstant: 42).isActive = true
    button.heightAnchor.constraint(equalToConstant: 42).isActive = true
    button.accessibilityLabel = "新建未命名文件"
    button.addTarget(self, action: #selector(handleNewUntitledDocumentTap), for: .touchUpInside)
    return button
  }()

  private lazy var saveToFileButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.tinted()
    configuration.image = UIImage(systemName: "square.and.arrow.down")
    configuration.title = nil
    configuration.baseForegroundColor = .label
    configuration.baseBackgroundColor = .secondarySystemFill
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    button.configuration = configuration
    button.setTitle(nil, for: .normal)
    button.setTitle(nil, for: .highlighted)
    button.setTitle(nil, for: .selected)
    button.setTitle(nil, for: .disabled)
    button.widthAnchor.constraint(equalToConstant: 42).isActive = true
    button.heightAnchor.constraint(equalToConstant: 42).isActive = true
    button.accessibilityLabel = "保存到文件系统"
    button.addTarget(self, action: #selector(handleSaveToFileTap), for: .touchUpInside)
    return button
  }()

  private lazy var bottomBarView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var bottomBarDividerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .separator
    return view
  }()

  override func loadView() {
    view = NibLessView()
    title = nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    availableMarkdownFontOptions = buildMarkdownFontOptions()
    setupView()
    setupMarkdownRendererIfNeeded()
    setupCausalRendererIfNeeded()
    restoreMarkdownDraftIfNeeded()
    loadCausalDraft()
    applyCanvasMode(.draw, force: true)
    reloadDocumentItems()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    setupToolPickerIfNeeded()
    if currentMode == .draw {
      if let requestId = activeRequestId, !hasCompletedCurrentKeyboardSession {
        setToolPickerVisible(true)
        canvasBridge.setState(requestId: requestId, state: .drawing)
        if statusLabel.text?.isEmpty ?? true {
          statusLabel.text = "已从键盘进入画布。画完后点击“完成”，返回宿主 App 即可粘贴图片。"
        }
      } else {
        // 普通切换到画布页时默认收起工具栏，避免遮挡底部 Tab。
        setToolPickerVisible(false)
      }
    } else {
      setToolPickerVisible(false)
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    lockCanvasToVisibleBounds()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
    if currentMode == .causal {
      scheduleCausalRender()
    }
  }

  func startCanvasSession(requestId: String) {
    activeRequestId = requestId
    hasCompletedCurrentKeyboardSession = false
    canvasBridge.setState(requestId: requestId, state: .drawing)
    if isViewLoaded {
      applyCanvasMode(.draw, force: true)
      canvasView.drawing = PKDrawing()
      setToolPickerVisible(true)
      statusLabel.text = "已从键盘进入画布。复制后返回宿主 App，即可粘贴图片。"
    }
  }

  func startMarkdownSession(requestId: String) {
    activeRequestId = requestId
    hasCompletedCurrentKeyboardSession = false
    canvasBridge.setState(requestId: requestId, state: .drawing)
    if isViewLoaded {
      applyCanvasMode(.markdown, force: true)
      statusLabel.text = "已从键盘进入 Markdown。复制后返回宿主 App 可粘贴图片。"
    }
  }

  private func setupView() {
    view.backgroundColor = .systemBackground
    view.addGestureRecognizer(screenTapGestureRecognizer)
    view.addSubview(documentsButton)
    view.addSubview(titleLabel)
    view.addSubview(statusScrollView)
    statusScrollView.addSubview(statusContentView)
    statusContentView.addSubview(statusLabel)
    view.addSubview(modeSegmentedControl)
    view.addSubview(canvasContainerView)
    canvasContainerView.addSubview(canvasView)
    canvasContainerView.addSubview(canvasWakeOverlayView)
    canvasWakeOverlayView.addSubview(canvasWakeHintLabel)
    setupCausalLayout()
    setupMarkdownLayout()
    view.addSubview(bottomBarView)
    bottomBarView.addSubview(bottomBarDividerView)
    bottomBarView.addSubview(clearButton)
    bottomBarView.addSubview(historyButtonStackView)
    bottomBarView.addSubview(newDocumentButton)
    bottomBarView.addSubview(copyButton)
    bottomBarView.addSubview(saveToFileButton)
    canvasView.delegate = self

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: documentsButton.leadingAnchor, constant: -12),

      documentsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      documentsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

      statusScrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      statusScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      statusScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      statusScrollView.heightAnchor.constraint(equalToConstant: 20),

      statusContentView.topAnchor.constraint(equalTo: statusScrollView.contentLayoutGuide.topAnchor),
      statusContentView.leadingAnchor.constraint(equalTo: statusScrollView.contentLayoutGuide.leadingAnchor),
      statusContentView.trailingAnchor.constraint(equalTo: statusScrollView.contentLayoutGuide.trailingAnchor),
      statusContentView.bottomAnchor.constraint(equalTo: statusScrollView.contentLayoutGuide.bottomAnchor),
      statusContentView.heightAnchor.constraint(equalTo: statusScrollView.frameLayoutGuide.heightAnchor),
      statusContentView.widthAnchor.constraint(greaterThanOrEqualTo: statusScrollView.frameLayoutGuide.widthAnchor),

      statusLabel.leadingAnchor.constraint(equalTo: statusContentView.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: statusContentView.trailingAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: statusContentView.centerYAnchor),

      modeSegmentedControl.topAnchor.constraint(equalTo: statusScrollView.bottomAnchor, constant: 10),
      modeSegmentedControl.leadingAnchor.constraint(equalTo: statusScrollView.leadingAnchor),
      modeSegmentedControl.trailingAnchor.constraint(equalTo: statusScrollView.trailingAnchor),

      bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bottomBarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

      bottomBarDividerView.topAnchor.constraint(equalTo: bottomBarView.topAnchor),
      bottomBarDividerView.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor),
      bottomBarDividerView.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor),
      bottomBarDividerView.heightAnchor.constraint(equalToConstant: 0.5),

      clearButton.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 20),
      clearButton.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),

      historyButtonStackView.leadingAnchor.constraint(equalTo: clearButton.trailingAnchor, constant: 10),
      historyButtonStackView.trailingAnchor.constraint(lessThanOrEqualTo: newDocumentButton.leadingAnchor, constant: -10),
      historyButtonStackView.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),

      saveToFileButton.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -20),
      saveToFileButton.topAnchor.constraint(equalTo: bottomBarDividerView.bottomAnchor, constant: 10),
      saveToFileButton.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: -10),

      newDocumentButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
      newDocumentButton.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),

      copyButton.trailingAnchor.constraint(equalTo: saveToFileButton.leadingAnchor, constant: -10),
      copyButton.centerYAnchor.constraint(equalTo: saveToFileButton.centerYAnchor),

      canvasContainerView.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 12),
      canvasContainerView.leadingAnchor.constraint(equalTo: statusScrollView.leadingAnchor),
      canvasContainerView.trailingAnchor.constraint(equalTo: statusScrollView.trailingAnchor),
      canvasContainerView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: -12),

      canvasView.topAnchor.constraint(equalTo: canvasContainerView.topAnchor),
      canvasView.leadingAnchor.constraint(equalTo: canvasContainerView.leadingAnchor),
      canvasView.trailingAnchor.constraint(equalTo: canvasContainerView.trailingAnchor),
      canvasView.bottomAnchor.constraint(equalTo: canvasContainerView.bottomAnchor),

      canvasWakeOverlayView.topAnchor.constraint(equalTo: canvasContainerView.topAnchor),
      canvasWakeOverlayView.leadingAnchor.constraint(equalTo: canvasContainerView.leadingAnchor),
      canvasWakeOverlayView.trailingAnchor.constraint(equalTo: canvasContainerView.trailingAnchor),
      canvasWakeOverlayView.bottomAnchor.constraint(equalTo: canvasContainerView.bottomAnchor),

      canvasWakeHintLabel.centerXAnchor.constraint(equalTo: canvasWakeOverlayView.centerXAnchor),
      canvasWakeHintLabel.centerYAnchor.constraint(equalTo: canvasWakeOverlayView.centerYAnchor),
      canvasWakeHintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: canvasWakeOverlayView.leadingAnchor, constant: 20),
      canvasWakeHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: canvasWakeOverlayView.trailingAnchor, constant: -20),
    ])
  }

  @objc private func handleDocumentsTap() {
    let browser = VoiceWorkspaceDocumentBrowserViewController(
      kind: currentDocumentKind,
      store: workspaceStore,
      pathComponentsProvider: { [weak self] in self?.currentPathComponents ?? [] },
      setPathComponents: { [weak self] in self?.currentPathComponents = $0 },
      activeDocumentURLProvider: { [weak self] in self?.currentActiveDocumentURL },
      setActiveDocumentURL: { [weak self] in self?.currentActiveDocumentURL = $0 },
      createDocument: { [weak self] name, pathComponents in
        guard let self else { throw CocoaError(.userCancelled) }
        switch self.currentMode {
        case .draw:
          let url = try self.workspaceStore.createCanvasDocument(
            named: name,
            drawing: self.canvasView.drawing,
            pathComponents: pathComponents
          )
          self.activeCanvasDocumentURL = url
          self.statusLabel.text = "已创建画布文件：\(url.lastPathComponent)"
          return url
        case .markdown:
          let url = try self.workspaceStore.createMarkdownDocument(
            named: name,
            content: self.markdownTextView.text ?? "",
            pathComponents: pathComponents
          )
          self.activeMarkdownDocumentURL = url
          self.statusLabel.text = "已创建 Markdown 文件：\(url.lastPathComponent)"
          return url
        case .causal:
          let url = try self.workspaceStore.createCausalDocument(
            named: name,
            edges: self.causalEdges,
            pathComponents: pathComponents
          )
          self.activeCausalDocumentURL = url
          self.statusLabel.text = "已创建因果图文件：\(url.lastPathComponent)"
          return url
        }
      },
      saveDocument: { [weak self] url in
        guard let self else { return }
        switch self.currentMode {
        case .draw:
          try self.workspaceStore.saveCanvas(drawing: self.canvasView.drawing, to: url)
        case .markdown:
          try self.workspaceStore.saveMarkdown(content: self.markdownTextView.text ?? "", to: url)
        case .causal:
          try self.workspaceStore.saveCausal(edges: self.causalEdges, to: url)
        }
        self.statusLabel.text = "已保存：\(url.lastPathComponent)"
      },
      loadDocument: { [weak self] url in
        guard let self else { return }
        switch self.currentMode {
        case .draw:
          let drawing = try self.workspaceStore.loadCanvas(from: url)
          self.canvasView.drawing = drawing
          self.canvasView.undoManager?.removeAllActions()
          self.activeCanvasDocumentURL = url
          self.setToolPickerVisible(false)
          self.statusLabel.text = "已打开画布文件：\(url.lastPathComponent)"
        case .markdown:
          let content = try self.workspaceStore.loadMarkdown(from: url)
          self.markdownTextView.text = content
          self.saveMarkdownDraftContent(content)
          self.activeMarkdownDocumentURL = url
          self.updateMarkdownPlaceholderState()
          self.scheduleMarkdownPreviewRender()
          self.statusLabel.text = "已打开 Markdown 文件：\(url.lastPathComponent)"
        case .causal:
          let edges = try self.workspaceStore.loadCausal(from: url)
          self.causalEdges = edges.isEmpty ? [VoiceCausalEdgeDraft()] : edges
          self.causalDraftStore.saveEdges(self.causalEdges)
          self.rebuildCausalRows()
          self.scheduleCausalRender()
          self.activeCausalDocumentURL = url
          self.statusLabel.text = "已打开因果图文件：\(url.lastPathComponent)"
        }
      },
      didDeleteDocument: { [weak self] url in
        guard let self else { return }
        if self.activeCanvasDocumentURL == url {
          self.activeCanvasDocumentURL = nil
        }
        if self.activeMarkdownDocumentURL == url {
          self.activeMarkdownDocumentURL = nil
        }
        if self.activeCausalDocumentURL == url {
          self.activeCausalDocumentURL = nil
        }
      }
    )
    if let sheet = browser.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
      sheet.preferredCornerRadius = 20
    }
    present(browser, animated: true)
  }

  private func setupCausalLayout() {
    canvasContainerView.addSubview(causalContainerView)
    causalContainerView.addSubview(causalHintLabel)
    causalContainerView.addSubview(causalRowsScrollView)
    causalRowsScrollView.addSubview(causalRowsContentView)
    causalRowsContentView.addSubview(causalRowsStackView)
    causalRowsContentView.addSubview(addCausalEdgeButton)
    causalContainerView.addSubview(causalPreviewTitleLabel)
    causalContainerView.addSubview(causalPreviewContainerView)
    causalPreviewContainerView.addSubview(causalPreviewWebView)

    NSLayoutConstraint.activate([
      causalContainerView.topAnchor.constraint(equalTo: canvasContainerView.topAnchor),
      causalContainerView.leadingAnchor.constraint(equalTo: canvasContainerView.leadingAnchor),
      causalContainerView.trailingAnchor.constraint(equalTo: canvasContainerView.trailingAnchor),
      causalContainerView.bottomAnchor.constraint(equalTo: canvasContainerView.bottomAnchor),

      causalHintLabel.topAnchor.constraint(equalTo: causalContainerView.topAnchor, constant: 10),
      causalHintLabel.leadingAnchor.constraint(equalTo: causalContainerView.leadingAnchor, constant: 12),
      causalHintLabel.trailingAnchor.constraint(equalTo: causalContainerView.trailingAnchor, constant: -12),

      causalRowsScrollView.topAnchor.constraint(equalTo: causalHintLabel.bottomAnchor, constant: 8),
      causalRowsScrollView.leadingAnchor.constraint(equalTo: causalContainerView.leadingAnchor, constant: 12),
      causalRowsScrollView.trailingAnchor.constraint(equalTo: causalContainerView.trailingAnchor, constant: -12),
      causalRowsScrollView.heightAnchor.constraint(equalToConstant: 150),

      causalRowsContentView.topAnchor.constraint(equalTo: causalRowsScrollView.contentLayoutGuide.topAnchor),
      causalRowsContentView.leadingAnchor.constraint(equalTo: causalRowsScrollView.contentLayoutGuide.leadingAnchor),
      causalRowsContentView.trailingAnchor.constraint(equalTo: causalRowsScrollView.contentLayoutGuide.trailingAnchor),
      causalRowsContentView.bottomAnchor.constraint(equalTo: causalRowsScrollView.contentLayoutGuide.bottomAnchor),
      causalRowsContentView.widthAnchor.constraint(equalTo: causalRowsScrollView.frameLayoutGuide.widthAnchor),

      causalRowsStackView.topAnchor.constraint(equalTo: causalRowsContentView.topAnchor),
      causalRowsStackView.leadingAnchor.constraint(equalTo: causalRowsContentView.leadingAnchor),
      causalRowsStackView.trailingAnchor.constraint(equalTo: causalRowsContentView.trailingAnchor),

      addCausalEdgeButton.topAnchor.constraint(equalTo: causalRowsStackView.bottomAnchor, constant: 8),
      addCausalEdgeButton.leadingAnchor.constraint(equalTo: causalRowsContentView.leadingAnchor),
      addCausalEdgeButton.bottomAnchor.constraint(equalTo: causalRowsContentView.bottomAnchor),

      causalPreviewTitleLabel.topAnchor.constraint(equalTo: causalRowsScrollView.bottomAnchor, constant: 10),
      causalPreviewTitleLabel.leadingAnchor.constraint(equalTo: causalRowsScrollView.leadingAnchor),
      causalPreviewTitleLabel.trailingAnchor.constraint(equalTo: causalRowsScrollView.trailingAnchor),

      causalPreviewContainerView.topAnchor.constraint(equalTo: causalPreviewTitleLabel.bottomAnchor, constant: 6),
      causalPreviewContainerView.leadingAnchor.constraint(equalTo: causalRowsScrollView.leadingAnchor),
      causalPreviewContainerView.trailingAnchor.constraint(equalTo: causalRowsScrollView.trailingAnchor),
      causalPreviewContainerView.bottomAnchor.constraint(equalTo: causalContainerView.bottomAnchor, constant: -12),

      causalPreviewWebView.topAnchor.constraint(equalTo: causalPreviewContainerView.topAnchor),
      causalPreviewWebView.leadingAnchor.constraint(equalTo: causalPreviewContainerView.leadingAnchor),
      causalPreviewWebView.trailingAnchor.constraint(equalTo: causalPreviewContainerView.trailingAnchor),
      causalPreviewWebView.bottomAnchor.constraint(equalTo: causalPreviewContainerView.bottomAnchor),
    ])
  }

  private func setupMarkdownLayout() {
    canvasContainerView.addSubview(markdownContainerView)
    markdownContainerView.addSubview(markdownEditorContainerView)
    markdownEditorContainerView.addSubview(markdownToolbarScrollView)
    markdownToolbarScrollView.addSubview(markdownToolbarStackView)
    markdownEditorContainerView.addSubview(markdownToolbarDividerView)
    markdownEditorContainerView.addSubview(markdownTextView)
    markdownEditorContainerView.addSubview(markdownPlaceholderLabel)
    markdownContainerView.addSubview(markdownPreviewTitleLabel)
    markdownContainerView.addSubview(markdownPreviewContainerView)
    markdownPreviewContainerView.addSubview(markdownPreviewWebView)

    NSLayoutConstraint.activate([
      markdownContainerView.topAnchor.constraint(equalTo: canvasContainerView.topAnchor),
      markdownContainerView.leadingAnchor.constraint(equalTo: canvasContainerView.leadingAnchor),
      markdownContainerView.trailingAnchor.constraint(equalTo: canvasContainerView.trailingAnchor),
      markdownContainerView.bottomAnchor.constraint(equalTo: canvasContainerView.bottomAnchor),

      markdownEditorContainerView.topAnchor.constraint(equalTo: markdownContainerView.topAnchor, constant: 12),
      markdownEditorContainerView.leadingAnchor.constraint(equalTo: markdownContainerView.leadingAnchor, constant: 12),
      markdownEditorContainerView.trailingAnchor.constraint(equalTo: markdownContainerView.trailingAnchor, constant: -12),
      markdownEditorContainerView.heightAnchor.constraint(equalTo: markdownContainerView.heightAnchor, multiplier: 0.42),

      markdownToolbarScrollView.topAnchor.constraint(equalTo: markdownEditorContainerView.topAnchor, constant: 8),
      markdownToolbarScrollView.leadingAnchor.constraint(equalTo: markdownEditorContainerView.leadingAnchor, constant: 8),
      markdownToolbarScrollView.trailingAnchor.constraint(equalTo: markdownEditorContainerView.trailingAnchor, constant: -8),
      markdownToolbarScrollView.heightAnchor.constraint(equalToConstant: 38),

      markdownToolbarStackView.topAnchor.constraint(equalTo: markdownToolbarScrollView.contentLayoutGuide.topAnchor),
      markdownToolbarStackView.leadingAnchor.constraint(equalTo: markdownToolbarScrollView.contentLayoutGuide.leadingAnchor),
      markdownToolbarStackView.trailingAnchor.constraint(equalTo: markdownToolbarScrollView.contentLayoutGuide.trailingAnchor),
      markdownToolbarStackView.bottomAnchor.constraint(equalTo: markdownToolbarScrollView.contentLayoutGuide.bottomAnchor),
      markdownToolbarStackView.heightAnchor.constraint(equalTo: markdownToolbarScrollView.frameLayoutGuide.heightAnchor),

      markdownToolbarDividerView.topAnchor.constraint(equalTo: markdownToolbarScrollView.bottomAnchor, constant: 6),
      markdownToolbarDividerView.leadingAnchor.constraint(equalTo: markdownEditorContainerView.leadingAnchor),
      markdownToolbarDividerView.trailingAnchor.constraint(equalTo: markdownEditorContainerView.trailingAnchor),
      markdownToolbarDividerView.heightAnchor.constraint(equalToConstant: 0.5),

      markdownTextView.topAnchor.constraint(equalTo: markdownToolbarDividerView.bottomAnchor, constant: 4),
      markdownTextView.leadingAnchor.constraint(equalTo: markdownEditorContainerView.leadingAnchor),
      markdownTextView.trailingAnchor.constraint(equalTo: markdownEditorContainerView.trailingAnchor),
      markdownTextView.bottomAnchor.constraint(equalTo: markdownEditorContainerView.bottomAnchor),

      markdownPlaceholderLabel.topAnchor.constraint(equalTo: markdownTextView.topAnchor, constant: 12),
      markdownPlaceholderLabel.leadingAnchor.constraint(equalTo: markdownEditorContainerView.leadingAnchor, constant: 16),
      markdownPlaceholderLabel.trailingAnchor.constraint(equalTo: markdownEditorContainerView.trailingAnchor, constant: -16),

      markdownPreviewTitleLabel.topAnchor.constraint(equalTo: markdownEditorContainerView.bottomAnchor, constant: 10),
      markdownPreviewTitleLabel.leadingAnchor.constraint(equalTo: markdownEditorContainerView.leadingAnchor),
      markdownPreviewTitleLabel.trailingAnchor.constraint(equalTo: markdownEditorContainerView.trailingAnchor),

      markdownPreviewContainerView.topAnchor.constraint(equalTo: markdownPreviewTitleLabel.bottomAnchor, constant: 6),
      markdownPreviewContainerView.leadingAnchor.constraint(equalTo: markdownPreviewTitleLabel.leadingAnchor),
      markdownPreviewContainerView.trailingAnchor.constraint(equalTo: markdownPreviewTitleLabel.trailingAnchor),
      markdownPreviewContainerView.bottomAnchor.constraint(equalTo: markdownContainerView.bottomAnchor, constant: -12),

      markdownPreviewWebView.topAnchor.constraint(equalTo: markdownPreviewContainerView.topAnchor),
      markdownPreviewWebView.leadingAnchor.constraint(equalTo: markdownPreviewContainerView.leadingAnchor),
      markdownPreviewWebView.trailingAnchor.constraint(equalTo: markdownPreviewContainerView.trailingAnchor),
      markdownPreviewWebView.bottomAnchor.constraint(equalTo: markdownPreviewContainerView.bottomAnchor),
    ])

    setupMarkdownQuickActionButtons()
  }

  private var currentDocumentKind: VoiceWorkspaceDocumentKind {
    switch currentMode {
    case .draw:
      return .canvas
    case .markdown:
      return .markdown
    case .causal:
      return .causal
    }
  }

  private var currentPathComponents: [String] {
    get {
      switch currentMode {
      case .draw:
        return canvasPathComponents
      case .markdown:
        return markdownPathComponents
      case .causal:
        return causalPathComponents
      }
    }
    set {
      switch currentMode {
      case .draw:
        canvasPathComponents = newValue
      case .markdown:
        markdownPathComponents = newValue
      case .causal:
        causalPathComponents = newValue
      }
    }
  }

  private var currentActiveDocumentURL: URL? {
    get {
      switch currentMode {
      case .draw:
        return activeCanvasDocumentURL
      case .markdown:
        return activeMarkdownDocumentURL
      case .causal:
        return activeCausalDocumentURL
      }
    }
    set {
      switch currentMode {
      case .draw:
        activeCanvasDocumentURL = newValue
      case .markdown:
        activeMarkdownDocumentURL = newValue
      case .causal:
        activeCausalDocumentURL = newValue
      }
    }
  }

  private func reloadDocumentItems() {
    canvasDocumentItems = workspaceStore.listItems(for: currentDocumentKind, pathComponents: currentPathComponents)
  }

  private func updateDocumentPanelState() {
  }

  private func promptForName(title: String, message: String? = nil, actionTitle: String, completion: @escaping (String) -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "输入名称"
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in
      let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      completion(name)
    })
    present(alert, animated: true)
  }

  @objc private func handleDocumentBackTap() {
    guard !currentPathComponents.isEmpty else { return }
    currentPathComponents.removeLast()
    reloadDocumentItems()
  }

  @objc private func handleNewFolderTap() {
    promptForName(title: "新建文件夹", actionTitle: "创建") { [weak self] name in
      guard let self, !name.isEmpty else { return }
      do {
        try self.workspaceStore.createFolder(named: name, for: self.currentDocumentKind, pathComponents: self.currentPathComponents)
        self.reloadDocumentItems()
      } catch {
        self.statusLabel.text = "创建文件夹失败：\(error.localizedDescription)"
      }
    }
  }

  @objc private func handleNewDocumentTap() {
    promptForName(title: "新建文件", message: "会在当前文件夹下创建可继续编辑的源文件。", actionTitle: "创建") { [weak self] name in
      guard let self, !name.isEmpty else { return }
      self.createNewDocument(named: name)
    }
  }

  @objc private func handleSaveDocumentTap() {
    saveCurrentDocument(promptIfNeeded: true)
  }

  @discardableResult
  private func createNewDocument(named name: String) -> Bool {
    do {
      switch currentMode {
      case .draw:
        let url = try workspaceStore.createCanvasDocument(named: name, drawing: canvasView.drawing, pathComponents: currentPathComponents)
        activeCanvasDocumentURL = url
        lastSavedCanvasSignature = currentCanvasSignature()
        statusLabel.text = "已创建画布文件：\(url.lastPathComponent)"
      case .markdown:
        let url = try workspaceStore.createMarkdownDocument(named: name, content: markdownTextView.text ?? "", pathComponents: currentPathComponents)
        activeMarkdownDocumentURL = url
        lastSavedMarkdownSignature = currentMarkdownSignature()
        statusLabel.text = "已创建 Markdown 文件：\(url.lastPathComponent)"
      case .causal:
        let url = try workspaceStore.createCausalDocument(named: name, edges: causalEdges, pathComponents: currentPathComponents)
        activeCausalDocumentURL = url
        lastSavedCausalSignature = currentCausalSignature()
        statusLabel.text = "已创建因果图文件：\(url.lastPathComponent)"
      }
      reloadDocumentItems()
      return true
    } catch {
      statusLabel.text = "创建文件失败：\(error.localizedDescription)"
      return false
    }
  }

  private func saveCurrentDocument(promptIfNeeded: Bool) {
    if let currentActiveDocumentURL {
      do {
        switch currentMode {
        case .draw:
          try workspaceStore.saveCanvas(drawing: canvasView.drawing, to: currentActiveDocumentURL)
          lastSavedCanvasSignature = currentCanvasSignature()
        case .markdown:
          try workspaceStore.saveMarkdown(content: markdownTextView.text ?? "", to: currentActiveDocumentURL)
          lastSavedMarkdownSignature = currentMarkdownSignature()
        case .causal:
          try workspaceStore.saveCausal(edges: causalEdges, to: currentActiveDocumentURL)
          lastSavedCausalSignature = currentCausalSignature()
        }
        statusLabel.text = "已保存：\(currentActiveDocumentURL.lastPathComponent)"
        reloadDocumentItems()
      } catch {
        statusLabel.text = "保存失败：\(error.localizedDescription)"
      }
      return
    }

    guard promptIfNeeded else { return }
    promptForName(title: "保存文件", message: "输入文件名后保存到当前文件夹。", actionTitle: "保存") { [weak self] name in
      guard let self, !name.isEmpty else { return }
      self.createNewDocument(named: name)
    }
  }

  private func autosaveCurrentDocumentIfNeeded() {
    guard currentActiveDocumentURL != nil else { return }
    saveCurrentDocument(promptIfNeeded: false)
  }

  private func loadDocumentItem(_ item: VoiceWorkspaceDocumentItem) {
    if item.isDirectory {
      currentPathComponents.append(item.fileName)
      reloadDocumentItems()
      return
    }

    do {
      switch currentMode {
      case .draw:
        let drawing = try workspaceStore.loadCanvas(from: item.url)
        canvasView.drawing = drawing
        canvasView.undoManager?.removeAllActions()
        activeCanvasDocumentURL = item.url
        lastSavedCanvasSignature = currentCanvasSignature()
        setToolPickerVisible(false)
        statusLabel.text = "已打开画布文件：\(item.fileName)"
      case .markdown:
        let content = try workspaceStore.loadMarkdown(from: item.url)
        markdownTextView.text = content
        saveMarkdownDraftContent(content)
        activeMarkdownDocumentURL = item.url
        lastSavedMarkdownSignature = currentMarkdownSignature()
        updateMarkdownPlaceholderState()
        scheduleMarkdownPreviewRender()
        statusLabel.text = "已打开 Markdown 文件：\(item.fileName)"
      case .causal:
        let edges = try workspaceStore.loadCausal(from: item.url)
        causalEdges = edges.isEmpty ? [VoiceCausalEdgeDraft()] : edges
        causalDraftStore.saveEdges(causalEdges)
        rebuildCausalRows()
        scheduleCausalRender()
        activeCausalDocumentURL = item.url
        lastSavedCausalSignature = currentCausalSignature()
        statusLabel.text = "已打开因果图文件：\(item.fileName)"
      }
      reloadDocumentItems()
    } catch {
      statusLabel.text = "打开文件失败：\(error.localizedDescription)"
    }
  }

  private func setupToolPickerIfNeeded() {
    guard toolPicker == nil else { return }
    let picker = PKToolPicker()
    picker.addObserver(canvasView)
    toolPicker = picker
    isToolPickerVisible = false
    canvasWakeOverlayView.isHidden = false
    updateHistoryButtonsState()
  }

  private func setupCausalRendererIfNeeded() {
    let bundle = Bundle.module
    let htmlURL =
      bundle.url(forResource: "causal_renderer", withExtension: "html", subdirectory: "Causal")
      ?? bundle.url(forResource: "causal_renderer", withExtension: "html")
      ?? bundle.urls(forResourcesWithExtension: "html", subdirectory: nil)?
      .first(where: { $0.lastPathComponent == "causal_renderer.html" })

    guard let htmlURL else {
      statusLabel.text = "因果图渲染资源缺失，请重新安装应用。"
      return
    }
    isCausalRendererReady = false
    causalPreviewWebView.loadFileURL(htmlURL, allowingReadAccessTo: bundle.bundleURL)
  }

  private func loadCausalDraft() {
    let storedEdges = causalDraftStore.loadEdges()
    if storedEdges.isEmpty {
      causalEdges = [VoiceCausalEdgeDraft()]
    } else {
      causalEdges = storedEdges
    }
    rebuildCausalRows()
    scheduleCausalRender()
  }

  private func rebuildCausalRows() {
    for row in causalRows {
      row.removeFromSuperview()
    }
    causalRows.removeAll()

    if causalEdges.isEmpty {
      causalEdges = [VoiceCausalEdgeDraft()]
    }

    for edge in causalEdges {
      addRowView(for: edge)
    }
  }

  private func addRowView(for edge: VoiceCausalEdgeDraft) {
    let row = VoiceCausalEdgeRowView()
    row.apply(edge: edge)
    row.onChanged = { [weak self, weak row] in
      guard let self, let row else { return }
      self.updateEdgeFromRow(row)
    }
    row.onDelete = { [weak self, weak row] in
      guard let self, let row else { return }
      self.removeEdgeRow(row)
    }
    causalRows.append(row)
    causalRowsStackView.addArrangedSubview(row)
  }

  private func updateEdgeFromRow(_ row: VoiceCausalEdgeRowView) {
    guard let idx = causalRows.firstIndex(where: { $0 === row }) else { return }
    causalEdges[idx] = row.currentEdgeDraft(id: causalEdges[idx].id)
    causalDraftStore.saveEdges(causalEdges)
    scheduleCausalRender()
    autosaveCurrentDocumentIfNeeded()
  }

  private func removeEdgeRow(_ row: VoiceCausalEdgeRowView) {
    guard let idx = causalRows.firstIndex(where: { $0 === row }) else { return }
    if causalRows.count == 1 {
      row.apply(edge: VoiceCausalEdgeDraft(id: causalEdges[idx].id))
      causalEdges[idx] = VoiceCausalEdgeDraft(id: causalEdges[idx].id)
    } else {
      causalRows.remove(at: idx)
      causalEdges.remove(at: idx)
      row.removeFromSuperview()
    }
    causalDraftStore.saveEdges(causalEdges)
    scheduleCausalRender()
    autosaveCurrentDocumentIfNeeded()
  }

  private func scheduleCausalRender() {
    pendingCausalRenderWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.renderCausalPreview()
    }
    pendingCausalRenderWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
  }

  private func renderCausalPreview() {
    guard isCausalRendererReady else { return }
    let mermaid = buildMermaidCode()
    let encodedMermaid = jsonStringLiteral(mermaid)
    let isDark = traitCollection.userInterfaceStyle == .dark
    let script = """
    window.renderMermaid(\(encodedMermaid), \(isDark ? "true" : "false"));
    null;
    """
    causalPreviewWebView.evaluateJavaScript(script) { [weak self] _, error in
      guard let self else { return }
      if let error {
        self.statusLabel.text = "因果图预览失败：\(error.localizedDescription)"
      } else if self.statusLabel.text?.contains("因果图预览失败") == true {
        self.statusLabel.text = currentMode == .causal
          ? "填写因果关系后，系统会自动生成关系图。完成后返回宿主 App 可直接粘贴图片。"
          : nil
      }
    }
  }

  private func buildMermaidCode() -> String {
    var validEdges: [VoiceCausalEdgeDraft] = []
    for row in causalRows {
      let edge = row.currentEdgeDraft()
      if !edge.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
         !edge.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        validEdges.append(edge)
      }
    }
    guard !validEdges.isEmpty else {
      return """
      flowchart TD
      start["请先添加关系"]
      """
    }

    var nodeIdMap: [String: String] = [:]
    var nodeSequence: [String] = []
    for edge in validEdges {
      for nodeTitle in [edge.from, edge.to] {
        let key = nodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { continue }
        if nodeIdMap[key] == nil {
          let nodeId = "n\(nodeIdMap.count + 1)"
          nodeIdMap[key] = nodeId
          nodeSequence.append(key)
        }
      }
    }

    var lines: [String] = ["flowchart TD"]
    for title in nodeSequence {
      guard let nodeId = nodeIdMap[title] else { continue }
      lines.append("\(nodeId)[\"\(escapeMermaidText(title))\"]")
    }
    for edge in validEdges {
      let from = edge.from.trimmingCharacters(in: .whitespacesAndNewlines)
      let to = edge.to.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let fromId = nodeIdMap[from], let toId = nodeIdMap[to] else { continue }
      let note = edge.note.trimmingCharacters(in: .whitespacesAndNewlines)
      if note.isEmpty {
        lines.append("\(fromId) --> \(toId)")
      } else {
        lines.append("\(fromId) -- \"\(escapeMermaidText(note))\" --> \(toId)")
      }
    }
    return lines.joined(separator: "\n")
  }

  private func escapeMermaidText(_ text: String) -> String {
    var output = text
    output = output.replacingOccurrences(of: "\\", with: "\\\\")
    output = output.replacingOccurrences(of: "\"", with: "\\\"")
    output = output.replacingOccurrences(of: "\n", with: " ")
    output = output.replacingOccurrences(of: "\r", with: " ")
    return output
  }

  private func jsonStringLiteral(_ string: String) -> String {
    guard let data = try? JSONEncoder().encode(string),
          let encoded = String(data: data, encoding: .utf8) else {
      return "\"\""
    }
    return encoded
  }

  private func setupMarkdownRendererIfNeeded() {
    let bundle = Bundle.module
    guard let htmlURL = resolveMarkdownRendererURL(in: bundle) else {
      isMarkdownRendererReady = false
      markdownPreviewWebView.loadHTMLString(Self.markdownRendererFallbackHTML, baseURL: nil)
      statusLabel.text = "Markdown 预览初始化失败，已切换基础模式。"
      return
    }
    isMarkdownRendererReady = false
    markdownPreviewWebView.loadFileURL(htmlURL, allowingReadAccessTo: bundle.bundleURL)
  }

  private func resolveMarkdownRendererURL(in bundle: Bundle) -> URL? {
    if let url = bundle.url(forResource: "markdown_renderer", withExtension: "html", subdirectory: "Markdown") {
      return url
    }
    if let url = bundle.url(forResource: "markdown_renderer", withExtension: "html") {
      return url
    }
    let rootCandidate = bundle.bundleURL.appendingPathComponent("markdown_renderer.html")
    if FileManager.default.fileExists(atPath: rootCandidate.path) { return rootCandidate }
    let subdirCandidate = bundle.bundleURL.appendingPathComponent("Markdown").appendingPathComponent("markdown_renderer.html")
    if FileManager.default.fileExists(atPath: subdirCandidate.path) { return subdirCandidate }
    return bundle.urls(forResourcesWithExtension: "html", subdirectory: nil)?
      .first(where: { $0.lastPathComponent == "markdown_renderer.html" })
  }

  private func restoreMarkdownDraftIfNeeded() {
    let storedFont = resolveStoredMarkdownFontOption(loadMarkdownDraftFontIdentifier())
    applyMarkdownFontOption(storedFont, persist: false, updateStatus: false)
    let content = loadMarkdownDraftContent()
    markdownTextView.text = content
    updateMarkdownPlaceholderState()
    scheduleMarkdownPreviewRender()
  }

  private func loadMarkdownDraftContent() -> String {
    markdownDraftDefaults.string(forKey: MarkdownDraftConstants.contentKey) ?? ""
  }

  private func saveMarkdownDraftContent(_ content: String) {
    markdownDraftDefaults.set(content, forKey: MarkdownDraftConstants.contentKey)
  }

  private func loadMarkdownDraftFontIdentifier() -> String? {
    markdownDraftDefaults.string(forKey: MarkdownDraftConstants.fontKey)
  }

  private func saveMarkdownDraftFontIdentifier(_ identifier: String) {
    markdownDraftDefaults.set(identifier, forKey: MarkdownDraftConstants.fontKey)
  }

  private func setupMarkdownQuickActionButtons() {
    for button in markdownQuickActionButtons {
      button.removeFromSuperview()
    }
    markdownQuickActionButtons.removeAll()
    markdownFontPickerButton.removeFromSuperview()
    markdownToolbarStackView.addArrangedSubview(markdownFontPickerButton)
    NSLayoutConstraint.activate([
      markdownFontPickerButton.heightAnchor.constraint(equalToConstant: 34)
    ])

    for (index, action) in MarkdownQuickAction.allCases.enumerated() {
      let button = UIButton(type: .system)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.tag = index
      button.setTitle(action.title, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
      button.setTitleColor(.label, for: .normal)
      button.backgroundColor = .tertiarySystemFill
      button.layer.cornerRadius = 10
      button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
      button.addTarget(self, action: #selector(handleMarkdownQuickActionTap(_:)), for: .touchUpInside)
      NSLayoutConstraint.activate([
        button.heightAnchor.constraint(equalToConstant: 34)
      ])
      markdownToolbarStackView.addArrangedSubview(button)
      markdownQuickActionButtons.append(button)
    }
  }

  private func updateMarkdownPlaceholderState() {
    markdownPlaceholderLabel.isHidden = !markdownTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func scheduleMarkdownPreviewRender() {
    pendingMarkdownRenderWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.renderMarkdownPreview()
    }
    pendingMarkdownRenderWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
  }

  private func renderMarkdownPreview() {
    guard isMarkdownRendererReady else { return }
    let markdown = markdownTextView.text ?? ""
    let payload = jsonStringLiteral(markdown)
    let isDark = traitCollection.userInterfaceStyle == .dark ? "true" : "false"
    let fontFamily = jsonStringLiteral(selectedMarkdownFontOption.cssFontFamily)
    let script = """
    window.renderMarkdown(\(payload), \(isDark), \(fontFamily));
    null;
    """
    markdownPreviewWebView.evaluateJavaScript(script) { [weak self] _, error in
      guard let self else { return }
      if let error {
        self.statusLabel.text = "Markdown 预览失败：\(error.localizedDescription)"
      } else if self.statusLabel.text?.contains("Markdown 预览失败") == true {
        self.statusLabel.text = nil
      }
    }
  }

  @objc private func handleMarkdownFontPickerTap(_ sender: UIButton) {
    if availableMarkdownFontOptions.isEmpty {
      availableMarkdownFontOptions = buildMarkdownFontOptions()
    }
    let alert = UIAlertController(title: "选择字体", message: nil, preferredStyle: .actionSheet)
    for option in availableMarkdownFontOptions {
      let title = option.identifier == selectedMarkdownFontOption.identifier ? "\(option.displayName)（当前）" : option.displayName
      alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
        self?.applyMarkdownFontOption(option, persist: true, updateStatus: true)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = sender
      popover.sourceRect = sender.bounds
    }
    present(alert, animated: true)
  }

  private func buildMarkdownFontOptions() -> [MarkdownFontOption] {
    var options: [MarkdownFontOption] = [.systemDefault]
    var usedIdentifiers: Set<String> = [MarkdownFontOption.systemIdentifier]
    var usedDisplayNames: Set<String> = [MarkdownFontOption.systemDefault.displayName]

    func appendOption(displayName: String, fontName: String, fallback: String) {
      guard let font = UIFont(name: fontName, size: 15) else { return }
      let identifier = font.fontName
      guard !usedIdentifiers.contains(identifier), !usedDisplayNames.contains(displayName) else { return }
      let css = "\(cssQuoted(font.familyName)), \(cssQuoted(font.fontName)), \(fallback)"
      options.append(MarkdownFontOption(identifier: identifier, displayName: displayName, editorFont: font, cssFontFamily: css))
      usedIdentifiers.insert(identifier)
      usedDisplayNames.insert(displayName)
    }

    for preset in Self.markdownFontPresets {
      for candidate in preset.candidates where UIFont(name: candidate, size: 15) != nil {
        appendOption(displayName: preset.displayName, fontName: candidate, fallback: preset.cssFallback)
        break
      }
    }

    let families = UIFont.familyNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    for family in families {
      guard !family.isEmpty, !family.hasPrefix(".") else { continue }
      let fontNames = UIFont.fontNames(forFamilyName: family)
      guard !fontNames.isEmpty else { continue }
      let preferredName = fontNames.first(where: { $0.localizedCaseInsensitiveContains("regular") }) ?? fontNames.first
      guard let preferredName else { continue }
      appendOption(displayName: family, fontName: preferredName, fallback: "-apple-system, sans-serif")
    }
    return options
  }

  private func resolveStoredMarkdownFontOption(_ storedIdentifier: String?) -> MarkdownFontOption {
    guard let storedIdentifier, !storedIdentifier.isEmpty else {
      return availableMarkdownFontOptions.first ?? .systemDefault
    }
    if let direct = availableMarkdownFontOptions.first(where: { $0.identifier == storedIdentifier }) {
      return direct
    }
    return availableMarkdownFontOptions.first ?? .systemDefault
  }

  private func applyMarkdownFontOption(_ option: MarkdownFontOption, persist: Bool, updateStatus: Bool) {
    selectedMarkdownFontOption = option
    markdownTextView.font = option.editorFont
    markdownPlaceholderLabel.font = option.editorFont
    markdownFontPickerButton.setTitle("字体·\(option.displayName)", for: .normal)
    if persist {
      saveMarkdownDraftFontIdentifier(option.identifier)
    }
    if updateStatus {
      statusLabel.text = "字体已切换为：\(option.displayName)。"
    }
    scheduleMarkdownPreviewRender()
  }

  private func cssQuoted(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "'", with: "\\'")
    return "'\(escaped)'"
  }

  @objc private func handleMarkdownQuickActionTap(_ sender: UIButton) {
    guard sender.tag >= 0, sender.tag < MarkdownQuickAction.allCases.count else { return }
    if !markdownTextView.isFirstResponder {
      markdownTextView.becomeFirstResponder()
    }
    let action = MarkdownQuickAction.allCases[sender.tag]
    applyMarkdownQuickAction(action)
  }

  private func applyMarkdownQuickAction(_ action: MarkdownQuickAction) {
    switch action {
    case .h1:
      applyMarkdownLinePrefixForSelectionOrInsert(prefix: "# ", placeholder: "标题")
    case .h2:
      applyMarkdownLinePrefixForSelectionOrInsert(prefix: "## ", placeholder: "标题")
    case .bold:
      wrapMarkdownSelectedText(prefix: "**", suffix: "**", placeholder: "文本")
    case .italic:
      wrapMarkdownSelectedText(prefix: "*", suffix: "*", placeholder: "文本")
    case .blockquote:
      applyMarkdownLinePrefixForSelectionOrInsert(prefix: "> ", placeholder: "引用")
    case .unorderedList:
      applyMarkdownLinePrefixForSelectionOrInsert(prefix: "- ", placeholder: "项目")
    case .orderedList:
      applyMarkdownOrderedListOrInsert()
    case .todo:
      applyMarkdownLinePrefixForSelectionOrInsert(prefix: "- [ ] ", placeholder: "任务")
    case .inlineCode:
      wrapMarkdownSelectedText(prefix: "`", suffix: "`", placeholder: "code")
    case .codeBlock:
      if markdownHasSelectedText {
        wrapMarkdownSelectedText(prefix: "```text\n", suffix: "\n```", placeholder: "内容")
      } else {
        insertMarkdownTemplateAndPlaceCursor("```text\n__CURSOR__\n```", cursorToken: "__CURSOR__")
      }
    case .link:
      wrapMarkdownSelectedText(prefix: "[", suffix: "](https://)", placeholder: "文本")
    case .image:
      wrapMarkdownSelectedText(prefix: "![", suffix: "](https://)", placeholder: "描述")
    case .table:
      insertMarkdownTemplateAndPlaceCursor("| 列1 | 列2 |\n| --- | --- |\n| __CURSOR__ | 内容 |", cursorToken: "__CURSOR__")
    case .mermaid:
      insertMarkdownTemplateAndPlaceCursor("```mermaid\nflowchart TD\n  A[起点] --> B[__CURSOR__]\n```", cursorToken: "__CURSOR__")
    }
    markdownTextView.scrollRangeToVisible(markdownTextView.selectedRange)
  }

  private var markdownHasSelectedText: Bool {
    markdownSelectedRange().length > 0
  }

  private func markdownSelectedRange() -> NSRange {
    let length = ((markdownTextView.text ?? "") as NSString).length
    var range = markdownTextView.selectedRange
    if range.location == NSNotFound {
      return NSRange(location: length, length: 0)
    }
    if range.location > length {
      range.location = length
      range.length = 0
      return range
    }
    if range.location + range.length > length {
      range.length = max(0, length - range.location)
    }
    return range
  }

  private func clampedMarkdownRange(_ range: NSRange, textLength: Int) -> NSRange {
    let safeLocation = max(0, min(range.location, textLength))
    let safeLength = max(0, min(range.length, textLength - safeLocation))
    return NSRange(location: safeLocation, length: safeLength)
  }

  private func replaceMarkdownText(in range: NSRange, with replacement: String, selectedRangeAfter: NSRange) {
    let text = markdownTextView.text ?? ""
    let nsText = text as NSString
    let safeRange = clampedMarkdownRange(range, textLength: nsText.length)
    let updated = nsText.replacingCharacters(in: safeRange, with: replacement)
    markdownTextView.text = updated
    markdownTextView.selectedRange = clampedMarkdownRange(selectedRangeAfter, textLength: (updated as NSString).length)
    handleProgrammaticMarkdownTextChange()
  }

  private func handleProgrammaticMarkdownTextChange() {
    let text = markdownTextView.text ?? ""
    saveMarkdownDraftContent(text)
    updateMarkdownPlaceholderState()
    scheduleMarkdownPreviewRender()
  }

  private func wrapMarkdownSelectedText(prefix: String, suffix: String, placeholder: String) {
    let text = markdownTextView.text ?? ""
    let nsText = text as NSString
    let selection = markdownSelectedRange()

    if selection.length > 0 {
      let selected = nsText.substring(with: selection)
      let replacement = "\(prefix)\(selected)\(suffix)"
      let cursor = selection.location + (replacement as NSString).length
      replaceMarkdownText(in: selection, with: replacement, selectedRangeAfter: NSRange(location: cursor, length: 0))
      return
    }

    let replacement = "\(prefix)\(placeholder)\(suffix)"
    let selectionAfter = NSRange(location: selection.location + (prefix as NSString).length, length: (placeholder as NSString).length)
    replaceMarkdownText(in: selection, with: replacement, selectedRangeAfter: selectionAfter)
  }

  private func markdownLineRangeCoveringSelection(_ selection: NSRange, in text: NSString) -> NSRange {
    if text.length == 0 { return NSRange(location: 0, length: 0) }
    let safeSelection = clampedMarkdownRange(selection, textLength: text.length)
    let startLine = text.lineRange(for: NSRange(location: safeSelection.location, length: 0))
    let endAnchor: Int = {
      let end = safeSelection.location + safeSelection.length
      if end <= 0 { return 0 }
      return min(max(0, end - 1), text.length - 1)
    }()
    let endLine = text.lineRange(for: NSRange(location: endAnchor, length: 0))
    return NSRange(location: startLine.location, length: endLine.location + endLine.length - startLine.location)
  }

  private func applyMarkdownLinePrefixForSelectionOrInsert(prefix: String, placeholder: String) {
    let selection = markdownSelectedRange()
    if selection.length == 0 {
      let template = "\(prefix)\(placeholder)"
      let selected = NSRange(location: selection.location + (prefix as NSString).length, length: (placeholder as NSString).length)
      replaceMarkdownText(in: selection, with: template, selectedRangeAfter: selected)
      return
    }
    let text = markdownTextView.text ?? ""
    let nsText = text as NSString
    let lineRange = markdownLineRangeCoveringSelection(selection, in: nsText)
    let block = nsText.substring(with: lineRange)
    let lines = block.components(separatedBy: "\n")
    let prefixed = lines.map { line -> String in
      let content = line.isEmpty ? placeholder : line
      return "\(prefix)\(content)"
    }.joined(separator: "\n")
    let cursor = lineRange.location + (prefixed as NSString).length
    replaceMarkdownText(in: lineRange, with: prefixed, selectedRangeAfter: NSRange(location: cursor, length: 0))
  }

  private func applyMarkdownOrderedListOrInsert() {
    let selection = markdownSelectedRange()
    if selection.length == 0 {
      let template = "1. 项目"
      replaceMarkdownText(in: selection, with: template, selectedRangeAfter: NSRange(location: selection.location + 3, length: 2))
      return
    }
    let text = markdownTextView.text ?? ""
    let nsText = text as NSString
    let lineRange = markdownLineRangeCoveringSelection(selection, in: nsText)
    let block = nsText.substring(with: lineRange)
    let lines = block.components(separatedBy: "\n")
    var index = 1
    let prefixed = lines.map { line -> String in
      let content = line.isEmpty ? "项目\(index)" : line
      defer { index += 1 }
      return "\(index). \(content)"
    }.joined(separator: "\n")
    let cursor = lineRange.location + (prefixed as NSString).length
    replaceMarkdownText(in: lineRange, with: prefixed, selectedRangeAfter: NSRange(location: cursor, length: 0))
  }

  private func insertMarkdownTemplateAndPlaceCursor(_ template: String, cursorToken: String) {
    let selection = markdownSelectedRange()
    let nsTemplate = template as NSString
    let tokenRange = nsTemplate.range(of: cursorToken)
    let replacement: String
    let cursorOffset: Int
    if tokenRange.location == NSNotFound {
      replacement = template
      cursorOffset = nsTemplate.length
    } else {
      replacement = nsTemplate.replacingCharacters(in: tokenRange, with: "")
      cursorOffset = tokenRange.location
    }
    replaceMarkdownText(in: selection, with: replacement, selectedRangeAfter: NSRange(location: selection.location + cursorOffset, length: 0))
  }

  private func waitForMarkdownRenderedContent(maxAttempts: Int, interval: TimeInterval, completion: @escaping (Bool) -> Void) {
    guard maxAttempts > 0 else {
      completion(false)
      return
    }
    markdownPreviewWebView.evaluateJavaScript("window.isMarkdownReady && window.isMarkdownReady();") { [weak self] value, _ in
      if let ready = value as? Bool, ready {
        completion(true)
        return
      }
      guard let self else {
        completion(false)
        return
      }
      if maxAttempts == 1 {
        completion(false)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
        self.waitForMarkdownRenderedContent(maxAttempts: maxAttempts - 1, interval: interval, completion: completion)
      }
    }
  }

  private func captureMarkdownPreviewImage(completion: @escaping (UIImage?) -> Void) {
    view.layoutIfNeeded()
    markdownPreviewContainerView.layoutIfNeeded()
    let snapshotBounds = markdownPreviewWebView.bounds.integral
    if snapshotBounds.width > 1, snapshotBounds.height > 1 {
      let config = WKSnapshotConfiguration()
      config.rect = snapshotBounds
      config.afterScreenUpdates = true
      markdownPreviewWebView.takeSnapshot(with: config) { [weak self] snapshot, _ in
        guard let self else {
          completion(nil)
          return
        }
        if let snapshot {
          completion(self.composeMarkdownImageWithBackground(snapshot))
          return
        }
        completion(self.captureMarkdownContainerFallbackImage())
      }
      return
    }
    completion(captureMarkdownContainerFallbackImage())
  }

  private func renderPlainMarkdownImage(_ markdown: String) -> UIImage? {
    let width = max(markdownPreviewContainerView.bounds.width, 360)
    let height = max(markdownPreviewContainerView.bounds.height, 240)
    let size = CGSize(width: width, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let backgroundColor = resolvedMarkdownExportBackgroundColor()
    let textColor = UIColor.label.resolvedColor(with: traitCollection)
    return renderer.image { _ in
      backgroundColor.setFill()
      UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
      let insetRect = CGRect(x: 14, y: 14, width: size.width - 28, height: size.height - 28)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: selectedMarkdownFontOption.editorFont,
        .foregroundColor: textColor
      ]
      NSString(string: markdown).draw(with: insetRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }
  }

  private func captureMarkdownContainerFallbackImage() -> UIImage? {
    let bounds = markdownPreviewContainerView.bounds.integral
    guard bounds.width > 1, bounds.height > 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
    let backgroundColor = resolvedMarkdownExportBackgroundColor()
    return renderer.image { context in
      context.cgContext.setFillColor(backgroundColor.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: bounds.size))
      markdownPreviewContainerView.drawHierarchy(in: CGRect(origin: .zero, size: bounds.size), afterScreenUpdates: true)
    }
  }

  private func composeMarkdownImageWithBackground(_ snapshot: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = snapshot.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: snapshot.size, format: format)
    let backgroundColor = resolvedMarkdownExportBackgroundColor()
    return renderer.image { context in
      context.cgContext.setFillColor(backgroundColor.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: snapshot.size))
      snapshot.draw(in: CGRect(origin: .zero, size: snapshot.size))
    }
  }

  private func resolvedMarkdownExportBackgroundColor() -> UIColor {
    let baseColor = markdownPreviewContainerView.backgroundColor ?? .secondarySystemBackground
    return baseColor.resolvedColor(with: traitCollection)
  }

  private func commitMarkdownExport(image: UIImage, markdown: String) {
    do {
      let item = try canvasStore.saveJPEG(image: image)
      var pasteboardItem: [String: Any] = [UTType.plainText.identifier: markdown]
      if let imageData = image.jpegData(compressionQuality: canvasStore.defaultJPEGQuality) {
        pasteboardItem[UTType.jpeg.identifier] = imageData
      }
      UIPasteboard.general.setItems([pasteboardItem], options: [:])
      if let requestId = activeRequestId {
        let relativePath = canvasStore.relativePath(for: item)
        canvasBridge.writeResult(requestId: requestId, imageRelativePath: relativePath)
        canvasBridge.setState(requestId: requestId, state: .ready)
        activeRequestId = nil
        hasCompletedCurrentKeyboardSession = true
        statusLabel.text = "已导出 Markdown 图片并复制原文。请返回宿主 App 后粘贴。"
      } else {
        statusLabel.text = "已导出 Markdown 图片并复制原文：\(item.fileName)"
      }
    } catch {
      if let requestId = activeRequestId {
        canvasBridge.setState(requestId: requestId, state: .failed, errorMessage: error.localizedDescription)
      }
      statusLabel.text = "导出失败：\(error.localizedDescription)"
    }
  }

  private func lockCanvasToVisibleBounds() {
    let size = canvasView.bounds.size
    guard size.width > 0, size.height > 0 else { return }
    if canvasView.contentSize != size {
      canvasView.contentSize = size
    }
    if canvasView.contentOffset != .zero {
      canvasView.contentOffset = .zero
    }
    if canvasView.contentInset != .zero {
      canvasView.contentInset = .zero
    }
  }

  private func applyCanvasMode(_ mode: CanvasMode, force: Bool = false) {
    if !force && currentMode == mode { return }
    currentMode = mode
    modeSegmentedControl.selectedSegmentIndex = mode.rawValue

    switch mode {
    case .draw:
      titleLabel.text = "画布"
      canvasView.isHidden = false
      markdownContainerView.isHidden = true
      canvasWakeOverlayView.isHidden = !isToolPickerVisible
      canvasWakeHintLabel.isHidden = !isToolPickerVisible
      causalContainerView.isHidden = true
      historyButtonStackView.isHidden = false
      if hasCompletedCurrentKeyboardSession || activeRequestId == nil {
        setToolPickerVisible(false)
      } else {
        setToolPickerVisible(true)
      }
      statusLabel.text = activeRequestId == nil
        ? "你可以手绘示意图。画完后返回宿主 App，即可粘贴图片。"
        : "已从键盘进入画布。复制后返回宿主 App，即可粘贴图片。"
    case .markdown:
      titleLabel.text = "Markdown"
      setToolPickerVisible(false)
      canvasView.isHidden = true
      markdownContainerView.isHidden = false
      canvasWakeOverlayView.isHidden = true
      canvasWakeHintLabel.isHidden = true
      causalContainerView.isHidden = true
      historyButtonStackView.isHidden = true
      statusLabel.text = activeRequestId == nil
        ? "输入 Markdown 后可复制图片和原文，也可保存为 .md 文件。"
        : "已从键盘进入 Markdown。复制后返回宿主 App 可粘贴图片。"
      scheduleMarkdownPreviewRender()
    case .causal:
      titleLabel.text = "因果图"
      setToolPickerVisible(false)
      canvasView.isHidden = true
      markdownContainerView.isHidden = true
      canvasWakeOverlayView.isHidden = true
      canvasWakeHintLabel.isHidden = true
      causalContainerView.isHidden = false
      historyButtonStackView.isHidden = true
      statusLabel.text = "填写因果关系后，系统会自动生成关系图。复制后返回宿主 App 可直接粘贴图片。"
      scheduleCausalRender()
    }
    updateHistoryButtonsState()
  }

  private func setToolPickerVisible(_ visible: Bool) {
    guard currentMode == .draw else {
      toolPicker?.setVisible(false, forFirstResponder: canvasView)
      canvasView.resignFirstResponder()
      canvasWakeOverlayView.isHidden = true
      canvasWakeHintLabel.isHidden = true
      isToolPickerVisible = false
      return
    }
    guard let picker = toolPicker else { return }
    if visible {
      canvasView.becomeFirstResponder()
      picker.setVisible(true, forFirstResponder: canvasView)
      canvasWakeOverlayView.isHidden = true
      canvasWakeHintLabel.isHidden = true
    } else {
      picker.setVisible(false, forFirstResponder: canvasView)
      canvasView.resignFirstResponder()
      canvasWakeOverlayView.isHidden = false
      canvasWakeHintLabel.isHidden = false
    }
    isToolPickerVisible = visible
  }

  @objc private func handleModeChanged(_ sender: UISegmentedControl) {
    let mode = CanvasMode(rawValue: sender.selectedSegmentIndex) ?? .draw
    applyCanvasMode(mode)
    reloadDocumentItems()
  }

  @objc private func handleAddCausalEdgeTap() {
    let edge = VoiceCausalEdgeDraft()
    causalEdges.append(edge)
    addRowView(for: edge)
    causalDraftStore.saveEdges(causalEdges)
    scheduleCausalRender()
    autosaveCurrentDocumentIfNeeded()
  }

  @objc private func handleScreenTap(_ recognizer: UITapGestureRecognizer) {
    guard currentMode == .draw else {
      view.endEditing(true)
      return
    }
    let point = recognizer.location(in: view)
    if canvasContainerView.frame.contains(point) {
      if !isToolPickerVisible {
        setToolPickerVisible(true)
      }
      return
    }

    let tappedButtonArea = clearButton.frame.contains(point)
      || newDocumentButton.frame.contains(point)
      || copyButton.frame.contains(point)
      || saveToFileButton.frame.contains(point)
      || undoButton.frame.contains(point)
      || redoButton.frame.contains(point)
    if !tappedButtonArea {
      setToolPickerVisible(false)
    }
  }

  @objc private func handleCanvasWakeTap() {
    guard currentMode == .draw else { return }
    guard !isToolPickerVisible else { return }
    setToolPickerVisible(true)
  }

  @objc private func handleClearTap() {
    if currentMode == .draw {
      canvasView.drawing = PKDrawing()
      canvasView.undoManager?.removeAllActions()
      if let requestId = activeRequestId, !hasCompletedCurrentKeyboardSession {
        canvasBridge.setState(requestId: requestId, state: .drawing)
      }
      statusLabel.text = activeRequestId == nil
        ? "画布已清空，你可以继续绘制。"
        : "画布已清空，请重新绘制后点击“完成”。"
      updateHistoryButtonsState()
      autosaveCurrentDocumentIfNeeded()
      return
    }

    if currentMode == .markdown {
      markdownTextView.text = ""
      saveMarkdownDraftContent("")
      updateMarkdownPlaceholderState()
      scheduleMarkdownPreviewRender()
      statusLabel.text = "Markdown 内容已清空。"
      autosaveCurrentDocumentIfNeeded()
      return
    }

    causalEdges = [VoiceCausalEdgeDraft()]
    causalDraftStore.saveEdges(causalEdges)
    rebuildCausalRows()
    scheduleCausalRender()
    statusLabel.text = "因果关系已清空，请重新填写后再完成。"
    autosaveCurrentDocumentIfNeeded()
  }

  @objc private func handleUndoTap() {
    canvasView.undoManager?.undo()
    updateHistoryButtonsState()
  }

  @objc private func handleRedoTap() {
    canvasView.undoManager?.redo()
    updateHistoryButtonsState()
  }

  private func updateHistoryButtonsState() {
    guard currentMode == .draw else {
      undoButton.isEnabled = false
      redoButton.isEnabled = false
      undoButton.alpha = 0.4
      redoButton.alpha = 0.4
      return
    }
    let canUndo = canvasView.undoManager?.canUndo ?? false
    let canRedo = canvasView.undoManager?.canRedo ?? false
    undoButton.isEnabled = canUndo
    redoButton.isEnabled = canRedo
    undoButton.alpha = canUndo ? 1.0 : 0.4
    redoButton.alpha = canRedo ? 1.0 : 0.4
  }

  @objc private func handleCopyTap() {
    if suppressDoneTapOnce {
      suppressDoneTapOnce = false
      return
    }
    if currentMode == .markdown {
      handleMarkdownCopyTap()
      return
    }
    if currentMode == .causal {
      handleCausalDoneTap()
      return
    }

    handleDrawDoneTap()
  }

  @objc private func handleSaveToFileTap() {
    saveCurrentDocument(promptIfNeeded: true)
  }

  @objc private func handleNewUntitledDocumentTap() {
    guard currentModeHasUnsavedChanges() else {
      resetCurrentModeToUntitledDocument()
      return
    }

    let alert = UIAlertController(
      title: "保留当前内容？",
      message: "新建未命名\(currentModeDisplayName())前，先保存当前内容。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "不保存", style: .destructive) { [weak self] _ in
      self?.resetCurrentModeToUntitledDocument()
    })
    alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
      self?.saveCurrentModeThenCreateUntitled()
    })
    present(alert, animated: true)
  }

  private func hasAnyCompleteCausalEdge() -> Bool {
    causalRows.contains { row in
      let edge = row.currentEdgeDraft()
      return !edge.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !edge.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  @objc private func handleDoneLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    guard currentMode == .causal else { return }
    suppressDoneTapOnce = true
    handleCausalMermaidExport()
  }

  private func handleDrawDoneTap() {
    let drawingBounds = canvasView.drawing.bounds
    guard !drawingBounds.isEmpty else {
      statusLabel.text = "你还没有画内容，请先手绘后再完成。"
      return
    }

    let visibleRect = CGRect(origin: canvasView.contentOffset, size: canvasView.bounds.size)
    guard !visibleRect.isEmpty else {
      statusLabel.text = "画布还没准备好，请稍后再试。"
      return
    }
    let visibleDrawingBounds = drawingBounds.intersection(visibleRect)
    guard !visibleDrawingBounds.isEmpty else {
      statusLabel.text = "请在画布区域内绘制后再完成。"
      return
    }

    // 按当前可见画布区域导出，保证“所见即所得”。
    let exportBounds = visibleRect
    guard !exportBounds.isEmpty else {
      statusLabel.text = "可导出的绘制区域为空，请重试。"
      return
    }
    let image = renderExportImage(from: exportBounds)
    commitExport(image)
  }

  private func currentCanvasSignature() -> Data {
    canvasView.drawing.dataRepresentation()
  }

  private func currentMarkdownSignature() -> String {
    markdownTextView.text ?? ""
  }

  private func currentCausalSignature() -> Data? {
    try? JSONEncoder().encode(causalEdges)
  }

  private func currentModeDisplayName() -> String {
    switch currentMode {
    case .draw:
      return "画布"
    case .markdown:
      return "Markdown"
    case .causal:
      return "因果图"
    }
  }

  private func currentModeHasContent() -> Bool {
    switch currentMode {
    case .draw:
      return !canvasView.drawing.strokes.isEmpty
    case .markdown:
      return !(markdownTextView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .causal:
      return causalEdges.contains {
        !$0.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || !$0.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
    }
  }

  private func currentModeHasUnsavedChanges() -> Bool {
    switch currentMode {
    case .draw:
      guard activeCanvasDocumentURL != nil else { return currentModeHasContent() }
      return currentCanvasSignature() != (lastSavedCanvasSignature ?? Data())
    case .markdown:
      guard activeMarkdownDocumentURL != nil else { return currentModeHasContent() }
      return currentMarkdownSignature() != (lastSavedMarkdownSignature ?? "")
    case .causal:
      guard activeCausalDocumentURL != nil else { return currentModeHasContent() }
      return currentCausalSignature() != lastSavedCausalSignature
    }
  }

  private func resetCurrentModeToUntitledDocument() {
    switch currentMode {
    case .draw:
      activeCanvasDocumentURL = nil
      lastSavedCanvasSignature = nil
      canvasView.drawing = PKDrawing()
      canvasView.undoManager?.removeAllActions()
      if let requestId = activeRequestId, !hasCompletedCurrentKeyboardSession {
        canvasBridge.setState(requestId: requestId, state: .drawing)
      }
    case .markdown:
      activeMarkdownDocumentURL = nil
      lastSavedMarkdownSignature = nil
      markdownTextView.text = ""
      saveMarkdownDraftContent("")
      updateMarkdownPlaceholderState()
      scheduleMarkdownPreviewRender()
    case .causal:
      activeCausalDocumentURL = nil
      lastSavedCausalSignature = nil
      causalEdges = [VoiceCausalEdgeDraft()]
      causalDraftStore.saveEdges(causalEdges)
      rebuildCausalRows()
      scheduleCausalRender()
    }
    reloadDocumentItems()
    statusLabel.text = "已新建未命名\(currentModeDisplayName())。"
  }

  private func saveCurrentModeThenCreateUntitled() {
    if let currentActiveDocumentURL {
      do {
        switch currentMode {
        case .draw:
          try workspaceStore.saveCanvas(drawing: canvasView.drawing, to: currentActiveDocumentURL)
          lastSavedCanvasSignature = currentCanvasSignature()
        case .markdown:
          try workspaceStore.saveMarkdown(content: markdownTextView.text ?? "", to: currentActiveDocumentURL)
          lastSavedMarkdownSignature = currentMarkdownSignature()
        case .causal:
          try workspaceStore.saveCausal(edges: causalEdges, to: currentActiveDocumentURL)
          lastSavedCausalSignature = currentCausalSignature()
        }
        resetCurrentModeToUntitledDocument()
      } catch {
        statusLabel.text = "保存失败：\(error.localizedDescription)"
      }
      return
    }

    promptForName(title: "保存文件", message: "输入文件名后保存当前内容，再新建未命名\(currentModeDisplayName())。", actionTitle: "保存") { [weak self] name in
      guard let self, !name.isEmpty else { return }
      if self.createNewDocument(named: name) {
        self.resetCurrentModeToUntitledDocument()
      }
    }
  }

  private func handleCausalDoneTap() {
    guard hasAnyCompleteCausalEdge() else {
      statusLabel.text = "请至少填写一条完整因果关系（原因与结果都不能为空）。"
      return
    }

    view.endEditing(true)
    copyButton.isEnabled = false
    renderCausalExportImage { [weak self] image in
      guard let self else { return }
      self.copyButton.isEnabled = true
      guard let image else {
        self.statusLabel.text = "因果图导出失败，请确认关系填写后重试。"
        return
      }
      self.commitExport(image)
    }
  }

  private func handleMarkdownCopyTap() {
    let markdown = markdownTextView.text ?? ""
    guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      statusLabel.text = "请先输入 Markdown 后再复制。"
      return
    }

    view.endEditing(true)
    copyButton.isEnabled = false
    waitForMarkdownRenderedContent(maxAttempts: 50, interval: 0.12) { [weak self] isReady in
      guard let self else { return }
      guard isReady else {
        self.copyButton.isEnabled = true
        guard let fallback = self.renderPlainMarkdownImage(markdown) else {
          self.statusLabel.text = "Markdown 导出失败，请重试。"
          return
        }
        self.commitMarkdownExport(image: fallback, markdown: markdown)
        return
      }

      self.captureMarkdownPreviewImage { image in
        self.copyButton.isEnabled = true
        guard let image = image ?? self.renderPlainMarkdownImage(markdown) else {
          self.statusLabel.text = "Markdown 导出失败，请重试。"
          return
        }
        self.commitMarkdownExport(image: image, markdown: markdown)
      }
    }
  }

  private func handleCausalMermaidExport() {
    guard hasAnyCompleteCausalEdge() else {
      statusLabel.text = "请至少填写一条完整因果关系后再导出 Mermaid。"
      return
    }

    view.endEditing(true)
    let mermaidSource = buildMermaidCode()
    UIPasteboard.general.setItems([[UTType.plainText.identifier: mermaidSource]], options: [:])

    do {
      let item = try canvasStore.saveTextFile(content: mermaidSource, fileExtension: "mmd", prefix: "causal_mermaid")
      statusLabel.text = "已导出 Mermaid 源文件并复制到剪贴板。"
      statusLabel.text = "已导出 Mermaid 源文件并复制到剪贴板：\(item.fileName)"
    } catch {
      statusLabel.text = "Mermaid 导出失败：\(error.localizedDescription)"
    }
  }

  private func commitExport(_ image: UIImage) {
    do {
      let item = try canvasStore.saveJPEG(image: image)
      UIPasteboard.general.image = image

      if let requestId = activeRequestId {
        let relativePath = canvasStore.relativePath(for: item)
        canvasBridge.writeResult(requestId: requestId, imageRelativePath: relativePath)
        canvasBridge.setState(requestId: requestId, state: .ready)
        activeRequestId = nil
        hasCompletedCurrentKeyboardSession = true
        statusLabel.text = "已完成并复制 JPG。请返回宿主 App 后直接粘贴图片。"
      } else {
        statusLabel.text = "已导出并复制 JPG：\(item.fileName)"
      }
    } catch {
      if let requestId = activeRequestId {
        canvasBridge.setState(requestId: requestId, state: .failed, errorMessage: error.localizedDescription)
      }
      statusLabel.text = "导出失败：\(error.localizedDescription)"
    }
  }

  private func renderCausalExportImage(completion: @escaping (UIImage?) -> Void) {
    pendingCausalRenderWorkItem?.cancel()
    if !isCausalRendererReady {
      setupCausalRendererIfNeeded()
    }
    waitForCausalSVGReady(maxAttempts: 24, interval: 0.12) { [weak self] isReady in
      guard let self else {
        completion(nil)
        return
      }
      if isReady {
        self.captureCausalPreviewSnapshot { image in
          completion(image ?? self.captureCausalPreviewImage())
        }
        return
      }
      completion(captureCausalPreviewImage())
    }
  }

  private func waitForCausalSVGReady(maxAttempts: Int, interval: TimeInterval, completion: @escaping (Bool) -> Void) {
    guard maxAttempts > 0 else {
      completion(false)
      return
    }
    let script = """
    (() => {
      const svg = document.querySelector('#diagram svg');
      if (!svg) { return false; }
      const rect = svg.getBoundingClientRect();
      return rect.width > 1 && rect.height > 1;
    })();
    """
    causalPreviewWebView.evaluateJavaScript(script) { [weak self] value, _ in
      if let ready = value as? Bool, ready {
        completion(true)
        return
      }
      guard let self else {
        completion(false)
        return
      }
      if maxAttempts == 1 {
        completion(false)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
        self.waitForCausalSVGReady(maxAttempts: maxAttempts - 1, interval: interval, completion: completion)
      }
    }
  }

  private func captureCausalPreviewImage() -> UIImage? {
    view.layoutIfNeeded()
    canvasContainerView.layoutIfNeeded()
    causalContainerView.layoutIfNeeded()
    causalPreviewContainerView.layoutIfNeeded()

    let targetView: UIView = {
      if causalPreviewContainerView.bounds.width > 1, causalPreviewContainerView.bounds.height > 1 {
        return causalPreviewContainerView
      }
      if causalContainerView.bounds.width > 1, causalContainerView.bounds.height > 1 {
        return causalContainerView
      }
      return canvasContainerView
    }()
    let bounds = targetView.bounds.integral
    guard bounds.width > 1, bounds.height > 1 else { return nil }

    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
    let backgroundColor = resolvedCanvasExportBackgroundColor()
    let image = renderer.image { context in
      context.cgContext.setFillColor(backgroundColor.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: bounds.size))
      targetView.drawHierarchy(in: CGRect(origin: .zero, size: bounds.size), afterScreenUpdates: true)
    }
    return image
  }

  private func captureCausalPreviewSnapshot(completion: @escaping (UIImage?) -> Void) {
    let bounds = causalPreviewWebView.bounds.integral
    guard bounds.width > 1, bounds.height > 1 else {
      completion(nil)
      return
    }
    let config = WKSnapshotConfiguration()
    config.rect = bounds
    config.afterScreenUpdates = true
    causalPreviewWebView.takeSnapshot(with: config) { [weak self] snapshot, _ in
      guard let self, let snapshot else {
        completion(nil)
        return
      }
      completion(composeCausalExportImage(from: snapshot))
    }
  }

  private func composeCausalExportImage(from snapshot: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = snapshot.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: snapshot.size, format: format)
    let backgroundColor = resolvedCanvasExportBackgroundColor()
    return renderer.image { context in
      context.cgContext.setFillColor(backgroundColor.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: snapshot.size))
      snapshot.draw(in: CGRect(origin: .zero, size: snapshot.size))
    }
  }

  private func renderExportImage(from bounds: CGRect) -> UIImage {
    let scale = UIScreen.main.scale
    let drawingImage = canvasView.drawing.image(from: bounds, scale: scale)
    let size = drawingImage.size
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let backgroundColor = resolvedCanvasExportBackgroundColor()
    return renderer.image { context in
      // JPEG 不支持透明通道；先按当前外观填充背景色，再叠加笔迹，避免导出后固定白底。
      context.cgContext.setFillColor(backgroundColor.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: size))
      drawingImage.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  private func resolvedCanvasExportBackgroundColor() -> UIColor {
    let baseColor = canvasContainerView.backgroundColor ?? .secondarySystemBackground
    return baseColor.resolvedColor(with: traitCollection)
  }
}

extension VoiceCanvasViewController: PKCanvasViewDelegate {
  func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
    updateHistoryButtonsState()
    autosaveCurrentDocumentIfNeeded()
  }
}

extension VoiceCanvasViewController: UITextViewDelegate {
  func textViewDidChange(_ textView: UITextView) {
    guard textView === markdownTextView else { return }
    let text = textView.text ?? ""
    saveMarkdownDraftContent(text)
    updateMarkdownPlaceholderState()
    scheduleMarkdownPreviewRender()
    autosaveCurrentDocumentIfNeeded()
  }
}

extension VoiceCanvasViewController: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if webView == causalPreviewWebView {
      isCausalRendererReady = true
      if currentMode == .causal, statusLabel.text?.contains("渲染资源缺失") == true {
        statusLabel.text = "填写因果关系后，系统会自动生成关系图。复制后返回宿主 App 可直接粘贴图片。"
      }
      scheduleCausalRender()
      return
    }
    if webView == markdownPreviewWebView {
      isMarkdownRendererReady = true
      scheduleMarkdownPreviewRender()
    }
  }
}

extension VoiceCanvasViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    canvasDocumentItems.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "VoiceWorkspaceDocumentCell", for: indexPath)
    let item = canvasDocumentItems[indexPath.row]
    var content = cell.defaultContentConfiguration()
    content.text = item.fileName
    let modifiedText: String
    if let modifiedAt = item.modifiedAt {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm"
      modifiedText = formatter.string(from: modifiedAt)
    } else {
      modifiedText = "刚刚"
    }
    if item.isDirectory {
      content.secondaryText = "文件夹"
      content.image = UIImage(systemName: "folder")
    } else {
      content.secondaryText = modifiedText
      content.image = UIImage(systemName: currentMode == .draw ? "scribble.variable" : "point.3.connected.trianglepath.dotted")
    }
    cell.contentConfiguration = content
    cell.accessoryType = (item.url == currentActiveDocumentURL) ? .checkmark : (item.isDirectory ? .disclosureIndicator : .none)
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    loadDocumentItem(canvasDocumentItems[indexPath.row])
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let item = canvasDocumentItems[indexPath.row]
    let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      guard let self else {
        completion(false)
        return
      }
      do {
        try self.workspaceStore.deleteItem(item)
        if self.activeCanvasDocumentURL == item.url {
          self.activeCanvasDocumentURL = nil
        }
        if self.activeCausalDocumentURL == item.url {
          self.activeCausalDocumentURL = nil
        }
        self.reloadDocumentItems()
        completion(true)
      } catch {
        self.statusLabel.text = "删除失败：\(error.localizedDescription)"
        completion(false)
      }
    }
    return UISwipeActionsConfiguration(actions: [deleteAction])
  }
}

private final class VoiceCausalEdgeRowView: UIView, UITextFieldDelegate {
  var onChanged: (() -> Void)?
  var onDelete: (() -> Void)?

  private lazy var fromField: UITextField = {
    let field = UITextField(frame: .zero)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.borderStyle = .roundedRect
    field.placeholder = "原因"
    field.returnKeyType = .next
    field.autocapitalizationType = .none
    field.autocorrectionType = .default
    field.clearButtonMode = .whileEditing
    field.delegate = self
    field.addTarget(self, action: #selector(handleTextChanged), for: .editingChanged)
    return field
  }()

  private lazy var arrowLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .medium)
    label.textColor = .secondaryLabel
    label.text = "→"
    return label
  }()

  private lazy var toField: UITextField = {
    let field = UITextField(frame: .zero)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.borderStyle = .roundedRect
    field.placeholder = "结果"
    field.returnKeyType = .next
    field.autocapitalizationType = .none
    field.autocorrectionType = .default
    field.clearButtonMode = .whileEditing
    field.delegate = self
    field.addTarget(self, action: #selector(handleTextChanged), for: .editingChanged)
    return field
  }()

  private lazy var deleteButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
    button.tintColor = .systemRed
    button.addTarget(self, action: #selector(handleDelete), for: .touchUpInside)
    return button
  }()

  private lazy var noteField: UITextField = {
    let field = UITextField(frame: .zero)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.borderStyle = .roundedRect
    field.placeholder = "关系说明（可选）"
    field.returnKeyType = .done
    field.autocapitalizationType = .none
    field.autocorrectionType = .default
    field.clearButtonMode = .whileEditing
    field.delegate = self
    field.addTarget(self, action: #selector(handleTextChanged), for: .editingChanged)
    return field
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(edge: VoiceCausalEdgeDraft) {
    fromField.text = edge.from
    toField.text = edge.to
    noteField.text = edge.note
  }

  func currentEdgeDraft(id: String = UUID().uuidString.lowercased()) -> VoiceCausalEdgeDraft {
    VoiceCausalEdgeDraft(
      id: id,
      from: fromField.text ?? "",
      to: toField.text ?? "",
      note: noteField.text ?? ""
    )
  }

  private func setupView() {
    translatesAutoresizingMaskIntoConstraints = false
    let topStack = UIStackView(arrangedSubviews: [fromField, arrowLabel, toField, deleteButton])
    topStack.translatesAutoresizingMaskIntoConstraints = false
    topStack.axis = .horizontal
    topStack.spacing = 8
    topStack.alignment = .center

    addSubview(topStack)
    addSubview(noteField)

    NSLayoutConstraint.activate([
      topStack.topAnchor.constraint(equalTo: topAnchor),
      topStack.leadingAnchor.constraint(equalTo: leadingAnchor),
      topStack.trailingAnchor.constraint(equalTo: trailingAnchor),

      arrowLabel.widthAnchor.constraint(equalToConstant: 16),
      deleteButton.widthAnchor.constraint(equalToConstant: 24),
      deleteButton.heightAnchor.constraint(equalToConstant: 24),

      noteField.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 8),
      noteField.leadingAnchor.constraint(equalTo: leadingAnchor),
      noteField.trailingAnchor.constraint(equalTo: trailingAnchor),
      noteField.bottomAnchor.constraint(equalTo: bottomAnchor),
      noteField.heightAnchor.constraint(equalToConstant: 34),
    ])
  }

  @objc private func handleDelete() {
    onDelete?()
  }

  @objc private func handleTextChanged() {
    onChanged?()
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if textField === fromField {
      toField.becomeFirstResponder()
    } else if textField === toField {
      noteField.becomeFirstResponder()
    } else {
      textField.resignFirstResponder()
    }
    return true
  }
}

@MainActor
final class VoiceCanvasStorageViewController: NibLessViewController {
  private let rootView = VoiceCanvasStorageRootView()
  private let canvasStore: VoiceCanvasStorageStore = .shared
  private let thumbnailProvider = VoiceCanvasExportThumbnailProvider()
  private var items: [VoiceCanvasFileItem] = []

  private lazy var dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()

  override func loadView() {
    title = "画布保存位置"
    view = rootView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    rootView.tableView.dataSource = self
    rootView.tableView.delegate = self
    rootView.tableView.register(VoiceCanvasExportFileCell.self, forCellReuseIdentifier: VoiceCanvasExportFileCell.reuseIdentifier)
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "清空",
      style: .plain,
      target: self,
      action: #selector(handleDeleteAllTap)
    )
    reloadItems()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    reloadItems()
  }

  private func reloadItems() {
    items = canvasStore.loadFiles()
    rootView.updateEmptyState(isEmpty: items.isEmpty)
    rootView.tableView.reloadData()
    navigationItem.rightBarButtonItem?.isEnabled = !items.isEmpty
  }

  @objc private func handleDeleteAllTap() {
    guard !items.isEmpty else { return }
    let alert = UIAlertController(
      title: "清空画布文件",
      message: "该操作会删除所有已导出的 JPG，是否继续？",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
      guard let self else { return }
      self.canvasStore.deleteAllFiles()
      self.reloadItems()
    })
    present(alert, animated: true)
  }
}

extension VoiceCanvasStorageViewController: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    2
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if section == 0 {
      return 1
    }
    return items.count
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    section == 0 ? "保存路径" : "已拷贝文件"
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    if section == 0 {
      return "默认拷贝为低质量 JPG（压缩率 0.28）。点击路径可复制。"
    }
    return nil
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.section == 0 {
      let cellIdentifier = "CanvasPathCell"
      let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
        ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellIdentifier)
      cell.selectionStyle = .default
      cell.textLabel?.text = "\(canvasStore.rootDisplayPath)"
      cell.textLabel?.font = .systemFont(ofSize: 13, weight: .regular)
      cell.textLabel?.numberOfLines = 2
      cell.detailTextLabel?.text = "点击复制路径"
      cell.detailTextLabel?.textColor = .secondaryLabel
      cell.accessoryType = .none
      return cell
    }

    let cell = tableView.dequeueReusableCell(withIdentifier: VoiceCanvasExportFileCell.reuseIdentifier, for: indexPath) as! VoiceCanvasExportFileCell
    let item = items[indexPath.row]
    let sizeText = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
    let detailText = "\(sizeText) · \(dateFormatter.string(from: item.modifiedAt))"
    cell.configure(item: item, detailText: detailText)
    thumbnailProvider.loadThumbnail(for: item, targetSize: CGSize(width: 72, height: 72)) { [weak tableView] image in
      guard let tableView,
            let visibleCell = tableView.cellForRow(at: indexPath) as? VoiceCanvasExportFileCell else { return }
      visibleCell.updateThumbnail(image)
    }
    cell.selectionStyle = .none
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard indexPath.section == 0 else { return }
    UIPasteboard.general.string = canvasStore.rootDisplayPath
    let alert = UIAlertController(title: "已复制", message: "画布保存路径已复制到剪贴板。", preferredStyle: .alert)
    present(alert, animated: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
      alert.dismiss(animated: true)
    }
  }

  func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    guard indexPath.section == 1 else { return nil }
    let item = items[indexPath.row]
    return UIContextMenuConfiguration(identifier: item.url as NSURL, previewProvider: nil) { [weak self, weak tableView] _ in
      guard let self else { return UIMenu() }
      let sourceView = tableView?.cellForRow(at: indexPath)
      let copyAction = UIAction(title: "再次复制", image: UIImage(systemName: "doc.on.doc")) { _ in
        self.copyExportedImage(item)
      }
      let shareAction = UIAction(title: "共享", image: UIImage(systemName: "square.and.arrow.up")) { _ in
        self.shareExportedImage(item, sourceView: sourceView)
      }
      let deleteAction = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
        self.canvasStore.deleteFile(item)
        self.reloadItems()
      }
      return UIMenu(children: [copyAction, shareAction, deleteAction])
    }
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    guard indexPath.section == 1 else { return nil }
    let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      guard let self else {
        completion(false)
        return
      }
      let item = self.items[indexPath.row]
      self.canvasStore.deleteFile(item)
      self.reloadItems()
      completion(true)
    }
    return UISwipeActionsConfiguration(actions: [deleteAction])
  }

  private func copyExportedImage(_ item: VoiceCanvasFileItem) {
    guard let image = UIImage(contentsOfFile: item.url.path) else { return }
    UIPasteboard.general.image = image
  }

  private func shareExportedImage(_ item: VoiceCanvasFileItem, sourceView: UIView?) {
    let controller = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
    if let popover = controller.popoverPresentationController, let sourceView {
      popover.sourceView = sourceView
      popover.sourceRect = sourceView.bounds
    }
    present(controller, animated: true)
  }
}

final class VoiceCanvasStorageRootView: NibLessView {
  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.rowHeight = 88
    view.estimatedRowHeight = 88
    return view
  }()

  private lazy var emptyTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.text = "暂无拷贝文件"
    return label
  }()

  private lazy var emptySubtitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.textAlignment = .center
    label.text = "你在画布页点击“拷贝”后，导出的 JPG 会保存在这里。"
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(tableView)
    addSubview(emptyTitleLabel)
    addSubview(emptySubtitleLabel)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyTitleLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
      emptyTitleLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor, constant: -18),
      emptyTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
      emptyTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

      emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 8),
      emptySubtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
      emptySubtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
    ])
  }

  override func setupAppearance() {
    backgroundColor = .systemBackground
    tableView.backgroundColor = .systemBackground
    emptyTitleLabel.textColor = .label
  }

  func updateEmptyState(isEmpty: Bool) {
    emptyTitleLabel.isHidden = !isEmpty
    emptySubtitleLabel.isHidden = !isEmpty
  }
}

private final class VoiceCanvasExportThumbnailProvider {
  private let cache = NSCache<NSString, UIImage>()

  func loadThumbnail(for item: VoiceCanvasFileItem, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
    let key = "\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)|\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
    if let cached = cache.object(forKey: key) {
      completion(cached)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [cache] in
      let image = UIImage(contentsOfFile: item.url.path)
      if let image {
        cache.setObject(image, forKey: key)
      }
      DispatchQueue.main.async {
        completion(image)
      }
    }
  }
}

private final class VoiceCanvasExportFileCell: UITableViewCell {
  static let reuseIdentifier = "VoiceCanvasExportFileCell"

  private let previewImageView = UIImageView(frame: .zero)
  private let titleLabel = UILabel(frame: .zero)
  private let detailLabel = UILabel(frame: .zero)

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear
    selectionStyle = .none

    previewImageView.translatesAutoresizingMaskIntoConstraints = false
    previewImageView.contentMode = .scaleAspectFill
    previewImageView.clipsToBounds = true
    previewImageView.layer.cornerRadius = 10
    previewImageView.backgroundColor = .tertiarySystemFill

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 1

    detailLabel.translatesAutoresizingMaskIntoConstraints = false
    detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
    detailLabel.textColor = .secondaryLabel
    detailLabel.numberOfLines = 2

    contentView.addSubview(previewImageView)
    contentView.addSubview(titleLabel)
    contentView.addSubview(detailLabel)

    NSLayoutConstraint.activate([
      previewImageView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
      previewImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
      previewImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
      previewImageView.widthAnchor.constraint(equalToConstant: 72),
      previewImageView.heightAnchor.constraint(equalToConstant: 72),

      titleLabel.leadingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 12),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
      titleLabel.topAnchor.constraint(equalTo: previewImageView.topAnchor, constant: 4),

      detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(item: VoiceCanvasFileItem, detailText: String) {
    titleLabel.text = item.fileName
    detailLabel.text = detailText
    previewImageView.image = UIImage(contentsOfFile: item.url.path)
  }

  func updateThumbnail(_ image: UIImage?) {
    previewImageView.image = image
  }
}
