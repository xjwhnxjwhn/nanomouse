//
//  ChineseKeyboardCustomLayoutSettingsView.swift
//
//
//  Created by OpenAI on 2026/5/11.
//

import HamsterKeyboardKit
import HamsterKit
import UIKit

final class ChineseKeyboardCustomLayoutSettingsView: UIView {
  private struct Slot {
    let id: String
  }

  private var profiles: [ChineseKeyboardLayoutProfile] = []
  private var activeProfileID: String?
  private var slotButtons: [UIButton] = []
  private var draggingButton: UIButton?
  private var dragSnapshot: UIView?
  private var previewKeyboardView: UIView?
  private var previewKeyboardConstraints: [NSLayoutConstraint] = []
  private var previewContainerHeightConstraint: NSLayoutConstraint?

  private lazy var previewKeyboardContext: KeyboardContext = {
    let context = KeyboardContext()
    context.hamsterConfiguration = HamsterAppDependencyContainer.shared.configuration
    context.screenSize = UIScreen.main.bounds.size
    context.traitCollection = traitCollection
    context.needsInputModeSwitchKey = false
    context.setKeyboardType(.chinese(.lowercased))
    return context
  }()

  private lazy var previewRimeContext = RimeContext()

  private lazy var previewInputSetProvider = StandardInputSetProvider(
    keyboardContext: previewKeyboardContext,
    rimeContext: previewRimeContext
  )

  private lazy var previewLayoutProvider = StandardKeyboardLayoutProvider(
    keyboardContext: previewKeyboardContext,
    inputSetProvider: previewInputSetProvider
  )

  private lazy var previewAppearance = StandardKeyboardAppearance(keyboardContext: previewKeyboardContext)

  private lazy var previewFeedbackHandler = StandardKeyboardFeedbackHandler(
    settings: KeyboardFeedbackSettings(
      audioConfiguration: .noFeedback,
      hapticConfiguration: .noFeedback
    )
  )

  private lazy var previewActionHandler = StandardKeyboardActionHandler(
    controller: nil,
    keyboardContext: previewKeyboardContext,
    rimeContext: previewRimeContext,
    keyboardBehavior: StandardKeyboardBehavior(keyboardContext: previewKeyboardContext),
    autocompleteContext: AutocompleteContext(),
    keyboardFeedbackHandler: previewFeedbackHandler,
    spaceDragGestureHandler: SpaceCursorDragGestureHandler(
      feedbackHandler: previewFeedbackHandler,
      action: { _ in }
    )
  )

  private lazy var scrollView: UIScrollView = {
    let view = UIScrollView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.alwaysBounceVertical = true
    return view
  }()

