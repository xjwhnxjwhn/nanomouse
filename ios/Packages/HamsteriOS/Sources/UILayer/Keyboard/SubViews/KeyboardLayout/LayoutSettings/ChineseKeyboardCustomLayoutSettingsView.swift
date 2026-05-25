//
//  ChineseKeyboardCustomLayoutSettingsView.swift
//
//
//  Created by OpenAI on 2026/5/11.
//

import HamsterKeyboardKit
import HamsterKit
import PhotosUI
import ProgressHUD
import UIKit

final class ChineseKeyboardCustomLayoutSettingsView: UIView, PHPickerViewControllerDelegate {
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
  private var selectedAppearanceActionID: String?
  private weak var selectedAppearanceButton: UIButton?
  private var isPositionEditing = false
  private let usesInternalScrollView: Bool
  private var lastReportedContentHeight: CGFloat = 0
  private let previewKeyboardBoardPadding: CGFloat = 10
  var contentHeightDidChange: ((CGFloat) -> Void)?
  var visualEffectPreviewUserInterfaceStyle: UIUserInterfaceStyle? {
    didSet {
      guard oldValue != visualEffectPreviewUserInterfaceStyle else { return }
      guard window != nil else { return }
      rebuildKeyboard()
    }
  }

  private lazy var previewKeyboardContext: KeyboardContext = {
    let context = KeyboardContext()
    context.hamsterConfiguration = HamsterAppDependencyContainer.shared.configuration
    context.screenSize = UIScreen.main.bounds.size
    context.traitCollection = previewTraitCollection()
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

  private lazy var previewActionHandler = PreviewKeyboardActionHandler()

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

  private lazy var previewIconBackgroundView: UIImageView = {
    let imageView = UIImageView(image: UIImage(named: "Hamster") ?? UIImage(named: "NanomouseLaunch"))
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.layer.cornerCurve = .continuous
    imageView.layer.cornerRadius = 14
    return imageView
  }()

  private lazy var previewIconContrastView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isUserInteractionEnabled = false
    return view
  }()

  private lazy var previewKeyboardBackgroundEffectView: UIVisualEffectView = {
    let view = UIVisualEffectView(effect: nil)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = true
    view.layer.cornerCurve = .continuous
    view.layer.cornerRadius = 24
    view.layer.shadowOffset = CGSize(width: 0, height: 6)
    view.layer.shadowRadius = 16
    return view
  }()

  private let previewKeyboardBackgroundTintView = UIView(frame: .zero)

