//
//  NumericCalculatorKeyboard.swift
//
//
//  Created by Codex on 2026/05/12.
//

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

  private var currentExpression: String = ""
  private var calculatedResult: String?
  private var isShowingHint = false

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
    for button in allKeyButtons(in: self) {
      button.layer.cornerRadius = min(10, button.bounds.height * 0.18)
    }
  }

  private func setupView() {
    backgroundColor = .clear
    isOpaque = false

    setupContentStack()
    setupCandidateRow()
    setupGrid()
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
      candidateButton.titleLabel?.alpha = 0.6
      return
    }

    candidateButton.titleLabel?.alpha = 1.0
    var displayText = currentExpression
    if let result = calculatedResult {
      displayText = "\(currentExpression)\(result)"
    }
    setCandidateText(displayText.isEmpty ? " " : displayText)
  }

  private func setCandidateText(_ text: String) {
    candidateButton.setAttributedTitle(
      NSAttributedString(
        string: text,
        attributes: [
          .font: UIFont.systemFont(ofSize: 20, weight: .medium),
          .foregroundColor: style.callout.textColor,
          .underlineStyle: 0
        ]
      ),
      for: .normal
    )
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
    sender.backgroundColor = keyBackgroundColor(for: key)
  }
}
