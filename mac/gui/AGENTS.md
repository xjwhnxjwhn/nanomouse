# Squirrel Configuration Tool (SCT) - Agent Guide

This document serves as a project overview and design record for AI agents working on the Squirrel (鼠须管) configuration GUI.

## Project Overview
The goal is to provide a native macOS GUI for configuring the Squirrel input method, which traditionally requires manual editing of YAML files in `~/Library/Rime`.

## Core Design Philosophy
**"Respect Rime Logic, Simplify User Operation"**
- **Non-Destructive**: Never modify default `.yaml` files. All changes must be written to `.custom.yaml` files under the `patch:` key.
- **Native Experience**: Use SwiftUI and macOS design patterns to make configuration feel like a first-class system setting.
- **Transparency**: Users should be able to see what YAML changes are being made.

## Key Design Decisions

### 1. Dual-Layer Configuration Model
- **Base Layer**: `default.yaml`, `squirrel.yaml` (Read-only).
- **Patch Layer**: `default.custom.yaml`, `squirrel.custom.yaml` (Read/Write).
- **Merged View**: The GUI displays the result of merging the Patch Layer into the Base Layer.

### 2. Technology Stack
- **Language**: Swift 6.0+
- **Framework**: SwiftUI (Targeting latest macOS)
- **YAML Engine**: [Yams](https://github.com/jpsim/Yams) for robust YAML parsing and serialization.
- **Markdown Engine**: [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) for rich help documentation rendering.

### 3. Configuration Merging Logic
Rime's patch system supports:
- Simple key-value replacement.
- Nested key access (e.g., `style/font_face`).
- Array manipulation (though SCT currently focuses on full array replacement for simplicity).

### 4. Color Handling
Rime uses **BGR** (Blue-Green-Red) hex format (e.g., `0xBBGGRR`). SCT must:
- Convert BGR to `SwiftUI.Color` for the UI.
- Convert `SwiftUI.Color` back to BGR for saving.

## Functional Modules

### General Settings
- `menu/page_size`: Number of candidates.
- `schema_list`: Selection and ordering of input schemas.
- `ascii_composer`: Behavior of Shift/Caps Lock keys.

### Appearance (The "Skin" Module)
- **Skin Selection**: Browse and apply `preset_color_schemes`.
- **Live Preview**: A simulated candidate window that reflects font, color, and layout changes in real-time.
- **Font Management**: Selection of system fonts and point sizes.

### App-Specific Settings
- `app_options`: Manage `ascii_mode` (default English) for specific applications (e.g., Terminal, Xcode).

### Shortcuts
- `switcher/hotkeys`: Record and manage global activation hotkeys.

## Technical Implementation Details

### Deployment Mechanism
After saving changes, Squirrel needs to "Deploy" to apply them.
- **Method**: Triggered via a "Deploy" button in the GUI.
- **Implementation**: Execute `/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel --reload` or touch the config files.

### File Monitoring
- Monitor `~/Library/Rime` for external changes to keep the GUI in sync.
- Automatically scan `~/Library/Rime` for `*.schema.yaml` files to populate the available schema list, ensuring user-added schemas are recognized.

### Sandbox & File Access
- During development we disable the App Sandbox so SCT can access the real `~/Library/Rime` path for schema testing.
- Before shipping we must re-enable the sandbox and build a security-scoped file access flow (e.g., prompting for `~/Library/Rime` and persisting the bookmark).

## Configuration Grouping Decisions
1. Input Schemes: expose `schema_list` plus the primary `switcher` fields (hotkeys/save_options/fold_options/abbreviate_options/option_list_separator); uncommon keys stay in Advanced YAML mode.
2. Candidate Panel: manage every `menu` and `style` sub-key, including memorize_size/mutual_exclusive/translucency/show_paging. `keyboard_layout`/`chord_duration`/`show_notifications_when` keep their defaults and do not need GUI.
3. Input Behaviors: give `ascii_composer` its own module; keep `punctuator` and `recognizer` in the YAML editor only; surface only the frequently used `key_binder` mappings (commit-first/last, paging, etc.).
4. App Options: the `app_options` table shows four toggle columns (ascii_mode/inline/no_inline/vim_mode) and can grow if we add more flags later.
5. Skins: preset color schemes remain read-only for now; a richer "skin editor" may come later for advanced users.
6. YAML Editor: must display the merged base+patch view, highlight patched values, support filtering to "customized only", provide search, and let users enable/disable individual patches with a split/diff view concept.
7. Sandbox Strategy: keep App Sandbox disabled during development to access real `~/Library/Rime`; re-enable it before release and request that directory via security-scoped bookmarks.
8. Navigation Layout: the macOS UI keeps the `NavigationSplitView` structure from `ContentView.swift`, mapping each group above to a dedicated sidebar item; `SchemaDrivenView` is only a prototype surface, not the final container for every feature.

## Advanced YAML Editor Design
The "Advanced Settings" tab is designed as a **Smart Configuration Browser** to bridge the gap between GUI and raw YAML editing.

### 1. Merged View with Source Attribution
- Displays the final effective configuration tree.
- **Visual Distinction**: Base values (from `default.yaml`) are shown in a neutral style, while patched values (from `.custom.yaml`) are highlighted (e.g., blue text or background).
- **Source Labels**: Each entry indicates whether it's a "Default" or "Customized" value.

### 2. Interaction Model
- **Search & Filter**: Global search by key path or value. A "Modified Only" toggle to quickly audit user changes.
- **One-Click Customization**: For any default value, a "Customize" button adds it to the patch dictionary and opens it for editing.
- **One-Click Reset**: For any customized value, a "Reset" button removes it from the patch, reverting to the base value.

### 3. Editor Types
- **Type-Aware UI**: Automatically provides appropriate controls (Toggle for Bool, Stepper for Int, TextField for String).
- **Source Fallback**: For complex types (nested objects or arrays), provides a mini YAML source editor.
- **Full Source Mode**: A dedicated sub-tab for direct editing of the `.custom.yaml` file with syntax validation.

### 4. Advanced Settings Refinement (2025-12-19)
- **Duplicate Entry Fix**: Resolved an issue where customized keys appeared twice by ensuring the patch dictionary is normalized (nested) before merging into the base configuration.
- **Unified Text Editor**: Replaced type-specific controls (Toggle, Stepper, etc.) with a consistent `TextField` for all values in the Advanced view. This provides a more "pro" feel and avoids UI clutter.
- **Smart Parsing**: Implemented a `parseValue` helper to automatically convert text input back to `Bool`, `Int`, or `Double` where appropriate, maintaining YAML type integrity.
- **Reset Logic Fix**: Corrected the order of operations in `removePatch` to ensure changes are saved to disk before reloading the configuration, fixing the issue where the reset button had no effect.
- **UX Polish**:
    - Fixed label wrapping in the header.
    - Enabled full-row click to focus the editor.
    - Implemented "Select All" on focus for faster editing.

## Refinement and Cleanup (2025-12-20)
- **Permission Management Refactoring**: Created `withSecurityScopedAccess` helper in `RimeConfigManager` to centralize sandbox access logic and reduce redundancy.
- **UI String Consolidation**: Cleaned up `L10n.swift`, consolidated similar strings (e.g., `saveSuccess`), and moved remaining hardcoded strings (like "When", "Accept", "default.yaml") to the localization file.
- **Code Cleanup**: Removed unused methods like `updateVirtualHotkeys` and ensured consistent use of `L10n` across all views.
- **Technical String Reversion**: Reverted `key_binder` related strings (`when`, `accept`, `always`, `composing`, etc.) to their technical English terms in `L10n.swift`. This maintains consistency with Rime's engine terminology and official documentation, as these are considered "special key names" rather than user-facing labels.
- **Placeholder Retention**: Decided to retain `KeyBinderControl` in `SchemaDrivenView.swift` as a placeholder for future complex shortcut management features, even though it is currently unused by `ConfigSchema.json`.

## Distribution & Update Strategy (Finalized 2025-12-21)

### 1. Core Stack
- **Hosting**: GitHub Releases (for binaries and metadata).
- **Update Engine**: [Sparkle 2](https://sparkle-project.org/).
- **Automation**: GitHub Actions.

### 2. Release Workflow
1. **Trigger**: Developer pushes a git tag (e.g., `v1.0.0`).
2. **Build**: GitHub Actions runner builds the project using `xcodebuild`.
3. **Sign & Notarize**: 
   - Sign with Apple Developer ID Certificate.
   - Notarize using `notarytool` to ensure macOS allows execution.
4. **Package**: Create a DMG using `create-dmg`.
5. **Metadata**: Generate/Update `appcast.xml` using Sparkle's `generate_appcast` tool. The tool is configured to use the GitHub Release download URL as the prefix.
6. **Sync**: Automatically commit and push the updated `appcast.xml` back to the `main` branch.
7. **Publish**: Upload the DMG to the GitHub Release. (Note: `appcast.xml` is served via GitHub Raw from the `main` branch, not as a release asset).

### 3. Setup Instructions for Developer

#### A. Xcode Project Setup
1. **Add Sparkle**: Add `https://github.com/sparkle-project/Sparkle` as a Swift Package dependency.
2. **Info.plist Keys**: Add the following keys to your target's "Info" tab or `Info.plist`:
   - `SUFeedURL`: `https://raw.githubusercontent.com/YOUR_USERNAME/sct/main/appcast.xml` (Points to the file in your `main` branch).
   - `SUPublicEDKey`: (The public key generated in step B).
3. **Hardened Runtime**: Ensure "Hardened Runtime" is enabled in "Signing & Capabilities".
4. **Sandbox Entitlements**: For Sparkle to work within the App Sandbox, add the following to `SCT.entitlements`:
   - `com.apple.security.network.client`: `true` (To check for updates).
   - `com.apple.security.temporary-exception.mach-lookup.global-name`: An array containing `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki` (Required for Sparkle's inter-process communication).

#### B. Sparkle Keys
1. Download the Sparkle distribution and run `./bin/generate_keys` to generate `ed25519` keys.
2. Copy the **Public Key** to the `SUPublicEDKey` in Xcode.
3. Keep the **Private Key** secure (it will be needed in GitHub Secrets).

#### C. Certificate & Provisioning
1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list).
2. Create a **Developer ID Application** certificate.
3. Download and install it in your Keychain.
4. In Xcode, under "Signing & Capabilities", select your Team and ensure "Developer ID" is selected for the Release configuration.

#### D. GitHub Secrets
Add the following to your repository settings under **Settings > Secrets and variables > Actions**:

1.  **`CERTIFICATE_P12`**:
    - **获取方式**: 在 Mac 上打开“钥匙串访问” (Keychain Access)，找到你的 **Developer ID Application** 证书。
    - **关键步骤**: 点击证书左侧的箭头展开，**同时选中证书及其下方的专用密钥 (Private Key)**。
    - **导出**: 右键点击 -> 导出 (Export)，此时即可选择 `.p12` 格式。保存并设置一个导出密码。
    - **编码**: 在终端运行 `base64 -i YourCert.p12 | pbcopy`，将剪贴板中的 Base64 字符串粘贴到 Secret 中。
2.  **`CERTIFICATE_PASSWORD`**: 导出 `.p12` 文件时设置的密码。
3.  **`KEYCHAIN_PASSWORD`**: 任意随机字符串（用于 CI 环境中临时创建的钥匙串，例如 `openssl rand -base64 12`）。
4.  **`APPLE_ID`**: 你的 Apple ID 邮箱地址。
5.  **`APPLE_PASSWORD`**: 
    - **获取方式**: 登录 [appleid.apple.com](https://appleid.apple.com)。
    - **生成**: 在“App 专用密码” (App-Specific Passwords) 栏目下点击“生成”，获取一个形如 `xxxx-xxxx-xxxx-xxxx` 的密码。
6.  **`TEAM_ID`**: 
    - **获取方式**: 登录 [developer.apple.com/account](https://developer.apple.com/account)。
    - **查看**: 在页面下方的 **Membership Details** 中找到 **Team ID** (10位字母数字组合)。
7.  **`SPARKLE_PRIVATE_KEY`**:
    - **获取方式**: 运行 Sparkle 工具包中的 `./bin/generate_keys`。
    - **查看**: 该命令会输出 `Private key` 和 `Public key`。将 `Private key` 的内容完整复制到此 Secret 中。

## Plan and Progress
- [x] Initial project scaffolding (2025-12-18).
- [x] Basic `RimeConfigManager` structure for YAML handling (2025-12-18).
- [x] UI prototype with `NavigationSplitView` sidebar and basic forms (2025-12-18).
- [x] Integration with `Yams` library (2025-12-18).
- [x] Robust patch merging implementation (2025-12-18).
- [x] BGR <-> RGB color conversion utility (2025-12-18).
- [x] Schema-driven UI generation to support future Rime features without code changes.
- [x] Schema expansion: update ConfigSchema.json per the grouping decisions and expose values via RimeConfigManager (2025-12-18).
- [x] Navigation UI: wire each configuration group to its own NavigationSplitView destination; keep SchemaDrivenView as a prototype surface (2025-12-18).
- [x] Key binder view: build UI for common bindings (commit-first/last, prev/next, paging) and persist changes (2025-12-19).
- [x] App options table: support add/remove rows with ascii_mode/inline/no_inline/vim_mode toggles plus validation and sorting (2025-12-19).
- [x] App selection: allow users to select apps from /Applications to get Bundle ID (2025-12-19).
- [x] UI Polish: rename "App Options" to "应用程序" and "Bundle ID" to "应用程序 ID" (2025-12-19).
- [x] YAML editor prototype: merged + diff views, search/filter, and an Enable Customization switch per entry (2025-12-19).
- [x] Advanced "Source Code" mode for direct YAML editing (2025-12-19).
- [x] Sandbox reactivation: re-enable App Sandbox, request `~/Library/Rime` access, persist the bookmark, retest reload/deploy (2025-12-20).
- [x] Documentation and user friendly help within the app (Added HelpView and field descriptions) (2025-12-20).
- [x] UI String Consolidation: Created `L10n.swift` to centralize static UI strings and moved Help content to `Help.md` (2025-12-20).
- [x] Markdown-based Help system: Refactored `HelpView` to load content from an external `Help.md` file for easier maintenance (2025-12-20).
- [x] Fix Markdown rendering: Integrated `MarkdownUI` library for professional rendering of headers, lists, and GitHub Flavored Markdown (2025-12-20).
- [x] Configuration backup strategy and mechanism (2025-12-21).
- [x] Undo/Redo capability (2025-12-21).
- [x] Sparkle 2 integration for auto-updates (2025-12-21).
- [x] GitHub Actions CI/CD pipeline setup (2025-12-21).
- [x] Final polish and distribution preparation (2025-12-21).

## Post-1.0.0 Cleanup and Refactoring (2025-12-22)

### 1. Redundancy Removal
- **RimeConfigManager**: Removed unused `@Published` properties (`pageSize`, `colorScheme`, `fontFace`, `fontPoint`, `schemaList`) and the `AppOption` struct. These were remnants of early prototypes and are now handled dynamically via `mergedConfigs` and `ConfigSchema.json`.
- **Logic Consolidation**: Deleted `applyMergedValues()` as it was only responsible for syncing the now-removed properties.

### 2. Code Architecture Improvements
- **Saving Logic**: Extracted `loadPatchRoot` and `savePatchRoot` in `RimeConfigManager` to centralize YAML file operations and reduce duplication between `saveToPatch` and `saveFullPatch`.
- **UI Bindings**: Implemented a generic `binding(for:domain:defaultValue:)` helper in `SchemaFieldRow` to eliminate repetitive `Binding(get:set:)` boilerplate across different control types.
- **Model Extensions**: Moved `SchemaField` convenience extensions (`minInt`, `maxInt`, `defaultInt`) from `SchemaDrivenView.swift` to `SchemaStore.swift` to keep model logic closer to the data definition.

### 3. Performance & Robustness
- **Caching**: Retained `choicesCache` and `labelsCache` but ensured they are cleared appropriately during config reloads.
- **Type Safety**: Improved `asInt` and `asDouble` helpers to handle `Decimal` types returned by Yams, preventing potential type mismatch crashes.

### 4. CI/CD Pipeline Enhancements
- **Build With Latest SDK**: force GitHub use `macos-26` runner to ensure compatibility with the latest macOS SDK.