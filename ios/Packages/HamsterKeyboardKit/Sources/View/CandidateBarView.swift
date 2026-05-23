//
//  CandidateWordsView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
import OSLog
import UIKit

/**
 候选栏视图
 */
public class CandidateBarView: NibLessView {
  /// 候选区状态
  public enum State {
    /// 展开
    case expand
    /// 收起
    case collapse

    func isCollapse() -> Bool {
      return self == .collapse
    }
  }

  private var style: CandidateBarStyle
  private var actionHandler: KeyboardActionHandler
  private var keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var subscriptions = Set<AnyCancellable>()
  private var textReplacementBubbleView: UIView?
  private weak var textReplacementBubbleContentView: UIView?
  private var textReplacementBubbleCandidates: [CandidateSuggestion] = []

  /// 拼音Label
  lazy var phoneticLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.textAlignment = .left
    label.numberOfLines = 1
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 划动分页的候选文字区域
  lazy var candidatesArea: CandidateWordsCollectionView = {
    let view = CandidateWordsCollectionView(
      style: style,
      keyboardContext: keyboardContext,
      actionHandler: actionHandler,
      rimeContext: rimeContext)
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 手动分页的候选文字区域
  lazy var candidatesPagingArea: CandidatesPagingCollectionView = {
    let view = CandidatesPagingCollectionView(
      style: style,
      keyboardContext: keyboardContext,
      actionHandler: actionHandler,
      rimeContext: rimeContext)
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 状态图片视图
  lazy var stateImageView: UIImageView = {
    let view = UIImageView(frame: .zero)
    view.contentMode = .center
    view.translatesAutoresizingMaskIntoConstraints = false
    view.image = stateImage(.collapse)
    return view
  }()

  /// 竖线
  lazy var verticalLine: UIView = {
    let view = UIView(frame: .zero)
    view.backgroundColor = .secondarySystemFill
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 候选区展开或收起控制按钮
  lazy var controlStateView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.addSubview(stateImageView)
    view.addSubview(verticalLine)

    NSLayoutConstraint.activate([
      verticalLine.topAnchor.constraint(equalTo: view.topAnchor, constant: 3),
      view.bottomAnchor.constraint(equalTo: verticalLine.bottomAnchor, constant: 3),
      view.leadingAnchor.constraint(equalTo: verticalLine.leadingAnchor),
      verticalLine.widthAnchor.constraint(equalToConstant: 1),

      stateImageView.leadingAnchor.constraint(equalTo: verticalLine.trailingAnchor),
      stateImageView.topAnchor.constraint(equalTo: view.topAnchor),
      stateImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stateImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])

    // 添加状态控制
    view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(changeState)))
    return view
  }()

