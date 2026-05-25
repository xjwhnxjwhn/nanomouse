//
//  KeyboardToolbarView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
import RimeKit
import UIKit

/**
 键盘工具栏

 用于显示：
 1. 候选文字，包含横向部分文字显示及下拉显示全部文字
 2. 常用功能视图
 */
class KeyboardToolbarView: NibLessView {
  private let appearance: KeyboardAppearance
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private let canvasInputBridge: KeyboardCanvasBridge = .shared
  private let voiceInputBridge: KeyboardVoiceInputBridge = .shared
  private let embeddedModuleEntry: KeyboardEmbeddedModuleEntry? = KeyboardEmbeddedModuleRegistry.shared.keyboardEntries().first
  private var style: CandidateBarStyle
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var oldBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()
  private var lastKeyboardType: KeyboardType?
  private var lastAsciiModeSnapshot: Bool = false
  private var traditionalizeHintWorkItem: DispatchWorkItem?
  private var traditionalizeHintAllowsWeather = false
  private var isDiaryIndicatorBlinking = false
  private var didTriggerDiaryModeLongPress = false
  private var didTriggerEmbeddedModuleLongPress = false
  private var didPerformInitialToolbarRefresh = false
  private var weatherIndicatorRefreshTask: Task<Void, Never>?
  private let rightButtonsReferenceSpacing: CGFloat = 2
  private let rightButtonsTargetWidthScale: CGFloat = 0.85

