//
//  NumericKeypadOverlay.swift
//
//
//  Created by Codex on 2026/01/07.
//

import UIKit

final class NumericKeypadOverlay: UIView, UIGestureRecognizerDelegate {
  private let style: KeyboardActionCalloutStyle
  private let onInput: (String) -> Void
  private let onDelete: () -> Void
  private let onNewline: () -> Void
  private let enableHapticFeedback: Bool

  private let containerView = UIView()
  private let mainStackView = UIStackView()
  
  // 候选栏：显示当前输入的算式和计算结果
  private let candidateButton = UIButton(type: .custom)
  
  // 当前输入的算式
  private var currentExpression: String = ""
  // 计算结果（nil=未计算）
  private var calculatedResult: String?
  
  // App 主题色 (米色)
  private var themeColor: UIColor {
    return UIColor(red: 0.706, green: 0.671, blue: 0.608, alpha: 1.0)
  }
  
  // 是否正在显示启动提示
  private var isShowingHint: Bool = false
  
  // Grid: 4x5
  // 1 2 3 ÷ (
  // 4 5 6 × )
  // 7 8 9 - ⌫
  // 空格 0 . + =
  private let keys: [[String]] = [
    ["1", "2", "3", "÷", "("],
    ["4", "5", "6", "×", ")"],
    ["7", "8", "9", "-", "⌫"],
    ["空格", "0", ".", "+", "="]
  ]

  init(
    style: KeyboardActionCalloutStyle,
    enableHapticFeedback: Bool = false,
    onInput: @escaping (String) -> Void,
    onDelete: @escaping () -> Void,
    onNewline: @escaping () -> Void
  ) {
    self.style = style
    self.enableHapticFeedback = enableHapticFeedback
    self.onInput = onInput
    self.onDelete = onDelete
    self.onNewline = onNewline
    super.init(frame: .zero)
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    // 使用 UIVisualEffectView 实现高斯模糊背景
    let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.frame = bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(blurView)
    
    // Tap background to dismiss (add to blurView to catch all touches)
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
    tap.delegate = self
    blurView.contentView.addGestureRecognizer(tap)
    
    setupContainer()
    setupCandidateBar()
    setupGrid()
  }
  
