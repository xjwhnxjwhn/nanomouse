//
//  InputSchemaViewModel.swift
//  Hamster
//
//  Created by morse on 2023/6/13.
//
import CloudKit
import Combine
import HamsterKeyboardKit
import HamsterKit
import HamsterUIKit
import OSLog
import ProgressHUD
import RimeKit
import UIKit

public class InputSchemaViewModel {
  // MARK: properties

  public enum PresentType {
    case documentPicker
    case downloadCloudInputSchema
    case uploadCloudInputSchema
    case inputSchema
  }

  public enum InstallType {
    case replace
    case overwrite
  }

  public struct InputSchemaInfo: Hashable {
    public var id: CKRecord.ID
    public var title: String
    public var author: String
    public var description: String
  }

  public let rimeContext: RimeContext
  public var inputSchemas = [InputSchemaInfo]()
  public var searchText = ""

  /// 查询游标，用于分页加载 CloudKit 中的输入方案信息
  public var inputSchemaQueryCursor: CKQueryOperation.Cursor?

  /// 安装 Subject: 用于 conform 提示
  public let installInputSchemaSubject = PassthroughSubject<(InstallType, InputSchemaInfo), Never>()

  /// 搜索 Subject: 对查询字符做防抖处理，防止短时间多次查询
  public let inputSchemaSearchTextSubject = PassthroughSubject<String, Never>()

  /// 显示上传方案文件 zip documentPicker 控件
  public let presentUploadInputSchemaZipFileSubject = PassthroughSubject<Bool, Never>()

  /// zip UIDocumentPickerViewController 选择文件后回调
  public let uploadInputSchemaPickerFileSubject = PassthroughSubject<URL, Never>()

  /// 上传确认对话框
  public let uploadInputSchemaConfirmSubject = PassthroughSubject<() -> Void, Never>()

  public let inputSchemaDetailsSubject = PassthroughSubject<InputSchemaInfo, Never>()
  public var inputSchemaDetailsPublished: AnyPublisher<InputSchemaInfo, Never> {
    inputSchemaDetailsSubject.eraseToAnyPublisher()
  }

  private let inputSchemasReloadSubject = PassthroughSubject<Result<Bool, Error>, Never>()
  public var inputSchemasReloadPublished: AnyPublisher<Result<Bool, Error>, Never> {
    inputSchemasReloadSubject.eraseToAnyPublisher()
  }

  public let reloadTableStateSubject = PassthroughSubject<Bool, Never>()
  public var reloadTableStatePublisher: AnyPublisher<Bool, Never> {
    reloadTableStateSubject.eraseToAnyPublisher()
  }

  /// 注意: 这是私有属性，在 View 中订阅上面的 presentDocumentPickerPublisher 响应是否打开文档View
  /// 而在 ViewModel 内部使用 presentDocumentPickerSubject 发布状态
  private let presentDocumentPickerSubject = PassthroughSubject<PresentType, Never>()
  public var presentDocumentPickerPublisher: AnyPublisher<PresentType, Never> {
    presentDocumentPickerSubject.eraseToAnyPublisher()
  }

  public var errorMessagePublisher: AnyPublisher<ErrorMessage, Never> {
    errorMessageSubject.eraseToAnyPublisher()
  }

  private let errorMessageSubject = PassthroughSubject<ErrorMessage, Never>()

  // MARK: methods

  public init(rimeContext: RimeContext) {
    self.rimeContext = rimeContext
  }

  enum TraditionalizationOption: String, CaseIterable {
    case s2t
    case s2hk
    case s2tw
    case s2twp

    var configFileName: String {
      "\(rawValue).json"
    }

    var displayName: String {
      switch self {
      case .s2t: return "s2t（通用繁体）"
      case .s2hk: return "s2hk（香港繁体）"
      case .s2tw: return "s2tw（台湾繁体）"
      case .s2twp: return "s2twp（台湾常用词）"
      }
    }
  }

  enum SchemaGroup: Int, CaseIterable {
    case chineseEnglish
    case japanese

    var title: String {
      switch self {
      case .chineseEnglish: return "中英"
      case .japanese: return "日语"
      }
    }
  }

