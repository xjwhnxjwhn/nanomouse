import SwiftUI
import MarkdownUI

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

            HStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.appTitle)
                        .font(.headline)
                    Text(String(format: L10n.version, "1.0.0 (Build 20251219)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(L10n.copyright)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button(L10n.checkUpdates) {
                        if let url = URL(string: "https://github.com/xjwhnxjwhn/nanomouse") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    Button(L10n.resetAccess) {
                        manager.resetAccess()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(.red)

                    Button(L10n.sharedSupportResetButton) {
                        manager.resetSharedSupportAccess()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.top, 20)
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
