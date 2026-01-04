import SwiftUI
import UniformTypeIdentifiers

struct SchemaDrivenView: View {
    @ObservedObject var schemaStore: SchemaStore
    @ObservedObject var manager: RimeConfigManager
    let sectionIDs: [String]?
    let title: String?

    init(schemaStore: SchemaStore, manager: RimeConfigManager, sectionIDs: [String]? = nil, title: String? = nil) {
        self.schemaStore = schemaStore
        self.manager = manager
        self.sectionIDs = sectionIDs
        self.title = title
    }

    var body: some View {
        Group {
            if let schema = schemaStore.schema {
                let filteredSections = sectionIDs == nil ? schema.sections : schema.sections.filter { sectionIDs!.contains($0.id) }
                SchemaSectionListView(sections: filteredSections, manager: manager, schemaStore: schemaStore)
            } else if let error = schemaStore.errorMessage {
                ContentUnavailableView(L10n.loadSchemaError,
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                ProgressView(L10n.loadingSchema)
                    .padding()
            }
        }
        .navigationTitle(title ?? L10n.defaultTitle)
        .rimeToolbar(manager: manager)
    }
}

private struct SchemaSectionListView: View {
    let sections: [SchemaSection]
    @ObservedObject var manager: RimeConfigManager
    @ObservedObject var schemaStore: SchemaStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sections) { section in
                    SchemaSectionCard(section: section, manager: manager, schemaStore: schemaStore)
                }
            }
            .padding(24)
        }
    }
}

