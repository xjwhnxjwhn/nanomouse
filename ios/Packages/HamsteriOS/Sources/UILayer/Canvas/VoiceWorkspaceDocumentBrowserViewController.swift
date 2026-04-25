//
//  VoiceWorkspaceDocumentBrowserViewController.swift
//
//
//  Created by Codex on 2026/4/20.
//

import EmbeddedMainModuleHost
import HamsterUIKit
import PencilKit
import UIKit
import UniformTypeIdentifiers

@MainActor
final class VoiceWorkspaceDocumentBrowserViewController: NibLessViewController {
  typealias CreateHandler = (_ fileName: String, _ pathComponents: [String]) throws -> URL
  typealias SaveHandler = (_ url: URL) throws -> Void
  typealias LoadHandler = (_ url: URL, _ traitCollection: UITraitCollection) throws -> Void
  typealias DeleteHandler = (_ url: URL) -> Void

  private let kind: VoiceWorkspaceDocumentKind
  private let store: VoiceWorkspaceDocumentStore
  private let createDocument: CreateHandler
  private let saveDocument: SaveHandler
  private let loadDocument: LoadHandler
  private let didDeleteDocument: DeleteHandler?
  private let pathComponentsProvider: () -> [String]
  private let setPathComponents: ([String]) -> Void
  private let activeDocumentURLProvider: () -> URL?
  private let setActiveDocumentURL: (URL?) -> Void

  private var items: [VoiceWorkspaceDocumentItem] = []
  private var displayMode: VoiceWorkspaceDocumentPanelView.DisplayMode = .list
  private let panelView = VoiceWorkspaceDocumentPanelView(frame: .zero)
  private let thumbnailProvider = VoiceWorkspaceDocumentThumbnailProvider()
  init(
    kind: VoiceWorkspaceDocumentKind,
    store: VoiceWorkspaceDocumentStore,
    pathComponentsProvider: @escaping () -> [String],
    setPathComponents: @escaping ([String]) -> Void,
    activeDocumentURLProvider: @escaping () -> URL?,
    setActiveDocumentURL: @escaping (URL?) -> Void,
    createDocument: @escaping CreateHandler,
    saveDocument: @escaping SaveHandler,
    loadDocument: @escaping LoadHandler,
    didDeleteDocument: DeleteHandler? = nil
  ) {
    self.kind = kind
    self.store = store
    self.pathComponentsProvider = pathComponentsProvider
    self.setPathComponents = setPathComponents
    self.activeDocumentURLProvider = activeDocumentURLProvider
    self.setActiveDocumentURL = setActiveDocumentURL
    self.createDocument = createDocument
    self.saveDocument = saveDocument
    self.loadDocument = loadDocument
    self.didDeleteDocument = didDeleteDocument
    super.init()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupView()
    reloadItems()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
    thumbnailProvider.invalidateAll()
    reloadItems()
  }

