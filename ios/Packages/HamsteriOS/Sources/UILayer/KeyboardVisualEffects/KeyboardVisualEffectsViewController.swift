//
//  KeyboardVisualEffectsViewController.swift
//
//
//  Created by Codex on 2026/05/24.
//

import HamsterUIKit
import UIKit

public final class KeyboardVisualEffectsViewController: NibLessViewController {
  private let keyboardSettingsViewModel: KeyboardSettingsViewModel

  init(keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel
    super.init()
  }

  public override func loadView() {
    title = "键盘视觉效果"
    view = KeyboardVisualEffectsRootView(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }
}
