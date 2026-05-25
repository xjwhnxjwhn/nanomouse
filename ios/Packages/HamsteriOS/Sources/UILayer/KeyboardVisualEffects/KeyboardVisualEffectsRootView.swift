//
//  KeyboardVisualEffectsRootView.swift
//
//
//  Created by Codex on 2026/05/24.
//

import Combine
import HamsterKeyboardKit
import HamsterUIKit
import UIKit

final class KeyboardVisualEffectsRootView: NibLessView {
  private let keyboardSettingsViewModel: KeyboardSettingsViewModel
  private let schemeStore = KeyboardVisualEffectSchemeStore.shared
  private var subscriptions = Set<AnyCancellable>()
  private var selectedKeyboardType: KeyboardType = .chinese(.lowercased)
  private var selectedVisualEffectUserInterfaceStyle: UIUserInterfaceStyle = .light
  private var layoutButtons: [UIButton] = []
  private var schemeButtons: [UIButton] = []
  private var schemes: [KeyboardVisualEffectScheme] = []
  private var selectedSchemeID: String?
  private var tableHeightConstraint: NSLayoutConstraint?
  private var layoutContentHeightConstraint: NSLayoutConstraint?
  private var previewDockHeightConstraint: NSLayoutConstraint?

  private lazy var scrollView: UIScrollView = {
    let scrollView = UIScrollView(frame: .zero)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.alwaysBounceVertical = true
    scrollView.keyboardDismissMode = .interactive
    return scrollView
  }()