  private func setupView() {
    view.backgroundColor = .systemGroupedBackground
    panelView.translatesAutoresizingMaskIntoConstraints = false
    panelView.tableView.dataSource = self
    panelView.tableView.delegate = self
    panelView.collectionView.dataSource = self
    panelView.collectionView.delegate = self
    panelView.collectionView.register(
      VoiceWorkspaceDocumentGridCell.self,
      forCellWithReuseIdentifier: VoiceWorkspaceDocumentGridCell.reuseIdentifier
    )
    panelView.backButton.addTarget(self, action: #selector(handleBackTap), for: .touchUpInside)
    panelView.newDocumentButton.addTarget(self, action: #selector(handleNewDocumentTap), for: .touchUpInside)
    panelView.newFolderButton.addTarget(self, action: #selector(handleNewFolderTap), for: .touchUpInside)
    panelView.refreshButton.addTarget(self, action: #selector(handleRefresh), for: .touchUpInside)
    panelView.displayModeControl.addTarget(self, action: #selector(handleDisplayModeChanged), for: .valueChanged)
    view.addSubview(panelView)

    NSLayoutConstraint.activate([
      panelView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      panelView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      panelView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      panelView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])
  }

  private var pathComponents: [String] {
    get { pathComponentsProvider() }
    set { setPathComponents(newValue) }
  }

  private func reloadItems() {
    items = store.listItems(for: kind, pathComponents: pathComponents)
    panelView.titleLabel.text = kind.panelTitle
    panelView.updatePath(
      store.relativeDisplayPath(for: kind, pathComponents: pathComponents),
      canGoBack: !pathComponents.isEmpty,
      isEmpty: items.isEmpty,
      displayMode: displayMode
    )
    panelView.tableView.reloadData()
    panelView.collectionView.reloadData()
  }

  private func promptForName(title: String, message: String? = nil, actionTitle: String, completion: @escaping (String) -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "输入名称"
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in
      let value = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      completion(value)
    })
    present(alert, animated: true)
  }

  @objc private func handleBackTap() {
    guard !pathComponents.isEmpty else { return }
    pathComponents.removeLast()
    reloadItems()
  }

  @objc private func handleNewFolderTap() {
    promptForName(title: "新建文件夹", actionTitle: "创建") { [weak self] name in
      guard let self, !name.isEmpty else { return }
      do {
        try self.store.createFolder(named: name, for: self.kind, pathComponents: self.pathComponents)
        self.reloadItems()
      } catch {
        self.alertConfirm(alertTitle: "创建失败", message: error.localizedDescription, confirmTitle: "知道了") {}
      }
    }
  }

  @objc private func handleNewDocumentTap() {
    promptForName(title: "新建文件", message: "会在当前文件夹下创建可继续编辑的源文件。", actionTitle: "创建") { [weak self] name in
      guard let self, !name.isEmpty else { return }
      do {
        let url = try self.createDocument(name, self.pathComponents)
        self.setActiveDocumentURL(url)
        self.reloadItems()
      } catch {
        self.alertConfirm(alertTitle: "创建失败", message: error.localizedDescription, confirmTitle: "知道了") {}
      }
    }
  }

  @objc private func handleSaveTap() {
    if let url = activeDocumentURLProvider() {
      do {
        try saveDocument(url)
        reloadItems()
      } catch {
        alertConfirm(alertTitle: "保存失败", message: error.localizedDescription, confirmTitle: "知道了") {}
      }
      return
    }

    promptForName(title: "保存文件", message: "输入文件名后保存到当前文件夹。", actionTitle: "保存") { [weak self] name in
      guard let self, !name.isEmpty else { return }
      do {
        let url = try self.createDocument(name, self.pathComponents)
        self.setActiveDocumentURL(url)
        self.reloadItems()
      } catch {
        self.alertConfirm(alertTitle: "保存失败", message: error.localizedDescription, confirmTitle: "知道了") {}
      }
    }
  }

  @objc private func handleDisplayModeChanged() {
    displayMode = panelView.displayModeControl.selectedSegmentIndex == 1 ? .grid : .list
    reloadItems()
  }

  @objc private func handleRefresh() {
    reloadItems()
  }

  private func openItem(_ item: VoiceWorkspaceDocumentItem) {
    if item.isDirectory {
      pathComponents.append(item.fileName)
      reloadItems()
      return
    }

    let loadingTraitCollection = UITraitCollection(userInterfaceStyle: traitCollection.userInterfaceStyle)
    dismiss(animated: true) { [weak self] in
      guard let self else { return }
      do {
        try self.loadDocument(item.url, loadingTraitCollection)
        self.setActiveDocumentURL(item.url)
        self.reloadItems()
      } catch {
        self.alertConfirm(alertTitle: "打开失败", message: error.localizedDescription, confirmTitle: "知道了") {}
      }
    }
  }

  private func presentShareSheet(for item: VoiceWorkspaceDocumentItem, sourceView: UIView?) {
    let controller = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
    if let popover = controller.popoverPresentationController, let sourceView {
      popover.sourceView = sourceView
      popover.sourceRect = sourceView.bounds
    }
    present(controller, animated: true)
  }

  private func promptRename(for item: VoiceWorkspaceDocumentItem) {
    let currentName: String
    if item.isDirectory {
      currentName = item.fileName
    } else if item.fileName.lowercased().hasSuffix(".\(kind.fileExtension.lowercased())") {
      currentName = String(item.fileName.dropLast(kind.fileExtension.count + 1))
    } else {
      currentName = item.fileName
    }

    let alert = UIAlertController(title: "重命名", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "输入名称"
      textField.text = currentName
      textField.clearButtonMode = .whileEditing
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "完成", style: .default) { [weak self] _ in
      guard let self else { return }
      let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !newName.isEmpty else { return }
      do {
        let renamed = try self.store.renameItem(item, to: newName, kind: self.kind)
        if self.activeDocumentURLProvider() == item.url {
          self.setActiveDocumentURL(renamed.url)
        }
        self.reloadItems()
      } catch {
        self.alertConfirm(alertTitle: "重命名失败", message: error.localizedDescription, confirmTitle: "知道了") {}
      }
    })
    present(alert, animated: true)
  }

  private func deleteItem(_ item: VoiceWorkspaceDocumentItem, completion: ((Bool) -> Void)? = nil) {
    do {
      try store.deleteItem(item)
      if activeDocumentURLProvider() == item.url {
        setActiveDocumentURL(nil)
        didDeleteDocument?(item.url)
      }
      reloadItems()
      completion?(true)
    } catch {
      alertConfirm(alertTitle: "删除失败", message: error.localizedDescription, confirmTitle: "知道了") {}
      completion?(false)
    }
  }

  private func makeContextMenu(for item: VoiceWorkspaceDocumentItem, sourceView: UIView?) -> UIMenu {
    let renameAction = UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in
      self?.promptRename(for: item)
    }
    let storeAction = UIAction(title: "格纳", image: UIImage(systemName: "square.grid.3x3.topleft.filled")) { [weak self] _ in
      self?.presentSlotPickerForFile(item)
    }
    let shareAction = UIAction(title: "共享", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
      self?.presentShareSheet(for: item, sourceView: sourceView)
    }
    let deleteAction = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
      self?.deleteItem(item)
    }
    if item.isDirectory {
      return UIMenu(children: [renameAction, shareAction, deleteAction])
    }
    return UIMenu(children: [renameAction, storeAction, shareAction, deleteAction])
  }

