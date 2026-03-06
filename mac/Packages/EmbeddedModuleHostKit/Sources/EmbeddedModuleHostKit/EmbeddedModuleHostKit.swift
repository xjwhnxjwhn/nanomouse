import AppKit
import Foundation

#if canImport(EmbeddedMacModuleBridge)
import EmbeddedMacModuleBridge
#endif

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
        bridgeDelegate?.application(application, didReceiveRemoteNotification: userInfo)
        #else
        _ = application
        _ = userInfo
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