  func schemas(in group: SchemaGroup) -> [RimeSchema] {
    rimeContext.schemas.filter { schemaGroup(for: $0) == group }
  }

  func schemaGroup(for schema: RimeSchema) -> SchemaGroup {
    schema.isJapaneseSchema ? .japanese : .chineseEnglish
  }

  func selectedSchema(in group: SchemaGroup) -> RimeSchema? {
    rimeContext.selectSchemas.first { schemaGroup(for: $0) == group }
  }

  func isSchemaSelected(_ schema: RimeSchema) -> Bool {
    rimeContext.selectSchemas.contains(schema)
  }

  var shouldShowRimeIceTraditionalizationSection: Bool {
    rimeContext.selectSchemas.contains(where: { $0.schemaId == "rime_ice" })
  }

  var selectedTraditionalizationOpenccConfig: String {
    HamsterAppDependencyContainer.shared.configuration.rime?.traditionalizationOpenccConfig ?? "s2twp.json"
  }

  func isTraditionalizationOptionSelected(_ option: TraditionalizationOption) -> Bool {
    selectedTraditionalizationOpenccConfig.lowercased() == option.configFileName
  }

  @MainActor
  func selectTraditionalizationOption(_ option: TraditionalizationOption) {
    guard !isTraditionalizationOptionSelected(option) else { return }

    var configuration = HamsterAppDependencyContainer.shared.configuration
    var appConfiguration = HamsterAppDependencyContainer.shared.applicationConfiguration

    if configuration.rime == nil {
      configuration.rime = RimeConfiguration()
    }
    if appConfiguration.rime == nil {
      appConfiguration.rime = RimeConfiguration()
    }

    configuration.rime?.traditionalizationOpenccConfig = option.configFileName
    appConfiguration.rime?.traditionalizationOpenccConfig = option.configFileName

    HamsterAppDependencyContainer.shared.configuration = configuration
    HamsterAppDependencyContainer.shared.applicationConfiguration = appConfiguration
    reloadTableStateSubject.send(true)

    ProgressHUD.animate("正在重新部署……", interaction: false)

    Task.detached { [weak self] in
      guard let self else { return }
      var updatedConfiguration = configuration
      do {
        try self.rimeContext.deployment(configuration: &updatedConfiguration)
        await MainActor.run {
          HamsterAppDependencyContainer.shared.configuration = updatedConfiguration
          ProgressHUD.success("部署完成", interaction: false, delay: 1.2)
        }
      } catch {
        Logger.statistics.error("rime deploy error: \(error)")
        await MainActor.run {
          ProgressHUD.failed("重新部署失败：\(error.localizedDescription)", interaction: false, delay: 2)
        }
      }
    }
  }

  var isJapaneseEnabled: Bool {
    selectedSchema(in: .japanese) != nil
  }

  func displayNameForInputSchemaList(_ schema: RimeSchema) -> String {
    switch schema.schemaId {
    case "japanese":
      return "rime-japanese"
    case "jaroomaji":
      return "rime-jaroomaji"
    default:
      return schema.schemaName
    }
  }
}

// MARK: - CloudKit 方案管理

extension InputSchemaViewModel {
  private func callbackHandler(_ result: Result<(matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?), Error>, appendState: Bool) {
    if case .failure(let failure) = result {
      Logger.statistics.error("\(failure.localizedDescription)")
      inputSchemasReloadSubject.send(Result.failure(failure))
      return
    }

    if case .success(let success) = result {
      var inputSchemas = appendState ? self.inputSchemas : [InputSchemaInfo]()
      success.matchResults.forEach { id, result in
        if case .success(let record) = result {
          guard let title = record.value(forKey: "title") as? String else { return }
          guard let author = record.value(forKey: "author") as? String else { return }
          guard let descriptions = record.value(forKey: "descriptions") as? String else { return }
          let info = InputSchemaInfo(id: id, title: title, author: author, description: descriptions)
          inputSchemas.append(info)
        }
      }
      self.inputSchemas = inputSchemas
      self.inputSchemaQueryCursor = success.queryCursor
      inputSchemasReloadSubject.send(Result.success(true))
    }
  }

