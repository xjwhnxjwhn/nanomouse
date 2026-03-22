//
//  EmbeddedModuleHost.swift
//  SCT
//
//  Created by Codex on 2026/2/28.
//

import Foundation
import SwiftUI
import EmbeddedModuleHostKit

/// mac 端私有模块侧边栏入口描述。
struct EmbeddedModuleSidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let iconSystemName: String
}

/// 私有 SPM 模块在 mac 端接入协议。
/// 模块只需要注册入口和详情页视图，主应用无需复制模块源码。
@MainActor
protocol EmbeddedModuleProvider: AnyObject {
    var moduleIdentifier: String { get }
    func sidebarItem() -> EmbeddedModuleSidebarItem?
    func makeDetailView() -> AnyView
}

/// mac 端私有模块注册表。
@MainActor
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

        guard EmbeddedModuleMenuBarHost.isEmbeddedModuleAvailable else { return }
        register(provider: EmbeddedMacRegistryAdapter())
    }
}

@MainActor
private final class EmbeddedMacRegistryAdapter: EmbeddedModuleProvider {
    let moduleIdentifier: String
    private let title: String
    private let iconSystemName: String

    init() {
        let descriptor = EmbeddedModuleMenuBarHost.defaultSidebarDescriptor()!
        self.moduleIdentifier = descriptor.moduleIdentifier
        self.title = descriptor.title
        self.iconSystemName = descriptor.iconSystemName
    }

    func sidebarItem() -> EmbeddedModuleSidebarItem? {
        EmbeddedModuleSidebarItem(
            id: moduleIdentifier,
            title: title,
            iconSystemName: iconSystemName
        )
    }

    func makeDetailView() -> AnyView {
        EmbeddedModuleMenuBarHost.makeDetailView()!
    }
}
