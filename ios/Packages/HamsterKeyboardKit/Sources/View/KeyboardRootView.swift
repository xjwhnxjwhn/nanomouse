//
//  KeyboardRootView.swift
//
//
//  Created by morse on 2023/8/14.
//

import Combine
import HamsterKit
import HamsterUIKit
import OSLog
import UIKit

/**
 键盘根视图
 */
class KeyboardRootView: NibLessView {
  public typealias KeyboardWidth = CGFloat
  public typealias KeyboardItemWidth = CGFloat

  // MARK: - Properties

  private let keyboardLayoutProvider: KeyboardLayoutProvider
  private let actionHandler: KeyboardActionHandler
  private let appearance: KeyboardAppearance
  private let layoutConfig: KeyboardLayoutConfiguration
  private var actionCalloutContext: ActionCalloutContext
  private var calloutContext: KeyboardCalloutContext
  private var inputCalloutContext: InputCalloutContext
  private var keyboardContext: KeyboardContext
  private var rimeContext: RimeContext

  private var subscriptions = Set<AnyCancellable>()

  /// 当前键盘类型
  private var currentKeyboardType: KeyboardType

  /// 当前屏幕方向
  private var interfaceOrientation: InterfaceOrientation

  /// 当前界面样式
  private var userInterfaceStyle: UIUserInterfaceStyle

  /// 键盘是否浮动
  private var isKeyboardFloating: Bool

  /// 口述模式状态
  private var isVoiceModeActive: Bool = false

  /// 工具栏收起时约束
  private var toolbarCollapseDynamicConstraints = [NSLayoutConstraint]()

  /// 工具栏展开时约束
  private var toolbarExpandDynamicConstraints = [NSLayoutConstraint]()

  /// 工具栏高度约束
  private var toolbarHeightConstraint: NSLayoutConstraint?

  /// 候选文字视图状态
  private var candidateViewState: CandidateBarView.State

  /// 非主键盘的临时键盘Cache
  // private var tempKeyboardViewCache: [KeyboardType: UIView] = [:]

  // MARK: - 计算属性

//  private var actionCalloutStyle: KeyboardActionCalloutStyle {
//    var style = appearance.actionCalloutStyle
//    let insets = layoutConfig.buttonInsets
//    style.callout.buttonInset = insets
//    return style
//  }

//  private var inputCalloutStyle: KeyboardInputCalloutStyle {
//    var style = appearance.inputCalloutStyle
//    let insets = layoutConfig.buttonInsets
//    style.callout.buttonInset = insets
//    return style
//  }

  // MARK: - subview

  /// 26键键盘，包含默认中文26键及英文26键
  /// 注意：计算属性， 在 primaryKeyboardView 闭包中按需创建
  private var standerSystemKeyboard: StanderSystemKeyboard {
    let view = StanderSystemKeyboard(
      keyboardLayoutProvider: keyboardLayoutProvider,
      appearance: appearance,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext,
      calloutContext: calloutContext
    )
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }

  /// 中文九宫格键盘
  /// 注意：计算属性， 在 primaryKeyboardView 闭包中按需创建
  private var chineseNineGridKeyboardView: ChineseNineGridKeyboard {
    let view = ChineseNineGridKeyboard(
      keyboardLayoutProvider: keyboardLayoutProvider,
      actionHandler: actionHandler,
      appearance: appearance,
      keyboardContext: keyboardContext,
      calloutContext: calloutContext,
      rimeContext: rimeContext
    )
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }

  /// 数字九宫格键盘
  /// 注意：计算属性
  private var numericNineGridKeyboardView: UIView {
    let view = NumericNineGridKeyboard(
      actionHandler: actionHandler,
      appearance: appearance,
      keyboardContext: keyboardContext,
      calloutContext: calloutContext,
      rimeContext: rimeContext
    )
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }

  /// 符号分类键盘
  /// 注意：计算属性
  private var classifySymbolicKeyboardView: ClassifySymbolicKeyboard {
    let view = ClassifySymbolicKeyboard(
      actionHandler: actionHandler,
      appearance: appearance,
      layoutProvider: keyboardLayoutProvider,
      keyboardContext: keyboardContext
    )
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }

  /// emoji键盘
  /// 注意：计算属性
  private var emojisKeyboardView: UIView {
    // TODO:
    let view = UIView()
    view.backgroundColor = .red
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }

  /// 工具栏
  private lazy var toolbarView: UIView = {
    let view = KeyboardToolbarView(appearance: appearance, actionHandler: actionHandler, keyboardContext: keyboardContext, rimeContext: rimeContext)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 口述模式视图
  private lazy var voiceModeView: VoiceModeView = {
    let view = VoiceModeView(
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      voiceInputBridge: KeyboardVoiceInputBridge.shared
    )
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    view.onClose = { [weak self] in
      self?.setVoiceMode(false)
    }
    return view
  }()

  private var extraCandidateBarHeight: CGFloat {
    rimeContext.prefersTwoTierCandidateBar ? keyboardContext.heightOfCodingArea : 0
  }

  private var effectiveToolbarHeight: CGFloat {
    keyboardContext.heightOfToolbar + extraCandidateBarHeight
  }

  /// 主键盘
  private lazy var primaryKeyboardView: UIView = {
    if let view = chooseKeyboard(keyboardType: keyboardContext.keyboardType) {
      return view
    }
    return standerSystemKeyboard
  }()

  // MARK: - Initializations

  /**
   Create a system keyboard with custom button views.

   The provided `buttonView` builder will be used to build
   the full button view for every layout item.

   - Parameters:
     - keyboardLayoutProvider: The keyboard layout provider to use.
     - appearance: The keyboard appearance to use.
     - actionHandler: The action handler to use.
     - autocompleteContext: The autocomplete context to use.
     - autocompleteToolbar: The autocomplete toolbar mode to use.
     - autocompleteToolbarAction: The action to trigger when tapping an autocomplete suggestion.
     - keyboardContext: The keyboard context to use.
     - calloutContext: The callout context to use.
     - width: The keyboard width.
   */
  public init(
    keyboardLayoutProvider: KeyboardLayoutProvider,
    appearance: KeyboardAppearance,
    actionHandler: KeyboardActionHandler,
    keyboardContext: KeyboardContext,
    calloutContext: KeyboardCalloutContext?,
    rimeContext: RimeContext
  ) {
    self.keyboardLayoutProvider = keyboardLayoutProvider
    self.layoutConfig = .standard(for: keyboardContext)
    self.actionHandler = actionHandler
    self.appearance = appearance
    self.keyboardContext = keyboardContext
    self.calloutContext = calloutContext ?? .disabled
    self.actionCalloutContext = calloutContext?.action ?? .disabled
    self.inputCalloutContext = calloutContext?.input ?? .disabled
    self.rimeContext = rimeContext
    self.candidateViewState = keyboardContext.candidatesViewState
    self.currentKeyboardType = keyboardContext.keyboardType
    self.interfaceOrientation = keyboardContext.interfaceOrientation
    self.isKeyboardFloating = keyboardContext.isKeyboardFloating
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    // Test
//    let view = UIView()
//    view.frame = CGRect(origin: .zero, size: CGSize(width: 100, height: 100))
//    view.backgroundColor = .yellow
//    addSubview(view)

    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()

    combine()
  }

  deinit {
    subviews.forEach { $0.removeFromSuperview() }
  }

  override func setupAppearance() {
    backgroundColor = appearance.backgroundStyle.backgroundColor
    contentMode = .redraw
  }

  // MARK: - Layout

  /// 构建视图层次
  override func constructViewHierarchy() {
    if keyboardContext.enableToolbar {
      addSubview(toolbarView)
      addSubview(primaryKeyboardView)
    } else {
      addSubview(primaryKeyboardView)
    }
    addSubview(voiceModeView)
  }

  /// 激活约束
  override func activateViewConstraints() {
    if keyboardContext.enableToolbar {
      // 工具栏高度约束，可随配置调整高度
      toolbarHeightConstraint = toolbarView.heightAnchor.constraint(equalToConstant: effectiveToolbarHeight)

      // 工具栏静态约束
      let toolbarStaticConstraint = createToolbarStaticConstraints()

      // 工具栏收缩时动态约束
      toolbarCollapseDynamicConstraints = createToolbarCollapseDynamicConstraints()

      // 工具栏展开时动态约束
      toolbarExpandDynamicConstraints = createToolbarExpandDynamicConstraints()

      NSLayoutConstraint.activate(toolbarStaticConstraint + toolbarCollapseDynamicConstraints + [toolbarHeightConstraint!])
    } else {
      NSLayoutConstraint.activate(createNoToolbarConstraints())
    }

    NSLayoutConstraint.activate([
      voiceModeView.topAnchor.constraint(equalTo: topAnchor),
      voiceModeView.bottomAnchor.constraint(equalTo: bottomAnchor),
      voiceModeView.leadingAnchor.constraint(equalTo: leadingAnchor),
      voiceModeView.trailingAnchor.constraint(equalTo: trailingAnchor)
    ])
  }

  /// 工具栏静态约束（不会发生变动）
  func createToolbarStaticConstraints() -> [NSLayoutConstraint] {
    return [
      toolbarView.topAnchor.constraint(equalTo: topAnchor),
      toolbarView.leadingAnchor.constraint(equalTo: leadingAnchor),
      toolbarView.trailingAnchor.constraint(equalTo: trailingAnchor)
    ]
  }

  /// 工具栏展开时动态约束
  func createToolbarExpandDynamicConstraints() -> [NSLayoutConstraint] {
    return [
      toolbarView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ]
  }

  /// 工具栏收缩时动态约束
  func createToolbarCollapseDynamicConstraints() -> [NSLayoutConstraint] {
    return [
      primaryKeyboardView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
      primaryKeyboardView.bottomAnchor.constraint(equalTo: bottomAnchor),
      primaryKeyboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
      primaryKeyboardView.trailingAnchor.constraint(equalTo: trailingAnchor)
    ]
  }

  /// 无工具栏时约束
  func createNoToolbarConstraints() -> [NSLayoutConstraint] {
    return [
      primaryKeyboardView.topAnchor.constraint(equalTo: topAnchor),
      primaryKeyboardView.bottomAnchor.constraint(equalTo: bottomAnchor),
      primaryKeyboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
      primaryKeyboardView.trailingAnchor.constraint(equalTo: trailingAnchor)
    ]
  }

  func combine() {
    // 在开启工具栏的状态下，根据候选状态调节候选栏区域大小
    if keyboardContext.enableToolbar {
      keyboardContext.$candidatesViewState
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
          guard let self = self else { return }
          guard candidateViewState != $0 else { return }
          setNeedsLayout()
        }
        .store(in: &subscriptions)
    }

    // 跟踪 UIUserInterfaceStyle 变化
    keyboardContext.$traitCollection
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        guard userInterfaceStyle != $0.userInterfaceStyle else { return }
        userInterfaceStyle = $0.userInterfaceStyle
        setupAppearance()
        if keyboardContext.enableToolbar {
          toolbarView.setNeedsLayout()
        }
        voiceModeView.updateStyle()
        primaryKeyboardView.setNeedsLayout()
      }
      .store(in: &subscriptions)

