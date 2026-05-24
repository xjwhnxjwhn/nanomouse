//
//  NumericCalculatorKeyboard.swift
//
//
//  Created by Codex on 2026/05/12.
//

import HamsterKit
import HamsterUIKit
import UIKit

/// 长按 123 后进入的计算器键盘页。
final class NumericCalculatorKeyboard: NibLessView {
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private let style: KeyboardActionCalloutStyle
  private let enableHapticFeedback: Bool

  private let contentStackView = UIStackView()
  private let candidateRowView = UIStackView()
  private let candidateButton = UIButton(type: .custom)
  private let topSpaceButton = UIButton(type: .custom)
  private let keyRowsStackView = UIStackView()
  private let arcContainerView = UIView()

  private var currentExpression: String = ""
  private var calculatedResult: String?
  private var isShowingHint = false
  private var arcRows: [[CalculatorArcButton]] = []
  private var arcCandidateButton: CalculatorArcButton?
  private var isOneHandArcLayoutActive = false

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

  private let keys: [[String]] = [
    ["1", "2", "3", "÷", "("],
    ["4", "5", "6", "×", ")"],
    ["7", "8", "9", "-", "⌫"],
    ["ABC", "0", ".", "+", "="]
  ]

  init(
    actionHandler: KeyboardActionHandler,
    appearance: KeyboardAppearance,
    keyboardContext: KeyboardContext
  ) {
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.style = appearance.actionCalloutStyle
    self.enableHapticFeedback = keyboardContext.hamsterConfiguration?.keyboard?.enableHapticFeedback ?? false
    super.init(frame: .zero)
    setupView()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let oneHandMode = UserDefaults.hamster.chineseKeyboardOneHandMode
    guard oneHandMode != .off, bounds.width > 1, bounds.height > 1 else {
      restoreStandardLayoutIfNeeded()
      roundStandardButtons()
      return
    }
    applyOneHandArcLayout(mode: oneHandMode)
  }

  private func restoreStandardLayoutIfNeeded() {
    contentStackView.isHidden = false
    arcContainerView.isHidden = true
    oneHandModeControlsStack.isHidden = true
    guard isOneHandArcLayoutActive else { return }
    isOneHandArcLayoutActive = false
    arcCandidateButton?.frame = .zero
    arcCandidateButton?.setArcContentShapePath(nil)
    arcRows.flatMap { $0 }.forEach { button in
      button.frame = .zero
      button.setArcContentShapePath(nil)
    }
  }

  private func applyOneHandArcLayout(mode: ChineseKeyboardOneHandMode) {
    isOneHandArcLayoutActive = true
    contentStackView.isHidden = true
    arcContainerView.isHidden = false
    bringSubviewToFront(arcContainerView)
    arcContainerView.frame = bounds
    let arcLayoutBounds = layoutArcCandidateButton()
    layoutOneHandModeControls(mode: mode)

    let baseRows = Array(arcRows.dropLast())
    guard !baseRows.isEmpty, let innerRow = arcRows.last, !innerRow.isEmpty else { return }
    let geometry = makeCalculatorArcGeometry(mode: mode, layoutBounds: arcLayoutBounds)
    var rowRanges = makeCalculatorArcRowRanges(for: baseRows, geometry: geometry)
    let innerOuterRadius = rowRanges.last?.innerRadius ?? geometry.innerRadius
    rowRanges.append(CalculatorArcRowRange(outerRadius: innerOuterRadius, innerRadius: 0))
    guard rowRanges.count == arcRows.count else { return }

    for (rowIndex, row) in arcRows.enumerated() {
      let rowRange = rowRanges[rowIndex]
      let count = row.count
      let segment = geometry.angleSpan / CGFloat(max(count, 1))
      let gap = min(geometry.angularGap, segment * 0.28)

      for (buttonIndex, button) in row.enumerated() {
        let segmentIndex = mode == .rightArc ? count - 1 - buttonIndex : buttonIndex
        let startAngle = geometry.startAngle + CGFloat(segmentIndex) * segment + gap / 2
        let endAngle = geometry.startAngle + CGFloat(segmentIndex + 1) * segment - gap / 2
        let keyPath = makeCalculatorArcKeyPath(
          pivot: geometry.pivot,
          innerRadius: rowRange.innerRadius,
          outerRadius: rowRange.outerRadius,
          startAngle: startAngle,
          endAngle: endAngle,
          horizontalScale: geometry.horizontalScale,
          mode: mode
        )
        var frame = keyPath.bounds.insetBy(dx: -0.5, dy: -0.5).integral
        frame = frame.intersection(arcContainerView.bounds.insetBy(dx: -0.5, dy: -0.5))
        guard frame.width > 2, frame.height > 2 else {
          button.frame = .zero
          button.setArcContentShapePath(nil)
          continue
        }
        let localPath = UIBezierPath(cgPath: keyPath.cgPath)
        localPath.apply(CGAffineTransform(translationX: -frame.minX, y: -frame.minY))
        button.frame = frame
        button.setArcContentShapePath(localPath)
      }
    }
  }

