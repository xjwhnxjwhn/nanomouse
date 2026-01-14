//
//  File.swift
//
//
//  Created by morse on 2023/7/7.
//

import Combine
import Foundation
import HamsterKeyboardKit
import HamsterKit
import HamsterUIKit
import ProgressHUD
import UIKit

public enum FinderSegmentAction {
  case settings
  case appFiles
  case appGroupFiles
  case iCloudFiles
}

public class FinderViewModel: ObservableObject {
  // MARK: properties

  private var configuration: HamsterConfiguration {
    HamsterAppDependencyContainer.shared.configuration
  }

  public var segmentActionSubject = CurrentValueSubject<FinderSegmentAction, Never>(.settings)
  public var segmentActionPublished: AnyPublisher<FinderSegmentAction, Never> {
    segmentActionSubject.eraseToAnyPublisher()
  }

  public let presentTextEditorSubject = PassthroughSubject<URL, Never>()
  public var presentTextEditorPublished: AnyPublisher<URL, Never> {
    presentTextEditorSubject.eraseToAnyPublisher()
  }

  public var conformPublished: AnyPublisher<Conform, Never> {
    conformSubject.eraseToAnyPublisher()
  }

  private let conformSubject = PassthroughSubject<Conform, Never>()

  public var enableAppleCloud: Bool {
    configuration.general?.enableAppleCloud ?? false
  }

  var regexOnCopyAppGroupDictFile: [String] {
    configuration.rime?.regexOnCopyAppGroupDictFile ?? ["^.*[.]userdb.*$", "^.*[.]txt$"]
  }

  public var textEditorLineWrappingEnabled: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.general?.textEditorLineWrappingEnabled ?? true
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.general?.textEditorLineWrappingEnabled = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.general?.textEditorLineWrappingEnabled = newValue
    }
  }

  lazy var settingItems: [SettingItemModel] = [
    .init(
      text: "存储占用统计",
      buttonAction: { [unowned self] in
        try await generateStorageReport()
      }
    ),
    .init(
      text: "文本编辑器: 自动换行",
      type: .toggle,
      toggleValue: { [unowned self] in textEditorLineWrappingEnabled },
      toggleHandled: { [unowned self] in
        textEditorLineWrappingEnabled = $0
      }
    ),
    .init(
      text: "拷贝键盘词库文件至应用",
      buttonAction: { [unowned self] in
        Task {
          try await copyAppGroupDictFileToAppDocument()
        }
      }
    ),
    .init(
      text: "使用键盘文件覆盖应用文件",
      buttonAction: { [unowned self] in
        overrideDirectoryConform { [unowned self] in
          Task {
            try await overrideAppDocument()
          }
        }
      }
    )
  ]

  // MARK: methods

  init() {}

  @objc func segmentChangeAction(sender: UISegmentedControl) {
    switch sender.selectedSegmentIndex {
    case 0:
      segmentActionSubject.send(.settings)
    case 1:
      segmentActionSubject.send(.appFiles)
    case 2:
      segmentActionSubject.send(.appGroupFiles)
    case 3:
      segmentActionSubject.send(.iCloudFiles)
    default:
      return
    }
  }

  public func openFileEditorController(fileURL: URL) {
    presentTextEditorSubject.send(fileURL)
  }

  public func deleteFileConform(completion: @escaping () -> Void) {
    conformSubject.send(Conform(title: "是否删除？", message: "文件删除后无法恢复，确认删除？", okAction: completion))
  }

  public func overrideDirectoryConform(completion: @escaping () -> Void) {
    conformSubject.send(Conform(title: "是否覆盖？", message: "覆盖后应用文件无法恢复，确认覆盖？", okAction: completion))
  }

  /// 拷贝 AppGroup 下词库文件至应用沙盒目录
  public func copyAppGroupDictFileToAppDocument() async throws {
    ProgressHUD.animate("拷贝中……", interaction: true)
    do {
      try FileManager.copyAppGroupUserDict(regexOnCopyAppGroupDictFile)
    } catch {
      throw error
    }
    ProgressHUD.success("拷贝词库成功", delay: 1.5)
  }

  /// 使用键盘文件覆盖应用沙盒文件
  public func overrideAppDocument() async throws {
    ProgressHUD.animate("覆盖中……", interaction: true)
    do {
      // 使用AppGroup下文件覆盖应用Sandbox下文件
      try FileManager.syncAppGroupSharedSupportDirectoryToSandbox(override: true)
      try FileManager.syncAppGroupUserDataDirectoryToSandbox(override: true)
    } catch {
      throw error
    }
    ProgressHUD.success("完成", delay: 1.5)
  }
}

