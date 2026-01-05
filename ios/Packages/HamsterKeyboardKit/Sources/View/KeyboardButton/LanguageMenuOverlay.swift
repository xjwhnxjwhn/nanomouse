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
      case .english: return "EN"
      }
    }
  }

  private let style: KeyboardActionCalloutStyle
  private let options: [LanguageOption]
  private let onSelect: (LanguageOption) -> Void

  private let menuContainer = UIView()
  private let stackView = UIStackView()

  private let buttonSize = CGSize(width: 44, height: 32)
  private let padding: CGFloat = 8
  private let spacing: CGFloat = 6
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

  private func setupView() {
    backgroundColor = .clear

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
    tap.delegate = self
    addGestureRecognizer(tap)

    menuContainer.backgroundColor = style.callout.backgroundColor
    menuContainer.layer.cornerRadius = style.callout.cornerRadius
    menuContainer.layer.borderColor = style.callout.borderColor.cgColor
    menuContainer.layer.borderWidth = 1
    menuContainer.layer.shadowColor = style.callout.shadowColor.cgColor
    menuContainer.layer.shadowOpacity = 1
    menuContainer.layer.shadowRadius = style.callout.shadowRadius
    menuContainer.layer.shadowOffset = CGSize(width: 0, height: 2)

    addSubview(menuContainer)
    menuContainer.addSubview(stackView)

    stackView.axis = .horizontal
    stackView.alignment = .fill
    stackView.distribution = .fillEqually
    stackView.spacing = spacing

    for option in options {
      let button = UIButton(type: .system)
      button.setTitle(option.title, for: .normal)
      button.setTitleColor(style.callout.textColor, for: .normal)
      button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .callout)
      button.tag = option.rawValue
      button.addTarget(self, action: #selector(handleOptionTap(_:)), for: .touchUpInside)
      stackView.addArrangedSubview(button)
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