  private struct CalculatorArcGeometry {
    let pivot: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let horizontalScale: CGFloat
    let angularGap: CGFloat
    let startAngle: CGFloat
    let angleSpan: CGFloat
  }

  private struct CalculatorArcRowRange {
    let outerRadius: CGFloat
    let innerRadius: CGFloat
  }

  private func layoutArcCandidateButton() -> CGRect {
    let bounds = arcContainerView.bounds
    let horizontalInset: CGFloat = 6
    let topInset: CGFloat = 4
    let candidateHeight = max(38, min(44, bounds.height * 0.14))
    let candidateFrame = CGRect(
      x: bounds.minX + horizontalInset,
      y: bounds.minY + topInset,
      width: max(1, bounds.width - horizontalInset * 2),
      height: candidateHeight
    ).integral
    arcCandidateButton?.frame = candidateFrame
    arcCandidateButton?.setArcContentShapePath(nil)
    arcCandidateButton?.layer.cornerRadius = min(10, candidateFrame.height * 0.22)

    let arcTop = candidateFrame.maxY + 6
    return CGRect(
      x: bounds.minX,
      y: arcTop,
      width: bounds.width,
      height: max(1, bounds.maxY - arcTop)
    )
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
    let normalBackground = keyBackgroundColor(for: "空格")
    let highlightedColor = style.callout.textColor.withAlphaComponent(0.15)
    for button in [oneHandReturnToFullButton, oneHandSwitchSideButton] {
      button.backgroundColor = button.isHighlighted ? highlightedColor : normalBackground
      button.tintColor = style.callout.textColor
      button.setTitleColor(style.callout.textColor, for: .normal)
      button.setTitleColor(style.callout.textColor.withAlphaComponent(0.7), for: .highlighted)
      button.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
      button.layer.borderWidth = 0.5
      button.layer.shadowOpacity = 0
    }
  }

