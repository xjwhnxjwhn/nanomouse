//
//  KeyboardEmbeddedModuleRegistry.swift
//
//
//  Created by Codex on 2026/2/28.
//

import Foundation
import UIKit
import HamsterKit
import EmbeddedKeyboardModuleHost

/// 私有 SPM 在键盘扩展中的入口描述。
public struct KeyboardEmbeddedModuleEntry {
  public let moduleIdentifier: String
  public let iconSystemName: String
  public let accessibilityLabel: String
  public let makeInlineViewController: ((UIInputViewController) -> UIViewController)?
  public let makeLaunchURL: () -> URL?

  public init(
    moduleIdentifier: String,
    iconSystemName: String,
    accessibilityLabel: String,
    makeInlineViewController: ((UIInputViewController) -> UIViewController)? = nil,
    makeLaunchURL: @escaping () -> URL? = { nil }
  ) {
    self.moduleIdentifier = moduleIdentifier
    self.iconSystemName = iconSystemName
    self.accessibilityLabel = accessibilityLabel
    self.makeInlineViewController = makeInlineViewController
    self.makeLaunchURL = makeLaunchURL
  }
}

public enum KeyboardEmbeddedModuleNotification {
  public static let toggle = Notification.Name("hamsterEmbeddedModuleToggle")
  public static let moduleIdentifierUserInfoKey = "moduleIdentifier"
}

/// 私有模块在键盘扩展中的注册协议。
public protocol KeyboardEmbeddedModuleProvider: AnyObject {
  var moduleIdentifier: String { get }
  func makeKeyboardEntry() -> KeyboardEmbeddedModuleEntry?
}

/// 键盘扩展私有模块注册表。
/// 该结构只负责“接收”模块入口信息，UI 是否展示由上层决定。
public final class KeyboardEmbeddedModuleRegistry {
  public static let shared = KeyboardEmbeddedModuleRegistry()

  private var providers: [KeyboardEmbeddedModuleProvider] = []
  private var didRegisterDefaultPrivateProviders = false

  private init() {}

  public func register(provider: KeyboardEmbeddedModuleProvider) {
    providers.removeAll(where: { $0.moduleIdentifier == provider.moduleIdentifier })
    providers.append(provider)
  }

  public func unregister(moduleIdentifier: String) {
    providers.removeAll(where: { $0.moduleIdentifier == moduleIdentifier })
  }

  public func removeAllProviders() {
    providers.removeAll()
  }

  public func keyboardEntries() -> [KeyboardEmbeddedModuleEntry] {
    providers.compactMap { $0.makeKeyboardEntry() }
  }

  public func keyboardEntry(moduleIdentifier: String) -> KeyboardEmbeddedModuleEntry? {
    keyboardEntries().first(where: { $0.moduleIdentifier == moduleIdentifier })
  }
}

extension KeyboardEmbeddedModuleRegistry {
  public func registerDefaultPrivateProvidersIfNeeded() {
    guard didRegisterDefaultPrivateProviders == false else { return }
    didRegisterDefaultPrivateProviders = true

    guard EmbeddedKeyboardModuleHost.isAvailable else { return }

    EmbeddedKeyboardModuleHost.configure(
      appGroupIdentifier: HamsterConstants.appGroupName,
      cloudKitContainerIdentifier: HamsterConstants.iCloudID
    )
    register(provider: EmbeddedKeyboardRegistryAdapter())
  }
}

private final class EmbeddedKeyboardRegistryAdapter: KeyboardEmbeddedModuleProvider {
  let moduleIdentifier: String

  private let descriptor: EmbeddedKeyboardModuleHostEntryDescriptor

  init() {
    let descriptor = EmbeddedKeyboardModuleHost.defaultEntryDescriptor()!
    self.descriptor = descriptor
    self.moduleIdentifier = descriptor.moduleIdentifier
  }

  func makeKeyboardEntry() -> KeyboardEmbeddedModuleEntry? {
    KeyboardEmbeddedModuleEntry(
      moduleIdentifier: descriptor.moduleIdentifier,
      iconSystemName: descriptor.iconSystemName,
      accessibilityLabel: descriptor.accessibilityLabel,
      makeInlineViewController: { hostInputViewController in
        EmbeddedKeyboardModuleHost.makeInlineViewController(
          hostInputViewController: hostInputViewController,
          onRequestClose: { hostInputViewController.dismissKeyboard() }
        )!
      },
      makeLaunchURL: {
        EmbeddedKeyboardModuleHost.makeLaunchURL()
      }
    )
  }
}
