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
                        .filter { $0.isVisible && $0.identifier != AppDelegate.welcomeWindowIdentifier }
                        .forEach { $0.orderOut(nil) }
                }
            }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static let welcomeWindowIdentifier = NSUserInterfaceItemIdentifier("NanoMouseMacWelcomeWindow")
    private static let welcomeDidShowKey = "NanoMouseMacWelcomeDidShow.v1"

    private lazy var embeddedMenuBarHost = EmbeddedModuleMenuBarHost(
        onOpenSettings: { [weak self] in
            self?.openSettingsWindow()
        }
    )
    private var settingsWindow: NSWindow?
    private var screenshotWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var welcomeWindowCoordinator: NanoMouseMacWelcomeWindowCoordinator?

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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.openWelcomeWindowIfNeeded()
            }
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

    private func openWelcomeWindowIfNeeded() {
        guard usesEmbeddedMenuBarHost, !MacScreenshotMode.isEnabled else { return }
        guard UserDefaults.standard.bool(forKey: Self.welcomeDidShowKey) == false else { return }
        openWelcomeWindow()
    }

    private func openWelcomeWindow() {
        if let welcomeWindow {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            welcomeWindow.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(
            rootView: NanoMouseMacWelcomeView(
                onStart: { [weak self] in
                    self?.finishWelcome()
                },
                onOpenSettings: { [weak self] in
                    self?.finishWelcome(restoreAccessory: false)
                    self?.openSettingsWindow()
                }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = Self.welcomeWindowIdentifier
        window.title = "欢迎使用鼠输入法"
        window.center()
        window.contentViewController = controller
        window.isReleasedWhenClosed = false

        let coordinator = NanoMouseMacWelcomeWindowCoordinator { [weak self] in
            self?.markWelcomeShown()
            self?.welcomeWindow = nil
            self?.welcomeWindowCoordinator = nil
            self?.restoreAccessoryActivationIfNeeded()
        }
        window.delegate = coordinator
        welcomeWindowCoordinator = coordinator
        welcomeWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finishWelcome(restoreAccessory: Bool = true) {
        markWelcomeShown()
        welcomeWindow?.close()
        if restoreAccessory {
            restoreAccessoryActivationIfNeeded()
        }
    }

    private func markWelcomeShown() {
        UserDefaults.standard.set(true, forKey: Self.welcomeDidShowKey)
    }

    private func restoreAccessoryActivationIfNeeded() {
        guard usesEmbeddedMenuBarHost, settingsWindow == nil, welcomeWindow == nil else { return }
        NSApp.setActivationPolicy(.accessory)
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
                contentRect: NSRect(origin: .zero, size: scenario.windowSize),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .clear
            window.isOpaque = false
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
        .background(Color.clear)
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
        restoreAccessoryActivationIfNeeded()
    }
}

private final class NanoMouseMacWelcomeWindowCoordinator: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct NanoMouseMacWelcomeView: View {
    let onStart: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    WelcomePill(icon: "menubar.rectangle", title: "常驻菜单栏", detail: "启动后不会一直占用 Dock 窗口，请看屏幕右上角的鼠图标。")
                    WelcomePill(icon: "keyboard", title: "快捷键呼出", detail: "默认按 ⌥ Space 打开或隐藏字节粘贴，可在设置中修改。")
                }

                VStack(spacing: 12) {
                    WelcomeFeatureRow(
                        icon: "square.grid.3x3.fill",
                        title: "字节粘贴格子",
                        detail: "保存常用文本、富文本、图片、PDF、文件和链接，点击或回车快速粘贴。"
                    )
                    WelcomeFeatureRow(
                        icon: "paintbrush.pointed.fill",
                        title: "画布、Markdown、因果图",
                        detail: "在同一个菜单栏窗口中手绘、写 Markdown、整理因果图，并可保存到文件系统。"
                    )
                    WelcomeFeatureRow(
                        icon: "icloud.fill",
                        title: "跨设备同步",
                        detail: "iPhone、iPad、Mac 与键盘扩展可以通过 iCloud 同步格子与文件。"
                    )
                    WelcomeFeatureRow(
                        icon: "command",
                        title: "两种入口",
                        detail: "点击菜单栏鼠图标打开；右键菜单可进入设置、帮助和其他管理功能。"
                    )
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 24)
            .padding(.bottom, 22)

            HStack(spacing: 12) {
                Button("打开设置") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("我知道了，开始使用") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 22)
            .background(.thinMaterial)
        }
        .frame(width: 760, height: 560)
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.20, blue: 0.19),
                    Color(red: 0.30, green: 0.41, blue: 0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(alignment: .center, spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("欢迎使用鼠输入法")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("这是一个菜单栏常驻工具。首次打开后，主窗口会自动收起，不是闪退。")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                }

                Spacer()

                VStack(spacing: 6) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 28, weight: .semibold))
                    Text("看右上角菜单栏")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
        }
        .frame(height: 190)
    }
}

private struct WelcomePill: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