  private func layoutOneHandModeControls(mode: ChineseKeyboardOneHandMode) {
    let bounds = arcContainerView.bounds
    guard mode != .off, bounds.width > 1, bounds.height > 1 else {
      oneHandModeControlsStack.isHidden = true
      return
    }

    updateOneHandModeControlAppearance()
    let horizontalInset: CGFloat = 4
    let controlWidth = max(58, min(88, bounds.width * 0.18))
    let controlHeight = max(78, min(98, bounds.height * 0.34))
    let originX = mode == .leftArc
      ? bounds.maxX - controlWidth - horizontalInset
      : bounds.minX + horizontalInset
    let candidateBottom = arcCandidateButton?.frame.maxY ?? bounds.minY
    let preferredY = bounds.height * 0.18
    let maximumY = max(8, bounds.height - controlHeight - 8)
    let originY = min(maximumY, max(candidateBottom + 8, preferredY))

    oneHandSwitchSideButton.setTitle(mode == .leftArc ? "右手" : "左手", for: .normal)
    oneHandReturnToFullButton.accessibilityLabel = "返回双手键盘"
    oneHandSwitchSideButton.accessibilityLabel = mode == .leftArc ? "切换到右手键盘" : "切换到左手键盘"
    oneHandModeControlsStack.frame = CGRect(x: originX, y: originY, width: controlWidth, height: controlHeight).integral
    oneHandModeControlsStack.isHidden = false
    oneHandModeControlsStack.layer.zPosition = 10
    arcContainerView.bringSubviewToFront(oneHandModeControlsStack)

    let buttonHeight = max(1, (controlHeight - oneHandModeControlsStack.spacing) / 2)
    for button in [oneHandReturnToFullButton, oneHandSwitchSideButton] {
      button.layer.cornerRadius = max(8, min(18, buttonHeight * 0.28))
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

  private func makeCalculatorArcGeometry(
    mode: ChineseKeyboardOneHandMode,
    layoutBounds: CGRect
  ) -> CalculatorArcGeometry {
    let safeBounds = layoutBounds.insetBy(dx: 1, dy: 1)
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
    let outerRadius = max(90, verticalRadius)
    return CalculatorArcGeometry(
      pivot: pivot,
      innerRadius: max(64, outerRadius * 0.25),
      outerRadius: outerRadius,
      horizontalScale: horizontalRadius / max(outerRadius, 1),
      angularGap: CGFloat(1.55) * .pi / 180,
      startAngle: startAngle,
      angleSpan: angleSpan
    )
  }

  private func makeCalculatorArcRowRanges(
    for rows: [[CalculatorArcButton]],
    geometry: CalculatorArcGeometry
  ) -> [CalculatorArcRowRange] {
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
      return CalculatorArcRowRange(outerRadius: outerRadius, innerRadius: innerRadius)
    }
  }

  private func makeCalculatorArcKeyPath(
    pivot: CGPoint,
    innerRadius: CGFloat,
    outerRadius: CGFloat,
    startAngle: CGFloat,
    endAngle: CGFloat,
    horizontalScale: CGFloat,
    mode: ChineseKeyboardOneHandMode
  ) -> UIBezierPath {
    let path = UIBezierPath()
    let sampleCount = 6
    let outerPoints = (0 ... sampleCount).map { index in
      let t = CGFloat(index) / CGFloat(sampleCount)
      return calculatorArcPoint(
        pivot: pivot,
        radius: outerRadius,
        angle: startAngle + (endAngle - startAngle) * t,
        horizontalScale: horizontalScale,
        mode: mode
      )
    }
    let innerPoints = (0 ... sampleCount).reversed().map { index in
      let t = CGFloat(index) / CGFloat(sampleCount)
      return calculatorArcPoint(
        pivot: pivot,
        radius: innerRadius,
        angle: startAngle + (endAngle - startAngle) * t,
        horizontalScale: horizontalScale,
        mode: mode
      )
    }

    guard let first = outerPoints.first else { return path }
    path.move(to: first)
    outerPoints.dropFirst().forEach { path.addLine(to: $0) }
    innerPoints.forEach { path.addLine(to: $0) }
    path.close()
    return path
  }

  private func calculatorArcPoint(
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

  private func roundStandardButtons() {
    for button in allKeyButtons(in: contentStackView) {
      button.layer.cornerRadius = min(10, button.bounds.height * 0.18)
    }
  }

  private func setupView() {
    backgroundColor = .clear
    isOpaque = false

    setupContentStack()
    setupCandidateRow()
    setupGrid()
    setupArcGrid()
    showStartupHint()
  }

  private func setupContentStack() {
    addSubview(contentStackView)
    contentStackView.axis = .vertical
    contentStackView.distribution = .fill
    contentStackView.spacing = 7
    contentStackView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      contentStackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
    ])
  }

