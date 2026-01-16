//
//  File.swift
//
//
//  Created by morse on 2023/7/4.
//

import CommonCrypto
import Foundation
import os
import ZIPFoundation

/// FileManager 扩展
public extension FileManager {
  /// 创建文件夹
  /// override: 当目标文件夹存在时，是否覆盖
  /// dst: 目标文件夹URL
  static func createDirectory(override: Bool = false, dst: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: dst.path) {
      if override {
        try fm.removeItem(atPath: dst.path)
      } else {
        return
      }
    }
    try fm.createDirectory(
      at: dst,
      withIntermediateDirectories: true,
      attributes: nil
    )
  }

  /// 拷贝文件夹
  /// override: 当目标文件夹存在时，是否覆盖
  /// src: 拷贝源 URL
  /// dst: 拷贝地址 URL
  static func copyDirectory(override: Bool = false, src: URL, dst: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: dst.path) {
      if override {
        try fm.removeItem(atPath: dst.path)
      } else {
        return
      }
    }

    if !fm.fileExists(atPath: dst.deletingLastPathComponent().path) {
      try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    try fm.copyItem(at: src, to: dst)
  }

  /// 增量复制
  /// 增量是指文件名相同且内容相同的文件会跳过，如果是目录，则会比较目录下的内容
  /// filterRegex: 正则表达式，用来过滤复制的文件，true: 需要过滤
  /// filterMatchBreak: 匹配后是否跳过 true 表示跳过匹配文件, 只拷贝非匹配的文件 false 表示只拷贝匹配文件
  static func incrementalCopy(
    src: URL,
    dst: URL,
    filterRegex: [String] = [],
    filterMatchBreak: Bool = true,
    override: Bool = true
  ) throws {
    let fm = FileManager.default
    // 递归获取全部文件
    guard let srcFiles = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
    guard let dstFiles = fm.enumerator(at: dst, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

    let dstFilesMapping = dstFiles.allObjects.compactMap { $0 as? URL }.reduce(into: [String: URL]()) { $0[$1.path.replacingOccurrences(of: dst.path, with: "")] = $1 }
    let srcPrefix = src.path

    while let file = srcFiles.nextObject() as? URL {
      // 正则过滤: true 表示正则匹配成功，false 表示没有匹配正则
      let match = !(filterRegex.first(where: { file.path.isMatch(regex: $0) }) ?? "").isEmpty

      // 匹配且需要跳过匹配项, 这是过滤的默认行为
      if match, filterMatchBreak {
        Logger.statistics.debug("filter filterRegex: \(filterRegex), filterMatchBreak: \(filterMatchBreak), file: \(file.path)")
        continue
      }

      // 不匹配且设置了不跳过匹配项，这是反向过滤行为，即只copy匹配过滤项文件
      if !filterRegex.isEmpty, !match, !filterMatchBreak {
        Logger.statistics.debug("filter filterRegex: \(filterRegex), match: \(match), filterMatchBreak: \(filterMatchBreak), file: \(file.path)")
        continue
      }

      let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      let relativePath = file.path.hasPrefix(srcPrefix) ? file.path.replacingOccurrences(of: srcPrefix, with: "") : file.path.replacingOccurrences(of: "/private" + srcPrefix, with: "")

      let dstFile = dstFilesMapping[relativePath] ?? dst.appendingPathComponent(relativePath, isDirectory: isDirectory)

      if fm.fileExists(atPath: dstFile.path) {
        // 目录不比较内容
        if isDirectory {
          continue
        }

        if fm.contentsEqual(atPath: file.path, andPath: dstFile.path) {
          continue // 文件已存在, 且内容相同，跳过
        }

        if override {
          try fm.removeItem(at: dstFile)
        }
      }

      if !fm.fileExists(atPath: dstFile.deletingLastPathComponent().path) {
        try FileManager.createDirectory(dst: dstFile.deletingLastPathComponent())
      }

      if isDirectory {
        try FileManager.createDirectory(dst: dstFile)
        continue
      }

      Logger.statistics.debug("incrementalCopy copy file: \(file.path) dst: \(dstFile.path)")
      try fm.copyItem(at: file, to: dstFile)
    }
  }
}

// MARK: zip/unzip

/// 添加 zip/unzip 逻辑
public extension FileManager {
  func unzip(_ data: Data, dst: URL) async throws {
    let tempZipURL = temporaryDirectory.appendingPathComponent("temp.zip")
    if fileExists(atPath: tempZipURL.path) {
      try removeItem(at: tempZipURL)
    }
    createFile(atPath: tempZipURL.path, contents: data)
    try await unzip(tempZipURL, dst: dst)
  }

