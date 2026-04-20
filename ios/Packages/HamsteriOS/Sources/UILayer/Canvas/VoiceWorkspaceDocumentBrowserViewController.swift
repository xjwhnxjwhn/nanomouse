//
//  VoiceWorkspaceDocumentBrowserViewController.swift
//
//
//  Created by Codex on 2026/4/20.
//

import HamsterUIKit
import UIKit

@MainActor
final class VoiceWorkspaceDocumentBrowserViewController: NibLessViewController {
  typealias CreateHandler = (_ fileName: String, _ pathComponents: [String]) throws -> URL
  typealias SaveHandler = (_ url: URL) throws -> Void
  typealias LoadHandler = (_ url: URL) throws -> Void
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
  private let panelView = VoiceWorkspaceDocumentPanelView(frame: .zero)

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

  private func setupView() {
    view.backgroundColor = .systemGroupedBackground
    panelView.translatesAutoresizingMaskIntoConstraints = false
    panelView.tableView.dataSource = self
    panelView.tableView.delegate = self
    panelView.backButton.addTarget(self, action: #selector(handleBackTap), for: .touchUpInside)
    panelView.newDocumentButton.addTarget(self, action: #selector(handleNewDocumentTap), for: .touchUpInside)
    panelView.newFolderButton.addTarget(self, action: #selector(handleNewFolderTap), for: .touchUpInside)
    panelView.saveButton.addTarget(self, action: #selector(handleSaveTap), for: .touchUpInside)
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
      isEmpty: items.isEmpty
    )
    panelView.tableView.reloadData()
    panelView.saveButton.accessibilityLabel = activeDocumentURLProvider() == nil ? "另存文件" : "保存当前文件"
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

  private func openItem(_ item: VoiceWorkspaceDocumentItem) {
    if item.isDirectory {
      pathComponents.append(item.fileName)
      reloadItems()
      return
    }

    do {
      try loadDocument(item.url)
      setActiveDocumentURL(item.url)
      reloadItems()
      dismiss(animated: true)
    } catch {
      alertConfirm(alertTitle: "打开失败", message: error.localizedDescription, confirmTitle: "知道了") {}
    }
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
      content.secondaryText = item.modifiedAt.map { formatter.string(from: $0) } ?? "刚刚"
      switch kind {
      case .markdown:
        content.image = UIImage(systemName: "doc.text")
      case .canvas:
        content.image = UIImage(systemName: "scribble.variable")
      case .causal:
        content.image = UIImage(systemName: "point.3.connected.trianglepath.dotted")
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

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let item = items[indexPath.row]
    let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      guard let self else {
        completion(false)
        return
      }
      do {
        try self.store.deleteItem(item)
        if self.activeDocumentURLProvider() == item.url {
          self.setActiveDocumentURL(nil)
          self.didDeleteDocument?(item.url)
        }
        self.reloadItems()
        completion(true)
      } catch {
        self.alertConfirm(alertTitle: "删除失败", message: error.localizedDescription, confirmTitle: "知道了") {}
        completion(false)
      }
    }
    return UISwipeActionsConfiguration(actions: [deleteAction])
  }
}