    // 屏幕方向改变调整按键高度及按键内距
    keyboardContext.$interfaceOrientation
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        guard $0 != self.interfaceOrientation else { return }
        self.interfaceOrientation = $0
        self.primaryKeyboardView.setNeedsLayout()
      }
      .store(in: &subscriptions)

    // iPad 浮动模式开启
    keyboardContext.$isKeyboardFloating
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        guard self.isKeyboardFloating != $0 else { return }
        self.isKeyboardFloating = $0
        self.primaryKeyboardView.setNeedsLayout()
      }
      .store(in: &subscriptions)

    // 跟踪键盘类型变化
    keyboardContext.keyboardTypePublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        guard $0 != currentKeyboardType else { return }
        currentKeyboardType = $0

        Logger.statistics.debug("KeyboardRootView keyboardType combine: \($0.yamlString)")

        updatePrimaryKeyboardView(for: $0)
      }
      .store(in: &subscriptions)

    NotificationCenter.default.publisher(for: .hamsterVoiceModeToggle)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self = self else { return }
        setVoiceMode(!isVoiceModeActive)
      }
      .store(in: &subscriptions)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Logger.statistics.debug("KeyboardRootView: layoutSubviews()")

    // 检测候选栏状态是否发生变化
    guard candidateViewState != keyboardContext.candidatesViewState else { return }
    candidateViewState = keyboardContext.candidatesViewState

    // 候选栏收起
    if candidateViewState.isCollapse() {
      // 键盘显示
      toolbarHeightConstraint?.constant = effectiveToolbarHeight
      addSubview(primaryKeyboardView)
      NSLayoutConstraint.deactivate(toolbarExpandDynamicConstraints)
      NSLayoutConstraint.activate(toolbarCollapseDynamicConstraints)
    } else {
      // 键盘隐藏
      let toolbarHeight = primaryKeyboardView.bounds.height + effectiveToolbarHeight
      primaryKeyboardView.removeFromSuperview()

      toolbarHeightConstraint?.constant = toolbarHeight
      NSLayoutConstraint.deactivate(toolbarCollapseDynamicConstraints)
      NSLayoutConstraint.activate(toolbarExpandDynamicConstraints)
    }
  }

  /// 根据键盘类型选择键盘
  func chooseKeyboard(keyboardType: KeyboardType) -> UIView? {
//    // 从 cache 中获取键盘
//    if let tempKeyboardView = tempKeyboardViewCache[keyboardType] {
//      return tempKeyboardView
//    }

    // 生成临时键盘
    var tempKeyboardView: UIView? = nil
    switch keyboardType {
    case .numericNineGrid:
      tempKeyboardView = numericNineGridKeyboardView
    case .classifySymbolic:
      tempKeyboardView = classifySymbolicKeyboardView
    case .emojis:
      tempKeyboardView = emojisKeyboardView
    case .alphabetic, .numeric, .symbolic, .chinese, .chineseNumeric, .chineseSymbolic, .custom:
      tempKeyboardView = standerSystemKeyboard
    case .chineseNineGrid:
      tempKeyboardView = chineseNineGridKeyboardView
    default:
      // 注意：非临时键盘类型外的类型直接 return
      Logger.statistics.error("keyboardType: \(keyboardType.yamlString) not match tempKeyboardType")
      return nil
    }

    // 保存 cache
//    tempKeyboardViewCache[keyboardType] = tempKeyboardView
    return tempKeyboardView
  }

  /// 强制刷新当前键盘视图
  func reloadKeyboardView() {
    updatePrimaryKeyboardView(for: currentKeyboardType)
  }

  private func updatePrimaryKeyboardView(for keyboardType: KeyboardType) {
    guard let keyboardView = chooseKeyboard(keyboardType: keyboardType) else {
      Logger.statistics.error("\(keyboardType.yamlString) cannot find keyboardView.")
      return
    }

    if keyboardContext.enableToolbar {
      NSLayoutConstraint.deactivate(toolbarCollapseDynamicConstraints + toolbarExpandDynamicConstraints)
      toolbarCollapseDynamicConstraints.removeAll(keepingCapacity: true)
      toolbarExpandDynamicConstraints.removeAll(keepingCapacity: true)

      primaryKeyboardView.subviews.forEach { $0.removeFromSuperview() }
      primaryKeyboardView.removeFromSuperview()

      primaryKeyboardView = keyboardView

      toolbarCollapseDynamicConstraints = createToolbarCollapseDynamicConstraints()
      toolbarExpandDynamicConstraints = createToolbarExpandDynamicConstraints()

      if candidateViewState.isCollapse() {
        addSubview(primaryKeyboardView)
        NSLayoutConstraint.activate(toolbarCollapseDynamicConstraints)
      } else {
        NSLayoutConstraint.activate(toolbarExpandDynamicConstraints)
      }
    } else {
      NSLayoutConstraint.deactivate(constraints)
      primaryKeyboardView.removeFromSuperview()
      primaryKeyboardView = keyboardView
      addSubview(primaryKeyboardView)
      NSLayoutConstraint.activate(createNoToolbarConstraints())
    }
  }

  /// 切换口述模式时隐藏键盘区域，避免误触
  private func setVoiceMode(_ isActive: Bool) {
    guard isVoiceModeActive != isActive else { return }
    isVoiceModeActive = isActive
    voiceModeView.isHidden = !isActive
    toolbarView.isHidden = isActive
    primaryKeyboardView.isHidden = isActive
    if isActive {
      bringSubviewToFront(voiceModeView)
    }
    setNeedsLayout()
  }
}