  private lazy var contentStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 14
    stack.isLayoutMarginsRelativeArrangement = true
    stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16)
    return stack
  }()

  private lazy var profileControl: UISegmentedControl = {
    let control = UISegmentedControl()
    control.addTarget(self, action: #selector(profileChanged), for: .valueChanged)
    return control
  }()

  private lazy var oneHandControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ChineseKeyboardOneHandMode.allCases.map(\.title))
    control.selectedSegmentIndex = ChineseKeyboardOneHandMode.allCases.firstIndex(of: UserDefaults.hamster.chineseKeyboardOneHandMode) ?? 0
    control.addTarget(self, action: #selector(oneHandModeChanged), for: .valueChanged)
    return control
  }()

  private lazy var previewContainer: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = false
    return view
  }()

  private lazy var previewOverlayView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    return view
  }()

  private lazy var horizontalGapSlider = makeSlider(
    value: UserDefaults.hamster.chineseKeyboardHorizontalGap,
    action: #selector(horizontalGapChanged(_:))
  )

  private lazy var verticalGapSlider = makeSlider(
    value: UserDefaults.hamster.chineseKeyboardVerticalGap,
    action: #selector(verticalGapChanged(_:))
  )

  private lazy var keyHeightSlider = makeSlider(
    value: UserDefaults.hamster.chineseKeyboardKeyHeightScale,
    minimum: 0.82,
    maximum: 1.22,
    action: #selector(keyHeightChanged(_:))
  )

  private lazy var borderWidthSlider = makeSlider(
    value: UserDefaults.hamster.chineseKeyboardBorderWidth,
    minimum: 0,
    maximum: 4,
    action: #selector(borderWidthChanged(_:))
  )

  private lazy var cornerRadiusSlider = makeSlider(
    value: UserDefaults.hamster.chineseKeyboardCornerRadius,
    minimum: 2,
    maximum: 18,
    action: #selector(cornerRadiusChanged(_:))
  )

  private lazy var backgroundColorWell = makeColorWell(
    title: "背景",
    hex: UserDefaults.hamster.chineseKeyboardBackgroundColorHex,
    action: #selector(backgroundColorChanged(_:))
  )

  private lazy var keyBackgroundColorWell = makeColorWell(
    title: "键帽",
    hex: UserDefaults.hamster.chineseKeyboardKeyBackgroundColorHex,
    action: #selector(keyBackgroundColorChanged(_:))
  )

  private lazy var keyTextColorWell = makeColorWell(
    title: "文字",
    hex: UserDefaults.hamster.chineseKeyboardKeyTextColorHex,
    action: #selector(keyTextColorChanged(_:))
  )

  private lazy var keyBorderColorWell = makeColorWell(
    title: "边框",
    hex: UserDefaults.hamster.chineseKeyboardKeyBorderColorHex,
    action: #selector(keyBorderColorChanged(_:))
  )

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .secondarySystemBackground
    setupView()
    loadProfiles()
    rebuildProfileControl()
    rebuildKeyboard()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    addSubview(scrollView)
    scrollView.addSubview(contentStack)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
    ])

    let title = UILabel()
    title.text = "拖动按键交换位置，格子大小固定，保存后立即用于中文 26 键。"
    title.numberOfLines = 0
    title.font = .preferredFont(forTextStyle: .footnote)
    title.textColor = .secondaryLabel
    contentStack.addArrangedSubview(title)
    contentStack.addArrangedSubview(profileControl)
    contentStack.addArrangedSubview(makeButtonRow())
    contentStack.addArrangedSubview(oneHandControl)
    contentStack.addArrangedSubview(makeSliderRow(title: "左右间隔", slider: horizontalGapSlider))
    contentStack.addArrangedSubview(makeSliderRow(title: "上下间隔", slider: verticalGapSlider))
    contentStack.addArrangedSubview(makeSliderRow(title: "键帽高度", slider: keyHeightSlider))
    contentStack.addArrangedSubview(makeSliderRow(title: "边框宽度", slider: borderWidthSlider))
    contentStack.addArrangedSubview(makeSliderRow(title: "圆角", slider: cornerRadiusSlider))
    contentStack.addArrangedSubview(makeColorRow())
    contentStack.addArrangedSubview(previewContainer)
    let heightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: 220)
    heightConstraint.isActive = true
    previewContainerHeightConstraint = heightConstraint
  }

  private func makeButtonRow() -> UIStackView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 10
    stack.distribution = .fillEqually
    let newButton = makeActionButton(title: "新建方案", action: #selector(createProfile))
    let saveButton = makeActionButton(title: "保存", action: #selector(saveCurrentProfile))
    let resetButton = makeActionButton(title: "恢复默认", action: #selector(resetCurrentProfile))
    stack.addArrangedSubview(newButton)
    stack.addArrangedSubview(saveButton)
    stack.addArrangedSubview(resetButton)
    return stack
  }

  private func makeActionButton(title: String, action: Selector) -> UIButton {
    var config = UIButton.Configuration.tinted()
    config.title = title
    let button = UIButton(configuration: config)
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func makeSlider(value: Double, minimum: Float = 2, maximum: Float = 14, action: Selector) -> UISlider {
    let slider = UISlider()
    slider.minimumValue = minimum
    slider.maximumValue = maximum
    slider.value = Float(value)
    slider.addTarget(self, action: action, for: .valueChanged)
    return slider
  }

  private func makeSliderRow(title: String, slider: UISlider) -> UIStackView {
    let label = UILabel()
    label.text = title
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.widthAnchor.constraint(equalToConstant: 72).isActive = true
    let stack = UIStackView(arrangedSubviews: [label, slider])
    stack.axis = .horizontal
    stack.spacing = 10
    stack.alignment = .center
    return stack
  }

  private func makeColorWell(title: String, hex: String?, action: Selector) -> UIColorWell {
    let well = UIColorWell()
    well.title = title
    well.selectedColor = hex?.keyboardUIColor
    well.addTarget(self, action: action, for: .valueChanged)
    return well
  }

  private func makeColorRow() -> UIStackView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 14
    stack.distribution = .fillEqually
    [
      ("背景", backgroundColorWell),
      ("键帽", keyBackgroundColorWell),
      ("文字", keyTextColorWell),
      ("边框", keyBorderColorWell)
    ].forEach { title, well in
      let container = UIStackView(arrangedSubviews: [label(title), well])
      container.axis = .vertical
      container.spacing = 6
      container.alignment = .center
      stack.addArrangedSubview(container)
    }
    return stack
  }

  private func label(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: .caption1)
    label.textColor = .secondaryLabel
    return label
  }

  private func loadProfiles() {
    profiles = UserDefaults.hamster.chineseKeyboardLayoutProfiles
    if profiles.isEmpty {
      profiles = [ChineseKeyboardLayoutProfile(name: "默认", mapping: defaultMapping())]
    }
    activeProfileID = UserDefaults.hamster.activeChineseKeyboardLayoutProfileID ?? profiles.first?.id
    UserDefaults.hamster.chineseKeyboardLayoutProfiles = profiles
    UserDefaults.hamster.activeChineseKeyboardLayoutProfileID = activeProfileID
  }

  private func rebuildProfileControl() {
    profileControl.removeAllSegments()
    for (index, profile) in profiles.enumerated() {
      profileControl.insertSegment(withTitle: profile.name, at: index, animated: false)
      if profile.id == activeProfileID {
        profileControl.selectedSegmentIndex = index
      }
    }
    if profileControl.selectedSegmentIndex == UISegmentedControl.noSegment, !profiles.isEmpty {
      profileControl.selectedSegmentIndex = 0
      activeProfileID = profiles[0].id
    }
  }

  private func rebuildKeyboard() {
    previewKeyboardContext.hamsterConfiguration = HamsterAppDependencyContainer.shared.configuration
    previewKeyboardContext.screenSize = UIScreen.main.bounds.size
    previewKeyboardContext.traitCollection = traitCollection
    previewKeyboardContext.setKeyboardType(.chinese(.lowercased))
    previewContainerHeightConstraint?.constant = previewKeyboardHeight()
    previewContainer.backgroundColor = UserDefaults.hamster.chineseKeyboardBackgroundColorHex?.keyboardUIColor ?? .clear

    NSLayoutConstraint.deactivate(previewKeyboardConstraints)
    previewKeyboardConstraints.removeAll()
    previewKeyboardView?.removeFromSuperview()
    previewOverlayView.removeFromSuperview()
    slotButtons.removeAll()

    let keyboard = StanderSystemKeyboard(
      keyboardLayoutProvider: previewLayoutProvider,
      appearance: previewAppearance,
      actionHandler: previewActionHandler,
      keyboardContext: previewKeyboardContext,
      rimeContext: previewRimeContext,
      calloutContext: .disabled
    )
    keyboard.translatesAutoresizingMaskIntoConstraints = false
    keyboard.isUserInteractionEnabled = false
    previewContainer.addSubview(keyboard)
    previewContainer.addSubview(previewOverlayView)
    previewKeyboardConstraints = [
      keyboard.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      keyboard.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      keyboard.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      keyboard.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
      previewOverlayView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      previewOverlayView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      previewOverlayView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      previewOverlayView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
    ]
    NSLayoutConstraint.activate(previewKeyboardConstraints)
    previewKeyboardView = keyboard

    setNeedsLayout()
    layoutIfNeeded()
    DispatchQueue.main.async { [weak self] in
      self?.rebuildDragOverlay()
    }
  }

  private func defaultMapping() -> [String: String] {
    Dictionary(uniqueKeysWithValues: defaultSlotRows().flatMap { $0 }.map { ($0.id, $0.id) })
  }

  private func previewKeyboardHeight() -> CGFloat {
    let rows = previewLayoutProvider.keyboardLayout(for: previewKeyboardContext).itemRows
    let height = rows.reduce(CGFloat(0)) { partial, row in
      partial + (row.map(\.size.height).max() ?? 0)
    }
    return max(180, height)
  }

  private func currentProfile() -> ChineseKeyboardLayoutProfile? {
    profiles.first { $0.id == activeProfileID }
  }

  private func currentProfileIndex() -> Int? {
    profiles.firstIndex { $0.id == activeProfileID }
  }

  private func title(for actionID: String) -> String {
    if actionID.hasPrefix("character("), actionID.hasSuffix(")") {
      let start = actionID.index(actionID.startIndex, offsetBy: "character(".count)
      let end = actionID.index(before: actionID.endIndex)
      return String(actionID[start ..< end]).uppercased()
    }
    switch actionID {
    case "shift": return "⇧"
    case "backspace": return "⌫"
    case "space": return "空格"
    case "enter": return "↵"
    case "nextKeyboard": return "🌐"
    case "keyboardType(chineseNumeric)": return "123"
    case "keyboardType(chineseSymbolic)": return "#+="
    case "keyboardType(alphabetic)": return "ABC"
    default: return actionID
    }
  }

  @objc private func profileChanged() {
    guard profileControl.selectedSegmentIndex >= 0, profileControl.selectedSegmentIndex < profiles.count else { return }
    activeProfileID = profiles[profileControl.selectedSegmentIndex].id
    UserDefaults.hamster.activeChineseKeyboardLayoutProfileID = activeProfileID
    rebuildKeyboard()
  }

  @objc private func createProfile() {
    let profile = ChineseKeyboardLayoutProfile(name: "方案\(profiles.count + 1)", mapping: currentProfile()?.mapping ?? defaultMapping())
    profiles.append(profile)
    activeProfileID = profile.id
    persistProfiles()
    rebuildProfileControl()
    rebuildKeyboard()
  }

  @objc private func saveCurrentProfile() {
    persistProfiles()
  }

  @objc private func resetCurrentProfile() {
    guard let index = currentProfileIndex() else { return }
    profiles[index].mapping = defaultMapping()
    resetAppearanceSettings()
    persistProfiles()
    rebuildKeyboard()
  }

  @objc private func oneHandModeChanged() {
    let modes = ChineseKeyboardOneHandMode.allCases
    guard oneHandControl.selectedSegmentIndex >= 0, oneHandControl.selectedSegmentIndex < modes.count else { return }
    UserDefaults.hamster.chineseKeyboardOneHandMode = modes[oneHandControl.selectedSegmentIndex]
    rebuildKeyboard()
  }

  @objc private func horizontalGapChanged(_ sender: UISlider) {
    UserDefaults.hamster.chineseKeyboardHorizontalGap = Double(sender.value)
    rebuildKeyboard()
  }

  @objc private func verticalGapChanged(_ sender: UISlider) {
    UserDefaults.hamster.chineseKeyboardVerticalGap = Double(sender.value)
    rebuildKeyboard()
  }

  @objc private func keyHeightChanged(_ sender: UISlider) {
    UserDefaults.hamster.chineseKeyboardKeyHeightScale = Double(sender.value)
    rebuildKeyboard()
  }

  @objc private func borderWidthChanged(_ sender: UISlider) {
    UserDefaults.hamster.chineseKeyboardBorderWidth = Double(sender.value)
    rebuildKeyboard()
  }

  @objc private func cornerRadiusChanged(_ sender: UISlider) {
    UserDefaults.hamster.chineseKeyboardCornerRadius = Double(sender.value)
    rebuildKeyboard()
  }

  @objc private func backgroundColorChanged(_ sender: UIColorWell) {
    UserDefaults.hamster.chineseKeyboardBackgroundColorHex = sender.selectedColor?.hexString
    rebuildKeyboard()
  }

  @objc private func keyBackgroundColorChanged(_ sender: UIColorWell) {
    UserDefaults.hamster.chineseKeyboardKeyBackgroundColorHex = sender.selectedColor?.hexString
    rebuildKeyboard()
  }

  @objc private func keyTextColorChanged(_ sender: UIColorWell) {
    UserDefaults.hamster.chineseKeyboardKeyTextColorHex = sender.selectedColor?.hexString
    rebuildKeyboard()
  }

  @objc private func keyBorderColorChanged(_ sender: UIColorWell) {
    UserDefaults.hamster.chineseKeyboardKeyBorderColorHex = sender.selectedColor?.hexString
    rebuildKeyboard()
  }

  private func resetAppearanceSettings() {
    UserDefaults.hamster.chineseKeyboardOneHandMode = .off
    UserDefaults.hamster.chineseKeyboardHorizontalGap = 6
    UserDefaults.hamster.chineseKeyboardVerticalGap = 6
    UserDefaults.hamster.chineseKeyboardKeyHeightScale = 1
    UserDefaults.hamster.chineseKeyboardBorderWidth = 0
    UserDefaults.hamster.chineseKeyboardCornerRadius = 5
    UserDefaults.hamster.chineseKeyboardBackgroundColorHex = nil
    UserDefaults.hamster.chineseKeyboardKeyBackgroundColorHex = nil
    UserDefaults.hamster.chineseKeyboardKeyTextColorHex = nil
    UserDefaults.hamster.chineseKeyboardKeyBorderColorHex = nil
    oneHandControl.selectedSegmentIndex = 0
    horizontalGapSlider.value = 6
    verticalGapSlider.value = 6
    keyHeightSlider.value = 1
    borderWidthSlider.value = 0
    cornerRadiusSlider.value = 5
    backgroundColorWell.selectedColor = nil
    keyBackgroundColorWell.selectedColor = nil
    keyTextColorWell.selectedColor = nil
    keyBorderColorWell.selectedColor = nil
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
    rebuildKeyboard()
  }

  private func defaultSlotRows() -> [[Slot]] {
    let activeProfileID = UserDefaults.hamster.activeChineseKeyboardLayoutProfileID
    UserDefaults.hamster.activeChineseKeyboardLayoutProfileID = nil
    defer {
      UserDefaults.hamster.activeChineseKeyboardLayoutProfileID = activeProfileID
    }
    return previewLayoutProvider.keyboardLayout(for: previewKeyboardContext).itemRows.map { row in
      row.compactMap { item in
        guard isCustomizableSlotAction(item.action) else { return nil }
        return Slot(id: item.action.yamlString)
      }
    }
  }

  private func isCustomizableSlotAction(_ action: KeyboardAction) -> Bool {
    switch action {
    case .character, .symbol, .shift, .backspace, .primary, .space, .keyboardType, .nextKeyboard, .shortCommand:
      return true
    default:
      return false
    }
  }

  private func rebuildDragOverlay() {
    previewOverlayView.subviews.forEach { $0.removeFromSuperview() }
    slotButtons.removeAll()
    previewContainer.layoutIfNeeded()
    previewKeyboardView?.layoutIfNeeded()
    previewOverlayView.layoutIfNeeded()
    guard let previewKeyboardView else { return }
    let slotIDs = defaultSlotRows().flatMap { $0.map(\.id) }
    let keyViews = previewKeyboardView.subviews
      .filter { !$0.isHidden && $0.bounds.width > 1 && $0.bounds.height > 1 }
    for (slotID, keyView) in zip(slotIDs, keyViews) {
      let button = UIButton(type: .custom)
      button.frame = keyView.convert(keyView.bounds, to: previewOverlayView)
      button.backgroundColor = .clear
      button.accessibilityIdentifier = slotID
      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      button.addGestureRecognizer(pan)
      previewOverlayView.addSubview(button)
      slotButtons.append(button)
    }
  }

  @objc private func handlePan(_ sender: UIPanGestureRecognizer) {
    guard let source = sender.view as? UIButton else { return }
    switch sender.state {
    case .began:
      draggingButton = source
      dragSnapshot = source.snapshotView(afterScreenUpdates: false)
      if let dragSnapshot {
        dragSnapshot.frame = source.convert(source.bounds, to: self)
        dragSnapshot.alpha = 0.85
        addSubview(dragSnapshot)
        source.alpha = 0.35
      }
    case .changed:
      let translation = sender.translation(in: self)
      let sourceCenter = source.superview?.convert(source.center, to: self) ?? source.center
      dragSnapshot?.center = CGPoint(x: sourceCenter.x + translation.x, y: sourceCenter.y + translation.y)
    case .ended, .cancelled, .failed:
      defer {
        source.alpha = 1
        dragSnapshot?.removeFromSuperview()
        dragSnapshot = nil
        draggingButton = nil
      }
      guard let target = targetButton(at: sender.location(in: self)),
            target !== source
      else {
        return
      }
      swap(sourceSlotID: source.accessibilityIdentifier, targetSlotID: target.accessibilityIdentifier)
    default:
      break
    }
  }

  private func targetButton(at point: CGPoint) -> UIButton? {
    slotButtons.first { button in
      let frame = button.convert(button.bounds, to: self)
      return frame.contains(point)
    }
  }

  private func swap(sourceSlotID: String?, targetSlotID: String?) {
    guard let sourceSlotID, let targetSlotID, let index = currentProfileIndex() else { return }
    var mapping = profiles[index].mapping
    let sourceValue = mapping[sourceSlotID] ?? sourceSlotID
    let targetValue = mapping[targetSlotID] ?? targetSlotID
    mapping[sourceSlotID] = targetValue
    mapping[targetSlotID] = sourceValue
    profiles[index].mapping = mapping
    persistProfiles()
    rebuildKeyboard()
  }

  private func persistProfiles() {
    UserDefaults.hamster.chineseKeyboardLayoutProfiles = profiles
    UserDefaults.hamster.activeChineseKeyboardLayoutProfileID = activeProfileID
  }
}

private extension String {
  var keyboardUIColor: UIColor? {
    var value = trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6 || value.count == 8, let hex = UInt64(value, radix: 16) else { return nil }
    let hasAlpha = value.count == 8
    let alpha = hasAlpha ? CGFloat((hex & 0xff00_0000) >> 24) / 255 : 1
    let red = CGFloat((hex & (hasAlpha ? 0x00ff_0000 : 0xff_0000)) >> 16) / 255
    let green = CGFloat((hex & (hasAlpha ? 0x0000_ff00 : 0x00_ff00)) >> 8) / 255
    let blue = CGFloat(hex & 0x0000_00ff) / 255
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}

private extension UIColor {
  var hexString: String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return String(
      format: "#%02X%02X%02X%02X",
      Int(round(alpha * 255)),
      Int(round(red * 255)),
      Int(round(green * 255)),
      Int(round(blue * 255))
    )
  }
}