  private lazy var contentView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var appearanceModeControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["亮色模式", "暗色模式"])
    control.translatesAutoresizingMaskIntoConstraints = false
    control.selectedSegmentIndex = selectedVisualEffectUserInterfaceStyle == .dark ? 1 : 0
    control.addTarget(self, action: #selector(appearanceModeChanged(_:)), for: .valueChanged)
    return control
  }()

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.isScrollEnabled = false
    tableView.register(SettingTableViewCell.self, forCellReuseIdentifier: SettingTableViewCell.identifier)
    tableView.register(ToggleTableViewCell.self, forCellReuseIdentifier: ToggleTableViewCell.identifier)
    tableView.register(TextFieldTableViewCell.self, forCellReuseIdentifier: TextFieldTableViewCell.identifier)
    tableView.register(ButtonTableViewCell.self, forCellReuseIdentifier: ButtonTableViewCell.identifier)
    tableView.register(PullDownMenuCell.self, forCellReuseIdentifier: PullDownMenuCell.identifier)
    tableView.register(StepperTableViewCell.self, forCellReuseIdentifier: StepperTableViewCell.identifier)
    tableView.register(KeyboardVisualEffectPreviewTableViewCell.self, forCellReuseIdentifier: KeyboardVisualEffectPreviewTableViewCell.identifier)
    return tableView
  }()

  private lazy var layoutTabScrollView: UIScrollView = {
    let scrollView = UIScrollView(frame: .zero)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsHorizontalScrollIndicator = false
    return scrollView
  }()

  private lazy var layoutTabStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.spacing = 8
    stack.alignment = .fill
    return stack
  }()

  private lazy var schemeTitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .preferredFont(forTextStyle: .headline)
    label.textColor = .label
    label.text = "当前方案：方案1"
    return label
  }()

  private lazy var schemeTabScrollView: UIScrollView = {
    let scrollView = UIScrollView(frame: .zero)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsHorizontalScrollIndicator = false
    return scrollView
  }()

  private lazy var schemeTabStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.spacing = 8
    stack.alignment = .fill
    return stack
  }()

  private lazy var schemeActionStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.spacing = 8
    stack.distribution = .fillEqually
    return stack
  }()

  private lazy var layoutContentContainer: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = true
    return view
  }()

  private lazy var previewDockView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .secondarySystemBackground
    return view
  }()

  private lazy var previewDockContentView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = false
    return view
  }()

  private lazy var customLayoutView: ChineseKeyboardCustomLayoutSettingsView = {
    let view = ChineseKeyboardCustomLayoutSettingsView(usesInternalScrollView: false)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.contentHeightDidChange = { [weak self] height in
      self?.updateLayoutContentHeight(preferredContentHeight: height)
    }
    view.previewHeightDidChange = { [weak self] height in
      self?.previewDockHeightConstraint?.constant = height + 16
      self?.updateLayoutContentHeight()
    }
    return view
  }()

  private lazy var unsupportedLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "当前先提供中文 26 键的完整视觉预览和键帽自定义。其它布局会按上方顺序保留入口，后续接入对应编辑面板。"
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = .secondaryLabel
    label.isHidden = true
    return label
  }()

  init(keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel
    super.init(frame: .zero)
    setupView()
  }

  private func setupView() {
    backgroundColor = .secondarySystemBackground
    tableView.dataSource = self
    tableView.delegate = self

    selectedVisualEffectUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .dark : .light
    appearanceModeControl.selectedSegmentIndex = selectedVisualEffectUserInterfaceStyle == .dark ? 1 : 0
    customLayoutView.visualEffectPreviewUserInterfaceStyle = selectedVisualEffectUserInterfaceStyle

    addSubview(scrollView)
    addSubview(previewDockView)
    scrollView.addSubview(contentView)
    previewDockView.addSubview(previewDockContentView)
    contentView.addSubview(appearanceModeControl)
    contentView.addSubview(layoutTabScrollView)
    contentView.addSubview(schemeTitleLabel)
    contentView.addSubview(schemeTabScrollView)
    contentView.addSubview(schemeActionStack)
    contentView.addSubview(tableView)
    contentView.addSubview(layoutContentContainer)
    layoutContentContainer.addSubview(customLayoutView)
    layoutContentContainer.addSubview(unsupportedLabel)
    layoutTabScrollView.addSubview(layoutTabStack)
    schemeTabScrollView.addSubview(schemeTabStack)
    setupSchemeActions()

    let tableHeightConstraint = tableView.heightAnchor.constraint(equalToConstant: 420)
    self.tableHeightConstraint = tableHeightConstraint
    let layoutContentHeightConstraint = layoutContentContainer.heightAnchor.constraint(equalToConstant: 860)
    self.layoutContentHeightConstraint = layoutContentHeightConstraint
    let previewDockHeightConstraint = previewDockView.heightAnchor.constraint(equalToConstant: 240)
    self.previewDockHeightConstraint = previewDockHeightConstraint
    customLayoutView.attachPreview(to: previewDockContentView)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: previewDockView.topAnchor),

      previewDockView.leadingAnchor.constraint(equalTo: leadingAnchor),
      previewDockView.trailingAnchor.constraint(equalTo: trailingAnchor),
      previewDockView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
      previewDockHeightConstraint,

      previewDockContentView.topAnchor.constraint(equalTo: previewDockView.topAnchor, constant: 8),
      previewDockContentView.leadingAnchor.constraint(equalTo: previewDockView.leadingAnchor, constant: 16),
      previewDockContentView.trailingAnchor.constraint(equalTo: previewDockView.trailingAnchor, constant: -16),
      previewDockContentView.bottomAnchor.constraint(equalTo: previewDockView.bottomAnchor, constant: -8),

      contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

      appearanceModeControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
      appearanceModeControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      appearanceModeControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

      layoutTabScrollView.topAnchor.constraint(equalTo: appearanceModeControl.bottomAnchor, constant: 8),
      layoutTabScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      layoutTabScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      layoutTabScrollView.heightAnchor.constraint(equalToConstant: 52),

      layoutTabStack.topAnchor.constraint(equalTo: layoutTabScrollView.contentLayoutGuide.topAnchor, constant: 8),
      layoutTabStack.leadingAnchor.constraint(equalTo: layoutTabScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
      layoutTabStack.trailingAnchor.constraint(equalTo: layoutTabScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
      layoutTabStack.bottomAnchor.constraint(equalTo: layoutTabScrollView.contentLayoutGuide.bottomAnchor, constant: -8),
      layoutTabStack.heightAnchor.constraint(equalTo: layoutTabScrollView.frameLayoutGuide.heightAnchor, constant: -16),

      schemeTitleLabel.topAnchor.constraint(equalTo: layoutTabScrollView.bottomAnchor, constant: 2),
      schemeTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      schemeTitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

      schemeTabScrollView.topAnchor.constraint(equalTo: schemeTitleLabel.bottomAnchor, constant: 2),
      schemeTabScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      schemeTabScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      schemeTabScrollView.heightAnchor.constraint(equalToConstant: 48),

      schemeTabStack.topAnchor.constraint(equalTo: schemeTabScrollView.contentLayoutGuide.topAnchor, constant: 6),
      schemeTabStack.leadingAnchor.constraint(equalTo: schemeTabScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
      schemeTabStack.trailingAnchor.constraint(equalTo: schemeTabScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
      schemeTabStack.bottomAnchor.constraint(equalTo: schemeTabScrollView.contentLayoutGuide.bottomAnchor, constant: -6),
      schemeTabStack.heightAnchor.constraint(equalTo: schemeTabScrollView.frameLayoutGuide.heightAnchor, constant: -12),

      schemeActionStack.topAnchor.constraint(equalTo: schemeTabScrollView.bottomAnchor, constant: 4),
      schemeActionStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      schemeActionStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      schemeActionStack.heightAnchor.constraint(equalToConstant: 38),

      tableView.topAnchor.constraint(equalTo: schemeActionStack.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      tableHeightConstraint,

      layoutContentContainer.topAnchor.constraint(equalTo: tableView.bottomAnchor),
      layoutContentContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      layoutContentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      layoutContentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      layoutContentHeightConstraint,

      customLayoutView.topAnchor.constraint(equalTo: layoutContentContainer.topAnchor),
      customLayoutView.leadingAnchor.constraint(equalTo: layoutContentContainer.leadingAnchor),
      customLayoutView.trailingAnchor.constraint(equalTo: layoutContentContainer.trailingAnchor),
      customLayoutView.bottomAnchor.constraint(equalTo: layoutContentContainer.bottomAnchor),

      unsupportedLabel.centerYAnchor.constraint(equalTo: layoutContentContainer.centerYAnchor),
      unsupportedLabel.leadingAnchor.constraint(equalTo: layoutContentContainer.leadingAnchor, constant: 24),
      unsupportedLabel.trailingAnchor.constraint(equalTo: layoutContentContainer.trailingAnchor, constant: -24)
    ])

    rebuildLayoutTabs()
    reloadSchemes(applyActive: true)

    keyboardSettingsViewModel.resetSignPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.reloadVisualEffects()
      }
      .store(in: &subscriptions)

    keyboardSettingsViewModel.keyboardVisualEffectPreviewChangePublished
      .debounce(for: .milliseconds(220), scheduler: DispatchQueue.main)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.customLayoutView.reloadPreview()
      }
      .store(in: &subscriptions)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else { return }
    reloadVisualEffects()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateLayoutContentHeight()
  }

  private func reloadVisualEffects() {
    reloadSettingsTable()
    updateLayoutContentHeight()
    customLayoutView.reloadPreview()
  }

  private func reloadSettingsTable() {
    tableView.reloadData()
    tableView.layoutIfNeeded()
    tableHeightConstraint?.constant = max(240, tableView.contentSize.height)
  }

  private func setupSchemeActions() {
    schemeActionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    [
      ("新建方案", #selector(createScheme)),
      ("保存方案", #selector(saveScheme)),
      ("导出JSON", #selector(exportScheme))
    ].forEach { item in
      let (title, action) = item
      var config = UIButton.Configuration.tinted()
      config.title = title
      config.cornerStyle = .medium
      let button = UIButton(configuration: config)
      button.titleLabel?.adjustsFontSizeToFitWidth = true
      button.titleLabel?.minimumScaleFactor = 0.82
      button.addTarget(self, action: action, for: .touchUpInside)
      schemeActionStack.addArrangedSubview(button)
    }
  }

  private var currentSchemeAppearance: KeyboardVisualEffectSchemeAppearance {
    KeyboardVisualEffectSchemeAppearance(selectedVisualEffectUserInterfaceStyle)
  }

  private var selectedScheme: KeyboardVisualEffectScheme? {
    schemes.first { $0.id == selectedSchemeID }
  }

  private func reloadSchemes(applyActive: Bool) {
    let appearance = currentSchemeAppearance
    schemes = schemeStore.schemes(appearance: appearance, keyboardType: selectedKeyboardType)
    if schemes.isEmpty, let scheme = createDefaultScheme() {
      schemes = [scheme]
    }

    let activeID = schemeStore.activeSchemeID(
      appearance: appearance,
      keyboardType: selectedKeyboardType
    )
    if let activeID, schemes.contains(where: { $0.id == activeID }) {
      selectedSchemeID = activeID
    } else {
      selectedSchemeID = schemes.first?.id
      schemeStore.setActiveSchemeID(
        selectedSchemeID,
        appearance: appearance,
        keyboardType: selectedKeyboardType
      )
    }

    rebuildSchemeTabs()
    if applyActive, let scheme = selectedScheme {
      applyScheme(scheme)
    } else {
      updateSchemeTitle()
    }
  }

  private func createDefaultScheme() -> KeyboardVisualEffectScheme? {
    let scheme = makeScheme(name: "方案1", forceNewLayoutProfileID: false)
    do {
      try schemeStore.save(scheme)
      schemeStore.setActiveSchemeID(
        scheme.id,
        appearance: scheme.appearance,
        keyboardType: selectedKeyboardType
      )
      selectedSchemeID = scheme.id
      return scheme
    } catch {
      showSchemeAlert("方案保存失败", message: error.localizedDescription)
      return nil
    }
  }

  private func makeScheme(
    name: String,
    id: String = UUID().uuidString,
    createdAt: Date = Date(),
    forceNewLayoutProfileID: Bool
  ) -> KeyboardVisualEffectScheme {
    var chinese26Snapshot: KeyboardVisualEffectChinese26Snapshot?
    if selectedKeyboardType == .chinese(.lowercased) {
      var snapshot = customLayoutView.visualEffectSchemeSnapshot(named: name)
      if forceNewLayoutProfileID {
        snapshot.layoutProfile.id = UUID().uuidString
      }
      snapshot.layoutProfile.name = name
      chinese26Snapshot = snapshot
    }

    return KeyboardVisualEffectScheme(
      id: id,
      name: name,
      appearance: currentSchemeAppearance,
      keyboardType: selectedKeyboardType,
      visualEffect: keyboardSettingsViewModel.keyboardVisualEffectStyleSnapshot(
        for: selectedVisualEffectUserInterfaceStyle
      ),
      chinese26: chinese26Snapshot,
      createdAt: createdAt,
      updatedAt: Date()
    )
  }

  private func rebuildSchemeTabs() {
    schemeTabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    schemeButtons.removeAll()

    for scheme in schemes {
      let button = UIButton(type: .system)
      button.configuration = tabConfiguration(title: scheme.name, selected: scheme.id == selectedSchemeID)
      button.addAction(UIAction { [weak self] _ in
        self?.selectScheme(scheme)
      }, for: .touchUpInside)
      schemeTabStack.addArrangedSubview(button)
      schemeButtons.append(button)
    }
    updateSchemeTitle()
  }

  private func updateSchemeTitle() {
    let appearanceTitle = selectedVisualEffectUserInterfaceStyle == .dark ? "暗色" : "亮色"
    let schemeName = selectedScheme?.name ?? "未保存"
    schemeTitleLabel.text = "当前方案：\(appearanceTitle) - \(selectedKeyboardType.label) - \(schemeName)"
  }

  private func selectScheme(_ scheme: KeyboardVisualEffectScheme) {
    selectedSchemeID = scheme.id
    schemeStore.setActiveSchemeID(
      scheme.id,
      appearance: currentSchemeAppearance,
      keyboardType: selectedKeyboardType
    )
    applyScheme(scheme)
    rebuildSchemeTabs()
  }

  private func applyScheme(_ scheme: KeyboardVisualEffectScheme) {
    keyboardSettingsViewModel.applyKeyboardVisualEffectStyleSnapshot(
      scheme.visualEffect,
      for: selectedVisualEffectUserInterfaceStyle,
      notifyChange: false
    )
    if selectedKeyboardType == .chinese(.lowercased), let snapshot = scheme.chinese26 {
      customLayoutView.applyVisualEffectSchemeSnapshot(snapshot)
    } else {
      customLayoutView.reloadPreview()
    }
    reloadSettingsTable()
    updateLayoutContentHeight()
    updateSchemeTitle()
  }

  @objc private func createScheme() {
    let name = nextSchemeName()
    let scheme = makeScheme(name: name, forceNewLayoutProfileID: true)
    do {
      try schemeStore.save(scheme)
      selectedSchemeID = scheme.id
      schemeStore.setActiveSchemeID(
        scheme.id,
        appearance: scheme.appearance,
        keyboardType: selectedKeyboardType
      )
      schemes.append(scheme)
      schemes.sort {
        if $0.createdAt == $1.createdAt {
          return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return $0.createdAt < $1.createdAt
      }
      applyScheme(scheme)
      rebuildSchemeTabs()
    } catch {
      showSchemeAlert("方案保存失败", message: error.localizedDescription)
    }
  }

  @objc private func saveScheme() {
    _ = persistSelectedScheme()
  }

  @objc private func exportScheme() {
    guard let scheme = persistSelectedScheme() else { return }
    do {
      let url = try schemeStore.exportURL(for: scheme)
      let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
      nearestViewController()?.present(picker, animated: true)
    } catch {
      showSchemeAlert("方案导出失败", message: error.localizedDescription)
    }
  }

  private func persistSelectedScheme() -> KeyboardVisualEffectScheme? {
    let existing = selectedScheme
    let scheme = makeScheme(
      name: existing?.name ?? nextSchemeName(),
      id: existing?.id ?? UUID().uuidString,
      createdAt: existing?.createdAt ?? Date(),
      forceNewLayoutProfileID: false
    )
    do {
      try schemeStore.save(scheme)
      selectedSchemeID = scheme.id
      schemeStore.setActiveSchemeID(
        scheme.id,
        appearance: scheme.appearance,
        keyboardType: selectedKeyboardType
      )
      schemes.removeAll { $0.id == scheme.id }
      schemes.append(scheme)
      schemes.sort {
        if $0.createdAt == $1.createdAt {
          return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return $0.createdAt < $1.createdAt
      }
      rebuildSchemeTabs()
      return scheme
    } catch {
      showSchemeAlert("方案保存失败", message: error.localizedDescription)
      return nil
    }
  }

  private func nextSchemeName() -> String {
    var index = schemes.count + 1
    let names = Set(schemes.map(\.name))
    while names.contains("方案\(index)") {
      index += 1
    }
    return "方案\(index)"
  }

  private func showSchemeAlert(_ title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    nearestViewController()?.present(alert, animated: true)
  }

  @objc private func appearanceModeChanged(_ sender: UISegmentedControl) {
    selectedVisualEffectUserInterfaceStyle = sender.selectedSegmentIndex == 1 ? .dark : .light
    customLayoutView.visualEffectPreviewUserInterfaceStyle = selectedVisualEffectUserInterfaceStyle
    reloadSchemes(applyActive: true)
    reloadSettingsTable()
    updateLayoutContentHeight()
  }

  private func updateLayoutContentHeight() {
    updateLayoutContentHeight(preferredContentHeight: nil)
  }

  private func updateLayoutContentHeight(preferredContentHeight: CGFloat?) {
    let previewHeight = previewDockHeightConstraint?.constant ?? 0
    let availableHeight = bounds.height - safeAreaInsets.top - safeAreaInsets.bottom - previewHeight - 72
    let isChinese26 = selectedKeyboardType == .chinese(.lowercased)
    let preferredHeight = preferredContentHeight ?? customLayoutView.preferredContentHeight(width: bounds.width)
    layoutContentHeightConstraint?.constant = isChinese26 ? max(preferredHeight, availableHeight, 360) : 180
  }

  private func rebuildLayoutTabs() {
    layoutTabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    layoutButtons.removeAll()

    for keyboardType in keyboardSettingsViewModel.keyboardLayoutList {
      let button = UIButton(type: .system)
      button.configuration = tabConfiguration(title: keyboardType.label, selected: keyboardType == selectedKeyboardType)
      button.addAction(UIAction { [weak self] _ in
        self?.selectKeyboardType(keyboardType)
      }, for: .touchUpInside)
      layoutTabStack.addArrangedSubview(button)
      layoutButtons.append(button)
    }
  }

  private func selectKeyboardType(_ keyboardType: KeyboardType) {
    selectedKeyboardType = keyboardType
    for (button, type) in zip(layoutButtons, keyboardSettingsViewModel.keyboardLayoutList) {
      button.configuration = tabConfiguration(title: type.label, selected: type == selectedKeyboardType)
    }

    let showChinese26 = keyboardType == .chinese(.lowercased)
    customLayoutView.isHidden = !showChinese26
    unsupportedLabel.isHidden = showChinese26
    reloadSchemes(applyActive: true)
    updateLayoutContentHeight()
  }

  private func tabConfiguration(title: String, selected: Bool) -> UIButton.Configuration {
    var config = selected ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
    config.title = title
    config.cornerStyle = .capsule
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
    return config
  }

  private var currentVisualEffectSections: [SettingSectionModel] {
    keyboardSettingsViewModel.keyboardVisualEffectSettingsItems(for: selectedVisualEffectUserInterfaceStyle)
  }
}

extension KeyboardVisualEffectsRootView: UITableViewDataSource, UITableViewDelegate {
  func numberOfSections(in tableView: UITableView) -> Int {
    currentVisualEffectSections.count
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    currentVisualEffectSections[section].items.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let setting = currentVisualEffectSections[indexPath.section].items[indexPath.row]
    switch setting.type {
    case .navigation, .settings:
      let cell = tableView.dequeueReusableCell(withIdentifier: SettingTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? SettingTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .toggle:
      let cell = tableView.dequeueReusableCell(withIdentifier: ToggleTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? ToggleTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .textField:
      let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? TextFieldTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .button:
      let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? ButtonTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .pullDown:
      let cell = tableView.dequeueReusableCell(withIdentifier: PullDownMenuCell.identifier, for: indexPath)
      guard let cell = cell as? PullDownMenuCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .step:
      let cell = tableView.dequeueReusableCell(withIdentifier: StepperTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? StepperTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    case .keyboardVisualEffectPreview:
      let cell = tableView.dequeueReusableCell(withIdentifier: KeyboardVisualEffectPreviewTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? KeyboardVisualEffectPreviewTableViewCell else { return cell }
      cell.updateWithSettingItem(setting)
      return cell
    }
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    currentVisualEffectSections[section].title
  }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    currentVisualEffectSections[section].footer
  }
}

private extension UIView {
  func nearestViewController() -> UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let viewController = current as? UIViewController {
        return viewController
      }
      responder = current.next
    }
    return nil
  }
}
