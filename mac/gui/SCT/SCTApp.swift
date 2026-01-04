//
//  SCTApp.swift
//  SCT
//
//  Created by Neo on 2025/12/18.
//

import SwiftUI

@main
struct SCTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterViewModel = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Remove unnecessary menu items
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
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
