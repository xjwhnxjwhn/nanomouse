# Nanomouse Pinyin Input Method

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20iOS-blue.svg)](#supported-platforms)

🐭 Tiny pinyin key mapping optimizations for easier typing!

[中文说明](./README.md)

## ✨ Features

### Nasal Sound Simplification (ng → nn)
| Input | Original | Example |
|-------|----------|---------|
| `dann` | dang | 当 (dāng) |
| `henn` | heng | 恒 (héng) |
| `dinn` | ding | 定 (dìng) |

### Key Position Optimization (uan/uang → vn/vnn)
| Input | Original | Example |
|-------|----------|---------|
| `gvn` | guan | 关 (guān) |
| `gvnn` | guang | 光 (guāng) |
| `chvnn` | chuang | 床 (chuáng) |

**Why "Nanomouse"?**
- nano = Tiny (just a few lines of config)
- mouse = Following Rime's tradition of small animal naming

## 📥 Installation

### macOS

1. Download [Nanomouse-Installer.dmg](https://github.com/xjwhnxjwhn/nanomouse/releases/latest)
2. Open DMG and run the installer
3. Follow the prompts

> 💡 If Squirrel is not installed, the installer will guide you (supports Homebrew auto-install)

> ✅ **Safe Installation**: If you have existing Rime customizations, the installer will automatically backup and merge, not overwrite your settings.

### Windows

1. Install [Weasel](https://rime.im/download/)
2. Download config files and copy to `%APPDATA%\Rime`
3. Right-click taskbar icon → Deploy

### iOS

The iOS version source code is located in the `ios/` directory. Please check the [iOS README](./ios/README.md) for build and run instructions.

### macOS

The macOS configuration tool is located in the `mac/gui/` directory, providing a simple graphical interface for configuration.

## 🔧 Manual Installation

Copy these files to your Rime user directory and deploy:

**Select based on your input schema:**

| Input Schema | Config File |
|--------------|-------------|
| Luna Pinyin | `luna_pinyin_simp.custom.yaml` |
| Rime Ice | `rime_ice.custom.yaml` |
| Double Pinyin (Ziranma) | `double_pinyin.custom.yaml` |
| Double Pinyin (Flypy) | `double_pinyin_flypy.custom.yaml` |

Also copy `default.custom.yaml` to set Simplified Chinese as default.

**Rime user directory:**
- macOS: `~/Library/Rime/`
- Windows: `%APPDATA%\Rime`

> ⚠️ **Note**: Manual installation will overwrite files with the same name. Please backup your config first.

## 🔄 Uninstall / Restore

To restore your original config:
1. Open `~/Library/Rime/`
2. Find the `nanomouse_backup_*` folder
3. Copy files back to `~/Library/Rime/`
4. Deploy again

## 📄 License

[MIT License](./LICENSE)

## 🙏 Acknowledgments

- [RIME Input Method Engine](https://rime.im/)
- [Squirrel](https://github.com/rime/squirrel)
- [Weasel](https://github.com/rime/weasel)
- [Hamster](https://github.com/imfuxiao/Hamster)
