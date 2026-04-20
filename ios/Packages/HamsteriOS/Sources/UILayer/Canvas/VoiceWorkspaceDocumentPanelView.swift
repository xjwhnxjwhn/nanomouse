//
//  VoiceWorkspaceDocumentPanelView.swift
//
//
//  Created by Codex on 2026/4/20.
//

import HamsterUIKit
import UIKit

final class VoiceWorkspaceDocumentPanelView: NibLessView {
  private lazy var headerStackView: UIStackView = {
    let view = UIStackView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.axis = .horizontal
    view.alignment = .center
    view.spacing = 10
    return view
  }()

  private lazy var titleStackView: UIStackView = {
    let view = UIStackView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.axis = .vertical
    view.alignment = .fill
    view.spacing = 2
    return view
  }()

  private lazy var actionsStackView: UIStackView = {
    let view = UIStackView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.axis = .horizontal
    view.alignment = .center
    view.spacing = 8
    return view
  }()

  private lazy var separatorView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .separator
    return view
  }()

  let titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.textColor = .label
    label.numberOfLines = 1
    return label
  }()

  let pathLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 11, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 1
    label.lineBreakMode = .byTruncatingMiddle
    return label
  }()

  let backButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "chevron.left")
    configuration.baseForegroundColor = .label
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
    button.configuration = configuration
    button.widthAnchor.constraint(equalToConstant: 30).isActive = true
    button.heightAnchor.constraint(equalToConstant: 30).isActive = true
    button.accessibilityLabel = "返回上一级"
    return button
  }()

  let newDocumentButton: UIButton = VoiceWorkspaceDocumentPanelView.makeActionButton(
    title: "新建文件",
    symbol: "doc.badge.plus"
  )

  let newFolderButton: UIButton = VoiceWorkspaceDocumentPanelView.makeActionButton(
    title: "新建文件夹",
    symbol: "folder.badge.plus"
  )

  let saveButton: UIButton = VoiceWorkspaceDocumentPanelView.makeActionButton(
    title: "保存",
    symbol: "square.and.arrow.down"
  )

  let tableView: UITableView = {
    let view = UITableView(frame: .zero, style: .plain)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.rowHeight = 58
    view.estimatedRowHeight = 58
    view.tableFooterView = UIView()
    view.backgroundColor = .clear
    view.register(UITableViewCell.self, forCellReuseIdentifier: "VoiceWorkspaceDocumentCell")
    view.separatorStyle = .singleLine
    view.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 14)
    return view
  }()

  let emptyLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    label.text = "还没有文件"
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    constructViewHierarchy()
    activateViewConstraints()
    configureAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(headerStackView)
    headerStackView.addArrangedSubview(backButton)
    headerStackView.addArrangedSubview(titleStackView)
    headerStackView.addArrangedSubview(actionsStackView)
    titleStackView.addArrangedSubview(titleLabel)
    titleStackView.addArrangedSubview(pathLabel)
    actionsStackView.addArrangedSubview(newDocumentButton)
    actionsStackView.addArrangedSubview(newFolderButton)
    actionsStackView.addArrangedSubview(saveButton)
    addSubview(separatorView)
    addSubview(tableView)
    addSubview(emptyLabel)
  }

  override func activateViewConstraints() {
    NSLayoutConstraint.activate([
      headerStackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      headerStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      headerStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

      separatorView.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: 10),
      separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      separatorView.heightAnchor.constraint(equalToConstant: 0.5),

      tableView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 2),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
      emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
      emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
    ])
  }

  private func configureAppearance() {
    backgroundColor = .secondarySystemGroupedBackground
    layer.cornerRadius = 16
    layer.masksToBounds = true
    layer.borderWidth = 1 / UIScreen.main.scale
    layer.borderColor = UIColor.separator.cgColor
  }

  func updatePath(_ text: String, canGoBack: Bool, isEmpty: Bool) {
    pathLabel.text = text
    backButton.isHidden = !canGoBack
    emptyLabel.isHidden = !isEmpty
    tableView.isHidden = isEmpty
  }

  private static func makeActionButton(title: String, symbol: String) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.tinted()
    configuration.image = UIImage(systemName: symbol)
    configuration.baseForegroundColor = .label
    configuration.baseBackgroundColor = .tertiarySystemFill
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
    configuration.cornerStyle = .capsule
    button.configuration = configuration
    button.accessibilityLabel = title
    button.widthAnchor.constraint(equalToConstant: 32).isActive = true
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    return button
  }
}
