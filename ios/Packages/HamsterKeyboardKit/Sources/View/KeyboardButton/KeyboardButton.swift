//
//  KeyboardButton.swift
//
//
//  Created by morse on 2023/8/6.
//

import HamsterKit
import OSLog
import UIKit

/// 键盘键盘
public class KeyboardButton: UIControl {
  struct ButtonBounds: Hashable {
    let width: CGFloat
    let height: CGFloat
  }

  // MARK: - Properties

  /// 布局中所处行，从 0 开始
  let row: Int

  /// 布局中所处列，从 0 开始
  let column: Int

  /// 是否用来填充空白
  /// 如: 标准键盘第二行 A 键的右边, L 键的左边等
  let isSpacer: Bool

  /// 对应布局的 item，存储按键的 action 信息
  /// 注意：item中尺寸信息在自动布局中不在使用了，这些信息在 SwiftUI 布局中使用
  var item: KeyboardLayoutItem

  /// 按键对应操作的处理类
  let actionHandler: KeyboardActionHandler

  /// 键盘上下文
  let keyboardContext: KeyboardContext

  let rimeContext: RimeContext

  /// 键盘外观
  let appearance: KeyboardAppearance

  /// 呼出的上下文
  let calloutContext: KeyboardCalloutContext

  /// 设备方向
  var interfaceOrientation: InterfaceOrientation

  /// iPad 浮动模式
  var isKeyboardFloating: Bool

  /// 用来缓存是否需要重新计算 UnderShape
  var oldUnderShapeFrame: CGRect

  var oldBounds: CGRect = .zero

  // MARK: - touch state

  // 按钮按下状态
  var isPressed = false

  /// 按钮长按开始时间
  var longPressDate: Date? = nil

  /// 按钮重复开始时间
  var repeatDate: Date? = nil

  /// 手势开始时间戳
  var touchBeginTimestamp: TimeInterval? = nil

  /// 轻扫手势处理
  var swipeGestureHandle: (() -> Void)?

  /// 拖动开始位置
  var dragStartLocation: CGPoint? = nil

  /// 最后一次拖拽的位置
  var lastDragLocation: CGPoint? = nil

  /// 是否触发 .release 操作
  /// 注意：
  /// 1. 长按空格状态下不应该触发 release
  /// 2. 在 calloutContext 呼出开始显示的时候，不应触发 release
  var shouldApplyReleaseAction = true

  /// 在按钮 bounds 外，仍然可以触发 .release 操作的区域大小的百分比
  /// 默认为 `0.75`，即把按钮 bounds 的 size 在扩大这个值
  /// 注意：这个值需要与划动的阈值相配合
  let releaseOutsideTolerance: Double = 0.75

  let repeatTimer: RepeatGestureTimer = .shared

  lazy var longPressDelay: TimeInterval = {
    if let longPressDelay = keyboardContext.longPressDelay {
      return longPressDelay
    }
    return GestureButtonDefaults.longPressDelay
  }()

  let repeatDelay: TimeInterval = GestureButtonDefaults.repeatDelay

  var userInterfaceStyle: UIUserInterfaceStyle
  private var enableButtonUnderBorder: Bool

  // MARK: - subview

  /// 按键内容视图
  lazy var buttonContentView: KeyboardButtonContentView = {
    let contentView = KeyboardButtonContentView(
      item: item,
      style: normalButtonStyle,
      appearance: appearance,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext)
    return contentView
  }()

  // 按钮底部立体阴影
  lazy var underShadowShape: CAShapeLayer = {
    let layer = CAShapeLayer()
    return layer
  }()

  // 输入按键气泡
  lazy var inputCalloutView: InputCalloutView = {
    let view = InputCalloutView(
      calloutContext: calloutContext.input,
      keyboardContext: keyboardContext,
      style: inputCalloutStyle)
    return view
  }()

  // MARK: - 计算属性

