import Foundation
import Combine
import Yams
import AppKit

/// A lightweight configuration loader that reads the available `.custom.yaml` patches.
/// The goal for now is to exercise the Yams dependency and provide data for the prototype UI.
final class RimeConfigManager: ObservableObject {
    enum ConfigDomain: String {
        case `default`
        case squirrel
    }

    struct RimeSchema: Identifiable, Hashable {
        var id: String { schemaID }
        let schemaID: String
        let name: String
        let isBuiltIn: Bool
    }

    @Published var availableSchemas: [RimeSchema] = []
    @Published var statusMessage: String = L10n.loadingConfig
    @Published var hasAccess: Bool = false
    @Published var hasSharedSupportAccess: Bool = false
    @Published private(set) var mergedConfigs: [ConfigDomain: [String: Any]] = [:]
    @Published private(set) var patchConfigs: [ConfigDomain: [String: Any]] = [:]

    // Data Safety & Undo
    var undoManager: UndoManager?
    private var isDirty = false
    private var hasCreatedSessionBackup = false
    private let maxBackups = 20

    private var choicesCache: [String: [String]] = [:]
    private var labelsCache: [String: String] = [:]

    private var saveTasks: [String: Task<Void, Never>] = [:]
    @Published var rimePath: URL
    @Published var sharedSupportPath: URL
    private let fileManager = FileManager.default
    private let bookmarkKey = "RimeDirectoryBookmark"
    private let sharedSupportBookmarkKey = "SquirrelSharedSupportBookmark"
    private var sharedSupportBookmarkURL: URL?
    private static let defaultSharedSupportPath = URL(fileURLWithPath: "/Library/Input Methods/Squirrel.app/Contents/SharedSupport", isDirectory: true)

    /// Executes a block of code with security-scoped access to the Rime directory.
    func withSecurityScopedAccess<T>(_ action: () throws -> T) rethrows -> T {
        let isScoped = rimePath.startAccessingSecurityScopedResource()
        defer { if isScoped { rimePath.stopAccessingSecurityScopedResource() } }
        return try action()
    }

    /// 使用安全书签访问 Squirrel SharedSupport，避免沙盒环境下访问失败。
    func withSharedSupportAccess<T>(_ action: () throws -> T) rethrows -> T {
        guard let scopeURL = sharedSupportBookmarkURL else {
            return try action()
        }
        let isScoped = scopeURL.startAccessingSecurityScopedResource()
        defer { if isScoped { scopeURL.stopAccessingSecurityScopedResource() } }
        return try action()
    }