  /// 初始加载 CloudKit 开源输入方案列表
  func initialLoadCloudInputSchema(_ title: String = "") {
    Task {
      do {
        ProgressHUD.animate("加载中……", AnimationType.circleRotateChase, interaction: false)
        try await CloudKitHelper.shared.inputSchemaList(title) { [unowned self] result in
          self.callbackHandler(result, appendState: false)
        }
      } catch {
        inputSchemasReloadSubject.send(Result.failure(error))
      }
    }
  }

  /// 根据游标加载 CloudKit 开源输入方案列表
  func loadCloudInputSchemaByCursor() {
    guard let cursor = self.inputSchemaQueryCursor else { return }
    Task {
      ProgressHUD.animate("加载中……", AnimationType.circleRotateChase, interaction: false)
      try await CloudKitHelper.shared.inputSchemaListByCursor(cursor) { [unowned self] result in
        self.callbackHandler(result, appendState: true)
      }
    }
  }

  /// 覆盖安装下载的方案，相同文件名文件覆盖，不同文件名追加
  func installInputSchemaByOverwrite(_ info: InputSchemaInfo) async {
    let fm = FileManager.default
    let tempInputSchemaZipFile = fm.temporaryDirectory.appendingPathComponent("rime.zip")
    do {
      try await downloadInputSchema(info.id, dst: tempInputSchemaZipFile)
      // 安装
      await importZipFile(fileURL: tempInputSchemaZipFile)
      presentDocumentPickerSubject.send(.inputSchema)
    } catch {
      Logger.statistics.error("\(error.localizedDescription)")
      ProgressHUD.failed(error, interaction: false, delay: 3)
    }
  }

  /// 替换安装下载的方案，删除 Rime 目录，并用下载方案替换 Rime 目录
  func installInputSchemaByReplace(_ info: InputSchemaInfo) async {
    let fm = FileManager.default
    let tempInputSchemaZipFile = fm.temporaryDirectory.appendingPathComponent("rime.zip")
    do {
      try await downloadInputSchema(info.id, dst: tempInputSchemaZipFile)
      // 删除 Rime 目录并新建
      try FileManager.createDirectory(override: true, dst: FileManager.sandboxUserDataDirectory)
      // 安装
      await importZipFile(fileURL: tempInputSchemaZipFile)
      presentDocumentPickerSubject.send(.inputSchema)
    } catch {
      Logger.statistics.error("\(error.localizedDescription)")
      ProgressHUD.failed(error, interaction: false, delay: 3)
    }
  }

  func downloadInputSchema(_ id: CKRecord.ID, dst: URL) async throws {
    do {
      ProgressHUD.animate("下载中……", AnimationType.circleRotateChase)
      let record = try await CloudKitHelper.shared.getRecord(id: id)
      if let asset = record.value(forKey: "data") as? CKAsset, let zipURL = asset.fileURL {
        do {
          let fm = FileManager.default
          if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
          }
          try fm.copyItem(at: zipURL, to: dst)
        } catch {
          Logger.statistics.error("\(error.localizedDescription)")
          throw error
        }
      }
    } catch {
      Logger.statistics.error("\(error.localizedDescription)")
      throw error
    }
  }

  func uploadInputSchema(title: String, author: String, description: String, fileURL: URL) async {
    uploadInputSchemaConfirmSubject.send { [unowned self] in
      Task {
        do {
          ProgressHUD.animate("方案上传中……", interaction: false)
          let fileInfo = try FileManager.default.attributesOfItem(atPath: fileURL.path)
          if let fileSize = fileInfo[FileAttributeKey.size] as? Int {
            if fileSize > Self.maxFileSize {
              ProgressHUD.error("方案文件不能超过 50 MB", interaction: false, delay: 1.5)
              return
            }
          } else {
            ProgressHUD.error("未能获取上传方案文件信息", interaction: false, delay: 1.5)
            return
          }

          let record = CKRecord(recordType: CloudKitHelper.inputSchemaRecordTypeName)
          record.setValue(title, forKey: "title")
          record.setValue(author, forKey: "author")
          record.setValue(description, forKey: "descriptions")

          let asset = CKAsset(fileURL: fileURL)
          record.setObject(asset, forKey: "data")

          _ = try await CloudKitHelper.shared.saveRecord(record)

          ProgressHUD.success("方案上传成功……")
          self.presentDocumentPickerSubject.send(.inputSchema)
        } catch {
          Logger.statistics.error("\(error.localizedDescription)")
          ProgressHUD.error("上传方案失败：\(error.localizedDescription)", interaction: false, delay: 1.5)
        }
      }
    }
  }
}