  /// 按钮样式
  /// 注意：action 与 是否按下的状态 isPressed 决定按钮样式
  lazy var normalButtonStyle: KeyboardButtonStyle = self.getButtonStyle(isPressed: false)
  lazy var pressedButtonStyle: KeyboardButtonStyle = self.getButtonStyle(isPressed: true)

  /// 布局配置
  var layoutConfig: KeyboardLayoutConfiguration {
    return .standard(for: keyboardContext)
  }

  /// input呼出样式
  var inputCalloutStyle: KeyboardInputCalloutStyle {
    var style = appearance.inputCalloutStyle
    let insets = item.insets
    style.callout.buttonInset = insets
    return style
  }

  /// 长按呼出样式
  var actionCalloutStyle: KeyboardActionCalloutStyle {
    var style = appearance.actionCalloutStyle
    let insets = item.insets
    style.callout.buttonInset = insets
    return style
  }

//  override public var isHighlighted: Bool {
//    didSet {
//      updateButtonStyle(isPressed: isHighlighted)
//    }
//  }

  // MARK: - Initializations

  init(
    row: Int,
    column: Int,
    item: KeyboardLayoutItem,
    actionHandler: KeyboardActionHandler,
    keyboardContext: KeyboardContext,
    rimeContext: RimeContext,
    calloutContext: KeyboardCalloutContext,
    appearance: KeyboardAppearance)
  {
    self.row = row
    self.column = column
    self.item = item
    self.isSpacer = item.action.isSpacer
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    self.calloutContext = calloutContext
    self.appearance = appearance
    self.interfaceOrientation = keyboardContext.interfaceOrientation
    self.userInterfaceStyle = keyboardContext.colorScheme
    self.isKeyboardFloating = keyboardContext.isKeyboardFloating
    self.oldUnderShapeFrame = .zero
    self.enableButtonUnderBorder = keyboardContext.enableButtonUnderBorder

    super.init(frame: .zero)

    self.isHidden = isSpacer ? true : false
    if item.action == .nextKeyboard {
      self.addTarget(self, action: #selector(handleInputModeListFromView(from: with:)), for: .allEvents)
    }

    setupButtonContentView()

    NotificationCenter.default.addObserver(self, selector: #selector(handleRimeSchemaChange), name: RimeContext.rimeSchemaDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(handleRimeAsciiModeChange), name: RimeContext.rimeAsciiModeDidChangeNotification, object: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    RepeatGestureTimer.shared.stop()
  }

  // MARK: - Layout Functions

  /// 设置按钮内容视图
  func setupButtonContentView() {
    addSubview(buttonContentView)

    // 初始状态样式
    let style = normalButtonStyle

    // 按钮样式
    buttonContentView.backgroundColor = style.backgroundColor
    if let color = style.border?.color {
      buttonContentView.layer.borderColor = color.cgColor
      buttonContentView.layer.borderWidth = style.border?.size ?? 1
    }
  }

  override public func layoutSubviews() {
    super.layoutSubviews()
    guard isHidden == false else { return }

    if oldBounds != self.bounds {
      oldBounds = self.bounds

      // 宽度为 0 时，不在计算 frame
      if oldBounds.width == .zero || oldBounds.height == .zero {
        if enableButtonUnderBorder {
          underShadowShape.path = .none
        }
        buttonContentView.frame = .zero
        return
      }

      CATransaction.begin()
      CATransaction.setDisableActions(true)

      let insets = item.insets
      // Logger.statistics.debug("button layoutSubviews(): row: \(self.row), column: \(self.column), rowHeight: \(insets.yamlString)")

      let bounds = oldBounds.inset(by: insets)
      buttonContentView.frame = bounds
      // Logger.statistics.debug("button content row: \(self.row), column: \(self.column), frame: \(bounds.width) \(bounds.height)")
      if let cornerRadius = normalButtonStyle.cornerRadius {
        buttonContentView.layer.cornerRadius = cornerRadius
        if enableButtonUnderBorder {
          buttonContentView.layer.addSublayer(underShadowShape)
          underShadowShape.path = calculatorUnderPath(bounds: CGSize(width: bounds.width, height: bounds.height + 1), cornerRadius: cornerRadius).cgPath
          underShadowShape.fillColor = normalButtonStyle.shadow?.color.cgColor
        }
      }
      CATransaction.commit()
    }

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      // 系统颜色发生变化，重新获取按键样式
      normalButtonStyle = getButtonStyle(isPressed: false)
      pressedButtonStyle = getButtonStyle(isPressed: true)
      updateButtonStyle(isPressed: isHighlighted)
    }

    // 语言切换键：始终刷新文字以反映当前语言状态（中/日/英）
    if isLanguageSwitchKey() {
      buttonContentView.refreshLanguageSwitchText(buttonText)
    }
  }

  @objc func handleRimeSchemaChange() {
    guard isLanguageSwitchKey() else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.buttonContentView.refreshLanguageSwitchText(self.buttonText)
    }
  }