  private func presentSlotPickerForFile(_ item: VoiceWorkspaceDocumentItem) {
    guard EmbeddedMainModuleHost.isAvailable else { return }
    let picker = VoiceBytePasteSlotPickerViewController(
      summaries: EmbeddedMainModuleHost.fetchSlotSummaries()
    ) { [weak self] slotIndex in
      self?.presentFileImportEditor(for: item, slotIndex: slotIndex)
    }
    if let sheet = picker.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
      sheet.preferredCornerRadius = 20
    }
    present(picker, animated: true)
  }

  private func presentFileImportEditor(for item: VoiceWorkspaceDocumentItem, slotIndex: Int) {
    guard !item.isDirectory else { return }
    guard let controller = EmbeddedMainModuleHost.makeFileSlotImportViewController(
      slotIndex: slotIndex,
      fileURLs: [item.url]
    ) else {
      alertConfirm(alertTitle: "格纳失败", message: "无法打开格子编辑器。", confirmTitle: "知道了") {}
      return
    }
    if let sheet = controller.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
      sheet.preferredCornerRadius = 20
    }
    present(controller, animated: true)
  }
}

extension VoiceWorkspaceDocumentBrowserViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    items.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "VoiceWorkspaceDocumentCell", for: indexPath)
    let item = items[indexPath.row]
    var content = cell.defaultContentConfiguration()
    content.text = item.fileName
    content.textProperties.numberOfLines = 1
    content.textProperties.font = .systemFont(ofSize: 15, weight: .regular)
    content.textProperties.lineBreakMode = .byTruncatingMiddle
    content.secondaryTextProperties.numberOfLines = 1
    content.secondaryTextProperties.font = .systemFont(ofSize: 12, weight: .regular)
    content.secondaryTextProperties.color = .secondaryLabel
    if item.isDirectory {
      content.secondaryText = "文件夹"
      content.image = UIImage(systemName: "folder")
    } else {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm"
      let modifiedText = item.modifiedAt.map { formatter.string(from: $0) } ?? "刚刚"
      let sizeText = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
      content.secondaryText = "\(sizeText) · \(modifiedText)"
      content.image = thumbnailProvider.placeholderImage(for: item, kind: kind)
      thumbnailProvider.loadThumbnail(
        for: item,
        kind: kind,
        targetSize: CGSize(width: 44, height: 44),
        traitCollection: traitCollection
      ) { [weak tableView] image in
        guard let tableView,
              let currentIndexPath = tableView.indexPath(for: cell),
              currentIndexPath == indexPath else { return }
        var updated = cell.defaultContentConfiguration()
        updated.text = item.fileName
        updated.textProperties.numberOfLines = 1
        updated.textProperties.font = .systemFont(ofSize: 15, weight: .regular)
        updated.textProperties.lineBreakMode = .byTruncatingMiddle
        updated.secondaryText = "\(sizeText) · \(modifiedText)"
        updated.secondaryTextProperties.numberOfLines = 1
        updated.secondaryTextProperties.font = .systemFont(ofSize: 12, weight: .regular)
        updated.secondaryTextProperties.color = .secondaryLabel
        updated.image = image
        cell.contentConfiguration = updated
      }
    }
    content.imageProperties.tintColor = .secondaryLabel
    content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    cell.contentConfiguration = content
    cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
    cell.accessoryType = (item.url == activeDocumentURLProvider()) ? .checkmark : (item.isDirectory ? .disclosureIndicator : .none)
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    openItem(items[indexPath.row])
  }

  func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    let item = items[indexPath.row]
    return UIContextMenuConfiguration(identifier: item.url as NSURL, previewProvider: nil) { [weak self, weak tableView] _ in
      guard let self else { return UIMenu() }
      let sourceView = tableView?.cellForRow(at: indexPath)
      return self.makeContextMenu(for: item, sourceView: sourceView)
    }
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let item = items[indexPath.row]
    let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      guard let self else {
        completion(false)
        return
      }
      self.deleteItem(item, completion: completion)
    }
    return UISwipeActionsConfiguration(actions: [deleteAction])
  }
}

extension VoiceWorkspaceDocumentBrowserViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    items.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let item = items[indexPath.item]
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: VoiceWorkspaceDocumentGridCell.reuseIdentifier,
      for: indexPath
    ) as! VoiceWorkspaceDocumentGridCell
    cell.configure(
      item: item,
      kind: kind,
      isActive: item.url == activeDocumentURLProvider(),
      placeholderImage: thumbnailProvider.placeholderImage(for: item, kind: kind)
    )
    thumbnailProvider.loadThumbnail(
      for: item,
      kind: kind,
      targetSize: CGSize(width: 140, height: 100),
      traitCollection: traitCollection
    ) { [weak collectionView] image in
      guard let collectionView,
            let visibleCell = collectionView.cellForItem(at: indexPath) as? VoiceWorkspaceDocumentGridCell else { return }
      visibleCell.updateThumbnail(image)
    }
    return cell
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    openItem(items[indexPath.item])
  }

  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    let width = collectionView.bounds.width - 24
    let columns: CGFloat = width > 720 ? 4 : (width > 520 ? 3 : 2)
    let totalSpacing = (columns - 1) * 12
    let itemWidth = floor((width - totalSpacing) / columns)
    return CGSize(width: itemWidth, height: 156)
  }

  func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    let item = items[indexPath.item]
    return UIContextMenuConfiguration(identifier: item.url as NSURL, previewProvider: nil) { [weak self, weak collectionView] _ in
      guard let self else { return UIMenu() }
      let sourceView = collectionView?.cellForItem(at: indexPath)
      return self.makeContextMenu(for: item, sourceView: sourceView)
    }
  }
}

