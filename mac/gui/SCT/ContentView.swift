//
//  ContentView.swift
//  SCT
//
//  Created by Neo on 2025/12/18.
//

import SwiftUI
import AppKit
import EmbeddedModuleHostKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case nanomouse
    case schemes
    case panel
    case behaviors
    case apps
    case advanced
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nanomouse: return L10n.nanomouse
        case .schemes: return L10n.schemes
        case .panel: return L10n.panel
        case .behaviors: return L10n.behaviors
        case .apps: return L10n.apps
        case .advanced: return L10n.advanced
        case .help: return L10n.help
        }
    }

    var icon: String {
        switch self {
        case .nanomouse: return "sparkles"
        case .schemes: return "list.bullet.indent"
        case .panel: return "list.number"
        case .behaviors: return "keyboard"
        case .apps: return "apps.ipad"
        case .advanced: return "gearshape.2"
        case .help: return "questionmark.circle"
        }
    }

    var sectionIDs: [String]? {
        switch self {
        case .nanomouse: return nil
        case .schemes: return ["schemes.list", "switcher"]
        case .panel: return ["panel.menu", "style"]
        case .behaviors: return ["asciiComposer", "keyBinder"]
        case .apps: return ["appOptions"]
        case .advanced: return nil
        case .help: return nil
        }
    }
}

enum SidebarSelection: Hashable {
    case builtIn(SidebarItem)
    case embedded(String)
}

struct ContentView: View {
    @StateObject private var manager = RimeConfigManager()
    @StateObject private var schemaStore = SchemaStore()
    @StateObject private var embeddedRegistry = EmbeddedModuleRegistry.shared
    @State private var selection: SidebarSelection?
    @State private var screenshotReady = false
    @Environment(\.undoManager) var undoManager
    private let screenshotScenario: MacScreenshotScenario?

    init(screenshotScenario: MacScreenshotScenario? = MacScreenshotMode.scenario) {
        self.screenshotScenario = screenshotScenario
        _selection = State(initialValue: screenshotScenario == nil ? .builtIn(.schemes) : .embedded("clipboard"))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SidebarItem.allCases, id: \.id) { item in
                        NavigationLink(value: SidebarSelection.builtIn(item)) {
                            Label(item.title, systemImage: item.icon)
                        }
                    }
                }

            }
            .listStyle(.sidebar)
            .navigationTitle(L10n.appTitle)
        } detail: {
            if let item = selection {
                detailView(for: item)
            } else {
                Text(L10n.selectItem)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .overlay {
            if !manager.hasAccess && !MacScreenshotMode.isEnabled {
                AccessRequestView(manager: manager)
            }
        }
        .overlay(alignment: .topLeading) {
            if let screenshotScenario, screenshotReady {
                ScreenshotReadyProbeView(identifier: screenshotScenario.readyIdentifier)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            StatusBarView(status: manager.statusMessage)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .task {
            embeddedRegistry.registerDefaultPrivateProvidersIfNeeded()
            manager.undoManager = undoManager
            manager.reload()
            schemaStore.loadSchema()
            if screenshotScenario != nil {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                screenshotReady = true
            }
        }
        .onChange(of: undoManager) { _, newValue in
            manager.undoManager = newValue
        }
    }

    @ViewBuilder
    private func detailView(for selection: SidebarSelection) -> some View {
        switch selection {
        case .embedded(let moduleIdentifier):
            if let screenshotScenario,
               moduleIdentifier == "clipboard",
               let view = EmbeddedModuleMenuBarHost.makeScreenshotDetailView(scenarioID: screenshotScenario.rawValue) {
                view
            } else if let view = embeddedRegistry.detailView(moduleIdentifier: moduleIdentifier) {
                view
            } else {
                Text(L10n.selectItem)
                    .foregroundStyle(.secondary)
            }
        case .builtIn(let item):
            switch item {
            case .nanomouse:
                NanomouseSettingsView(manager: manager)
            case .advanced:
                AdvancedSettingsView(manager: manager)
            case .help:
                HelpView(manager: manager)
            default:
                SchemaDrivenView(schemaStore: schemaStore,
                                 manager: manager,
                                 sectionIDs: item.sectionIDs,
                                 title: item.title)
            }
        }
    }
}

private struct ScreenshotReadyProbeView: NSViewRepresentable {
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

extension View {
    func rimeToolbar(manager: RimeConfigManager) -> some View {
        self.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { manager.deploy() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.deployHelp)
            }
        }
    }
}

struct StatusBarView: View {
    var status: String

    var body: some View {
        Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}

#Preview {
    ContentView()
}
