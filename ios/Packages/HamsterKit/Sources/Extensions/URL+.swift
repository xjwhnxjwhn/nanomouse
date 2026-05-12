//
//  File.swift
//
//
//  Created by morse on 2023/7/4.
//

import Foundation
import os
import Yams

public extension URL {
  /// 获取制定URL下文件或目录URL
  func getFilesAndDirectories() -> [URL] {
    do {
      return try FileManager.default.contentsOfDirectory(
        at: self,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
      )
    } catch {
      Logger.statistics.error("Error getting files and directories - \(error.localizedDescription)")
      return []
    }
  }

  /// 获取指定URL路径下 .schema.yaml 文件URL
//  func getSchemesFile() -> [URL] {
//    getFilesAndDirectories()
//      .filter { $0.lastPathComponent.hasSuffix(".schema.yaml") }
//  }

  /// 获取指定URL的文件内容
  func getStringFromFile() -> String? {
    guard let data = FileManager.default.contents(atPath: path) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// 获取 RIME 同步路径位置
  func getSyncPath() -> String? {
    guard let yamlContent = getStringFromFile() else { return nil }
    do {
      if let yamlFileContent = try Yams.load(yaml: yamlContent) as? [String: Any] {
        return yamlFileContent["sync_dir"] as? String
      }
    } catch {
      Logger.statistics.error("yaml load error \(error.localizedDescription), url:\(self.path)")
    }
    return nil
  }
}

// MARK: iCloud 相关地址

public extension URL {
  private static var iCloudDocumentURLOrFallback: URL {
    if let iCloudDocumentURL {
      return iCloudDocumentURL
    }
    return FileManager.sandboxDirectory
  }

  // 应用iCloud文件夹
  // 注意：appendingPathComponent("Documents")是非常重要的一点，如果没有它，你的文件夹将不会显示在iCloud Drive里面。
  static var iCloudDocumentURL: URL? {
    let fm = FileManager.default
    if let icloudURL = fm.url(forUbiquityContainerIdentifier: HamsterConstants.iCloudID) ?? fm.url(forUbiquityContainerIdentifier: nil) {
      return icloudURL.appendingPathComponent("Documents")
    }
    return nil
  }

  static func requireICloudDocumentURL() throws -> URL {
    guard let url = iCloudDocumentURL else {
      throw StringError("iCloud 不可用：请确认已登录 iCloud、已开启 iCloud Drive，并允许 NanoMouse 使用 iCloud。")
    }
    return url
  }

  // iCloud 中 Rime 使用文件路径
  // 兼容目录命名差异：优先 Rime，其次旧版 RIME。
  static var iCloudRimeURL: URL {
    let root = iCloudDocumentURLOrFallback
    let preferred = root.appendingPathComponent(HamsterConstants.rimeUserPathName, isDirectory: true) // Rime
    let legacy = root.appendingPathComponent("RIME", isDirectory: true)
    let fm = FileManager.default
    if fm.fileExists(atPath: preferred.path) {
      return preferred
    }
    if fm.fileExists(atPath: legacy.path) {
      return legacy
    }
    return preferred
  }

  // iCloud中 RIME sharedSupport 路径
  static var iCloudSharedSupportURL: URL {
    iCloudRimeURL.appendingPathComponent(HamsterConstants.rimeSharedSupportPathName)
  }

  // iCloud中 RIME 方案 userData 路径
  static var iCloudUserDataURL: URL {
    iCloudRimeURL.appendingPathComponent(HamsterConstants.rimeUserPathName)
  }

  // iCloud 中 RIME 方案同步路径
  static var iCloudRimeSyncURL: URL {
    iCloudRimeURL.appendingPathComponent("sync")
  }

  // iCloud 中 软件备份路径
  static var iCloudBackupsURL: URL {
    iCloudDocumentURLOrFallback.appendingPathComponent("backups", isDirectory: true)
  }
}