private final class VoiceWorkspaceDocumentThumbnailProvider {
  private let cache = NSCache<NSString, UIImage>()

  func invalidateAll() {
    cache.removeAllObjects()
  }

  func placeholderImage(for item: VoiceWorkspaceDocumentItem, kind: VoiceWorkspaceDocumentKind) -> UIImage? {
    let resolvedKind = resolvedKind(for: item, fallback: kind)
    if item.isDirectory {
      return UIImage(systemName: "folder.fill")
    }
    switch resolvedKind {
    case .markdown:
      return UIImage(systemName: "doc.text.fill")
    case .canvas:
      return UIImage(systemName: "scribble.variable")
    case .causal:
      return UIImage(systemName: "point.3.connected.trianglepath.dotted")
    }
  }

  func loadThumbnail(
    for item: VoiceWorkspaceDocumentItem,
    kind: VoiceWorkspaceDocumentKind,
    targetSize: CGSize,
    traitCollection: UITraitCollection,
    completion: @escaping (UIImage?) -> Void
  ) {
    let appearanceToken = traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
    let sourceKey = "\(item.url.path)|\(item.modifiedAt?.timeIntervalSince1970 ?? 0)|\(appearanceToken)" as NSString
    let resolvedKind = resolvedKind(for: item, fallback: kind)
    if let cached = cache.object(forKey: sourceKey) {
      DispatchQueue.main.async {
        completion(self.scaledImage(from: cached, targetSize: targetSize))
      }
      return
    }
    if item.isDirectory {
      DispatchQueue.main.async {
        completion(self.placeholderImage(for: item, kind: kind))
      }
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [cache] in
      let image = self.generateThumbnail(for: item, kind: resolvedKind, targetSize: targetSize, traitCollection: traitCollection)
      if let image {
        cache.setObject(image, forKey: sourceKey)
      }
      DispatchQueue.main.async {
        completion(image.map { self.scaledImage(from: $0, targetSize: targetSize) } ?? self.placeholderImage(for: item, kind: resolvedKind))
      }
    }
  }

  private func generateThumbnail(
    for item: VoiceWorkspaceDocumentItem,
    kind: VoiceWorkspaceDocumentKind,
    targetSize: CGSize,
    traitCollection: UITraitCollection
  ) -> UIImage? {
    switch kind {
    case .canvas:
      return VoiceWorkspaceDocumentStore.canvasPreviewImage(
        forCanvasAt: item.url,
        traitCollection: traitCollection,
        targetSize: targetSize
      )
        ?? placeholderImage(for: item, kind: kind)
    case .markdown:
      guard let markdown = try? String(contentsOf: item.url, encoding: .utf8) else {
        return placeholderImage(for: item, kind: kind)
      }
      return renderTextThumbnail(
        lines: markdown.split(whereSeparator: \.isNewline).prefix(5).map(String.init),
        title: item.fileName,
        targetSize: targetSize,
        accentColor: .systemBlue
      )
    case .causal:
      guard let data = try? Data(contentsOf: item.url),
            let edges = try? JSONDecoder().decode([VoiceCausalEdgeDraft].self, from: data) else {
        return placeholderImage(for: item, kind: kind)
      }
      let lines = edges.prefix(4).map { edge in
        let from = edge.from.isEmpty ? "?" : edge.from
        let to = edge.to.isEmpty ? "?" : edge.to
        return "\(from) → \(to)"
      }
      return renderTextThumbnail(lines: lines, title: item.fileName, targetSize: targetSize, accentColor: .systemGreen)
    }
  }

  private func resolvedKind(for item: VoiceWorkspaceDocumentItem, fallback: VoiceWorkspaceDocumentKind) -> VoiceWorkspaceDocumentKind {
    guard !item.isDirectory else { return fallback }
    let lowercasedName = item.fileName.lowercased()
    if lowercasedName.hasSuffix(".md") {
      return .markdown
    }
    if lowercasedName.hasSuffix(".pkdrawing") {
      return .canvas
    }
    if lowercasedName.hasSuffix(".causal.json") {
      return .causal
    }
    return fallback
  }

