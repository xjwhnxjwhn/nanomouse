//
//  KeyboardExtensionScreenshotHostViewController.swift
//
//  Screenshot-only host that asks iOS to present the real keyboard extension.
//

import UIKit

final class KeyboardExtensionScreenshotHostViewController: UIViewController {
  private let scenario: ScreenshotScenario
  private let textView = UITextView()
  private var didRequestKeyboard = false

  init(scenario: ScreenshotScenario) {
    self.scenario = scenario
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground

    setupTextPreview()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    presentSystemKeyboardIfNeeded()
  }

  private func setupTextPreview() {
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.text = screenshotDescription
    textView.font = .preferredFont(forTextStyle: .title3)
    textView.textColor = .label
    textView.backgroundColor = .secondarySystemGroupedBackground
    textView.layer.cornerRadius = 18
    textView.layer.cornerCurve = .continuous
    textView.textContainerInset = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    textView.isEditable = true
    textView.isSelectable = true
    textView.accessibilityIdentifier = "screenshot_keyboard_text_view"
    view.addSubview(textView)

    NSLayoutConstraint.activate([
      textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
      textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
      textView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: scenario == .keyboardExtension ? 0.30 : 0.36),
    ])
  }

  private var screenshotDescription: String {
    switch scenario {
    case .keyboardExtension:
      return "字节粘贴键盘\n常用文本、富文本、图片和文件直接停在键盘里，切到输入框后不用离开当前 App 就能一格取用。"
    case .keyboardChinese:
      return "中文输入更顺手\n候选栏、工具栏和语言切换都集中在键盘顶部，输入、管理和扩展入口保持在拇指可达区域。"
    case .keyboardLongPressA:
      return "长按扩展字符\n按住字母即可展开变音字符，适合中英日混输和外文名称输入，不需要切换到额外符号页。"
    case .keyboardNumberPad:
      return "数字九宫格\n长按 123 弹出数字面板，金额、验证码和简单计算可以在同一个键盘动作里完成。"
    default:
      return "NanoMouse Keyboard\n候选栏、工具栏和字节粘贴可以在键盘内直接使用。"
    }
  }

  private func presentSystemKeyboardIfNeeded() {
    guard !didRequestKeyboard else { return }
    didRequestKeyboard = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self else { return }
      self.textView.becomeFirstResponder()
    }
  }
}
