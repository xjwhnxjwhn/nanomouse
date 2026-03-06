//
//  EmbeddedModuleHost.swift
//  SCT
//
//  Created by Codex on 2026/2/28.
//

import Foundation
import SwiftUI
#if canImport(EmbeddedMacModuleBridge)
import EmbeddedMacModuleBridge
#endif

/// mac 端私有模块侧边栏入口描述。
struct EmbeddedModuleSidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let iconSystemName: String
}

/// 私有 SPM 模块在 mac 端接入协议。
/// 模块只需要注册入口和详情页视图，主应用无需复制模块源码。
protocol EmbeddedModuleProvider: AnyObject {
    var moduleIdentifier: String { get }
    func sidebarItem() -> EmbeddedModuleSidebarItem?
    func makeDetailView() -> AnyView
}

/// mac 端私有模块注册表。
final class EmbeddedModuleRegistry: ObservableObject {
    static let shared = EmbeddedModuleRegistry()

    @Published private(set) var providers: [EmbeddedModuleProvider] = []
    private var didRegisterDefaultPrivateProviders = false

    private init() {}

    func register(provider: EmbeddedModuleProvider) {
        providers.removeAll(where: { $0.moduleIdentifier == provider.moduleIdentifier })
        providers.append(provider)
    }

    func unregister(moduleIdentifier: String) {
        providers.removeAll(where: { $0.moduleIdentifier == moduleIdentifier })
    }

    func removeAllProviders() {
        providers.removeAll()
    }

    func sidebarItems() -> [EmbeddedModuleSidebarItem] {
        providers.compactMap { $0.sidebarItem() }
    }

    func detailView(moduleIdentifier: String) -> AnyView? {
        providers.first(where: { $0.moduleIdentifier == moduleIdentifier })?.makeDetailView()
    }
}

extension EmbeddedModuleRegistry {
    func registerDefaultPrivateProvidersIfNeeded() {
        guard didRegisterDefaultPrivateProviders == false else { return }
        didRegisterDefaultPrivateProviders = true

        #if canImport(EmbeddedMacModuleBridge)
        if let runtimeConfiguration = EmbeddedMacRuntimeConfigurationProvider.resolve() {
            EmbeddedMacModuleBridge.configure(runtimeConfiguration)
        }
        register(provider: EmbeddedMacRegistryAdapter())
        #endif
    }
}

#if canImport(EmbeddedMacModuleBridge)
private enum EmbeddedMacRuntimeConfigurationProvider {
    private static let appGroupInfoKey = "EMBEDDED_APP_GROUP_IDENTIFIER"
    private static let cloudKitInfoKey = "EMBEDDED_CLOUDKIT_CONTAINER_IDENTIFIER"

    static func resolve() -> EmbeddedMacRuntimeConfiguration? {
        let infoDictionary = Bundle.main.infoDictionary
        guard
            let appGroupIdentifier = sanitizedString(infoDictionary?[appGroupInfoKey] as? String),
            let cloudKitContainerIdentifier = sanitizedString(infoDictionary?[cloudKitInfoKey] as? String)
        else {
            return nil
        }

        return EmbeddedMacRuntimeConfiguration(
            appGroupIdentifier: appGroupIdentifier,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )
    }

    private static func sanitizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif

#if canImport(EmbeddedMacModuleBridge)
private final class EmbeddedMacRegistryAdapter: EmbeddedModuleProvider {
    let moduleIdentifier: String
    private let descriptor: EmbeddedMacSidebarItem

    init() {
        let descriptor = EmbeddedMacModuleBridge.defaultSidebarItem()
        self.descriptor = descriptor
        self.moduleIdentifier = descriptor.moduleIdentifier
    }

    func sidebarItem() -> EmbeddedModuleSidebarItem? {
        EmbeddedModuleSidebarItem(
            id: descriptor.moduleIdentifier,
            title: descriptor.title,
            iconSystemName: descriptor.iconSystemName
        )
    }

    func makeDetailView() -> AnyView {
        EmbeddedMacModuleBridge.makeDetailView()
    }
}
#endif
