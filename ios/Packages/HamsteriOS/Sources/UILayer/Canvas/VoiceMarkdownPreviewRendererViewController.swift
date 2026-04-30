import UIKit
import WebKit

@MainActor
final class VoiceMarkdownPreviewRendererViewController: UIViewController {
  nonisolated static let systemFontFamily = "-apple-system, BlinkMacSystemFont, 'PingFang SC', 'SF Pro Text', sans-serif"

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

  let webView: WKWebView

  private let allowsScrolling: Bool
  private var isRendererReady = false
  private var latestMarkdown = ""
  private var latestIsDark = false
  private var latestFontFamily = systemFontFamily
  private var latestRenderErrorHandler: ((Error) -> Void)?

  init(
    markdownText: String = "",
    isDark: Bool = false,
    fontFamily: String = VoiceMarkdownPreviewRendererViewController.systemFontFamily,
    allowsScrolling: Bool = true
  ) {
    self.allowsScrolling = allowsScrolling
    latestMarkdown = markdownText
    latestIsDark = isDark
    latestFontFamily = fontFamily

    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init(nibName: nil, bundle: nil)
    webView.navigationDelegate = self
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.isScrollEnabled = allowsScrolling
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = webView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupRenderer()
  }

  func render(
    markdownText: String,
    isDark: Bool,
    fontFamily: String = VoiceMarkdownPreviewRendererViewController.systemFontFamily,
    onError: ((Error) -> Void)? = nil
  ) {
    latestMarkdown = markdownText
    latestIsDark = isDark
    latestFontFamily = fontFamily
    latestRenderErrorHandler = onError
    loadViewIfNeeded()
    renderIfReady()
  }

  func waitForRenderedContent(maxAttempts: Int, interval: TimeInterval, completion: @escaping (Bool) -> Void) {
    guard maxAttempts > 0 else {
      completion(false)
      return
    }
    webView.evaluateJavaScript("window.isMarkdownReady && window.isMarkdownReady();") { [weak self] value, _ in
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

  private func setupRenderer() {
    let bundle = Bundle.module
    isRendererReady = false
    if let rendererHTML = makeInlineMarkdownRendererHTML(in: bundle) {
      webView.loadHTMLString(rendererHTML, baseURL: bundle.bundleURL)
      scheduleRendererReadinessFallback()
      return
    }
    guard let htmlURL = resolveMarkdownRendererURL(in: bundle) else {
      webView.loadHTMLString(Self.fallbackRendererHTML, baseURL: nil)
      scheduleRendererReadinessFallback()
      return
    }
    webView.loadFileURL(htmlURL, allowingReadAccessTo: bundle.bundleURL)
    scheduleRendererReadinessFallback()
  }

  private func scheduleRendererReadinessFallback() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self, !self.isRendererReady else { return }
      self.isRendererReady = true
      self.renderIfReady()
    }
  }

  private func renderIfReady() {
    guard isRendererReady else { return }
    let markdown = jsonStringLiteral(latestMarkdown)
    let isDark = latestIsDark ? "true" : "false"
    let fontFamily = jsonStringLiteral(latestFontFamily)
    let script = """
    window.renderMarkdown(\(markdown), \(isDark), \(fontFamily));
    null;
    """
    webView.evaluateJavaScript(script) { [weak self] _, error in
      guard let self, let error else { return }
      self.latestRenderErrorHandler?(error)
    }
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

  private func makeInlineMarkdownRendererHTML(in bundle: Bundle) -> String? {
    guard let htmlURL = resolveMarkdownRendererURL(in: bundle),
          var html = try? String(contentsOf: htmlURL, encoding: .utf8),
          let markdownItSource = loadMarkdownRendererResource(
            named: "markdown-it.min",
            withExtension: "js",
            in: bundle
          ),
          let mermaidSource = loadMarkdownRendererResource(
            named: "mermaid-markdown.min",
            withExtension: "js",
            in: bundle
          ) else {
      return nil
    }

    html = html.replacingOccurrences(
      of: #"<script src="markdown-it.min.js"></script>"#,
      with: "<script>\(htmlSafeInlineScript(markdownItSource))</script>"
    )
    html = html.replacingOccurrences(
      of: #"<script src="mermaid-markdown.min.js"></script>"#,
      with: "<script>\(htmlSafeInlineScript(mermaidSource))</script>"
    )
    return html
  }

  private func loadMarkdownRendererResource(
    named name: String,
    withExtension ext: String,
    in bundle: Bundle
  ) -> String? {
    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Markdown"),
       let content = try? String(contentsOf: url, encoding: .utf8) {
      return content
    }
    if let url = bundle.url(forResource: name, withExtension: ext),
       let content = try? String(contentsOf: url, encoding: .utf8) {
      return content
    }
    let candidate = bundle.bundleURL
      .appendingPathComponent("Markdown")
      .appendingPathComponent("\(name).\(ext)")
    if FileManager.default.fileExists(atPath: candidate.path),
       let content = try? String(contentsOf: candidate, encoding: .utf8) {
      return content
    }
    return nil
  }

  private func htmlSafeInlineScript(_ source: String) -> String {
    source.replacingOccurrences(
      of: "</script>",
      with: #"<\/script>"#,
      options: .caseInsensitive
    )
  }

  private func jsonStringLiteral(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let output = String(data: data, encoding: .utf8) else {
      return "\"\""
    }
    return output
  }
}

extension VoiceMarkdownPreviewRendererViewController: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    isRendererReady = true
    renderIfReady()
  }
}
