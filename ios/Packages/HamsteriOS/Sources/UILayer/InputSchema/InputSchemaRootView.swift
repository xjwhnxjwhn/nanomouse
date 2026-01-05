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
    InputSchemaViewModel.SchemaGroup.allCases.count
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let group = InputSchemaViewModel.SchemaGroup(rawValue: section) else { return 0 }
    return inputSchemaViewModel.schemas(in: group).count
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = self.tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
    guard let group = InputSchemaViewModel.SchemaGroup(rawValue: indexPath.section) else { return cell }
    let schema = inputSchemaViewModel.schemas(in: group)[indexPath.row]

    var config = UIListContentConfiguration.cell()
    config.text = inputSchemaViewModel.displayNameForInputSchemaList(schema)
    cell.contentConfiguration = config
    cell.accessoryType = inputSchemaViewModel.isSchemaSelected(schema) ? .checkmark : .none

    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    guard let group = InputSchemaViewModel.SchemaGroup(rawValue: section) else { return nil }
    return group.title
  }
}

extension InputSchemaRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    Task {
      do {
        guard let group = InputSchemaViewModel.SchemaGroup(rawValue: indexPath.section) else { return }
        let schema = inputSchemaViewModel.schemas(in: group)[indexPath.row]
        try await inputSchemaViewModel.checkboxForInputSchema(schema)
      } catch {
        ProgressHUD.failed(error.localizedDescription, delay: 1.5)
      }
    }
  }
}
