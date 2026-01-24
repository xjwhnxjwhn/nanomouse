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

  /// 当前显示的分组（nil 表示显示所有分组，用于兼容旧逻辑）
  private let schemaGroup: InputSchemaViewModel.SchemaGroup?

  private var subscriptions = Set<AnyCancellable>()

  let tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: InputSchemaRootView.cellIdentifier)
    return tableView
  }()

  // MARK: methods

  init(frame: CGRect = .zero, inputSchemaViewModel: InputSchemaViewModel, schemaGroup: InputSchemaViewModel.SchemaGroup? = nil) {
    self.inputSchemaViewModel = inputSchemaViewModel
    self.schemaGroup = schemaGroup

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

  // MARK: - Section 类型定义

  private enum SectionType {
    case schemaList(InputSchemaViewModel.SchemaGroup)
    case traditional
    case azooKeyMode
    case azooKeyAdvanced
  }

  /// 根据当前分组过滤条件，计算可见的 sections
  private var visibleSections: [SectionType] {
    var sections: [SectionType] = []

    // 如果指定了分组，只显示该分组相关的 sections
    if let group = schemaGroup {
      switch group {
      case .chineseEnglish:
        sections.append(.schemaList(.chineseEnglish))
        if inputSchemaViewModel.shouldShowRimeIceTraditionalizationSection {
          sections.append(.traditional)
        }
      case .japanese:
        sections.append(.schemaList(.japanese))
        if inputSchemaViewModel.shouldShowAzooKeyModeSection {
          sections.append(.azooKeyMode)
          sections.append(.azooKeyAdvanced)
        }
      }
    } else {
      // 兼容旧逻辑：显示所有 sections
      sections.append(.schemaList(.chineseEnglish))
      if inputSchemaViewModel.shouldShowRimeIceTraditionalizationSection {
        sections.append(.traditional)
      }
      sections.append(.schemaList(.japanese))
      if inputSchemaViewModel.shouldShowAzooKeyModeSection {
        sections.append(.azooKeyMode)
        sections.append(.azooKeyAdvanced)
      }
    }

    return sections
  }

  private func sectionType(for section: Int) -> SectionType? {
    guard section < visibleSections.count else { return nil }
    return visibleSections[section]
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
    schema.schemaId == HamsterConstants.azooKeySchemaId
  }

  /// 已下载的推荐方案显示的标签视图（推荐 + 可选的 checkmark）
  private func recommendedBadgeView(isSelected: Bool) -> UIView {
    let badge = UILabel()
    badge.text = "推荐"
    badge.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    badge.textColor = .systemOrange
    badge.sizeToFit()

    if isSelected {
      let checkmark = UIImageView(image: UIImage(systemName: "checkmark"))
      checkmark.tintColor = .systemBlue
      checkmark.sizeToFit()

      let spacing: CGFloat = 8
      let height = max(badge.bounds.height, checkmark.bounds.height)
      let width = badge.bounds.width + spacing + checkmark.bounds.width
      let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))

      badge.frame = CGRect(
        x: 0,
        y: (height - badge.bounds.height) / 2,
        width: badge.bounds.width,
        height: badge.bounds.height
      )
      checkmark.frame = CGRect(
        x: badge.frame.maxX + spacing,
        y: (height - checkmark.bounds.height) / 2,
        width: checkmark.bounds.width,
        height: checkmark.bounds.height
      )

      container.addSubview(badge)
      container.addSubview(checkmark)
      return container
    } else {
      return badge
    }
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
    visibleSections.count
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let sectionType = sectionType(for: section) else { return 0 }
    switch sectionType {
    case .schemaList(let group):
      return inputSchemaViewModel.schemas(in: group).count
    case .traditional:
      return InputSchemaViewModel.TraditionalizationOption.allCases.count
    case .azooKeyMode:
      return InputSchemaViewModel.AzooKeyModeOption.allCases.count
    case .azooKeyAdvanced:
      return InputSchemaViewModel.AzooKeyAdvancedOption.allCases.count
    }
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = self.tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
    var config = UIListContentConfiguration.cell()

    guard let sectionType = sectionType(for: indexPath.section) else { return cell }

    switch sectionType {
    case .traditional:
      let option = InputSchemaViewModel.TraditionalizationOption.allCases[indexPath.row]
      config.text = option.displayName
      cell.contentConfiguration = config
      cell.accessoryView = nil
      cell.accessoryType = inputSchemaViewModel.isTraditionalizationOptionSelected(option) ? .checkmark : .none
      return cell

    case .azooKeyMode:
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

    case .azooKeyAdvanced:
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

    case .schemaList(let group):
      let schemas = inputSchemaViewModel.schemas(in: group)
      let schema = schemas[indexPath.row]
      let isJapanese = group == .japanese
      let isAvailable = inputSchemaViewModel.isSchemaAvailable(schema)
      config.text = inputSchemaViewModel.displayNameForInputSchemaList(schema)
      cell.contentConfiguration = config
      if isJapanese, !isAvailable {
        cell.accessoryView = downloadAccessoryView(for: schema)
        cell.accessoryType = .none
      } else if isRecommendedSchema(schema) {
        // 已下载的推荐方案：显示推荐标签
        cell.accessoryView = recommendedBadgeView(isSelected: inputSchemaViewModel.isSchemaSelected(schema))
        cell.accessoryType = .none
      } else {
        cell.accessoryView = nil
        cell.accessoryType = inputSchemaViewModel.isSchemaSelected(schema) ? .checkmark : .none
      }
      return cell
    }
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    guard let sectionType = sectionType(for: section) else { return nil }
    switch sectionType {
    case .schemaList(let group):
      // 如果是单独分组页面，不显示分组标题（因为页面标题已经说明了）
      return schemaGroup != nil ? nil : group.title
    case .traditional:
      return "雾凇拼音 · 繁体方案"
    case .azooKeyMode:
      return "AzooKey 模式"
    case .azooKeyAdvanced:
      return "AzooKey 高级设置"
    }
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    guard let sectionType = sectionType(for: section) else { return nil }
    switch sectionType {
    case .schemaList(let group):
      return group == .japanese ? "日语方案不随安装包内置，右侧可按需下载。" : nil
    case .traditional:
      return "切换繁体方案会立即触发重新部署（是否覆盖词库文件与 RIME 菜单设置保持一致）。"
    case .azooKeyMode:
      return "Zenzai 为可选增强模式，需要单独下载后启用。"
    case .azooKeyAdvanced:
      return nil
    }
  }
}

extension InputSchemaRootView: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    Task {
      do {
        guard let sectionType = sectionType(for: indexPath.section) else { return }

        switch sectionType {
        case .traditional:
          let option = InputSchemaViewModel.TraditionalizationOption.allCases[indexPath.row]
          inputSchemaViewModel.selectTraditionalizationOption(option)

        case .azooKeyMode:
          let option = InputSchemaViewModel.AzooKeyModeOption.allCases[indexPath.row]
          guard inputSchemaViewModel.isAzooKeyModeOptionAvailable(option) else { return }
          inputSchemaViewModel.selectAzooKeyModeOption(option)

        case .azooKeyAdvanced:
          let option = InputSchemaViewModel.AzooKeyAdvancedOption.allCases[indexPath.row]
          inputSchemaViewModel.toggleAzooKeyAdvancedOption(option)

        case .schemaList(let group):
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
    guard let sectionType = sectionType(for: indexPath.section),
          case .schemaList(let group) = sectionType,
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
