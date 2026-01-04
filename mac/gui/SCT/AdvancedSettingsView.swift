import SwiftUI
import Yams

struct AdvancedSettingsView: View {
    @ObservedObject var manager: RimeConfigManager
    @State private var searchText = ""
    @State private var showCustomizedOnly = false
    @State private var selectedDomain: RimeConfigManager.ConfigDomain = .default
    @State private var showSourceEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header / Controls
            HStack(spacing: 6) {
                Text(L10n.configFile)
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedDomain) {
                    Text(L10n.defaultYaml).tag(RimeConfigManager.ConfigDomain.default)
                    Text(L10n.squirrelYaml).tag(RimeConfigManager.ConfigDomain.squirrel)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .labelsHidden()

                Spacer()

                Button(action: { showSourceEditor = true }) {
                    Label(L10n.sourceCodeMode, systemImage: "code.square")
                }
                .buttonStyle(.bordered)

                Toggle(L10n.modifiedOnly, isOn: $showCustomizedOnly)
                    .toggleStyle(.checkbox)
            }
            .padding()
            .background(.ultraThinMaterial)

            // Key-Value List
            List {
                let allKeys = manager.allKeys(in: selectedDomain).sorted()

                let filteredKeys = allKeys.filter { key in
                    let matchesSearch = searchText.isEmpty || key.localizedCaseInsensitiveContains(searchText)
                    let isCustomized = manager.isCustomized(key, in: selectedDomain)
                    return matchesSearch && (!showCustomizedOnly || isCustomized)
                }

                if filteredKeys.isEmpty {
                    ContentUnavailableView(L10n.noResults, systemImage: "magnifyingglass")
                } else {
                    ForEach(filteredKeys, id: \.self) { key in
                        AdvancedRowView(key: key, domain: selectedDomain, manager: manager)
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .automatic, prompt: L10n.searchPlaceholder)
        .navigationTitle(L10n.advanced)
        .rimeToolbar(manager: manager)
        .sheet(isPresented: $showSourceEditor) {
            SourceCodeEditorView(domain: selectedDomain, manager: manager)
        }
    }
}

struct AdvancedRowView: View {
    let key: String
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @FocusState private var isFocused: Bool

    var body: some View {
        let isCustomized = manager.isCustomized(key, in: domain)
        let value = manager.value(for: key, in: domain)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(isCustomized ? .bold : .regular)
                    .foregroundStyle(isCustomized ? Color.accentColor : .primary)
                    .onTapGesture {
                        if isCustomized {
                            isFocused = true
                        }
                    }

                if isCustomized {
                    Text(L10n.patchedValue)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(4)
                }

                Spacer()

                if isCustomized {
                    Button(role: .destructive) {
                        manager.removePatch(for: key, in: domain)
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .help(L10n.reset)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        // Copy current value to patch to start customizing
                        if let val = value {
                            manager.updateValue(val, for: key, in: domain)
                            // Focus the new field
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isFocused = true
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .help(L10n.customize)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }

            if isCustomized {
                TextField("", text: Binding(
                    get: { rawString(from: value) },
                    set: { newValue in
                        let parsed = parseValue(newValue)
                        manager.updateValue(parsed, for: key, in: domain)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isFocused)
                .onChange(of: isFocused) { _, newValue in
                    if newValue {
                        // Select all text when focused
                        DispatchQueue.main.async {
                            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        }
                    }
                }
            } else {
                Text(SchemaValueFormatter.string(from: value ?? "—"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func rawString(from value: Any?) -> String {
        guard let value = value else { return "" }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let int = value as? Int { return String(int) }
        if let double = value as? Double { return String(double) }
        if let decimal = value as? Decimal { return NSDecimalNumber(decimal: decimal).stringValue }
        if let string = value as? String { return string }

        // For complex types (Array/Dictionary), use JSON to keep it on a single line for the TextField.
        // This is valid YAML and will be parsed back into an object by parseValue.
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return SchemaValueFormatter.string(from: value)
    }

    private func parseValue(_ string: String) -> Any {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "true" { return true }
        if trimmed.lowercased() == "false" { return false }
        if let i = Int(trimmed) { return i }
        if let d = Double(trimmed) { return d }

        // Try parsing as YAML for complex types (arrays or dictionaries)
        // We check if it looks like a YAML object/array or if it's a multi-line string
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("-") || trimmed.contains("\n") {
            if let obj = try? Yams.load(yaml: trimmed) {
                return obj
            }
        }

        return string
    }
}

struct SourceCodeEditorView: View {
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager
    @Environment(\.dismiss) var dismiss

    @State private var content: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .padding(4)

                Divider()

                HStack {
                    Text(L10n.rawYamlDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.cancel) {
                        dismiss()
                    }
                    Button(L10n.save) {
                        manager.saveRawYaml(content, for: domain)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(L10n.sourceCodeMode)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            content = manager.loadRawYaml(for: domain)
        }
    }
}
