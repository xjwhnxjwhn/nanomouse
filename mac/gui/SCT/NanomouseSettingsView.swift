import SwiftUI

struct NanomouseSettingsView: View {
    @ObservedObject var manager: RimeConfigManager
    @State private var presetStates: [String: Bool] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.nanomouseIntro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(L10n.nanomouseHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(NanomousePreset.allCases) { preset in
                    NanomousePresetRow(
                        preset: preset,
                        isOn: Binding(
                            get: { presetStates[preset.id] ?? manager.nanomousePresetIsEnabled(preset) },
                            set: { newValue in
                                manager.setNanomousePreset(preset, enabled: newValue)
                                presetStates[preset.id] = manager.nanomousePresetIsEnabled(preset)
                                manager.deploy()
                            }
                        ),
                        isEnabled: manager.hasAccess
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .navigationTitle(L10n.nanomouse)
        .rimeToolbar(manager: manager)
        .onAppear {
            reloadPresetStates()
        }
        .onChange(of: manager.hasAccess) { _, _ in
            reloadPresetStates()
        }
    }

    private func reloadPresetStates() {
        var states: [String: Bool] = [:]
        for preset in NanomousePreset.allCases {
            states[preset.id] = manager.nanomousePresetIsEnabled(preset)
        }
        presetStates = states
    }
}

private struct NanomousePresetRow: View {
    let preset: NanomousePreset
    @Binding var isOn: Bool
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(preset.displayName)
                    .font(.headline)
                Text(preset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(!isEnabled)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    NanomouseSettingsView(manager: RimeConfigManager())
}
