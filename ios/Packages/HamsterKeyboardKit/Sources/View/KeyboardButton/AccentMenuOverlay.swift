//
//  AccentMenuOverlay.swift
//
//
//  Created by Codex on 2026/01/07.
//

import UIKit

final class AccentMenuOverlay: UIView, UIGestureRecognizerDelegate {
  private let style: KeyboardActionCalloutStyle
  private let chars: [String]
  private let onSelect: (String) -> Void
  private var highlightedChar: String?

  private let menuContainer = UIView()
  private let glassEffectView = UIVisualEffectView(effect: nil)
  private let glassTintView = UIView(frame: .zero)
  private let glassStrokeView = UIView(frame: .zero)
  private var charButtons: [UIButton] = []

  private let buttonSize = CGSize(width: 36, height: 44) // 宽度从 44 减小到 36，更紧凑
  private let padding: CGFloat = 4 // padding 从 8 减小到 4
  private let spacing: CGFloat = 0 // spacing 从 4 减小到 0，紧密排列
  private let rowSpacing: CGFloat = 4
  private let edgeInset: CGFloat = 2 // 边缘留白减小

  init(
    style: KeyboardActionCalloutStyle,
    chars: [String],
    onSelect: @escaping (String) -> Void
  ) {
    self.style = style
    self.chars = chars
    self.onSelect = onSelect
    super.init(frame: .zero)
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func positionMenu(above buttonFrame: CGRect, in bounds: CGRect) {
    let count = max(chars.count, 1)
    let maxContentWidth = max(bounds.width - edgeInset * 2 - padding * 2, buttonSize.width)
    let maxColumns = max(Int((maxContentWidth + spacing) / (buttonSize.width + spacing)), 1)
    let columns = min(count, maxColumns)
    let rows = Int(ceil(Double(count) / Double(columns)))

    let menuWidth = padding * 2 + buttonSize.width * CGFloat(columns) + spacing * CGFloat(max(columns - 1, 0))
    let menuHeight = padding * 2 + buttonSize.height * CGFloat(rows) + rowSpacing * CGFloat(max(rows - 1, 0))

    var origin = CGPoint(
      x: buttonFrame.midX - menuWidth / 2,
      y: buttonFrame.minY - menuHeight - 8
    )

    // 防止超出顶部
    // 允许气泡延伸到键盘视图的上方（即负坐标区域），覆盖候选栏
    // 只要不超出整个屏幕的可视范围即可（这里 bounds 通常是 keyboardView 的 bounds）
    // 为了防止其被顶部导航栏完全遮挡，我们可以设置一个更宽松的负数限制，或者完全移除限制
    // 但为了避免过于夸张，我们限制其最多超出 bounds 顶部一定距离（例如 -50）
    if origin.y < -50 {
      origin.y = -50
    }

    // 防止超出左右边界
    if origin.x < edgeInset {
      origin.x = edgeInset
    } else if origin.x + menuWidth > bounds.width - edgeInset {
      origin.x = bounds.width - menuWidth - edgeInset
    }

    menuContainer.frame = CGRect(origin: origin, size: CGSize(width: menuWidth, height: menuHeight))
    layoutButtons(columns: columns)
  }

  /// 处理拖拽手势选择
  func handleDrag(at point: CGPoint, in view: UIView) {
    let localPoint = view.convert(point, to: self)
    
    // 查找包含触摸点的按钮
    var foundChar: String?
    for button in charButtons {
      if button.convert(button.bounds, to: self).contains(localPoint) {
        foundChar = chars[button.tag]
        break
      }
    }

    if foundChar != highlightedChar {
      highlightedChar = foundChar
      updateHighlightState()
      
      // 触觉反馈
      if foundChar != nil {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
      }
    }
  }

  /// 确认选择
  func confirmSelection() {
    if let char = highlightedChar {
      onSelect(char)
    }
    removeFromSuperview()
  }

  private func updateHighlightState() {
    for button in charButtons {
      let char = chars[button.tag]
      let isHighlighted = char == highlightedChar
      button.backgroundColor = isHighlighted
        ? KeyboardLiquidGlass.selectionColor(textColor: style.callout.textColor, userInterfaceStyle: traitCollection.userInterfaceStyle)
        : .clear
      button.isHighlighted = isHighlighted
      
      // 放大高亮的按钮
      if isHighlighted {
          UIView.animate(withDuration: 0.1) {
              button.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
          }
      } else {
          UIView.animate(withDuration: 0.1) {
              button.transform = .identity
          }
      }
    }
  }

  private func setupView() {
    backgroundColor = .clear

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
    tap.delegate = self
    addGestureRecognizer(tap)

    menuContainer.backgroundColor = style.callout.backgroundColor
    menuContainer.layer.cornerRadius = style.callout.cornerRadius
    
    // 阴影
    menuContainer.layer.shadowColor = UIColor.black.cgColor
    menuContainer.layer.shadowOpacity = 0.15
    menuContainer.layer.shadowRadius = 8
    menuContainer.layer.shadowOffset = CGSize(width: 0, height: 4)

    addSubview(menuContainer)
    setupGlassBackground()

    for (index, char) in chars.enumerated() {
      let button = UIButton(type: .custom)
      if #available(iOS 15.0, *) {
        button.configuration = nil
      }
      
      let fontSize: CGFloat = 22
      let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
      
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: style.callout.textColor,
        .underlineStyle: 0 // Explicitly remove underline
      ]
      
      let attributedTitle = NSAttributedString(string: char, attributes: attributes)
      button.setAttributedTitle(attributedTitle, for: .normal)
      
      button.layer.cornerRadius = 6
      button.tag = index
      button.addTarget(self, action: #selector(handleOptionTap(_:)), for: .touchUpInside)
      button.frame.size = buttonSize
      
      menuContainer.addSubview(button)
      charButtons.append(button)
    }

    menuContainer.addSubview(glassStrokeView)
  }

