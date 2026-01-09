//
//  InputSchemaRootView.swift
//
//
//  Created by morse on 2023/7/8.
//

import Combine
import HamsterKit
import HamsterUIKit
import ProgressHUD
import UIKit

class InputSchemaRootView: NibLessView {
  // MARK: properties

  private static let cellIdentifier = "InputSchemaTableCell"

  private let inputSchemaViewModel: InputSchemaViewModel

  private var subscriptions = Set<AnyCancellable>()

  let tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: InputSchemaRootView.cellIdentifier)
    return tableView
  }()

  // MARK: methods

  init(frame: CGRect = .zero, inputSchemaViewModel: InputSchemaViewModel) {
    self.inputSchemaViewModel = inputSchemaViewModel

    super.init(frame: frame)

    constructViewHierarchy()
    activateViewConstraints()

    inputSchemaViewModel.reloadTableStatePublisher
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] _ in
        tableView.reloadData()
      }
      .store(in: &subscriptions)
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

extension InputSchemaRootView: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    let baseSections = InputSchemaViewModel.SchemaGroup.allCases.count
    return baseSections + (inputSchemaViewModel.shouldShowRimeIceTraditionalizationSection ? 1 : 0)
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    let groupCount = InputSchemaViewModel.SchemaGroup.allCases.count
    if section < groupCount {
      guard let group = InputSchemaViewModel.SchemaGroup(rawValue: section) else { return 0 }
      return inputSchemaViewModel.schemas(in: group).count
    }
    return InputSchemaViewModel.TraditionalizationOption.allCases.count
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = self.tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
    let groupCount = InputSchemaViewModel.SchemaGroup.allCases.count
    var config = UIListContentConfiguration.cell()

    if indexPath.section < groupCount, let group = InputSchemaViewModel.SchemaGroup(rawValue: indexPath.section) {
      let schema = inputSchemaViewModel.schemas(in: group)[indexPath.row]
      config.text = inputSchemaViewModel.displayNameForInputSchemaList(schema)
      cell.accessoryType = inputSchemaViewModel.isSchemaSelected(schema) ? .checkmark : .none
    } else {
      let option = InputSchemaViewModel.TraditionalizationOption.allCases[indexPath.row]
      config.text = option.displayName
      cell.accessoryType = inputSchemaViewModel.isTraditionalizationOptionSelected(option) ? .checkmark : .none
    }

    cell.contentConfiguration = config
    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    let groupCount = InputSchemaViewModel.SchemaGroup.allCases.count
    if section < groupCount, let group = InputSchemaViewModel.SchemaGroup(rawValue: section) {
      return group.title
    }
    return "雾凇拼音 · 繁体方案"
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    let groupCount = InputSchemaViewModel.SchemaGroup.allCases.count
    guard section >= groupCount else { return nil }
    return "切换繁体方案会立即触发重新部署（是否覆盖词库文件与 RIME 菜单设置保持一致）。"
  }
}

extension InputSchemaRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    Task {
      do {
        let groupCount = InputSchemaViewModel.SchemaGroup.allCases.count
        if indexPath.section < groupCount, let group = InputSchemaViewModel.SchemaGroup(rawValue: indexPath.section) {
          let schema = inputSchemaViewModel.schemas(in: group)[indexPath.row]
          try await inputSchemaViewModel.checkboxForInputSchema(schema)
        } else {
          let option = InputSchemaViewModel.TraditionalizationOption.allCases[indexPath.row]
          inputSchemaViewModel.selectTraditionalizationOption(option)
        }
      } catch {
        ProgressHUD.failed(error.localizedDescription, delay: 1.5)
      }
    }
  }
}
