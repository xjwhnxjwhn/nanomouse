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
  private var style: CandidateBarStyle
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var oldBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()
  private var lastKeyboardType: KeyboardType?
  private var lastAsciiModeSnapshot: Bool = false
  private var traditionalizeHintWorkItem: DispatchWorkItem?

  /// 用户引导相关属性
  private var currentTipIndex = 0
  private var tipTimer: Timer?
  private var userGuideSuppressedByTraditionalize = false

  private lazy var traditionalizeLongPressGesture: UILongPressGestureRecognizer = {
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleTraditionalizeLongPress(_:)))
    recognizer.minimumPressDuration = keyboardContext.longPressDelay ?? GestureButtonDefaults.longPressDelay
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = self
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

  /// 用户引导提示标签
  private lazy var userGuideLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.7
    label.alpha = 0
    label.isUserInteractionEnabled = false
    return label
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
    button.setImage(UIImage(systemName: "chevron.down.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(dismissKeyboardTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
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

  func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    commonFunctionBar.addGestureRecognizer(traditionalizeLongPressGesture)
    setupUserGuide()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      setupAppearance()
      candidateBarView.setStyle(self.style)
    }
    
    // Ensure logo image is also rounded if it has a background
    let radius = logoImageView.bounds.height * 0.2237
    logoImageView.layer.cornerRadius = radius
    logoImageView.layer.cornerCurve = .continuous
  }

  override func constructViewHierarchy() {
    addSubview(commonFunctionBar)
    if keyboardContext.displayAppIconButton {
      commonFunctionBar.addSubview(logoContainer)
      logoContainer.addSubview(logoImageView)
      logoContainer.addSubview(iconButton)
    }
    if keyboardContext.displayKeyboardDismissButton {
      commonFunctionBar.addSubview(dismissKeyboardButton)
    }
    commonFunctionBar.addSubview(traditionalizeHintLabel)
    commonFunctionBar.addSubview(userGuideLabel)
  }

  override func activateViewConstraints() {
    var constraints: [NSLayoutConstraint] = [
      commonFunctionBar.topAnchor.constraint(equalTo: topAnchor),
      commonFunctionBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      commonFunctionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      commonFunctionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
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

    if keyboardContext.displayKeyboardDismissButton {
      constraints.append(contentsOf: [
        dismissKeyboardButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        dismissKeyboardButton.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
        dismissKeyboardButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: dismissKeyboardButton.bottomAnchor),
        dismissKeyboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    constraints.append(contentsOf: [
      traditionalizeHintLabel.centerXAnchor.constraint(equalTo: commonFunctionBar.centerXAnchor),
      traditionalizeHintLabel.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      traditionalizeHintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: commonFunctionBar.leadingAnchor, constant: 8),
      traditionalizeHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.trailingAnchor, constant: -8),
    ])

    // 用户引导标签约束
    constraints.append(contentsOf: [
      userGuideLabel.centerXAnchor.constraint(equalTo: commonFunctionBar.centerXAnchor),
      userGuideLabel.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      userGuideLabel.leadingAnchor.constraint(greaterThanOrEqualTo: commonFunctionBar.leadingAnchor, constant: 8),
      userGuideLabel.trailingAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.trailingAnchor, constant: -8),
    ])

    NSLayoutConstraint.activate(constraints)
  }

  override func setupAppearance() {
    self.style = appearance.candidateBarStyle
    if keyboardContext.displayAppIconButton {
      // iconButton.tintColor = style.toolbarButtonFrontColor // Button is now touch overlay, icon is in ImageView
      logoContainer.backgroundColor = style.toolbarButtonBackgroundColor
    }
    if keyboardContext.displayKeyboardDismissButton {
      dismissKeyboardButton.tintColor = style.toolbarButtonFrontColor
    }
    let hintFontSize = max(style.phoneticTextFont.pointSize - 1, 9)
    traditionalizeHintLabel.font = style.phoneticTextFont.withSize(hintFontSize)
    traditionalizeHintLabel.textColor = style.candidateTextColor

    // 用户引导标签样式（字体为候选字体的一半大小）
    let guideFontSize = style.candidateTextFont.pointSize * 0.5
    userGuideLabel.font = style.candidateTextFont.withSize(guideFontSize)
    userGuideLabel.textColor = style.candidateTextColor.withAlphaComponent(0.6)
  }

  func combine() {
    Publishers.CombineLatest(
      rimeContext.userInputKeyPublished,
      rimeContext.$textReplacementSuggestions
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] userInputKey, textReplacementSuggestions in
      guard let self = self else { return }
      
      // 有 RIME 输入或有文本替换建议时，显示候选栏
      let hasContent = !userInputKey.isEmpty || !textReplacementSuggestions.isEmpty
      let isEmpty = !hasContent
      
      self.commonFunctionBar.isHidden = !isEmpty
      self.candidateBarView.isHidden = isEmpty
      if hasContent {
        self.hideTraditionalizeHint(animated: false)
      }

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
        let wasChinese = self.lastKeyboardType?.isChinesePrimaryKeyboard ?? false
        self.lastKeyboardType = keyboardType
        if keyboardType.isChinesePrimaryKeyboard, !wasChinese {
          self.showTraditionalizeHintIfNeeded()
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
          self.showTraditionalizeHintIfNeeded()
        }
      }
      .store(in: &subscriptions)
  }

  @objc func dismissKeyboardTouchDownAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func dismissKeyboardTouchUpAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  @objc func openHamsterAppTouchDownAction() {
    logoContainer.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func openHamsterAppTouchUpAction() {
    logoContainer.backgroundColor = style.toolbarButtonPressedBackgroundColor
    actionHandler.handle(.release, on: .url(URL(string: "nanomouse://com.XiangqingZHANG.nanomouse/main"), id: "openHamster"))
  }

  @objc func touchCancel() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    logoContainer.backgroundColor = style.toolbarButtonBackgroundColor
  }

  private var canToggleTraditionalizationFromToolbar: Bool {
    guard !commonFunctionBar.isHidden else { return false }
    guard keyboardContext.keyboardType.isChinesePrimaryKeyboard else { return false }
    guard rimeContext.currentSchema?.isJapaneseSchema != true else { return false }
    guard rimeContext.asciiModeSnapshot == false else { return false }
    guard rimeContext.userInputKey.isEmpty else { return false }
    guard rimeContext.textReplacementSuggestions.isEmpty else { return false }
    return true
  }

  private func traditionalizeHintText() -> String {
    let simplifiedModeKey = keyboardContext.hamsterConfiguration?.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
    let isSimplified = simplifiedModeKey.isEmpty ? true : Rime.shared.simplifiedChineseMode(key: simplifiedModeKey)
    return isSimplified ? "长按此处可切换繁简" : "長按此處可切換繁簡"
  }

  private func showTraditionalizeHintIfNeeded() {
    guard canToggleTraditionalizationFromToolbar else { return }
    if tipTimer != nil {
      userGuideSuppressedByTraditionalize = true
      stopUserGuide()
    } else {
      userGuideSuppressedByTraditionalize = true
    }
    traditionalizeHintWorkItem?.cancel()
    traditionalizeHintLabel.text = traditionalizeHintText()
    traditionalizeHintLabel.isHidden = false
    UIView.animate(withDuration: 0.12) {
      self.traditionalizeHintLabel.alpha = 1
    }
    let workItem = DispatchWorkItem { [weak self] in
      self?.hideTraditionalizeHint(animated: true)
    }
    traditionalizeHintWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
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
      if self.userGuideSuppressedByTraditionalize {
        self.userGuideSuppressedByTraditionalize = false
        self.startUserGuide()
      }
    }
    if animated {
      UIView.animate(withDuration: 0.12, animations: hide, completion: completion)
    } else {
      hide()
      traditionalizeHintLabel.isHidden = true
      if userGuideSuppressedByTraditionalize {
        userGuideSuppressedByTraditionalize = false
        startUserGuide()
      }
    }
  }

  @objc private func handleTraditionalizeLongPress(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began else { return }
    guard canToggleTraditionalizationFromToolbar else { return }
    let simplifiedModeKey = keyboardContext.hamsterConfiguration?.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
    guard !simplifiedModeKey.isEmpty else { return }

    // 振动反馈
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()

    rimeContext.switchTraditionalSimplifiedChinese(simplifiedModeKey)
  }

  // MARK: - 用户引导相关方法

  /// 设置用户引导
  private func setupUserGuide() {
    // 检查是否启用用户引导
    guard keyboardContext.hamsterConfiguration?.toolbar?.enableUserGuideScrolling ?? true else {
      return
    }
    // 启动用户引导
    startUserGuide()
  }

  /// 启动用户引导
  private func startUserGuide() {
    guard tipTimer == nil else { return }
    guard traditionalizeHintLabel.isHidden else { return }
    showCurrentTip()
    tipTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
      self?.fadeToNextTip()
    }
  }

  /// 停止用户引导
  private func stopUserGuide() {
    tipTimer?.invalidate()
    tipTimer = nil
    UIView.animate(withDuration: 0.2) {
      self.userGuideLabel.alpha = 0
    }
  }

  /// 显示当前提示
  private func showCurrentTip() {
    let tipText = UserGuideTips.tip(at: currentTipIndex)
    userGuideLabel.text = tipText
    UIView.animate(withDuration: 0.3) {
      self.userGuideLabel.alpha = 1.0
    }
  }

  /// 淡入淡出切换到下一条提示
  private func fadeToNextTip() {
    UIView.animate(withDuration: 0.3, animations: {
      self.userGuideLabel.alpha = 0
    }) { _ in
      self.currentTipIndex = (self.currentTipIndex + 1) % UserGuideTips.count
      self.userGuideLabel.text = UserGuideTips.tip(at: self.currentTipIndex)
      UIView.animate(withDuration: 0.3) {
        self.userGuideLabel.alpha = 1.0
      }
    }
  }
}

extension KeyboardToolbarView: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard gestureRecognizer === traditionalizeLongPressGesture else { return true }
    let point = touch.location(in: commonFunctionBar)
    if keyboardContext.displayAppIconButton, logoContainer.frame.contains(point) {
      return false
    }
    if keyboardContext.displayKeyboardDismissButton, dismissKeyboardButton.frame.contains(point) {
      return false
    }
    return true
  }
}