  func handleLanguageSelection(_ option: LanguageMenuOverlay.LanguageOption) {
    switch option {
    case .chinese:
      actionHandler.handle(.release, on: .shortCommand(.setLanguageChinese))
    case .japanese:
      actionHandler.handle(.release, on: .shortCommand(.setLanguageJapanese))
    case .english:
      actionHandler.handle(.release, on: .shortCommand(.setLanguageEnglish))
    }
  }

  // MARK: - Accent Menu Support

  static let accentMenuOverlayTag = 8118

  func presentAccentMenu(for accents: [String]) {
    guard let container = superview else { return }
    // 移除已存在的菜单
    container.viewWithTag(Self.accentMenuOverlayTag)?.removeFromSuperview()

    let overlay = AccentMenuOverlay(style: actionCalloutStyle, chars: accents) { [weak self] char in
      self?.handleAccentSelection(char)
    }
    overlay.tag = Self.accentMenuOverlayTag
    overlay.frame = container.bounds
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(overlay)
    
    // 必须确保气泡在正确的位置
    overlay.positionMenu(above: frame, in: overlay.bounds)
  }

  func handleAccentSelection(_ char: String) {
    Logger.statistics.info("Accent selected: \(char)")
    actionHandler.handle(.release, on: .character(char))
  }



  // MARK: - Numeric Keypad Support

  static let numericKeypadOverlayTag = 8119

  func presentNumericKeypad() {
    var container = superview
    // 尝试获取键盘控制器的根视图，以确保覆盖整个键盘区域
    if let handler = actionHandler as? StandardKeyboardActionHandler,
       let controller = handler.keyboardController as? UIViewController {
      container = controller.view
    }
    
    guard let container = container else { return }
    // Remove existing overlay
    container.viewWithTag(Self.numericKeypadOverlayTag)?.removeFromSuperview()

    // 获取键盘振动设置
    let enableHaptic = keyboardContext.hamsterConfiguration?.keyboard?.enableHapticFeedback ?? false

    let overlay = NumericKeypadOverlay(
      style: actionCalloutStyle,
      enableHapticFeedback: enableHaptic,
      onInput: { [weak self] char in
        self?.handleNumericInput(char)
      },
      onDelete: { [weak self] in
        self?.handleNumericDelete()
      }
    )
    
    overlay.tag = Self.numericKeypadOverlayTag
    overlay.frame = container.bounds
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(overlay)
  }

  func handleNumericInput(_ char: String) {
    Logger.statistics.info("Numeric input: \(char)")
    actionHandler.handle(.release, on: .character(char))
  }
  
  func handleNumericDelete() {
    Logger.statistics.info("Numeric delete")
    // Backspace works on .press (or .repeatPress), not .release in StandardKeyboardActionHandler
    actionHandler.handle(.press, on: .backspace)
    actionHandler.handle(.release, on: .backspace) // Clean up state if necessary
  }

