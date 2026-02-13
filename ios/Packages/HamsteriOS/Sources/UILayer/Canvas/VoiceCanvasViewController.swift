//
//  VoiceCanvasViewController.swift
//
//
//  Created by Codex on 2026/2/13.
//

import HamsterKit
import HamsterUIKit
import PencilKit
import UIKit

struct VoiceCanvasFileItem: Hashable {
  let url: URL
  let fileName: String
  let fileSize: Int64
  let modifiedAt: Date
}

enum VoiceCanvasStoreError: LocalizedError {
  case imageEncodingFailed

  var errorDescription: String? {
    switch self {
    case .imageEncodingFailed:
      return "图片编码失败，请重试。"
    }
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
  private let canvasStore: VoiceCanvasStorageStore = .shared
  private let canvasBridge: AppCanvasBridge = .shared
  private var activeRequestId: String?
  private var hasCompletedCurrentKeyboardSession = false
  private var toolPicker: PKToolPicker?
  private var isToolPickerVisible = true

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

  private lazy var titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 30, weight: .bold)
    label.text = "画布"
    return label
  }()

  private lazy var statusLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "你可以手绘示意图，并导出低质量 JPG。"
    return label
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
    title = "画布"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupView()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    setupToolPickerIfNeeded()
    if let requestId = activeRequestId, !hasCompletedCurrentKeyboardSession {
      canvasBridge.setState(requestId: requestId, state: .drawing)
      if statusLabel.text?.isEmpty ?? true {
        statusLabel.text = "已从键盘进入画布。画完后点击“完成”，然后返回上一应用并粘贴。"
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    lockCanvasToVisibleBounds()
  }

  func startCanvasSession(requestId: String) {
    activeRequestId = requestId
    hasCompletedCurrentKeyboardSession = false
    canvasBridge.setState(requestId: requestId, state: .drawing)
    if isViewLoaded {
      canvasView.drawing = PKDrawing()
      statusLabel.text = "已从键盘进入画布。画完后点击“完成”，然后返回上一应用并粘贴。"
      tipLabel.text = "图片会导出为低质量 JPG，并自动复制到系统剪贴板。"
    }
  }

  private func setupView() {
    view.backgroundColor = .systemBackground
    view.addGestureRecognizer(screenTapGestureRecognizer)
    view.addSubview(titleLabel)
    view.addSubview(statusLabel)
    view.addSubview(canvasContainerView)
    canvasContainerView.addSubview(canvasView)
    canvasContainerView.addSubview(canvasWakeOverlayView)
    view.addSubview(clearButton)
    view.addSubview(historyButtonStackView)
    view.addSubview(doneButton)
    view.addSubview(tipLabel)
    canvasView.delegate = self

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

      canvasContainerView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 14),
      canvasContainerView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      canvasContainerView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      canvasContainerView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -18),

      canvasView.topAnchor.constraint(equalTo: canvasContainerView.topAnchor),
      canvasView.leadingAnchor.constraint(equalTo: canvasContainerView.leadingAnchor),
      canvasView.trailingAnchor.constraint(equalTo: canvasContainerView.trailingAnchor),
      canvasView.bottomAnchor.constraint(equalTo: canvasContainerView.bottomAnchor),

      canvasWakeOverlayView.topAnchor.constraint(equalTo: canvasContainerView.topAnchor),
      canvasWakeOverlayView.leadingAnchor.constraint(equalTo: canvasContainerView.leadingAnchor),
      canvasWakeOverlayView.trailingAnchor.constraint(equalTo: canvasContainerView.trailingAnchor),
      canvasWakeOverlayView.bottomAnchor.constraint(equalTo: canvasContainerView.bottomAnchor),

      clearButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      clearButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),

      historyButtonStackView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      historyButtonStackView.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),

      doneButton.bottomAnchor.constraint(equalTo: tipLabel.topAnchor, constant: -10),
      doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      tipLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      tipLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      tipLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
    ])
  }

  private func setupToolPickerIfNeeded() {
    guard toolPicker == nil else { return }
    let picker = PKToolPicker()
    picker.setVisible(true, forFirstResponder: canvasView)
    picker.addObserver(canvasView)
    canvasView.becomeFirstResponder()
    toolPicker = picker
    isToolPickerVisible = true
    updateHistoryButtonsState()
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

  private func setToolPickerVisible(_ visible: Bool) {
    guard let picker = toolPicker else { return }
    if visible {
      canvasView.becomeFirstResponder()
      picker.setVisible(true, forFirstResponder: canvasView)
      canvasWakeOverlayView.isHidden = true
    } else {
      picker.setVisible(false, forFirstResponder: canvasView)
      canvasView.resignFirstResponder()
      canvasWakeOverlayView.isHidden = false
    }
    isToolPickerVisible = visible
  }

  @objc private func handleScreenTap(_ recognizer: UITapGestureRecognizer) {
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
    guard !isToolPickerVisible else { return }
    setToolPickerVisible(true)
  }

  @objc private func handleClearTap() {
    canvasView.drawing = PKDrawing()
    canvasView.undoManager?.removeAllActions()
    updateHistoryButtonsState()
    if let requestId = activeRequestId, !hasCompletedCurrentKeyboardSession {
      canvasBridge.setState(requestId: requestId, state: .drawing)
    }
    statusLabel.text = activeRequestId == nil
      ? "画布已清空，你可以继续绘制。"
      : "画布已清空，请重新绘制后点击“完成”。"
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
    let canUndo = canvasView.undoManager?.canUndo ?? false
    let canRedo = canvasView.undoManager?.canRedo ?? false
    undoButton.isEnabled = canUndo
    redoButton.isEnabled = canRedo
    undoButton.alpha = canUndo ? 1.0 : 0.4
    redoButton.alpha = canRedo ? 1.0 : 0.4
  }

  @objc private func handleDoneTap() {
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

    // 仅导出可见画布区域内的笔迹，避免画布外误触也被保存。
    let paddedBounds = visibleDrawingBounds.insetBy(dx: -12, dy: -12).intersection(visibleRect)
    guard !paddedBounds.isEmpty else {
      statusLabel.text = "可导出的绘制区域为空，请重试。"
      return
    }
    let image = canvasView.drawing.image(from: paddedBounds, scale: UIScreen.main.scale)

    do {
      let item = try canvasStore.saveJPEG(image: image)
      UIPasteboard.general.image = image

      if let requestId = activeRequestId {
        let relativePath = canvasStore.relativePath(for: item)
        canvasBridge.writeResult(requestId: requestId, imageRelativePath: relativePath)
        canvasBridge.setState(requestId: requestId, state: .ready)
        activeRequestId = nil
        hasCompletedCurrentKeyboardSession = true
        statusLabel.text = "已完成并复制 JPG。请点击系统左上角返回上一应用后粘贴。"
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
}

extension VoiceCanvasViewController: PKCanvasViewDelegate {
  func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
    updateHistoryButtonsState()
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
