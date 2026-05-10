//
//  SettingsViewController.swift
//
//  Created by morse on 2023/6/12.
//

import HamsterKit
import HamsterUIKit
import OSLog
import ProgressHUD
import UIKit

protocol SettingsViewModelFactory {
  func makeSettingsViewModel() -> SettingsViewModel
}

public class SettingsViewController: NibLessViewController {
  // MARK: - properties

  private var settingsViewModel: SettingsViewModel
  private var rimeViewModel: RimeViewModel
  private var backupViewModel: BackupViewModel
  private var shouldShowMainTitle = true
  private var languageObserver: NSObjectProtocol?

  init(settingsViewModel: SettingsViewModel, rimeViewModel: RimeViewModel, backupViewModel: BackupViewModel) {
    self.settingsViewModel = settingsViewModel
    self.rimeViewModel = rimeViewModel
    self.backupViewModel = backupViewModel
    super.init()
  }

  func setMainTitleVisible(_ visible: Bool) {
    shouldShowMainTitle = visible
    let title = visible ? AppL10n.text("输入法设置") : ""
    self.title = title
    navigationItem.title = title
    navigationItem.largeTitleDisplayMode = visible ? .automatic : .never
  }

  deinit {
    if let languageObserver {
      NotificationCenter.default.removeObserver(languageObserver)
    }
  }
}

// MARK: override UIViewController

public extension SettingsViewController {
  override func loadView() {
    title = shouldShowMainTitle ? AppL10n.text("输入法设置") : ""
    view = SettingsRootView(settingsViewModel: settingsViewModel, rimeViewModel: rimeViewModel, backupViewModel: backupViewModel)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    setMainTitleVisible(shouldShowMainTitle)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    languageObserver = NotificationCenter.default.addObserver(
      forName: AppLocalization.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      setMainTitleVisible(shouldShowMainTitle)
      settingsViewModel.reloadLocalizedSections()
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task {
      do {
        try await self.settingsViewModel.loadAppData()
      } catch {
        ProgressHUD.failed(AppL10n.text("导入数据异常"), interaction: false, delay: 2)
        Logger.statistics.error("load app data error: \(error)")
      }
    }
  }

}
