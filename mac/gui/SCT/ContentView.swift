//
//  ContentView.swift
//  SCT
//
//  Created by Neo on 2025/12/18.
//

import SwiftUI

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

struct ContentView: View {
    @StateObject private var manager = RimeConfigManager()
    @StateObject private var schemaStore = SchemaStore()
    @State private var selection: SidebarItem? = .schemes
    @Environment(\.undoManager) var undoManager

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.icon)
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
            if !manager.hasAccess {
                AccessRequestView(manager: manager)
            }
        }
        .overlay(alignment: .bottomLeading) {
            StatusBarView(status: manager.statusMessage)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .task {
            manager.undoManager = undoManager
            manager.reload()
            schemaStore.loadSchema()
        }
        .onChange(of: undoManager) { _, newValue in
            manager.undoManager = newValue
        }
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
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