// MARK: - 本地方案管理

extension InputSchemaViewModel {
  func inputSchemaMenus() -> UIMenu {
    let barButtonMenu = UIMenu(title: "", children: [
      UIAction(
        title: "导入方案",
        image: UIImage(systemName: "square.and.arrow.down"),
        handler: { [unowned self] _ in self.presentDocumentPickerSubject.send(.documentPicker) }
      ),
      UIAction(
        title: "方案下载",
        image: UIImage(systemName: "icloud.and.arrow.down"),
        handler: { [unowned self] _ in self.presentDocumentPickerSubject.send(.downloadCloudInputSchema) }
      ),
    ])
    return barButtonMenu
  }

  func uploadInputSchemaMenus() -> UIMenu {
    let barButtonMenu = UIMenu(title: "", children: [
      UIAction(
        title: "开源方案上传",
        image: UIImage(systemName: "icloud.and.arrow.up"),
        handler: { [unowned self] _ in self.presentDocumentPickerSubject.send(.uploadCloudInputSchema) }
      ),
    ])
    return barButtonMenu
  }

  /// 选择 InputSchema
  func checkboxForInputSchema(_ schema: RimeSchema) async throws {
    let group = schemaGroup(for: schema)
    let selectedInGroup = rimeContext.selectSchemas.filter { schemaGroup(for: $0) == group }

    switch group {
    case .chineseEnglish:
      if selectedInGroup.contains(schema) {
        // 中英分组必须保留一个，点击当前选中不做处理
        break
      }
      for item in selectedInGroup where item != schema {
        rimeContext.removeSelectSchema(item)
      }
      if !rimeContext.selectSchemas.contains(schema) {
        rimeContext.appendSelectSchema(schema)
      }
    case .japanese:
      if selectedInGroup.contains(schema) {
        rimeContext.removeSelectSchema(schema)
      } else {
        for item in selectedInGroup {
          rimeContext.removeSelectSchema(item)
        }
        rimeContext.appendSelectSchema(schema)
      }
    }
    reloadTableStateSubject.send(true)
  }

  /// 导入zip文件
  public func importZipFile(fileURL: URL) async {
    Logger.statistics.debug("file.fileName: \(fileURL.path)")

    ProgressHUD.animate("方案导入中……", AnimationType.circleRotateChase, interaction: false)
    do {
      // 检测 Rime 目录是否存在
      try FileManager.createDirectory(override: false, dst: FileManager.sandboxUserDataDirectory)
      try await FileManager.default.unzip(fileURL, dst: FileManager.sandboxUserDataDirectory)

      var hamsterConfiguration = HamsterAppDependencyContainer.shared.configuration

      ProgressHUD.animate("方案部署中……", interaction: false)
      try rimeContext.deployment(configuration: &hamsterConfiguration)

      HamsterAppDependencyContainer.shared.configuration = hamsterConfiguration

      // 发布
      reloadTableStateSubject.send(true)
      ProgressHUD.success("导入成功", interaction: false, delay: 1.5)
    } catch {
      Logger.statistics.debug("zip \(error)")
      ProgressHUD.failed("导入Zip文件失败, \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: fileURL)
  }
}

public extension InputSchemaViewModel {
  // static let copyright = "云端存储内容均为NanoMouse用户自主上传，内容立场与NanoMouse无关，版权归原作者所有，如有侵权，请联系我(nanomouse.official@gmail.com)删除。"
  static let copyright = "开源输入方案均来自：https://github.com/xjwhnxjwhn/nanomouse 项目，希望将输入方案内置到鼠输入法的作者，可以提交 PR，或者联系我（nanomouse.official@gmail.com）。"
  // 单位： byte
  static let maxFileSize = 50 * 1024 * 1024
}
