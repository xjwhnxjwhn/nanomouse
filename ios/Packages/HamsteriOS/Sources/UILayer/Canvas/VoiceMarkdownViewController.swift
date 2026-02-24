//
//  VoiceMarkdownViewController.swift
//
//
//  Created by Codex on 2026/2/22.
//

import HamsterKit
import HamsterUIKit
import UniformTypeIdentifiers
import UIKit
import WebKit

private final class VoiceMarkdownDraftStore {
  static let shared = VoiceMarkdownDraftStore()

  private enum Constants {
    static let contentKey = "voice.markdown.draft.content"
    static let fontKey = "voice.markdown.draft.font"
  }

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .hamster) {
    self.userDefaults = userDefaults
  }

  func loadContent() -> String {
    userDefaults.string(forKey: Constants.contentKey) ?? ""
  }

  func saveContent(_ content: String) {
    userDefaults.set(content, forKey: Constants.contentKey)
  }

  func loadFontIdentifier() -> String? {
    userDefaults.string(forKey: Constants.fontKey)
  }

  func saveFontIdentifier(_ identifier: String) {
    userDefaults.set(identifier, forKey: Constants.fontKey)
  }
}

@MainActor
final class VoiceMarkdownViewController: NibLessViewController {
  private static let fallbackRendererHTML: String = """
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

  private let canvasStore: VoiceCanvasStorageStore = .shared
  private let canvasBridge: AppCanvasBridge = .shared
  private let draftStore: VoiceMarkdownDraftStore = .shared
  private var activeRequestId: String?
  private var hasCompletedCurrentKeyboardSession = false
  private var isRendererReady = false
  private var pendingRenderWorkItem: DispatchWorkItem?
  private var quickActionButtons: [UIButton] = []
  private var availableFontOptions: [MarkdownFontOption] = []
  private var selectedFontOption: MarkdownFontOption = .systemDefault

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

  private lazy var titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 34, weight: .bold)
    label.textColor = .label
    label.text = "Markdown"
    return label
  }()

  private lazy var statusLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "你可以输入 Markdown。完成后返回宿主 App 可粘贴图片，系统也会复制原文文本。"
    return label
  }()

  private lazy var editorContainerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .secondarySystemBackground
    view.layer.cornerRadius = 12
    view.layer.masksToBounds = true
    return view
  }()

  private lazy var toolbarScrollView: UIScrollView = {
    let view = UIScrollView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.showsHorizontalScrollIndicator = false
    view.alwaysBounceHorizontal = true
    return view
  }()

  private lazy var toolbarStackView: UIStackView = {
    let view = UIStackView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.axis = .horizontal
    view.alignment = .fill
    view.spacing = 8
    return view
  }()

  private lazy var toolbarDividerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .separator
    return view
  }()

  private lazy var fontPickerButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("字体", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.setTitleColor(.label, for: .normal)
    button.backgroundColor = .tertiarySystemFill
    button.layer.cornerRadius = 10
    button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
    button.addTarget(self, action: #selector(handleFontPickerTap(_:)), for: .touchUpInside)
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

  private lazy var editorPlaceholderLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .regular)
    label.textColor = .tertiaryLabel
    label.numberOfLines = 2
    label.text = "输入 Markdown，例如：\n```mermaid\\nflowchart TD\\nA --> B\\n```"
    return label
  }()

  private lazy var previewTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .secondaryLabel
    label.text = "预览"
    return label
  }()

  private lazy var previewContainerView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .tertiarySystemBackground
    view.layer.cornerRadius = 12
    view.layer.masksToBounds = true
    return view
  }()

  private lazy var previewWebView: WKWebView = {
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

  private lazy var doneButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("完成", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = .systemBlue
    button.layer.cornerRadius = 22
    button.contentEdgeInsets = UIEdgeInsets(top: 11, left: 24, bottom: 11, right: 24)
    button.addTarget(self, action: #selector(handleDoneTap), for: .touchUpInside)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDoneLongPress(_:)))
    longPress.minimumPressDuration = 0.45
    button.addGestureRecognizer(longPress)
    return button
  }()

  private lazy var tipLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "点击完成导出 JPG；长按完成可仅复制 Markdown 原文。"
    return label
  }()

  override func loadView() {
    view = NibLessView()
    title = nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    availableFontOptions = buildFontOptions()
    setupView()
    setupRendererIfNeeded()
    restoreDraftIfNeeded()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
    schedulePreviewRender()
  }

  func startMarkdownSession(requestId: String) {
    activeRequestId = requestId
    hasCompletedCurrentKeyboardSession = false
    canvasBridge.setState(requestId: requestId, state: .drawing)
    if isViewLoaded {
      statusLabel.text = "已从键盘进入 Markdown。完成后返回宿主 App 可粘贴图片。"
    }
  }

  private func setupView() {
    view.backgroundColor = .systemBackground
    view.addSubview(titleLabel)
    view.addSubview(statusLabel)
    view.addSubview(editorContainerView)
    editorContainerView.addSubview(toolbarScrollView)
    toolbarScrollView.addSubview(toolbarStackView)
    editorContainerView.addSubview(toolbarDividerView)
    editorContainerView.addSubview(markdownTextView)
    editorContainerView.addSubview(editorPlaceholderLabel)
    view.addSubview(previewTitleLabel)
    view.addSubview(previewContainerView)
    previewContainerView.addSubview(previewWebView)
    view.addSubview(clearButton)
    view.addSubview(doneButton)
    view.addSubview(tipLabel)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

      editorContainerView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
      editorContainerView.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
      editorContainerView.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
      editorContainerView.heightAnchor.constraint(equalToConstant: 230),

      toolbarScrollView.topAnchor.constraint(equalTo: editorContainerView.topAnchor, constant: 8),
      toolbarScrollView.leadingAnchor.constraint(equalTo: editorContainerView.leadingAnchor, constant: 8),
      toolbarScrollView.trailingAnchor.constraint(equalTo: editorContainerView.trailingAnchor, constant: -8),
      toolbarScrollView.heightAnchor.constraint(equalToConstant: 38),

      toolbarStackView.topAnchor.constraint(equalTo: toolbarScrollView.contentLayoutGuide.topAnchor),
      toolbarStackView.leadingAnchor.constraint(equalTo: toolbarScrollView.contentLayoutGuide.leadingAnchor),
      toolbarStackView.trailingAnchor.constraint(equalTo: toolbarScrollView.contentLayoutGuide.trailingAnchor),
      toolbarStackView.bottomAnchor.constraint(equalTo: toolbarScrollView.contentLayoutGuide.bottomAnchor),
      toolbarStackView.heightAnchor.constraint(equalTo: toolbarScrollView.frameLayoutGuide.heightAnchor),

      toolbarDividerView.topAnchor.constraint(equalTo: toolbarScrollView.bottomAnchor, constant: 6),
      toolbarDividerView.leadingAnchor.constraint(equalTo: editorContainerView.leadingAnchor),
      toolbarDividerView.trailingAnchor.constraint(equalTo: editorContainerView.trailingAnchor),
      toolbarDividerView.heightAnchor.constraint(equalToConstant: 0.5),

      markdownTextView.topAnchor.constraint(equalTo: toolbarDividerView.bottomAnchor, constant: 4),
      markdownTextView.leadingAnchor.constraint(equalTo: editorContainerView.leadingAnchor),
      markdownTextView.trailingAnchor.constraint(equalTo: editorContainerView.trailingAnchor),
      markdownTextView.bottomAnchor.constraint(equalTo: editorContainerView.bottomAnchor),

      editorPlaceholderLabel.topAnchor.constraint(equalTo: markdownTextView.topAnchor, constant: 12),
      editorPlaceholderLabel.leadingAnchor.constraint(equalTo: editorContainerView.leadingAnchor, constant: 16),
      editorPlaceholderLabel.trailingAnchor.constraint(equalTo: editorContainerView.trailingAnchor, constant: -16),

      previewTitleLabel.topAnchor.constraint(equalTo: editorContainerView.bottomAnchor, constant: 10),
      previewTitleLabel.leadingAnchor.constraint(equalTo: editorContainerView.leadingAnchor),
      previewTitleLabel.trailingAnchor.constraint(equalTo: editorContainerView.trailingAnchor),

      previewContainerView.topAnchor.constraint(equalTo: previewTitleLabel.bottomAnchor, constant: 6),
      previewContainerView.leadingAnchor.constraint(equalTo: previewTitleLabel.leadingAnchor),
      previewContainerView.trailingAnchor.constraint(equalTo: previewTitleLabel.trailingAnchor),
      previewContainerView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -18),

      previewWebView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
      previewWebView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
      previewWebView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
      previewWebView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor),

      clearButton.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
      clearButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),

      doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      doneButton.bottomAnchor.constraint(equalTo: tipLabel.topAnchor, constant: -10),

      tipLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
      tipLabel.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
      tipLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
    ])

    setupQuickActionButtons()
  }

  private func setupQuickActionButtons() {
    for button in quickActionButtons {
      button.removeFromSuperview()
    }
    quickActionButtons.removeAll()
    fontPickerButton.removeFromSuperview()
    toolbarStackView.addArrangedSubview(fontPickerButton)
    NSLayoutConstraint.activate([
      fontPickerButton.heightAnchor.constraint(equalToConstant: 34)
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
      button.addTarget(self, action: #selector(handleQuickActionTap(_:)), for: .touchUpInside)
      NSLayoutConstraint.activate([
        button.heightAnchor.constraint(equalToConstant: 34)
      ])
      toolbarStackView.addArrangedSubview(button)
      quickActionButtons.append(button)
    }
  }

  private func cssQuoted(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "'", with: "\\'")
    return "'\(escaped)'"
  }

  private func buildFontOptions() -> [MarkdownFontOption] {
    var options: [MarkdownFontOption] = [.systemDefault]
    var usedIdentifiers: Set<String> = [MarkdownFontOption.systemIdentifier]
    var usedDisplayNames: Set<String> = [MarkdownFontOption.systemDefault.displayName]

    func appendOption(displayName: String, fontName: String, fallback: String) {
      guard let font = UIFont(name: fontName, size: 15) else { return }
      let identifier = font.fontName
      guard !usedIdentifiers.contains(identifier) else { return }
      guard !usedDisplayNames.contains(displayName) else { return }
      let css = "\(cssQuoted(font.familyName)), \(cssQuoted(font.fontName)), \(fallback)"
      options.append(
        MarkdownFontOption(
          identifier: identifier,
          displayName: displayName,
          editorFont: font,
          cssFontFamily: css
        )
      )
      usedIdentifiers.insert(identifier)
      usedDisplayNames.insert(displayName)
    }

    for preset in Self.markdownFontPresets {
      for candidate in preset.candidates {
        if UIFont(name: candidate, size: 15) != nil {
          appendOption(displayName: preset.displayName, fontName: candidate, fallback: preset.cssFallback)
          break
        }
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

  private func resolveStoredFontOption(_ storedIdentifier: String?) -> MarkdownFontOption {
    guard let storedIdentifier, !storedIdentifier.isEmpty else {
      return availableFontOptions.first ?? .systemDefault
    }
    if let direct = availableFontOptions.first(where: { $0.identifier == storedIdentifier }) {
      return direct
    }
    if let legacyDisplayName = legacyFontDisplayName(for: storedIdentifier),
       let mapped = availableFontOptions.first(where: { $0.displayName == legacyDisplayName }) {
      return mapped
    }
    return availableFontOptions.first ?? .systemDefault
  }

  private func legacyFontDisplayName(for identifier: String) -> String? {
    switch identifier {
    case "pingFangSC": return "PingFang SC"
    case "pingFangTC": return "PingFang TC"
    case "songtiSC": return "Songti SC"
    case "kaitiSC": return "Kaiti SC"
    case "heitiSC": return "Heiti SC"
    case "hiraginoSansGB": return "Hiragino Sans GB"
    case "stFangSong": return "STFangsong"
    case "stSong": return "STSong"
    case "helveticaNeue": return "Helvetica Neue"
    case "avenirNext": return "Avenir Next"
    case "georgia": return "Georgia"
    case "timesNewRoman": return "Times New Roman"
    case "menlo": return "Menlo"
    case "courierNew": return "Courier New"
    case "sfMono": return "SF Mono"
    case "system": return "系统默认"
    default: return nil
    }
  }

  private func setupRendererIfNeeded() {
    let bundle = Bundle.module
    guard let htmlURL = resolveMarkdownRendererURL(in: bundle) else {
      isRendererReady = false
      previewWebView.loadHTMLString(Self.fallbackRendererHTML, baseURL: nil)
      statusLabel.text = "Markdown 预览初始化失败，已切换基础模式。"
      return
    }
    isRendererReady = false
    previewWebView.loadFileURL(htmlURL, allowingReadAccessTo: bundle.bundleURL)
  }

  private func resolveMarkdownRendererURL(in bundle: Bundle) -> URL? {
    if let url = bundle.url(forResource: "markdown_renderer", withExtension: "html", subdirectory: "Markdown") {
      return url
    }
    if let url = bundle.url(forResource: "markdown_renderer", withExtension: "html") {
      return url
    }
    let rootCandidate = bundle.bundleURL.appendingPathComponent("markdown_renderer.html")
    if FileManager.default.fileExists(atPath: rootCandidate.path) {
      return rootCandidate
    }
    let subdirCandidate = bundle.bundleURL
      .appendingPathComponent("Markdown")
      .appendingPathComponent("markdown_renderer.html")
    if FileManager.default.fileExists(atPath: subdirCandidate.path) {
      return subdirCandidate
    }
    return bundle.urls(forResourcesWithExtension: "html", subdirectory: nil)?
      .first(where: { $0.lastPathComponent == "markdown_renderer.html" })
  }

  private func restoreDraftIfNeeded() {
    let storedFont = resolveStoredFontOption(draftStore.loadFontIdentifier())
    applyFontOption(storedFont, persist: false, updateStatus: false)
    let content = draftStore.loadContent()
    markdownTextView.text = content
    updatePlaceholderState()
    schedulePreviewRender()
  }

  private func updatePlaceholderState() {
    editorPlaceholderLabel.isHidden = !markdownTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func schedulePreviewRender() {
    pendingRenderWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.renderMarkdownPreview()
    }
    pendingRenderWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
  }

  private func renderMarkdownPreview() {
    guard isRendererReady else { return }
    let markdown = markdownTextView.text ?? ""
    let payload = jsonStringLiteral(markdown)
    let isDark = traitCollection.userInterfaceStyle == .dark ? "true" : "false"
    let fontFamily = jsonStringLiteral(selectedFontOption.cssFontFamily)
    let script = "window.renderMarkdown(\(payload), \(isDark), \(fontFamily));"
    previewWebView.evaluateJavaScript(script) { [weak self] _, error in
      guard let self else { return }
      if let error {
        statusLabel.text = "Markdown 预览失败：\(error.localizedDescription)"
      }
    }
  }

  private func jsonStringLiteral(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let output = String(data: data, encoding: .utf8) else {
      return "\"\""
    }
    return output
  }

  @objc private func handleFontPickerTap(_ sender: UIButton) {
    if availableFontOptions.isEmpty {
      availableFontOptions = buildFontOptions()
    }
    let alert = UIAlertController(title: "选择字体", message: nil, preferredStyle: .actionSheet)
    for option in availableFontOptions {
      let title: String
      if option.identifier == selectedFontOption.identifier {
        title = "\(option.displayName)（当前）"
      } else {
        title = option.displayName
      }
      alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
        self?.applyFontOption(option, persist: true, updateStatus: true)
      })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = sender
      popover.sourceRect = sender.bounds
    }
    present(alert, animated: true)
  }

  private func applyFontOption(_ option: MarkdownFontOption, persist: Bool, updateStatus: Bool) {
    selectedFontOption = option
    markdownTextView.font = option.editorFont
    editorPlaceholderLabel.font = option.editorFont
    fontPickerButton.setTitle("字体·\(option.displayName)", for: .normal)
    if persist {
      draftStore.saveFontIdentifier(option.identifier)
    }
    if updateStatus {
      statusLabel.text = "字体已切换为：\(option.displayName)。"
    }
    schedulePreviewRender()
  }

  @objc private func handleQuickActionTap(_ sender: UIButton) {
    guard sender.tag >= 0, sender.tag < MarkdownQuickAction.allCases.count else { return }
    if !markdownTextView.isFirstResponder {
      markdownTextView.becomeFirstResponder()
    }
    let action = MarkdownQuickAction.allCases[sender.tag]
    applyQuickAction(action)
  }

  private func applyQuickAction(_ action: MarkdownQuickAction) {
    switch action {
    case .h1:
      applyLinePrefixForSelectionOrInsert(prefix: "# ", placeholder: "标题")
    case .h2:
      applyLinePrefixForSelectionOrInsert(prefix: "## ", placeholder: "标题")
    case .bold:
      wrapSelectedText(prefix: "**", suffix: "**", placeholder: "文本")
    case .italic:
      wrapSelectedText(prefix: "*", suffix: "*", placeholder: "文本")
    case .blockquote:
      applyLinePrefixForSelectionOrInsert(prefix: "> ", placeholder: "引用")
    case .unorderedList:
      applyLinePrefixForSelectionOrInsert(prefix: "- ", placeholder: "项目")
    case .orderedList:
      applyOrderedListOrInsert()
    case .todo:
      applyLinePrefixForSelectionOrInsert(prefix: "- [ ] ", placeholder: "任务")
    case .inlineCode:
      wrapSelectedText(prefix: "`", suffix: "`", placeholder: "code")
    case .codeBlock:
      if hasSelectedText {
        wrapSelectedText(prefix: "```text\n", suffix: "\n```", placeholder: "内容")
      } else {
        insertTemplateAndPlaceCursor("```text\n__CURSOR__\n```", cursorToken: "__CURSOR__")
      }
    case .link:
      wrapSelectedText(prefix: "[", suffix: "](https://)", placeholder: "文本")
    case .image:
      wrapSelectedText(prefix: "![", suffix: "](https://)", placeholder: "描述")
    case .table:
      insertTemplateAndPlaceCursor(
        "| 列1 | 列2 |\n| --- | --- |\n| __CURSOR__ | 内容 |",
        cursorToken: "__CURSOR__"
      )
    case .mermaid:
      insertTemplateAndPlaceCursor(
        "```mermaid\nflowchart TD\n  A[起点] --> B[__CURSOR__]\n```",
        cursorToken: "__CURSOR__"
      )
    }

    markdownTextView.scrollRangeToVisible(markdownTextView.selectedRange)
  }

  private var hasSelectedText: Bool {
    selectedRangeInText().length > 0
  }

  private func selectedRangeInText() -> NSRange {
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

  private func clampedRange(_ range: NSRange, textLength: Int) -> NSRange {
    let safeLocation = max(0, min(range.location, textLength))
    let safeLength = max(0, min(range.length, textLength - safeLocation))
    return NSRange(location: safeLocation, length: safeLength)
  }

  private func replaceText(
    in range: NSRange,
    with replacement: String,
    selectedRangeAfter: NSRange
  ) {
    let text = markdownTextView.text ?? ""
    let nsText = text as NSString
    let safeRange = clampedRange(range, textLength: nsText.length)
    let updated = nsText.replacingCharacters(in: safeRange, with: replacement)
    markdownTextView.text = updated
    let updatedRange = clampedRange(selectedRangeAfter, textLength: (updated as NSString).length)
    markdownTextView.selectedRange = updatedRange
    handleProgrammaticTextChange()
  }

  private func handleProgrammaticTextChange() {
    let text = markdownTextView.text ?? ""
    draftStore.saveContent(text)
    updatePlaceholderState()
    schedulePreviewRender()
  }

  private func wrapSelectedText(prefix: String, suffix: String, placeholder: String) {
    let text = markdownTextView.text ?? ""
    let nsText = text as NSString
    let selection = selectedRangeInText()

    if selection.length > 0 {
      let selected = nsText.substring(with: selection)
      let replacement = "\(prefix)\(selected)\(suffix)"
      let cursor = selection.location + (replacement as NSString).length
      replaceText(
        in: selection,
        with: replacement,
        selectedRangeAfter: NSRange(location: cursor, length: 0)
      )
      return
    }

    let replacement = "\(prefix)\(placeholder)\(suffix)"
    let selectionAfter = NSRange(
      location: selection.location + (prefix as NSString).length,
      length: (placeholder as NSString).length
    )
    replaceText(in: selection, with: replacement, selectedRangeAfter: selectionAfter)
  }

  private func lineRangeCoveringSelection(_ selection: NSRange, in text: NSString) -> NSRange {
    if text.length == 0 {
      return NSRange(location: 0, length: 0)
    }

    let safeSelection = clampedRange(selection, textLength: text.length)
    let startLine = text.lineRange(for: NSRange(location: safeSelection.location, length: 0))
    let endAnchor: Int = {
      let end = safeSelection.location + safeSelection.length
      if end <= 0 { return 0 }
      return min(max(0, end - 1), text.length - 1)
    }()
    let endLine = text.lineRange(for: NSRange(location: endAnchor, length: 0))
    return NSRange(
      location: startLine.location,
      length: endLine.location + endLine.length - startLine.location
    )
  }

  private func applyLinePrefixForSelectionOrInsert(prefix: String, placeholder: String) {
    let selection = selectedRangeInText()
    if selection.length == 0 {
      let template = "\(prefix)\(placeholder)"
      let selected = NSRange(
        location: selection.location + (prefix as NSString).length,
        length: (placeholder as NSString).length
      )
      replaceText(in: selection, with: template, selectedRangeAfter: selected)
      return
    }

    let text = markdownTextView.text ?? ""
    let nsText = text as NSString
    let lineRange = lineRangeCoveringSelection(selection, in: nsText)
    let block = nsText.substring(with: lineRange)
    let lines = block.components(separatedBy: "\n")
    let prefixed = lines.map { line -> String in
      let content = line.isEmpty ? placeholder : line
      return "\(prefix)\(content)"
    }.joined(separator: "\n")
    let cursor = lineRange.location + (prefixed as NSString).length
    replaceText(
      in: lineRange,
      with: prefixed,
      selectedRangeAfter: NSRange(location: cursor, length: 0)
    )
  }

  private func applyOrderedListOrInsert() {
    let selection = selectedRangeInText()
    if selection.length == 0 {
      let template = "1. 项目"
      let selected = NSRange(location: selection.location + 3, length: 2)
      replaceText(in: selection, with: template, selectedRangeAfter: selected)
      return
    }

    let text = markdownTextView.text ?? ""
    let nsText = text as NSString
    let lineRange = lineRangeCoveringSelection(selection, in: nsText)
    let block = nsText.substring(with: lineRange)
    let lines = block.components(separatedBy: "\n")
    var index = 1
    let prefixed = lines.map { line -> String in
      let content = line.isEmpty ? "项目\(index)" : line
      defer { index += 1 }
      return "\(index). \(content)"
    }.joined(separator: "\n")
    let cursor = lineRange.location + (prefixed as NSString).length
    replaceText(
      in: lineRange,
      with: prefixed,
      selectedRangeAfter: NSRange(location: cursor, length: 0)
    )
  }

  private func insertTemplateAndPlaceCursor(_ template: String, cursorToken: String) {
    let selection = selectedRangeInText()
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

    replaceText(
      in: selection,
      with: replacement,
      selectedRangeAfter: NSRange(location: selection.location + cursorOffset, length: 0)
    )
  }

  @objc private func handleClearTap() {
    markdownTextView.text = ""
    draftStore.saveContent("")
    updatePlaceholderState()
    schedulePreviewRender()
    statusLabel.text = "Markdown 内容已清空。"
  }

  @objc private func handleDoneTap() {
    let markdown = markdownTextView.text ?? ""
    guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      statusLabel.text = "请先输入 Markdown 后再完成。"
      return
    }

    view.endEditing(true)
    doneButton.isEnabled = false
    waitForRenderedContent(maxAttempts: 50, interval: 0.12) { [weak self] isReady in
      guard let self else { return }
      guard isReady else {
        doneButton.isEnabled = true
        guard let fallback = renderPlainTextImage(markdown) else {
          statusLabel.text = "Markdown 导出失败，请重试。"
          return
        }
        commitExport(image: fallback, markdown: markdown)
        return
      }

      capturePreviewImage { image in
        self.doneButton.isEnabled = true
        guard let image = image ?? self.renderPlainTextImage(markdown) else {
          self.statusLabel.text = "Markdown 导出失败，请重试。"
          return
        }
        self.commitExport(image: image, markdown: markdown)
      }
    }
  }

  @objc private func handleDoneLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    let markdown = markdownTextView.text ?? ""
    guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      statusLabel.text = "暂无 Markdown 可复制。"
      return
    }

    UIPasteboard.general.setItems(
      [[UTType.plainText.identifier: markdown]],
      options: [:]
    )
    statusLabel.text = "已复制 Markdown 原文到剪贴板。"
    tipLabel.text = "你可以直接粘贴 Markdown 文本。"
  }

  private func waitForRenderedContent(maxAttempts: Int, interval: TimeInterval, completion: @escaping (Bool) -> Void) {
    guard maxAttempts > 0 else {
      completion(false)
      return
    }
    let script = "window.isMarkdownReady && window.isMarkdownReady();"
    previewWebView.evaluateJavaScript(script) { [weak self] value, _ in
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
        self.waitForRenderedContent(maxAttempts: maxAttempts - 1, interval: interval, completion: completion)
      }
    }
  }

  private func capturePreviewImage(completion: @escaping (UIImage?) -> Void) {
    view.layoutIfNeeded()
    previewContainerView.layoutIfNeeded()

    let snapshotBounds = previewWebView.bounds.integral
    if snapshotBounds.width > 1, snapshotBounds.height > 1 {
      let config = WKSnapshotConfiguration()
      config.rect = snapshotBounds
      config.afterScreenUpdates = true
      previewWebView.takeSnapshot(with: config) { [weak self] snapshot, _ in
        guard let self else {
          completion(nil)
          return
        }
        if let snapshot {
          completion(composeImageWithBackground(snapshot))
          return
        }
        completion(captureContainerFallbackImage())
      }
      return
    }
    completion(captureContainerFallbackImage())
  }

  private func renderPlainTextImage(_ markdown: String) -> UIImage? {
    let width = max(previewContainerView.bounds.width, 360)
    let height = max(previewContainerView.bounds.height, 240)
    let size = CGSize(width: width, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let backgroundColor = resolvedExportBackgroundColor()
    let textColor = UIColor.label.resolvedColor(with: traitCollection)

    return renderer.image { _ in
      backgroundColor.setFill()
      UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

      let insetRect = CGRect(x: 14, y: 14, width: size.width - 28, height: size.height - 28)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: selectedFontOption.editorFont,
        .foregroundColor: textColor
      ]
      NSString(string: markdown).draw(
        with: insetRect,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes,
        context: nil
      )
    }
  }

  private func captureContainerFallbackImage() -> UIImage? {
    let bounds = previewContainerView.bounds.integral
    guard bounds.width > 1, bounds.height > 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
    let backgroundColor = resolvedExportBackgroundColor()
    return renderer.image { context in
      context.cgContext.setFillColor(backgroundColor.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: bounds.size))
      previewContainerView.drawHierarchy(in: CGRect(origin: .zero, size: bounds.size), afterScreenUpdates: true)
    }
  }

  private func composeImageWithBackground(_ snapshot: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = snapshot.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: snapshot.size, format: format)
    let backgroundColor = resolvedExportBackgroundColor()
    return renderer.image { context in
      context.cgContext.setFillColor(backgroundColor.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: snapshot.size))
      snapshot.draw(in: CGRect(origin: .zero, size: snapshot.size))
    }
  }

  private func resolvedExportBackgroundColor() -> UIColor {
    let baseColor = previewContainerView.backgroundColor ?? .secondarySystemBackground
    return baseColor.resolvedColor(with: traitCollection)
  }

  private func commitExport(image: UIImage, markdown: String) {
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
        statusLabel.text = "已导出 Markdown 图片并复制原文。"
      }
      tipLabel.text = "已导出：\(item.fileName)（低质量 JPG）。"
    } catch {
      if let requestId = activeRequestId {
        canvasBridge.setState(requestId: requestId, state: .failed, errorMessage: error.localizedDescription)
      }
      statusLabel.text = "导出失败：\(error.localizedDescription)"
    }
  }
}

extension VoiceMarkdownViewController: UITextViewDelegate {
  func textViewDidChange(_ textView: UITextView) {
    let text = textView.text ?? ""
    draftStore.saveContent(text)
    updatePlaceholderState()
    schedulePreviewRender()
  }
}

extension VoiceMarkdownViewController: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    isRendererReady = true
    schedulePreviewRender()
  }
}
