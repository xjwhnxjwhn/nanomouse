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
  private var customContentShapePath: UIBezierPath?
  private var customContentShapeSignature: String?
  private let customContentMaskLayer = CAShapeLayer()
  private let customContentBorderLayer = CAShapeLayer()
  private let keySurfaceEffectView = UIVisualEffectView(effect: nil)
  private let keySurfaceTintView = UIView(frame: .zero)
  private let keySurfaceWhiteOverlayView = UIView(frame: .zero)
  private let keySurfaceStrokeLayer = CAShapeLayer()
  private let keyBackgroundImageView = UIImageView(frame: .zero)
  private var keyBackgroundImagePathSignature: String?
  private static let keyBackgroundImageCache = NSCache<NSString, UIImage>()

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
    applyButtonBackground(style, isPressed: false)
    applyButtonBorder(style)
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

      if let customContentShapePath {
        buttonContentView.frame = oldBounds
        buttonContentView.layer.cornerRadius = 0
        if enableButtonUnderBorder {
          underShadowShape.path = nil
        }
        applyCustomContentShape(customContentShapePath, style: normalButtonStyle)
      } else {
        removeCustomContentShape()
        let insets = item.insets
        // Logger.statistics.debug("button layoutSubviews(): row: \(self.row), column: \(self.column), rowHeight: \(insets.yamlString)")

        let bounds = oldBounds.inset(by: insets)
        buttonContentView.frame = bounds
        // Logger.statistics.debug("button content row: \(self.row), column: \(self.column), frame: \(bounds.width) \(bounds.height)")
        if let cornerRadius = normalButtonStyle.cornerRadius {
          let cornerRadius = clampedCornerRadius(cornerRadius, in: bounds.size)
          buttonContentView.layer.cornerRadius = cornerRadius
          if enableButtonUnderBorder, !shouldRenderKeySurfaceGlass() {
            buttonContentView.layer.addSublayer(underShadowShape)
            underShadowShape.path = calculatorUnderPath(bounds: CGSize(width: bounds.width, height: bounds.height + 1), cornerRadius: cornerRadius).cgPath
            underShadowShape.fillColor = normalButtonStyle.shadow?.color.cgColor
          } else {
            underShadowShape.removeFromSuperlayer()
          }
        }
      }
      CATransaction.commit()
    }
    updateKeySurface(style: isHighlighted ? pressedButtonStyle : normalButtonStyle, isPressed: isHighlighted)

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      // 系统颜色发生变化，重新获取按键样式
      normalButtonStyle = getButtonStyle(isPressed: false)
      pressedButtonStyle = getButtonStyle(isPressed: true)
      updateButtonStyle(isPressed: isHighlighted)
    }
    if let customContentShapePath {
      applyCustomContentShape(customContentShapePath, style: isHighlighted ? pressedButtonStyle : normalButtonStyle)
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

    let overlay = AccentMenuOverlay(
      style: actionCalloutStyle,
      visualEffectConfiguration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect,
      userInterfaceStyle: keyboardContext.colorScheme,
      chars: accents
    ) { [weak self] char in
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
    applyButtonBackground(style, isPressed: isPressed)
    applyButtonBorder(style)
    if let customContentShapePath {
      applyCustomContentShape(customContentShapePath, style: style)
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
      // 延迟移除气泡，使其持续时间更接近原生 iOS 键盘
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.removeInputCallout()
      }
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

  func setCustomContentShapePath(_ path: UIBezierPath?, signature: String? = nil) {
    let nextSignature: String?
    if let path {
      let bounds = path.bounds.integral
      nextSignature = signature ?? "\(Int(bounds.minX))-\(Int(bounds.minY))-\(Int(bounds.width))-\(Int(bounds.height))"
    } else {
      nextSignature = nil
    }
    guard customContentShapeSignature != nextSignature else { return }
    customContentShapeSignature = nextSignature
    customContentShapePath = path
    if path == nil {
      removeCustomContentShape()
    }
    oldBounds = .zero
    setNeedsLayout()
  }

  func customContentShapeContains(_ point: CGPoint) -> Bool? {
    guard let customContentShapePath else { return nil }
    return customContentShapePath.contains(point)
  }

  private func applyCustomContentShape(_ path: UIBezierPath, style: KeyboardButtonStyle) {
    customContentMaskLayer.frame = buttonContentView.bounds
    customContentMaskLayer.path = path.cgPath
    buttonContentView.layer.mask = customContentMaskLayer

    let borderWidth = max(0, style.border?.size ?? 0)
    let defaultGlassStrokeWidth = KeyboardLiquidGlass.defaultKeySurfaceStrokeWidth(
      userInterfaceStyle: keyboardContext.colorScheme,
      configuration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect
    )
    let configuredColor = style.border?.color
    let effectiveBorderWidth = max(borderWidth, defaultGlassStrokeWidth)
    let strokeColor: UIColor = {
      guard effectiveBorderWidth > 0 else { return .clear }
      if let configuredColor, configuredColor.cgColor.alpha > 0 {
        return configuredColor
      }
      guard shouldRenderKeySurfaceGlass() else { return .clear }
      return KeyboardLiquidGlass.strokeColor(
        userInterfaceStyle: keyboardContext.colorScheme,
        configuration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect,
        target: .keySurface
      )
    }()

    customContentBorderLayer.frame = buttonContentView.bounds
    customContentBorderLayer.path = path.cgPath
    customContentBorderLayer.fillColor = UIColor.clear.cgColor
    customContentBorderLayer.strokeColor = strokeColor.cgColor
    customContentBorderLayer.lineWidth = effectiveBorderWidth
    if customContentBorderLayer.superlayer == nil {
      buttonContentView.layer.addSublayer(customContentBorderLayer)
    }
  }

  private func removeCustomContentShape() {
    if buttonContentView.layer.mask === customContentMaskLayer {
      buttonContentView.layer.mask = nil
    }
    customContentBorderLayer.removeFromSuperlayer()
  }

  private func applyButtonBackground(_ style: KeyboardButtonStyle, isPressed: Bool) {
    configureKeySurfaceViewsIfNeeded()
    let shouldUseGlass = shouldRenderKeySurfaceGlass()
    let hasImage = currentKeyAppearanceOverride()?.backgroundImageURL != nil
    buttonContentView.backgroundColor = shouldUseGlass || hasImage ? .clear : style.backgroundColor
    updateKeySurface(style: style, isPressed: isPressed)
  }

  private func applyButtonBorder(_ style: KeyboardButtonStyle) {
    guard customContentShapePath == nil else {
      buttonContentView.layer.borderColor = UIColor.clear.cgColor
      buttonContentView.layer.borderWidth = 0
      return
    }
    if let border = style.border {
      buttonContentView.layer.borderColor = border.color.cgColor
      buttonContentView.layer.borderWidth = max(0, border.size)
    } else {
      buttonContentView.layer.borderColor = UIColor.clear.cgColor
      buttonContentView.layer.borderWidth = 0
    }
  }

  private func configureKeySurfaceViewsIfNeeded() {
    guard keySurfaceEffectView.superview == nil else { return }
    keySurfaceEffectView.isUserInteractionEnabled = false
    keySurfaceEffectView.clipsToBounds = true
    keySurfaceTintView.isUserInteractionEnabled = false
    keySurfaceTintView.backgroundColor = .clear
    keySurfaceWhiteOverlayView.isUserInteractionEnabled = false
    keySurfaceWhiteOverlayView.backgroundColor = .clear
    keySurfaceEffectView.contentView.addSubview(keySurfaceTintView)
    keySurfaceEffectView.contentView.addSubview(keySurfaceWhiteOverlayView)

    keyBackgroundImageView.isUserInteractionEnabled = false
    keyBackgroundImageView.contentMode = .scaleAspectFill
    keyBackgroundImageView.clipsToBounds = true

    buttonContentView.insertSubview(keySurfaceEffectView, at: 0)
    buttonContentView.insertSubview(keyBackgroundImageView, aboveSubview: keySurfaceEffectView)
    buttonContentView.layer.addSublayer(keySurfaceStrokeLayer)
  }

  private func updateKeySurface(style: KeyboardButtonStyle, isPressed: Bool) {
    configureKeySurfaceViewsIfNeeded()
    let bounds = buttonContentView.bounds
    let cornerRadius = clampedCornerRadius(style.cornerRadius ?? 0, in: bounds.size)
    let shouldUseGlass = shouldRenderKeySurfaceGlass()
    let imageURL = currentKeyAppearanceOverride()?.backgroundImageURL

    keySurfaceEffectView.frame = bounds
    keySurfaceEffectView.layer.cornerRadius = cornerRadius
    keySurfaceTintView.frame = keySurfaceEffectView.contentView.bounds
    keySurfaceTintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    keySurfaceWhiteOverlayView.frame = keySurfaceEffectView.contentView.bounds
    keySurfaceWhiteOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    keySurfaceStrokeLayer.frame = bounds
    keySurfaceStrokeLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
    keySurfaceStrokeLayer.fillColor = UIColor.clear.cgColor
    let borderWidth = max(0, style.border?.size ?? 0)
    let defaultGlassStrokeWidth = KeyboardLiquidGlass.defaultKeySurfaceStrokeWidth(
      userInterfaceStyle: keyboardContext.colorScheme,
      configuration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect
    )
    let shouldDrawGlassStroke = shouldUseGlass &&
      (borderWidth > 0 || defaultGlassStrokeWidth > 0) &&
      (style.border?.color.cgColor.alpha ?? 0) <= 0
    keySurfaceStrokeLayer.lineWidth = shouldDrawGlassStroke ? max(borderWidth, defaultGlassStrokeWidth) : 0
    keySurfaceStrokeLayer.strokeColor = shouldDrawGlassStroke
      ? KeyboardLiquidGlass.strokeColor(
        userInterfaceStyle: keyboardContext.colorScheme,
        configuration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect,
        target: .keySurface
      ).cgColor
      : UIColor.clear.cgColor

    if shouldUseGlass {
      keySurfaceEffectView.isHidden = false
      keySurfaceEffectView.effect = KeyboardLiquidGlass.effect(
        userInterfaceStyle: keyboardContext.colorScheme,
        configuration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect,
        target: .keySurface
      )
      var tint = KeyboardLiquidGlass.tintColor(
        userInterfaceStyle: keyboardContext.colorScheme,
        configuration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect,
        target: .keySurface
      )
      if isPressed {
        tint = tint.withAlphaComponent(min(1, tint.cgColor.alpha + 0.12))
      }
      keySurfaceTintView.backgroundColor = tint
      keySurfaceWhiteOverlayView.backgroundColor = KeyboardLiquidGlass.keySurfaceWhiteOverlayColor(
        userInterfaceStyle: keyboardContext.colorScheme,
        configuration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect
      )
    } else {
      keySurfaceEffectView.isHidden = true
      keySurfaceEffectView.effect = nil
      keySurfaceTintView.backgroundColor = .clear
      keySurfaceWhiteOverlayView.backgroundColor = .clear
    }

    keyBackgroundImageView.frame = bounds
    keyBackgroundImageView.layer.cornerRadius = cornerRadius
    updateKeyBackgroundImage(url: imageURL)
  }

  private func shouldRenderKeySurfaceGlass() -> Bool {
    guard !isSpacer else { return false }
    guard keyboardContext.hamsterConfiguration?.keyboard?.enableColorSchema != true else { return false }
    guard UserDefaults.hamster.chineseKeyboardKeyBackgroundColorHex?.isEmpty != false else { return false }
    guard currentKeyAppearanceOverride()?.backgroundColorHex?.isEmpty != false else { return false }
    return KeyboardLiquidGlass.shouldRenderVisualSurface(
      configuration: keyboardContext.hamsterConfiguration?.keyboard?.visualEffect,
      target: .keySurface,
      userInterfaceStyle: keyboardContext.colorScheme
    )
  }

  private func currentKeyAppearanceOverride() -> ChineseKeyboardKeyAppearance? {
    guard keyboardContext.keyboardType.isChinesePrimaryKeyboard else { return nil }
    return UserDefaults.hamster.chineseKeyboardKeyAppearanceOverrides.appearance(forActionID: item.action.yamlString)
  }

  private func updateKeyBackgroundImage(url: URL?) {
    let signature = url?.path
    guard keyBackgroundImagePathSignature != signature else { return }
    keyBackgroundImagePathSignature = signature
    guard let url else {
      keyBackgroundImageView.image = nil
      keyBackgroundImageView.isHidden = true
      return
    }
    let key = url.path as NSString
    if let cached = Self.keyBackgroundImageCache.object(forKey: key) {
      keyBackgroundImageView.image = cached
      keyBackgroundImageView.isHidden = false
      return
    }
    guard let image = UIImage(contentsOfFile: url.path) else {
      keyBackgroundImageView.image = nil
      keyBackgroundImageView.isHidden = true
      return
    }
    Self.keyBackgroundImageCache.setObject(image, forKey: key)
    keyBackgroundImageView.image = image
    keyBackgroundImageView.isHidden = false
  }

  private func clampedCornerRadius(_ radius: CGFloat, in size: CGSize) -> CGFloat {
    max(0, min(radius, min(size.width, size.height) / 2))
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
    // DEBUG: 检查气泡条件
    let configSetting = keyboardContext.hamsterConfiguration?.keyboard?.displayButtonBubbles ?? false
    let typeSetting = keyboardContext.keyboardType.displayButtonBubbles
    // print("DBG_BUBBLE: config=\(configSetting), type=\(typeSetting), keyboardType=\(keyboardContext.keyboardType)")
    
    guard keyboardContext.displayButtonBubbles else { return }
    // 屏幕横向无按键气泡
    guard keyboardContext.interfaceOrientation.isPortrait else { return }
    let shouldShowBubble: Bool = {
      if item.action.showKeyBubble { return true }
      if keyboardContext.keyboardType.isAlphabetic {
        switch item.action {
        case .symbol, .symbolOfDark:
          return true
        default:
          return false
        }
      }
      return false
    }()
    guard shouldShowBubble else { return }
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
