//
//  StanderSystemKeyboard.swift
//
//
//  Created by morse on 2023/8/10.
//

import HamsterKit
import HamsterUIKit
import OSLog
import UIKit

/**
 标准系统键盘
 */
public class StanderSystemKeyboard: KeyboardTouchView {
  // MARK: - Properties

  private let keyboardLayoutProvider: KeyboardLayoutProvider
  private let actionHandler: KeyboardActionHandler
  private let appearance: KeyboardAppearance
  private var actionCalloutContext: ActionCalloutContext
  private var calloutContext: KeyboardCalloutContext
  private var inputCalloutContext: InputCalloutContext
  private var keyboardContext: KeyboardContext
  private var rimeContext: RimeContext

  /// TODO: 触摸管理视图
  /// 统一手势处理
  // private let touchView = KeyboardTouchView()

  /// 缓存所有按键视图
  private var keyboardRows: [[KeyboardButton]] = []
  /// 静态视图约束，视图创建完毕后不在发生变化
  private var staticConstraints: [NSLayoutConstraint] = []
  /// 动态视图约束，在键盘方向发生变化后需要更新约束
  private var dynamicConstraints: [NSLayoutConstraint] = []
  private var isChineseArcManualLayoutActive = false

  private lazy var oneHandReturnToFullButton: UIButton = {
    makeOneHandModeControlButton(title: "双手", action: #selector(handleOneHandReturnToFullTap))
  }()

  private lazy var oneHandSwitchSideButton: UIButton = {
    makeOneHandModeControlButton(title: "右手", action: #selector(handleOneHandSwitchSideTap))
  }()

  private lazy var oneHandModeControlsStack: UIStackView = {
    let stack = UIStackView(arrangedSubviews: [oneHandReturnToFullButton, oneHandSwitchSideButton])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.distribution = .fillEqually
    stack.spacing = 8
    stack.isHidden = true
    stack.isUserInteractionEnabled = true
    return stack
  }()

  // 当前外观
  var userInterfaceStyle: UIUserInterfaceStyle

  // 屏幕方向
  private var interfaceOrientation: InterfaceOrientation

  // 键盘是否浮动
  private var isKeyboardFloating: Bool

  // MARK: - 计算属性

  private var layout: KeyboardLayout {
    keyboardLayoutProvider.keyboardLayout(for: keyboardContext)
  }

  private var layoutConfig: KeyboardLayoutConfiguration {
    .standard(for: keyboardContext)
  }

//  private var actionCalloutStyle: KeyboardActionCalloutStyle {
//    var style = appearance.actionCalloutStyle
//    let insets = layoutConfig.buttonInsets
//    style.callout.buttonInset = CGSize(width: insets.left, height: insets.top)
//    return style
//  }
//
//  private var inputCalloutStyle: KeyboardInputCalloutStyle {
//    var style = appearance.inputCalloutStyle
//    let insets = layoutConfig.buttonInsets
//    style.callout.buttonInset = CGSize(width: insets.left, height: insets.top)
//    return style
//  }

  // MARK: - Initializations

  /**
   Create a system keyboard with custom button views.

   The provided `buttonView` builder will be used to build
   the full button view for every layout item.

   - Parameters:
     - KeyboardLayoutProvider: The keyboard layout provider.
     - appearance: The keyboard appearance to use.
     - actionHandler: The action handler to use.
     - autocompleteContext: The autocomplete context to use.
     - autocompleteToolbar: The autocomplete toolbar mode to use.
     - keyboardContext: The keyboard context to use.
     - calloutContext: The callout context to use.
   */
  public init(
    keyboardLayoutProvider: KeyboardLayoutProvider,
    appearance: KeyboardAppearance,
    actionHandler: KeyboardActionHandler,
    keyboardContext: KeyboardContext,
    rimeContext: RimeContext,
    calloutContext: KeyboardCalloutContext?
  ) {
    self.keyboardLayoutProvider = keyboardLayoutProvider
    self.actionHandler = actionHandler
    self.appearance = appearance
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    self.calloutContext = calloutContext ?? .disabled
    self.actionCalloutContext = calloutContext?.action ?? .disabled
    self.inputCalloutContext = calloutContext?.input ?? .disabled
    self.interfaceOrientation = keyboardContext.interfaceOrientation
    self.isKeyboardFloating = keyboardContext.isKeyboardFloating
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    KeyboardStartupDiagnostics.log("StanderSystemKeyboard init keyboardType=\(keyboardContext.keyboardType.yamlString) screen=\(keyboardContext.screenSize) orientation=\(keyboardContext.interfaceOrientation)")
    setupKeyboardView()
  }

  deinit {
    subviews.forEach { $0.removeFromSuperview() }
  }

  func setupKeyboardView() {
    KeyboardStartupDiagnostics.setStartupPhase("standard.setup.begin")
    KeyboardStartupDiagnostics.measure("StanderSystemKeyboard.constructViewHierarchy") { constructViewHierarchy() }
    KeyboardStartupDiagnostics.setStartupPhase("standard.construct.end")
    KeyboardStartupDiagnostics.measure("StanderSystemKeyboard.activateViewConstraints") { activateViewConstraints() }
    KeyboardStartupDiagnostics.setStartupPhase("standard.constraints.end")
    KeyboardStartupDiagnostics.measure("StanderSystemKeyboard.setupAppearance") { setupAppearance() }
    KeyboardStartupDiagnostics.setStartupPhase("standard.setup.end")
  }

  override public func setupAppearance() {
    backgroundColor = .clear
    contentMode = .redraw
    updateOneHandModeControlAppearance()
  }

  func refreshAppearanceForTraitChange() {
    applyTraitAppearance()
    setNeedsLayout()
    layoutIfNeeded()
  }

  private func applyTraitAppearance() {
    userInterfaceStyle = keyboardContext.colorScheme
    setupAppearance()
    keyboardRows.flatMap { $0 }.forEach { $0.refreshAppearanceForTraitChange() }
  }

  // MARK: Layout

  /// 构建视图层次
  override public func constructViewHierarchy() {
    // addSubview(touchView)

    // 添加按键至 View
    let itemRows = layout.itemRows
    KeyboardStartupDiagnostics.setStartupPhase("standard.construct.rows.\(itemRows.count)")
    KeyboardStartupDiagnostics.log("StanderSystemKeyboard.construct rows=\(layoutRowsSummary(itemRows))")
    for (rowIndex, row) in itemRows.enumerated() {
      KeyboardStartupDiagnostics.setStartupPhase("standard.construct.row.\(rowIndex).begin.count.\(row.count)")
      var tempRow = [KeyboardButton]()
      for (itemIndex, item) in row.enumerated() {
        if itemIndex == 0 {
          KeyboardStartupDiagnostics.log("StanderSystemKeyboard.construct row=\(rowIndex) firstItem=\(item.action) count=\(row.count)")
        }
        let buttonItem = KeyboardButton(
          row: rowIndex,
          column: itemIndex,
          item: item,
          actionHandler: actionHandler,
          keyboardContext: keyboardContext,
          rimeContext: rimeContext,
          calloutContext: calloutContext,
          appearance: appearance
        )
        buttonItem.translatesAutoresizingMaskIntoConstraints = false
        // 需要将按键添加至 touchView, 统一处理
        // touchView.addSubview(buttonItem)
        addSubview(buttonItem)
        tempRow.append(buttonItem)
      }

      keyboardRows.append(tempRow)
      KeyboardStartupDiagnostics.setStartupPhase("standard.construct.row.\(rowIndex).end.totalRows.\(keyboardRows.count)")
    }
    addSubview(oneHandModeControlsStack)
    if keyboardRows.count < 3 {
      KeyboardStartupDiagnostics.log("SUSPICIOUS StanderSystemKeyboard constructed only \(keyboardRows.count) rows; keyboardType=\(keyboardContext.keyboardType.yamlString)")
    }
  }

  /// 按键宽度约束
  /// button: 需要设置约束的按键
  /// inputAnchorButton: 宽度类型为 input 的按键，因为所有 input 类型的按键宽度是一致的
  ///
  /// 注意:
  /// 1. 当行中 .available 类型按键数量等于 1 时，不需要添加宽度约束
  /// 2. 当行中 .available 类型按键数量大于 1 的情况下，需要在行遍历结束后添加等宽约束。即同一行中的所有 .available 类型的宽度相同
  func buttonWidthConstraint(_ button: KeyboardButton, inputAnchorButton: KeyboardButton?) -> NSLayoutConstraint? {
    var constraint: NSLayoutConstraint? = nil
    switch button.item.size.width {
    case .input:
      if let firstInputButton = inputAnchorButton, firstInputButton != button {
        constraint = button.widthAnchor.constraint(equalTo: firstInputButton.widthAnchor)
      }
    case .inputPercentage(let percent):
      let percent = CGFloat.rounded(percent)
      if let firstInputButton = inputAnchorButton {
        constraint = button.widthAnchor.constraint(equalTo: firstInputButton.widthAnchor, multiplier: percent)
      }
    case .percentage(let percent):
      let percent = CGFloat.rounded(percent)
      constraint = button.widthAnchor.constraint(equalTo: widthAnchor, multiplier: percent)
    case .points(let points):
      constraint = button.widthAnchor.constraint(equalToConstant: points)
    default:
      break
    }
    return constraint
  }

  /// 激活视图约束
  override public func activateViewConstraints() {
    KeyboardStartupDiagnostics.setStartupPhase("standard.constraints.begin.rows.\(keyboardRows.count)")
    KeyboardStartupDiagnostics.log("StanderSystemKeyboard.activate constraints rows=\(keyboardRows.count) rowCounts=\(keyboardRows.map { $0.count }) bounds=\(bounds)")
    // 暂存同一行中 available 宽度类型按键集合
    var availableItems = [KeyboardButton]()

    // 首个 input 宽度类型按钮
    var firstInputButton: KeyboardButton? = nil

    for row in keyboardRows {
      for button in row {
        // 获取首个 input 类型宽度按键
        if firstInputButton == nil && button.item.size.width == .input {
          firstInputButton = button
        }

        // 按键高度约束（高度包含 insets 部分）
        let heightConstant = button.item.size.height
        let buttonHeightConstraint = button.heightAnchor.constraint(equalToConstant: heightConstant)
        // TODO: .required 会导致日志打印约束错误，但是改为 .defaultHigh 后，高度约束不起作用，会导致显示的高度有问题
        buttonHeightConstraint.priority = .defaultHigh
        buttonHeightConstraint.identifier = "\(button.row)-\(button.column)-button-height"
        dynamicConstraints.append(buttonHeightConstraint)
        if button.column > 0, let rowFirstButton = row.first {
          // 同一行必须等高，否则容器高度不完全匹配时，额外高度会被第一行第一个键单独吸收。
          staticConstraints.append(button.heightAnchor.constraint(equalTo: rowFirstButton.heightAnchor))
        }
        // Logger.statistics.debug("keyboard layoutSubviews(): row: \(button.row), column: \(button.column), rowHeight: \(heightConstant)")

        // 按键宽度约束
        // 注意：.available 类型宽度在行遍历结束后添加
        if let constraint = buttonWidthConstraint(button, inputAnchorButton: firstInputButton) {
          staticConstraints.append(constraint)
        } else {
          // 注意：available 类型按键宽度在 input 类型宽度约束在行遍历后添加
          if button.item.size.width == .available {
            availableItems.append(button)
          }
        }

        // 按键 leading
        if button.column == 0 {
          staticConstraints.append(button.leadingAnchor.constraint(equalTo: leadingAnchor))
        } else {
          let prevItem = row[button.column - 1]
          staticConstraints.append(button.leadingAnchor.constraint(equalTo: prevItem.trailingAnchor))
        }

        // 按键 top
        if button.row == 0 {
          staticConstraints.append(button.topAnchor.constraint(equalTo: topAnchor))
        } else { // 非首行添加相对上一行首个按键的 top 约束
          let prevRowItem = keyboardRows[button.row - 1][0]
          staticConstraints.append(button.topAnchor.constraint(equalTo: prevRowItem.bottomAnchor))
        }

        // 按键 bottom
        // 注意：只有最后一行需要添加
        if button.row + 1 == keyboardRows.endIndex {
          staticConstraints.append(button.bottomAnchor.constraint(equalTo: bottomAnchor))
        }

        // 按键 trailing
        // 注意：只有最后一列需要添加
        if button.column + 1 == row.endIndex {
          staticConstraints.append(button.trailingAnchor.constraint(equalTo: trailingAnchor))
        }
      }

      // 每行循环结束后，平均分配 .available 宽度类型的按键
      // 当行中 .available 类型按键数量大于 1 的情况下，添加等宽约束
      if let firstItem = availableItems.first {
        for item in availableItems.dropFirst() {
          staticConstraints.append(item.widthAnchor.constraint(equalTo: firstItem.widthAnchor))
        }
        availableItems.removeAll()
      }
    }

    NSLayoutConstraint.activate(staticConstraints + dynamicConstraints)
    isChineseArcManualLayoutActive = false
    KeyboardStartupDiagnostics.setStartupPhase("standard.constraints.activated.static.\(staticConstraints.count).dynamic.\(dynamicConstraints.count)")
    KeyboardStartupDiagnostics.log("StanderSystemKeyboard.activate constraints done static=\(staticConstraints.count) dynamic=\(dynamicConstraints.count)")
  }

  override public func layoutSubviews() {
    super.layoutSubviews()
    let currentRows = layout.itemRows
    let summary = "bounds=\(bounds) frame=\(frame) keyboardRows=\(keyboardRows.count) rowCounts=\(keyboardRows.map { $0.count }) layoutRows=\(layoutRowsSummary(currentRows))"
    if KeyboardStartupDiagnostics.shouldLogLayoutSummary(object: self, summary: summary) {
      KeyboardStartupDiagnostics.setStartupPhase("standard.layout.rows.\(keyboardRows.count).h.\(Int(bounds.height.rounded()))")
      KeyboardStartupDiagnostics.log("StanderSystemKeyboard.layout \(summary)")
    }

    if userInterfaceStyle != keyboardContext.colorScheme {
      applyTraitAppearance()
    }

    guard interfaceOrientation != keyboardContext.interfaceOrientation || isKeyboardFloating != keyboardContext.isKeyboardFloating else {
      applyChineseArcOneHandLayoutIfNeeded()
      logSuspiciousButtonFramesIfNeeded()
      return
    }
    interfaceOrientation = keyboardContext.interfaceOrientation
    isKeyboardFloating = keyboardContext.isKeyboardFloating

    // 当布局行列结构不一致时，直接重建，避免约束错位导致按键错乱
    if keyboardRows.count != currentRows.count {
      KeyboardStartupDiagnostics.log("StanderSystemKeyboard row-count mismatch current=\(keyboardRows.count) expected=\(currentRows.count); rebuilding")
      rebuildKeyboardLayout()
      return
    }
    for (rowIndex, row) in currentRows.enumerated() {
      if keyboardRows[rowIndex].count != row.count {
        KeyboardStartupDiagnostics.log("StanderSystemKeyboard column-count mismatch row=\(rowIndex) current=\(keyboardRows[rowIndex].count) expected=\(row.count); rebuilding")
        rebuildKeyboardLayout()
        return
      }
    }

    // 是否重新计算自动布局标志
    var resetConstraints = false

    // 约束索引
    var dynamicConstraintsIndex = 0
    for (rowIndex, row) in currentRows.enumerated() {
      for (columnIndex, item) in row.enumerated() {
        let oldItem = keyboardRows[rowIndex][columnIndex].item

        // 检测按键宽度或高度是否发生变化, 只要任意一项发生变化就需要重建约束
        resetConstraints = resetConstraints
          || oldItem.size.width != item.size.width
          || oldItem.size.height != item.size.height

        keyboardRows[rowIndex][columnIndex].item = item

        // 动态变更行高度，如果不存在宽度变化的问题，则只需改变动态高度约束中的高度
        if dynamicConstraintsIndex < dynamicConstraints.count {
          let rowHeight = item.size.height
          // Logger.statistics.debug("Custom keyboard layoutSubviews(): row: \(rowIndex), column: \(columnIndex), rowHeight: \(rowHeight)")
          dynamicConstraints[dynamicConstraintsIndex].constant = rowHeight
        }
        dynamicConstraintsIndex += 1
      }
    }

    if resetConstraints {
      KeyboardStartupDiagnostics.log("StanderSystemKeyboard reset constraints rows=\(layoutRowsSummary(currentRows))")
      NSLayoutConstraint.deactivate(staticConstraints + dynamicConstraints)
      staticConstraints.removeAll(keepingCapacity: true)
      dynamicConstraints.removeAll(keepingCapacity: true)
      activateViewConstraints()
    }
    applyChineseArcOneHandLayoutIfNeeded()
    logSuspiciousButtonFramesIfNeeded()
  }

  private func rebuildKeyboardLayout() {
    KeyboardStartupDiagnostics.log("StanderSystemKeyboard.rebuild begin")
    NSLayoutConstraint.deactivate(staticConstraints + dynamicConstraints)
    staticConstraints.removeAll(keepingCapacity: true)
    dynamicConstraints.removeAll(keepingCapacity: true)
    isChineseArcManualLayoutActive = false

    keyboardRows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
    keyboardRows.removeAll(keepingCapacity: true)

    constructViewHierarchy()
    activateViewConstraints()
    setNeedsLayout()
    KeyboardStartupDiagnostics.log("StanderSystemKeyboard.rebuild end rows=\(keyboardRows.count) rowCounts=\(keyboardRows.map { $0.count })")
  }

  private func layoutRowsSummary(_ rows: KeyboardLayoutItemRows) -> String {
    rows.enumerated().map { rowIndex, row in
      let labels = row.map { item in
        appearance.buttonText(for: item.action) ?? item.action.lookupString ?? "_"
      }.joined()
      return "\(rowIndex):\(row.count)[\(labels)]"
    }.joined(separator: " ")
  }

  func startupDiagnosticSnapshot() -> String {
    let flattenedButtons = keyboardRows.flatMap { $0 }
    let qButton = flattenedButtons.first { $0.buttonText.caseInsensitiveCompare("q") == .orderedSame }
    let oversizedButtons = flattenedButtons.filter { !$0.isHidden && bounds.height > 1 && $0.frame.height > bounds.height * 0.55 }
    let qFrame = qButton.map { KeyboardStartupDiagnostics.format($0.frame) } ?? "nil"
    let qHeight = qButton?.frame.height ?? 0
    let isBad = keyboardRows.count < 3
      || (bounds.height > 1 && qHeight > bounds.height * 0.55)
      || !oversizedButtons.isEmpty
    let rowCounts = keyboardRows.map { "\($0.count)" }.joined(separator: ",")
    let rowFrames = keyboardRows.enumerated().map { rowIndex, row in
      guard let first = row.first else { return "\(rowIndex):nil" }
      return "\(rowIndex):\(KeyboardStartupDiagnostics.format(first.frame))"
    }.joined(separator: ",")
    let oversizedLabels = oversizedButtons.prefix(6).map(\.buttonText).joined(separator: ",")

    return [
      "standard",
      "frame=\(KeyboardStartupDiagnostics.format(frame))",
      "bounds=\(KeyboardStartupDiagnostics.format(bounds))",
      "rows=\(keyboardRows.count)",
      "rc=\(rowCounts)",
      "row0=\(rowFrames)",
      "q=\(qFrame)",
      "overs=\(oversizedLabels.isEmpty ? "none" : oversizedLabels)",
      "manual=\(isChineseArcManualLayoutActive ? 1 : 0)",
      "bad=\(isBad ? 1 : 0)"
    ].joined(separator: " ")
  }

  private func applyChineseArcOneHandLayoutIfNeeded() {
    guard keyboardContext.keyboardType.supportsStandardChineseArcOneHandKeyboard else {
      restoreStandardButtonLayoutIfNeeded()
      return
    }
    let mode = UserDefaults.hamster.chineseKeyboardOneHandMode
    guard mode != .off, bounds.width > 1, bounds.height > 1, keyboardRows.count >= 3 else {
      restoreStandardButtonLayoutIfNeeded()
      return
    }

    enterChineseArcManualLayoutIfNeeded()
    let visibleLayout = makeChineseArcVisibleLayout()
    let visibleRows = visibleLayout.rows
    let baseRangeRows = makeChineseArcBaseRangeRows()
    guard visibleRows.count >= 3 else {
      restoreStandardButtonLayoutIfNeeded()
      return
    }

    let geometry = makeChineseArcGeometry(rowCount: baseRangeRows.count, mode: mode)
    var rowRanges = makeChineseArcRowRanges(for: baseRangeRows, geometry: geometry)
    if visibleLayout.hasCreatedInnermostRow {
      let innerOuterRadius = rowRanges.last?.innerRadius ?? geometry.innerRadius
      rowRanges.append(ChineseArcRowRange(outerRadius: innerOuterRadius, innerRadius: 0))
    }
    guard rowRanges.count == visibleRows.count else {
      restoreStandardButtonLayoutIfNeeded()
      return
    }
    let visibleButtonIDs = Set(visibleRows.flatMap { $0 }.map { ObjectIdentifier($0) })
    layoutOneHandModeControls(mode: mode)
    keyboardRows.flatMap { $0 }.forEach { button in
      button.transform = .identity
      if !visibleButtonIDs.contains(ObjectIdentifier(button)) {
        button.frame = .zero
        button.setCustomContentShapePath(nil)
      }
    }

    for (rowIndex, row) in visibleRows.enumerated() {
      let rowRange = rowRanges[rowIndex]
      let outerRadius = rowRange.outerRadius
      let innerRadius = rowRange.innerRadius
      let count = row.count
      let segment = geometry.angleSpan / CGFloat(max(count, 1))
      let gap = min(geometry.angularGap, segment * 0.28)

      for (buttonIndex, button) in row.enumerated() {
        let segmentIndex = mode == .rightArc ? count - 1 - buttonIndex : buttonIndex
        let startAngle = geometry.startAngle + CGFloat(segmentIndex) * segment + gap / 2
        let endAngle = geometry.startAngle + CGFloat(segmentIndex + 1) * segment - gap / 2
        let keyPath = makeChineseArcKeyPath(
          pivot: geometry.pivot,
          innerRadius: innerRadius,
          outerRadius: outerRadius,
          startAngle: startAngle,
          endAngle: endAngle,
          horizontalScale: geometry.horizontalScale,
          mode: mode
        )
        var frame = keyPath.bounds.insetBy(dx: -0.5, dy: -0.5).integral
        frame = frame.intersection(bounds.insetBy(dx: -0.5, dy: -0.5))
        guard frame.width > 2, frame.height > 2 else {
          button.frame = .zero
          button.setCustomContentShapePath(nil)
          continue
        }
        let localPath = UIBezierPath(cgPath: keyPath.cgPath)
        localPath.apply(CGAffineTransform(translationX: -frame.minX, y: -frame.minY))
        if button.frame != frame {
          button.frame = frame
        }
        let shapeSignature = [
          mode.rawValue,
          "\(rowIndex)",
          "\(buttonIndex)",
          "\(Int(frame.minX))",
          "\(Int(frame.minY))",
          "\(Int(frame.width))",
          "\(Int(frame.height))",
          "\(Int((innerRadius * 10).rounded()))",
          "\(Int((outerRadius * 10).rounded()))",
          "\(Int((geometry.horizontalScale * 100).rounded()))",
          "\(Int((startAngle * 1000).rounded()))",
          "\(Int((endAngle * 1000).rounded()))",
        ].joined(separator: "-")
        button.setCustomContentShapePath(localPath, signature: shapeSignature)
      }
    }
  }

  private struct ChineseArcVisibleLayout {
    let rows: [[KeyboardButton]]
    let hasCreatedInnermostRow: Bool
  }

  private func makeChineseArcVisibleLayout() -> ChineseArcVisibleLayout {
    switch keyboardContext.keyboardType {
    case .chinese:
      return makeChinesePrimaryArcVisibleLayout()
    case .chineseNumeric:
      return makeChineseNumericArcVisibleLayout()
    case .chineseSymbolic:
      return makeChineseSymbolicArcVisibleLayout()
    default:
      return ChineseArcVisibleLayout(rows: makeChineseArcBaseRangeRows(), hasCreatedInnermostRow: false)
    }
  }

  private func makeChinesePrimaryArcVisibleLayout() -> ChineseArcVisibleLayout {
    let inputRows = keyboardRows.prefix(3).map { row in
      row.filter { button in
        isVisibleArcKey(button) && isChineseArcInputKey(button)
      }
    }.filter { !$0.isEmpty }

    let secondInnerRow = uniqueChineseArcButtons([
      firstChineseArcButton(where: isChineseArcCapsKey),
      firstChineseArcButton(where: isChineseArcNumberSwitchKey),
      firstChineseArcButton(where: isChineseArcLanguageSwitchKey),
      firstChineseArcButton(where: isChineseArcBackspaceKey),
    ])
    let innerRow = uniqueChineseArcButtons([
      firstChineseArcButton(where: isChineseArcSpaceKey),
      firstChineseArcButton(where: isChineseArcReturnKey),
    ])

    var rows = inputRows
    if !secondInnerRow.isEmpty {
      rows.append(secondInnerRow)
    }
    if !innerRow.isEmpty {
      rows.append(innerRow)
    }
    return ChineseArcVisibleLayout(rows: rows, hasCreatedInnermostRow: !innerRow.isEmpty)
  }

  private func makeChineseNumericArcVisibleLayout() -> ChineseArcVisibleLayout {
    makeChineseNumericOrSymbolicArcVisibleLayout(secondInnerButtons: [
      firstChineseArcButton(where: isChineseArcSymbolSwitchKey),
      firstChineseArcButton(where: isChineseArcLanguageSwitchKey),
      firstChineseArcButton(where: isChineseArcBackspaceKey),
    ])
  }

  private func makeChineseSymbolicArcVisibleLayout() -> ChineseArcVisibleLayout {
    makeChineseNumericOrSymbolicArcVisibleLayout(secondInnerButtons: [
      firstChineseArcButton(where: isChineseArcNumberSwitchKey),
      firstChineseArcButton(where: isChineseArcLanguageSwitchKey),
      firstChineseArcButton(where: isChineseArcBackspaceKey),
    ])
  }

  private func makeChineseNumericOrSymbolicArcVisibleLayout(secondInnerButtons: [KeyboardButton?]) -> ChineseArcVisibleLayout {
    let inputRows = keyboardRows.prefix(3).map { row in
      row.filter { button in
        isVisibleArcKey(button) && isChineseArcInputKey(button)
      }
    }.filter { !$0.isEmpty }

    let secondInnerRow = uniqueChineseArcButtons(secondInnerButtons)
    let innerRow = uniqueChineseArcButtons([
      firstChineseArcButton(where: isChineseArcSpaceKey),
      firstChineseArcButton(where: isChineseArcReturnKey),
    ])

    var rows = inputRows
    if !secondInnerRow.isEmpty {
      rows.append(secondInnerRow)
    }
    if !innerRow.isEmpty {
      rows.append(innerRow)
    }
    return ChineseArcVisibleLayout(rows: rows, hasCreatedInnermostRow: !innerRow.isEmpty)
  }

  private func makeChineseArcBaseRangeRows() -> [[KeyboardButton]] {
    keyboardRows.map { row in
      row.filter { isVisibleArcKey($0) }
    }.filter { !$0.isEmpty }
  }

  private func uniqueChineseArcButtons(_ buttons: [KeyboardButton?]) -> [KeyboardButton] {
    var seen = Set<ObjectIdentifier>()
    return buttons.compactMap { button in
      guard let button else { return nil }
      let id = ObjectIdentifier(button)
      guard seen.insert(id).inserted else { return nil }
      return button
    }
  }

  private func firstChineseArcButton(where predicate: (KeyboardButton) -> Bool) -> KeyboardButton? {
    for button in keyboardRows.flatMap({ $0 }) where isVisibleArcKey(button) && predicate(button) {
      return button
    }
    return nil
  }

  private func enterChineseArcManualLayoutIfNeeded() {
    guard !isChineseArcManualLayoutActive else { return }
    NSLayoutConstraint.deactivate(staticConstraints + dynamicConstraints)
    isChineseArcManualLayoutActive = true
  }

  private func restoreStandardButtonLayoutIfNeeded() {
    oneHandModeControlsStack.isHidden = true
    keyboardRows.flatMap { $0 }.forEach { button in
      button.transform = .identity
      button.setCustomContentShapePath(nil)
    }
    guard isChineseArcManualLayoutActive else { return }
    NSLayoutConstraint.activate(staticConstraints + dynamicConstraints)
    isChineseArcManualLayoutActive = false
    setNeedsLayout()
  }

  private func makeOneHandModeControlButton(title: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    button.addTarget(self, action: action, for: .touchUpInside)
    button.layer.cornerCurve = .continuous
    button.layer.masksToBounds = false
    return button
  }

  private func updateOneHandModeControlAppearance() {
    let normalStyle = appearance.buttonStyle(for: .space, isPressed: false)
    let pressedStyle = appearance.buttonStyle(for: .space, isPressed: true)
    for button in [oneHandReturnToFullButton, oneHandSwitchSideButton] {
      button.backgroundColor = normalStyle.backgroundColor ?? UIColor.secondarySystemFill
      button.tintColor = normalStyle.foregroundColor ?? UIColor.label
      button.setTitleColor(normalStyle.foregroundColor ?? UIColor.label, for: .normal)
      button.setTitleColor(pressedStyle.foregroundColor ?? UIColor.label, for: .highlighted)
      button.layer.borderColor = normalStyle.border?.color.cgColor
      button.layer.borderWidth = normalStyle.border?.size ?? 0
      button.layer.shadowColor = normalStyle.shadow?.color.cgColor
      button.layer.shadowOpacity = normalStyle.shadow == nil ? 0 : 1
      button.layer.shadowRadius = normalStyle.shadow?.size ?? 0
      button.layer.shadowOffset = CGSize(width: 0, height: normalStyle.shadow?.size ?? 0)
    }
  }

  private func layoutOneHandModeControls(mode: ChineseKeyboardOneHandMode) {
    guard mode != .off, bounds.width > 1, bounds.height > 1 else {
      oneHandModeControlsStack.isHidden = true
      return
    }

    let horizontalInset: CGFloat = 4
    let controlWidth = max(58, min(88, bounds.width * 0.18))
    let controlHeight = max(78, min(98, bounds.height * 0.34))
    let originX = mode == .leftArc
      ? bounds.maxX - controlWidth - horizontalInset
      : bounds.minX + horizontalInset
    let originY = max(8, min(bounds.height - controlHeight - 8, bounds.height * 0.18))

    oneHandSwitchSideButton.setTitle(mode == .leftArc ? "右手" : "左手", for: .normal)
    oneHandReturnToFullButton.accessibilityLabel = "返回双手键盘"
    oneHandSwitchSideButton.accessibilityLabel = mode == .leftArc ? "切换到右手键盘" : "切换到左手键盘"
    oneHandModeControlsStack.frame = CGRect(x: originX, y: originY, width: controlWidth, height: controlHeight).integral
    oneHandModeControlsStack.isHidden = false
    oneHandModeControlsStack.layer.zPosition = 10
    bringSubviewToFront(oneHandModeControlsStack)

    for button in [oneHandReturnToFullButton, oneHandSwitchSideButton] {
      button.layer.cornerRadius = max(8, min(18, button.bounds.height * 0.28))
    }
  }

  @objc private func handleOneHandReturnToFullTap() {
    setChineseOneHandMode(.off)
  }

  @objc private func handleOneHandSwitchSideTap() {
    let current = UserDefaults.hamster.chineseKeyboardOneHandMode
    setChineseOneHandMode(current == .leftArc ? .rightArc : .leftArc)
  }

  private func setChineseOneHandMode(_ mode: ChineseKeyboardOneHandMode) {
    guard UserDefaults.hamster.chineseKeyboardOneHandMode != mode else { return }
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
    UserDefaults.hamster.chineseKeyboardOneHandMode = mode
    NotificationCenter.default.post(name: .hamsterChineseKeyboardOneHandModeDidChange, object: self)
    setNeedsLayout()
  }

  private func isVisibleArcKey(_ button: KeyboardButton) -> Bool {
    guard !button.isHidden else { return false }
    switch button.item.action {
    case .none, .characterMargin:
      return false
    default:
      return true
    }
  }

  private func isChineseArcInputKey(_ button: KeyboardButton) -> Bool {
    switch button.item.action {
    case .character, .characterOfDark, .symbol, .symbolOfDark, .chineseNineGrid:
      return true
    default:
      return false
    }
  }

  private func isChineseArcCapsKey(_ button: KeyboardButton) -> Bool {
    if case .shift = button.item.action { return true }
    return false
  }

  private func isChineseArcNumberSwitchKey(_ button: KeyboardButton) -> Bool {
    guard case .keyboardType(let type) = button.item.action else { return false }
    return type.isNumber || button.buttonText == "123"
  }

  private func isChineseArcSymbolSwitchKey(_ button: KeyboardButton) -> Bool {
    guard case .keyboardType(let type) = button.item.action else { return false }
    return type.isSymbol || button.buttonText == "#+="
  }

  private func isChineseArcLanguageSwitchKey(_ button: KeyboardButton) -> Bool {
    guard case .keyboardType(let type) = button.item.action else { return false }
    guard type.isAlphabetic || type.isChinese else { return false }
    return button.buttonText == "中" || button.buttonText == "日" || button.buttonText == "英"
  }

  private func isChineseArcBackspaceKey(_ button: KeyboardButton) -> Bool {
    button.item.action == .backspace
  }

  private func isChineseArcSpaceKey(_ button: KeyboardButton) -> Bool {
    button.item.action == .space
  }

  private func isChineseArcReturnKey(_ button: KeyboardButton) -> Bool {
    if case .primary = button.item.action { return true }
    return false
  }

  private struct ChineseArcGeometry {
    let pivot: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let horizontalScale: CGFloat
    let angularGap: CGFloat
    let startAngle: CGFloat
    let angleSpan: CGFloat
  }

  private func makeChineseArcGeometry(rowCount: Int, mode: ChineseKeyboardOneHandMode) -> ChineseArcGeometry {
    let safeBounds = bounds.insetBy(dx: 1, dy: 1)
    let startAngle = CGFloat(-90) * .pi / 180
    let endAngle = CGFloat(0) * .pi / 180
    let angleSpan = endAngle - startAngle
    let pivot = CGPoint(
      x: mode == .leftArc ? safeBounds.minX : safeBounds.maxX,
      y: safeBounds.maxY
    )
    let verticalRadius = max(1, pivot.y - safeBounds.minY)
    let maximumHorizontalRadius = max(1, safeBounds.width * 0.8)
    let horizontalRadius: CGFloat
    if mode == .leftArc {
      horizontalRadius = min(maximumHorizontalRadius, max(1, safeBounds.maxX - pivot.x))
    } else {
      horizontalRadius = min(maximumHorizontalRadius, max(1, pivot.x - safeBounds.minX))
    }
    let outerRadius = max(96, verticalRadius)
    let horizontalScale = horizontalRadius / max(outerRadius, 1)
    let innerRadius = max(64, outerRadius * 0.25)
    return ChineseArcGeometry(
      pivot: pivot,
      innerRadius: innerRadius,
      outerRadius: outerRadius,
      horizontalScale: horizontalScale,
      angularGap: CGFloat(1.55) * .pi / 180,
      startAngle: startAngle,
      angleSpan: angleSpan
    )
  }

  private struct ChineseArcRowRange {
    let outerRadius: CGFloat
    let innerRadius: CGFloat
  }

  private func makeChineseArcRowRanges(
    for rows: [[KeyboardButton]],
    geometry: ChineseArcGeometry
  ) -> [ChineseArcRowRange] {
    let keyCounts = rows.map { CGFloat(max($0.count, 1)) }
    let totalKeyCount = max(keyCounts.reduce(CGFloat(0), +), 1)
    let outerRadiusSquared = geometry.outerRadius * geometry.outerRadius
    let innerRadiusSquared = geometry.innerRadius * geometry.innerRadius
    let availableRadiusSquared = max(1, outerRadiusSquared - innerRadiusSquared)
    var currentOuterRadiusSquared = outerRadiusSquared

    return rows.enumerated().map { rowIndex, _ in
      let rowRadiusSquared = availableRadiusSquared * keyCounts[rowIndex] / totalKeyCount
      let isLastRow = rowIndex == rows.count - 1
      let nextOuterRadiusSquared = isLastRow
        ? innerRadiusSquared
        : max(innerRadiusSquared, currentOuterRadiusSquared - rowRadiusSquared)
      let outerRadius = sqrt(currentOuterRadiusSquared)
      let rawInnerRadius = sqrt(nextOuterRadiusSquared)
      let rawBand = max(outerRadius - rawInnerRadius, 1)
      let radialGap = isLastRow ? 0 : min(max(2.5, rawBand * 0.06), 4.5)
      let innerRadius = min(max(rawInnerRadius + radialGap, geometry.innerRadius), outerRadius - 18)
      currentOuterRadiusSquared = nextOuterRadiusSquared
      return ChineseArcRowRange(outerRadius: outerRadius, innerRadius: innerRadius)
    }
  }

  private func makeChineseArcKeyPath(
    pivot: CGPoint,
    innerRadius: CGFloat,
    outerRadius: CGFloat,
    startAngle: CGFloat,
    endAngle: CGFloat,
    horizontalScale: CGFloat,
    mode: ChineseKeyboardOneHandMode
  ) -> UIBezierPath {
    let sampleCount = 6
    let outerPoints = (0 ... sampleCount).map { index in
      let t = CGFloat(index) / CGFloat(sampleCount)
      return chineseArcPoint(
        pivot: pivot,
        radius: outerRadius,
        angle: startAngle + (endAngle - startAngle) * t,
        horizontalScale: horizontalScale,
        mode: mode
      )
    }
    let innerPoints: [CGPoint]
    if innerRadius <= 1 {
      innerPoints = [pivot]
    } else {
      innerPoints = (0 ... sampleCount).reversed().map { index in
        let t = CGFloat(index) / CGFloat(sampleCount)
        return chineseArcPoint(
          pivot: pivot,
          radius: innerRadius,
          angle: startAngle + (endAngle - startAngle) * t,
          horizontalScale: horizontalScale,
          mode: mode
        )
      }
    }
    let radius = max(0, min(CGFloat(UserDefaults.hamster.chineseKeyboardCornerRadius), 16))
    return UIBezierPath.roundedClosedPath(points: outerPoints + innerPoints, cornerRadius: radius)
  }

  private func chineseArcPoint(
    pivot: CGPoint,
    radius: CGFloat,
    angle: CGFloat,
    horizontalScale: CGFloat,
    mode: ChineseKeyboardOneHandMode
  ) -> CGPoint {
    let xOffset = cos(angle) * radius * horizontalScale
    let yOffset = sin(angle) * radius
    let x = mode == .leftArc ? pivot.x + xOffset : pivot.x - xOffset
    return CGPoint(x: x, y: pivot.y + yOffset)
  }

  private func logSuspiciousButtonFramesIfNeeded() {
    guard bounds.height > 1 else { return }
    let flattened = keyboardRows.flatMap { $0 }
    let qButton = flattened.first { $0.buttonText.caseInsensitiveCompare("q") == .orderedSame }
    let oversizedButtons = flattened.filter { !$0.isHidden && $0.frame.height > bounds.height * 0.55 }
    guard qButton != nil || !oversizedButtons.isEmpty else { return }

    let qFrame = qButton.map { "\($0.frame)" } ?? "nil"
    if let qButton, qButton.frame.height <= bounds.height * 0.55, oversizedButtons.isEmpty {
      return
    }

    let frameSummary = keyboardRows.enumerated().map { rowIndex, row in
      let items = row.prefix(4).map { "\($0.buttonText):\($0.frame.integral)" }.joined(separator: "|")
      return "row\(rowIndex){\(items)}"
    }.joined(separator: " ")
    KeyboardStartupDiagnostics.log("SUSPICIOUS button frames q=\(qFrame) oversized=\(oversizedButtons.map { $0.buttonText }) bounds=\(bounds) \(frameSummary)")
  }
}

private extension KeyboardType {
  var supportsStandardChineseArcOneHandKeyboard: Bool {
    switch self {
    case .chinese, .chineseNumeric, .chineseSymbolic:
      return true
    default:
      return false
    }
  }
}
