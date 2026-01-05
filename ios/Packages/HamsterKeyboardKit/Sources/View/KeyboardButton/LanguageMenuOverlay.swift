//
//  LanguageMenuOverlay.swift
//
//
//  Created by Codex on 2026/01/05.
//

import UIKit

final class LanguageMenuOverlay: UIView, UIGestureRecognizerDelegate {
  enum LanguageOption: Int, CaseIterable {
    case chinese = 0
    case japanese = 1
    case english = 2

    var title: String {
      switch self {
      case .chinese: return "中"
      case .japanese: return "日"
      case .english: return "英"
      }
    }
  }

  private let style: KeyboardActionCalloutStyle
  private let options: [LanguageOption]
  private let onSelect: (LanguageOption) -> Void
  private var highlightedOption: LanguageOption?

  private let menuContainer = UIView()
  private let stackView = UIStackView()
  private var optionButtons: [UIButton] = []

  private let buttonSize = CGSize(width: 44, height: 44)
  private let padding: CGFloat = 8
  private let spacing: CGFloat = 8
  private let edgeInset: CGFloat = 4

  init(
    style: KeyboardActionCalloutStyle,
    options: [LanguageOption],
    onSelect: @escaping (LanguageOption) -> Void
  ) {
    self.style = style
    self.options = options
    self.onSelect = onSelect
    super.init(frame: .zero)
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func positionMenu(above buttonFrame: CGRect, in bounds: CGRect) {
    let count = max(options.count, 1)
    let menuWidth = padding * 2 + buttonSize.width * CGFloat(count) + spacing * CGFloat(max(count - 1, 0))
    let menuHeight = padding * 2 + buttonSize.height

    var origin = CGPoint(
      x: buttonFrame.midX - menuWidth / 2,
      y: buttonFrame.minY - menuHeight - 8
    )

    if origin.y < edgeInset {
      origin.y = buttonFrame.maxY + 8
    }

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
    let localPoint = view.convert(point, to: stackView)
    
    // 查找包含触摸点的按钮
    var foundOption: LanguageOption?
    for button in optionButtons {
      if button.frame.contains(view.convert(point, to: stackView)) {
        foundOption = LanguageOption(rawValue: button.tag)
        break
      }
    }

    if foundOption != highlightedOption {
      highlightedOption = foundOption
      updateHighlightState()
      
      // 触觉反馈
      if foundOption != nil {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
      }
    }
  }

  /// 确认选择
  func confirmSelection() {
    if let option = highlightedOption {
      onSelect(option)
    }
    removeFromSuperview()
  }

  private func updateHighlightState() {
    for button in optionButtons {
      let isHighlighted = button.tag == highlightedOption?.rawValue
      button.backgroundColor = isHighlighted ? style.callout.textColor.withAlphaComponent(0.1) : .clear
      button.isHighlighted = isHighlighted
    }
  }

  private func setupView() {
    backgroundColor = .clear

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
    tap.delegate = self
    addGestureRecognizer(tap)

    menuContainer.backgroundColor = style.callout.backgroundColor
    menuContainer.layer.cornerRadius = style.callout.cornerRadius
    menuContainer.layer.borderColor = UIColor.clear.cgColor
    menuContainer.layer.borderWidth = 0
    menuContainer.layer.shadowColor = UIColor.black.cgColor
    menuContainer.layer.shadowOpacity = 0 // Remove shadow to prevent "underline" look
    menuContainer.layer.shadowRadius = 0
    menuContainer.layer.shadowOffset = .zero

    addSubview(menuContainer)
    menuContainer.addSubview(stackView)

    stackView.axis = .horizontal
    stackView.alignment = .fill
    stackView.distribution = .fillEqually
    stackView.spacing = spacing

    for option in options {
      let button = UIButton(type: .custom)
      if #available(iOS 15.0, *) {
        button.configuration = nil // Reset configuration
      }
      
      let fontSize: CGFloat = 20
      let font: UIFont
      if let descriptor = UIFont.systemFont(ofSize: fontSize, weight: .bold).fontDescriptor.withDesign(.rounded) {
        font = UIFont(descriptor: descriptor, size: fontSize)
      } else {
        font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
      }
      
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: style.callout.textColor,
        .underlineStyle: 0 // Explicitly no underline
      ]
      
      let attributedTitle = NSAttributedString(string: option.title, attributes: attributes)
      button.setAttributedTitle(attributedTitle, for: .normal)
      
      button.layer.cornerRadius = 6
      button.tag = option.rawValue
      button.addTarget(self, action: #selector(handleOptionTap(_:)), for: .touchUpInside)
      
      stackView.addArrangedSubview(button)
      optionButtons.append(button)
    }
  }

  @objc private func handleOptionTap(_ sender: UIButton) {
    guard let option = LanguageOption(rawValue: sender.tag) else { return }
    onSelect(option)
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
