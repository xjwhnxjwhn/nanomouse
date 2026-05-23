//
//  CandidateWordsCollectionView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import OSLog
import UIKit

/**
 候选文字集合视图
 */
public class CandidateWordsCollectionView: UICollectionView {
  var style: CandidateBarStyle

  /// RIME 上下文
  let rimeContext: RimeContext

  let keyboardContext: KeyboardContext

  let actionHandler: KeyboardActionHandler

  /// 水平滚动方向布局
  let horizontalLayout: UICollectionViewLayout

  /// 垂直滚动方向布局
  let verticalLayout: UICollectionViewLayout

  /// Combine
  var subscriptions = Set<AnyCancellable>()

  /// 候选栏状态
  var candidatesViewState: CandidateBarView.State

  /// 当前用户输入，用来判断滚动候选栏是否滚动到首个首选字
  var currentUserInputKey: String = ""

  init(
    style: CandidateBarStyle,
    keyboardContext: KeyboardContext,
    actionHandler: KeyboardActionHandler,
    rimeContext: RimeContext
  ) {
    self.style = style
    self.keyboardContext = keyboardContext
    self.actionHandler = actionHandler
    self.rimeContext = rimeContext
    self.candidatesViewState = keyboardContext.candidatesViewState

    self.horizontalLayout = {
      let layout = AlignedCollectionViewFlowLayout(horizontalAlignment: .justified, verticalAlignment: .center)
      layout.scrollDirection = .horizontal
      return layout
    }()

    self.verticalLayout = {
      let layout = SeparatorCollectionViewFlowLayout()
      layout.scrollDirection = .vertical
      return layout
    }()

    super.init(frame: .zero, collectionViewLayout: horizontalLayout)

    self.delegate = self
    self.dataSource = self
    self.register(CandidateWordCell.self, forCellWithReuseIdentifier: CandidateWordCell.identifier)

    self.backgroundColor = UIColor.clear
    // 水平划动状态下不允许垂直划动
    self.showsHorizontalScrollIndicator = false
    self.alwaysBounceHorizontal = true
    self.alwaysBounceVertical = false

    let gesture = UISwipeGestureRecognizer(target: self, action: #selector(downSwipeGesture(_:)))
    gesture.direction = .down
    self.addGestureRecognizer(gesture)

    combine()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc func downSwipeGesture(_ sender: CandidateWordsCollectionView) {
    if candidatesViewState.isCollapse() {
      keyboardContext.candidatesViewState = .expand
    }
  }

  func setupStyle(_ style: CandidateBarStyle) {
    self.style = style
    self.reloadData()
  }

  func combine() {
    Publishers.CombineLatest(
      self.rimeContext.$suggestions,
      self.rimeContext.$textReplacementSuggestions
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] suggestions, _ in
      guard let self = self else { return }
      self.reloadData()
      if self.currentUserInputKey != self.rimeContext.userInputKey {
        self.currentUserInputKey = self.rimeContext.userInputKey
        let hasSuggestions = !suggestions.isEmpty
        if hasSuggestions {
          let itemCount = self.numberOfItems(inSection: 0)
          if itemCount > 0 {
            if self.candidatesViewState.isCollapse() {
              self.scrollToItem(at: IndexPath(item: 0, section: 0), at: .right, animated: false)
            } else {
              self.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
            }
          }
          return
        }
      }

      if suggestions.isEmpty && self.candidatesViewState != .collapse {
        self.candidatesViewState = .collapse
        self.keyboardContext.candidatesViewState = .collapse
        changeLayout(.collapse)
      }
    }
    .store(in: &subscriptions)

    keyboardContext.$candidatesViewState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] state in
        guard let self = self else { return }
        guard self.candidatesViewState != state else { return }
        self.candidatesViewState = state
        changeLayout(state)
      }
      .store(in: &subscriptions)
  }
  
  /// 获取合并后的候选项列表
  var combinedSuggestions: [CandidateSuggestion] {
    let hasMiddleDigit = !rimeContext.mixedInputManager.digitLiteralAfterFirstPinyin.isEmpty
    let prefixPending = !rimeContext.mixedInputManager.pinyinOnlyBeforeFirstDigitLiteral.isEmpty
    let suppressSuffixCandidates = rimeContext.mixedInputManager.hasLiteral && hasMiddleDigit && prefixPending

    var result = [CandidateSuggestion]()
    if suppressSuffixCandidates {
      // 仅保留混输注入的候选（负索引），避免显示后缀英文/拼音候选
      result.append(contentsOf: rimeContext.suggestions.filter { $0.index < 0 })
      return result
    }

    result.append(contentsOf: rimeContext.suggestions)
    return result
  }

  func changeLayout(_ state: CandidateBarView.State) {
    if state.isCollapse() {
      setCollectionViewLayout(self.horizontalLayout, animated: false) { [unowned self] _ in
        self.alwaysBounceHorizontal = true
        self.alwaysBounceVertical = false
        self.contentOffset = .zero
      }
    } else {
      setCollectionViewLayout(self.verticalLayout, animated: false) { [unowned self] _ in
        self.alwaysBounceHorizontal = false
        self.alwaysBounceVertical = true
        self.contentOffset = .zero
      }
    }
  }
}

