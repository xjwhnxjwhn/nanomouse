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

  /// 用户引导相关属性
  private var subscriptions = Set<AnyCancellable>()
  private var currentTipIndex = 0
  private var tipTimer: Timer?

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

  /// 用户引导提示标签
  lazy var userGuideLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.textAlignment = .center
    label.numberOfLines = 1
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.7
    label.alpha = 0
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
  }

  func setupContentView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
    setupUserGuideSubscription()
  }

  /// 构建视图层次
  override public func constructViewHierarchy() {
    // 非内嵌模式或双行候选栏时添加拼写区域
    if showsFocusLine {
      addSubview(phoneticLabel)
    }
    if keyboardContext.swipePaging {
      addSubview(candidatesArea)
      addSubview(controlStateView)
    } else {
      addSubview(candidatesPagingArea)
    }
    // 添加用户引导标签（放在最后确保在最上层）
    addSubview(userGuideLabel)
    bringSubviewToFront(userGuideLabel)
  }

  /// 激活视图约束
  override public func activateViewConstraints() {
    let buttonInsets = layoutConfig.buttonInsets
    let focusLineHeight = showsFocusLine ? self.focusLineHeight : 0
    let controlStateHeight: CGFloat = effectiveToolbarHeight - focusLineHeight
    let candidatesView = keyboardContext.swipePaging ? candidatesArea : candidatesPagingArea

    /// 隐藏拼写区域
    if !showsFocusLine {
      if keyboardContext.swipePaging {
        NSLayoutConstraint.activate([
          candidatesView.topAnchor.constraint(equalTo: topAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: controlStateView.leadingAnchor),

          controlStateView.heightAnchor.constraint(equalTo: controlStateView.widthAnchor, multiplier: 1.0),
          controlStateView.topAnchor.constraint(equalTo: topAnchor),
          controlStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
          controlStateView.heightAnchor.constraint(equalToConstant: controlStateHeight)
        ])
      } else {
        NSLayoutConstraint.activate([
          candidatesView.topAnchor.constraint(equalTo: topAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -buttonInsets.right)
        ])
      }
    } else {
      if keyboardContext.swipePaging {
        NSLayoutConstraint.activate([
          phoneticLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          phoneticLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
          phoneticLabel.topAnchor.constraint(equalTo: topAnchor),
          phoneticLabel.heightAnchor.constraint(equalToConstant: focusLineHeight),

          candidatesView.topAnchor.constraint(equalTo: phoneticLabel.bottomAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: controlStateView.leadingAnchor),

          controlStateView.heightAnchor.constraint(equalTo: controlStateView.widthAnchor, multiplier: 1.0),
          controlStateView.topAnchor.constraint(equalTo: phoneticLabel.bottomAnchor),
          controlStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
          controlStateView.heightAnchor.constraint(equalToConstant: controlStateHeight)
        ])
      } else {
        NSLayoutConstraint.activate([
          phoneticLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          phoneticLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
          phoneticLabel.topAnchor.constraint(equalTo: topAnchor),
          phoneticLabel.heightAnchor.constraint(equalToConstant: focusLineHeight),

          candidatesView.topAnchor.constraint(equalTo: phoneticLabel.bottomAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -buttonInsets.right)
        ])
      }
    }

    // 用户引导标签约束（与候选区域重叠，通过 alpha 控制显示隐藏）
    NSLayoutConstraint.activate([
      userGuideLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
      userGuideLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -buttonInsets.right),
      userGuideLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
    ])
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

    // 用户引导标签样式
    userGuideLabel.font = style.candidateTextFont
    userGuideLabel.textColor = style.candidateTextColor.withAlphaComponent(0.6)

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

  // 状态图片
  func stateImage(_ state: State) -> UIImage? {
    let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)
    return state == .collapse
      ? UIImage(systemName: "chevron.down", withConfiguration: config)
      : UIImage(systemName: "chevron.up", withConfiguration: config)
  }

  // MARK: - 用户引导相关方法

  /// 设置用户引导订阅
  private func setupUserGuideSubscription() {
    // 检查是否启用用户引导
    guard keyboardContext.hamsterConfiguration?.toolbar?.enableUserGuideScrolling ?? true else {
      return
    }

    // 订阅候选词变化，控制用户引导的显示/隐藏
    let userInputKeyPublisher = rimeContext.userInputKeyPublished.prepend(rimeContext.userInputKey)
    Publishers.CombineLatest3(
      rimeContext.$suggestions,
      rimeContext.$textReplacementSuggestions,
      userInputKeyPublisher
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] suggestions, textReplacements, userInputKey in
      guard let self = self else { return }
      let isEmpty = suggestions.isEmpty && textReplacements.isEmpty
      let hasInput = !userInputKey.isEmpty
      if isEmpty && !hasInput {
        self.showUserGuide()
      } else {
        self.hideUserGuide()
      }
    }
    .store(in: &subscriptions)

    // 初始状态：如果当前没有候选词，立即显示用户引导
    if rimeContext.suggestions.isEmpty && rimeContext.textReplacementSuggestions.isEmpty && rimeContext.userInputKey.isEmpty {
      showUserGuide()
    }
  }

  /// 显示用户引导
  private func showUserGuide() {
    guard tipTimer == nil else { return }
    Logger.statistics.debug("[UserGuide] showUserGuide called, currentTipIndex: \(self.currentTipIndex)")
    showCurrentTip()
    tipTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
      self?.fadeToNextTip()
    }
  }

  /// 隐藏用户引导
  private func hideUserGuide() {
    Logger.statistics.debug("[UserGuide] hideUserGuide called")
    tipTimer?.invalidate()
    tipTimer = nil
    UIView.animate(withDuration: 0.2) {
      self.userGuideLabel.alpha = 0
    }
  }

  /// 显示当前提示
  private func showCurrentTip() {
    let tipText = UserGuideTips.tip(at: currentTipIndex)
    Logger.statistics.debug("[UserGuide] showCurrentTip: \(tipText)")
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