  @objc func handleRimeAsciiModeChange() {
    guard isLanguageSwitchKey() else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.buttonContentView.refreshLanguageSwitchText(self.buttonText)
    }
  }

  /// 根据按下状态更新当前按钮样式
  func updateButtonStyle(isPressed: Bool) {
    // Logger.statistics.debug("updateButtonStyle(), isPressed: \(isPressed), isHighlighted: \(self.isHighlighted)")
    let style = isPressed ? pressedButtonStyle : normalButtonStyle

    // 更新按钮内容的样式
    buttonContentView.setStyle(style)

    // 按钮样式
    buttonContentView.backgroundColor = style.backgroundColor
    if let color = style.border?.color {
      buttonContentView.layer.borderColor = color.cgColor
      buttonContentView.layer.borderWidth = style.border?.size ?? 1
    }

    if isPressed {
      if enableButtonUnderBorder {
        underShadowShape.opacity = 0
      }
      addInputCallout()
    } else {
      if enableButtonUnderBorder {
        underShadowShape.opacity = 1
      }
      removeInputCallout()
    }
  }

  func getButtonStyle(isPressed: Bool) -> KeyboardButtonStyle {
    if keyboardContext.keyboardType.isCustom, let key = item.key {
      return appearance.buttonStyle(for: key, isPressed: isPressed)
    }
    return appearance.buttonStyle(for: item.action, isPressed: isPressed)
  }

  // MARK: debuger

  override public var debugDescription: String {
    let description = super.debugDescription
    return "\(row)-\(column) button: \(description)"
  }
}

// MARK: - Input Callout

extension KeyboardButton {
  var buttonText: String {
    if let languageText = languageSwitchButtonText() {
      return languageText
    }
    if keyboardContext.keyboardType.isCustom, let buttonText = item.key?.label.text, !buttonText.isEmpty {
      return buttonText
    }
    return appearance.buttonText(for: item.action) ?? ""
  }

  private func languageSwitchButtonText() -> String? {
    guard isLanguageSwitchKey() else { return nil }
    if rimeContext.asciiModeSnapshot {
      return "英"
    }
    if rimeContext.currentSchema?.isJapaneseSchema == true {
      return "日"
    }
    return "中"
  }

  private func isLanguageSwitchKey() -> Bool {
    guard case .keyboardType(let type) = item.action else { return false }
    if keyboardContext.keyboardType == keyboardContext.selectKeyboard {
      return type.isAlphabetic
    }
    if keyboardContext.keyboardType.isAlphabetic {
      return type == keyboardContext.selectKeyboard
    }
    return false
  }

  /// 添加 input 按键气泡
  func addInputCallout() {
    guard keyboardContext.displayButtonBubbles else { return }
    // 屏幕横向无按键气泡
    guard keyboardContext.interfaceOrientation.isPortrait else { return }
    guard item.action.showKeyBubble else { return }
    guard inputCalloutView.superview == nil else { return }

    inputCalloutView.setText(buttonText)

    let insets = item.insets
    inputCalloutView.frame = self.frame.inset(by: insets)
    self.superview?.addSubview(inputCalloutView)
    inputCalloutView.setNeedsLayout()
  }

  /// 删除 input 按键气泡
  func removeInputCallout() {
    if inputCalloutView.superview != nil {
      inputCalloutView.removeFromSuperview()
    }
  }
}

// MARK: - background view style

extension KeyboardButton {
  /// 按键 underPath 缓存
  static var underPathCache = [ButtonBounds: UIBezierPath]()

  /// 按钮底部深色样式路径
  func calculatorUnderPath(bounds: CGSize, cornerRadius: CGFloat) -> UIBezierPath {
    let key = add(bounds: bounds, cornerRadius: cornerRadius)
    // 缓存 PATH
    if let path = Self.underPathCache[key] {
      return path
    }
    let underPath = CAShapeLayer.underPath(size: bounds, cornerRadius: cornerRadius)
    Self.underPathCache[key] = underPath
    return underPath
  }

  func add(bounds: CGSize, cornerRadius: CGFloat) -> ButtonBounds {
    ButtonBounds(width: bounds.width + cornerRadius, height: bounds.height + cornerRadius)
  }
}
