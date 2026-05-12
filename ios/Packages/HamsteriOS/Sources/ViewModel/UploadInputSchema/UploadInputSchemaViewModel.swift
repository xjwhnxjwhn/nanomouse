//
//  UploadInputSchemaViewModel.swift
//  Hamster
//
//  Created by morse on 2023/6/13.
//

import Foundation
import HamsterFileServer
import HamsterKit
import Network
import OSLog
import UIKit

class UploadInputSchemaViewModel {
  private static let serverPort = 8080

  /// 局域网上传根目录（AppGroup/InputSchema）
  /// 说明：这样可直接看到并上传到 Rime 目录，避免用户手工新建目录。
  private let uploadRootDirectory = FileManager.shareURL

  /// 局域网上传的 Rime 用户目录（AppGroup/InputSchema/Rime）
  private let uploadRimeDirectory = FileManager.appGroupUserDataDirectoryURL

  private lazy var fileServer: FileServer = {
    let server = FileServer(
      port: Self.serverPort,
      publicDirectory: uploadRootDirectory
    )
    return server
  }()

  @Published
  public private(set) var fileServerRunning = false

  @Published
  public private(set) var fileServerError: String?

  private var wifiEnable = false

  init() {
    prepareUploadDirectories()
  }
}

extension UploadInputSchemaViewModel {
  /// 确保上传目录结构存在：
  /// - InputSchema/
  /// - InputSchema/Rime/
  private func prepareUploadDirectories() {
    do {
      try FileManager.createDirectory(override: false, dst: uploadRootDirectory)
      try FileManager.createDirectory(override: false, dst: uploadRimeDirectory)
    } catch {
      Logger.statistics.error("prepare upload directories failed: \(error.localizedDescription)")
    }
  }

  func startWiFiMonitor() {
    let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    monitor.pathUpdateHandler = { [unowned self] path in
      if path.status == .satisfied {
        self.wifiEnable = true
        monitor.cancel()
        return
      }
      self.wifiEnable = false
      monitor.cancel()
    }
    monitor.start(queue: .main)
  }

  @objc func managerfileServer() {
    if fileServerRunning {
      Logger.statistics.debug("stop file server")
      self.fileServer.shutdown()
      fileServerRunning = false
    } else {
      Logger.statistics.debug("start file server")
      prepareUploadDirectories()
      guard self.fileServer.start() else {
        fileServerRunning = false
        fileServerError = "启动服务失败，请确认本地网络权限已开启，并稍后重试。"
        return
      }
      fileServerRunning = true
    }
  }

  func stopFileServer() {
    fileServerRunning = false
    self.fileServer.shutdown()
  }

  func localAccessURLString() -> String? {
    guard let ip = UIDevice.current.getAddress() else { return nil }
    return "http://\(ip):\(Self.serverPort)"
  }
}