  private func setupGlassBackground() {
    menuContainer.backgroundColor = .clear
    menuContainer.layer.cornerRadius = 14
    menuContainer.layer.cornerCurve = .continuous

    menuContainer.layer.shadowColor = UIColor.black.cgColor
    menuContainer.layer.shadowOpacity = KeyboardLiquidGlass.shadowOpacity(userInterfaceStyle: traitCollection.userInterfaceStyle)
    menuContainer.layer.shadowRadius = 12
    menuContainer.layer.shadowOffset = CGSize(width: 0, height: 5)

    glassEffectView.effect = KeyboardLiquidGlass.effect(userInterfaceStyle: traitCollection.userInterfaceStyle)
    glassEffectView.isUserInteractionEnabled = false
    glassEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glassEffectView.layer.cornerRadius = 14
    glassEffectView.layer.cornerCurve = .continuous
    glassEffectView.layer.masksToBounds = true

    glassTintView.backgroundColor = KeyboardLiquidGlass.tintColor(userInterfaceStyle: traitCollection.userInterfaceStyle)
    glassTintView.isUserInteractionEnabled = false
    glassTintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glassEffectView.contentView.addSubview(glassTintView)

    glassStrokeView.backgroundColor = .clear
    glassStrokeView.isUserInteractionEnabled = false
    glassStrokeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glassStrokeView.layer.cornerRadius = 14
    glassStrokeView.layer.cornerCurve = .continuous
    glassStrokeView.layer.borderWidth = 1 / UIScreen.main.scale
    glassStrokeView.layer.borderColor = KeyboardLiquidGlass.strokeColor(userInterfaceStyle: traitCollection.userInterfaceStyle).cgColor

    menuContainer.addSubview(glassEffectView)
  }

  private func layoutButtons(columns: Int) {
    guard columns > 0 else { return }

    glassEffectView.frame = menuContainer.bounds
    glassTintView.frame = glassEffectView.contentView.bounds
    glassStrokeView.frame = menuContainer.bounds

    for (index, button) in charButtons.enumerated() {
      let row = index / columns
      let column = index % columns
      let x = padding + CGFloat(column) * (buttonSize.width + spacing)
      let y = padding + CGFloat(row) * (buttonSize.height + rowSpacing)
      button.frame = CGRect(origin: CGPoint(x: x, y: y), size: buttonSize)
    }
  }

  @objc private func handleOptionTap(_ sender: UIButton) {
    if sender.tag < chars.count {
        let char = chars[sender.tag]
        onSelect(char)
    }
    removeFromSuperview()
  }

  @objc private func handleBackgroundTap() {
    removeFromSuperview()
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    if let view = touch.view, view.isDescendant(of: menuContainer) {
      return false
    }
    return true
  }
}