  private func setupCandidateRow() {
    candidateRowView.axis = .horizontal
    candidateRowView.distribution = .fill
    candidateRowView.alignment = .fill
    candidateRowView.spacing = 7

    configureButton(candidateButton, title: " ", fontSize: 20, weight: .medium, backgroundColor: barBackgroundColor())
    candidateButton.setAttributedTitle(nil, for: .normal)
    candidateButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
    candidateButton.setTitleColor(style.callout.textColor, for: .normal)
    candidateButton.contentHorizontalAlignment = .center
    candidateButton.addTarget(self, action: #selector(handleCandidateTap), for: .touchUpInside)

    configureButton(topSpaceButton, title: "␣", fontSize: 18, weight: .regular, backgroundColor: keyBackgroundColor(for: "空格"))
    topSpaceButton.accessibilityIdentifier = "空格"
    topSpaceButton.addTarget(self, action: #selector(handleTouchDown(_:)), for: .touchDown)
    topSpaceButton.addTarget(self, action: #selector(handleTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    topSpaceButton.addTarget(self, action: #selector(handleTopSpaceTap), for: .touchUpInside)
    let spaceLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSpaceLongPress(_:)))
    spaceLongPress.minimumPressDuration = 0.5
    topSpaceButton.addGestureRecognizer(spaceLongPress)

    let topReturnButton = createTopReturnButton()
    candidateRowView.addArrangedSubview(candidateButton)
    candidateRowView.addArrangedSubview(topSpaceButton)
    candidateRowView.addArrangedSubview(topReturnButton)
    topSpaceButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
    topReturnButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
    candidateRowView.heightAnchor.constraint(equalToConstant: 40).isActive = true
    contentStackView.addArrangedSubview(candidateRowView)
    updateCandidateDisplay()
  }

  private func createTopReturnButton() -> UIButton {
    let button = UIButton(type: .custom)
    if #available(iOS 15.0, *) {
      button.configuration = nil
    }
    configureButton(button, title: "↩︎", fontSize: 20, weight: .regular, backgroundColor: keyBackgroundColor(for: "return"))
    button.accessibilityIdentifier = "return"
    button.addTarget(self, action: #selector(handleTouchDown(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(handleTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    button.addTarget(self, action: #selector(handleTopReturnTap), for: .touchUpInside)
    return button
  }

  private func setupGrid() {
    keyRowsStackView.axis = .vertical
    keyRowsStackView.distribution = .fillEqually
    keyRowsStackView.spacing = 7
    contentStackView.addArrangedSubview(keyRowsStackView)

    for rowKeys in keys {
      let rowStack = UIStackView()
      rowStack.axis = .horizontal
      rowStack.distribution = .fillEqually
      rowStack.spacing = 7

      for key in rowKeys {
        rowStack.addArrangedSubview(createKeyButton(for: key))
      }
      keyRowsStackView.addArrangedSubview(rowStack)
    }
  }

  private func setupArcGrid() {
    addSubview(arcContainerView)
    arcContainerView.translatesAutoresizingMaskIntoConstraints = false
    arcContainerView.backgroundColor = .clear
    arcContainerView.isHidden = true
    NSLayoutConstraint.activate([
      arcContainerView.topAnchor.constraint(equalTo: topAnchor),
      arcContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      arcContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      arcContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    let candidateButton = createArcButton(for: "candidate")
    arcContainerView.addSubview(candidateButton)
    arcContainerView.addSubview(oneHandModeControlsStack)

    let rows = keys + [["空格", "return"]]
    arcRows = rows.map { rowKeys in
      rowKeys.map { key in
        let button = createArcButton(for: key)
        arcContainerView.addSubview(button)
        return button
      }
    }
  }

  private func createKeyButton(for key: String) -> UIButton {
    let button = UIButton(type: .custom)
    if #available(iOS 15.0, *) {
      button.configuration = nil
    }

    let displayText: String = {
      if key == "空格" { return "␣" }
      if key == "ABC" { return returnKeyboardType().standardButtonText(for: keyboardContext) ?? "ABC" }
      return key
    }()
    configureButton(
      button,
      title: displayText,
      fontSize: key == "空格" || key == "ABC" ? 18 : 22,
      weight: key == "ABC" ? .semibold : .regular,
      backgroundColor: keyBackgroundColor(for: key)
    )
    button.accessibilityIdentifier = key
    button.addTarget(self, action: #selector(handleTouchDown(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(handleTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    button.addTarget(self, action: #selector(handleKeyTap(_:)), for: .touchUpInside)

    if key == "空格" {
      let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSpaceLongPress(_:)))
      longPress.minimumPressDuration = 0.5
      button.addGestureRecognizer(longPress)
    }
    return button
  }

  private func createArcButton(for key: String) -> CalculatorArcButton {
    let button = CalculatorArcButton(type: .custom)
    if #available(iOS 15.0, *) {
      button.configuration = nil
    }

    let displayText: String = {
      switch key {
      case "candidate":
        return " "
      case "空格":
        return "␣"
      case "return":
        return "↩︎"
      case "ABC":
        return returnKeyboardType().standardButtonText(for: keyboardContext) ?? "ABC"
      default:
        return key
      }
    }()
    let isControlKey = key == "空格" || key == "ABC" || key == "return"
    configureButton(
      button,
      title: displayText,
      fontSize: isControlKey ? 18 : 22,
      weight: key == "ABC" ? .semibold : .regular,
      backgroundColor: key == "candidate" ? barBackgroundColor() : keyBackgroundColor(for: key)
    )
    button.accessibilityIdentifier = key
    button.addTarget(self, action: #selector(handleTouchDown(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(handleTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

    switch key {
    case "candidate":
      arcCandidateButton = button
      button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
      button.addTarget(self, action: #selector(handleCandidateTap), for: .touchUpInside)
    case "空格":
      button.addTarget(self, action: #selector(handleTopSpaceTap), for: .touchUpInside)
      let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSpaceLongPress(_:)))
      longPress.minimumPressDuration = 0.5
      button.addGestureRecognizer(longPress)
    case "return":
      button.addTarget(self, action: #selector(handleTopReturnTap), for: .touchUpInside)
    default:
      button.addTarget(self, action: #selector(handleKeyTap(_:)), for: .touchUpInside)
    }
    return button
  }

  private func configureButton(
    _ button: UIButton,
    title: String,
    fontSize: CGFloat,
    weight: UIFont.Weight,
    backgroundColor: UIColor
  ) {
    button.backgroundColor = backgroundColor
    button.layer.masksToBounds = true
    button.setAttributedTitle(
      NSAttributedString(
        string: title,
        attributes: [
          .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
          .foregroundColor: style.callout.textColor,
          .underlineStyle: 0
        ]
      ),
      for: .normal
    )
  }

  private func returnKeyboardType() -> KeyboardType {
    guard let type = keyboardContext.calculatorReturnKeyboardType, type != .calculatorNumeric else {
      return keyboardContext.selectKeyboard
    }
    return type
  }

  private func showStartupHint() {
    isShowingHint = true
    updateCandidateDisplay()

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self, self.isShowingHint else { return }
      self.isShowingHint = false
      self.updateCandidateDisplay()
    }
  }

  private func updateCandidateDisplay() {
    if isShowingHint && currentExpression.isEmpty {
      setCandidateText("长按空格以换行")
      setCandidateAlpha(0.6)
      return
    }

    setCandidateAlpha(1.0)
    var displayText = currentExpression
    if let result = calculatedResult {
      displayText = "\(currentExpression)\(result)"
    }
    setCandidateText(displayText.isEmpty ? " " : displayText)
  }

  private func setCandidateText(_ text: String) {
    let attributedTitle = NSAttributedString(
      string: text,
      attributes: [
        .font: UIFont.systemFont(ofSize: 20, weight: .medium),
        .foregroundColor: style.callout.textColor,
        .underlineStyle: 0
      ]
    )
    candidateButton.setAttributedTitle(attributedTitle, for: .normal)
    arcCandidateButton?.setAttributedTitle(attributedTitle, for: .normal)
  }

  private func setCandidateAlpha(_ alpha: CGFloat) {
    candidateButton.titleLabel?.alpha = alpha
    arcCandidateButton?.titleLabel?.alpha = alpha
  }

  private func tryCalculate() {
    calculatedResult = nil
    guard currentExpression.hasSuffix("=") else { return }

    let exprPart = String(currentExpression.dropLast())
    guard !exprPart.isEmpty else { return }

    var expr = exprPart
      .replacingOccurrences(of: "×", with: "*")
      .replacingOccurrences(of: "÷", with: "/")

    if let regex = try? NSRegularExpression(pattern: "(?<!\\.)\\b(\\d+)\\b(?!\\.)", options: []) {
      expr = regex.stringByReplacingMatches(in: expr, options: [], range: NSRange(expr.startIndex..., in: expr), withTemplate: "$1.0")
    }
    calculatedResult = safeEvaluate(expr)
  }

  private func safeEvaluate(_ expr: String) -> String? {
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/")) != nil else { return nil }

    if let last = trimmed.last, "+-*/".contains(last) {
      return nil
    }

    var parenCount = 0
    for char in trimmed {
      if char == "(" { parenCount += 1 }
      if char == ")" { parenCount -= 1 }
      if parenCount < 0 { return nil }
    }
    guard parenCount == 0 else { return nil }

    if trimmed.range(of: "[+\\-*/]{2,}", options: .regularExpression) != nil {
      return nil
    }
    for pattern in ["[0-9)]\\(", "\\)[0-9(]"] {
      if trimmed.range(of: pattern, options: .regularExpression) != nil {
        return nil
      }
    }

    let expression = NSExpression(format: expr)
    guard let result = expression.expressionValue(with: nil, context: nil) as? NSNumber else {
      return nil
    }
    let doubleResult = result.doubleValue
    guard doubleResult.isFinite else { return "Error" }

    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 4
    formatter.minimumFractionDigits = 0
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: doubleResult)) ?? String(doubleResult)
  }