  private func setupContainer() {
    // 容器背景透明，不需要矩形背景层
    containerView.backgroundColor = .clear
    containerView.layer.cornerRadius = 10
    
    addSubview(containerView)
    containerView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
      containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
      containerView.widthAnchor.constraint(equalToConstant: 300),
      containerView.heightAnchor.constraint(equalToConstant: 280)
    ])
  }
  
  private func setupCandidateBar() {
    candidateButton.backgroundColor = getCandidateBarBackgroundColor()
    candidateButton.layer.cornerRadius = 6
    candidateButton.contentHorizontalAlignment = .center
    candidateButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
    candidateButton.setTitleColor(style.callout.textColor, for: .normal)
    candidateButton.addTarget(self, action: #selector(handleCandidateTap), for: .touchUpInside)
    
    containerView.addSubview(candidateButton)
    candidateButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      candidateButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
      candidateButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
      candidateButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
      candidateButton.heightAnchor.constraint(equalToConstant: 40)
    ])
    
    updateCandidateDisplay()
    
    // 显示启动提示 1 秒
    showStartupHint()
  }
  
  private func showStartupHint() {
    isShowingHint = true
    updateCandidateDisplay()
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self = self, self.isShowingHint else { return }
      self.isShowingHint = false
      self.updateCandidateDisplay()
    }
  }
  
  private func setupGrid() {
    containerView.addSubview(mainStackView)
    mainStackView.axis = .vertical
    mainStackView.distribution = .fillEqually
    mainStackView.spacing = 6
    mainStackView.translatesAutoresizingMaskIntoConstraints = false
    
    let padding: CGFloat = 10
    NSLayoutConstraint.activate([
      mainStackView.topAnchor.constraint(equalTo: candidateButton.bottomAnchor, constant: 10),
      mainStackView.leftAnchor.constraint(equalTo: containerView.leftAnchor, constant: padding),
      mainStackView.rightAnchor.constraint(equalTo: containerView.rightAnchor, constant: -padding),
      mainStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -padding)
    ])
    
    for rowKeys in keys {
      let rowStack = UIStackView()
      rowStack.axis = .horizontal
      rowStack.distribution = .fillEqually
      rowStack.spacing = 6
      
      for key in rowKeys {
        let button = createButton(for: key)
        rowStack.addArrangedSubview(button)
      }
      mainStackView.addArrangedSubview(rowStack)
    }
  }
  
  private func createButton(for key: String) -> UIButton {
    let button = UIButton(type: .custom)
    if #available(iOS 15.0, *) {
      button.configuration = nil
    }
    
    // 运算符和特殊键使用不同的背景色
    button.backgroundColor = getButtonBackgroundColor(for: key)
    button.layer.cornerRadius = 6
    
    // Explicitly using NSAttributedString to avoid any system default underlines
    let displayText = key == "空格" ? "␣" : key
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: key == "空格" ? 18 : 22, weight: .regular),
      .foregroundColor: style.callout.textColor,
      .underlineStyle: 0
    ]
    let attributedTitle = NSAttributedString(string: displayText, attributes: attributes)
    button.setAttributedTitle(attributedTitle, for: .normal)
    
    // Store the original key in accessibilityIdentifier
    button.accessibilityIdentifier = key
    
    // Highlight effect
    button.addTarget(self, action: #selector(handleTouchDown(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(handleTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    
    button.addTarget(self, action: #selector(handleKeyTap(_:)), for: .touchUpInside)
    
    // 空格键添加长按手势（换行）
    if key == "空格" {
      let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSpaceLongPress(_:)))
      longPress.minimumPressDuration = 0.5
      button.addGestureRecognizer(longPress)
    }
    
    return button
  }
  
  private func updateCandidateDisplay() {
    if isShowingHint && currentExpression.isEmpty {
      candidateButton.setTitle("长按空格以换行", for: .normal)
      candidateButton.titleLabel?.alpha = 0.6
      return
    }
    
    candidateButton.titleLabel?.alpha = 1.0
    var displayText = currentExpression
    // 如果有计算结果，表达式已经包含 = 了，直接追加结果
    if let result = calculatedResult {
      displayText = "\(currentExpression)\(result)"
    }
    candidateButton.setTitle(displayText.isEmpty ? " " : displayText, for: .normal)
  }
  
  /// 尝试计算表达式（静默失败，不展示错误）
  private func tryCalculate() {
    calculatedResult = nil
    
    // 检查表达式是否以 = 结尾
    guard currentExpression.hasSuffix("=") else { return }
    
    // 提取 = 之前的部分进行计算
    let exprPart = String(currentExpression.dropLast())
    guard !exprPart.isEmpty else { return }
    
    // 将显示符号转换为计算符号
    var expr = exprPart
      .replacingOccurrences(of: "×", with: "*")
      .replacingOccurrences(of: "÷", with: "/")
    
    // 浮点数转换：将整数 1 转换为 1.0，防止 NSExpression 执行整除
    // 使用正则匹配不带小数点的数字，并追加 .0
    if let regex = try? NSRegularExpression(pattern: "(?<!\\.)\\b(\\d+)\\b(?!\\.)", options: []) {
      expr = regex.stringByReplacingMatches(in: expr, options: [], range: NSRange(expr.startIndex..., in: expr), withTemplate: "$1.0")
    }

    // 安全计算：使用 @try/@catch 防止崩溃
    calculatedResult = safeEvaluate(expr)
  }
  
  /// 安全评估数学表达式，返回结果字符串或 nil
  private func safeEvaluate(_ expr: String) -> String? {
    // 基本格式检查：确保不以运算符开头或结尾（除了负号开头）
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    
    // 检查是否包含有效的运算符
    let operators = CharacterSet(charactersIn: "+-*/")
    guard trimmed.rangeOfCharacter(from: operators) != nil else { return nil }
    
    // 检查是否以运算符结尾（这会导致 NSExpression 崩溃）
    if let last = trimmed.last, "+-*/".contains(last) {
      return nil
    }
    
    // 检查括号是否匹配
    var parenCount = 0
    for char in trimmed {
      if char == "(" { parenCount += 1 }
      else if char == ")" { parenCount -= 1 }
      if parenCount < 0 { return nil }
    }
    if parenCount != 0 { return nil }
    
    // 检查连续运算符（如 ++ 或 */）
    let consecutiveOpPattern = "[+\\-*/]{2,}"
    if let _ = trimmed.range(of: consecutiveOpPattern, options: .regularExpression) {
      return nil
    }
    
    // 检查隐式乘法（如 6(6+1) 或 (1+2)3 或 )(）
    // NSExpression 不支持这种语法
    let implicitMultPatterns = [
      "[0-9)]\\(",  // 数字或)后面直接跟(
      "\\)[0-9(]"   // )后面直接跟数字或(
    ]
    for pattern in implicitMultPatterns {
      if let _ = trimmed.range(of: pattern, options: .regularExpression) {
        return nil
      }
    }
    
    // 尝试计算
    do {
      let expression = try NSExpression(format: expr)
      guard let result = expression.expressionValue(with: nil, context: nil) as? NSNumber else {
        return nil
      }
      let doubleResult = result.doubleValue
      
      // 检查是否为有效数字（非 NaN、非无穷大）
      guard doubleResult.isFinite else { return "Error" }
      
      // 格式化结果：最多保留 4 位小数，且自动去除末尾无用的零
      let formatter = NumberFormatter()
      formatter.maximumFractionDigits = 4
      formatter.minimumFractionDigits = 0
      formatter.usesGroupingSeparator = false // 日常计算不需要千分位
      
      if let formatted = formatter.string(from: NSNumber(value: doubleResult)) {
        return formatted
      } else {
        return String(doubleResult)
      }
    } catch {
      return nil
    }
  }
  
  private func submitContent() {
    // 如果候选栏为空，什么都不做
    guard !currentExpression.isEmpty else { return }
    
    // 忠实保持输入内容
    var textToSubmit = currentExpression
    // 如果有计算结果，表达式已经包含 = 了，追加结果
    if let result = calculatedResult {
      textToSubmit = "\(currentExpression)\(result)"
    }
    
    onInput(textToSubmit)
    // 上屏后清空表达式，保持计算器界面
    currentExpression = ""
    calculatedResult = nil
    updateCandidateDisplay()
  }
  
  @objc private func handleKeyTap(_ sender: UIButton) {
    // 任何按键交互都清除提示
    if isShowingHint {
      isShowingHint = false
      updateCandidateDisplay()
    }
    
    guard let key = sender.accessibilityIdentifier else { return }
    
    // 跟随键盘振动设置
    if enableHapticFeedback {
      let generator = UIImpactFeedbackGenerator(style: .medium)
      generator.impactOccurred()
    }
    
    switch key {
    case "⌫":
      // 退格：删除最后一个字符
      if !currentExpression.isEmpty {
        currentExpression.removeLast()
        calculatedResult = nil
        updateCandidateDisplay()
      } else {
        onDelete()
      }
      
    case "空格":
      // 空格：如果有内容则上屏，否则插入空格
      if currentExpression.isEmpty {
        onInput(" ")
        // 插入空格后也保持界面
      } else {
        submitContent()
      }
      
    default:
      // 所有其他键（包括 = 和运算符）：追加到表达式
      currentExpression += key
      // 尝试计算（如果表达式以 = 结尾且有效）
      tryCalculate()
      updateCandidateDisplay()
    }
  }
  
  @objc private func handleCandidateTap() {
    submitContent()
  }
  
  @objc private func handleSpaceLongPress(_ sender: UILongPressGestureRecognizer) {
    guard sender.state == .began else { return }
    
    // 触发振动反馈
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
    
    // 如果有内容，先上屏
    if !currentExpression.isEmpty {
      submitContent()
    }
    // 然后触发换行
    onNewline()
  }
  
  @objc private func handleTouchDown(_ sender: UIButton) {
    sender.backgroundColor = style.callout.textColor.withAlphaComponent(0.15)
  }
  
  private func getButtonBackgroundColor(for key: String) -> UIColor {
    return UIColor { [weak self] traitCollection in
      guard let self = self else { return .clear }
      
      let isDark = traitCollection.userInterfaceStyle == .dark
      let isOperator = ["+", "-", "×", "÷", "="].contains(key)
      
      if isOperator {
        return self.themeColor.withAlphaComponent(isDark ? 0.4 : 0.6)
      }
      
      if isDark {
        return self.style.callout.backgroundColor.darker(by: 10) ?? .lightGray.withAlphaComponent(0.3)
      } else {
        // 浅色模式下，使用更明亮的背景（类原生键盘颜色），避免发灰
        return UIColor(white: 0.95, alpha: 0.8)
      }
    }
  }
  
  private func getCandidateBarBackgroundColor() -> UIColor {
    return UIColor { [weak self] traitCollection in
      guard let self = self else { return .clear }
      if traitCollection.userInterfaceStyle == .dark {
        return self.style.callout.backgroundColor.darker(by: 5) ?? .lightGray.withAlphaComponent(0.2)
      } else {
        // 浅色模式下候选栏也使用明亮颜色
        return UIColor(white: 0.9, alpha: 0.9)
      }
    }
  }
  
  @objc private func handleTouchUp(_ sender: UIButton) {
    guard let key = sender.accessibilityIdentifier else { return }
    sender.backgroundColor = getButtonBackgroundColor(for: key)
  }

  @objc private func handleBackgroundTap() {
    removeFromSuperview()
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    if let view = touch.view, view.isDescendant(of: containerView) {
      return false
    }
    return true
  }
}

// Helper to darken color (simple implementation if not available in project)
extension UIColor {
    func darker(by percentage: CGFloat = 30.0) -> UIColor? {
        return self.adjust(by: -1 * abs(percentage) )
    }

    func adjust(by percentage: CGFloat = 30.0) -> UIColor? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if self.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return UIColor(red: min(r + percentage/100, 1.0),
                           green: min(g + percentage/100, 1.0),
                           blue: min(b + percentage/100, 1.0),
                           alpha: a)
        } else {
            return nil
        }
    }
}