// MARK: - UICollectionViewDataSource

extension CandidateWordsCollectionView: UICollectionViewDataSource {
  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    combinedSuggestions.count
  }

  public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let toolbarConfig = keyboardContext.hamsterConfiguration?.toolbar
    let showIndex = toolbarConfig?.displayIndexOfCandidateWord
    let showComment = toolbarConfig?.displayCommentOfCandidateWord
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CandidateWordCell.identifier, for: indexPath)
    let suggestions = combinedSuggestions
    if let cell = cell as? CandidateWordCell, indexPath.item < suggestions.count {
      let candidate = suggestions[indexPath.item]
      cell.updateWithCandidateSuggestion(candidate, style: style, showIndex: showIndex, showComment: showComment)
    }
    return cell
  }
}

// MAKE: - UICollectionViewDelegate

extension CandidateWordsCollectionView: UICollectionViewDelegate {
  /// 向下划动到达阈值时获取下一页数据
//  public func scrollViewDidScroll(_ scrollView: UIScrollView) {
//    let threshold: CGFloat = 50.0
//    let contentOffset = scrollView.contentOffset.y
//    let maximumOffset = scrollView.contentSize.height - scrollView.frame.size.height
//    if (maximumOffset - contentOffset <= threshold) && (maximumOffset - contentOffset != -5.0) {
//      rimeContext.nextPage()
//    }
//  }
  public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
    if indexPath.item + 1 >= combinedSuggestions.count {
      rimeContext.nextPage()
    }
  }

  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let _ = collectionView.cellForItem(at: indexPath) else { return }
    // 用于触发反馈
    actionHandler.handle(.press, on: .character(""))
    
    let suggestions = combinedSuggestions
    guard indexPath.item < suggestions.count else { return }
    let selectedItem = suggestions[indexPath.item]
    
    if let handler = actionHandler as? StandardKeyboardActionHandler,
       let controller = handler.keyboardController as? KeyboardInputViewController
    {
      if controller.handleMixedInputDigitCandidateIfNeeded(
        selectedItem.text,
        candidateIndex: selectedItem.index
      ) {
        return
      }
      if rimeContext.mixedInputManager.hasLiteral {
        if selectedItem.index < 0 {
          controller.commitMixedInputCandidateWithLiteralOption(
            rimeIndex: selectedItem.index,
            displayIndex: indexPath.item,
            candidateText: selectedItem.text,
            candidateSubtitle: selectedItem.subtitle
          )
          return
        }
        if rimeContext.mixedInputManager.pinyinOnly.isEmpty {
          controller.commitMixedInputCandidateDirectly(selectedItem.text)
          return
        }
        controller.commitMixedInputCandidateWithLiteralOption(
          rimeIndex: selectedItem.index,
          displayIndex: indexPath.item,
          candidateText: selectedItem.text,
          candidateSubtitle: selectedItem.subtitle
        )
        return
      }
      // 英语输入模式
      if controller.isEnglishInputActive && controller.englishEngine.isComposing {
        controller.selectEnglishCandidate(index: indexPath.item)
        return
      }
      // AzooKey 日语输入模式
      if rimeContext.currentSchema?.schemaId == HamsterConstants.azooKeySchemaId {
        controller.selectAzooKeyCandidate(index: indexPath.item)
        return
      }
    }
    self.rimeContext.selectCandidate(index: indexPath.item)
  }

  public func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
    if let cell = collectionView.cellForItem(at: indexPath) {
      cell.isHighlighted = true
    }
  }
}

// MAKE: - UICollectionViewDelegateFlowLayout

