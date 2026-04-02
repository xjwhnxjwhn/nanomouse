import SwiftUI
import MarkdownUI
import NanomouseReviewKit
import EmbeddedModuleHostKit

struct HelpView: View {
    @ObservedObject var manager: RimeConfigManager
    @State private var helpContent: String = L10n.loadingHelp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Markdown(helpContent)
                    .markdownTheme(.docC)
                    .textSelection(.enabled)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Button(action: {
                        manager.withSecurityScopedAccess {
                            NSWorkspace.shared.activateFileViewerSelecting([manager.rimePath])
                        }
                    }) {
                        Label(L10n.showInFinder, systemImage: "folder")
                    }
                    .buttonStyle(.link)

                    VStack(alignment: .leading, spacing: 6) {
                        if manager.hasSharedSupportAccess {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text(L10n.sharedSupportAccessGranted)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(manager.sharedSupportPath.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Button(action: {
                                manager.requestSharedSupportAccess()
                            }) {
                                Label(L10n.sharedSupportAccessButton, systemImage: "lock.open")
                            }
                            .buttonStyle(.link)
                            Text(L10n.sharedSupportAccessDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    aboutSection
                }
            }
            .padding(16)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .navigationTitle(L10n.help)
        .onAppear {
            loadHelpContent()
        }
    }

    private func loadHelpContent() {
        guard let url = Bundle.main.url(forResource: "Help", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Fallback if file not in bundle (e.g. during development if not added to target)
            if let devUrl = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("SCT/Help.md") as URL?,
               let devContent = try? String(contentsOf: devUrl, encoding: .utf8) {
                helpContent = devContent
                return
            }
            helpContent = L10n.helpLoadError
            return
        }
        helpContent = content
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            HStack(alignment: .top, spacing: 20) {
                quickCopyAboutColumn

                sctAboutColumn
            }
        }
        .padding(.top, 20)
    }

    private var quickCopyAboutColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("字节粘贴关于")
                        .font(.headline)
                    Text("此区域直接映射“字节粘贴偏好设置 -> 关于”的内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(EmbeddedModuleMenuBarHost.defaultAboutSections()) { section in
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            embeddedAboutRow(item)

                            if index < section.items.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(section.title, systemImage: section.iconSystemName)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var sctAboutColumn: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("项目")
                    Spacer()
                    Text("Squirrel Configuration Tool (SCT)")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Text("版本")
                    Spacer()
                    Text(currentBundleVersionText)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button {
                    if let url = URL(string: "https://github.com/neolee/sct") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("上游仓库", systemImage: "link")
                        Spacer()
                        Text("github.com/neolee/sct")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Divider()

                Button {
                    if let url = URL(string: "https://github.com/rime/squirrel") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("鼠须管项目", systemImage: "link")
                        Spacer()
                        Text("github.com/rime/squirrel")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Divider()

                Button(L10n.resetAccess) {
                    manager.resetAccess()
                }
                .buttonStyle(.link)
                .foregroundStyle(.red)

                Button(L10n.sharedSupportResetButton) {
                    manager.resetSharedSupportAccess()
                }
                .buttonStyle(.link)
                .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("SCT 原项目信息", systemImage: "square.stack.3d.up")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func embeddedAboutRow(_ item: EmbeddedModuleAboutItemDescriptor) -> some View {
        switch item.displayStyle {
        case .value:
            HStack {
                Text(item.title)
                Spacer()
                if let detail = item.detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
        case .action:
            Button {
                handleEmbeddedAboutAction(item.action)
            } label: {
                HStack {
                    if let systemImage = item.systemImage {
                        Label(item.title, systemImage: systemImage)
                    } else {
                        Text(item.title)
                    }

                    Spacer()

                    if let detail = item.detail {
                        Text(detail)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.systemImage == nil ? Color.primary : Color.blue)
        }
    }

    private func handleEmbeddedAboutAction(_ action: EmbeddedModuleAboutAction?) {
        guard let action else { return }

        switch action {
        case .openURL(let urlString):
            guard let url = URL(string: urlString) else { return }
            NSWorkspace.shared.open(url)
        case .copy(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        case .rateApp:
            AppReviewManager.shared.requestManualReview()
        }
    }

    private var currentBundleVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if shortVersion.isEmpty {
            return buildVersion
        }
        if buildVersion.isEmpty {
            return shortVersion
        }
        return "\(shortVersion)(\(buildVersion))"
    }
}

extension String {
    var expandingTildeWithFileManager: String {
        return (self as NSString).expandingTildeInPath
    }
}

#Preview {
    HelpView(manager: RimeConfigManager())
}
