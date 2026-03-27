//
//  SCTApp.swift
//  SCT
//
//  Created by Neo on 2025/12/18.
//

import SwiftUI
import AppKit
import EmbeddedModuleHostKit
import NanomouseReviewKit

@main
struct SCTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootWindowContentView(usesEmbeddedMenuBarHost: appDelegate.usesEmbeddedMenuBarHost)
        }
        .commands {
            applicationCommands
        }
    }

    @CommandsBuilder
    private var applicationCommands: some Commands {
        CommandGroup(replacing: .newItem) { }
        CommandGroup(replacing: .saveItem) { }
        CommandGroup(replacing: .pasteboard) { }

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
    private var settingsWindow: NSWindow?

    var usesEmbeddedMenuBarHost: Bool {
        embeddedMenuBarHost.isAvailable
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppReviewManager.shared.registerLaunchIfNeeded()
        embeddedMenuBarHost.applicationDidFinishLaunching(notification)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppReviewManager.shared.maybeRequestAutomaticReview()
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
        if usesEmbeddedMenuBarHost == false {
            if let firstWindow = NSApp.windows.first {
                firstWindow.makeKeyAndOrderFront(nil)
            }
            return
        }

        if settingsWindow == nil {
            let controller = NSHostingController(rootView: ContentView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.appTitle
            window.center()
            window.contentViewController = controller
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard window == settingsWindow else { return }
        settingsWindow = nil
    }
}
