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

public struct EmbeddedMainModuleHostSlotSummary {
    public let index: Int
    public let isLocked: Bool
    public let previewText: String
    public let previewSymbolName: String?
    public let isEmpty: Bool

    public init(index: Int, isLocked: Bool, previewText: String, previewSymbolName: String?, isEmpty: Bool) {
        self.index = index
        self.isLocked = isLocked
        self.previewText = previewText
        self.previewSymbolName = previewSymbolName
        self.isEmpty = isEmpty
    }
}

public struct EmbeddedMainModuleHostSlotImageImportPayload {
    public let data: Data
    public let preferredFilename: String

    public init(data: Data, preferredFilename: String) {
        self.data = data
        self.preferredFilename = preferredFilename
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

    public static func handleRemoteNotification(
        userInfo: [AnyHashable: Any]
    ) async {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        await EmbeddedMainModuleBridge.handleRemoteNotification(userInfo: userInfo)
        #else
        _ = userInfo
        #endif
    }

    @MainActor
    public static func fetchSlotSummaries() -> [EmbeddedMainModuleHostSlotSummary] {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        return EmbeddedMainModuleBridge.fetchSlotSummaries().map { summary in
            EmbeddedMainModuleHostSlotSummary(
                index: summary.index,
                isLocked: summary.isLocked,
                previewText: summary.previewText,
                previewSymbolName: summary.previewSymbolName,
                isEmpty: summary.isEmpty
            )
        }
        #else
        return []
        #endif
    }

    @MainActor
    public static func makeImageSlotImportViewController(
        slotIndex: Int,
        payload: EmbeddedMainModuleHostSlotImageImportPayload,
        onFinish: (() -> Void)? = nil
    ) -> UIViewController? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        return EmbeddedMainModuleBridge.makeImageSlotImportViewController(
            slotIndex: slotIndex,
            payload: EmbeddedMainSlotImageImportPayload(
                data: payload.data,
                preferredFilename: payload.preferredFilename
            ),
            onFinish: onFinish
        )
        #else
        _ = slotIndex
        _ = payload
        _ = onFinish
        return nil
        #endif
    }

    @MainActor
    public static func makeFileSlotImportViewController(
        slotIndex: Int,
        fileURLs: [URL],
        onFinish: (() -> Void)? = nil
    ) -> UIViewController? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        return EmbeddedMainModuleBridge.makeFileSlotImportViewController(
            slotIndex: slotIndex,
            fileURLs: fileURLs,
            onFinish: onFinish
        )
        #else
        _ = slotIndex
        _ = fileURLs
        _ = onFinish
        return nil
        #endif
    }

    @MainActor
    @discardableResult
    public static func storeImageInSlot(
        slotIndex: Int,
        data: Data,
        preferredFilename: String
    ) -> Bool {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        return EmbeddedMainModuleBridge.storeImageInSlot(
            slotIndex: slotIndex,
            data: data,
            preferredFilename: preferredFilename
        )
        #else
        _ = slotIndex
        _ = data
        _ = preferredFilename
        return false
        #endif
    }

    @MainActor
    @discardableResult
    public static func storeFileInSlot(
        slotIndex: Int,
        data: Data,
        preferredFilename: String,
        uti: String?
    ) -> Bool {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        return EmbeddedMainModuleBridge.storeFileInSlot(
            slotIndex: slotIndex,
            data: data,
            preferredFilename: preferredFilename,
            uti: uti
        )
        #else
        _ = slotIndex
        _ = data
        _ = preferredFilename
        _ = uti
        return false
        #endif
    }

    @MainActor
    @discardableResult
    public static func storePlainTextInSlot(
        slotIndex: Int,
        text: String
    ) -> Bool {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedMainModuleBridge)
        return EmbeddedMainModuleBridge.storePlainTextInSlot(
            slotIndex: slotIndex,
            text: text
        )
        #else
        _ = slotIndex
        _ = text
        return false
        #endif
    }
}