  private lazy var traditionalizeLongPressGesture: UILongPressGestureRecognizer = {
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleTraditionalizeLongPress(_:)))
    recognizer.minimumPressDuration = keyboardContext.longPressDelay ?? GestureButtonDefaults.longPressDelay
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = self
    return recognizer
  }()

  private lazy var oneHandLeftSwipeGesture: UISwipeGestureRecognizer = {
    let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleTraditionalizeAreaSwipe(_:)))
    recognizer.direction = .left
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = self
    return recognizer
  }()

  private lazy var oneHandRightSwipeGesture: UISwipeGestureRecognizer = {
    let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleTraditionalizeAreaSwipe(_:)))
    recognizer.direction = .right
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = self
    return recognizer
  }()

  private lazy var embeddedModuleLongPressGesture: UILongPressGestureRecognizer = {
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleEmbeddedModuleLongPress(_:)))
    recognizer.minimumPressDuration = keyboardContext.longPressDelay ?? GestureButtonDefaults.longPressDelay
    recognizer.cancelsTouchesInView = false
    return recognizer
  }()

  private lazy var diaryModeLongPressGesture: UILongPressGestureRecognizer = {
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleDiaryModeLongPress(_:)))
    recognizer.minimumPressDuration = keyboardContext.longPressDelay ?? GestureButtonDefaults.longPressDelay
    recognizer.cancelsTouchesInView = false
    return recognizer
  }()

  private lazy var traditionalizeHintLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.7
    label.alpha = 0
    label.isHidden = true
    label.isUserInteractionEnabled = false
    return label
  }()

  private struct WeatherIndicatorPresentation {
    let symbolName: String
    let text: String
  }

  private lazy var weatherIndicatorContainer: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 4
    stack.setContentCompressionResistancePriority(.required, for: .horizontal)
    stack.setContentHuggingPriority(.required, for: .horizontal)
    stack.isHidden = true
    stack.isUserInteractionEnabled = true
    let tap = UITapGestureRecognizer(target: self, action: #selector(openWeatherIndicatorSettings))
    stack.addGestureRecognizer(tap)
    stack.addGestureRecognizer(diaryModeLongPressGesture)
    return stack
  }()

  private lazy var weatherIndicatorIconView: UIImageView = {
    let imageView = UIImageView(frame: .zero)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = style.candidateTextColor
    imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    imageView.setContentHuggingPriority(.required, for: .horizontal)
    return imageView
  }()

  private lazy var weatherIndicatorLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .left
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.7
    label.lineBreakMode = .byClipping
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    label.setContentHuggingPriority(.required, for: .horizontal)
    return label
  }()

  private lazy var traditionalizeHotspotView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = true
    view.isAccessibilityElement = true
    view.accessibilityLabel = "繁简切换"
    view.accessibilityIdentifier = "nanomouse_keyboard_traditionalize_hotspot"
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
  }()

  lazy var logoContainer: RoundedContainer = {
    let view = RoundedContainer(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = style.toolbarButtonBackgroundColor
    
    return view
  }()

  lazy var logoImageView: UIImageView = {
    let view = UIImageView(image: UIImage(named: "NanomouseLogo", in: .module, compatibleWith: nil))
    view.translatesAutoresizingMaskIntoConstraints = false
    view.contentMode = .scaleAspectFill
    view.clipsToBounds = true
    return view
  }()

  /// 常用功能项: NanomouseApp (Touch Only)
  lazy var iconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    // Image removed, handled by logoImageView
    button.backgroundColor = .clear
    button.addTarget(self, action: #selector(openHamsterAppTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(openHamsterAppTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    
    return button
  }()

  /// 解散键盘 Button
  lazy var dismissKeyboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 19), scale: .default), forImageIn: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.contentEdgeInsets = .init(top: 6, left: 6, bottom: 6, right: 6)
    button.tintColor = .secondaryLabel
    button.backgroundColor = .clear
    button.addTarget(self, action: #selector(dismissKeyboardTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  private lazy var rightButtonsStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = rightButtonsReferenceSpacing
    return stack
  }()

  /// 口述模式按钮
  private lazy var voiceModeButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.setImage(UIImage(systemName: "waveform"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 19), scale: .default), forImageIn: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.contentEdgeInsets = .init(top: 6, left: 6, bottom: 6, right: 6)
    button.tintColor = style.toolbarButtonFrontColor
    button.addTarget(self, action: #selector(voiceModeTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(voiceModeTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 画布按钮
  private lazy var canvasButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.setImage(UIImage(systemName: "scribble.variable"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 19), scale: .default), forImageIn: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.contentEdgeInsets = .init(top: 6, left: 6, bottom: 6, right: 6)
    button.tintColor = style.toolbarButtonFrontColor
    button.addTarget(self, action: #selector(canvasTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(canvasTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// Markdown 按钮
  private lazy var markdownButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.setImage(UIImage(systemName: "text.document"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 19), scale: .default), forImageIn: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.contentEdgeInsets = .init(top: 6, left: 6, bottom: 6, right: 6)
    button.tintColor = style.toolbarButtonFrontColor
    button.addTarget(self, action: #selector(markdownTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(markdownTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  /// 私有模块按钮（由注册表动态提供）
  private lazy var embeddedModuleButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = style.toolbarButtonBackgroundColor
    let symbolName = embeddedModuleEntry?.iconSystemName ?? "square.on.square"
    button.setImage(UIImage(systemName: symbolName), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 19), scale: .default), forImageIn: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.contentEdgeInsets = .init(top: 6, left: 6, bottom: 6, right: 6)
    button.tintColor = style.toolbarButtonFrontColor
    button.accessibilityLabel = embeddedModuleEntry?.accessibilityLabel ?? "扩展模块"
    button.accessibilityIdentifier = "nanomouse_keyboard_embedded_module"
    button.addTarget(self, action: #selector(embeddedModuleTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(embeddedModuleTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  // TODO: 常用功能栏
  lazy var commonFunctionBar: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 候选文字视图
  lazy var candidateBarView: CandidateBarView = {
    let view = CandidateBarView(
      style: style,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext
    )
    return view
  }()

  lazy var predictionCandidatesView: PredictionCandidatesCollectionView = {
    let view = PredictionCandidatesCollectionView(
      style: style,
      keyboardContext: keyboardContext,
      actionHandler: actionHandler,
      rimeContext: rimeContext
    )
    view.isHidden = true
    return view
  }()

  private var commonFunctionBarHeightConstraint: NSLayoutConstraint?
  private var predictionCandidatesHeightConstraint: NSLayoutConstraint?

  init(appearance: KeyboardAppearance, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.appearance = appearance
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    // KeyboardToolbarView 为 candidateBarStyle 样式根节点, 这里生成一次，减少计算次数
    self.style = appearance.candidateBarStyle
    self.userInterfaceStyle = keyboardContext.colorScheme
    self.lastKeyboardType = keyboardContext.keyboardType
    self.lastAsciiModeSnapshot = rimeContext.asciiModeSnapshot

    super.init(frame: .zero)

    setupSubview()

    combine()
    observeKeyboardState()
  }

  deinit {
    weatherIndicatorRefreshTask?.cancel()
  }

  func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    commonFunctionBar.addGestureRecognizer(traditionalizeLongPressGesture)
    commonFunctionBar.addGestureRecognizer(oneHandLeftSwipeGesture)
    commonFunctionBar.addGestureRecognizer(oneHandRightSwipeGesture)
    if embeddedModuleEntry != nil {
      embeddedModuleButton.addGestureRecognizer(embeddedModuleLongPressGesture)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if userInterfaceStyle != keyboardContext.colorScheme {
      applyTraitAppearance()
    }
    
    // Ensure logo image is also rounded if it has a background
    let radius = logoImageView.bounds.height * 0.2237
    logoImageView.layer.cornerRadius = radius
    logoImageView.layer.cornerCurve = .continuous
    updateToolbarButtonSymbolConfiguration()
    applyToolbarButtonCornerStyle()
    updateRightButtonsStackSpacing()
    scheduleInitialToolbarRefreshIfNeeded()
  }

  func refreshAppearanceForTraitChange() {
    applyTraitAppearance()
    setNeedsLayout()
    layoutIfNeeded()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    scheduleInitialToolbarRefreshIfNeeded()
  }

  override func constructViewHierarchy() {
    addSubview(commonFunctionBar)
    addSubview(predictionCandidatesView)
    if keyboardContext.displayAppIconButton {
      commonFunctionBar.addSubview(logoContainer)
      logoContainer.addSubview(logoImageView)
      logoContainer.addSubview(iconButton)
    }
    commonFunctionBar.addSubview(rightButtonsStack)
    if embeddedModuleEntry != nil {
      rightButtonsStack.addArrangedSubview(embeddedModuleButton)
    }
    rightButtonsStack.addArrangedSubview(canvasButton)
    rightButtonsStack.addArrangedSubview(markdownButton)
    rightButtonsStack.addArrangedSubview(voiceModeButton)
    if keyboardContext.displayKeyboardDismissButton {
      rightButtonsStack.addArrangedSubview(dismissKeyboardButton)
    }
    weatherIndicatorContainer.addArrangedSubview(weatherIndicatorIconView)
    weatherIndicatorContainer.addArrangedSubview(weatherIndicatorLabel)
    commonFunctionBar.addSubview(weatherIndicatorContainer)
    commonFunctionBar.addSubview(traditionalizeHotspotView)
    commonFunctionBar.addSubview(traditionalizeHintLabel)
  }

  override func activateViewConstraints() {
    commonFunctionBarHeightConstraint = commonFunctionBar.heightAnchor.constraint(equalToConstant: keyboardContext.heightOfToolbar)
    predictionCandidatesHeightConstraint = predictionCandidatesView.heightAnchor.constraint(equalToConstant: 0)
    var constraints: [NSLayoutConstraint] = [
      commonFunctionBar.topAnchor.constraint(equalTo: topAnchor),
      commonFunctionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      commonFunctionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
      commonFunctionBarHeightConstraint!,

      predictionCandidatesView.topAnchor.constraint(equalTo: commonFunctionBar.bottomAnchor),
      predictionCandidatesView.leadingAnchor.constraint(equalTo: leadingAnchor),
      predictionCandidatesView.trailingAnchor.constraint(equalTo: trailingAnchor),
      predictionCandidatesHeightConstraint!,
    ]

    if keyboardContext.displayAppIconButton {
      constraints.append(contentsOf: [
        logoContainer.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor),
        logoContainer.heightAnchor.constraint(equalTo: logoContainer.widthAnchor),
        logoContainer.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: logoContainer.bottomAnchor),
        logoContainer.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
        
        // ImageView centered and 50% size
        logoImageView.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
        logoImageView.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
        logoImageView.widthAnchor.constraint(equalTo: logoContainer.widthAnchor, multiplier: 0.5),
        logoImageView.heightAnchor.constraint(equalTo: logoContainer.heightAnchor, multiplier: 0.5),
        
        // Button fills container (on top)
        iconButton.topAnchor.constraint(equalTo: logoContainer.topAnchor),
        iconButton.bottomAnchor.constraint(equalTo: logoContainer.bottomAnchor),
        iconButton.leadingAnchor.constraint(equalTo: logoContainer.leadingAnchor),
        iconButton.trailingAnchor.constraint(equalTo: logoContainer.trailingAnchor),
      ])
    }

    constraints.append(contentsOf: [
      rightButtonsStack.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
      rightButtonsStack.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      rightButtonsStack.topAnchor.constraint(greaterThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: rightButtonsStack.bottomAnchor),
    ])

    if keyboardContext.displayKeyboardDismissButton {
      constraints.append(contentsOf: [
        dismissKeyboardButton.heightAnchor.constraint(equalTo: commonFunctionBar.heightAnchor, multiplier: 0.7),
        dismissKeyboardButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        voiceModeButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.heightAnchor),
        voiceModeButton.widthAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        canvasButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.heightAnchor),
        canvasButton.widthAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        markdownButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.heightAnchor),
        markdownButton.widthAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
      ])
      if embeddedModuleEntry != nil {
        constraints.append(contentsOf: [
          embeddedModuleButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.heightAnchor),
          embeddedModuleButton.widthAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        ])
      }
    } else {
      constraints.append(contentsOf: [
        voiceModeButton.heightAnchor.constraint(equalTo: commonFunctionBar.heightAnchor, multiplier: 0.7),
        voiceModeButton.widthAnchor.constraint(equalTo: voiceModeButton.heightAnchor),
        canvasButton.heightAnchor.constraint(equalTo: voiceModeButton.heightAnchor),
        canvasButton.widthAnchor.constraint(equalTo: voiceModeButton.widthAnchor),
        markdownButton.heightAnchor.constraint(equalTo: voiceModeButton.heightAnchor),
        markdownButton.widthAnchor.constraint(equalTo: voiceModeButton.widthAnchor),
      ])
      if embeddedModuleEntry != nil {
        constraints.append(contentsOf: [
          embeddedModuleButton.heightAnchor.constraint(equalTo: voiceModeButton.heightAnchor),
          embeddedModuleButton.widthAnchor.constraint(equalTo: voiceModeButton.widthAnchor),
        ])
      }
    }

    constraints.append(contentsOf: [
      traditionalizeHintLabel.centerXAnchor.constraint(equalTo: traditionalizeHotspotView.centerXAnchor),
      traditionalizeHintLabel.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      traditionalizeHintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: traditionalizeHotspotView.leadingAnchor, constant: 2),
      traditionalizeHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: traditionalizeHotspotView.trailingAnchor, constant: -2),
      weatherIndicatorContainer.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      weatherIndicatorContainer.trailingAnchor.constraint(lessThanOrEqualTo: rightButtonsStack.leadingAnchor, constant: -6),
      weatherIndicatorIconView.widthAnchor.constraint(equalToConstant: 15),
      weatherIndicatorIconView.heightAnchor.constraint(equalTo: weatherIndicatorIconView.widthAnchor),
      traditionalizeHotspotView.leadingAnchor.constraint(equalTo: weatherIndicatorContainer.trailingAnchor, constant: 4),
      traditionalizeHotspotView.trailingAnchor.constraint(equalTo: rightButtonsStack.leadingAnchor, constant: -4),
      traditionalizeHotspotView.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      traditionalizeHotspotView.heightAnchor.constraint(equalTo: commonFunctionBar.heightAnchor, multiplier: 0.7),
    ])

    let traditionalizeHotspotMinWidth = traditionalizeHotspotView.widthAnchor.constraint(greaterThanOrEqualToConstant: 56)
    traditionalizeHotspotMinWidth.priority = .defaultHigh
    constraints.append(traditionalizeHotspotMinWidth)

    if keyboardContext.displayAppIconButton {
      constraints.append(weatherIndicatorContainer.leadingAnchor.constraint(equalTo: logoContainer.trailingAnchor, constant: 6))
    } else {
      constraints.append(weatherIndicatorContainer.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor, constant: 8))
    }

    NSLayoutConstraint.activate(constraints)
  }

  override func setupAppearance() {
    self.style = appearance.candidateBarStyle
    if keyboardContext.displayAppIconButton {
      // iconButton.tintColor = style.toolbarButtonFrontColor // Button is now touch overlay, icon is in ImageView
      logoContainer.backgroundColor = style.toolbarButtonBackgroundColor
    }
    if keyboardContext.displayKeyboardDismissButton {
      dismissKeyboardButton.tintColor = .secondaryLabel
      dismissKeyboardButton.backgroundColor = .clear
      dismissKeyboardButton.alpha = 1
    }
    embeddedModuleButton.tintColor = style.toolbarButtonFrontColor
    embeddedModuleButton.backgroundColor = style.toolbarButtonBackgroundColor
    canvasButton.tintColor = style.toolbarButtonFrontColor
    canvasButton.backgroundColor = style.toolbarButtonBackgroundColor
    markdownButton.tintColor = style.toolbarButtonFrontColor
    markdownButton.backgroundColor = style.toolbarButtonBackgroundColor
    voiceModeButton.tintColor = style.toolbarButtonFrontColor
    voiceModeButton.backgroundColor = style.toolbarButtonBackgroundColor
    let hintFontSize = max(style.phoneticTextFont.pointSize - 1, 9)
    traditionalizeHintLabel.font = style.phoneticTextFont.withSize(hintFontSize)
    traditionalizeHintLabel.textColor = style.candidateTextColor
    weatherIndicatorLabel.font = style.phoneticTextFont.withSize(hintFontSize)
    weatherIndicatorLabel.textColor = style.candidateTextColor
    weatherIndicatorIconView.tintColor = style.candidateTextColor
    updateCenterIndicatorVisibility()
    updateDiaryRecordingIndicatorAppearance()
  }

  private func applyTraitAppearance() {
    userInterfaceStyle = keyboardContext.colorScheme
    setupAppearance()
    candidateBarView.setStyle(style)
    predictionCandidatesView.setupStyle(style)
    updateToolbarButtonSymbolConfiguration()
    applyToolbarButtonCornerStyle()
    updateRightButtonsStackSpacing()
  }

  private func applyToolbarButtonCornerStyle() {
    let buttons = [embeddedModuleButton, canvasButton, markdownButton, voiceModeButton, dismissKeyboardButton]
    for button in buttons {
      let radius = button.bounds.height / 2
      button.layer.cornerRadius = radius
      button.layer.cornerCurve = .continuous
      button.layer.masksToBounds = false
    }
  }

  private func updateRightButtonsStackSpacing() {
    let visibleButtons = rightButtonsStack.arrangedSubviews.filter { !$0.isHidden }
    guard visibleButtons.count > 1 else {
      rightButtonsStack.spacing = rightButtonsReferenceSpacing
      return
    }

    let buttonWidths = visibleButtons.map(\.bounds.width)
    guard buttonWidths.allSatisfy({ $0 > 0 }) else { return }

    let totalButtonWidth = buttonWidths.reduce(0, +)
    let spacingSlots = CGFloat(visibleButtons.count - 1)
    let referenceWidth = totalButtonWidth + spacingSlots * rightButtonsReferenceSpacing
    let targetWidth = referenceWidth * rightButtonsTargetWidthScale
    let targetSpacing = (targetWidth - totalButtonWidth) / spacingSlots

    if abs(rightButtonsStack.spacing - targetSpacing) > 0.1 {
      rightButtonsStack.spacing = targetSpacing
      rightButtonsStack.setNeedsLayout()
    }
  }

  private func scheduleInitialToolbarRefreshIfNeeded() {
    guard !didPerformInitialToolbarRefresh else { return }
    guard window != nil else { return }
    guard bounds.width > 0, bounds.height > 0 else { return }
    didPerformInitialToolbarRefresh = true
    DispatchQueue.main.async { [weak self] in
      self?.performInitialToolbarRefresh()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.performInitialToolbarRefresh()
    }
  }

  private func performInitialToolbarRefresh() {
    setNeedsLayout()
    layoutIfNeeded()
    updateToolbarButtonSymbolConfiguration()
    applyToolbarButtonCornerStyle()
    updateRightButtonsStackSpacing()
    updateCenterIndicatorVisibility()
    refreshWeatherIndicatorIfNeeded()
    showCurrentTraditionalizeStateIfNeeded()
  }

  private func refreshWeatherIndicatorIfNeeded() {
    guard window != nil else { return }
    guard keyboardContext.hamsterConfiguration?.toolbar?.enableWeatherIndicator ?? true else { return }
    guard weatherIndicatorRefreshTask == nil else { return }
    weatherIndicatorRefreshTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      defer { self.weatherIndicatorRefreshTask = nil }
      let didRefresh = await KeyboardWeatherIndicatorExtensionRefreshService.shared.refreshIfNeeded(
        toolbar: self.keyboardContext.hamsterConfiguration?.toolbar,
        hasFullAccess: self.keyboardContext.hasFullAccess
      )
      guard !Task.isCancelled else { return }
      if didRefresh {
        self.updateCenterIndicatorVisibility()
      }
    }
  }

  private func updateToolbarButtonSymbolConfiguration() {
    let buttons = [embeddedModuleButton, canvasButton, markdownButton, voiceModeButton, dismissKeyboardButton]
    for button in buttons {
      let pointSize = toolbarSymbolPointSize(for: button)
      let configuration = UIImage.SymbolConfiguration(font: .systemFont(ofSize: pointSize), scale: .default)
      button.setPreferredSymbolConfiguration(configuration, forImageIn: .normal)
    }
  }

  private func toolbarSymbolPointSize(for button: UIButton) -> CGFloat {
    let availableHeight = button.bounds.height - button.contentEdgeInsets.top - button.contentEdgeInsets.bottom
    guard availableHeight > 0 else { return 19 }
    return min(19, max(14, availableHeight * 0.65))
  }

  private func setTopToolbarButtonPressed(_ button: UIButton, isPressed: Bool) {
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.alpha = isPressed ? 0.62 : 1
  }

  func combine() {
    Publishers.CombineLatest4(
      rimeContext.userInputKeyPublished,
      rimeContext.$textReplacementSuggestions,
      rimeContext.$suggestions,
      rimeContext.$predictiveSuggestions
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] userInputKey, textReplacementSuggestions, suggestions, predictiveSuggestions in
      guard let self = self else { return }
      
      // 有 RIME 输入或有文本替换建议时，显示候选栏
      let hasContent = !userInputKey.isEmpty || !textReplacementSuggestions.isEmpty || !suggestions.isEmpty
      let showsPredictions = keyboardContext.enablePredictiveSuggestions && !hasContent && !predictiveSuggestions.isEmpty
      let isEmpty = !hasContent
      
      self.commonFunctionBar.isHidden = !isEmpty
      self.candidateBarView.isHidden = isEmpty
      self.predictionCandidatesView.isHidden = !showsPredictions
      self.predictionCandidatesHeightConstraint?.constant = showsPredictions ? keyboardContext.heightOfPredictionCandidateRow : 0
      if hasContent {
        self.hideTraditionalizeHint(animated: false)
      }
      self.updateCenterIndicatorVisibility()

      if self.candidateBarView.superview == nil {
        candidateBarView.setStyle(self.style)
        addSubview(candidateBarView)
        candidateBarView.fillSuperview()
      }

      let showsFocusLine = !keyboardContext.enableEmbeddedInputMode || rimeContext.prefersTwoTierCandidateBar
      guard showsFocusLine else { return }
      if self.keyboardContext.keyboardType.isChineseNineGrid {
        // Debug
        // self.phoneticArea.text = inputKeys + " | " + self.rimeContext.t9UserInputKey
        let prefix = self.rimeContext.compositionPrefix
        candidateBarView.phoneticLabel.text = prefix + self.rimeContext.t9UserInputKey
      } else {
        // 如果是文本替换建议，且没有 RIME 输入，则不显示拼音标签
        // 或者显示文本替换的快捷短语？这里选择保持原逻辑，如果 userInputKey 为空则显示空
        candidateBarView.phoneticLabel.text = userInputKey
      }
    }
    .store(in: &subscriptions)
  }

  private func observeKeyboardState() {
    keyboardContext.keyboardTypePublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] keyboardType in
        guard let self = self else { return }
        let wasChinese = (self.lastKeyboardType?.isChinesePrimaryKeyboard ?? false) || (self.lastKeyboardType?.isChineseNineGrid ?? false)
        self.lastKeyboardType = keyboardType
        if (keyboardType.isChinesePrimaryKeyboard || keyboardType.isChineseNineGrid), !wasChinese {
          self.showCurrentTraditionalizeStateIfNeeded()
        }
      }
      .store(in: &subscriptions)

    NotificationCenter.default.publisher(for: RimeContext.rimeAsciiModeDidChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self = self else { return }
        let previous = self.lastAsciiModeSnapshot
        let current = self.rimeContext.asciiModeSnapshot
        self.lastAsciiModeSnapshot = current
        if previous && !current {
          self.showCurrentTraditionalizeStateIfNeeded()
        }
      }
      .store(in: &subscriptions)

    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateCenterIndicatorVisibility()
      }
      .store(in: &subscriptions)

    keyboardContext.$hasFullAccess
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.refreshWeatherIndicatorIfNeeded()
      }
      .store(in: &subscriptions)

    rimeContext.$optionState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] optionState in
        guard let self = self else { return }
        guard let optionState, self.isTraditionalizeOptionState(optionState) else { return }
        self.showTraditionalizeOptionState(self.currentTraditionalizeStateText())
      }
      .store(in: &subscriptions)
  }

  @objc func dismissKeyboardTouchDownAction() {
    dismissKeyboardButton.alpha = 0.62
  }

  @objc func dismissKeyboardTouchUpAction() {
    dismissKeyboardButton.alpha = 1
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  @objc func voiceModeTouchDownAction() {
    setTopToolbarButtonPressed(voiceModeButton, isPressed: true)
  }

  @objc func voiceModeTouchUpAction() {
    setTopToolbarButtonPressed(voiceModeButton, isPressed: false)
    if UserDefaults.hamster.enableKeyboardExtensionVoiceModeView {
      NotificationCenter.default.post(name: .hamsterVoiceModeToggle, object: nil)
      return
    }
    let requestId = voiceInputBridge.makeRequestId()
    voiceInputBridge.setState(requestId: requestId, state: .launching)
    guard let openURL = voiceInputBridge.makeDictationURL(requestId: requestId) else {
      voiceInputBridge.setState(requestId: requestId, state: .failed, errorMessage: "invalid dictation url")
      return
    }
    actionHandler.handle(.release, on: .url(openURL, id: "voiceDictation"))
  }

  @objc func canvasTouchDownAction() {
    setTopToolbarButtonPressed(canvasButton, isPressed: true)
  }

  @objc func canvasTouchUpAction() {
    setTopToolbarButtonPressed(canvasButton, isPressed: false)
    let requestId = canvasInputBridge.makeRequestId()
    canvasInputBridge.setState(requestId: requestId, state: .launching)
    guard let openURL = canvasInputBridge.makeCanvasURL(requestId: requestId) else {
      canvasInputBridge.setState(requestId: requestId, state: .failed, errorMessage: "invalid canvas url")
      return
    }
    actionHandler.handle(.release, on: .url(openURL, id: "canvasInput"))
  }

  @objc func markdownTouchDownAction() {
    setTopToolbarButtonPressed(markdownButton, isPressed: true)
  }

  @objc func markdownTouchUpAction() {
    setTopToolbarButtonPressed(markdownButton, isPressed: false)
    let requestId = canvasInputBridge.makeRequestId()
    canvasInputBridge.setState(requestId: requestId, state: .launching)
    guard let openURL = canvasInputBridge.makeMarkdownURL(requestId: requestId) else {
      canvasInputBridge.setState(requestId: requestId, state: .failed, errorMessage: "invalid markdown url")
      return
    }
    actionHandler.handle(.release, on: .url(openURL, id: "markdownInput"))
  }

  @objc func embeddedModuleTouchDownAction() {
    setTopToolbarButtonPressed(embeddedModuleButton, isPressed: true)
  }

  @objc func embeddedModuleTouchUpAction() {
    setTopToolbarButtonPressed(embeddedModuleButton, isPressed: false)
    if didTriggerEmbeddedModuleLongPress {
      didTriggerEmbeddedModuleLongPress = false
      return
    }
    guard let entry = embeddedModuleEntry else { return }
    if entry.makeInlineViewController != nil {
      NotificationCenter.default.post(
        name: KeyboardEmbeddedModuleNotification.toggle,
        object: nil,
        userInfo: [KeyboardEmbeddedModuleNotification.moduleIdentifierUserInfoKey: entry.moduleIdentifier]
      )
      return
    }
    guard let openURL = entry.makeLaunchURL() else { return }
    actionHandler.handle(.release, on: .url(openURL, id: "embeddedModule.\(entry.moduleIdentifier)"))
  }

  @objc private func handleEmbeddedModuleLongPress(_ sender: UILongPressGestureRecognizer) {
    guard let entry = embeddedModuleEntry else { return }
    switch sender.state {
    case .began:
      guard let openURL = entry.makeLaunchURL() else { return }
      didTriggerEmbeddedModuleLongPress = true
      setTopToolbarButtonPressed(embeddedModuleButton, isPressed: true)
      actionHandler.handle(.release, on: .url(openURL, id: "embeddedModule.longPress.\(entry.moduleIdentifier)"))
    case .ended, .cancelled, .failed:
      setTopToolbarButtonPressed(embeddedModuleButton, isPressed: false)
    default:
      break
    }
  }

  @objc func openHamsterAppTouchDownAction() {
    logoContainer.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func openHamsterAppTouchUpAction() {
    logoContainer.backgroundColor = style.toolbarButtonPressedBackgroundColor
    actionHandler.handle(.release, on: .url(URL(string: "nanomouse://com.XiangqingZHANG.nanomouse/main"), id: "openHamster"))
  }

  @objc func touchCancel() {
    didTriggerEmbeddedModuleLongPress = false
    dismissKeyboardButton.backgroundColor = .clear
    dismissKeyboardButton.alpha = 1
    logoContainer.backgroundColor = style.toolbarButtonBackgroundColor
    setTopToolbarButtonPressed(embeddedModuleButton, isPressed: false)
    setTopToolbarButtonPressed(canvasButton, isPressed: false)
    setTopToolbarButtonPressed(markdownButton, isPressed: false)
    setTopToolbarButtonPressed(voiceModeButton, isPressed: false)
  }

  private var canToggleTraditionalizationFromToolbar: Bool {
    guard !commonFunctionBar.isHidden else { return false }
    guard keyboardContext.keyboardType.isChinesePrimaryKeyboard || keyboardContext.keyboardType.isChineseNineGrid else { return false }
    guard rimeContext.currentSchema?.isJapaneseSchema != true else { return false }
    guard rimeContext.asciiModeSnapshot == false else { return false }
    return true
  }

  private var canSwitchOneHandModeFromToolbar: Bool {
    guard !commonFunctionBar.isHidden else { return false }
    return keyboardContext.keyboardType.supportsChineseOneHandToolbarSwitch
  }

  private var traditionalizeInteractionFrameInCommonBar: CGRect {
    guard commonFunctionBar.bounds.width > 1, commonFunctionBar.bounds.height > 1 else { return .null }

    let left: CGFloat
    if !weatherIndicatorContainer.isHidden, weatherIndicatorContainer.frame.maxX > 0 {
      left = weatherIndicatorContainer.frame.maxX + 2
    } else if keyboardContext.displayAppIconButton, logoContainer.frame.maxX > 0 {
      left = logoContainer.frame.maxX + 6
    } else {
      left = commonFunctionBar.bounds.minX + 8
    }

    let right = rightButtonsStack.frame.minX > 0
      ? rightButtonsStack.frame.minX - 2
      : traditionalizeHotspotView.frame.maxX
    let width = right - left
    if width >= 24 {
      return CGRect(
        x: left,
        y: commonFunctionBar.bounds.minY,
        width: width,
        height: commonFunctionBar.bounds.height
      )
    }

    let fallback = traditionalizeHotspotView.frame.insetBy(dx: -12, dy: -8)
    return fallback.intersection(commonFunctionBar.bounds)
  }

  private func traditionalizeHintText() -> String {
    return isTraditionalizationEnabled() ? "長按此處可切換繁簡" : "长按此处可切换繁简"
  }

  private func showTraditionalizeHintIfNeeded() {
    guard canToggleTraditionalizationFromToolbar else { return }
    traditionalizeHintWorkItem?.cancel()
    traditionalizeHintAllowsWeather = false
    traditionalizeHintLabel.text = traditionalizeHintText()
    traditionalizeHintLabel.isHidden = false
    weatherIndicatorContainer.isHidden = true
    UIView.animate(withDuration: 0.12) {
      self.traditionalizeHintLabel.alpha = 1
    }
    let workItem = DispatchWorkItem { [weak self] in
      self?.hideTraditionalizeHint(animated: true)
    }
    traditionalizeHintWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
  }

  private func showTraditionalizeOptionState(_ text: String) {
    traditionalizeHintWorkItem?.cancel()
    traditionalizeHintAllowsWeather = true
    traditionalizeHintLabel.text = text
    traditionalizeHintLabel.isHidden = false
    updateCenterIndicatorVisibility()
    UIView.animate(withDuration: 0.12) {
      self.traditionalizeHintLabel.alpha = 1
    }
    let workItem = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.hideTraditionalizeHint(animated: true)
      if let optionState = self.rimeContext.optionState,
         self.isTraditionalizeOptionState(optionState) {
        self.rimeContext.optionState = nil
      }
    }
    traditionalizeHintWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
  }

  private func showCurrentTraditionalizeStateIfNeeded() {
    guard canToggleTraditionalizationFromToolbar else { return }
    showTraditionalizeOptionState(currentTraditionalizeStateText())
  }

  private func currentTraditionalizeStateText() -> String {
    return isTraditionalizationEnabled() ? "繁" : "简"
  }

  private func isTraditionalizationEnabled() -> Bool {
    let simplifiedModeKey = keyboardContext.hamsterConfiguration?.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
    guard !simplifiedModeKey.isEmpty else { return false }
    return Rime.shared.simplifiedChineseMode(key: simplifiedModeKey)
  }

  private func hideTraditionalizeHint(animated: Bool) {
    traditionalizeHintWorkItem?.cancel()
    traditionalizeHintWorkItem = nil
    guard !traditionalizeHintLabel.isHidden else { return }
    let hide = {
      self.traditionalizeHintLabel.alpha = 0
    }
    let completion: (Bool) -> Void = { _ in
      self.traditionalizeHintLabel.isHidden = true
      self.traditionalizeHintAllowsWeather = false
      self.updateCenterIndicatorVisibility()
    }
    if animated {
      UIView.animate(withDuration: 0.12, animations: hide, completion: completion)
    } else {
      hide()
      traditionalizeHintLabel.isHidden = true
      traditionalizeHintAllowsWeather = false
      updateCenterIndicatorVisibility()
    }
  }

  private func isTraditionalizeOptionState(_ text: String) -> Bool {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return value == "简" || value == "簡" || value == "繁"
  }

  private func weatherIndicatorPresentation() -> WeatherIndicatorPresentation? {
    guard keyboardContext.hamsterConfiguration?.toolbar?.enableWeatherIndicator ?? true else { return nil }
    let locationMode = keyboardContext.hamsterConfiguration?.toolbar?.weatherIndicatorLocationMode ?? .currentLocation
    let fixedLocationName = keyboardContext.hamsterConfiguration?.toolbar?.weatherIndicatorFixedLocationName
    let fixedLatitude = keyboardContext.hamsterConfiguration?.toolbar?.weatherIndicatorFixedLatitude
    let fixedLongitude = keyboardContext.hamsterConfiguration?.toolbar?.weatherIndicatorFixedLongitude
    let metric = keyboardContext.hamsterConfiguration?.toolbar?.weatherIndicatorMetric ?? .temperature
    if let cache = UserDefaults.hamster.keyboardWeatherIndicatorCache,
       cache.isDisplayable(
         enabled: true,
         locationMode: locationMode,
         fixedLocationName: fixedLocationName,
         fixedLatitude: fixedLatitude,
         fixedLongitude: fixedLongitude
       )
    {
      return WeatherIndicatorPresentation(symbolName: cache.symbolName, text: compactWeatherIndicatorText(from: cache, metric: metric))
    }
    return WeatherIndicatorPresentation(symbolName: "arrow.clockwise", text: "天气")
  }

  private func compactWeatherIndicatorText(from cache: KeyboardWeatherIndicatorCache, metric: KeyboardWeatherIndicatorMetric) -> String {
    switch metric {
    case .temperature:
      return "\(Int(cache.temperatureCelsius.rounded()))°"
    case .apparentTemperature:
      return "\(Int(cache.apparentTemperatureCelsius.rounded()))°"
    case .uvIndex:
      return "\(cache.uvIndexValue)"
    case .humidity:
      return "\(Int((cache.humidityFraction * 100).rounded()))%"
    }
  }

  private func updateCenterIndicatorVisibility() {
    guard !commonFunctionBar.isHidden else {
      weatherIndicatorContainer.isHidden = true
      traditionalizeHotspotView.isHidden = true
      stopDiaryIndicatorBlinking()
      return
    }
    traditionalizeHotspotView.isHidden = false
    guard traditionalizeHintLabel.isHidden || traditionalizeHintAllowsWeather else {
      weatherIndicatorContainer.isHidden = true
      return
    }
    guard let presentation = weatherIndicatorPresentation() else {
      weatherIndicatorContainer.isHidden = true
      return
    }
    weatherIndicatorLabel.text = presentation.text
    weatherIndicatorIconView.image = UIImage(systemName: presentation.symbolName) ?? UIImage(systemName: "cloud.sun")
    weatherIndicatorContainer.isHidden = false
    updateDiaryRecordingIndicatorAppearance()
  }

  private func updateDiaryRecordingIndicatorAppearance() {
    let isRecording = UserDefaults.hamster.keyboardDiaryModeEnabled
    let tintColor = isRecording ? UIColor.systemRed : style.candidateTextColor
    weatherIndicatorLabel.textColor = tintColor
    weatherIndicatorIconView.tintColor = tintColor
    if isRecording {
      startDiaryIndicatorBlinking()
    } else {
      stopDiaryIndicatorBlinking()
    }
  }

  private func startDiaryIndicatorBlinking() {
    guard !isDiaryIndicatorBlinking, !weatherIndicatorContainer.isHidden else { return }
    isDiaryIndicatorBlinking = true
    weatherIndicatorContainer.layer.removeAnimation(forKey: "NanoMouseDiaryRecordingBlink")
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 1.0
    animation.toValue = 0.35
    animation.duration = 1.2
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    weatherIndicatorContainer.layer.add(animation, forKey: "NanoMouseDiaryRecordingBlink")
  }

  private func stopDiaryIndicatorBlinking() {
    isDiaryIndicatorBlinking = false
    weatherIndicatorContainer.layer.removeAnimation(forKey: "NanoMouseDiaryRecordingBlink")
    weatherIndicatorContainer.alpha = 1
    weatherIndicatorContainer.layer.opacity = 1
  }

  @objc private func openWeatherIndicatorSettings() {
    if didTriggerDiaryModeLongPress {
      didTriggerDiaryModeLongPress = false
      return
    }
    actionHandler.handle(
      .release,
      on: .url(
        URL(string: "nanomouse://com.XiangqingZHANG.nanomouse/keyboardSettings?subView=toolbar&focus=weatherIndicator"),
        id: "openWeatherIndicatorSettings")
    )
  }

  @objc private func handleDiaryModeLongPress(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began else { return }
    didTriggerDiaryModeLongPress = true
    let newValue = !UserDefaults.hamster.keyboardDiaryModeEnabled
    UserDefaults.hamster.keyboardDiaryModeEnabled = newValue
    if newValue {
      UserDefaults.hamster.keyboardDiaryFirstEnableAcknowledged = true
    }
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
    updateDiaryRecordingIndicatorAppearance()
    showTraditionalizeOptionState(newValue ? "日记·本地" : "日记已关闭")
  }

  @objc private func handleTraditionalizeLongPress(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began else { return }
    guard canToggleTraditionalizationFromToolbar else { return }
    let simplifiedModeKey = keyboardContext.hamsterConfiguration?.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
    guard !simplifiedModeKey.isEmpty else { return }

    // 振动反馈
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()

    actionHandler.handle(.release, on: .shortCommand(.simplifiedTraditionalSwitch))
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.showTraditionalizeOptionState(self.currentTraditionalizeStateText())
    }
  }

  @objc private func handleTraditionalizeAreaSwipe(_ sender: UISwipeGestureRecognizer) {
    guard sender.state == .ended else { return }
    guard canSwitchOneHandModeFromToolbar else { return }
    let current = UserDefaults.hamster.chineseKeyboardOneHandMode
    let target: ChineseKeyboardOneHandMode
    switch sender.direction {
    case .left:
      target = current == .rightArc ? .off : .leftArc
    case .right:
      target = current == .leftArc ? .off : .rightArc
    default:
      return
    }
    applyChineseOneHandMode(target, label: chineseOneHandModeLabel(target))
  }

  private func applyChineseOneHandMode(_ mode: ChineseKeyboardOneHandMode, label: String) {
    guard UserDefaults.hamster.chineseKeyboardOneHandMode != mode else { return }
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
    UserDefaults.hamster.chineseKeyboardOneHandMode = mode
    NotificationCenter.default.post(name: .hamsterChineseKeyboardOneHandModeDidChange, object: self)
    showTraditionalizeOptionState(label)
  }

  private func chineseOneHandModeLabel(_ mode: ChineseKeyboardOneHandMode) -> String {
    switch mode {
    case .leftArc:
      return "左手"
    case .off:
      return "双手"
    case .rightArc:
      return "右手"
    }
  }
}

