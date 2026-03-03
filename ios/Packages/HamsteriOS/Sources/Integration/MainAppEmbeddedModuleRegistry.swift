//
//  MainAppEmbeddedModuleRegistry.swift
//
//
//  Created by Codex on 2026/2/28.
//

import UIKit
import HamsterKit

/// 私有 SPM 模块在主 App 中挂载为独立 Tab 的描述。
public struct MainAppEmbeddedTabDescriptor {
  public let moduleIdentifier: String
  public let title: String
  public let iconSystemName: String
  public let selectedIconSystemName: String?
  public let hidesNavigationBar: Bool
  public let prefersLargeTitles: Bool
  public let makeRootViewController: () -> UIViewController

  public init(
    moduleIdentifier: String,
    title: String,
    iconSystemName: String,
    selectedIconSystemName: String? = nil,
    hidesNavigationBar: Bool = false,
    prefersLargeTitles: Bool = true,
    makeRootViewController: @escaping () -> UIViewController
  ) {
    self.moduleIdentifier = moduleIdentifier
    self.title = title
    self.iconSystemName = iconSystemName
    self.selectedIconSystemName = selectedIconSystemName
    self.hidesNavigationBar = hidesNavigationBar
    self.prefersLargeTitles = prefersLargeTitles
    self.makeRootViewController = makeRootViewController
  }
}

/// 私有 SPM 模块接入协议：
/// - 提供可选 Tab
/// - 处理模块专用 deep link
public protocol MainAppEmbeddedModuleProvider: AnyObject {
  var moduleIdentifier: String { get }
  func makeEmbeddedTab() -> MainAppEmbeddedTabDescriptor?
  func handleOpenURL(_ url: URL, activateTab: (String) -> Void) -> Bool
}

/// 主 App 私有模块注册表。
/// 外部私有 SPM 只需要实现协议并在启动时注册即可，不需要把源码并入 nanomouse。
public final class MainAppEmbeddedModuleRegistry {
  public static let shared = MainAppEmbeddedModuleRegistry()

  private var providers: [MainAppEmbeddedModuleProvider] = []

  private init() {}

  public func register(provider: MainAppEmbeddedModuleProvider) {
    providers.removeAll(where: { $0.moduleIdentifier == provider.moduleIdentifier })
    providers.append(provider)
  }

  public func unregister(moduleIdentifier: String) {
    providers.removeAll(where: { $0.moduleIdentifier == moduleIdentifier })
  }

  public func removeAllProviders() {
    providers.removeAll()
  }

  public func makeEmbeddedTabs() -> [MainAppEmbeddedTabDescriptor] {
    providers.compactMap { $0.makeEmbeddedTab() }
  }

  public func handleOpenURL(_ url: URL, activateTab: (String) -> Void) -> Bool {
    for provider in providers where provider.handleOpenURL(url, activateTab: activateTab) {
      return true
    }
    return false
  }
}

extension MainAppEmbeddedModuleRegistry {
  public func registerDefaultPrivateProvidersIfNeeded() {
    // 公共仓库默认不注册任何私有模块，私有侧可通过协议自行注入。
  }
}