final class VoiceModeView: NibLessView {
  var onClose: (() -> Void)?

  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private let voiceInputBridge: KeyboardVoiceInputBridge
  private var activeRequestId: String?

  private lazy var appIconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(named: "NanomouseLogo", in: .module, compatibleWith: nil), for: .normal)
    button.imageView?.contentMode = .scaleAspectFill
    button.clipsToBounds = true
    button.addTarget(self, action: #selector(handleOpenAppTouchDown), for: .touchDown)
    button.addTarget(self, action: #selector(handleOpenAppTouchUp), for: .touchUpInside)
    button.addTarget(self, action: #selector(handleOpenAppTouchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(handleOpenAppTouchCancel), for: .touchUpOutside)
    return button
  }()

  private lazy var promptLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "点击说话"
    label.font = .systemFont(ofSize: 16, weight: .regular)
    return label
  }()

  private lazy var micButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "mic.fill"), for: .normal)
    button.addTarget(self, action: #selector(handleMicTap), for: .touchUpInside)
    return button
  }()

  private lazy var lineBreakButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("换行", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    button.addTarget(self, action: #selector(handleLineBreakTap), for: .touchUpInside)
    return button
  }()

  private lazy var atButton: UIButton = {
    makeTopButton(title: "@", action: #selector(handleAtTap))
  }()

  private lazy var spaceButton: UIButton = {
    makeTopButton(title: "空格", action: #selector(handleSpaceTap))
  }()

  private lazy var backspaceButton: UIButton = {
    makeTopButton(title: "⌫", action: #selector(handleBackspaceTap))
  }()

  private lazy var closeButton: UIButton = {
    makeTopButton(title: "×", action: #selector(handleCloseTap))
  }()

  private lazy var dismissKeyboardButton: UIButton = {
    makeTopIconButton(
      symbolName: "chevron.down.circle",
      action: #selector(handleDismissKeyboardTap)
    )
  }()

  private lazy var topRightStack: UIStackView = {
    let stack = UIStackView(arrangedSubviews: [atButton, spaceButton, backspaceButton, closeButton, dismissKeyboardButton])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 10
    return stack
  }()

  private lazy var centerStack: UIStackView = {
    let stack = UIStackView(arrangedSubviews: [promptLabel, micButton, lineBreakButton])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 18
    return stack
  }()

  init(
    actionHandler: KeyboardActionHandler,
    keyboardContext: KeyboardContext,
    voiceInputBridge: KeyboardVoiceInputBridge = .shared
  ) {
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.voiceInputBridge = voiceInputBridge
    super.init(frame: .zero)
    setupSubview()
  }

  private func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func constructViewHierarchy() {
    addSubview(appIconButton)
    addSubview(topRightStack)
    addSubview(centerStack)
  }

  override func activateViewConstraints() {
    layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    NSLayoutConstraint.activate([
      appIconButton.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
      appIconButton.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
      appIconButton.widthAnchor.constraint(equalToConstant: 36),
      appIconButton.heightAnchor.constraint(equalTo: appIconButton.widthAnchor),

      topRightStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
      topRightStack.centerYAnchor.constraint(equalTo: appIconButton.centerYAnchor),

      atButton.widthAnchor.constraint(equalToConstant: 36),
      atButton.heightAnchor.constraint(equalTo: atButton.widthAnchor),
      spaceButton.widthAnchor.constraint(equalTo: atButton.widthAnchor),
      spaceButton.heightAnchor.constraint(equalTo: atButton.heightAnchor),
      backspaceButton.widthAnchor.constraint(equalTo: atButton.widthAnchor),
      backspaceButton.heightAnchor.constraint(equalTo: atButton.heightAnchor),
      closeButton.widthAnchor.constraint(equalTo: atButton.widthAnchor),
      closeButton.heightAnchor.constraint(equalTo: atButton.heightAnchor),
      dismissKeyboardButton.widthAnchor.constraint(equalTo: atButton.widthAnchor),
      dismissKeyboardButton.heightAnchor.constraint(equalTo: atButton.heightAnchor),

      centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
      centerStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 8),

      micButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.62),
      micButton.heightAnchor.constraint(equalToConstant: 72),
      lineBreakButton.widthAnchor.constraint(equalTo: micButton.widthAnchor, multiplier: 0.52),
      lineBreakButton.heightAnchor.constraint(equalToConstant: 42)
    ])
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    micButton.layer.cornerRadius = micButton.bounds.height / 2
    lineBreakButton.layer.cornerRadius = lineBreakButton.bounds.height / 2
    atButton.layer.cornerRadius = atButton.bounds.height / 2
    spaceButton.layer.cornerRadius = spaceButton.bounds.height / 2
    backspaceButton.layer.cornerRadius = backspaceButton.bounds.height / 2
    closeButton.layer.cornerRadius = closeButton.bounds.height / 2
    dismissKeyboardButton.layer.cornerRadius = dismissKeyboardButton.bounds.height / 2
    appIconButton.layer.cornerRadius = appIconButton.bounds.height / 2
  }

  override func setupAppearance() {
    updateStyle()
  }

  func updateStyle() {
    let isDark = keyboardContext.colorScheme == .dark
    let background = isDark ? UIColor(white: 0.16, alpha: 1.0) : UIColor(white: 0.96, alpha: 1.0)
    let primaryText = isDark ? UIColor(white: 0.97, alpha: 1.0) : UIColor(white: 0.1, alpha: 1.0)
    let secondaryText = isDark ? UIColor(white: 0.72, alpha: 1.0) : UIColor(white: 0.4, alpha: 1.0)
    let pillBackground = isDark ? UIColor(white: 0.92, alpha: 1.0) : UIColor(white: 0.18, alpha: 1.0)
    let pillText = isDark ? UIColor(white: 0.12, alpha: 1.0) : UIColor(white: 0.95, alpha: 1.0)
    let topButtonBackground = isDark ? UIColor(white: 0.26, alpha: 1.0) : UIColor(white: 0.85, alpha: 1.0)
    let topButtonText = isDark ? UIColor(white: 0.95, alpha: 1.0) : UIColor(white: 0.1, alpha: 1.0)

    backgroundColor = background
    promptLabel.textColor = secondaryText

    micButton.backgroundColor = pillBackground
    micButton.tintColor = pillText
    lineBreakButton.backgroundColor = pillBackground
    lineBreakButton.setTitleColor(pillText, for: .normal)

    [atButton, spaceButton, backspaceButton, closeButton, dismissKeyboardButton].forEach { button in
      button.backgroundColor = topButtonBackground
    }
    [atButton, spaceButton, backspaceButton, closeButton].forEach { button in
      button.setTitleColor(topButtonText, for: .normal)
    }
    dismissKeyboardButton.tintColor = topButtonText
    appIconButton.backgroundColor = topButtonBackground
  }

  private func makeTopButton(title: String, action: Selector) -> UIButton {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func makeTopIconButton(symbolName: String, action: Selector) -> UIButton {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: symbolName), for: .normal)
    button.setPreferredSymbolConfiguration(
      .init(font: .systemFont(ofSize: 18, weight: .semibold), scale: .default),
      forImageIn: .normal
    )
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  @objc private func handleAtTap() {
    actionHandler.handle(.release, on: .character("@"))
  }

  @objc private func handleSpaceTap() {
    actionHandler.handle(.release, on: .space)
  }

  @objc private func handleBackspaceTap() {
    actionHandler.handle(.press, on: .backspace)
    actionHandler.handle(.release, on: .backspace)
  }

  @objc private func handleLineBreakTap() {
    actionHandler.handle(.release, on: .primary(.return))
  }

  @objc private func handleCloseTap() {
    resetMicLaunchState()
    onClose?()
  }

  @objc private func handleDismissKeyboardTap() {
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  @objc private func handleOpenAppTouchDown() {
    appIconButton.backgroundColor = keyboardContext.colorScheme == .dark
      ? UIColor(white: 0.34, alpha: 1.0)
      : UIColor(white: 0.76, alpha: 1.0)
  }

  @objc private func handleOpenAppTouchUp() {
    appIconButton.backgroundColor = keyboardContext.colorScheme == .dark
      ? UIColor(white: 0.34, alpha: 1.0)
      : UIColor(white: 0.76, alpha: 1.0)
    actionHandler.handle(
      .release,
      on: .url(URL(string: "nanomouse://com.XiangqingZHANG.nanomouse/main"), id: "openHamster")
    )
  }

  @objc private func handleOpenAppTouchCancel() {
    appIconButton.backgroundColor = keyboardContext.colorScheme == .dark
      ? UIColor(white: 0.26, alpha: 1.0)
      : UIColor(white: 0.85, alpha: 1.0)
  }

  @objc private func handleMicTap() {
    guard micButton.isEnabled else { return }
    let requestId = voiceInputBridge.makeRequestId()
    activeRequestId = requestId
    voiceInputBridge.setState(requestId: requestId, state: .launching)
    guard let openURL = voiceInputBridge.makeDictationURL(requestId: requestId) else {
      voiceInputBridge.setState(requestId: requestId, state: .failed, errorMessage: "invalid dictation url")
      return
    }

    promptLabel.text = "正在启动..."
    micButton.isEnabled = false
    actionHandler.handle(.release, on: .url(openURL, id: "voiceDictation"))

    // 避免跳转失败后按钮被锁死，延时恢复点击
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self = self else { return }
      self.resetMicLaunchState()
    }
  }

  private func resetMicLaunchState() {
    promptLabel.text = "点击说话"
    micButton.isEnabled = true
  }
}

extension Notification.Name {
  static let hamsterVoiceModeToggle = Notification.Name("hamsterVoiceModeToggle")
}
