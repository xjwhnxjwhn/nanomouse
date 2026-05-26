import AppKit
import Foundation
import SwiftUI

#if canImport(EmbeddedMacModuleBridge)
import EmbeddedMacModuleBridge
#endif

@inline(__always)
func print(_ message: @autoclosure () -> String, terminator: String = "\n") {
    #if DEBUG
    Swift.print(message(), terminator: terminator)
    #endif
}

@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
    #endif
}

public struct EmbeddedModuleSidebarDescriptor {
    public let moduleIdentifier: String
    public let title: String
    public let iconSystemName: String

    public init(moduleIdentifier: String, title: String, iconSystemName: String) {
        self.moduleIdentifier = moduleIdentifier
        self.title = title
        self.iconSystemName = iconSystemName
    }
}

public enum EmbeddedModuleAboutAction: Hashable {
    case openURL(String)
    case copy(String)
    case rateApp
}

public struct EmbeddedModuleAboutItemDescriptor: Identifiable, Hashable {
    public enum DisplayStyle: Hashable {
        case value
        case action
    }

    public let id: String
    public let title: String
    public let detail: String?
    public let systemImage: String?
    public let displayStyle: DisplayStyle
    public let action: EmbeddedModuleAboutAction?

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        systemImage: String? = nil,
        displayStyle: DisplayStyle = .value,
        action: EmbeddedModuleAboutAction? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.displayStyle = displayStyle
        self.action = action
    }
}

public struct EmbeddedModuleAboutSectionDescriptor: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let iconSystemName: String
    public let items: [EmbeddedModuleAboutItemDescriptor]

    public init(
        id: String,
        title: String,
        iconSystemName: String,
        items: [EmbeddedModuleAboutItemDescriptor]
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.items = items
    }
}

@MainActor
public final class EmbeddedModuleMenuBarHost {
    #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
    private let bridgeDelegate: BridgeDelegate?
    #endif

    public init(onOpenSettings: @escaping @MainActor () -> Void) {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        if let configuration = EmbeddedModuleRuntimeConfigurationProvider.resolve() {
            EmbeddedMacModuleBridge.configure(configuration)
        }
        bridgeDelegate = EmbeddedMacModuleApplicationDelegate(onOpenSettings: {
            Task { @MainActor in
                onOpenSettings()
            }
        })
        #else
        bridgeDelegate = nil
        _ = onOpenSettings
        #endif
    }

    public var isAvailable: Bool {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        bridgeDelegate != nil
        #else
        false
        #endif
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        bridgeDelegate?.applicationDidFinishLaunching(notification)
        #else
        _ = notification
        #endif
    }

    public func applicationWillTerminate(_ notification: Notification) {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        bridgeDelegate?.applicationWillTerminate(notification)
        #else
        _ = notification
        #endif
    }

    public func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        print("🧭 [PushDebug] EmbeddedModuleHostKit forward didRegister tokenLength=\(deviceToken.count)")
        bridgeDelegate?.application(
            application,
            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
        )
        #else
        _ = application
        _ = deviceToken
        #endif
    }

    public func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        bridgeDelegate?.application(
            application,
            didFailToRegisterForRemoteNotificationsWithError: error
        )
        #else
        _ = application
        _ = error
        #endif
    }

    public func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        print("🧭 [PushDebug] EmbeddedModuleHostKit forward didReceive")
        bridgeDelegate?.application(application, didReceiveRemoteNotification: userInfo)
        #else
        _ = application
        _ = userInfo
        #endif
    }

    public static var isEmbeddedModuleAvailable: Bool {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        true
        #else
        false
        #endif
    }

    public static func defaultSidebarDescriptor() -> EmbeddedModuleSidebarDescriptor? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        let descriptor = EmbeddedMacModuleBridge.defaultSidebarItem()
        return EmbeddedModuleSidebarDescriptor(
            moduleIdentifier: descriptor.moduleIdentifier,
            title: descriptor.title,
            iconSystemName: descriptor.iconSystemName
        )
        #else
        return nil
        #endif
    }

    public static func makeDetailView() -> AnyView? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        return EmbeddedMacModuleBridge.makeDetailView()
        #else
        return nil
        #endif
    }

    public static func makeScreenshotDetailView(scenarioID: String) -> AnyView? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        return EmbeddedMacModuleBridge.makeScreenshotDetailView(scenarioID: scenarioID)
        #else
        _ = scenarioID
        return nil
        #endif
    }

    public static func defaultAboutSections() -> [EmbeddedModuleAboutSectionDescriptor] {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
        return EmbeddedMacModuleBridge.defaultAboutSections().map { section in
            EmbeddedModuleAboutSectionDescriptor(
                id: section.id,
                title: section.title,
                iconSystemName: section.iconSystemName,
                items: section.items.map { item in
                    EmbeddedModuleAboutItemDescriptor(
                        id: item.id,
                        title: item.title,
                        detail: item.detail,
                        systemImage: item.systemImage,
                        displayStyle: item.displayStyle == .value ? .value : .action,
                        action: mapAboutAction(item.action)
                    )
                }
            )
        }
        #else
        return []
        #endif
    }
}

#if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
private typealias BridgeDelegate = EmbeddedMacModuleApplicationDelegate

private enum EmbeddedModuleRuntimeConfigurationProvider {
    static func resolve() -> EmbeddedMacRuntimeConfiguration? {
        guard let baseIdentifier = resolveBaseBundleIdentifier() else { return nil }

        return EmbeddedMacRuntimeConfiguration(
            appGroupIdentifier: "group.\(baseIdentifier)",
            cloudKitContainerIdentifier: "iCloud.\(baseIdentifier)"
        )
    }

    private static func resolveBaseBundleIdentifier() -> String? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              bundleIdentifier.isEmpty == false
        else {
            return nil
        }

        if bundleIdentifier.hasSuffix(".mac") {
            return String(bundleIdentifier.dropLast(4))
        }

        return bundleIdentifier
    }
}
#else
private typealias BridgeDelegate = NSObject
#endif

#if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMacModuleBridge)
private func mapAboutAction(_ action: EmbeddedMacAboutAction?) -> EmbeddedModuleAboutAction? {
    guard let action else { return nil }

    switch action {
    case .openURL(let urlString):
        return .openURL(urlString)
    case .copy(let value):
        return .copy(value)
    case .rateApp:
        return .rateApp
    }
}
#endif