extension FinderViewModel {
  private struct StorageSection {
    let title: String
    let entries: [(String, Int64)]
  }

  private func storageReportText() -> String {
    let appGroupRoot = FileManager.shareURL
    let sandboxRoot = FileManager.sandboxDirectory

    let appGroupSharedSupport = FileManager.appGroupSharedSupportDirectoryURL
    let appGroupUserData = FileManager.appGroupUserDataDirectoryURL
    let appGroupBuild = appGroupUserData.appendingPathComponent("build")
    let appGroupBackups = FileManager.appGroupBackupDirectory
    let userdbRegex = ["^.*[.]userdb.*$", "^.*[.]txt$"]
    let appGroupUserDB = FileManager.directorySize(appGroupUserData, matching: userdbRegex)

    let sandboxSharedSupport = FileManager.sandboxSharedSupportDirectory
    let sandboxUserData = FileManager.sandboxUserDataDirectory
    let sandboxBackups = FileManager.sandboxBackupDirectory
    let sandboxUserDB = FileManager.directorySize(sandboxUserData, matching: userdbRegex)
    let sandboxLogs = FileManager.sandboxRimeLogDirectory

    let sections: [StorageSection] = [
      .init(title: "AppGroup", entries: [
        ("SharedSupport", FileManager.directorySize(appGroupSharedSupport)),
        ("Rime", FileManager.directorySize(appGroupUserData)),
        ("Rime/build", FileManager.directorySize(appGroupBuild)),
        ("Rime/userdb(+.txt)", appGroupUserDB),
        ("backups", FileManager.directorySize(appGroupBackups)),
      ]),
      .init(title: "Sandbox (Documents)", entries: [
        ("SharedSupport", FileManager.directorySize(sandboxSharedSupport)),
        ("Rime", FileManager.directorySize(sandboxUserData)),
        ("Rime/userdb(+.txt)", sandboxUserDB),
        ("backups", FileManager.directorySize(sandboxBackups)),
        ("Rime logs", FileManager.directorySize(sandboxLogs)),
      ]),
    ]

    var lines: [String] = []
    lines.append("NanoMouse 存储占用报告")
    lines.append("生成时间: \(Date())")
    lines.append("")
    lines.append("根路径")
    lines.append("  AppGroup: \(appGroupRoot.path)")
    lines.append("  Sandbox: \(sandboxRoot.path)")
    lines.append("")

    for section in sections {
      lines.append(section.title)
      for (name, size) in section.entries {
        lines.append("  \(name): \(FileManager.formatByteCount(size))")
      }
      lines.append("")
    }

    let topAppGroup = FileManager.largestFiles(in: appGroupRoot, limit: 15)
    if !topAppGroup.isEmpty {
      lines.append("AppGroup 最大文件")
      for (index, item) in topAppGroup.enumerated() {
        let rel = item.0.path.replacingOccurrences(of: appGroupRoot.path, with: "")
        lines.append("  \(index + 1). \(FileManager.formatByteCount(item.1))  \(rel)")
      }
      lines.append("")
    }

    let topSandbox = FileManager.largestFiles(in: sandboxRoot, limit: 15)
    if !topSandbox.isEmpty {
      lines.append("Sandbox 最大文件")
      for (index, item) in topSandbox.enumerated() {
        let rel = item.0.path.replacingOccurrences(of: sandboxRoot.path, with: "")
        lines.append("  \(index + 1). \(FileManager.formatByteCount(item.1))  \(rel)")
      }
      lines.append("")
    }

    return lines.joined(separator: "\n")
  }

  private func writeStorageReport() throws -> URL {
    let reportText = storageReportText()
    let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("nanomouse_storage_report.txt")
    try reportText.write(to: reportURL, atomically: true, encoding: .utf8)
    return reportURL
  }

  func generateStorageReport() async throws {
    ProgressHUD.animate("统计中……", interaction: false)
    let reportURL = try writeStorageReport()
    await MainActor.run {
      ProgressHUD.dismiss()
      presentTextEditorSubject.send(reportURL)
    }
  }
}
