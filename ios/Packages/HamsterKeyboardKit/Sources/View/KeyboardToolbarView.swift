//
//  KeyboardToolbarView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
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

  private lazy var traditionalizeLongPressGesture: UILongPressGestureRecognizer = {
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleTraditionalizeLongPress(_:)))
    recognizer.minimumPressDuration = keyboardContext.longPressDelay ?? GestureButtonDefaults.longPressDelay
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = self
    return recognizer
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

    super.init(frame: .zero)

    setupSubview()

    combine()
  }

  func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    commonFunctionBar.addGestureRecognizer(traditionalizeLongPressGesture)
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

      if self.candidateBarView.superview == nil {
        candidateBarView.setStyle(self.style)
        addSubview(candidateBarView)
        candidateBarView.fillSuperview()
      }

      // 检测是否启用内嵌编码
      guard !keyboardContext.enableEmbeddedInputMode else { return }
      if self.keyboardContext.keyboardType.isChineseNineGrid {
        // Debug
        // self.phoneticArea.text = inputKeys + " | " + self.rimeContext.t9UserInputKey
        candidateBarView.phoneticLabel.text = self.rimeContext.t9UserInputKey
      } else {
        // 如果是文本替换建议，且没有 RIME 输入，则不显示拼音标签
        // 或者显示文本替换的快捷短语？这里选择保持原逻辑，如果 userInputKey 为空则显示空
        candidateBarView.phoneticLabel.text = userInputKey
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

  @objc private func handleTraditionalizeLongPress(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began else { return }
    guard canToggleTraditionalizationFromToolbar else { return }
    let simplifiedModeKey = keyboardContext.hamsterConfiguration?.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
    guard !simplifiedModeKey.isEmpty else { return }
    rimeContext.switchTraditionalSimplifiedChinese(simplifiedModeKey)
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
