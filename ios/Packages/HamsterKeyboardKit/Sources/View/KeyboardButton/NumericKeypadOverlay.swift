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
  private let enableHapticFeedback: Bool

  private let containerView = UIView()
  private let stackView = UIStackView()
  
  // Grid: 3x4
  // 1 2 3
  // 4 5 6
  // 7 8 9
  // . 0 ⌫
  private let keys: [[String]] = [
    ["1", "2", "3"],
    ["4", "5", "6"],
    ["7", "8", "9"],
    [".", "0", "⌫"]
  ]

  init(
    style: KeyboardActionCalloutStyle,
    enableHapticFeedback: Bool = false,
    onInput: @escaping (String) -> Void,
    onDelete: @escaping () -> Void
  ) {
    self.style = style
    self.enableHapticFeedback = enableHapticFeedback
    self.onInput = onInput
    self.onDelete = onDelete
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
    setupGrid()
  }
  
  private func setupContainer() {
    containerView.backgroundColor = style.callout.backgroundColor
    containerView.layer.cornerRadius = 10
    // 容器阴影
    containerView.layer.shadowColor = UIColor.black.cgColor
    containerView.layer.shadowOpacity = 0.2
    containerView.layer.shadowRadius = 10
    containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
    
    addSubview(containerView)
    containerView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
      containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
      containerView.widthAnchor.constraint(equalToConstant: 250),
      containerView.heightAnchor.constraint(equalToConstant: 220)
    ])
  }
  
  private func setupGrid() {
    containerView.addSubview(stackView)
    stackView.axis = .vertical
    stackView.distribution = .fillEqually
    stackView.spacing = 6
    stackView.translatesAutoresizingMaskIntoConstraints = false
    
    let padding: CGFloat = 10
    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
      stackView.leftAnchor.constraint(equalTo: containerView.leftAnchor, constant: padding),
      stackView.rightAnchor.constraint(equalTo: containerView.rightAnchor, constant: -padding),
      stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -padding)
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
      stackView.addArrangedSubview(rowStack)
    }
  }
  
  private func createButton(for key: String) -> UIButton {
    let button = UIButton(type: .custom)
    if #available(iOS 15.0, *) {
      button.configuration = nil
    }
    
    button.backgroundColor = style.callout.backgroundColor.darker(by: 10) ?? .lightGray.withAlphaComponent(0.3)
    button.layer.cornerRadius = 6
    
    // Explicitly using NSAttributedString to avoid any system default underlines (e.g. Button Shapes)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 24, weight: .regular),
      .foregroundColor: style.callout.textColor,
      .underlineStyle: 0
    ]
    let attributedTitle = NSAttributedString(string: key, attributes: attributes)
    button.setAttributedTitle(attributedTitle, for: .normal)
    
    // Highlight effect
    button.addTarget(self, action: #selector(handleTouchDown(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(handleTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    
    button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
    
    return button
  }
  
  @objc private func handleTap(_ sender: UIButton) {
    // 优先获取 AttributedTitle 的文本，因为为了去除下划线我们使用了 attributedTitle
    let title = sender.attributedTitle(for: .normal)?.string ?? sender.title(for: .normal)
    guard let title = title else { return }
    
    // 跟随键盘整体的振动设置
    if enableHapticFeedback {
      let generator = UIImpactFeedbackGenerator(style: .light)
      generator.impactOccurred()
    }
    
    if title == "⌫" {
      onDelete()
    } else {
      onInput(title)
    }
  }
  
  @objc private func handleTouchDown(_ sender: UIButton) {
    sender.backgroundColor = style.callout.textColor.withAlphaComponent(0.1)
  }
  
  @objc private func handleTouchUp(_ sender: UIButton) {
    sender.backgroundColor = style.callout.backgroundColor.darker(by: 10) ?? .lightGray.withAlphaComponent(0.3)
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
