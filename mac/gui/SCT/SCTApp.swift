//
//  SCTApp.swift
//  SCT
//
//  Created by Neo on 2025/12/18.
//

import SwiftUI
import AppKit
import CloudKit
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
            if usesEmbeddedMenuBarHost && !MacScreenshotMode.isEnabled {
                EmbeddedMenuBarPlaceholderView()
            } else {
                ContentView()
            }
        }
        .preferredColorScheme(MacScreenshotMode.theme?.colorScheme)
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
    private var screenshotWindow: NSWindow?

    var usesEmbeddedMenuBarHost: Bool {
        embeddedMenuBarHost.isAvailable
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if MacScreenshotMode.isEnabled {
            openScreenshotWindow()
            return
        }

        if !MacScreenshotMode.isEnabled {
            AppReviewManager.shared.registerLaunchIfNeeded()
            embeddedMenuBarHost.applicationDidFinishLaunching(notification)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !MacScreenshotMode.isEnabled {
            AppReviewManager.shared.maybeRequestAutomaticReview()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        embeddedMenuBarHost.applicationWillTerminate(notification)
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("🧭 [PushDebug] SCTApp didRegister tokenLength=\(deviceToken.count)")
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
        let subscriptionID = CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID ?? "nil"
        print("🧭 [PushDebug] SCTApp didReceive subscriptionID=\(subscriptionID)")
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

    private func openScreenshotWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        _ = embeddedMenuBarHost.isAvailable

        if screenshotWindow == nil {
            let scenario = MacScreenshotMode.scenario ?? .bytePaste
            let controller = NSHostingController(
                rootView: MacScreenshotWindowRootView(scenario: scenario)
                    .preferredColorScheme(MacScreenshotMode.theme?.colorScheme)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 780),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            window.hasShadow = false
            window.level = .normal
            window.sharingType = .readOnly
            window.setAccessibilityIdentifier("screenshot_window")
            window.setAccessibilityLabel("screenshot_window")
            window.center()
            window.contentViewController = controller
            window.isReleasedWhenClosed = false
            screenshotWindow = window
        }

        screenshotWindow?.makeKeyAndOrderFront(nil)
    }
}

private struct MacScreenshotWindowRootView: View {
    let scenario: MacScreenshotScenario
    @State private var screenshotReady = false

    var body: some View {
        Group {
            if let view = EmbeddedModuleMenuBarHost.makeScreenshotDetailView(scenarioID: scenario.rawValue) {
                view
            } else {
                ContentView(screenshotScenario: scenario)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screenshot_content")
        .overlay(alignment: .topLeading) {
            if screenshotReady {
                MacScreenshotReadyProbeView(identifier: scenario.readyIdentifier)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: scenario.readyDelayNanoseconds)
            screenshotReady = true
        }
    }
}

private struct MacScreenshotReadyProbeView: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSView) {
        view.setAccessibilityElement(true)
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityLabel(identifier)
        view.setAccessibilityRole(.group)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard window == settingsWindow else { return }
        settingsWindow = nil
    }
}
