# Nanomouse Input Method

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20iOS-blue.svg)](#platform-support)

🐭 **Cross-platform Pinyin input optimization — type faster, type easier**

[中文说明](./README.md) | [隐私政策](./PRIVACY.md) | [Privacy Policy](./PRIVACY_EN.md)

---

## 🎯 Why Nanomouse?

**Tired of awkward key combinations when typing Pinyin?** Nanomouse solves the biggest pain points with minimal changes:

| Pain Point | Nanomouse Solution | Result |
|------------|-------------------|--------|
| `ang/eng/ing` nasal finals need 2 keys | `nn` replaces `ng` | `dann` → 当, one less keystroke |
| `uan/uang` requires finger stretching | `vn/vnn` replaces them | `gvn` → 关, fingers stay home |

**That's it.** No learning curve, just smoother typing for high-frequency patterns.

---

## 🖥️ Platform Support

### macOS — Squirrel + SCT GUI Configuration

**One-click install:** Download [Nanomouse-Installer.dmg](https://github.com/xjwhnxjwhn/nanomouse/releases/latest) and run.

**SCT Configuration Tool** — Say goodbye to manual YAML editing:

- 🎨 Native SwiftUI interface, feels right at home on macOS
- 🔒 Non-invasive config: all changes go to `.custom.yaml`, safe across Squirrel upgrades
- ↩️ Multi-level Undo/Redo + auto-backup, experiment freely
- ⚡ Advanced mode: search and modify any Rime config option directly
- 🔄 Built-in Sparkle auto-updates

> 💡 Squirrel not installed? The installer guides you through one-click Homebrew installation
>
> ✅ Have existing customizations? Auto-backup and smart merge, never overwrites

---

### iOS — A Full-Featured Keyboard App

Built on [Hamster](https://github.com/imfuxiao/Hamster), this isn't just a config — it's **a complete iOS keyboard app**.

**Key Features:**

| Feature | Description |
|---------|-------------|
| 📱 **Native Keyboard Feel** | Key bubbles, haptic feedback, smooth like system keyboard |
| 🔤 **Long-Press Accent Menu** | Hold any key for extended characters, slide to select with haptics |
| 🔢 **Long-Press Numeric Keypad** | Hold `123` key for quick number input without switching layouts |
| 🌐 **CN/JP/EN Quick Switch** | Long-press globe key, instant language switching |
| 📝 **System Text Replacement** | Auto-syncs with iOS Settings > General > Keyboard > Text Replacement |
| 🎌 **Multiple Schemas** | Rime Ice, Double Pinyin, Japanese Romaji, Stroke input... |

**Built-in Input Schemas:**
- Rime Ice (rime-ice) — Modern Pinyin
- Terra Pinyin (terra-pinyin)
- Japanese Romaji (jaroomaji)
- Stroke Input (stroke)
- Vietnamese (hannomps)
- Korean (hangyl)

Source code: `ios/` directory | [Build instructions](./ios/README.md)

---

### Windows — Weasel

1. Install [Weasel](https://rime.im/download/)
2. Download config files from `configs/` to `%APPDATA%\Rime`
3. Right-click taskbar icon → Deploy

---

## ⌨️ Key Mapping Quick Reference

### Nasal Sound Simplification (ng → nn)

| Input | Original | Example |
|-------|----------|---------|
| `dann` | dang | 当 (dāng) |
| `henn` | heng | 恒 (héng) |
| `dinn` | ding | 定 (dìng) |
| `tonn` | tong | 同 (tóng) |

### Key Position Optimization (uan/uang → vn/vnn)

| Input | Original | Example |
|-------|----------|---------|
| `gvn` | guan | 关 (guān) |
| `hvn` | huan | 换 (huàn) |
| `gvnn` | guang | 光 (guāng) |
| `chvnn` | chuang | 床 (chuáng) |

> **How it works:** `v` is already used for `ü` in Pinyin, and combinations like `gv` don't exist in `guan/guang`, making `vn/vnn` conflict-free shortcuts.

---

## 🔧 Manual Installation (Advanced)

Copy config files to your Rime user directory and deploy:

| Input Schema | Config File |
|--------------|-------------|
| Luna Pinyin | `luna_pinyin_simp.custom.yaml` |
| Rime Ice | `rime_ice.custom.yaml` |
| Double Pinyin (Ziranma) | `double_pinyin.custom.yaml` |
| Double Pinyin (Flypy) | `double_pinyin_flypy.custom.yaml` |

**Rime user directory:**
- macOS: `~/Library/Rime/`
- Windows: `%APPDATA%\Rime`

Config example:
```yaml
# luna_pinyin_simp.custom.yaml
patch:
  "speller/algebra/+":
    - derive/ng$/nn/      # ng → nn
    - derive/uan$/vn/     # uan → vn
    - derive/uang$/vnn/   # uang → vnn
```

---

## 📁 Project Structure

```
nanomouse/
├── configs/          # Desktop Rime config files
├── shared/           # Cross-platform shared configs
├── ios/              # iOS Keyboard App (full Xcode project)
├── mac/
│   ├── gui/          # SCT Config Tool (SwiftUI App)
│   └── install.sh    # CLI install script
├── windows/          # Windows related
├── installers/       # macOS installer
└── build/            # Build artifacts
```

---

## 🔄 Uninstall / Restore

To restore original config:
1. Open `~/Library/Rime/`
2. Find `nanomouse_backup_*` folder
3. Copy files back to `~/Library/Rime/`
4. Deploy again

---

## 🤝 Contributing

Issues and Pull Requests welcome!

---

## 📄 License

[MIT License](./LICENSE)

---

## 🙏 Acknowledgments

- [RIME Input Method Engine](https://rime.im/) — Powerful cross-platform input framework
- [Squirrel](https://github.com/rime/squirrel) — macOS Rime frontend
- [Weasel](https://github.com/rime/weasel) — Windows Rime frontend
- [Hamster](https://github.com/imfuxiao/Hamster) — iOS Rime implementation
- [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit) — iOS keyboard framework
- [Rime Ice](https://github.com/iDvel/rime-ice) — Well-maintained Pinyin dictionary

---

**Why "Nanomouse"?**
- **nano** = Tiny — just a few lines of config
- **mouse** = Following Rime's small animal naming tradition (Squirrel, Hamster...)