  private func submitContent() {
    guard !currentExpression.isEmpty else { return }

    var textToSubmit = currentExpression
    if let result = calculatedResult {
      textToSubmit = "\(currentExpression)\(result)"
    }

    keyboardContext.textDocumentProxy.insertText(textToSubmit)
    currentExpression = ""
    calculatedResult = nil
    updateCandidateDisplay()
  }

  private func triggerHapticIfNeeded() {
    guard enableHapticFeedback else { return }
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
  }

  private func keyBackgroundColor(for key: String) -> UIColor {
    UIColor { traitCollection in
      let isOperator = ["+", "-", "×", "÷", "="].contains(key)
      return (isOperator ? UIColor.tertiarySystemFill : UIColor.secondarySystemFill).resolvedColor(with: traitCollection)
    }
  }

  private func barBackgroundColor() -> UIColor {
    UIColor { traitCollection in
      UIColor.tertiarySystemFill.resolvedColor(with: traitCollection)
    }
  }

  private func allKeyButtons(in root: UIView) -> [UIButton] {
    var buttons: [UIButton] = []
    if let button = root as? UIButton {
      buttons.append(button)
    }
    for subview in root.subviews {
      buttons.append(contentsOf: allKeyButtons(in: subview))
    }
    return buttons
  }

  @objc private func handleKeyTap(_ sender: UIButton) {
    if isShowingHint {
      isShowingHint = false
      updateCandidateDisplay()
    }

    guard let key = sender.accessibilityIdentifier else { return }
    triggerHapticIfNeeded()

    switch key {
    case "⌫":
      if !currentExpression.isEmpty {
        currentExpression.removeLast()
        calculatedResult = nil
        updateCandidateDisplay()
      } else {
        actionHandler.handle(.press, on: .backspace)
        actionHandler.handle(.release, on: .backspace)
      }
    case "空格":
      if currentExpression.isEmpty {
        keyboardContext.textDocumentProxy.insertText(" ")
      } else {
        submitContent()
      }
    case "ABC":
      returnToPreviousKeyboard()
    default:
      currentExpression += key
      tryCalculate()
      updateCandidateDisplay()
    }
  }

