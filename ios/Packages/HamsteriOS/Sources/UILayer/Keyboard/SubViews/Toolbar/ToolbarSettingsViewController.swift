//
//  CandidateTextBarSettingViewController.swift
//  Hamster
//
//  Created by morse on 2023/6/15.
//

import HamsterUIKit
import UIKit

public class ToolbarSettingsViewController: NibLessViewController {
  private let keyboardSettingsViewModel: KeyboardSettingsViewModel
  private var toolbarSettingsRootView: ToolbarSettingsRootView? {
    view as? ToolbarSettingsRootView
  }

  init(keyboardSettingsViewModel: KeyboardSettingsViewModel) {
    self.keyboardSettingsViewModel = keyboardSettingsViewModel

    super.init()
  }

  override public func loadView() {
    title = "候选栏"
    view = ToolbarSettingsRootView(keyboardSettingsViewModel: keyboardSettingsViewModel)
  }

  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    toolbarSettingsRootView?.scrollToPendingFocusIfNeeded(animated: true)
  }
}
