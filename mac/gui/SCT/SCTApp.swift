//
//  SCTApp.swift
//  SCT
//
//  Created by Neo on 2025/12/18.
//

import SwiftUI
import AppKit
import EmbeddedModuleHostKit

@main
struct SCTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterViewModel = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            RootWindowContentView(usesEmbeddedMenuBarHost: appDelegate.usesEmbeddedMenuBarHost)
        }
        .commands {
            applicationCommands
        }

        Settings {
            SettingsRootContentView(usesEmbeddedMenuBarHost: appDelegate.usesEmbeddedMenuBarHost)
        }
    }

    @CommandsBuilder
    private var applicationCommands: some Commands {
        CommandGroup(replacing: .newItem) { }
        CommandGroup(replacing: .saveItem) { }
        CommandGroup(replacing: .pasteboard) { }

        CommandGroup(after: .appInfo) {
            Button(L10n.checkForUpdates) {
                updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)
        }

        CommandGroup(replacing: .help) {
            Button(L10n.sctWebsite) {
                if let url = URL(string: "https://github.com/xjwhnxjwhn/nanomouse") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(L10n.squirrelWebsite) {
                if let url = URL(string: "https://github.com/rime/squirrel") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

private struct RootWindowContentView: View {
    let usesEmbeddedMenuBarHost: Bool

    var body: some View {
        Group {
            if usesEmbeddedMenuBarHost {
                EmbeddedMenuBarPlaceholderView()
            } else {
                ContentView()
            }
        }
    }
}

private struct SettingsRootContentView: View {
    let usesEmbeddedMenuBarHost: Bool

    var body: some View {
        Group {
            if usesEmbeddedMenuBarHost {
                ContentView()
            } else {
                EmptyView()
            }
        }
    }
}

private struct EmbeddedMenuBarPlaceholderView: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 1, minHeight: 1)
            .onAppear {
                // 菜单栏模式下，主窗口不应在启动时弹出。
                DispatchQueue.main.async {
                    NSApp.windows
                        .filter { $0.isVisible }
                        .forEach { $0.orderOut(nil) }
                }
            }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var embeddedMenuBarHost = EmbeddedModuleMenuBarHost(
        onOpenSettings: { [weak self] in
            self?.openSettingsWindow()
        }
    )

    var usesEmbeddedMenuBarHost: Bool {
        embeddedMenuBarHost.isAvailable
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        embeddedMenuBarHost.applicationDidFinishLaunching(notification)
    }

    func applicationWillTerminate(_ notification: Notification) {
        embeddedMenuBarHost.applicationWillTerminate(notification)
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        embeddedMenuBarHost.application(
            application,
            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
        )
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        embeddedMenuBarHost.application(
            application,
            didFailToRegisterForRemoteNotificationsWithError: error
        )
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        embeddedMenuBarHost.application(application, didReceiveRemoteNotification: userInfo)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        usesEmbeddedMenuBarHost == false
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let didOpenSettings = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        if didOpenSettings == false, let firstWindow = NSApp.windows.first {
            firstWindow.makeKeyAndOrderFront(nil)
        }
    }
}
