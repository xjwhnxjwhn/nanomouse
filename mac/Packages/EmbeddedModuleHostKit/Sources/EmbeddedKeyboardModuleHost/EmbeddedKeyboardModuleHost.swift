import Foundation
import UIKit

#if canImport(EmbeddedKeyboardModuleBridge)
import EmbeddedKeyboardModuleBridge
#endif

public struct EmbeddedKeyboardModuleHostEntryDescriptor {
    public let moduleIdentifier: String
    public let iconSystemName: String
    public let accessibilityLabel: String

    public init(
        moduleIdentifier: String,
        iconSystemName: String,
        accessibilityLabel: String
    ) {
        self.moduleIdentifier = moduleIdentifier
        self.iconSystemName = iconSystemName
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum EmbeddedKeyboardModuleHost {
    public static var isAvailable: Bool {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedKeyboardModuleBridge)
        true
        #else
        false
        #endif
    }

    public static func configure(
        appGroupIdentifier: String,
        cloudKitContainerIdentifier: String
    ) {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedKeyboardModuleBridge)
        EmbeddedKeyboardModuleBridge.configure(
            EmbeddedKeyboardRuntimeConfiguration(
                appGroupIdentifier: appGroupIdentifier,
                cloudKitContainerIdentifier: cloudKitContainerIdentifier
            )
        )
        #else
        _ = appGroupIdentifier
        _ = cloudKitContainerIdentifier
        #endif
    }

    public static func defaultEntryDescriptor() -> EmbeddedKeyboardModuleHostEntryDescriptor? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedKeyboardModuleBridge)
        let descriptor = EmbeddedKeyboardModuleBridge.defaultEntryDescriptor()
        return EmbeddedKeyboardModuleHostEntryDescriptor(
            moduleIdentifier: descriptor.moduleIdentifier,
            iconSystemName: descriptor.iconSystemName,
            accessibilityLabel: descriptor.accessibilityLabel
        )
        #else
        return nil
        #endif
    }

    public static func makeInlineViewController(
        hostInputViewController: UIInputViewController,
        onRequestClose: (() -> Void)? = nil
    ) -> UIViewController? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedKeyboardModuleBridge)
        EmbeddedKeyboardModuleBridge.makeInlineViewController(
            hostInputViewController: hostInputViewController,
            onRequestClose: onRequestClose
        )
        #else
        _ = hostInputViewController
        _ = onRequestClose
        return nil
        #endif
    }

    public static func makeLaunchURL() -> URL? {
        #if EMBEDDED_MODULE_BRIDGE_ENABLED && canImport(EmbeddedKeyboardModuleBridge)
        EmbeddedKeyboardModuleBridge.makeLaunchURL()
        #else
        return nil
        #endif
    }
}