  private func scaledImage(from image: UIImage, targetSize: CGSize) -> UIImage {
    guard targetSize.width > 0, targetSize.height > 0 else { return image }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = UIScreen.main.scale
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    return renderer.image { _ in
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: targetSize), cornerRadius: 14).addClip()
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private func renderTextThumbnail(lines: [String], title: String, targetSize: CGSize, accentColor: UIColor) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.image { context in
      let bounds = CGRect(origin: .zero, size: targetSize)
      UIColor.secondarySystemBackground.setFill()
      UIBezierPath(roundedRect: bounds, cornerRadius: 14).fill()

      let insetBounds = bounds.insetBy(dx: 10, dy: 10)
      let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: accentColor,
      ]
      let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: UIColor.label,
      ]
      NSString(string: title).draw(in: CGRect(x: insetBounds.minX, y: insetBounds.minY, width: insetBounds.width, height: 14), withAttributes: titleAttributes)
      var y = insetBounds.minY + 20
      for line in lines where y < insetBounds.maxY - 14 {
        NSString(string: line).draw(in: CGRect(x: insetBounds.minX, y: y, width: insetBounds.width, height: 14), withAttributes: bodyAttributes)
        y += 16
      }
      context.cgContext.setStrokeColor(UIColor.separator.cgColor)
      context.cgContext.stroke(bounds.insetBy(dx: 0.5, dy: 0.5), width: 1)
    }
  }
}

private final class VoiceWorkspaceDocumentGridCell: UICollectionViewCell {
  static let reuseIdentifier = "VoiceWorkspaceDocumentGridCell"

  private let thumbnailView = UIImageView(frame: .zero)
  private let titleLabel = UILabel(frame: .zero)
  private let detailLabel = UILabel(frame: .zero)
  private let activeBadge = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.backgroundColor = .secondarySystemGroupedBackground
    contentView.layer.cornerRadius = 14
    contentView.layer.masksToBounds = true
    contentView.layer.borderColor = UIColor.separator.cgColor
    contentView.layer.borderWidth = 1 / UIScreen.main.scale

    thumbnailView.translatesAutoresizingMaskIntoConstraints = false
    thumbnailView.contentMode = .scaleAspectFill
    thumbnailView.clipsToBounds = true
    thumbnailView.layer.cornerRadius = 10
    thumbnailView.tintColor = .secondaryLabel
    thumbnailView.backgroundColor = .tertiarySystemFill

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 2

    detailLabel.translatesAutoresizingMaskIntoConstraints = false
    detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
    detailLabel.textColor = .secondaryLabel
    detailLabel.numberOfLines = 2

    activeBadge.translatesAutoresizingMaskIntoConstraints = false
    activeBadge.tintColor = .systemBlue
    activeBadge.isHidden = true

    contentView.addSubview(thumbnailView)
    contentView.addSubview(titleLabel)
    contentView.addSubview(detailLabel)
    contentView.addSubview(activeBadge)

    NSLayoutConstraint.activate([
      thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
      thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
      thumbnailView.heightAnchor.constraint(equalToConstant: 92),

      titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 10),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

      detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

      activeBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
      activeBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
      activeBadge.widthAnchor.constraint(equalToConstant: 16),
      activeBadge.heightAnchor.constraint(equalToConstant: 16),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(item: VoiceWorkspaceDocumentItem, kind: VoiceWorkspaceDocumentKind, isActive: Bool, placeholderImage: UIImage?) {
    titleLabel.text = item.fileName
    if item.isDirectory {
      detailLabel.text = "文件夹"
    } else {
      let sizeText = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
      detailLabel.text = sizeText
    }
    thumbnailView.image = placeholderImage
    thumbnailView.contentMode = item.isDirectory ? .scaleAspectFit : .scaleAspectFill
    activeBadge.isHidden = !isActive
  }

  func updateThumbnail(_ image: UIImage?) {
    guard let image else { return }
    thumbnailView.image = image
    thumbnailView.contentMode = .scaleAspectFill
  }
}