  private lazy var textReplacementButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.tintColor = style.toolbarButtonFrontColor
    button.setImage(UIImage(systemName: "text.bubble") ?? UIImage(systemName: "quote.bubble"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(pointSize: 16, weight: .regular, scale: .default), forImageIn: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.contentEdgeInsets = .init(top: 6, left: 8, bottom: 6, right: 8)
    button.layer.cornerRadius = 6
    button.layer.cornerCurve = .continuous
    button.isHidden = true
    button.accessibilityLabel = "快捷短语"
    button.accessibilityIdentifier = "nanomouse_keyboard_text_replacement_button"
    button.addTarget(self, action: #selector(toggleTextReplacementBubble), for: .touchUpInside)
    return button
  }()

  private lazy var rightControlsStackView: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .fill
    stack.distribution = .fill
    stack.spacing = 0
    stack.setContentCompressionResistancePriority(.required, for: .horizontal)
    stack.setContentHuggingPriority(.required, for: .horizontal)
    return stack
  }()

  // MARK: - 计算属性

  /// 布局配置
  private var layoutConfig: KeyboardLayoutConfiguration {
    .standard(for: keyboardContext)
  }

  private var showsFocusLine: Bool {
    !keyboardContext.enableEmbeddedInputMode || rimeContext.prefersTwoTierCandidateBar
  }

  private var focusLineHeight: CGFloat {
    let base = keyboardContext.heightOfCodingArea
    return rimeContext.prefersTwoTierCandidateBar ? base * 2 : base
  }

  private var effectiveToolbarHeight: CGFloat {
    keyboardContext.heightOfToolbar + (rimeContext.prefersTwoTierCandidateBar ? keyboardContext.heightOfCodingArea : 0)
  }

  init(style: CandidateBarStyle, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.style = style
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupContentView()
    observeTextReplacementSuggestions()
  }

  func setupContentView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  /// 构建视图层次
  override public func constructViewHierarchy() {
    // 非内嵌模式或双行候选栏时添加拼写区域
    if showsFocusLine {
      addSubview(phoneticLabel)
    }
    if keyboardContext.swipePaging {
      addSubview(candidatesArea)
    } else {
      addSubview(candidatesPagingArea)
    }
    addSubview(rightControlsStackView)
    rightControlsStackView.addArrangedSubview(textReplacementButton)
    if keyboardContext.swipePaging {
      rightControlsStackView.addArrangedSubview(controlStateView)
    }
  }

  /// 激活视图约束
  override public func activateViewConstraints() {
    let buttonInsets = layoutConfig.buttonInsets
    let focusLineHeight = showsFocusLine ? self.focusLineHeight : 0
    let controlStateHeight: CGFloat = effectiveToolbarHeight - focusLineHeight
    let candidatesView = keyboardContext.swipePaging ? candidatesArea : candidatesPagingArea
    let candidateRowTopAnchor: NSLayoutYAxisAnchor = showsFocusLine ? phoneticLabel.bottomAnchor : topAnchor
    var constraints: [NSLayoutConstraint] = []

    if showsFocusLine {
      constraints.append(contentsOf: [
        phoneticLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
        phoneticLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        phoneticLabel.topAnchor.constraint(equalTo: topAnchor),
        phoneticLabel.heightAnchor.constraint(equalToConstant: focusLineHeight),
      ])
    }

    constraints.append(contentsOf: [
      candidatesView.topAnchor.constraint(equalTo: candidateRowTopAnchor),
      candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
      candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
      candidatesView.trailingAnchor.constraint(equalTo: rightControlsStackView.leadingAnchor, constant: -buttonInsets.right),

      rightControlsStackView.topAnchor.constraint(equalTo: candidateRowTopAnchor),
      rightControlsStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
      rightControlsStackView.heightAnchor.constraint(equalToConstant: controlStateHeight),
      textReplacementButton.heightAnchor.constraint(equalTo: rightControlsStackView.heightAnchor),
    ])

    if keyboardContext.swipePaging {
      constraints.append(contentsOf: [
        controlStateView.heightAnchor.constraint(equalTo: rightControlsStackView.heightAnchor),
        controlStateView.widthAnchor.constraint(equalTo: controlStateView.heightAnchor),
      ])
    }

    NSLayoutConstraint.activate(constraints)
  }

  override public func setupAppearance() {
    phoneticLabel.font = style.phoneticTextFont
    phoneticLabel.textColor = style.phoneticTextColor
    if rimeContext.prefersTwoTierCandidateBar {
      phoneticLabel.numberOfLines = 2
      phoneticLabel.lineBreakMode = .byCharWrapping
    } else {
      phoneticLabel.numberOfLines = 1
      phoneticLabel.lineBreakMode = .byTruncatingTail
    }
    stateImageView.tintColor = style.candidateTextColor
    textReplacementButton.tintColor = style.toolbarButtonFrontColor
    textReplacementButton.backgroundColor = style.toolbarButtonBackgroundColor

    if keyboardContext.swipePaging {
      candidatesArea.setupStyle(style)
    } else {
      candidatesPagingArea.setupStyle(style)
    }
  }

  func setStyle(_ style: CandidateBarStyle) {
    self.style = style
    setupAppearance()
  }

  @objc func changeState() {
    let state: State = keyboardContext.candidatesViewState.isCollapse() ? .expand : .collapse
    stateImageView.image = stateImage(state)
    verticalLine.isHidden = state == .expand
    keyboardContext.candidatesViewState = state
  }

  private func observeTextReplacementSuggestions() {
    rimeContext.$textReplacementSuggestions
      .receive(on: DispatchQueue.main)
      .sink { [weak self] suggestions in
        guard let self = self else { return }
        self.textReplacementButton.isHidden = suggestions.isEmpty
        self.setNeedsLayout()
        if suggestions.isEmpty {
          self.hideTextReplacementBubble()
        } else if self.textReplacementBubbleView?.superview != nil {
          self.showTextReplacementBubble()
        }
      }
      .store(in: &subscriptions)
  }

  @objc private func toggleTextReplacementBubble() {
    actionHandler.handle(.press, on: .character(""))
    guard !rimeContext.textReplacementSuggestions.isEmpty else {
      hideTextReplacementBubble()
      return
    }
    if textReplacementBubbleView?.superview != nil {
      hideTextReplacementBubble()
    } else {
      showTextReplacementBubble()
    }
  }

  private func showTextReplacementBubble() {
    hideTextReplacementBubble()

    let candidates = rimeContext.textReplacementSuggestions
    guard !candidates.isEmpty else { return }
    guard let hostView = textReplacementBubbleHostView() else { return }
    textReplacementBubbleCandidates = candidates
    hostView.layoutIfNeeded()
    layoutIfNeeded()

    let overlayView = TextReplacementBubbleOverlayView(frame: hostView.bounds)
    overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlayView.backgroundColor = .clear
    overlayView.onOutsideTap = { [weak self] in
      self?.hideTextReplacementBubble()
    }

    let bubbleView = UIView(frame: .zero)
    bubbleView.backgroundColor = .clear
    bubbleView.layer.cornerCurve = .continuous
    bubbleView.layer.shadowColor = UIColor.black.cgColor
    bubbleView.layer.shadowOpacity = userInterfaceStyle == .dark ? 0.45 : 0.24
    bubbleView.layer.shadowRadius = 14
    bubbleView.layer.shadowOffset = CGSize(width: 0, height: 6)
    bubbleView.accessibilityIdentifier = "nanomouse_keyboard_text_replacement_bubble"

    let effectView = UIVisualEffectView(effect: textReplacementBubbleEffect())
    effectView.translatesAutoresizingMaskIntoConstraints = false
    effectView.layer.cornerRadius = 14
    effectView.layer.cornerCurve = .continuous
    effectView.layer.masksToBounds = true

    let tintView = UIView(frame: .zero)
    tintView.translatesAutoresizingMaskIntoConstraints = false
    tintView.backgroundColor = textReplacementBubbleTintColor()
    tintView.isUserInteractionEnabled = false

    let strokeView = UIView(frame: .zero)
    strokeView.translatesAutoresizingMaskIntoConstraints = false
    strokeView.backgroundColor = .clear
    strokeView.layer.cornerRadius = 14
    strokeView.layer.cornerCurve = .continuous
    strokeView.layer.borderWidth = 1 / UIScreen.main.scale
    strokeView.layer.borderColor = textReplacementBubbleStrokeColor().cgColor
    strokeView.isUserInteractionEnabled = false

    let scrollView = UIScrollView(frame: .zero)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.backgroundColor = .clear
    scrollView.showsVerticalScrollIndicator = candidates.count > 4
    scrollView.alwaysBounceVertical = false

    let stackView = UIStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .fill
    stackView.distribution = .fill
    stackView.spacing = 0

    for (index, candidate) in candidates.enumerated() {
      let button = UIButton(type: .custom)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.tag = index
      button.backgroundColor = .clear
      button.setTitle(candidate.title, for: .normal)
      button.setTitleColor(textReplacementBubbleTextColor(), for: .normal)
      button.titleLabel?.font = style.candidateTextFont
      button.titleLabel?.numberOfLines = 2
      button.titleLabel?.lineBreakMode = .byTruncatingTail
      button.contentHorizontalAlignment = .left
      button.contentEdgeInsets = .init(top: 8, left: 10, bottom: 8, right: 10)
      button.addTarget(self, action: #selector(selectTextReplacementBubbleCandidate(_:)), for: .touchUpInside)
      stackView.addArrangedSubview(button)
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true

      if index < candidates.count - 1 {
        let separator = UIView(frame: .zero)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = textReplacementBubbleSeparatorColor()
        stackView.addArrangedSubview(separator)
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
      }
    }

    bubbleView.addSubview(effectView)
    effectView.contentView.addSubview(tintView)
    effectView.contentView.addSubview(scrollView)
    effectView.contentView.addSubview(strokeView)
    scrollView.addSubview(stackView)
    overlayView.addSubview(bubbleView)
    overlayView.bubbleView = bubbleView
    hostView.addSubview(overlayView)
    hostView.bringSubviewToFront(overlayView)

    let availableWidth = overlayView.bounds.width > 0 ? overlayView.bounds.width : UIScreen.main.bounds.width
    let bubbleWidth = max(200, min(availableWidth - 16, 340))
    let rowHeight: CGFloat = 43
    let separatorHeight = CGFloat(max(candidates.count - 1, 0)) / UIScreen.main.scale
    let bubbleHeight = min(CGFloat(candidates.count) * rowHeight + separatorHeight + 12, 220)
    let buttonFrame = textReplacementButton.convert(textReplacementButton.bounds, to: overlayView)
    let bubbleX = max(8, min(buttonFrame.maxX - bubbleWidth, overlayView.bounds.width - bubbleWidth - 8))
    let preferredY = buttonFrame.maxY + 4
    let bubbleY = min(preferredY, max(8, overlayView.bounds.height - bubbleHeight - 8))
    bubbleView.frame = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
    bubbleView.autoresizingMask = []

    NSLayoutConstraint.activate([
      effectView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
      effectView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
      effectView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),

      tintView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
      tintView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
      tintView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
      tintView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),

      scrollView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: 6),
      scrollView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -6),
      scrollView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),

