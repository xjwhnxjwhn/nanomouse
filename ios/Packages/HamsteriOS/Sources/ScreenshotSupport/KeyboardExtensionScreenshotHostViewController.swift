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
    textView.text = "NanoMouse Keyboard\n候选栏、工具栏和字节粘贴可以在键盘内直接使用。"
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

  private func presentSystemKeyboardIfNeeded() {
    guard !didRequestKeyboard else { return }
    didRequestKeyboard = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self else { return }
      self.textView.becomeFirstResponder()
    }
  }
}
