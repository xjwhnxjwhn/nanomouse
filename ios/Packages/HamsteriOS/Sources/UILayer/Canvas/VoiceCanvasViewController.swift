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

private struct VoiceCausalEdgeDraft: Codable, Hashable {
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
    case causal = 1
  }

  private let canvasStore: VoiceCanvasStorageStore = .shared
  private let canvasBridge: AppCanvasBridge = .shared
  private let causalDraftStore: VoiceCausalDraftStore = .shared
  private var activeRequestId: String?
  private var hasCompletedCurrentKeyboardSession = false
  private var toolPicker: PKToolPicker?
  private var isToolPickerVisible = true
  private var currentMode: CanvasMode = .draw
  private var causalEdges: [VoiceCausalEdgeDraft] = []
  private var causalRows: [VoiceCausalEdgeRowView] = []
  private var pendingCausalRenderWorkItem: DispatchWorkItem?
  private var isCausalRendererReady = false
  private var suppressDoneTapOnce = false

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
    label.text = "轻点此处以开始"
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

  private lazy var statusLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "你可以手绘示意图。画完后返回宿主 App，即可粘贴图片。"
    return label
  }()

  private lazy var modeSegmentedControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["手绘", "因果图"])
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
    longPress.cancelsTouchesInView = true
    button.addGestureRecognizer(longPress)
    return button
  }()

  private lazy var tipLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "导出默认压缩率：0.28（低质量，体积更小）。"
    return label
  }()

  override func loadView() {
    view = NibLessView()
    title = nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupView()
    setupCausalRendererIfNeeded()
    loadCausalDraft()
    applyCanvasMode(.draw, force: true)
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
      statusLabel.text = "已从键盘进入画布。画完后点击“完成”，返回宿主 App 即可粘贴图片。"
      tipLabel.text = "图片会导出为低质量 JPG，并自动复制到系统剪贴板。"
    }
  }

  private func setupView() {
    view.backgroundColor = .systemBackground
    view.addGestureRecognizer(screenTapGestureRecognizer)
    view.addSubview(titleLabel)
    view.addSubview(statusLabel)
    view.addSubview(modeSegmentedControl)
    view.addSubview(canvasContainerView)
    canvasContainerView.addSubview(canvasView)
    canvasContainerView.addSubview(canvasWakeOverlayView)
    canvasWakeOverlayView.addSubview(canvasWakeHintLabel)
    setupCausalLayout()
    view.addSubview(clearButton)
    view.addSubview(historyButtonStackView)
    view.addSubview(doneButton)
    view.addSubview(tipLabel)
    canvasView.delegate = self

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      modeSegmentedControl.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
      modeSegmentedControl.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
      modeSegmentedControl.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),

      canvasContainerView.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 12),
      canvasContainerView.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
      canvasContainerView.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
      canvasContainerView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -18),

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

      clearButton.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
      clearButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),

      historyButtonStackView.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
      historyButtonStackView.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),

      doneButton.bottomAnchor.constraint(equalTo: tipLabel.topAnchor, constant: -10),
      doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      tipLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
      tipLabel.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
      tipLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
    ])
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
    let script = "window.renderMermaid(\(encodedMermaid), \(isDark ? "true" : "false"));"
    causalPreviewWebView.evaluateJavaScript(script) { [weak self] _, error in
      if let error {
        self?.statusLabel.text = "因果图预览失败：\(error.localizedDescription)"
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
      canvasView.isHidden = false
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
        : "已从键盘进入画布。画完后点击“完成”，返回宿主 App 即可粘贴图片。"
      tipLabel.text = "导出默认压缩率：0.28（低质量，体积更小）。"
    case .causal:
      setToolPickerVisible(false)
      canvasView.isHidden = true
      canvasWakeOverlayView.isHidden = true
      canvasWakeHintLabel.isHidden = true
      causalContainerView.isHidden = false
      historyButtonStackView.isHidden = true
      statusLabel.text = "填写因果关系后，系统会自动生成关系图。完成后返回宿主 App 可直接粘贴图片。"
      tipLabel.text = "点击完成导出 JPG；长按完成可导出 Mermaid 源文件。"
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
  }

  @objc private func handleAddCausalEdgeTap() {
    let edge = VoiceCausalEdgeDraft()
    causalEdges.append(edge)
    addRowView(for: edge)
    causalDraftStore.saveEdges(causalEdges)
    scheduleCausalRender()
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
      || doneButton.frame.contains(point)
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
      return
    }

    causalEdges = [VoiceCausalEdgeDraft()]
    causalDraftStore.saveEdges(causalEdges)
    rebuildCausalRows()
    scheduleCausalRender()
    statusLabel.text = "因果关系已清空，请重新填写后再完成。"
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

  @objc private func handleDoneTap() {
    if suppressDoneTapOnce {
      suppressDoneTapOnce = false
      return
    }
    if currentMode == .causal {
      handleCausalDoneTap()
      return
    }

    handleDrawDoneTap()
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

  private func handleCausalDoneTap() {
    guard hasAnyCompleteCausalEdge() else {
      statusLabel.text = "请至少填写一条完整因果关系（原因与结果都不能为空）。"
      return
    }

    view.endEditing(true)
    doneButton.isEnabled = false
    renderCausalExportImage { [weak self] image in
      guard let self else { return }
      self.doneButton.isEnabled = true
      guard let image else {
        self.statusLabel.text = "因果图导出失败，请确认关系填写后重试。"
        return
      }
      self.commitExport(image)
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
      tipLabel.text = "已保存：\(item.fileName)（.mmd）"
    } catch {
      statusLabel.text = "Mermaid 导出失败：\(error.localizedDescription)"
      tipLabel.text = "已复制 Mermaid 文本到剪贴板。"
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
        tipLabel.text = "已导出：\(item.fileName)（低质量 JPG）。"
      } else {
        statusLabel.text = "已导出并复制 JPG。"
        tipLabel.text = "已保存到：\(canvasStore.rootDisplayPath)"
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
  }
}

extension VoiceCanvasViewController: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    isCausalRendererReady = true
    if currentMode == .causal, statusLabel.text?.contains("渲染资源缺失") == true {
      statusLabel.text = "填写因果关系后，系统会自动生成关系图。完成后返回宿主 App 可直接粘贴图片。"
    }
    scheduleCausalRender()
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
    rootView.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CanvasFileCell")
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
    section == 0 ? "保存路径" : "已导出文件"
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    if section == 0 {
      return "默认导出为低质量 JPG（压缩率 0.28）。点击路径可复制。"
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

    let cell = tableView.dequeueReusableCell(withIdentifier: "CanvasFileCell", for: indexPath)
    let item = items[indexPath.row]
    var content = cell.defaultContentConfiguration()
    content.text = item.fileName
    let sizeText = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
    content.secondaryText = "\(sizeText) · \(dateFormatter.string(from: item.modifiedAt))"
    content.textProperties.font = .systemFont(ofSize: 14, weight: .medium)
    content.secondaryTextProperties.font = .systemFont(ofSize: 12, weight: .regular)
    content.secondaryTextProperties.color = .secondaryLabel
    cell.contentConfiguration = content
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
}

final class VoiceCanvasStorageRootView: NibLessView {
  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .insetGrouped)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var emptyTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.text = "暂无画布文件"
    return label
  }()

  private lazy var emptySubtitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.textAlignment = .center
    label.text = "你在画布页点击“完成”后，导出的 JPG 会保存在这里。"
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
