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

  enum AzooKeyModeOption: String, CaseIterable {
    case standard
    case zenzai

    var displayName: String {
      switch self {
      case .standard: return "标准模式（默认）"
      case .zenzai: return "Zenzai 增强"
      }
    }
  }

  enum ZenzaiModelQuality: String, CaseIterable {
    case low
    case high

    var displayName: String {
      switch self {
      case .low: return "Low（21MB，适合大多数设备）"
      case .high: return "High（74MB，仅限 iPhone 15 Pro 及以上）"
      }
    }

    var fileName: String {
      switch self {
      case .low: return HamsterConstants.azooKeyZenzaiWeightFileLow
      case .high: return HamsterConstants.azooKeyZenzaiWeightFileHigh
      }
    }
  }

  enum AzooKeyAdvancedOption: String, CaseIterable {
    case englishCandidate
    case typographyLetter

    var displayName: String {
      switch self {
      case .englishCandidate: return "日语输入中的英语单词转换"
      case .typographyLetter: return "装饰英文字符转换"
      }
    }

    var explanation: String {
      switch self {
      case .englishCandidate: return "在罗马字日语输入时显示英语单词候选，如「いんてれsちんg」→「interesting」"
      case .typographyLetter: return "在英文输入时显示装饰字体候选，如「typography」→「𝕥𝕪𝕡𝕠𝕘𝕣𝕒𝕡𝕙𝕪」"
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
    let schemas = rimeContext.schemas.filter { schemaGroup(for: $0) == group }
    guard group == .japanese else { return schemas }
    return japaneseSchemas.map { placeholder in
      schemas.first(where: { $0.schemaId == placeholder.schemaId }) ?? placeholder
    }
  }

  func schemaGroup(for schema: RimeSchema) -> SchemaGroup {
    schema.isJapaneseSchema ? .japanese : .chineseEnglish
  }

  func selectedSchema(in group: SchemaGroup) -> RimeSchema? {
    rimeContext.selectSchemas.first { schemaGroup(for: $0) == group }
  }

  func isSchemaSelected(_ schema: RimeSchema) -> Bool {
    if schemaGroup(for: schema) == .japanese, !schemaFileExists(schema.schemaId) {
      return false
    }
    return rimeContext.selectSchemas.contains(schema)
  }

  func isSchemaAvailable(_ schema: RimeSchema) -> Bool {
    guard schemaGroup(for: schema) == .japanese else { return true }
    return schemaFileExists(schema.schemaId)
  }

  var shouldShowRimeIceTraditionalizationSection: Bool {
    rimeContext.selectSchemas.contains(where: { $0.schemaId == "rime_ice" })
  }

  var shouldShowAzooKeyModeSection: Bool {
    rimeContext.selectSchemas.contains(where: { $0.schemaId == HamsterConstants.azooKeySchemaId })
      && FileManager.isAzooKeyDictionaryAvailable()
  }

  var selectedAzooKeyMode: AzooKeyMode {
    UserDefaults.hamster.azooKeyMode
  }

  func isAzooKeyModeOptionSelected(_ option: AzooKeyModeOption) -> Bool {
    selectedAzooKeyMode.rawValue == option.rawValue
  }

  func isAzooKeyModeOptionAvailable(_ option: AzooKeyModeOption) -> Bool {
    switch option {
    case .standard:
      return true
    case .zenzai:
      return FileManager.azooKeyZenzaiWeightURL() != nil
    }
  }

  /// 检测设备是否支持 High 质量模型（iPhone 15 Pro 及以上，或 M 系列芯片）
  var isHighQualityZenzaiSupported: Bool {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { id, element in
      guard let value = element.value as? Int8, value != 0 else { return id }
      return id + String(UnicodeScalar(UInt8(value)))
    }

    // iPhone 15 Pro = iPhone16,1, iPhone 15 Pro Max = iPhone16,2
    // iPhone 16 系列 = iPhone17,x
    // iPad Pro M1/M2/M4 = iPad13,x / iPad14,x 等
    if identifier.hasPrefix("iPhone") {
      if let range = identifier.range(of: "iPhone"),
         let majorVersion = Int(identifier[range.upperBound...].prefix(while: { $0.isNumber })) {
        return majorVersion >= 16 // iPhone 15 Pro 及以上
      }
    }
    // iPad Pro with M chip
    if identifier.hasPrefix("iPad") {
      if let range = identifier.range(of: "iPad"),
         let majorVersion = Int(identifier[range.upperBound...].prefix(while: { $0.isNumber })) {
        return majorVersion >= 13 // iPad Pro M1 及以上
      }
    }
    // Mac (Catalyst) 或模拟器
    if identifier.hasPrefix("arm64") || identifier.contains("Mac") {
      return true
    }
    return false
  }

  func isZenzaiModelQualityAvailable(_ quality: ZenzaiModelQuality) -> Bool {
    switch quality {
    case .low:
      return true
    case .high:
      return isHighQualityZenzaiSupported
    }
  }

  /// 获取当前已下载的 Zenzai 模型质量
  var downloadedZenzaiQuality: ZenzaiModelQuality? {
    guard let url = FileManager.azooKeyZenzaiWeightURL() else { return nil }
    let fileName = url.lastPathComponent
    if fileName.contains("xsmall") || fileName == HamsterConstants.azooKeyZenzaiWeightFileLow {
      return .low
    }
    if fileName.contains("small") || fileName == HamsterConstants.azooKeyZenzaiWeightFileHigh {
      return .high
    }
    return .low // 默认当作 low
  }

  var selectedTraditionalizationOpenccConfig: String {
    HamsterAppDependencyContainer.shared.configuration.rime?.traditionalizationOpenccConfig ?? "s2twp.json"
  }

  func isTraditionalizationOptionSelected(_ option: TraditionalizationOption) -> Bool {
    selectedTraditionalizationOpenccConfig.lowercased() == option.configFileName
  }

  @MainActor
  func selectAzooKeyModeOption(_ option: AzooKeyModeOption) {
    guard isAzooKeyModeOptionAvailable(option) else { return }
    UserDefaults.hamster.azooKeyMode = AzooKeyMode(rawValue: option.rawValue) ?? .standard
    reloadTableStateSubject.send(true)
  }

  func isAzooKeyAdvancedOptionEnabled(_ option: AzooKeyAdvancedOption) -> Bool {
    switch option {
    case .englishCandidate:
      return UserDefaults.hamster.azooKeyEnglishCandidate
    case .typographyLetter:
      return UserDefaults.hamster.azooKeyTypographyLetter
    }
  }

  @MainActor
  func toggleAzooKeyAdvancedOption(_ option: AzooKeyAdvancedOption) {
    switch option {
    case .englishCandidate:
      UserDefaults.hamster.azooKeyEnglishCandidate.toggle()
    case .typographyLetter:
      UserDefaults.hamster.azooKeyTypographyLetter.toggle()
    }
    reloadTableStateSubject.send(true)
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
    case HamsterConstants.azooKeySchemaId:
      return "AzooKey（推荐）"
    case "japanese":
      return "rime-japanese"
    case "jaroomaji":
      return "rime-jaroomaji"
    case "jaroomaji-easy":
      return "rime-jaroomaji-easy"
    default:
      return schema.schemaName
    }
  }

  private var japaneseSchemas: [RimeSchema] {
    [
      .init(schemaId: HamsterConstants.azooKeySchemaId, schemaName: "AzooKey"),
      .init(schemaId: "japanese", schemaName: "japanese"),
      .init(schemaId: "jaroomaji", schemaName: "jaroomaji"),
      .init(schemaId: "jaroomaji-easy", schemaName: "jaroomaji-easy"),
    ]
  }

  private func schemaFileExists(_ schemaId: String) -> Bool {
    if schemaId == HamsterConstants.azooKeySchemaId {
      return FileManager.isAzooKeyDictionaryAvailable()
    }
    let fileName = "\(schemaId).schema.yaml"
    let userDataPath = FileManager.appGroupUserDataDirectoryURL.appendingPathComponent(fileName)
    let sharedSupportPath = FileManager.appGroupSharedSupportDirectoryURL.appendingPathComponent(fileName)
    let fm = FileManager.default
    return fm.fileExists(atPath: userDataPath.path) || fm.fileExists(atPath: sharedSupportPath.path)
  }

  func downloadJapaneseSchema(_ schema: RimeSchema) {
    if schema.schemaId == HamsterConstants.azooKeySchemaId {
      downloadAzooKeyDictionary()
      return
    }
    guard let zipFile = HamsterConstants.onDemandJapaneseSchemaZipMap[schema.schemaId] else {
      ProgressHUD.failed("未找到下载资源", interaction: false, delay: 1.5)
      return
    }
    downloadOnDemandZipFiles([zipFile], title: displayNameForInputSchemaList(schema))
  }

  func downloadExtraSchema(zipFile: String, title: String) {
    downloadOnDemandZipFiles([zipFile], title: title)
  }

  func deleteDownloadedSchema(_ schema: RimeSchema) async {
    ProgressHUD.animate("删除中……", interaction: false)
    do {
      if schema.schemaId == HamsterConstants.azooKeySchemaId {
        try removeAzooKeyFiles()
        if rimeContext.selectSchemas.contains(schema) {
          rimeContext.removeSelectSchema(schema)
        }
        UserDefaults.hamster.azooKeyMode = .standard
        await MainActor.run {
          reloadTableStateSubject.send(true)
          ProgressHUD.success("删除完成", interaction: false, delay: 1.0)
        }
        return
      }
      try removeSchemaFiles(schemaId: schema.schemaId)
      if rimeContext.selectSchemas.contains(schema) {
        rimeContext.removeSelectSchema(schema)
      }

      var updatedConfiguration = HamsterAppDependencyContainer.shared.configuration
      try rimeContext.deployment(configuration: &updatedConfiguration)

      await MainActor.run {
        HamsterAppDependencyContainer.shared.configuration = updatedConfiguration
        reloadTableStateSubject.send(true)
        ProgressHUD.success("删除完成", interaction: false, delay: 1.0)
      }
    } catch {
      Logger.statistics.error("delete schema failed: \(error.localizedDescription)")
      await MainActor.run {
        ProgressHUD.failed("删除失败：\(error.localizedDescription)", interaction: false, delay: 2)
      }
    }
  }

  private func downloadOnDemandZipFiles(_ zipFiles: [String], title: String) {
    downloadOnDemandZipFiles(zipFiles, title: title, destination: FileManager.appGroupUserDataDirectoryURL, needsRimeDeploy: true)
  }

  private func downloadOnDemandZipFiles(
    _ zipFiles: [String],
    title: String,
    destination: URL,
    needsRimeDeploy: Bool,
    onSuccess: (() -> Void)? = nil
  ) {
    guard let baseURL = URL(string: HamsterConstants.onDemandInputSchemaZipBaseURL) else {
      ProgressHUD.failed("下载地址无效", interaction: false, delay: 1.5)
      return
    }

    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      await MainActor.run {
        ProgressHUD.animate("正在下载\(title)…", AnimationType.circleRotateChase, interaction: false)
      }

      do {
        try FileManager.createDirectory(override: false, dst: destination)

        for zipFile in zipFiles {
          let remoteURL = baseURL.appendingPathComponent(zipFile)
          let tempURL = try await self.downloadZip(from: remoteURL)
          try await FileManager.default.unzip(tempURL, dst: destination)
          try? FileManager.default.removeItem(at: tempURL)
        }

        if needsRimeDeploy {
          var updatedConfiguration = HamsterAppDependencyContainer.shared.configuration
          try self.rimeContext.deployment(configuration: &updatedConfiguration)

          await MainActor.run {
            HamsterAppDependencyContainer.shared.configuration = updatedConfiguration
            self.reloadTableStateSubject.send(true)
            onSuccess?()
            ProgressHUD.success("\(title)部署完成", interaction: false, delay: 1.2)
          }
        } else {
          await MainActor.run {
            self.reloadTableStateSubject.send(true)
            onSuccess?()
            ProgressHUD.success("\(title)下载完成", interaction: false, delay: 1.2)
          }
        }
      } catch {
        Logger.statistics.error("download on-demand schemas failed: \(error.localizedDescription)")
        await MainActor.run {
          ProgressHUD.failed("下载失败：\(error.localizedDescription)", interaction: false, delay: 2)
        }
      }
    }
  }

  private func downloadZip(from url: URL) async throws -> URL {
    let (tempURL, response) = try await URLSession.shared.download(from: url)
    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
      try? FileManager.default.removeItem(at: tempURL)
      throw StringError("下载失败（HTTP \(httpResponse.statusCode)）")
    }
    return tempURL
  }

  private func removeSchemaFiles(schemaId: String) throws {
    let fm = FileManager.default
    let targets: [URL] = [
      FileManager.appGroupSharedSupportDirectoryURL,
      FileManager.appGroupUserDataDirectoryURL,
      FileManager.appGroupUserDataDirectoryURL.appendingPathComponent("build"),
    ]

    for root in targets {
      guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
      for case let fileURL as URL in enumerator {
        let name = fileURL.lastPathComponent
        if matchesSchemaFile(name: name, schemaId: schemaId) {
          try? fm.removeItem(at: fileURL)
        }
      }
    }
  }

  private func matchesSchemaFile(name: String, schemaId: String) -> Bool {
    if schemaId == "jaroomaji" {
      return name.hasPrefix("jaroomaji.") || name.hasPrefix("jaroomaji_")
    }
    return name.hasPrefix("\(schemaId).")
      || name.hasPrefix("\(schemaId)_")
      || name.hasPrefix("\(schemaId)-")
      || name == schemaId
  }

  private func downloadAzooKeyDictionary() {
    downloadOnDemandZipFiles(
      [HamsterConstants.azooKeyDictionaryZipFile],
      title: "AzooKey 词库",
      destination: FileManager.appGroupAzooKeyDirectoryURL,
      needsRimeDeploy: false
    ) { [weak self] in
      guard let self else { return }
      // 下载完成后默认勾选
      let azooKeySchema = RimeSchema(schemaId: HamsterConstants.azooKeySchemaId, schemaName: "AzooKey")
      let selectedJapanese = self.rimeContext.selectSchemas.filter { self.schemaGroup(for: $0) == .japanese }
      for item in selectedJapanese where item.schemaId != HamsterConstants.azooKeySchemaId {
        self.rimeContext.removeSelectSchema(item)
      }
      if !self.rimeContext.selectSchemas.contains(azooKeySchema) {
        self.rimeContext.appendSelectSchema(azooKeySchema)
      }
      self.reloadTableStateSubject.send(true)
    }
  }

  func downloadAzooKeyZenzai(quality: ZenzaiModelQuality) {
    guard let baseURL = URL(string: HamsterConstants.onDemandInputSchemaZipBaseURL) else {
      ProgressHUD.failed("下载地址无效", interaction: false, delay: 1.5)
      return
    }

    let fileName = quality.fileName
    let remoteURL = baseURL.appendingPathComponent(fileName)
    let destination = FileManager.appGroupAzooKeyZenzaiDirectoryURL
      .appendingPathComponent(fileName)

    Task.detached(priority: .userInitiated) { [weak self] in
      await MainActor.run {
        ProgressHUD.animate("正在下载 Zenzai 模型（\(quality == .low ? "Low" : "High")）…", AnimationType.circleRotateChase, interaction: false)
      }

      do {
        let zenzaiDir = FileManager.appGroupAzooKeyZenzaiDirectoryURL
        try FileManager.createDirectory(override: false, dst: zenzaiDir)

        // 删除旧的模型文件（如果有）
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: zenzaiDir, includingPropertiesForKeys: nil) {
          for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "gguf" {
              try? fm.removeItem(at: fileURL)
            }
          }
        }

        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
          try? FileManager.default.removeItem(at: tempURL)
          throw StringError("下载失败（HTTP \(httpResponse.statusCode)）")
        }

        // 移动到目标位置
        if fm.fileExists(atPath: destination.path) {
          try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)

        await MainActor.run {
          if FileManager.azooKeyZenzaiWeightURL() != nil {
            UserDefaults.hamster.azooKeyMode = .zenzai
          } else {
            UserDefaults.hamster.azooKeyMode = .standard
          }
          self?.reloadTableStateSubject.send(true)
          ProgressHUD.success("Zenzai 模型下载完成", interaction: false, delay: 1.2)
        }
      } catch {
        Logger.statistics.error("download Zenzai weight failed: \(error.localizedDescription)")
        await MainActor.run {
          ProgressHUD.failed("下载失败：\(error.localizedDescription)", interaction: false, delay: 2)
        }
      }
    }
  }

  private func removeAzooKeyFiles() throws {
    let fm = FileManager.default
    let targets: [URL] = [
      FileManager.appGroupAzooKeyDictionaryDirectoryURL,
      FileManager.appGroupAzooKeyZenzaiDirectoryURL,
      FileManager.appGroupAzooKeyMemoryDirectoryURL,
    ]
    for target in targets {
      if fm.fileExists(atPath: target.path) {
        try? fm.removeItem(at: target)
      }
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
      try FileManager.createDirectory(override: true, dst: FileManager.appGroupUserDataDirectoryURL)
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
    let onDemandMenu = UIMenu(
      title: "下载其他中英方案",
      options: .displayInline,
      children: [
        UIAction(
          title: "下载地球拼音",
          image: UIImage(systemName: "globe.asia.australia"),
          handler: { [unowned self] _ in self.downloadExtraSchema(zipFile: "rime-terra-pinyin.zip", title: "地球拼音") }
        ),
        UIAction(
          title: "下载笔画",
          image: UIImage(systemName: "pencil.and.outline"),
          handler: { [unowned self] _ in self.downloadExtraSchema(zipFile: "rime-stroke.zip", title: "笔画") }
        ),
        UIAction(
          title: "下载韩语",
          image: UIImage(systemName: "character.book.closed"),
          handler: { [unowned self] _ in self.downloadExtraSchema(zipFile: "rime-hangyl.zip", title: "韩语") }
        ),
        UIAction(
          title: "下载越南语",
          image: UIImage(systemName: "character.book.closed"),
          handler: { [unowned self] _ in self.downloadExtraSchema(zipFile: "rime-hannomps.zip", title: "越南语") }
        ),
      ]
    )

    let barButtonMenu = UIMenu(title: "", children: [
      UIAction(
        title: "从本地导入方案",
        image: UIImage(systemName: "square.and.arrow.down"),
        handler: { [unowned self] _ in self.presentDocumentPickerSubject.send(.documentPicker) }
      ),
      onDemandMenu,
      UIAction(
        title: "从CloudKit下载方案",
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
      try FileManager.createDirectory(override: false, dst: FileManager.appGroupUserDataDirectoryURL)
      try await FileManager.default.unzip(fileURL, dst: FileManager.appGroupUserDataDirectoryURL)

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