extension KeyboardToolbarView: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    if gestureRecognizer === traditionalizeLongPressGesture {
      guard canToggleTraditionalizationFromToolbar else { return false }
    } else if gestureRecognizer === oneHandLeftSwipeGesture || gestureRecognizer === oneHandRightSwipeGesture {
      guard canSwitchOneHandModeFromToolbar else { return false }
    } else {
      return true
    }

    let point = touch.location(in: commonFunctionBar)
    return traditionalizeInteractionFrameInCommonBar.contains(point)
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    let toolbarGestures: Set<UIGestureRecognizer> = [
      traditionalizeLongPressGesture,
      oneHandLeftSwipeGesture,
      oneHandRightSwipeGesture,
    ]
    return toolbarGestures.contains(gestureRecognizer) && toolbarGestures.contains(otherGestureRecognizer)
  }
}

final class VoiceModeIconView: UIView {
  private let ringLayer = CAShapeLayer()
  private let coreLayer = CAShapeLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.addSublayer(ringLayer)
    layer.addSublayer(coreLayer)
    ringLayer.fillColor = UIColor.clear.cgColor
    coreLayer.fillColor = UIColor.clear.cgColor
    ringLayer.lineWidth = 1.6
    coreLayer.lineWidth = 1.4
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let size = min(bounds.width, bounds.height)
    let ringInset = size * 0.12
    let ringRect = bounds.insetBy(dx: ringInset, dy: ringInset)
    ringLayer.path = UIBezierPath(ovalIn: ringRect).cgPath

    let coreSize = size * 0.34
    let coreRect = CGRect(
      x: (bounds.width - coreSize) / 2,
      y: (bounds.height - coreSize) / 2,
      width: coreSize,
      height: coreSize
    )
    let coreRadius = coreSize * 0.22
    coreLayer.path = UIBezierPath(roundedRect: coreRect, cornerRadius: coreRadius).cgPath
  }

  func applyColor(_ color: UIColor) {
    ringLayer.strokeColor = color.cgColor
    coreLayer.strokeColor = color.cgColor
  }
}
