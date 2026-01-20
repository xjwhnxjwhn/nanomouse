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

  private var hasTraditionalSection: Bool {
    inputSchemaViewModel.shouldShowRimeIceTraditionalizationSection
  }

  private var hasAzooKeyModeSection: Bool {
    inputSchemaViewModel.shouldShowAzooKeyModeSection
  }

  private var hasAzooKeyAdvancedSection: Bool {
    inputSchemaViewModel.shouldShowAzooKeyModeSection
  }

  private var japaneseSectionIndex: Int {
    1 + (hasTraditionalSection ? 1 : 0)
  }

  private var traditionalSectionIndex: Int? {
    hasTraditionalSection ? 1 : nil
  }

  private var azooKeyModeSectionIndex: Int? {
    hasAzooKeyModeSection ? japaneseSectionIndex + 1 : nil
  }

  private var azooKeyAdvancedSectionIndex: Int? {
    hasAzooKeyAdvancedSection ? japaneseSectionIndex + 2 : nil
  }

  private func schemaGroup(for section: Int) -> InputSchemaViewModel.SchemaGroup? {
    if section == 0 { return .chineseEnglish }
    if section == japaneseSectionIndex { return .japanese }
    return nil
  }

  private func downloadAccessoryView(for schema: RimeSchema) -> UIView {
    let button = downloadButton(for: schema)
    guard isRecommendedSchema(schema) else { return button }

    let badge = UILabel()
    badge.text = "推荐"
    badge.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    badge.textColor = .systemOrange
    badge.sizeToFit()

    let spacing: CGFloat = 6
    let height = max(badge.bounds.height, button.bounds.height)
    let width = badge.bounds.width + spacing + button.bounds.width
    let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))

    badge.frame = CGRect(
      x: 0,
      y: (height - badge.bounds.height) / 2,
      width: badge.bounds.width,
      height: badge.bounds.height
    )
    button.frame = CGRect(
      x: badge.frame.maxX + spacing,
      y: (height - button.bounds.height) / 2,
      width: button.bounds.width,
      height: button.bounds.height
    )

    container.addSubview(badge)
    container.addSubview(button)
    return container
  }

  private func isRecommendedSchema(_ schema: RimeSchema) -> Bool {
    schema.schemaId == "jaroomaji-easy"
  }

  private func downloadButton(for schema: RimeSchema) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle("下载", for: .normal)
    button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    button.sizeToFit()
    button.addAction(UIAction { [unowned self] _ in
      self.inputSchemaViewModel.downloadJapaneseSchema(schema)
    }, for: .touchUpInside)
    return button
  }

  private func azooKeyModeDownloadButton() -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle("下载", for: .normal)
    button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    button.sizeToFit()
    button.showsMenuAsPrimaryAction = true
    button.menu = zenzaiDownloadMenu()
    return button
  }

  private func zenzaiDownloadMenu() -> UIMenu {
    var actions: [UIAction] = []

    // Low 选项始终可用
    let lowAction = UIAction(
      title: "Low（21MB）",
      subtitle: "适合大多数设备",
      image: UIImage(systemName: "arrow.down.circle")
    ) { [unowned self] _ in
      self.inputSchemaViewModel.downloadAzooKeyZenzai(quality: .low)
    }
    actions.append(lowAction)

    // High 选项仅在支持的设备上显示
    if inputSchemaViewModel.isHighQualityZenzaiSupported {
      let highAction = UIAction(
        title: "High（74MB）",
        subtitle: "更高精度",
        image: UIImage(systemName: "arrow.down.circle.fill")
      ) { [unowned self] _ in
        self.inputSchemaViewModel.downloadAzooKeyZenzai(quality: .high)
      }
      actions.append(highAction)
    }

    return UIMenu(title: "选择模型质量", children: actions)
  }
}