    func resetAccess() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        self.rimePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Rime", isDirectory: true)
        self.hasAccess = false
        self.statusMessage = L10n.accessRequired
    }

    private var folderMonitor: DispatchSourceFileSystemObject?
    private var folderDescriptor: Int32 = -1

    private static let fallbackYAML = """
    menu:
      page_size: 9
    schema_list:
      - schema: rime_ice
      - schema: double_pinyin
      - schema: t9
    style:
      color_scheme: dark_temple
      font_face: "Sarasa UI SC"
      font_point: 16
    app_options:
      com.apple.Terminal:
        ascii_mode: true
      com.apple.dt.Xcode:
        ascii_mode: true
    """

    init(rimePath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Rime", isDirectory: true)) {
        self.rimePath = rimePath
        self.sharedSupportPath = Self.defaultSharedSupportPath

        let bookmarked = loadBookmark()
        let sharedBookmarked = loadSharedSupportBookmark()
        loadConfig()

        if bookmarked || checkActualAccess() {
            self.hasAccess = true
            startMonitoring()
        } else {
            self.hasAccess = false
            statusMessage = L10n.accessRequired
        }

        if sharedBookmarked || checkSharedSupportAccess() {
            self.hasSharedSupportAccess = true
        } else {
            self.hasSharedSupportAccess = false
        }
    }

    func resetSharedSupportAccess() {
        UserDefaults.standard.removeObject(forKey: sharedSupportBookmarkKey)
        self.sharedSupportBookmarkURL = nil
        self.sharedSupportPath = Self.defaultSharedSupportPath
        self.hasSharedSupportAccess = false
        self.statusMessage = L10n.sharedSupportAccessReset
        self.parseAvailableSchemas()
    }

    private func checkActualAccess() -> Bool {
        return withSecurityScopedAccess {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: rimePath.path, isDirectory: &isDir) && isDir.boolValue && FileManager.default.isReadableFile(atPath: rimePath.path)
        }
    }

    private func checkSharedSupportAccess() -> Bool {
        return withSharedSupportAccess {
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: sharedSupportPath.path, isDirectory: &isDir) && isDir.boolValue && fileManager.isReadableFile(atPath: sharedSupportPath.path)
        }
    }

    func requestAccess() {
        let openPanel = NSOpenPanel()
        openPanel.message = L10n.accessPrompt
        openPanel.prompt = L10n.accessConfirm
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = rimePath

        openPanel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = openPanel.url else { return }

            do {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: self.bookmarkKey)
                self.rimePath = url
                self.hasAccess = true
                self.hasCreatedSessionBackup = false
                self.isDirty = false
                self.loadConfig()
                self.startMonitoring()
            } catch {
                self.statusMessage = String(format: L10n.authFailed, error.localizedDescription)
            }
        }
    }

    func requestSharedSupportAccess() {
        let openPanel = NSOpenPanel()
        openPanel.message = L10n.sharedSupportAccessPrompt
        openPanel.prompt = L10n.sharedSupportAccessConfirm
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.treatsFilePackagesAsDirectories = true
        openPanel.directoryURL = URL(fileURLWithPath: "/Library/Input Methods", isDirectory: true)

        openPanel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = openPanel.url else { return }

            // 允许用户选择 Squirrel.app 或 SharedSupport 目录，统一解析为 SharedSupport 路径。
            guard let resolvedSharedSupport = self.resolveSharedSupportPath(from: url),
                  self.fileManager.fileExists(atPath: resolvedSharedSupport.path) else {
                self.statusMessage = L10n.sharedSupportAccessInvalid
                return
            }

            do {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: self.sharedSupportBookmarkKey)
                self.sharedSupportBookmarkURL = url
                self.sharedSupportPath = resolvedSharedSupport
                self.hasSharedSupportAccess = true
                self.statusMessage = L10n.sharedSupportAccessSuccess
                self.parseAvailableSchemas()
            } catch {
                self.statusMessage = String(format: L10n.sharedSupportAccessFailed, error.localizedDescription)
            }
        }
    }

    private func loadBookmark() -> Bool {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            print("DEBUG: No bookmark data found in UserDefaults for key: \(bookmarkKey)")
            return false
        }

        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale)

            if isStale {
                print("DEBUG: Bookmark is stale, refreshing...")
                let newBookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(newBookmarkData, forKey: bookmarkKey)
            }

            self.rimePath = url
            print("DEBUG: Successfully resolved bookmark: \(url.path)")
            return true
        } catch {
            print("DEBUG: Failed to resolve bookmark: \(error.localizedDescription)")
            return false
        }
    }

    private func loadSharedSupportBookmark() -> Bool {
        guard let bookmarkData = UserDefaults.standard.data(forKey: sharedSupportBookmarkKey) else {
            return false
        }

        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale)

            if isStale {
                let newBookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(newBookmarkData, forKey: sharedSupportBookmarkKey)
            }

            guard let resolvedPath = resolveSharedSupportPath(from: url) else {
                return false
            }
            sharedSupportBookmarkURL = url
            sharedSupportPath = resolvedPath
            return true
        } catch {
            return false
        }
    }

    private func resolveSharedSupportPath(from url: URL) -> URL? {
        if url.pathExtension == "app" {
            return url.appendingPathComponent("Contents/SharedSupport", isDirectory: true)
        }
        if url.lastPathComponent == "SharedSupport" {
            return url
        }
        return nil
    }

    deinit {
        folderMonitor?.cancel()
    }

    private func startMonitoring() {
        withSecurityScopedAccess {
            folderDescriptor = open(rimePath.path, O_EVTONLY)
            guard folderDescriptor != -1 else { return }

            folderMonitor = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: folderDescriptor,
                eventMask: .write,
                queue: DispatchQueue.main
            )

            folderMonitor?.setEventHandler { [weak self] in
                // Directory content changed (file added, removed, or modified)
                // We use a small delay to avoid multiple rapid reloads
                self?.loadConfig()
            }

            folderMonitor?.setCancelHandler { [weak self] in
                if let descriptor = self?.folderDescriptor {
                    close(descriptor)
                }
            }

            folderMonitor?.resume()
        }
    }

    private func createBackup(reason: String) {
        withSecurityScopedAccess {
            let backupsRoot = rimePath.appendingPathComponent(".sct", isDirectory: true)
                .appendingPathComponent("backups", isDirectory: true)

            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "Z", with: "")

            let folderName = "\(timestamp)_\(reason)"
            let currentBackupDir = backupsRoot.appendingPathComponent(folderName, isDirectory: true)

            do {
                try fileManager.createDirectory(at: currentBackupDir, withIntermediateDirectories: true)

                let filesToBackup = ["default.custom.yaml", "squirrel.custom.yaml"]
                var backedUpAny = false

                for fileName in filesToBackup {
                    let sourceURL = rimePath.appendingPathComponent(fileName)
                    if fileManager.fileExists(atPath: sourceURL.path) {
                        let destURL = currentBackupDir.appendingPathComponent(fileName)
                        try fileManager.copyItem(at: sourceURL, to: destURL)
                        backedUpAny = true
                    }
                }

                // If no files were backed up, remove the empty folder
                if !backedUpAny {
                    try fileManager.removeItem(at: currentBackupDir)
                } else {
                    rotateBackups()
                }
            } catch {
                print("Backup failed: \(error)")
            }
        }
    }

    private func rotateBackups() {
        withSecurityScopedAccess {
            let backupsRoot = rimePath.appendingPathComponent(".sct", isDirectory: true)
                .appendingPathComponent("backups", isDirectory: true)

            guard let items = try? fileManager.contentsOfDirectory(at: backupsRoot, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey]) else { return }

            // Only rotate directories
            let folders = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

            let sortedFolders = folders.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 < date2
            }

            if sortedFolders.count > maxBackups {
                let toDelete = sortedFolders.count - maxBackups
                for i in 0..<toDelete {
                    try? fileManager.removeItem(at: sortedFolders[i])
                }
            }
        }
    }

    func loadConfig() {
        if !hasCreatedSessionBackup && hasAccess {
            createBackup(reason: "session_start")
            hasCreatedSessionBackup = true
        }

        withSecurityScopedAccess {
            choicesCache.removeAll()
            labelsCache.removeAll()

            let hasDefaultFiles = fileExists(named: "default.yaml") || fileExists(named: "default.custom.yaml")
            let hasSquirrelFiles = fileExists(named: "squirrel.yaml") || fileExists(named: "squirrel.custom.yaml")

            guard hasDefaultFiles || hasSquirrelFiles else {
                applyFallbackSnapshot()
                statusMessage = L10n.usingExampleConfig
                return
            }

            let defaultBase = loadYamlDictionary(named: "default.yaml")
            let defaultPatch = loadPatchDictionary(named: "default.custom.yaml")
            patchConfigs[.default] = defaultPatch
            mergedConfigs[.default] = mergedDictionary(base: defaultBase, patch: normalizeRimeDictionary(defaultPatch))

            let squirrelBase = loadYamlDictionary(named: "squirrel.yaml")
            let squirrelPatch = loadPatchDictionary(named: "squirrel.custom.yaml")
            patchConfigs[.squirrel] = squirrelPatch
            mergedConfigs[.squirrel] = mergedDictionary(base: squirrelBase, patch: normalizeRimeDictionary(squirrelPatch))

            parseAvailableSchemas()
            statusMessage = String(format: L10n.readPath, rimePath.path)
        }
    }

    private func parseAvailableSchemas() {
        var schemas: [RimeSchema] = []
        var seen = Set<String>()

        let mergedDefault = mergedConfigs[.default] ?? [:]
        let schemaListIDs = parseSchemaListIDs(from: mergedDefault)

        // 为了展示系统内置方案（如明月拼音），需要同时扫描用户目录与 Squirrel 共享目录。
        let schemaFileMap = buildSchemaFileMap()

        for id in schemaListIDs {
            guard !seen.contains(id) else { continue }
            let name = schemaFileMap[id].flatMap(getSchemaName) ?? id
            schemas.append(RimeSchema(schemaID: id, name: name, isBuiltIn: true))
            seen.insert(id)
        }

        for (id, fileURL) in schemaFileMap.sorted(by: { $0.key < $1.key }) {
            guard !seen.contains(id) else { continue }
            let name = getSchemaName(from: fileURL) ?? id
            schemas.append(RimeSchema(schemaID: id, name: name, isBuiltIn: false))
            seen.insert(id)
        }

        self.availableSchemas = schemas
    }

    private func parseSchemaListIDs(from config: [String: Any]) -> [String] {
        guard let list = config["schema_list"] else { return [] }
        var ids: [String] = []

        if let items = list as? [[String: Any]] {
            for item in items {
                if let id = item["schema"] as? String {
                    ids.append(id)
                }
            }
            return ids
        }

        if let items = list as? [String] {
            return items
        }

        if let items = list as? [Any] {
            for item in items {
                if let id = item as? String {
                    ids.append(id)
                } else if let dict = item as? [String: Any], let id = dict["schema"] as? String {
                    ids.append(id)
                }
            }
        }

        return ids
    }

    func schemaListIDs(for domain: ConfigDomain) -> [String] {
        return parseSchemaListIDs(from: mergedConfigs[domain] ?? [:])
    }

    func displayActiveSchemaIDs(for domain: ConfigDomain) -> Set<String> {
        var ids = Set(schemaListIDs(for: domain))
        guard domain == .default else { return ids }

        let schemaFileMap = buildSchemaFileMap()
        if schemaFileMap["luna_pinyin"] != nil {
            ids.insert("luna_pinyin")
        }

        return ids
    }

    func isVirtualActiveSchema(_ id: String, in domain: ConfigDomain) -> Bool {
        let actual = Set(schemaListIDs(for: domain))
        let display = displayActiveSchemaIDs(for: domain)
        return display.contains(id) && !actual.contains(id)
    }


    private func buildSchemaFileMap() -> [String: URL] {
        var result: [String: URL] = [:]

        for (id, url) in schemaFiles(in: rimePath) {
            result[id] = url
        }

        for sharedPath in squirrelSharedSupportPaths() {
            let files = schemaFilesWithSharedSupportAccessIfNeeded(in: sharedPath)
            for (id, url) in files where result[id] == nil {
                result[id] = url
            }
        }

        return result
    }

    private func schemaFilesWithSharedSupportAccessIfNeeded(in directory: URL) -> [String: URL] {
        if hasSharedSupportAccess, directory == sharedSupportPath {
            return withSharedSupportAccess {
                schemaFiles(in: directory)
            }
        }
        return schemaFiles(in: directory)
    }

    private func schemaFiles(in directory: URL) -> [String: URL] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [:]
        }

        var results: [String: URL] = [:]
        for file in files where file.pathExtension == "yaml" && file.lastPathComponent.hasSuffix(".schema.yaml") {
            let id = file.lastPathComponent.replacingOccurrences(of: ".schema.yaml", with: "")
            results[id] = file
        }
        return results
    }

    private func squirrelSharedSupportPaths() -> [URL] {
        var paths: [URL] = []

        if hasSharedSupportAccess {
            paths.append(sharedSupportPath)
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "im.rime.inputmethod.Squirrel") {
            paths.append(appURL.appendingPathComponent("Contents/SharedSupport", isDirectory: true))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        paths.append(home.appendingPathComponent("Library/Input Methods/Squirrel.app/Contents/SharedSupport", isDirectory: true))
        paths.append(URL(fileURLWithPath: "/Library/Input Methods/Squirrel.app/Contents/SharedSupport", isDirectory: true))

        let uniquePaths = Array(Set(paths))
        return uniquePaths.filter { url in
            if hasSharedSupportAccess, url == sharedSupportPath {
                return withSharedSupportAccess {
                    fileManager.fileExists(atPath: url.path)
                }
            }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    private func getSchemaName(from url: URL) -> String? {
        let readSchemaName: () -> String? = {
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  let dict = try? Yams.load(yaml: content) as? [String: Any],
                  let schema = dict["schema"] as? [String: Any] else {
                return nil
            }
            return schema["name"] as? String
        }

        if hasSharedSupportAccess, url.path.hasPrefix(sharedSupportPath.path) {
            return withSharedSupportAccess {
                readSchemaName()
            }
        }

        return readSchemaName()
    }

    func reload() {
        loadConfig()
    }

    func addNewSchema(id: String, name: String) {
        if !isDirty && hasAccess {
            createBackup(reason: "first_change")
            isDirty = true
        }
        withSecurityScopedAccess {
            let fileName = "\(id).schema.yaml"
            let url = rimePath.appendingPathComponent(fileName)

            let content = """
            # Rime schema settings
            schema:
              schema_id: \(id)
              name: \(name)
              version: "0.1"
            """

            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                loadConfig()
                statusMessage = String(format: L10n.schemaAdded, name)
            } catch {
                statusMessage = String(format: L10n.schemaAddFailed, error.localizedDescription)
            }
        }
    }

    func deleteSchema(id: String) {
        if !isDirty && hasAccess {
            createBackup(reason: "first_change")
            isDirty = true
        }
        withSecurityScopedAccess {
            let fileName = "\(id).schema.yaml"
            let url = rimePath.appendingPathComponent(fileName)

            do {
                // 1. Remove from schema_list if present in patch
                var patch = patchConfigs[.default] ?? [:]
                if var schemaList = patch["schema_list"] as? [[String: Any]] {
                    let originalCount = schemaList.count
                    schemaList.removeAll { ($0["schema"] as? String) == id }
                    if schemaList.count != originalCount {
                        patch["schema_list"] = schemaList
                        patchConfigs[.default] = patch
                        saveFullPatch(in: .default)
                    }
                }

                // 2. Delete the file
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                    loadConfig()
                    statusMessage = String(format: L10n.schemaDeleted, id)
                } else {
                    loadConfig()
                    statusMessage = String(format: L10n.configCleaned, id)
                }
            } catch {
                statusMessage = String(format: L10n.schemaDeleteFailed, error.localizedDescription)
            }
        }
    }

    /// Triggers Squirrel to reload its configuration.
    func deploy() {
        isDirty = false
        let squirrelAppPath = "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: squirrelAppPath)
        process.arguments = ["--reload"]

        do {
            try process.run()
            statusMessage = L10n.deployTriggered
        } catch {
            // Fallback: touch the config files if the app is not found or fails
            statusMessage = L10n.deployFailed
            touchConfigFiles()
        }
    }

    private func touchConfigFiles() {
        withSecurityScopedAccess {
            let files = ["default.custom.yaml", "squirrel.custom.yaml"]
            for fileName in files {
                let fileURL = rimePath.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: fileURL.path) {
                    try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
                }
            }
            statusMessage = L10n.timestampUpdated
        }
    }

    func value(for keyPath: String, in domain: ConfigDomain) -> Any? {
        // Handle virtual keypaths for key_binder
        if keyPath.hasPrefix("key_binder/") {
            let virtualKey = keyPath.replacingOccurrences(of: "key_binder/", with: "")
            switch virtualKey {
            case "select_pair":
                let first = value(in: mergedConfigs[domain] ?? [:], keyPath: "key_binder/select_first_character") as? String ?? ""
                let last = value(in: mergedConfigs[domain] ?? [:], keyPath: "key_binder/select_last_character") as? String ?? ""
                return (first.isEmpty && last.isEmpty) ? [] : [[first, last]]
            case "cursor_pair":
                return getVirtualHotkeyPairs(prevAction: "cursor_prev", nextAction: "cursor_next", in: domain)
            case "page_pair":
                return getVirtualHotkeyPairs(prevAction: "page_up", nextAction: "page_down", in: domain)
            default: break
            }
        }

        guard let dictionary = mergedConfigs[domain] else { return nil }
        return value(in: dictionary, keyPath: keyPath)
    }

    func isCustomized(_ keyPath: String, in domain: ConfigDomain) -> Bool {
        guard let patch = patchConfigs[domain] else { return false }
        return patch[keyPath] != nil
    }

    private func getVirtualHotkeyPairs(prevAction: String, nextAction: String, in domain: ConfigDomain) -> [[String]] {
        let prevs = getVirtualHotkeys(for: prevAction, in: domain)
        let nexts = getVirtualHotkeys(for: nextAction, in: domain)

        var pairs: [[String]] = []
        let count = min(prevs.count, nexts.count)
        for i in 0..<count {
            pairs.append([prevs[i], nexts[i]])
        }
        return pairs
    }

    private func getVirtualHotkeys(for action: String, in domain: ConfigDomain) -> [String] {
        let bindings = value(for: "key_binder/bindings", in: domain) as? [[String: Any]] ?? []
        let targetSend: String
        let targetWhen: String

        switch action {
        case "cursor_prev": (targetSend, targetWhen) = ("Shift+Left", "composing")
        case "cursor_next": (targetSend, targetWhen) = ("Shift+Right", "composing")
        case "page_up": (targetSend, targetWhen) = ("Page_Up", "has_menu")
        case "page_down": (targetSend, targetWhen) = ("Page_Down", "has_menu")
        default: return []
        }

        return bindings.filter { ($0["send"] as? String) == targetSend && ($0["when"] as? String) == targetWhen }
            .compactMap { $0["accept"] as? String }
    }

    func allKeys(in domain: ConfigDomain) -> [String] {
        guard let dictionary = mergedConfigs[domain] else { return [] }
        return getAllKeys(from: dictionary)
    }

    private func getAllKeys(from dict: [String: Any], prefix: String = "") -> [String] {
        var keys: [String] = []
        for (key, value) in dict {
            let fullKey = prefix.isEmpty ? key : "\(prefix)/\(key)"
            if let subDict = value as? [String: Any] {
                keys.append(contentsOf: getAllKeys(from: subDict, prefix: fullKey))
            } else {
                keys.append(fullKey)
            }
        }
        return keys
    }

    func mergedConfig(for domain: ConfigDomain) -> [String: Any] {
        return mergedConfigs[domain] ?? [:]
    }

    func doubleValue(for keyPath: String, in domain: ConfigDomain) -> Double? {
        asDouble(value(for: keyPath, in: domain))
    }

    func intValue(for keyPath: String, in domain: ConfigDomain) -> Int? {
        asInt(value(for: keyPath, in: domain))
    }

    /// Resolves choices for a field, either from fixed choices or a reference to another config path.
    func resolveChoices(for field: SchemaField) -> [String] {
        if let choices = field.choices {
            return choices
        }

        if let ref = field.choicesRef {
            if let cached = choicesCache[ref] {
                return cached
            }

            let domains: [ConfigDomain] = [.squirrel, .default]
            for domain in domains {
                if let dict = value(for: ref, in: domain) as? [String: Any] {
                    let sortedKeys = dict.keys.sorted()
                    choicesCache[ref] = sortedKeys
                    return sortedKeys
                }
            }
        }

        return []
    }

    /// Returns a user-friendly label for a choice ID.
    func choiceLabel(for field: SchemaField, choice: String) -> String {
        let cacheKey = "\(field.id):\(choice)"
        if let cached = labelsCache[cacheKey] {
            return cached
        }

        // Hardcoded labels for common Rime options (can be moved to Schema or Localization later)
        let commonLabels: [String: String] = [
            "ascii_punct": L10n.asciiPunct,
            "traditionalization": L10n.traditionalization,
            "emoji": L10n.emoji,
            "full_shape": L10n.fullShape,
            "search_single_char": L10n.searchSingleChar,
            "noop": L10n.noop,
            "clear": L10n.clear,
            "commit_code": L10n.commitCode,
            "commit_text": L10n.commitText,
            "inline_ascii": L10n.inlineAscii,
            "Caps_Lock": L10n.capsLock,
            "Shift_L": L10n.shiftL,
            "Shift_R": L10n.shiftR,
            "Control_L": L10n.controlL,
            "Control_R": L10n.controlR
        ]

        if let label = commonLabels[choice] {
            labelsCache[cacheKey] = label
            return label
        }

        if field.choices != nil {
            return choice // Fixed choices are already labels
        }

        if let ref = field.choicesRef {
            let domains: [ConfigDomain] = [.squirrel, .default]
            for domain in domains {
                if let dict = value(for: ref, in: domain) as? [String: Any],
                   let item = dict[choice] as? [String: Any],
                   let name = item["name"] as? String {
                    labelsCache[cacheKey] = name
                    return name
                }
            }
        }

        labelsCache[cacheKey] = choice
        return choice
    }

    func updateValue(_ value: Any, for keyPath: String, in domain: ConfigDomain) {
        // Register Undo
        let oldValue = patchConfigs[domain]?[keyPath]
        undoManager?.registerUndo(withTarget: self) { target in
            if let old = oldValue {
                target.updateValue(old, for: keyPath, in: domain)
            } else {
                target.removePatch(for: keyPath, in: domain)
            }
        }

        // First-Change Backup
        if !isDirty && hasAccess {
            createBackup(reason: "first_change")
            isDirty = true
        }

        var finalValue = value

        // Handle virtual keypaths for key_binder
        if keyPath.hasPrefix("key_binder/") {
            let virtualKey = keyPath.replacingOccurrences(of: "key_binder/", with: "")
            switch virtualKey {
            case "select_pair":
                let pairs = value as? [[String]] ?? []
                if let firstPair = pairs.first, firstPair.count == 2 {
                    updateValue(firstPair[0], for: "key_binder/select_first_character", in: domain)
                    updateValue(firstPair[1], for: "key_binder/select_last_character", in: domain)
                } else {
                    updateValue("", for: "key_binder/select_first_character", in: domain)
                    updateValue("", for: "key_binder/select_last_character", in: domain)
                }
                return
            case "cursor_pair":
                updateVirtualHotkeyPairs(value as? [[String]] ?? [], prevAction: "cursor_prev", nextAction: "cursor_next", in: domain)
                return
            case "page_pair":
                updateVirtualHotkeyPairs(value as? [[String]] ?? [], prevAction: "page_up", nextAction: "page_down", in: domain)
                return
            default: break
            }
        }

        // Handle Double to ensure clean YAML output without scientific notation
        if let doubleValue = value as? Double {
            // Using Decimal with a fixed locale to ensure consistent string conversion
            let rounded = (doubleValue * 10000).rounded() / 10000
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.maximumFractionDigits = 4
            formatter.numberStyle = .decimal
            if let formattedString = formatter.string(from: NSNumber(value: rounded)),
               let decimal = Decimal(string: formattedString, locale: Locale(identifier: "en_US")) {
                finalValue = decimal
            } else {
                finalValue = rounded
            }
        }

        // 1. Update mergedConfigs for immediate UI update
        var merged = mergedConfigs[domain] ?? [:]
        let components = keyPath.split(separator: "/").map(String.init)
        updateInMemoryValue(finalValue, for: components[...], in: &merged)
        mergedConfigs[domain] = merged

        // 1.5 Update patchConfigs for YAML editor
        var patch = patchConfigs[domain] ?? [:]
        patch[keyPath] = finalValue
        patchConfigs[domain] = patch

        // 3. Save to .custom.yaml (Debounced)
        let taskKey = "\(domain.rawValue)/\(keyPath)"
        saveTasks[taskKey]?.cancel()
        saveTasks[taskKey] = Task {
            // Small delay to batch rapid updates (like sliders)
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            if !Task.isCancelled {
                saveToPatch(finalValue, for: keyPath, in: domain)
            }
        }
    }
    func removePatch(for keyPath: String, in domain: ConfigDomain) {
        // Register Undo
        if let oldValue = patchConfigs[domain]?[keyPath] {
            undoManager?.registerUndo(withTarget: self) { target in
                target.updateValue(oldValue, for: keyPath, in: domain)
            }
        }

        // First-Change Backup
        if !isDirty && hasAccess {
            createBackup(reason: "first_change")
            isDirty = true
        }

        // 1. Update patchConfigs
        var patch = patchConfigs[domain] ?? [:]
        patch.removeValue(forKey: keyPath)
        patchConfigs[domain] = patch

        // 2. Save the updated patch file
        saveFullPatch(in: domain)

        // 3. Reload everything to get back to base values
        loadConfig()
    }

    private func saveFullPatch(in domain: ConfigDomain) {
        withSecurityScopedAccess {
            var root = loadPatchRoot(for: domain)
            root["patch"] = patchConfigs[domain] ?? [:]
            savePatchRoot(root, for: domain)
        }
    }

    func loadRawYaml(for domain: ConfigDomain) -> String {
        withSecurityScopedAccess {
            let fileName = "\(domain.rawValue).custom.yaml"
            let url = rimePath.appendingPathComponent(fileName)
            return (try? String(contentsOf: url, encoding: .utf8)) ?? "patch:\n"
        }
    }

    func saveRawYaml(_ content: String, for domain: ConfigDomain) {
        // Register Undo
        let oldContent = loadRawYaml(for: domain)
        undoManager?.registerUndo(withTarget: self) { target in
            target.saveRawYaml(oldContent, for: domain)
        }

        // First-Change Backup
        if !isDirty && hasAccess {
            createBackup(reason: "first_change")
            isDirty = true
        }

        withSecurityScopedAccess {
            let fileName = "\(domain.rawValue).custom.yaml"
            let url = rimePath.appendingPathComponent(fileName)
            try? content.write(to: url, atomically: true, encoding: .utf8)
            loadConfig() // Reload to sync UI
            statusMessage = String(format: L10n.saveSuccess, fileName)
        }
    }
    private func updateVirtualHotkeyPairs(_ pairs: [[String]], prevAction: String, nextAction: String, in domain: ConfigDomain) {
        let prevHotkeys = pairs.map { $0[0] }
        let nextHotkeys = pairs.map { $0[1] }

        // We need to update both actions in the bindings
        var bindings = value(for: "key_binder/bindings", in: domain) as? [[String: Any]] ?? []

        let (prevSend, prevWhen) = getActionDetails(for: prevAction)
        let (nextSend, nextWhen) = getActionDetails(for: nextAction)

        // 1. Remove existing bindings for both actions
        bindings.removeAll {
            (($0["send"] as? String) == prevSend && ($0["when"] as? String) == prevWhen) ||
            (($0["send"] as? String) == nextSend && ($0["when"] as? String) == nextWhen)
        }

        // 2. Add new bindings in pairs
        for i in 0..<pairs.count {
            bindings.append(["when": prevWhen, "accept": prevHotkeys[i], "send": prevSend])
            bindings.append(["when": nextWhen, "accept": nextHotkeys[i], "send": nextSend])
        }

        // 3. Update the real keyPath
        updateValue(bindings, for: "key_binder/bindings", in: domain)
    }

    private func getActionDetails(for action: String) -> (send: String, when: String) {
        switch action {
        case "cursor_prev": return ("Shift+Left", "composing")
        case "cursor_next": return ("Shift+Right", "composing")
        case "page_up": return ("Page_Up", "has_menu")
        case "page_down": return ("Page_Down", "has_menu")
        default: return ("", "")
        }
    }

    private func updateInMemoryValue(_ value: Any, for components: ArraySlice<String>, in dictionary: inout [String: Any]) {
        guard let head = components.first else { return }
        if components.count == 1 {
            dictionary[head] = value
            return
        }
        var child = dictionary[head] as? [String: Any] ?? [:]
        updateInMemoryValue(value, for: components.dropFirst(), in: &child)
        dictionary[head] = child
    }

    private func saveToPatch(_ value: Any, for keyPath: String, in domain: ConfigDomain) {
        withSecurityScopedAccess {
            var root = loadPatchRoot(for: domain)
            var patch = root["patch"] as? [String: Any] ?? [:]

            // Use flat keys (e.g., "style/font_face") instead of nested structures.
            // This is the most robust way to patch Rime configs without overwriting sibling keys.
            patch[keyPath] = value
            root["patch"] = patch

            savePatchRoot(root, for: domain)
        }
    }

    private func loadPatchRoot(for domain: ConfigDomain) -> [String: Any] {
        let fileName = "\(domain.rawValue).custom.yaml"
        let url = rimePath.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path),
           let contents = try? String(contentsOf: url, encoding: .utf8),
           let existingRoot = try? Yams.load(yaml: contents) as? [String: Any] {
            return existingRoot
        }
        return [:]
    }

    private func savePatchRoot(_ root: [String: Any], for domain: ConfigDomain) {
        let fileName = "\(domain.rawValue).custom.yaml"
        let url = rimePath.appendingPathComponent(fileName)
        do {
            // sortKeys: true ensures consistent output order
            // allowUnicode: true ensures Chinese characters are not escaped
            let yaml = try Yams.dump(object: root, width: -1, allowUnicode: true, sortKeys: true)
            try yaml.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = String(format: L10n.saveSuccess, fileName)
        } catch {
            statusMessage = String(format: L10n.saveFailed, error.localizedDescription)
        }
    }

    private func flattenDictionary(_ dict: [String: Any], prefix: String = "") -> [String: Any] {
        var flat: [String: Any] = [:]
        for (key, value) in dict {
            let fullKey = prefix.isEmpty ? key : "\(prefix)/\(key)"
            if let subDict = value as? [String: Any] {
                let subFlat = flattenDictionary(subDict, prefix: fullKey)
                flat.merge(subFlat) { (_, new) in new }
            } else {
                flat[fullKey] = value
            }
        }
        return flat
    }

    private func loadPatchDictionary(named fileName: String) -> [String: Any] {
        let url = rimePath.appendingPathComponent(fileName)
          guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              let root = try? Yams.load(yaml: contents) as? [String: Any],
              let patch = root["patch"] as? [String: Any] else {
            return [:]
        }
          return flattenDictionary(patch)
    }

    private func loadYamlDictionary(named fileName: String) -> [String: Any] {
        let url = rimePath.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              let root = try? Yams.load(yaml: contents) as? [String: Any] else {
            return [:]
        }
          return normalizeRimeDictionary(root)
    }

    private func mergedDictionary(base: [String: Any], patch: [String: Any]) -> [String: Any] {
        guard !patch.isEmpty else { return base }
        var result = base
        for (key, value) in patch {
            if let patchDict = value as? [String: Any], let baseDict = result[key] as? [String: Any] {
                result[key] = mergedDictionary(base: baseDict, patch: patchDict)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func value(in dictionary: [String: Any], keyPath: String) -> Any? {
        var current: Any? = dictionary
        for component in keyPath.split(separator: "/") {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[String(component)]
        }
        return current
    }

    private func fileExists(named fileName: String) -> Bool {
        let url = rimePath.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path)
    }

    private func asDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let dec = value as? Decimal { return NSDecimalNumber(decimal: dec).doubleValue }
        return nil
    }

    private func asInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let dec = value as? Decimal { return NSDecimalNumber(decimal: dec).intValue }
        return nil
    }

    private func applyFallbackSnapshot() {
        guard
            let root = try? Yams.load(yaml: Self.fallbackYAML),
            let dictRaw = root as? [String: Any]
        else {
            mergedConfigs = [:]
            return
        }

        let dict = normalizeRimeDictionary(dictRaw)

        mergedConfigs[.default] = dict
        mergedConfigs[.squirrel] = dict
    }

    // MARK: - Dictionary Normalization

    private func normalizeRimeDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        for (key, value) in dictionary {
            if key.contains("/") {
                let components = key.split(separator: "/").map(String.init)
                insert(value: value, for: components[...], into: &normalized)
            } else {
                let normalizedValue = normalizeValue(value)
                if let dictValue = normalizedValue as? [String: Any],
                   let existingDict = normalized[key] as? [String: Any] {
                    normalized[key] = mergedDictionary(base: existingDict, patch: dictValue)
                } else {
                    normalized[key] = normalizedValue
                }
            }
        }
        return normalized
    }

    private func insert(value: Any, for components: ArraySlice<String>, into dictionary: inout [String: Any]) {
        guard let head = components.first else { return }
        if components.count == 1 {
            dictionary[head] = normalizeValue(value)
            return
        }

        var child = dictionary[head] as? [String: Any] ?? [:]
        insert(value: value, for: components.dropFirst(), into: &child)
        dictionary[head] = child
    }

    private func normalizeValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return normalizeRimeDictionary(dict)
        }
        if let array = value as? [[String: Any]] {
            return array.map { normalizeRimeDictionary($0) }
        }
        if let array = value as? [Any] {
            let dicts = array.compactMap { $0 as? [String: Any] }
            if dicts.count == array.count {
                return dicts.map { normalizeRimeDictionary($0) }
            }
        }
        return value
    }
}
