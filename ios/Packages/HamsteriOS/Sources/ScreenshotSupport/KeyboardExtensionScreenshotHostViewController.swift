//
//  KeyboardExtensionScreenshotHostViewController.swift
//
//  Screenshot-only host for rendering the keyboard extension UI in UITests.
//

import HamsterKeyboardKit
import UIKit

final class KeyboardExtensionScreenshotHostViewController: UIViewController {
  private let textView = UITextView()
  private let keyboardController = KeyboardInputViewController()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground

    KeyboardEmbeddedModuleRegistry.shared.registerDefaultPrivateProvidersIfNeeded()
    setupTextPreview()
    setupKeyboardPreview()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    keyboardController.setKeyboardType(.chinese(.lowercased))
  }

  private func setupTextPreview() {
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.text = "NanoMouse Keyboard\n候选栏、工具栏和字节粘贴可以在键盘内直接使用。"
    textView.font = .preferredFont(forTextStyle: .title3)
    textView.textColor = .label
    textView.backgroundColor = .secondarySystemGroupedBackground
    textView.layer.cornerRadius = 18
    textView.textContainerInset = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    textView.isEditable = false
    view.addSubview(textView)

    NSLayoutConstraint.activate([
      textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
      textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
      textView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.34),
    ])
  }

  private func setupKeyboardPreview() {
    addChild(keyboardController)
    keyboardController.view.translatesAutoresizingMaskIntoConstraints = false
    keyboardController.view.backgroundColor = .systemBackground
    view.addSubview(keyboardController.view)
    NSLayoutConstraint.activate([
      keyboardController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      keyboardController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      keyboardController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      keyboardController.view.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.42),
    ])
    keyboardController.didMove(toParent: self)
  }
}
