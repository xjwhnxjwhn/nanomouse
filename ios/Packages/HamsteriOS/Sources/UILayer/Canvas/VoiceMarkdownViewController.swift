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
        window.renderMarkdown = function renderMarkdown(source) {
          const el = document.getElementById("content");
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
    return button
  }()

  private lazy var tipLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "导出默认压缩率：0.28（低质量 JPG），同时复制 Markdown 原文。"
    return label
  }()

  override func loadView() {
    view = NibLessView()
    title = nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
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
      editorContainerView.heightAnchor.constraint(equalToConstant: 170),

      markdownTextView.topAnchor.constraint(equalTo: editorContainerView.topAnchor),
      markdownTextView.leadingAnchor.constraint(equalTo: editorContainerView.leadingAnchor),
      markdownTextView.trailingAnchor.constraint(equalTo: editorContainerView.trailingAnchor),
      markdownTextView.bottomAnchor.constraint(equalTo: editorContainerView.bottomAnchor),

      editorPlaceholderLabel.topAnchor.constraint(equalTo: editorContainerView.topAnchor, constant: 14),
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
    let script = "window.renderMarkdown(\(payload), \(isDark));"
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
        .font: UIFont.systemFont(ofSize: 15, weight: .regular),
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
