import Foundation
import UIKit

#if canImport(EmbeddedMainModuleBridge)
import EmbeddedMainModuleBridge
#endif

public struct EmbeddedMainModuleHostTabDescriptor {
    public let moduleIdentifier: String
    public let title: String
    public let iconSystemName: String
    public let selectedIconSystemName: String?
    public let hidesNavigationBar: Bool
    public let prefersLargeTitles: Bool

    public init(
        moduleIdentifier: String,
        title: String,
        iconSystemName: String,
        selectedIconSystemName: String? = nil,
        hidesNavigationBar: Bool = false,
        prefersLargeTitles: Bool = true
    ) {
        self.moduleIdentifier = moduleIdentifier
        self.title = title
        self.iconSystemName = iconSystemName
        self.selectedIconSystemName = selectedIconSystemName
        self.hidesNavigationBar = hidesNavigationBar
        self.prefersLargeTitles = prefersLargeTitles
    }
}

public struct EmbeddedMainModuleHostSettingsDescriptor {
    public let moduleIdentifier: String
    public let title: String
    public let iconSystemName: String
    public let prefersLargeTitles: Bool

    public init(
        moduleIdentifier: String,
        title: String,
        iconSystemName: String,
        prefersLargeTitles: Bool = false
    ) {
        self.moduleIdentifier = moduleIdentifier
        self.title = title
        self.iconSystemName = iconSystemName
        self.prefersLargeTitles = prefersLargeTitles
    }
}

public enum EmbeddedMainModuleHost {
    public static var isAvailable: Bool {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        true
        #else
        false
        #endif
    }

    public static func configure(
        appGroupIdentifier: String,
        cloudKitContainerIdentifier: String
    ) {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        EmbeddedMainModuleBridge.configure(
            EmbeddedMainRuntimeConfiguration(
                appGroupIdentifier: appGroupIdentifier,
                cloudKitContainerIdentifier: cloudKitContainerIdentifier
            )
        )
        #else
        _ = appGroupIdentifier
        _ = cloudKitContainerIdentifier
        #endif
    }

    public static func defaultTabDescriptor() -> EmbeddedMainModuleHostTabDescriptor? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        let descriptor = EmbeddedMainModuleBridge.defaultTabDescriptor()
        return EmbeddedMainModuleHostTabDescriptor(
            moduleIdentifier: descriptor.moduleIdentifier,
            title: descriptor.title,
            iconSystemName: descriptor.iconSystemName,
            selectedIconSystemName: descriptor.selectedIconSystemName,
            hidesNavigationBar: descriptor.hidesNavigationBar,
            prefersLargeTitles: descriptor.prefersLargeTitles
        )
        #else
        return nil
        #endif
    }

    public static func makeRootViewController(
        title: String,
        prefersLargeTitles: Bool
    ) -> UIViewController? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        EmbeddedMainModuleBridge.makeRootViewController(
            title: title,
            prefersLargeTitles: prefersLargeTitles
        )
        #else
        _ = title
        _ = prefersLargeTitles
        return nil
        #endif
    }

    public static func defaultSettingsDescriptor() -> EmbeddedMainModuleHostSettingsDescriptor? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        let descriptor = EmbeddedMainModuleBridge.defaultSettingsDescriptor()
        return EmbeddedMainModuleHostSettingsDescriptor(
            moduleIdentifier: descriptor.moduleIdentifier,
            title: descriptor.title,
            iconSystemName: descriptor.iconSystemName,
            prefersLargeTitles: descriptor.prefersLargeTitles
        )
        #else
        return nil
        #endif
    }

    public static func makeSettingsViewController(
        title: String,
        prefersLargeTitles: Bool
    ) -> UIViewController? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        EmbeddedMainModuleBridge.makeSettingsViewController(
            title: title,
            prefersLargeTitles: prefersLargeTitles
        )
        #else
        _ = title
        _ = prefersLargeTitles
        return nil
        #endif
    }

    public static func handleOpenURL(
        _ url: URL,
        activateTab: (String) -> Void
    ) -> Bool {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        EmbeddedMainModuleBridge.handleOpenURL(url, activateTab: activateTab)
        #else
        _ = url
        _ = activateTab
        return false
        #endif
    }
}