  private lazy var previewOverlayView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.isHidden = true
    view.isUserInteractionEnabled = false
    return view
  }()

  private lazy var positionEditButton: UIButton = {
    var config = UIButton.Configuration.tinted()
    config.title = "自定义键帽位置"
    let button = UIButton(configuration: config)
    button.addTarget(self, action: #selector(togglePositionEditing), for: .touchUpInside)
    return button
  }()

  private lazy var rowLetterFields: [UITextField] = (0 ..< 3).map { rowIndex in
    let field = UITextField(frame: .zero)
    field.borderStyle = .roundedRect
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.clearButtonMode = .whileEditing
    field.placeholder = ["第一行", "第二行", "第三行"][rowIndex]
    field.tag = rowIndex
    field.addTarget(self, action: #selector(letterRowChanged(_:)), for: .editingChanged)
    return field
  }

  private lazy var positionFieldsStack: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 8
    stack.isHidden = true
    for (index, field) in rowLetterFields.enumerated() {
      let label = UILabel()
      label.text = "第 \(index + 1) 行"
      label.font = .preferredFont(forTextStyle: .caption1)
      label.textColor = .secondaryLabel
      label.widthAnchor.constraint(equalToConstant: 54).isActive = true
      let row = UIStackView(arrangedSubviews: [label, field])
      row.axis = .horizontal
      row.alignment = .center
      row.spacing = 8
      stack.addArrangedSubview(row)
    }
    return stack
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
    minimum: 0,
    maximum: 32,
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

  private lazy var selectedKeyLabel: UILabel = {
    let label = UILabel()
    label.text = "点按下方预览中的按键，可单独调整该键外观。"
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = .secondaryLabel
    return label
  }()

  private lazy var selectedKeyBackgroundColorWell = makeColorWell(
    title: "单键背景",
    hex: nil,
    action: #selector(selectedKeyBackgroundColorChanged(_:))
  )

  private lazy var selectedKeyTextColorWell = makeColorWell(
    title: "单键文字",
    hex: nil,
    action: #selector(selectedKeyTextColorChanged(_:))
  )

  private lazy var selectedKeyBorderColorWell = makeColorWell(
    title: "单键边框",
    hex: nil,
    action: #selector(selectedKeyBorderColorChanged(_:))
  )

  private lazy var selectedKeyImagePreview: UIImageView = {
    let imageView = UIImageView(frame: .zero)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.layer.cornerCurve = .continuous
    imageView.layer.cornerRadius = 8
    imageView.layer.borderWidth = 0.5
    imageView.layer.borderColor = UIColor.separator.cgColor
    imageView.backgroundColor = .tertiarySystemFill
    imageView.widthAnchor.constraint(equalToConstant: 54).isActive = true
    imageView.heightAnchor.constraint(equalToConstant: 38).isActive = true
    return imageView
  }()

  init(frame: CGRect = .zero, usesInternalScrollView: Bool = true) {
    self.usesInternalScrollView = usesInternalScrollView
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
    if usesInternalScrollView {
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
    } else {
      addSubview(contentStack)
      NSLayoutConstraint.activate([
        contentStack.topAnchor.constraint(equalTo: topAnchor),
        contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
        contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
        contentStack.bottomAnchor.constraint(equalTo: bottomAnchor)
      ])
    }

    let title = UILabel()
    title.text = "拖动按键交换位置；点按按键可单独设置背景、文字、边框或背景图。保存后立即用于中文 26 键。"
    title.numberOfLines = 0
    title.font = .preferredFont(forTextStyle: .footnote)
    title.textColor = .secondaryLabel
    contentStack.addArrangedSubview(title)
    contentStack.addArrangedSubview(profileControl)
    contentStack.addArrangedSubview(makeButtonRow())
    contentStack.addArrangedSubview(oneHandControl)
    contentStack.addArrangedSubview(makeInfoLabel("单手键盘可在真实键盘的繁简/语言区域左右滑切换左手、双手、右手；这里的预览用于确认单手布局形状和按键位置。"))
    contentStack.addArrangedSubview(makeSliderRow(title: "左右间隔", slider: horizontalGapSlider))
    contentStack.addArrangedSubview(makeSliderRow(title: "上下间隔", slider: verticalGapSlider))
    contentStack.addArrangedSubview(makeSliderRow(title: "键帽高度", slider: keyHeightSlider))
    contentStack.addArrangedSubview(makeSliderRow(title: "边框宽度", slider: borderWidthSlider))
    contentStack.addArrangedSubview(makeSliderRow(title: "按键形状", slider: cornerRadiusSlider))
    contentStack.addArrangedSubview(makeColorRow())
    contentStack.addArrangedSubview(makePositionEditorView())
    contentStack.addArrangedSubview(makeSelectedKeyAppearanceView())
    contentStack.addArrangedSubview(previewContainer)
    previewContainer.addSubview(previewIconBackgroundView)
    previewContainer.addSubview(previewKeyboardBackgroundEffectView)
    previewContainer.addSubview(previewIconContrastView)
    previewKeyboardBackgroundEffectView.contentView.addSubview(previewKeyboardBackgroundTintView)
    NSLayoutConstraint.activate([
      previewIconBackgroundView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      previewIconBackgroundView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      previewIconBackgroundView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      previewIconBackgroundView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

      previewIconContrastView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      previewIconContrastView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      previewIconContrastView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      previewIconContrastView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

      previewKeyboardBackgroundEffectView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      previewKeyboardBackgroundEffectView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      previewKeyboardBackgroundEffectView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      previewKeyboardBackgroundEffectView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
    ])
    let heightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: 220)
    heightConstraint.isActive = true
    previewContainerHeightConstraint = heightConstraint
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    previewKeyboardBackgroundTintView.frame = previewKeyboardBackgroundEffectView.contentView.bounds
    reportContentHeightIfNeeded()
  }

  func preferredContentHeight(width: CGFloat) -> CGFloat {
    let targetWidth = max(1, width)
    let targetSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
    return contentStack.systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
  }

  private func reportContentHeightIfNeeded() {
    guard !usesInternalScrollView, bounds.width > 1 else { return }
    let height = ceil(preferredContentHeight(width: bounds.width))
    guard abs(height - lastReportedContentHeight) > 1 else { return }
    lastReportedContentHeight = height
    contentHeightDidChange?(height)
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

  private func makeInfoLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: .caption1)
    label.textColor = .secondaryLabel
    return label
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

  private func makeSelectedKeyAppearanceView() -> UIStackView {
    let colorStack = UIStackView()
    colorStack.axis = .horizontal
    colorStack.spacing = 14
    colorStack.distribution = .fillEqually
    [
      ("背景", selectedKeyBackgroundColorWell),
      ("文字", selectedKeyTextColorWell),
      ("边框", selectedKeyBorderColorWell)
    ].forEach { title, well in
      let container = UIStackView(arrangedSubviews: [label(title), well])
      container.axis = .vertical
      container.spacing = 6
      container.alignment = .center
      colorStack.addArrangedSubview(container)
    }

    let imageButton = makeActionButton(title: "选择背景图", action: #selector(selectSelectedKeyBackgroundImage))
    let clearButton = makeActionButton(title: "清除单键", action: #selector(clearSelectedKeyAppearance))
    let imageStack = UIStackView(arrangedSubviews: [selectedKeyImagePreview, imageButton, clearButton])
    imageStack.axis = .horizontal
    imageStack.spacing = 10
    imageStack.alignment = .center
    imageStack.distribution = .fill

    let stack = UIStackView(arrangedSubviews: [selectedKeyLabel, colorStack, imageStack])
    stack.axis = .vertical
    stack.spacing = 10
    stack.isLayoutMarginsRelativeArrangement = true
    stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12)
    stack.backgroundColor = .tertiarySystemGroupedBackground
    stack.layer.cornerRadius = 10
    stack.layer.cornerCurve = .continuous
    return stack
  }

  private func makePositionEditorView() -> UIStackView {
    let title = makeInfoLabel("默认预览可点按、长按查看按键气泡；进入位置编辑后，按键会抖动，可拖动换位，也可直接输入三行字母。")
    let stack = UIStackView(arrangedSubviews: [title, positionEditButton, positionFieldsStack])
    stack.axis = .vertical
    stack.spacing = 10
    stack.isLayoutMarginsRelativeArrangement = true
    stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12)
    stack.backgroundColor = .tertiarySystemGroupedBackground
    stack.layer.cornerRadius = 10
    stack.layer.cornerCurve = .continuous
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
    let style = previewUserInterfaceStyle()
    previewKeyboardContext.hamsterConfiguration = HamsterAppDependencyContainer.shared.configuration
    previewKeyboardContext.screenSize = UIScreen.main.bounds.size
    previewKeyboardContext.traitCollection = previewTraitCollection()
    previewKeyboardContext.setKeyboardType(.chinese(.lowercased))
    [previewContainer, previewKeyboardBackgroundEffectView].forEach {
      $0.overrideUserInterfaceStyle = style
    }
    previewContainerHeightConstraint?.constant = previewKeyboardHeight() + previewKeyboardBoardPadding * 2
    let hasCustomBackgroundColor = UserDefaults.hamster.chineseKeyboardBackgroundColorHex?.isEmpty == false
    previewContainer.backgroundColor = UserDefaults.hamster.chineseKeyboardBackgroundColorHex?.keyboardUIColor ?? .clear
    previewIconBackgroundView.alpha = hasCustomBackgroundColor ? 0.32 : 1
    previewIconContrastView.backgroundColor = hasCustomBackgroundColor
      ? .clear
      : (style == .dark ? UIColor.black.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.24))
    updatePreviewKeyboardBackground()

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
    keyboard.overrideUserInterfaceStyle = style
    keyboard.isUserInteractionEnabled = !isPositionEditing
    previewContainer.insertSubview(keyboard, aboveSubview: previewIconContrastView)
    previewContainer.addSubview(previewOverlayView)
    let padding = previewKeyboardBoardPadding
    previewKeyboardConstraints = [
      keyboard.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: padding),
      keyboard.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: padding),
      keyboard.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -padding),
      keyboard.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -padding),
      previewOverlayView.topAnchor.constraint(equalTo: keyboard.topAnchor),
      previewOverlayView.leadingAnchor.constraint(equalTo: keyboard.leadingAnchor),
      previewOverlayView.trailingAnchor.constraint(equalTo: keyboard.trailingAnchor),
      previewOverlayView.bottomAnchor.constraint(equalTo: keyboard.bottomAnchor)
    ]
    NSLayoutConstraint.activate(previewKeyboardConstraints)
    previewKeyboardView = keyboard

    setNeedsLayout()
    layoutIfNeeded()
    DispatchQueue.main.async { [weak self] in
      self?.rebuildDragOverlay()
      self?.reportContentHeightIfNeeded()
    }
  }

  func reloadPreview() {
    rebuildKeyboard()
  }

  private func updatePreviewKeyboardBackground() {
    let visualEffect = KeyboardVisualEffectConfiguration()
    let hasCustomBackgroundColor = UserDefaults.hamster.chineseKeyboardBackgroundColorHex?.isEmpty == false
    let style = previewUserInterfaceStyle()
    previewKeyboardBackgroundEffectView.overrideUserInterfaceStyle = style
    let shouldRenderGlass = !hasCustomBackgroundColor && KeyboardLiquidGlass.shouldRenderVisualSurface(
      configuration: visualEffect,
      target: .keyboardBackground,
      userInterfaceStyle: style
    )
    previewKeyboardBackgroundEffectView.isHidden = !shouldRenderGlass
    guard shouldRenderGlass else {
      previewKeyboardBackgroundEffectView.effect = nil
      previewKeyboardBackgroundTintView.backgroundColor = .clear
      return
    }
    previewKeyboardBackgroundEffectView.effect = KeyboardLiquidGlass.effect(
      userInterfaceStyle: style,
      configuration: visualEffect,
      target: .keyboardBackground
    )
    previewKeyboardBackgroundTintView.backgroundColor = KeyboardLiquidGlass.tintColor(
      userInterfaceStyle: style,
      configuration: visualEffect,
      target: .keyboardBackground
    )
    previewKeyboardBackgroundEffectView.layer.shadowColor = UIColor.black.cgColor
    previewKeyboardBackgroundEffectView.layer.shadowOpacity = KeyboardLiquidGlass.shadowOpacity(
      userInterfaceStyle: style,
      configuration: visualEffect,
      target: .keyboardBackground
    )
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
    UserDefaults.hamster.chineseKeyboardKeyAppearanceOverrides = [:]
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
    selectedAppearanceActionID = nil
    reloadSelectedKeyAppearanceControls()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard visualEffectPreviewUserInterfaceStyle == nil else { return }
    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
    rebuildKeyboard()
  }

  private func previewUserInterfaceStyle() -> UIUserInterfaceStyle {
    visualEffectPreviewUserInterfaceStyle ?? (traitCollection.userInterfaceStyle == .dark ? .dark : .light)
  }

  private func previewTraitCollection() -> UITraitCollection {
    guard let visualEffectPreviewUserInterfaceStyle else { return traitCollection }
    return UITraitCollection(traitsFrom: [
      traitCollection,
      UITraitCollection(userInterfaceStyle: visualEffectPreviewUserInterfaceStyle)
    ])
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
    previewOverlayView.isHidden = !isPositionEditing
    previewOverlayView.isUserInteractionEnabled = isPositionEditing
    previewContainer.layoutIfNeeded()
    previewKeyboardView?.layoutIfNeeded()
    previewKeyboardView?.isUserInteractionEnabled = !isPositionEditing
    previewOverlayView.layoutIfNeeded()
    guard let previewKeyboardView else { return }
    let slotIDs = defaultSlotRows().flatMap { $0.map(\.id) }
    let actionIDs = currentVisibleActionIDs()
    let keyViews = previewKeyboardView.subviews
      .filter { !$0.isHidden && $0.bounds.width > 1 && $0.bounds.height > 1 }
    for ((slotID, actionID), keyView) in zip(zip(slotIDs, actionIDs), keyViews) {
      let button = UIButton(type: .custom)
      button.frame = keyView.convert(keyView.bounds, to: previewOverlayView)
      button.backgroundColor = .clear
      button.accessibilityIdentifier = slotID
      button.accessibilityValue = actionID
      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      button.addGestureRecognizer(pan)
      let tap = UITapGestureRecognizer(target: self, action: #selector(handleAppearanceTap(_:)))
      button.addGestureRecognizer(tap)
      previewOverlayView.addSubview(button)
      slotButtons.append(button)
    }
    refreshSelectedAppearanceButton()
    updateLetterFieldsFromProfile()
    applyPositionEditingState()
  }

  private func currentVisibleActionIDs() -> [String] {
    previewLayoutProvider.keyboardLayout(for: previewKeyboardContext).itemRows.flatMap { row in
      row.compactMap { item in
        guard isCustomizableSlotAction(item.action) else { return nil }
        return appearanceStorageID(for: item.action.yamlString)
      }
    }
  }

  @objc private func handleAppearanceTap(_ sender: UITapGestureRecognizer) {
    guard sender.state == .ended, let button = sender.view as? UIButton else { return }
    selectAppearanceButton(button)
  }

  private func selectAppearanceButton(_ button: UIButton) {
    guard let actionID = button.accessibilityValue ?? button.accessibilityIdentifier else { return }
    selectedAppearanceActionID = appearanceStorageID(for: actionID)
    selectedAppearanceButton = button
    reloadSelectedKeyAppearanceControls()
    refreshSelectedAppearanceButton()
  }

  private func reloadSelectedKeyAppearanceControls() {
    guard let actionID = selectedAppearanceActionID else {
      selectedKeyLabel.text = "点按下方预览中的按键，可单独调整该键外观。"
      selectedKeyBackgroundColorWell.selectedColor = nil
      selectedKeyTextColorWell.selectedColor = nil
      selectedKeyBorderColorWell.selectedColor = nil
      selectedKeyImagePreview.image = nil
      return
    }

    let appearance = UserDefaults.hamster.chineseKeyboardKeyAppearanceOverrides[actionID] ?? ChineseKeyboardKeyAppearance()
    selectedKeyLabel.text = "正在编辑：\(title(for: actionID))"
    selectedKeyBackgroundColorWell.selectedColor = appearance.backgroundUIColor
    selectedKeyTextColorWell.selectedColor = appearance.textUIColor
    selectedKeyBorderColorWell.selectedColor = appearance.borderUIColor
    if let url = appearance.backgroundImageURL {
      selectedKeyImagePreview.image = UIImage(contentsOfFile: url.path)
    } else {
      selectedKeyImagePreview.image = nil
    }
  }

  private func refreshSelectedAppearanceButton() {
    for button in slotButtons {
      let isSelected = selectedAppearanceActionID != nil &&
        appearanceStorageID(for: button.accessibilityValue ?? button.accessibilityIdentifier ?? "") == selectedAppearanceActionID
      button.layer.borderWidth = isSelected ? 2 : 0
      button.layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
      button.layer.cornerRadius = isSelected ? 8 : 0
    }
  }

  @objc private func togglePositionEditing() {
    isPositionEditing.toggle()
    applyPositionEditingState()
  }

  private func applyPositionEditingState() {
    previewOverlayView.isHidden = !isPositionEditing
    previewOverlayView.isUserInteractionEnabled = isPositionEditing
    previewKeyboardView?.isUserInteractionEnabled = !isPositionEditing
    positionFieldsStack.isHidden = !isPositionEditing
    positionEditButton.configuration?.title = isPositionEditing ? "完成位置编辑" : "自定义键帽位置"
    for button in slotButtons {
      if isPositionEditing {
        startJiggle(button)
      } else {
        button.layer.removeAnimation(forKey: "positionJiggle")
      }
    }
  }

  private func startJiggle(_ button: UIButton) {
    guard button.layer.animation(forKey: "positionJiggle") == nil else { return }
    let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
    animation.values = [-0.018, 0.018, -0.014]
    animation.duration = 0.16
    animation.repeatCount = .infinity
    animation.autoreverses = true
    button.layer.add(animation, forKey: "positionJiggle")
  }

  @objc private func letterRowChanged(_ sender: UITextField) {
    let rowIndex = sender.tag
    let slotRows = defaultSlotRows()
    guard rowIndex >= 0, rowIndex < slotRows.count, let profileIndex = currentProfileIndex() else { return }
    let characterSlots = slotRows[rowIndex].filter { characterText(from: $0.id) != nil }
    let letters = (sender.text ?? "")
      .lowercased()
      .filter { !$0.isWhitespace }
      .map(String.init)
    guard !characterSlots.isEmpty else { return }

    var mapping = profiles[profileIndex].mapping
    for (slot, letter) in zip(characterSlots, letters) {
      mapping[slot.id] = "character(\(letter))"
    }
    profiles[profileIndex].mapping = mapping
    persistProfiles()
    rebuildKeyboard()
  }

  private func updateLetterFieldsFromProfile() {
    let rows = defaultSlotRows()
    for index in rowLetterFields.indices {
      guard index < rows.count else { continue }
      let text = rows[index].compactMap { slot -> String? in
        let actionID = currentProfile()?.mapping[slot.id] ?? slot.id
        return characterText(from: actionID)
      }.joined()
      if rowLetterFields[index].text != text {
        rowLetterFields[index].text = text
      }
    }
  }

  private func characterText(from actionID: String) -> String? {
    guard actionID.hasPrefix("character("), actionID.hasSuffix(")") else { return nil }
    let start = actionID.index(actionID.startIndex, offsetBy: "character(".count)
    let end = actionID.index(before: actionID.endIndex)
    return String(actionID[start ..< end])
  }

  private func updateSelectedKeyAppearance(_ update: (inout ChineseKeyboardKeyAppearance) -> Void) {
    guard let actionID = selectedAppearanceActionID else { return }
    var overrides = UserDefaults.hamster.chineseKeyboardKeyAppearanceOverrides
    var appearance = overrides[actionID] ?? ChineseKeyboardKeyAppearance()
    update(&appearance)
    if appearance.isEmpty {
      overrides.removeValue(forKey: actionID)
    } else {
      overrides[actionID] = appearance
    }
    UserDefaults.hamster.chineseKeyboardKeyAppearanceOverrides = overrides
    reloadSelectedKeyAppearanceControls()
    rebuildKeyboard()
  }

  @objc private func selectedKeyBackgroundColorChanged(_ sender: UIColorWell) {
    updateSelectedKeyAppearance { appearance in
      appearance.backgroundColorHex = sender.selectedColor?.hexString
    }
  }

  @objc private func selectedKeyTextColorChanged(_ sender: UIColorWell) {
    updateSelectedKeyAppearance { appearance in
      appearance.textColorHex = sender.selectedColor?.hexString
    }
  }

  @objc private func selectedKeyBorderColorChanged(_ sender: UIColorWell) {
    updateSelectedKeyAppearance { appearance in
      appearance.borderColorHex = sender.selectedColor?.hexString
    }
  }

  @objc private func selectSelectedKeyBackgroundImage() {
    guard selectedAppearanceActionID != nil else { return }
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    nearestViewController()?.present(picker, animated: true)
  }

  @objc private func clearSelectedKeyAppearance() {
    guard let actionID = selectedAppearanceActionID else { return }
    var overrides = UserDefaults.hamster.chineseKeyboardKeyAppearanceOverrides
    overrides.removeValue(forKey: actionID)
    UserDefaults.hamster.chineseKeyboardKeyAppearanceOverrides = overrides
    reloadSelectedKeyAppearanceControls()
    rebuildKeyboard()
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider,
          provider.canLoadObject(ofClass: UIImage.self)
    else {
      return
    }
    provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
      guard let self, let image = object as? UIImage else { return }
      DispatchQueue.main.async {
        self.saveSelectedKeyBackgroundImage(image)
      }
    }
  }

  private func saveSelectedKeyBackgroundImage(_ image: UIImage) {
    guard selectedAppearanceActionID != nil else { return }
    let relativePath = "KeyboardKeyBackgrounds/\(UUID().uuidString).jpg"
    let directory = FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("KeyboardKeyBackgrounds", isDirectory: true)
    let url = FileManager.appGroupUserDataDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let resizedImage = image.resizedForKeyboardKeyBackground(maxDimension: 720)
      guard let data = resizedImage.jpegData(compressionQuality: 0.84) else { return }
      try data.write(to: url, options: .atomic)
      updateSelectedKeyAppearance { appearance in
        appearance.backgroundImagePath = relativePath
      }
    } catch {
      ProgressHUD.failed("背景图保存失败", interaction: false, delay: 1.5)
    }
  }

  private func appearanceStorageID(for actionID: String) -> String {
    if actionID.hasPrefix("character(") || actionID.hasPrefix("symbol(") {
      return actionID.lowercased()
    }
    return actionID
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
    updateLetterFieldsFromProfile()
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

private final class PreviewKeyboardActionHandler: KeyboardActionHandler {
  func canHandle(_ gesture: KeyboardGesture, on action: KeyboardAction) -> Bool {
    true
  }

  func handle(_ action: KeyboardAction) {}

  func handle(_ gesture: KeyboardGesture, on action: KeyboardAction) {}

  func handle(_ gesture: KeyboardGesture, on key: Key) {}

  func handleDrag(on action: KeyboardAction, from startLocation: CGPoint, to currentLocation: CGPoint) {}
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

private extension UIImage {
  func resizedForKeyboardKeyBackground(maxDimension: CGFloat) -> UIImage {
    let longest = max(size.width, size.height)
    guard longest > maxDimension, longest > 0 else { return self }
    let scale = maxDimension / longest
    let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.image { _ in
      draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }
}