  // 返回值
  // Bool 处理是否成功
  // Error: 处理失败的Error
  func unzip(_ zipURL: URL, dst: URL) async throws {
    var tempURL = zipURL

    // 检测是否为iCloudURL, 需要特殊处理
    if zipURL.path.contains("com~apple~CloudDocs") || zipURL.path.contains("iCloud~com~XiangqingZHANG~nanomouse") {
      // iCloud中的URL须添加安全访问资源语句，否则会异常：Operation not permitted
      // startAccessingSecurityScopedResource与stopAccessingSecurityScopedResource必须成对出现
      if !zipURL.startAccessingSecurityScopedResource() {
        throw StringError("Zip文件读取权限受限")
      }

      let tempPath = temporaryDirectory.appendingPathComponent(zipURL.lastPathComponent)

      // 临时文件如果存在需要先删除
      if fileExists(atPath: tempPath.path) {
        try removeItem(at: tempPath)
      }

      try copyItem(atPath: zipURL.path, toPath: tempPath.path)

      // 停止读取url文件
      zipURL.stopAccessingSecurityScopedResource()

      tempURL = tempPath
    }

    // 读取ZIP内容
    guard let archive = Archive(url: tempURL, accessMode: .read) else {
      throw StringError("读取Zip文件异常")
    }

    // 解压缩文件，已存在文件先删除在解压
    for entry in archive {
      let destinationEntryURL = dst.appendingPathComponent(entry.path)
      if fileExists(atPath: destinationEntryURL.path) {
        try removeItem(at: destinationEntryURL)
      }
      _ = try archive.extract(entry, to: destinationEntryURL, skipCRC32: true)
    }

    // 不在判断是否包含 schema 文件
    // 查找解压的文件夹里有没有名字包含schema.yaml 的文件
    // guard let _ = archive.filter({ $0.path.contains("schema.yaml") }).first else {
    //  throw "Zip文件未包含输入方案文件"
    // }

    // 解压前先删除原Rime目录
    // try removeItem(at: dst)
    // try unzipItem(at: tempURL, to: dst)
  }
}

// MARK: rime tempBackup

public extension FileManager {
  static var tempBackupDirectory: URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("HamsterBackup")
  }

  static var tempSharedSupportDirectory: URL {
    tempBackupDirectory.appendingPathComponent("RIME").appendingPathComponent(HamsterConstants.rimeSharedSupportPathName)
  }

  static var tempUserDataDirectory: URL {
    tempBackupDirectory.appendingPathComponent("RIME").appendingPathComponent(HamsterConstants.rimeUserPathName)
  }

  static var tempAppConfigurationYaml: URL {
    tempBackupDirectory.appendingPathComponent("hamster.yaml")
  }

  static var tempSwipePlist: URL {
    tempBackupDirectory.appendingPathComponent("swipe.plist")
  }
}

// MARK: SHA256

public extension FileManager {
  /// 计算文件 SHA256 的值
  func sha256(filePath path: String) -> String {
    guard let fileHandle = FileHandle(forReadingAtPath: path) else { return "" }
    defer { fileHandle.closeFile() }

    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)

    let bufferSize = 1024 * 1024
    while autoreleasepool(invoking: {
      let data = fileHandle.readData(ofLength: bufferSize)
      if !data.isEmpty {
        data.withUnsafeBytes { ptr in
          _ = CC_SHA256_Update(&context, ptr.baseAddress, CC_LONG(data.count))
        }
        return true
      } else {
        return false
      }
    }) {}

    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&hash, &context)

    return hash.map { String(format: "%02hhx", $0) }.joined()
  }
}

// MARK: 应用内文件路径及操作

