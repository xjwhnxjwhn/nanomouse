import SwiftUI

struct AccessRequestView: View {
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 8) {
                    Text(L10n.accessTitle)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(L10n.accessDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                Button(action: {
                    manager.requestAccess()
                }) {
                    Text(L10n.accessButton)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Divider()
                    .frame(maxWidth: 360)

                VStack(spacing: 8) {
                    Text(L10n.sharedSupportAccessTitle)
                        .font(.headline)
                    Text(L10n.sharedSupportAccessDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    if manager.hasSharedSupportAccess {
                        Label(L10n.sharedSupportAccessGranted, systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button(action: {
                            manager.requestSharedSupportAccess()
                        }) {
                            Text(L10n.sharedSupportAccessButton)
                                .font(.subheadline)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text(L10n.accessFooter)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
        }
    }
}

#Preview {
    AccessRequestView(manager: RimeConfigManager())
}