private struct SchemaSectionCard: View {
    let section: SchemaSection
    @ObservedObject var manager: RimeConfigManager
    @ObservedObject var schemaStore: SchemaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: section.icon ?? "square.on.square")
                    .foregroundStyle(Color.accentColor)
                Text(section.title)
                    .font(.headline)
                Spacer()
                Text(section.targetFile)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                ForEach(section.fields) { field in
                    SchemaFieldRow(field: field, section: section, manager: manager, schemaStore: schemaStore)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SchemaFieldRow: View {
    let field: SchemaField
    let section: SchemaSection
    @ObservedObject var manager: RimeConfigManager
    @ObservedObject var schemaStore: SchemaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if field.type == .appOptions || field.type == .keyBinder || field.type == .hotkeyList || field.type == .hotkeyPairList {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                        .fontWeight(.semibold)
                    if let desc = field.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                controlView
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label)
                            .fontWeight(.semibold)
                        if let desc = field.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    Spacer()
                    controlView
                }
            }
        }
    }

    @ViewBuilder
    private var controlView: some View {
        let domain = RimeConfigManager.ConfigDomain(rawValue: section.targetFile) ?? .default
        let rawValue = manager.value(for: field.keyPath, in: domain)

        switch field.type {
        case .toggle:
            Toggle("", isOn: binding(for: field.keyPath, domain: domain, defaultValue: false))
            .labelsHidden()

        case .stepper:
            Stepper(value: Binding(
                get: { manager.intValue(for: field.keyPath, in: domain) ?? field.defaultInt },
                set: { manager.updateValue($0, for: field.keyPath, in: domain) }
            ), in: field.minInt...field.maxInt) {
                Text("\(manager.intValue(for: field.keyPath, in: domain) ?? field.defaultInt)")
                    .monospacedDigit()
            }
            .frame(maxWidth: 200, alignment: .trailing)

        case .text:
            TextField(field.label, text: binding(for: field.keyPath, domain: domain, defaultValue: ""))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200, alignment: .trailing)

        case .enumeration:
            let choices = manager.resolveChoices(for: field)
            Picker("", selection: binding(for: field.keyPath, domain: domain, defaultValue: choices.first ?? "")) {
                if rawValue == nil {
                    Text(L10n.notSet).tag("")
                }
                ForEach(choices, id: \.self) { choice in
                    Text(manager.choiceLabel(for: field, choice: choice)).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 200, alignment: .trailing)

        case .segmented:
            let choices = manager.resolveChoices(for: field)
            Picker("", selection: binding(for: field.keyPath, domain: domain, defaultValue: choices.first ?? "")) {
                ForEach(choices, id: \.self) { choice in
                    Text(manager.choiceLabel(for: field, choice: choice)).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 200, alignment: .trailing)

        case .slider:
            SliderControl(field: field, domain: domain, manager: manager)

        case .colorBGR:
            if let bgrString = rawValue as? String {
                ColorPicker("", selection: Binding(
                    get: { Color(bgrHex: bgrString) ?? .black },
                    set: { if let hex = $0.bgrHexString() { manager.updateValue(hex, for: field.keyPath, in: domain) } }
                ))
                .labelsHidden()
            } else {
                Text(L10n.invalidColor)
                    .foregroundStyle(.secondary)
            }

        case .fontPicker:
            let fonts = schemaStore.availableFonts
            Picker("", selection: binding(for: field.keyPath, domain: domain, defaultValue: "Avenir")) {
                if fonts.isEmpty {
                    Text(L10n.loadingFonts).tag("Avenir")
                } else {
                    ForEach(fonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 200, alignment: .trailing)

        case .multiSelect:
            MultiSelectControl(field: field, domain: domain, manager: manager)

        case .schemaList:
            SchemaListControl(field: field, domain: domain, manager: manager)

        case .appOptions:
            AppOptionsControl(field: field, domain: domain, manager: manager)

        case .keyBinder:
            KeyBinderControl(field: field, domain: domain, manager: manager)

        case .keyMapping:
            KeyMappingControl(field: field, domain: domain, manager: manager)

        case .hotkeyList:
            HotkeyListControl(field: field, domain: domain, manager: manager)

        case .hotkeyPairList:
            HotkeyPairListControl(field: field, domain: domain, manager: manager)

        default:
            Text(SchemaValueFormatter.string(from: rawValue ?? "—"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func binding<T>(for keyPath: String, domain: RimeConfigManager.ConfigDomain, defaultValue: T) -> Binding<T> {
        Binding(
            get: { manager.value(for: keyPath, in: domain) as? T ?? defaultValue },
            set: { manager.updateValue($0, for: keyPath, in: domain) }
        )
    }
}

struct SliderControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @State private var localValue: Double = 0

    var body: some View {
        HStack {
            Slider(value: Binding(
                get: { localValue },
                set: { newValue in
                    let step = field.step ?? 0.05
                    localValue = (newValue / step).rounded() * step
                }
            ), in: (field.min ?? 0)...(field.max ?? 1))
            Text(String(format: "%.2f", localValue))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44)
        }
        .frame(maxWidth: 200, alignment: .trailing)
        .onAppear {
            localValue = manager.doubleValue(for: field.keyPath, in: domain) ?? field.min ?? 0
        }
        .onChange(of: localValue) { _, newValue in
            manager.updateValue(newValue, for: field.keyPath, in: domain)
        }
        // Sync back if manager changes externally
        .onChange(of: manager.doubleValue(for: field.keyPath, in: domain)) { _, newValue in
            if let nv = newValue, nv != localValue {
                localValue = nv
            }
        }
    }
}

struct MultiSelectControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        let currentValues = manager.value(for: field.keyPath, in: domain) as? [String] ?? []
        let choices = manager.resolveChoices(for: field)

        VStack(alignment: .leading, spacing: 6) {
            ForEach(choices, id: \.self) { choice in
                HStack {
                    Spacer()
                    Text(manager.choiceLabel(for: field, choice: choice))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(
                        get: { currentValues.contains(choice) },
                        set: { isSelected in
                            var newValues = currentValues
                            if isSelected {
                                if !newValues.contains(choice) {
                                    newValues.append(choice)
                                }
                            } else {
                                newValues.removeAll { $0 == choice }
                            }
                            manager.updateValue(newValues, for: field.keyPath, in: domain)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
            }
        }
        .frame(maxWidth: 220)
    }
}

struct SchemaListControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @State private var showAll = false
    @State private var newID = ""
    @State private var newName = ""
    @State private var isAdding = false

    var body: some View {
        let availableSchemas = manager.availableSchemas
        let selectedSchemaIDs = manager.schemaListIDs(for: domain)
        let displayActiveIDs = manager.displayActiveSchemaIDs(for: domain)

        let activeSchemas = availableSchemas.filter { displayActiveIDs.contains($0.id) }
        let inactiveSchemas = availableSchemas.filter { !displayActiveIDs.contains($0.id) }

        VStack(alignment: .leading, spacing: 12) {
            // Active Section
            ForEach(activeSchemas) { schema in
                schemaRow(schema,
                          isSelected: true,
                          isVirtualActive: manager.isVirtualActiveSchema(schema.id, in: domain))
            }

            if !inactiveSchemas.isEmpty {
                Button(showAll ? L10n.hideInactiveSchemas : String(format: L10n.showMoreSchemas, inactiveSchemas.count)) {
                    withAnimation { showAll.toggle() }
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if showAll {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(inactiveSchemas) { schema in
                        schemaRow(schema,
                                  isSelected: false,
                                  isVirtualActive: manager.isVirtualActiveSchema(schema.id, in: domain))
                    }
                }
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            // Add New Section
            if isAdding {
                VStack(spacing: 8) {
                    TextField(L10n.schemaIdPlaceholder, text: $newID)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n.schemaNamePlaceholder, text: $newName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button(L10n.cancel) { isAdding = false }
                        Spacer()
                        Button(L10n.confirm) {
                            manager.addNewSchema(id: newID, name: newName)
                            newID = ""
                            newName = ""
                            isAdding = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newID.isEmpty || newName.isEmpty)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button(action: { isAdding = true }) {
                    Label(L10n.addSchema, systemImage: "plus.circle")
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: 350)
    }

    @ViewBuilder
    private func schemaRow(_ schema: RimeConfigManager.RimeSchema, isSelected: Bool, isVirtualActive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(schema.name)
                    .font(.body)
                Text(schema.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if !schema.isBuiltIn {
                Button(role: .destructive) {
                    manager.deleteSchema(id: schema.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.trailing, 4)
            }

            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { newValue in
                    var currentList = (manager.value(for: field.keyPath, in: domain) as? [[String: Any]]) ?? []
                    if newValue {
                        if !currentList.contains(where: { ($0["schema"] as? String) == schema.id }) {
                            currentList.append(["schema": schema.id])
                        }
                    } else {
                        currentList.removeAll { ($0["schema"] as? String) == schema.id }
                    }
                    manager.updateValue(currentList, for: field.keyPath, in: domain)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(isVirtualActive)
        }
        .padding(.vertical, 2)
    }
}

struct AppOptionsControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @State private var newBundleID: String = ""

    var body: some View {
        let options = (manager.value(for: field.keyPath, in: domain) as? [String: [String: Any]]) ?? [:]
        let sortedKeys = options.keys.sorted()

        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(L10n.appId)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    Text(L10n.defaultEnglish).frame(width: 70)
                    Text(L10n.tempInline).frame(width: 70)
                    Text(L10n.disableInline).frame(width: 70)
                    Text(L10n.vimMode).frame(width: 70)
                }
                .multilineTextAlignment(.center)

                Spacer().frame(width: 40) // Space for trash button
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            ForEach(sortedKeys, id: \.self) { bundleID in
                HStack {
                    Text(bundleID)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Group {
                        flagToggle(bundleID: bundleID, flag: "ascii_mode").frame(width: 70)
                        flagToggle(bundleID: bundleID, flag: "inline").frame(width: 70)
                        flagToggle(bundleID: bundleID, flag: "no_inline").frame(width: 70)
                        flagToggle(bundleID: bundleID, flag: "vim_mode").frame(width: 70)
                    }

                    Button(role: .destructive) {
                        var currentOptions = options
                        currentOptions.removeValue(forKey: bundleID)
                        manager.updateValue(currentOptions, for: field.keyPath, in: domain)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .frame(width: 40)
                }
            }

            Divider()

            HStack {
                TextField(L10n.appIdPlaceholder, text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addBundleID() }

                Button {
                    selectApp()
                } label: {
                    Label(L10n.selectApp, systemImage: "app.badge")
                }

                Button(L10n.add) {
                    addBundleID()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newBundleID.isEmpty || options[newBundleID] != nil)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    private func selectApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                newBundleID = bundleID
            }
        }
    }

    private func addBundleID() {
        let options = (manager.value(for: field.keyPath, in: domain) as? [String: [String: Any]]) ?? [:]
        guard !newBundleID.isEmpty, options[newBundleID] == nil else { return }

        var currentOptions = options
        currentOptions[newBundleID] = [:]
        manager.updateValue(currentOptions, for: field.keyPath, in: domain)
        newBundleID = ""
    }

    @ViewBuilder
    private func flagToggle(bundleID: String, flag: String) -> some View {
        let options = (manager.value(for: field.keyPath, in: domain) as? [String: [String: Any]]) ?? [:]
        let flags = options[bundleID] ?? [:]
        let isOn = flags[flag] as? Bool ?? false

        Toggle("", isOn: Binding(
            get: { isOn },
            set: { newValue in
                var currentOptions = options
                var currentFlags = currentOptions[bundleID] ?? [:]
                if newValue {
                    currentFlags[flag] = true
                } else {
                    currentFlags.removeValue(forKey: flag)
                }
                currentOptions[bundleID] = currentFlags
                manager.updateValue(currentOptions, for: field.keyPath, in: domain)
            }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
    }
}

struct KeyBinderControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        let bindings = (manager.value(for: field.keyPath, in: domain) as? [[String: Any]]) ?? []

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.when).frame(width: 80, alignment: .leading)
                Text(L10n.accept).frame(width: 100, alignment: .leading)
                Text(L10n.sendToggle).frame(width: 120, alignment: .leading)
                Spacer()
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            ForEach(0..<bindings.count, id: \.self) { index in
                let binding = bindings[index]
                HStack {
                    Text(L10n.whenLabel(binding["when"] as? String ?? "always"))
                        .frame(width: 80, alignment: .leading)
                    Text(binding["accept"] as? String ?? "")
                        .frame(width: 100, alignment: .leading)
                    Text((binding["send"] as? String) ?? (binding["toggle"] as? String) ?? "")
                        .frame(width: 120, alignment: .leading)

                    Spacer()

                    Button(role: .destructive) {
                        var currentBindings = bindings
                        currentBindings.remove(at: index)
                        manager.updateValue(currentBindings, for: field.keyPath, in: domain)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }
}

struct KeyMappingControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    var body: some View {
        let mapping = (manager.value(for: field.keyPath, in: domain) as? [String: String]) ?? [:]
        let keys = field.keys ?? []
        let choices = field.choices ?? []

        VStack(alignment: .trailing, spacing: 8) {
            ForEach(keys, id: \.self) { key in
                HStack {
                    Text(manager.choiceLabel(for: field, choice: key))
                        .frame(width: 100, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { mapping[key] ?? "noop" },
                        set: { newValue in
                            var currentMapping = mapping
                            currentMapping[key] = newValue
                            manager.updateValue(currentMapping, for: field.keyPath, in: domain)
                        }
                    )) {
                        ForEach(choices, id: \.self) { choice in
                            Text(manager.choiceLabel(for: field, choice: choice)).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 150, alignment: .trailing)
                }
            }
        }
    }
}

struct HotkeyListControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @State private var newHotkey: String = ""
    @State private var isAdding = false

    var body: some View {
        let hotkeys = (manager.value(for: field.keyPath, in: domain) as? [String]) ?? []

        VStack(alignment: .leading, spacing: 8) {
            ForEach(hotkeys, id: \.self) { hotkey in
                HStack {
                    Text(hotkey)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                    Spacer()
                    Button(role: .destructive) {
                        var currentHotkeys = hotkeys
                        currentHotkeys.removeAll { $0 == hotkey }
                        manager.updateValue(currentHotkeys, for: field.keyPath, in: domain)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            if isAdding {
                HStack {
                    HotkeyRecorder(hotkey: $newHotkey)

                    Button(L10n.add) {
                        guard !newHotkey.isEmpty else { return }
                        var currentHotkeys = hotkeys
                        if !currentHotkeys.contains(newHotkey) {
                            currentHotkeys.append(newHotkey)
                            manager.updateValue(currentHotkeys, for: field.keyPath, in: domain)
                        }
                        newHotkey = ""
                        isAdding = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newHotkey.isEmpty)

                    Button(L10n.cancel) {
                        isAdding = false
                        newHotkey = ""
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            } else {
                Button(action: { isAdding = true }) {
                    Label(L10n.addHotkey, systemImage: "plus.circle")
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: 300)
    }
}

struct HotkeyPairListControl: View {
    let field: SchemaField
    let domain: RimeConfigManager.ConfigDomain
    @ObservedObject var manager: RimeConfigManager

    @State private var newHotkey1: String = ""
    @State private var newHotkey2: String = ""
    @State private var isAdding = false

    var body: some View {
        let pairs = (manager.value(for: field.keyPath, in: domain) as? [[String]]) ?? []
        let labels = field.pairLabels ?? ["Key 1", "Key 2"]

        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<pairs.count, id: \.self) { index in
                let pair = pairs[index]
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text(labels[0])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(pair[0])
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Image(systemName: "arrow.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(labels[1])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(pair[1])
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        var currentPairs = pairs
                        currentPairs.remove(at: index)
                        manager.updateValue(currentPairs, for: field.keyPath, in: domain)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            if isAdding {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(labels[0]).font(.caption).foregroundStyle(.secondary)
                            HotkeyRecorder(hotkey: $newHotkey1)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(labels[1]).font(.caption).foregroundStyle(.secondary)
                            HotkeyRecorder(hotkey: $newHotkey2)
                        }
                    }

                    HStack {
                        Button(L10n.add) {
                            guard !newHotkey1.isEmpty && !newHotkey2.isEmpty else { return }
                            var currentPairs = pairs
                            currentPairs.append([newHotkey1, newHotkey2])
                            manager.updateValue(currentPairs, for: field.keyPath, in: domain)
                            newHotkey1 = ""
                            newHotkey2 = ""
                            isAdding = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newHotkey1.isEmpty || newHotkey2.isEmpty)

                        Button(L10n.cancel) {
                            isAdding = false
                            newHotkey1 = ""
                            newHotkey2 = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            } else {
                Button(action: { isAdding = true }) {
                    Label(L10n.addHotkey, systemImage: "plus.circle")
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: 450)
    }
}