extension InputSchemaRootView: UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    let baseSections = InputSchemaViewModel.SchemaGroup.allCases.count
    return baseSections + (hasTraditionalSection ? 1 : 0) + (hasAzooKeyModeSection ? 1 : 0) + (hasAzooKeyAdvancedSection ? 1 : 0)
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if let traditionalSectionIndex, section == traditionalSectionIndex {
      return InputSchemaViewModel.TraditionalizationOption.allCases.count
    }
    if let azooKeyModeSectionIndex, section == azooKeyModeSectionIndex {
      return InputSchemaViewModel.AzooKeyModeOption.allCases.count
    }
    if let azooKeyAdvancedSectionIndex, section == azooKeyAdvancedSectionIndex {
      return InputSchemaViewModel.AzooKeyAdvancedOption.allCases.count
    }
    guard let group = schemaGroup(for: section) else { return 0 }
    return inputSchemaViewModel.schemas(in: group).count
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = self.tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
    var config = UIListContentConfiguration.cell()

    if let traditionalSectionIndex, indexPath.section == traditionalSectionIndex {
      let option = InputSchemaViewModel.TraditionalizationOption.allCases[indexPath.row]
      config.text = option.displayName
      cell.contentConfiguration = config
      cell.accessoryView = nil
      cell.accessoryType = inputSchemaViewModel.isTraditionalizationOptionSelected(option) ? .checkmark : .none
      return cell
    }
    if let azooKeyModeSectionIndex, indexPath.section == azooKeyModeSectionIndex {
      let option = InputSchemaViewModel.AzooKeyModeOption.allCases[indexPath.row]
      config.text = option.displayName
      cell.contentConfiguration = config
      let available = inputSchemaViewModel.isAzooKeyModeOptionAvailable(option)
      if !available, option == .zenzai {
        cell.accessoryView = azooKeyModeDownloadButton()
        cell.accessoryType = .none
      } else {
        cell.accessoryView = nil
        cell.accessoryType = inputSchemaViewModel.isAzooKeyModeOptionSelected(option) ? .checkmark : .none
      }
      return cell
    }
    if let azooKeyAdvancedSectionIndex, indexPath.section == azooKeyAdvancedSectionIndex {
      let option = InputSchemaViewModel.AzooKeyAdvancedOption.allCases[indexPath.row]
      config.text = option.displayName
      config.secondaryText = option.explanation
      config.secondaryTextProperties.color = .secondaryLabel
      config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
      cell.contentConfiguration = config
      let toggle = UISwitch()
      toggle.isOn = inputSchemaViewModel.isAzooKeyAdvancedOptionEnabled(option)
      toggle.tag = indexPath.row
      toggle.addAction(UIAction { [unowned self] action in
        guard let sw = action.sender as? UISwitch else { return }
        let opt = InputSchemaViewModel.AzooKeyAdvancedOption.allCases[sw.tag]
        self.inputSchemaViewModel.toggleAzooKeyAdvancedOption(opt)
      }, for: .valueChanged)
      cell.accessoryView = toggle
      cell.accessoryType = .none
      return cell
    }

    guard let group = schemaGroup(for: indexPath.section) else { return cell }
    let schemas = inputSchemaViewModel.schemas(in: group)
    let schema = schemas[indexPath.row]
    let isJapanese = group == .japanese
    let isAvailable = inputSchemaViewModel.isSchemaAvailable(schema)
    config.text = inputSchemaViewModel.displayNameForInputSchemaList(schema)
    cell.contentConfiguration = config
    if isJapanese, !isAvailable {
      cell.accessoryView = downloadAccessoryView(for: schema)
      cell.accessoryType = .none
    } else {
      cell.accessoryView = nil
      cell.accessoryType = inputSchemaViewModel.isSchemaSelected(schema) ? .checkmark : .none
    }
    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    if let traditionalSectionIndex, section == traditionalSectionIndex {
      return "雾凇拼音 · 繁体方案"
    }
    if let azooKeyModeSectionIndex, section == azooKeyModeSectionIndex {
      return "AzooKey 模式"
    }
    if let azooKeyAdvancedSectionIndex, section == azooKeyAdvancedSectionIndex {
      return "AzooKey 高级设置"
    }
    if let group = schemaGroup(for: section) {
      return group.title
    }
    return "雾凇拼音 · 繁体方案"
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    if let group = schemaGroup(for: section), group == .japanese {
      return "日语方案不随安装包内置，右侧可按需下载。"
    }
    if let azooKeyModeSectionIndex, section == azooKeyModeSectionIndex {
      return "Zenzai 为可选增强模式，需要单独下载后启用。"
    }
    if let azooKeyAdvancedSectionIndex, section == azooKeyAdvancedSectionIndex {
      return nil
    }
    if let traditionalSectionIndex, section == traditionalSectionIndex {
      return "切换繁体方案会立即触发重新部署（是否覆盖词库文件与 RIME 菜单设置保持一致）。"
    }
    return nil
  }
}

extension InputSchemaRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    Task {
      do {
        if let traditionalSectionIndex, indexPath.section == traditionalSectionIndex {
          let option = InputSchemaViewModel.TraditionalizationOption.allCases[indexPath.row]
          inputSchemaViewModel.selectTraditionalizationOption(option)
          return
        }
        if let azooKeyModeSectionIndex, indexPath.section == azooKeyModeSectionIndex {
          let option = InputSchemaViewModel.AzooKeyModeOption.allCases[indexPath.row]
          guard inputSchemaViewModel.isAzooKeyModeOptionAvailable(option) else { return }
          inputSchemaViewModel.selectAzooKeyModeOption(option)
          return
        }
        if let azooKeyAdvancedSectionIndex, indexPath.section == azooKeyAdvancedSectionIndex {
          // 高级设置使用 UISwitch，点击行时切换开关状态
          let option = InputSchemaViewModel.AzooKeyAdvancedOption.allCases[indexPath.row]
          inputSchemaViewModel.toggleAzooKeyAdvancedOption(option)
          return
        }
        if let group = schemaGroup(for: indexPath.section) {
          let schemas = inputSchemaViewModel.schemas(in: group)
          let schema = schemas[indexPath.row]
          if group == .japanese, !inputSchemaViewModel.isSchemaAvailable(schema) { return }
          try await inputSchemaViewModel.checkboxForInputSchema(schema)
        }
      } catch {
        ProgressHUD.failed(error.localizedDescription, delay: 1.5)
      }
    }
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    guard let group = schemaGroup(for: indexPath.section),
          group == .japanese else { return nil }
    let schemas = inputSchemaViewModel.schemas(in: group)
    let schema = schemas[indexPath.row]
    guard inputSchemaViewModel.isSchemaAvailable(schema) else { return nil }

    let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      guard let self else {
        completion(false)
        return
      }
      Task {
        await self.inputSchemaViewModel.deleteDownloadedSchema(schema)
        completion(true)
      }
    }
    return UISwipeActionsConfiguration(actions: [deleteAction])
  }
}
