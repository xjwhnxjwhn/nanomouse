# Nanomouse 拼音输入法

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20iOS-blue.svg)](#支持平台)

🐭 小巧的拼音键位优化配置，让打字更顺手！

[English](./README_EN.md)

## ✨ 功能

### 后鼻音简化 (ng → nn)
| 输入 | 原拼音 | 示例 |
|------|--------|------|
| `dann` | dang | 当、档、党 |
| `henn` | heng | 恒、横、衡 |
| `dinn` | ding | 定、顶、钉 |

### 键位优化 (uan/uang → vn/vnn)
| 输入 | 原拼音 | 示例 |
|------|--------|------|
| `gvn` | guan | 关、官、管 |
| `gvnn` | guang | 光、广、逛 |
| `chvnn` | chuang | 床、窗、创 |

**为什么叫 Nanomouse？**
- nano = 纳米级小巧（配置文件只有几行）
- mouse = 融入 Rime 生态的小动物命名传统

## 📥 下载安装

### macOS

1. 下载 [Nanomouse-Installer.dmg](https://github.com/xjwhnxjwhn/nanomouse/releases/latest)
2. 打开 DMG，双击「Nanomouse 安装器」
3. 按提示完成安装

> 💡 如果未安装鼠须管，安装器会自动引导安装（支持 Homebrew 自动安装）

> ✅ **安全安装**：如果你已有 Rime 自定义配置，安装器会自动备份并智能合并，不会覆盖你的设置。

### Windows

1. 先安装 [小狼毫 (Weasel)](https://rime.im/download/)
2. 下载配置文件，复制到 `%APPDATA%\Rime`
3. 右键任务栏图标 → 重新部署

### iOS（即将推出）

iOS 版本正在开发中，敬请期待。

## 🔧 手动安装

将配置文件复制到 Rime 用户目录，然后重新部署：

**根据你使用的输入方案选择：**

| 输入方案 | 配置文件 |
|----------|----------|
| 明月拼音 | `luna_pinyin_simp.custom.yaml` |
| 雾凇拼音 | `rime_ice.custom.yaml` |

还需复制 `default.custom.yaml` 设置默认使用简体中文。

**Rime 用户目录：**
- macOS: `~/Library/Rime/`
- Windows: `%APPDATA%\Rime`

> ⚠️ **注意**：手动安装会覆盖同名文件，请先备份你的配置。

## 📁 配置说明

```yaml
# luna_pinyin_simp.custom.yaml
patch:
  "speller/algebra/+":
    - derive/ng$/nn/      # ng → nn
    - derive/uan$/vn/     # uan → vn
    - derive/uang$/vnn/   # uang → vnn
```

## 🔄 卸载 / 恢复

如需恢复原配置：
1. 打开 `~/Library/Rime/`
2. 找到 `nanomouse_backup_*` 文件夹
3. 将里面的文件复制回 `~/Library/Rime/`
4. 重新部署

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

[MIT License](./LICENSE)

## 🙏 致谢

- [RIME 输入法引擎](https://rime.im/)
- [鼠须管](https://github.com/rime/squirrel)
- [小狼毫](https://github.com/rime/weasel)
- [仓输入法](https://github.com/imfuxiao/Hamster)
