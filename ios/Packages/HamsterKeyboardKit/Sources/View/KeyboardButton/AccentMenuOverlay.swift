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
  private let stackView = UIStackView()
  private var charButtons: [UIButton] = []

  private let buttonSize = CGSize(width: 36, height: 44) // 宽度从 44 减小到 36，更紧凑
  private let padding: CGFloat = 4 // padding 从 8 减小到 4
  private let spacing: CGFloat = 0 // spacing 从 4 减小到 0，紧密排列
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
    let menuWidth = padding * 2 + buttonSize.width * CGFloat(count) + spacing * CGFloat(max(count - 1, 0))
    let menuHeight = padding * 2 + buttonSize.height

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
    stackView.frame = CGRect(
      x: padding,
      y: padding,
      width: menuWidth - padding * 2,
      height: buttonSize.height
    )
  }

  /// 处理拖拽手势选择
  func handleDrag(at point: CGPoint, in view: UIView) {
    // 将点转换到 stackView 坐标系
    let localPoint = view.convert(point, to: stackView)
    
    // 查找包含触摸点的按钮
    var foundChar: String?
    for button in charButtons {
      if button.frame.contains(view.convert(point, to: stackView)) {
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
      button.backgroundColor = isHighlighted ? style.callout.textColor.withAlphaComponent(0.1) : .clear
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
    menuContainer.addSubview(stackView)

    stackView.axis = .horizontal
    stackView.alignment = .fill
    stackView.distribution = .fillEqually
    stackView.spacing = spacing

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
      
      stackView.addArrangedSubview(button)
      charButtons.append(button)
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