  @objc private func handleCandidateTap() {
    triggerHapticIfNeeded()
    submitContent()
  }

  @objc private func handleTopSpaceTap() {
    triggerHapticIfNeeded()
    if currentExpression.isEmpty {
      keyboardContext.textDocumentProxy.insertText(" ")
    } else {
      submitContent()
    }
  }

  @objc private func handleTopReturnTap() {
    triggerHapticIfNeeded()
    if !currentExpression.isEmpty {
      submitContent()
    }
    actionHandler.handle(.release, on: .primary(.return))
  }

  private func returnToPreviousKeyboard() {
    let target = returnKeyboardType()
    keyboardContext.calculatorReturnKeyboardType = nil
    keyboardContext.setKeyboardType(target)
  }

  @objc private func handleSpaceLongPress(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began else { return }
    triggerHapticIfNeeded()
    if !currentExpression.isEmpty {
      submitContent()
    }
    actionHandler.handle(.release, on: .primary(.return))
  }

  @objc private func handleTouchDown(_ sender: UIButton) {
    sender.backgroundColor = style.callout.textColor.withAlphaComponent(0.15)
  }

  @objc private func handleTouchUp(_ sender: UIButton) {
    guard let key = sender.accessibilityIdentifier else {
      sender.backgroundColor = keyBackgroundColor(for: "ABC")
      return
    }
    sender.backgroundColor = key == "candidate" ? barBackgroundColor() : keyBackgroundColor(for: key)
  }
}

private final class CalculatorArcButton: UIButton {
  private let arcMaskLayer = CAShapeLayer()
  private var arcContentShapePath: UIBezierPath?

  func setArcContentShapePath(_ path: UIBezierPath?) {
    arcContentShapePath = path
    guard let path else {
      if layer.mask === arcMaskLayer {
        layer.mask = nil
      }
      return
    }
    arcMaskLayer.frame = bounds
    arcMaskLayer.path = path.cgPath
    layer.mask = arcMaskLayer
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let arcContentShapePath else { return }
    arcMaskLayer.frame = bounds
    arcMaskLayer.path = arcContentShapePath.cgPath
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    if let arcContentShapePath {
      return arcContentShapePath.contains(point)
    }
    return super.point(inside: point, with: event)
  }
}