public extension FileManager {
  // AppGroup共享目录
  // 注意：AppGroup 为键盘与主应用共享的 RIME 目录
  static var shareURL: URL {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)
    else {
      assertionFailure("Missing App Group container for \(HamsterConstants.appGroupName)")
      let fallback = (try? FileManager.default.url(
        for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      )) ?? FileManager.default.temporaryDirectory
      return fallback.appendingPathComponent("InputSchema")
    }
    return containerURL.appendingPathComponent("InputSchema")
  }

  static var sandboxDirectory: URL {
    (try? FileManager.default.url(
      for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )) ?? FileManager.default.temporaryDirectory
  }

  // AppGroup共享下: SharedSupport目录
  static var appGroupSharedSupportDirectoryURL: URL {
    shareURL.appendingPathComponent(
      HamsterConstants.rimeSharedSupportPathName, isDirectory: true
    )
  }

  // AppGroup共享下: userData目录
  static var appGroupUserDataDirectoryURL: URL {
    shareURL.appendingPathComponent(
      HamsterConstants.rimeUserPathName, isDirectory: true
    )
  }

  // AppGroup 共享下备份目录
  static var appGroupBackupDirectory: URL {
    shareURL.appendingPathComponent("backups", isDirectory: true)
  }

  // AppGroup共享下：userData目录下: default.custom.yaml文件路径
  static var appGroupUserDataDefaultCustomYaml: URL {
    appGroupUserDataDirectoryURL.appendingPathComponent("default.custom.yaml")
  }

  // Sandbox下：userData目录下: default.custom.yaml文件路径
  static var sandboxUserDataDefaultCustomYaml: URL {
    sandboxUserDataDirectory.appendingPathComponent("default.custom.yaml")
  }

  // AppGroup共享下：userData目录下: installation.yaml文件路径
  static var appGroupInstallationYaml: URL {
    appGroupUserDataDirectoryURL.appendingPathComponent("installation.yaml")
  }

  // Sandbox下：userData目录下: installation.yaml文件路径
  static var sandboxInstallationYaml: URL {
    sandboxUserDataDirectory.appendingPathComponent("installation.yaml")
  }

  /// Sandbox/SharedSupport/hamster.yaml 文件
  static var hamsterConfigFileOnSandboxSharedSupport: URL {
    sandboxSharedSupportDirectory.appendingPathComponent("hamster.yaml")
  }

  /// AppGroup/SharedSupport/hamster.yaml 文件
  static var hamsterConfigFileOnAppGroupSharedSupport: URL {
    appGroupSharedSupportDirectoryURL.appendingPathComponent("hamster.yaml")
  }

  /// Sandbox/Rime/hamster.yaml 文件
  static var hamsterConfigFileOnUserData: URL {
    sandboxUserDataDirectory.appendingPathComponent("hamster.yaml")
  }

  /// AppGroup/Rime/hamster.yaml 文件
  static var hamsterConfigFileOnAppGroupUserData: URL {
    appGroupUserDataDirectoryURL.appendingPathComponent("hamster.yaml")
  }

  /// Sandbox/Rime/hamster.custom.yaml 文件
  static var hamsterPatchConfigFileOnUserData: URL {
    sandboxUserDataDirectory.appendingPathComponent("hamster.custom.yaml")
  }

  /// AppGroup/Rime/hamster.custom.yaml 文件
  static var hamsterPatchConfigFileOnAppGroupUserData: URL {
    appGroupUserDataDirectoryURL.appendingPathComponent("hamster.custom.yaml")
  }

  /// Sandbox/Rime/hamster.app.yaml 文件
  /// 用于存储应用配置
  /// 注意：此文件已废弃，应用操作产生的配置存储在 UserDefaults 中
  static var hamsterAppConfigFileOnUserData: URL {
    sandboxUserDataDirectory.appendingPathComponent("hamster.app.yaml")
  }

  /// Sandbox/Rime/hamster.all.yaml 文件
  static var hamsterAllConfigFileOnUserData: URL {
    sandboxUserDataDirectory.appendingPathComponent("hamster.all.yaml")
  }

  /// Sandbox/Rime/build/hamster.yaml 文件
  static var hamsterConfigFileOnBuild: URL {
    sandboxUserDataDirectory.appendingPathComponent("/build/hamster.yaml")
  }

  /// AppGroup/Rime/build/hamster.yaml 文件
  static var hamsterConfigFileOnAppGroupBuild: URL {
    appGroupUserDataDirectoryURL.appendingPathComponent("/build/hamster.yaml")
  }

  // 沙盒 Document 目录下 ShareSupport 目录
  static var sandboxSharedSupportDirectory: URL {
    sandboxDirectory
      .appendingPathComponent(HamsterConstants.rimeSharedSupportPathName, isDirectory: true)
  }

  // 沙盒 Document 目录下 userData 目录
  static var sandboxUserDataDirectory: URL {
    sandboxDirectory
      .appendingPathComponent(HamsterConstants.rimeUserPathName, isDirectory: true)
  }

  // 沙盒 Document 目录下备份目录
  static var sandboxBackupDirectory: URL {
    sandboxDirectory.appendingPathComponent("backups", isDirectory: true)
  }

  // 沙盒 Document 目录下日志目录
  static var sandboxRimeLogDirectory: URL {
    sandboxDirectory.appendingPathComponent("RIMELogger", isDirectory: true)
  }

  // 安装包ShareSupport资源目录
  static var appSharedSupportDirectory: URL {
    Bundle.main.bundleURL
      .appendingPathComponent(
        HamsterConstants.rimeSharedSupportPathName, isDirectory: true
      )
  }

  /// 初始 AppGroup 共享目录下SharedSupport目录资源
  static func initAppGroupSharedSupportDirectory(override: Bool = false) throws {
    try initSharedSupportDirectory(override: override, dst: appGroupSharedSupportDirectoryURL)
  }

  /// 初始沙盒目录下 SharedSupport 目录资源
  static func initSandboxSharedSupportDirectory(override: Bool = false) throws {
    try initSharedSupportDirectory(override: override, dst: sandboxSharedSupportDirectory)
  }

  // 初始化 SharedSupport 目录资源
  private static func initSharedSupportDirectory(override: Bool = false, dst: URL) throws {
    let fm = FileManager()
    if fm.fileExists(atPath: dst.path) {
      if override {
        try fm.removeItem(atPath: dst.path)
      } else {
        try ensureExtraInputSchemaFiles(in: dst)
        // 每次都从 Bundle 复制最新的 hamster.yaml
        try copyBundleHamsterYaml(to: dst)
        return
      }
    }

    if !fm.fileExists(atPath: dst.path) {
      try fm.createDirectory(at: dst, withIntermediateDirectories: true, attributes: nil)
    }

    let src = appSharedSupportDirectory.appendingPathComponent(HamsterConstants.inputSchemaZipFile)

    Logger.statistics.debug("unzip src: \(src), dst: \(dst)")

    // 解压缩输入方案zip文件
    try fm.unzipItem(at: src, to: dst)

    // 解压缩额外输入方案zip文件
    try ensureExtraInputSchemaFiles(in: dst)
    
    // 从 Bundle 复制最新的 hamster.yaml
    try copyBundleHamsterYaml(to: dst)
  }
  
  /// 从 Bundle 复制 hamster.yaml 覆盖目标目录中的版本
  /// 这样可以在不更新 ZIP 的情况下修改 hamster.yaml
  public static func copyBundleHamsterYaml(to dst: URL) throws {
    let fm = FileManager.default
    let bundleHamsterYaml = appSharedSupportDirectory.appendingPathComponent("hamster.yaml")
    let dstHamsterYaml = dst.appendingPathComponent("hamster.yaml")
    
    Logger.statistics.debug("DBG_DEPLOY copyBundleHamsterYaml: bundlePath=\(bundleHamsterYaml.path)")
    Logger.statistics.debug("DBG_DEPLOY copyBundleHamsterYaml: dstPath=\(dstHamsterYaml.path)")
    Logger.statistics.debug("DBG_DEPLOY copyBundleHamsterYaml: bundleExists=\(fm.fileExists(atPath: bundleHamsterYaml.path))")
    
    if fm.fileExists(atPath: bundleHamsterYaml.path) {
      if fm.fileExists(atPath: dstHamsterYaml.path) {
        Logger.statistics.debug("DBG_DEPLOY removing existing dst hamster.yaml")
        try fm.removeItem(at: dstHamsterYaml)
      }
      try fm.copyItem(at: bundleHamsterYaml, to: dstHamsterYaml)
      Logger.statistics.debug("DBG_DEPLOY SUCCESS: copied hamster.yaml from Bundle to \(dstHamsterYaml.path)")
      
      // 验证拷贝后的文件大小
      if let attrs = try? fm.attributesOfItem(atPath: dstHamsterYaml.path),
         let size = attrs[.size] as? Int {
        Logger.statistics.debug("DBG_DEPLOY copied file size: \(size) bytes")
      }
    } else {
      Logger.statistics.error("DBG_DEPLOY FAILED: Bundle hamster.yaml not found at \(bundleHamsterYaml.path)")
    }
  }

  static func ensureExtraInputSchemaFiles(in dst: URL) throws {
    let fm = FileManager.default
    Logger.statistics.debug("DBG_DEPLOY extraInputSchemaZipFiles: \(HamsterConstants.extraInputSchemaZipFiles)")
    for extraZip in HamsterConstants.extraInputSchemaZipFiles {
      let extraSrc = appSharedSupportDirectory.appendingPathComponent(extraZip)
      let isJaroomajiEasy = extraZip.contains("jaroomaji-easy")
      let exists = fm.fileExists(atPath: extraSrc.path)
      if !exists {
        Logger.statistics.debug("DBG_DEPLOY extra schema zip missing: \(extraZip) path=\(extraSrc.path)")
        if isJaroomajiEasy {
          print("DBG_DEPLOY jaroomaji-easy zip missing: \(extraSrc.path)")
        }
        continue
      }
      
      var sizeInfo = ""
      if let attrs = try? fm.attributesOfItem(atPath: extraSrc.path),
         let size = attrs[.size] as? NSNumber {
        sizeInfo = " size=\(size)"
      }
      Logger.statistics.debug("DBG_DEPLOY extra schema zip found: \(extraZip) path=\(extraSrc.path)\(sizeInfo)")
      if isJaroomajiEasy {
        print("DBG_DEPLOY jaroomaji-easy zip found: \(extraSrc.lastPathComponent)\(sizeInfo)")
      }
      
      // 强制覆盖 jaroomaji，以确保 build 脚本的 patch 生效
      let forceOverwrite = extraZip.contains("jaroomaji")
      
      let shouldUnzip = forceOverwrite || needsUnzip(extraSrc, dst: dst)
      Logger.statistics.debug("DBG_DEPLOY extra schema zip decision: \(extraZip) forceOverwrite=\(forceOverwrite) shouldUnzip=\(shouldUnzip)")
      if isJaroomajiEasy {
        print("DBG_DEPLOY jaroomaji-easy unzip? forceOverwrite=\(forceOverwrite) shouldUnzip=\(shouldUnzip) dst=\(dst.path)")
        if let archive = Archive(url: extraSrc, accessMode: .read) {
          var hasSchema = false
          var hasDict = false
          for entry in archive {
            if entry.path == "jaroomaji-easy.schema.yaml" { hasSchema = true }
            if entry.path == "jaroomaji-easy.dict.yaml" { hasDict = true }
            if hasSchema && hasDict { break }
          }
          Logger.statistics.debug("DBG_DEPLOY jaroomaji-easy zip entries: schema=\(hasSchema) dict=\(hasDict)")
          print("DBG_DEPLOY jaroomaji-easy zip entries: schema=\(hasSchema) dict=\(hasDict)")
        } else {
          Logger.statistics.error("DBG_DEPLOY jaroomaji-easy zip open failed: \(extraSrc.path)")
          print("DBG_DEPLOY jaroomaji-easy zip open failed: \(extraSrc.path)")
        }
      }

      guard shouldUnzip else { continue }
      Logger.statistics.debug("unzip extra src: \(extraSrc), dst: \(dst)")
      try fm.unzipOverwrite(extraSrc, dst: dst)
      
      if isJaroomajiEasy {
        let schemaPath = dst.appendingPathComponent("jaroomaji-easy.schema.yaml")
        let dictPath = dst.appendingPathComponent("jaroomaji-easy.dict.yaml")
        let schemaExists = fm.fileExists(atPath: schemaPath.path)
        let dictExists = fm.fileExists(atPath: dictPath.path)
        Logger.statistics.debug("DBG_DEPLOY jaroomaji-easy after unzip: schemaExists=\(schemaExists) dictExists=\(dictExists)")
        print("DBG_DEPLOY jaroomaji-easy after unzip: schemaExists=\(schemaExists) dictExists=\(dictExists)")
      }
    }
  }

  private static func needsUnzip(_ zipURL: URL, dst: URL) -> Bool {
    let fm = FileManager.default
    guard let archive = Archive(url: zipURL, accessMode: .read) else { return false }
    var markerEntry: Entry?
    for entry in archive {
      if markerEntry == nil { markerEntry = entry }
      if entry.path.hasSuffix(".schema.yaml") {
        markerEntry = entry
        break
      }
    }
    guard let markerEntry else { return true }
    let markerPath = dst.appendingPathComponent(markerEntry.path).path
    return !fm.fileExists(atPath: markerPath)
  }

  func unzipOverwrite(_ zipURL: URL, dst: URL) throws {
    guard let archive = Archive(url: zipURL, accessMode: .read) else {
      throw StringError("读取Zip文件异常")
    }

    for entry in archive {
      let destinationEntryURL = dst.appendingPathComponent(entry.path)
      if fileExists(atPath: destinationEntryURL.path) {
        try removeItem(at: destinationEntryURL)
      }
      _ = try archive.extract(entry, to: destinationEntryURL, skipCRC32: true)
    }
  }

  private static let rimeIceCoreDicts = [
    "cn_dicts/8105.dict.yaml",
    "cn_dicts/base.dict.yaml",
    "cn_dicts/ext.dict.yaml",
    "cn_dicts/tencent.dict.yaml",
    "cn_dicts/others.dict.yaml",
  ]

  /// 确保 Rime 核心词库存在，避免旧数据不完整导致缺失
  static func ensureRimeIceCoreDictsExist(in dst: URL) throws {
    let fm = FileManager.default
    let required = rimeIceCoreDicts
    let missing = required.filter { !fm.fileExists(atPath: dst.appendingPathComponent($0).path) }
    guard !missing.isEmpty else { return }

    Logger.statistics.error("RIME missing core dicts: \(missing)")

    let src = appSharedSupportDirectory.appendingPathComponent(HamsterConstants.userDataZipFile)
    guard let archive = Archive(url: src, accessMode: .read) else {
      throw StringError("读取Zip文件异常")
    }

    let missingSet = Set(missing)
    var repaired: [String] = []
    var samplePaths: [String] = []

    for entry in archive {
      if samplePaths.count < 5 {
        samplePaths.append(entry.path)
      }
      guard let requiredPath = missing.first(where: { entry.path.hasSuffix($0) }) else { continue }
      guard missingSet.contains(requiredPath) else { continue }
      let destinationEntryURL = dst.appendingPathComponent(requiredPath)
      if fm.fileExists(atPath: destinationEntryURL.path) {
        try fm.removeItem(at: destinationEntryURL)
      }
      if !fm.fileExists(atPath: destinationEntryURL.deletingLastPathComponent().path) {
        try fm.createDirectory(at: destinationEntryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      }
      _ = try archive.extract(entry, to: destinationEntryURL, skipCRC32: true)
      repaired.append(requiredPath)
    }

    let stillMissing = required.filter { !fm.fileExists(atPath: dst.appendingPathComponent($0).path) }
    if !stillMissing.isEmpty {
      throw StringError("核心词库缺失：\(stillMissing.joined(separator: ", "))")
    }

    // 仅在显式开启时输出补写明细，便于验证
    if UserDefaults.hamster.enableRimeDictRepairLog {
      Logger.statistics.debug("RIME dict repair dst: \(dst.path)")
      Logger.statistics.debug("RIME dict repair src: \(src.path)")
      Logger.statistics.debug("RIME dict repair missing: \(missing.sorted())")
      Logger.statistics.debug("RIME dict repair archive sample: \(samplePaths)")
      Logger.statistics.debug("RIME repaired core dicts: \(repaired.sorted())")
    }
  }

  /// 输出 Rime 用户目录结构，便于核对实际路径
  static func debugRimeUserDataLayout(in dst: URL, note: String) {
    guard UserDefaults.hamster.enableRimeDictRepairLog else { return }
    let fm = FileManager.default
    let cnDicts = dst.appendingPathComponent("cn_dicts")

    Logger.statistics.debug("RIME layout \(note): root=\(dst.path)")
    Logger.statistics.debug("RIME layout \(note): cn_dicts exists=\(fm.fileExists(atPath: cnDicts.path))")

    if let items = try? fm.contentsOfDirectory(atPath: cnDicts.path) {
      let sample = Array(items.sorted().prefix(20))
      Logger.statistics.debug("RIME layout \(note): cn_dicts files=\(sample)")
    } else {
      Logger.statistics.debug("RIME layout \(note): cn_dicts list failed")
    }

    let required = rimeIceCoreDicts
    for path in required {
      let full = dst.appendingPathComponent(path).path
      Logger.statistics.debug("RIME layout \(note): exists \(path)=\(fm.fileExists(atPath: full))")
    }
  }

  /// 删除目录下符合正则规则的文件/文件夹
  static func removeMatchedFiles(in dst: URL, regex: [String]) throws {
    guard !regex.isEmpty else { return }
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: dst, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
    for case let fileURL as URL in enumerator {
      let path = fileURL.path
      let match = !(regex.first(where: { path.isMatch(regex: $0) }) ?? "").isEmpty
      if match {
        try? fm.removeItem(at: fileURL)
      }
    }
  }

  // 初始化 AppGroup 共享目录下 UserData 目录资源（可解压内置方案）
  static func initAppGroupUserDataDirectory(override: Bool = false, unzip: Bool = false) throws {
    try FileManager.createDirectory(
      override: override, dst: appGroupUserDataDirectoryURL
    )

    if unzip {
      let src = appSharedSupportDirectory.appendingPathComponent(HamsterConstants.userDataZipFile)
      // 覆盖解压，不移除现有目录，可保留用户词库
      try FileManager.default.unzipOverwrite(src, dst: appGroupUserDataDirectoryURL)
    }
  }

  // 初始化沙盒目录下 UserData 目录资源
  static func initSandboxUserDataDirectory(override: Bool = false, unzip: Bool = false) throws {
    try FileManager.createDirectory(
      override: override, dst: sandboxUserDataDirectory
    )

    if unzip {
      let src = appSharedSupportDirectory.appendingPathComponent(HamsterConstants.userDataZipFile)

      // 解压缩输入方案zip文件
      try FileManager.default.unzipItem(at: src, to: sandboxUserDataDirectory)
    }
  }

  /// 初始化沙盒目录下 Backup 目录
  static func initSandboxBackupDirectory(override: Bool = false) throws {
    try FileManager.createDirectory(
      override: override, dst: sandboxBackupDirectory
    )
  }

  // 同步 AppGroup 共享目录下SharedSupport目录至沙盒目录
  static func syncAppGroupSharedSupportDirectoryToSandbox(override: Bool = false) throws {
    Logger.statistics.info("rime syncAppGroupSharedSupportDirectory: override \(override)")
    try FileManager.copyDirectory(override: override, src: appGroupSharedSupportDirectoryURL, dst: sandboxSharedSupportDirectory)
  }

  // 同步 AppGroup 共享目录下 UserData 目录至沙盒目录
  static func syncAppGroupUserDataDirectoryToSandbox(override: Bool = false) throws {
    Logger.statistics.info("rime syncAppGroupUserDataDirectory: override \(override)")
    try FileManager.copyDirectory(override: override, src: appGroupUserDataDirectoryURL, dst: sandboxUserDataDirectory)
  }

  // 同步 Sandbox 目录下 SharedSupport 目录至 AppGroup 目录
  static func syncSandboxSharedSupportDirectoryToAppGroup(override: Bool = false) throws {
    Logger.statistics.info("rime syncSandboxSharedSupportDirectoryToApGroup: override \(override)")
    try FileManager.copyDirectory(override: override, src: sandboxSharedSupportDirectory, dst: appGroupSharedSupportDirectoryURL)
  }

  // 同步 Sandbox 目录下 UserData 目录至 AppGroup 目录
  static func syncSandboxUserDataDirectoryToAppGroup(override: Bool = false) throws {
    Logger.statistics.info("rime syncSandboxUserDataDirectoryToApGroup: override \(override)")
    try FileManager.copyDirectory(override: override, src: sandboxUserDataDirectory, dst: appGroupUserDataDirectoryURL)
  }

  /// 拷贝 Sandbox 下 SharedSupport 目录至 AppGroup 下 SharedSupport 目录
  static func copySandboxSharedSupportDirectoryToAppGroup(_ filterRegex: [String] = [], filterMatchBreak: Bool = true) throws {
    Logger.statistics.info("rime copySandboxSharedSupportDirectoryToAppGroupSharedSupportDirectory: fileRegex \(filterRegex)")
    try FileManager.incrementalCopy(src: sandboxSharedSupportDirectory, dst: appGroupSharedSupportDirectoryURL, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak)
  }

  /// 拷贝 Sandbox 下 UserData 目录至 AppGroup 下 UserData 目录
  static func copySandboxUserDataDirectoryToAppGroup(_ filterRegex: [String] = [], filterMatchBreak: Bool = true) throws {
    Logger.statistics.info("rime copySandboxUserDataDirectoryToAppGroupUserDirectory: filterRegex \(filterRegex)")
    try FileManager.incrementalCopy(src: sandboxUserDataDirectory, dst: appGroupUserDataDirectoryURL, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak)
  }

  /// 拷贝 Sandbox 下 SharedSupport 目录至 AppGroup 下 SharedSupport 目录
  static func copySandboxSharedSupportDirectoryToAppleCloud(_ filterRegex: [String] = [], filterMatchBreak: Bool = true) throws {
    Logger.statistics.info("rime copySandboxSharedSupportDirectoryToAppleCloud: fileRegex \(filterRegex)")
    try FileManager.incrementalCopy(src: sandboxSharedSupportDirectory, dst: URL.iCloudSharedSupportURL, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak)
  }

  /// 拷贝 Sandbox 下 UserData 目录至 AppGroup 下 UserData 目录
  static func copySandboxUserDataDirectoryToAppleCloud(_ filterRegex: [String] = [], filterMatchBreak: Bool = true) throws {
    Logger.statistics.info("rime copySandboxUserDataDirectoryToAppleCloud: filterRegex \(filterRegex)")
    try FileManager.incrementalCopy(src: sandboxUserDataDirectory, dst: URL.iCloudUserDataURL, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak)
  }

  /// 拷贝 iCloud 下 SharedSupport 目录至 Sandbox 下 SharedSupport 目录
  static func copyAppleCloudSharedSupportDirectoryToSandbox(_ filterRegex: [String] = []) throws {
    Logger.statistics.info("rime copyAppleCloudSharedSupportDirectoryToSandboxSharedSupportDirectory")
    try FileManager.incrementalCopy(src: URL.iCloudSharedSupportURL, dst: sandboxSharedSupportDirectory, filterRegex: filterRegex)
  }

  /// 拷贝 iCloud 下 UserData 目录至 Sandbox 下 UserData 目录
  static func copyAppleCloudUserDataDirectoryToSandbox(_ filterRegex: [String] = []) throws {
    Logger.statistics.info("rime copyAppleCloudUserDataDirectoryToSandboxUserDirectory:")
    try FileManager.incrementalCopy(src: URL.iCloudUserDataURL, dst: sandboxUserDataDirectory, filterRegex: filterRegex)
  }

  /// 拷贝 iCloud 下 SharedSupport 目录至 AppGroup 下 SharedSupport 目录
  static func copyAppleCloudSharedSupportDirectoryToAppGroup(_ filterRegex: [String] = []) throws {
    Logger.statistics.info("rime copyAppleCloudSharedSupportDirectoryToAppGroupSharedSupportDirectory")
    try FileManager.incrementalCopy(src: URL.iCloudSharedSupportURL, dst: appGroupSharedSupportDirectoryURL, filterRegex: filterRegex)
  }

  /// 拷贝 iCloud 下 UserData 目录至 AppGroup 下 UserData 目录
  static func copyAppleCloudUserDataDirectoryToAppGroup(_ filterRegex: [String] = []) throws {
    Logger.statistics.info("rime copyAppleCloudUserDataDirectoryToAppGroupUserDirectory:")
    try FileManager.incrementalCopy(src: URL.iCloudUserDataURL, dst: appGroupUserDataDirectoryURL, filterRegex: filterRegex)
  }

  /// 拷贝 AppGroup 下 SharedSupport 目录至 iCloud 下 SharedSupport 目录
  static func copyAppGroupSharedSupportDirectoryToAppleCloud(_ filterRegex: [String] = [], filterMatchBreak: Bool = true) throws {
    Logger.statistics.info("rime copyAppGroupSharedSupportDirectoryToAppleCloudSharedSupportDirectory")
    try FileManager.incrementalCopy(src: appGroupSharedSupportDirectoryURL, dst: URL.iCloudSharedSupportURL, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak)
  }

  /// 拷贝 AppGroup 下 UserData 目录至 iCloud 下 UserData 目录
  static func copyAppGroupUserDirectoryToAppleCloud(_ filterRegex: [String] = [], filterMatchBreak: Bool = true) throws {
    Logger.statistics.info("rime copyAppGroupUserDirectoryToAppleCloudUserDataDirectory:")
    try FileManager.incrementalCopy(src: appGroupUserDataDirectoryURL, dst: URL.iCloudUserDataURL, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak)
  }

  /// 拷贝 AppGroup 下 SharedSupport 目录至 sandbox 下 SharedSupport 目录
  static func copyAppGroupSharedSupportDirectoryToSandbox(_ filterRegex: [String] = [], filterMatchBreak: Bool = true, override: Bool = true) throws {
    Logger.statistics.info("rime copyAppGroupSharedSupportDirectoryToAppleCloudSharedSupportDirectory")
    try FileManager.incrementalCopy(src: appGroupSharedSupportDirectoryURL, dst: sandboxSharedSupportDirectory, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak, override: override)
  }

  /// 拷贝 AppGroup 下 UserData 目录至 sandbox 下 UserData 目录
  static func copyAppGroupUserDirectoryToSandbox(_ filterRegex: [String] = [], filterMatchBreak: Bool = true, override: Bool = true) throws {
    Logger.statistics.info("rime copyAppGroupUserDirectoryToAppleCloudUserDataDirectory:")
    try FileManager.incrementalCopy(src: appGroupUserDataDirectoryURL, dst: sandboxUserDataDirectory, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak, override: override)
  }

  /// 拷贝 AppGroup 下词库文件
  static func copyAppGroupUserDict(_ regex: [String] = []) throws {
    // TODO: 将AppGroup下词库文件copy至应用目录
    // 只copy用户词库文件
    // let regex = ["^.*[.]userdb.*$", "^.*[.]txt$"]
    // let regex = ["^.*[.]userdb.*$"]
    try copyAppGroupSharedSupportDirectoryToSandbox(regex, filterMatchBreak: false)
    try copyAppGroupUserDirectoryToSandbox(regex, filterMatchBreak: false)
  }
}

