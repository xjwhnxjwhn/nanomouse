//
//  NibLessViewController.swift
//
//
//  Created by morse on 2023/7/5.
//

import UIKit

/// Hamster 基类 UIViewController
open class NibLessViewController: UIViewController {
  private weak var activeTextInputResponder: UIResponder?
  private var keyboardDismissTrailingConstraint: NSLayoutConstraint?
  private var keyboardDismissBottomConstraint: NSLayoutConstraint?
  private lazy var keyboardDismissFloatingButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.layer.cornerRadius = 21
    button.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
    button.tintColor = .label
    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    button.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: config), for: .normal)
    button.addTarget(self, action: #selector(handleKeyboardDismissTap), for: .touchUpInside)
    button.accessibilityLabel = "收起键盘"
    button.isHidden = true
    button.alpha = 0
    return button
  }()

  public init() {
    super.init(nibName: nil, bundle: nil)
    registerKeyboardDismissObservers()
  }

  override public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    registerKeyboardDismissObservers()
  }

  @available(*, unavailable,
             message: "为了支持从 init 依赖注入，从 nib 加载这个视图控制器是不被支持的。")
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  /// 弹出一个确认对话框
  public func alertConfirm(alertTitle: String, message: String? = nil, confirmTitle: String, confirmCallback: @escaping () -> Void) {
    let optionMenu = UIAlertController(title: alertTitle, message: message, preferredStyle: .alert)

    let confirmAction = UIAlertAction(title: confirmTitle, style: .destructive) { _ in
      confirmCallback()
    }
    optionMenu.addAction(confirmAction)

    let cancelAction = UIAlertAction(title: "取消", style: .cancel)
    optionMenu.addAction(cancelAction)

    present(optionMenu, animated: true)
  }

  /// 弹出包含一个文本框的对话框
  public func alertText(alertTitle: String? = nil, submitTitle: String, submitCallback: @escaping (UITextField) -> Void) {
    let optionMenu = UIAlertController(title: alertTitle, message: nil, preferredStyle: .alert)
    optionMenu.addTextField()

    let submitAction = UIAlertAction(title: submitTitle, style: .default) { [unowned optionMenu] _ in
      let textField = optionMenu.textFields![0]
      submitCallback(textField)
    }
    optionMenu.addAction(submitAction)

    let cancelAction = UIAlertAction(title: "取消", style: .cancel)
    optionMenu.addAction(cancelAction)

    present(optionMenu, animated: true)
  }

  /// 弹出选择列表对话表
  public func alertOptionSheet(alertTitle: String? = nil, addAlertOptions: @escaping (UIAlertController) -> Void) {
    let optionMenu = UIAlertController(title: alertTitle, message: nil, preferredStyle: .actionSheet)

    addAlertOptions(optionMenu)

    let cancelAction = UIAlertAction(title: "取消", style: .cancel)
    optionMenu.addAction(cancelAction)

    present(optionMenu, animated: true)
  }

  private func registerKeyboardDismissObservers() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTextInputDidBeginEditing(_:)),
      name: UITextField.textDidBeginEditingNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTextInputDidBeginEditing(_:)),
      name: UITextView.textDidBeginEditingNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTextInputDidEndEditing(_:)),
      name: UITextField.textDidEndEditingNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTextInputDidEndEditing(_:)),
      name: UITextView.textDidEndEditingNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleKeyboardDidHide(_:)),
      name: UIResponder.keyboardDidHideNotification,
      object: nil
    )
  }

  @objc private func handleTextInputDidBeginEditing(_ notification: Notification) {
    guard isViewLoaded else { return }
    if let textField = notification.object as? UITextField {
      guard textField.window === view.window else { return }
      activeTextInputResponder = textField
      attachFloatingDismissButtonIfNeeded()
      showFloatingDismissButton()
      return
    }
    if let textView = notification.object as? UITextView {
      guard textView.window === view.window else { return }
      activeTextInputResponder = textView
      attachFloatingDismissButtonIfNeeded()
      showFloatingDismissButton()
    }
  }

  @objc private func handleTextInputDidEndEditing(_ notification: Notification) {
    guard let responder = notification.object as? UIResponder else { return }
    guard responder === activeTextInputResponder else { return }
    activeTextInputResponder = nil
  }

  @objc private func handleKeyboardDidHide(_ notification: Notification) {
    guard activeTextInputResponder == nil else { return }
    hideFloatingDismissButton()
  }

  private func attachFloatingDismissButtonIfNeeded() {
    guard keyboardDismissFloatingButton.superview == nil else { return }
    view.addSubview(keyboardDismissFloatingButton)
    let trailing = keyboardDismissFloatingButton.trailingAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.trailingAnchor,
      constant: -12
    )
    let bottom = keyboardDismissFloatingButton.bottomAnchor.constraint(
      equalTo: view.keyboardLayoutGuide.topAnchor,
      constant: -12
    )
    keyboardDismissTrailingConstraint = trailing
    keyboardDismissBottomConstraint = bottom
    NSLayoutConstraint.activate([
      keyboardDismissFloatingButton.widthAnchor.constraint(equalToConstant: 42),
      keyboardDismissFloatingButton.heightAnchor.constraint(equalToConstant: 42),
      trailing,
      bottom
    ])
  }

  private func showFloatingDismissButton() {
    keyboardDismissFloatingButton.isHidden = false
    keyboardDismissFloatingButton.alpha = 1
    view.layoutIfNeeded()
  }

  private func hideFloatingDismissButton() {
    keyboardDismissFloatingButton.alpha = 0
    keyboardDismissFloatingButton.isHidden = true
  }

  @objc private func handleKeyboardDismissTap() {
    view.endEditing(true)
  }
}
