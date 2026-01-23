//
//  InputSchemaSelectRootView.swift
//
//
//  Created by Claude on 2024.
//

import HamsterUIKit
import UIKit

/// 输入方案分组选择页面
class InputSchemaSelectRootView: NibLessView {
  // MARK: - Properties

  private static let cellIdentifier = "InputSchemaSelectCell"

  private weak var delegate: InputSchemaSelectDelegate?

  let tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: InputSchemaSelectRootView.cellIdentifier)
    return tableView
  }()

  private let items: [(title: String, subtitle: String, group: InputSchemaViewModel.SchemaGroup)] = [
    ("中英", "雾凇拼音、双拼等中文输入方案", .chineseEnglish),
    ("日语", "AzooKey、rime-japanese 等日语输入方案", .japanese),
  ]

  // MARK: - Init

  init(frame: CGRect = .zero, delegate: InputSchemaSelectDelegate?) {
    self.delegate = delegate

    super.init(frame: frame)

    constructViewHierarchy()
    activateViewConstraints()
  }

  override func constructViewHierarchy() {
    addSubview(tableView)
    tableView.delegate = self
    tableView.dataSource = self
  }

  override func activateViewConstraints() {
    tableView.fillSuperview()
  }
}

// MARK: - UITableViewDataSource

extension InputSchemaSelectRootView: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    1
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    items.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
    var config = UIListContentConfiguration.subtitleCell()
    let item = items[indexPath.row]
    config.text = item.title
    config.secondaryText = item.subtitle
    config.secondaryTextProperties.color = .secondaryLabel
    cell.contentConfiguration = config
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    "选择输入方案分组"
  }
}

// MARK: - UITableViewDelegate

extension InputSchemaSelectRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let group = items[indexPath.row].group
    delegate?.didSelectSchemaGroup(group)
  }
}

// MARK: - Delegate Protocol

protocol InputSchemaSelectDelegate: AnyObject {
  func didSelectSchemaGroup(_ group: InputSchemaViewModel.SchemaGroup)
}