// MARK: storage size helpers

public extension FileManager {
  /// 获取文件占用大小（已分配大小，若不可用则使用文件大小）
  static func allocatedFileSize(_ url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey,
      .totalFileAllocatedSizeKey,
      .fileAllocatedSizeKey,
      .fileSizeKey,
    ]
    guard let values = try? url.resourceValues(forKeys: keys),
          values.isRegularFile == true
    else { return 0 }
    if let size = values.totalFileAllocatedSize {
      return Int64(size)
    }
    if let size = values.fileAllocatedSize {
      return Int64(size)
    }
    if let size = values.fileSize {
      return Int64(size)
    }
    return 0
  }

  /// 获取目录占用大小
  static func directorySize(_ url: URL) -> Int64 {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return 0 }
    if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
       values.isDirectory != true
    {
      return allocatedFileSize(url)
    }

    var total: Int64 = 0
    if let enumerator = fm.enumerator(
      at: url,
      includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
      options: [.skipsHiddenFiles],
      errorHandler: { _, _ in true }
    ) {
      for case let fileURL as URL in enumerator {
        total += allocatedFileSize(fileURL)
      }
    }
    return total
  }

  /// 获取目录中匹配正则的文件占用大小
  static func directorySize(_ url: URL, matching regex: [String]) -> Int64 {
    guard !regex.isEmpty else { return 0 }
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return 0 }
    var total: Int64 = 0
    guard let enumerator = fm.enumerator(
      at: url,
      includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
      options: [.skipsHiddenFiles],
      errorHandler: { _, _ in true }
    ) else { return 0 }

    for case let fileURL as URL in enumerator {
      let path = fileURL.path
      let match = !(regex.first(where: { path.isMatch(regex: $0) }) ?? "").isEmpty
      guard match else { continue }
      total += allocatedFileSize(fileURL)
    }
    return total
  }

  /// 获取目录下最大文件列表
  static func largestFiles(in root: URL, limit: Int = 20) -> [(URL, Int64)] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return [] }
    var results: [(URL, Int64)] = []

    guard let enumerator = fm.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
      options: [.skipsHiddenFiles],
      errorHandler: { _, _ in true }
    ) else { return [] }

    for case let fileURL as URL in enumerator {
      let size = allocatedFileSize(fileURL)
      guard size > 0 else { continue }

      if results.count < limit {
        results.append((fileURL, size))
        results.sort { $0.1 > $1.1 }
      } else if let last = results.last, size > last.1 {
        results.removeLast()
        results.append((fileURL, size))
        results.sort { $0.1 > $1.1 }
      }
    }
    return results
  }

  static func formatByteCount(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
