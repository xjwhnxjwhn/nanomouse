//
//  InputSchemaSelectViewController.swift
//
//
//  Created by Claude on 2024.
//

import Combine
import HamsterUIKit
import UIKit

/// 输入方案分组选择页面
class InputSchemaSelectViewController: NibLessViewController {
  private let inputSchemaViewModel: InputSchemaViewModel
  private let documentPickerViewController: UIDocumentPickerViewController
  private lazy var cloudInputSchemaViewController: CloudInputSchemaViewController = .init(inputSchemaViewModel: inputSchemaViewModel)

  private var subscriptions = Set<AnyCancellable>()

  init(inputSchemaViewModel: InputSchemaViewModel, documentPickerViewController: UIDocumentPickerViewController) {
    self.inputSchemaViewModel = inputSchemaViewModel
    self.documentPickerViewController = documentPickerViewController

    super.init()

    self.documentPickerViewController.delegate = self

    // 导航栏导入按钮
    let importItem = UIBarButtonItem(systemItem: .add)
    importItem.menu = inputSchemaViewModel.inputSchemaMenus()
    navigationItem.rightBarButtonItem = importItem

    inputSchemaViewModel.presentDocumentPickerPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self else { return }
        switch $0 {
        case .documentPicker: self.presentDocumentPicker()
        case .downloadCloudInputSchema: self.presentCloudInputSchema()
        default: return
        }
      }
      .store(in: &subscriptions)

    // 异常订阅
    inputSchemaViewModel.errorMessagePublisher
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] in
        presentError(error: $0)
      }
      .store(in: &subscriptions)
  }

  /// Present the document picker.
  func presentDocumentPicker() {
    present(documentPickerViewController, animated: true, completion: nil)
  }

  /// 云存储输入方案下载
  func presentCloudInputSchema() {
    navigationController?.pushViewController(cloudInputSchemaViewController, animated: true)
  }
}

// MARK: - Override UIViewController

extension InputSchemaSelectViewController {
  override func loadView() {
    title = "输入方案设置"
    view = InputSchemaSelectRootView(delegate: self)
  }
}

// MARK: - InputSchemaSelectDelegate

extension InputSchemaSelectViewController: InputSchemaSelectDelegate {
  func didSelectSchemaGroup(_ group: InputSchemaViewModel.SchemaGroup) {
    let detailVC = InputSchemaDetailViewController(
      inputSchemaViewModel: inputSchemaViewModel,
      schemaGroup: group
    )
    navigationController?.pushViewController(detailVC, animated: true)
  }
}

// MARK: - UIDocumentPickerDelegate

extension InputSchemaSelectViewController: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard !urls.isEmpty else {
      return
    }
    Task {
      await self.inputSchemaViewModel.importZipFile(fileURL: urls[0])
    }
  }
}