      strokeView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
      strokeView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
      strokeView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
      strokeView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),

      stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
    ])

    textReplacementBubbleView = overlayView
    textReplacementBubbleContentView = bubbleView
  }

  private func hideTextReplacementBubble() {
    textReplacementBubbleView?.removeFromSuperview()
    textReplacementBubbleView = nil
    textReplacementBubbleContentView = nil
    textReplacementBubbleCandidates = []
  }

  private func textReplacementBubbleHostView() -> UIView? {
    var host: UIView = self
    while let next = host.superview, !(next is UIWindow) {
      host = next
    }
    return host.superview == nil ? window : host
  }

  private func textReplacementBubbleEffect() -> UIVisualEffect {
    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .regular)
      effect.tintColor = userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.16)
        : UIColor.white.withAlphaComponent(0.34)
      effect.isInteractive = true
      return effect
    }
    return UIBlurEffect(style: userInterfaceStyle == .dark ? .systemThickMaterialDark : .systemThickMaterialLight)
  }

  private func textReplacementBubbleTintColor() -> UIColor {
    if #available(iOS 26.0, *) {
      return userInterfaceStyle == .dark
        ? UIColor.black.withAlphaComponent(0.22)
        : UIColor.white.withAlphaComponent(0.18)
    }
    return userInterfaceStyle == .dark
      ? UIColor.black.withAlphaComponent(0.36)
      : UIColor.white.withAlphaComponent(0.42)
  }

  private func textReplacementBubbleStrokeColor() -> UIColor {
    userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.22)
      : UIColor.white.withAlphaComponent(0.62)
  }

  private func textReplacementBubbleSeparatorColor() -> UIColor {
    userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.14)
      : UIColor.black.withAlphaComponent(0.10)
  }

  private func textReplacementBubbleTextColor() -> UIColor {
    userInterfaceStyle == .dark ? .white : .label
  }

  @objc private func selectTextReplacementBubbleCandidate(_ sender: UIButton) {
    guard sender.tag >= 0, sender.tag < textReplacementBubbleCandidates.count else { return }
    actionHandler.handle(.press, on: .character(""))
    let candidate = textReplacementBubbleCandidates[sender.tag]
    hideTextReplacementBubble()
    applyTextReplacementCandidate(candidate)
  }

  private func applyTextReplacementCandidate(_ candidate: CandidateSuggestion) {
    if let handler = actionHandler as? StandardKeyboardActionHandler,
       let controller = handler.keyboardController as? KeyboardInputViewController
    {
      controller.applyTextReplacementCandidate(candidate)
      return
    }

    if let shortcut = candidate.subtitle {
      for _ in 0..<shortcut.count {
        keyboardContext.textDocumentProxy.deleteBackward()
      }
    }
    keyboardContext.textDocumentProxy.insertText(candidate.text)
    rimeContext.textReplacementSuggestions = []
  }

  // 状态图片
  func stateImage(_ state: State) -> UIImage? {
    let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)
    return state == .collapse
      ? UIImage(systemName: "chevron.down", withConfiguration: config)
      : UIImage(systemName: "chevron.up", withConfiguration: config)
  }
}

private final class TextReplacementBubbleOverlayView: UIView {
  weak var bubbleView: UIView?
  var onOutsideTap: (() -> Void)?

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, alpha >= 0.01, isUserInteractionEnabled, bounds.contains(point) else {
      return nil
    }

    if let bubbleView {
      let bubblePoint = convert(point, to: bubbleView)
      if bubbleView.bounds.contains(bubblePoint) {
        return bubbleView.hitTest(bubblePoint, with: event) ?? bubbleView
      }
    }

    return self
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else {
      super.touchesEnded(touches, with: event)
      return
    }

    let point = touch.location(in: self)
    if let bubbleView {
      let bubblePoint = convert(point, to: bubbleView)
      if bubbleView.bounds.contains(bubblePoint) {
        super.touchesEnded(touches, with: event)
        return
      }
    }

    onOutsideTap?()
  }
}
