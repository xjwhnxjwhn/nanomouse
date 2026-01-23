//
//  InputSchemaDetailViewController.swift
//
//
//  Created by Claude on 2024.
//

import Combine
import HamsterUIKit
import UIKit

/// 输入方案详情页面（中英或日语）
class InputSchemaDetailViewController: NibLessViewController {
  private let inputSchemaViewModel: InputSchemaViewModel
  private let schemaGroup: InputSchemaViewModel.SchemaGroup

  private var subscriptions = Set<AnyCancellable>()

  init(inputSchemaViewModel: InputSchemaViewModel, schemaGroup: InputSchemaViewModel.SchemaGroup) {
    self.inputSchemaViewModel = inputSchemaViewModel
    self.schemaGroup = schemaGroup

    super.init()

    // 异常订阅
    inputSchemaViewModel.errorMessagePublisher
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] in
        presentError(error: $0)
      }
      .store(in: &subscriptions)
  }
}

// MARK: - Override UIViewController

extension InputSchemaDetailViewController {
  override func loadView() {
    title = schemaGroup.title
    view = InputSchemaRootView(inputSchemaViewModel: inputSchemaViewModel, schemaGroup: schemaGroup)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    inputSchemaViewModel.reloadTableStateSubject.send(true)
  }
}
