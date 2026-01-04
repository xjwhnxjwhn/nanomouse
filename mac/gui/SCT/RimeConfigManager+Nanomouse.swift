import Foundation
import Yams

extension RimeConfigManager {
    func nanomousePresetIsEnabled(_ preset: NanomousePreset) -> Bool {
        return withSecurityScopedAccess {
            let fileURL = rimePath.appendingPathComponent(preset.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }

            let root = loadNanomouseYamlRoot(from: fileURL)
            let patch = root["patch"] as? [String: Any] ?? [:]
            let currentRules = nanomouseAlgebraRules(from: patch).rules
            return preset.rules.allSatisfy { currentRules.contains($0) }
        }
    }

    func setNanomousePreset(_ preset: NanomousePreset, enabled: Bool) {
        withSecurityScopedAccess {
            let fileURL = rimePath.appendingPathComponent(preset.fileName)
            var root = loadNanomouseYamlRoot(from: fileURL)
            var patch = root["patch"] as? [String: Any] ?? [:]

            let (currentRules, style) = nanomouseAlgebraRules(from: patch)
            var updatedRules = currentRules

            // 为了避免覆盖用户自定义，这里只增删 Nanomouse 规则，其他 patch 保持不变。
            if enabled {
                for rule in preset.rules where !updatedRules.contains(rule) {
                    updatedRules.append(rule)
                }
            } else {
                updatedRules.removeAll { preset.rules.contains($0) }
            }

            if updatedRules == currentRules {
                statusMessage = String(format: L10n.nanomouseNoChange, preset.displayName)
                return
            }

            patch = writeNanomouseAlgebraRules(patch, rules: updatedRules, style: style, allowCreate: enabled)
            root["patch"] = patch

            saveNanomouseYamlRoot(root, to: fileURL)
            statusMessage = String(format: enabled ? L10n.nanomouseEnabled : L10n.nanomouseDisabled, preset.displayName)
        }

        loadConfig()
    }
}

private enum NanomouseAlgebraStyle {
    case flat
    case nested
    case none
}

private func nanomouseAlgebraRules(from patch: [String: Any]) -> (rules: [String], style: NanomouseAlgebraStyle) {
    if let flatRules = patch["speller/algebra/+"] as? [String] {
        return (flatRules, .flat)
    }
    if let flatRules = patch["speller/algebra/+"] as? [Any] {
        return (flatRules.compactMap { $0 as? String }, .flat)
    }

    if let speller = patch["speller"] as? [String: Any],
       let algebra = speller["algebra"] as? [String: Any] {
        if let nestedRules = algebra["+"] as? [String] {
            return (nestedRules, .nested)
        }
        if let nestedRules = algebra["+"] as? [Any] {
            return (nestedRules.compactMap { $0 as? String }, .nested)
        }
    }

    return ([], .none)
}

private func writeNanomouseAlgebraRules(
    _ patch: [String: Any],
    rules: [String],
    style: NanomouseAlgebraStyle,
    allowCreate: Bool
) -> [String: Any] {
    var updatedPatch = patch

    switch style {
    case .flat:
        if rules.isEmpty {
            updatedPatch.removeValue(forKey: "speller/algebra/+")
        } else {
            updatedPatch["speller/algebra/+"] = rules
        }

    case .nested:
        var speller = updatedPatch["speller"] as? [String: Any] ?? [:]
        var algebra = speller["algebra"] as? [String: Any] ?? [:]

        if rules.isEmpty {
            algebra.removeValue(forKey: "+")
        } else {
            algebra["+"] = rules
        }

        if algebra.isEmpty {
            speller.removeValue(forKey: "algebra")
        } else {
            speller["algebra"] = algebra
        }

        if speller.isEmpty {
            updatedPatch.removeValue(forKey: "speller")
        } else {
            updatedPatch["speller"] = speller
        }

    case .none:
        if allowCreate, !rules.isEmpty {
            updatedPatch["speller/algebra/+"] = rules
        }
    }

    return updatedPatch
}

private func loadNanomouseYamlRoot(from url: URL) -> [String: Any] {
    guard FileManager.default.fileExists(atPath: url.path),
          let contents = try? String(contentsOf: url, encoding: .utf8),
          let root = try? Yams.load(yaml: contents) as? [String: Any] else {
        return [:]
    }

    return root
}

private func saveNanomouseYamlRoot(_ root: [String: Any], to url: URL) {
    do {
        let yaml = try Yams.dump(object: root, width: -1, allowUnicode: true, sortKeys: true)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        print("Debug: 保存 Nanomouse 方案失败: \(error.localizedDescription)")
    }
}