extension CandidateWordsCollectionView: UICollectionViewDelegateFlowLayout {
  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
    return UIEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
  }

  // 询问委托一个部分连续的行或列之间的间距。
  // 对于一个垂直滚动的网格，这个值表示连续的行之间的最小间距。
  // 对于一个水平滚动的网格，这个值代表连续的列之间的最小间距。
  // 这个间距不应用于标题和第一行之间的空间或最后一行和页脚之间的空间。
  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
    return 3
  }

  // 向委托询问某部分的行或列中连续项目之间的间距。
  // 你对这个方法的实现可以返回一个固定的值或者为每个部分返回不同的间距值。
  // 对于一个垂直滚动的网格，这个值代表了同一行中项目之间的最小间距。
  // 对于一个水平滚动的网格，这个值代表同一列中项目之间的最小间距。
  // 这个间距是用来计算单行可以容纳多少个项目的，但是在确定了项目的数量之后，实际的间距可能会被向上调整。
  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
    let isVerticalLayout: Bool = !self.candidatesViewState.isCollapse()
    if isVerticalLayout {
      return 1
    }
    return 5
  }

  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    let isVerticalLayout: Bool = !self.candidatesViewState.isCollapse()
    let baseCodingArea: CGFloat = keyboardContext.heightOfCodingArea
    let focusLineHeight: CGFloat = rimeContext.prefersTwoTierCandidateBar ? baseCodingArea * 2 : baseCodingArea
    let reservedHeight: CGFloat = (keyboardContext.enableEmbeddedInputMode && !rimeContext.prefersTwoTierCandidateBar) ? 0 : focusLineHeight
    let effectiveToolbarHeight: CGFloat = keyboardContext.heightOfToolbar + (rimeContext.prefersTwoTierCandidateBar ? baseCodingArea : 0)
    let heightOfToolbar: CGFloat = effectiveToolbarHeight - reservedHeight - 6

    let suggestions = combinedSuggestions
    guard indexPath.item < suggestions.count else { return .zero }
    let candidate = suggestions[indexPath.item]
    let toolbarConfig = keyboardContext.hamsterConfiguration?.toolbar
    let showComment = toolbarConfig?.displayCommentOfCandidateWord ?? false
    let showIndex = toolbarConfig?.displayIndexOfCandidateWord ?? false

    // 为 cell 内容增加左右间距, 对应 cell 的 leading, trailing 的约束
    let intrinsicHorizontalMargin: CGFloat = 14

    // 60 为下拉状态按钮宽度, 220 是 横屏时需要减去全面屏两侧的宽度(注意：这里忽略的非全面屏)
    let maxWidth: CGFloat = UIScreen.main.bounds.width - ((self.window?.screen.interfaceOrientation == .portrait) ? 60 : 220)

    let attributeString = candidate.attributeString(showIndex: showIndex, showComment: showComment, style: style)

    // 60 是下拉箭头按键的宽度，垂直滑动的 label 在超出宽度时，文字折叠
    let targetWidth: CGFloat = maxWidth - (isVerticalLayout ? 60 : 0)

    var titleLabelSize = UILabel.estimatedAttributeSize(attributeString, targetSize: CGSize(width: targetWidth, height: 0))

    if attributeString.string.count == 1, let minWidth = UILabel.fontSizeAndMinWidthMapping[style.candidateTextFont.pointSize] {
      titleLabelSize.width = minWidth
    }

    let width = titleLabelSize.width + intrinsicHorizontalMargin
    return CGSize(
      // 垂直布局下，cell 宽度不能大于屏幕宽度
      width: isVerticalLayout ? min(width, maxWidth) : width,
      height: heightOfToolbar
    )
  }
}

public extension UILabel {
  /// 字体大小与最小宽度映射
  /// 最小宽度是由单个 emoji 表情计算得出, 比如：🉐，
  /// 因为单个 emoji 表情的宽度比单个汉字的宽度大，所以使用 emoji 作为最小宽度
  /// key: 字体大小
  /// value: 最小宽度
  static let fontSizeAndMinWidthMapping: [CGFloat: CGFloat] = [
    10: 14,
    11: 16,
    12: 17,
    13: 19,
    14: 20,
    15: 21,
    16: 23,
    17: 23,
    18: 24,
    19: 24,
    20: 25,
    21: 26,
    22: 26,
    23: 27,
    24: 27,
    25: 28,
    26: 30,
    27: 31,
    28: 32,
    29: 33,
    30: 34,
  ]

  static var tempLabelForCalc: UILabel = {
    let label = UILabel()
    label.numberOfLines = 1
    return label
  }()

  static func estimatedSize(_ text: String, targetSize: CGSize = .zero, font: UIFont? = nil) -> CGSize {
    tempLabelForCalc.attributedText = nil
    tempLabelForCalc.text = text
    if let font = font {
      tempLabelForCalc.font = font
    }
    return tempLabelForCalc.sizeThatFits(targetSize)
  }

  static func estimatedAttributeSize(_ text: NSAttributedString, targetSize: CGSize = .zero) -> CGSize {
    tempLabelForCalc.text = nil
    tempLabelForCalc.attributedText = text
    return tempLabelForCalc.sizeThatFits(targetSize)
  }
}
