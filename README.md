# 鼠输入法（NanoMouse）

鼠输入法 NanoMouse 是一款面向 iPhone、iPad 的 Rime 与 AI 输入法，并提供 Mac 配套工作区。它把本地输入与纠错、语音成稿、润色翻译、字节粘贴、跨设备剪贴板及创作资料放进连续的输入流程。

[English](./README_EN.md) · [App Store](https://apps.apple.com/app/id6757662900) · [国际官网](https://nanomouse.2nori.com/zh-Hans/) · [中国官网](https://nanomouse.top/zh-Hans/) · [完整功能资料](https://nanomouse.2nori.com/zh-Hans/features/) · [隐私政策](https://nanomouse.2nori.com/zh-Hans/privacy)

> 资料核对：2026 年 11 月 6 日。App Store 当前公开版本为 3.4.7；云端会员服务已更新。3.4.8 客户端专属能力尚不作为已上架功能介绍。功能与界面因设备、系统、地区和版本而异。

**关于此公开仓库：** 本仓库保留历史开放源码，并持续更新产品文档和资源文件。后续 App 开发已转入私有仓库；这里的源码不等同于当前 App Store 完整实现。现有公开文件按各自许可证使用。

## 三支产品预览视频

以下使用 2026 年 10 月 30 日的 App Store 预览交付成片，保留原画面、字幕、剪辑与音轨。点击封面进入独立播放页；每页都有文字说明和原版 MP4。部分场景包含示例账号与演示动画，视频播放时长不代表服务响应速度。

### 01. 智能输入、语音成稿与键盘特效

[<img src="https://nanomouse.2nori.com/media/app-previews/nanomouse-preview-01.jpg" width="220" alt="智能输入、语音成稿与键盘特效" />](https://nanomouse.2nori.com/zh-Hans/videos/01/)

第一支预览展示 NanoMouse 的语音与文字输入、邮件表达调整、Emoji 润色、多语种翻译和动态键盘效果。

[播放与内容说明](https://nanomouse.2nori.com/zh-Hans/videos/01/) · [MP4](https://nanomouse.2nori.com/media/app-previews/nanomouse-preview-01.mp4) · 29.91 秒

### 02. 多语言翻译、连续粘贴与隐私

[<img src="https://nanomouse.2nori.com/media/app-previews/nanomouse-preview-02.jpg" width="220" alt="多语言翻译、连续粘贴与隐私" />](https://nanomouse.2nori.com/zh-Hans/videos/02/)

第二支预览展示输入中文后选择多语种译文、复制外语消息后回译，以及连续取用片段和隐私相关界面。

[播放与内容说明](https://nanomouse.2nori.com/zh-Hans/videos/02/) · [MP4](https://nanomouse.2nori.com/media/app-previews/nanomouse-preview-02.mp4) · 29.91 秒

### 03. 跨设备剪贴板、文本加密与摩斯电码

[<img src="https://nanomouse.2nori.com/media/app-previews/nanomouse-preview-03.jpg" width="220" alt="跨设备剪贴板、文本加密与摩斯电码" />](https://nanomouse.2nori.com/zh-Hans/videos/03/)

第三支预览展示不同 Apple ID 的示例设备间复制、接收与粘贴内容，并展示文本加密面板和电报键盘。

[播放与内容说明](https://nanomouse.2nori.com/zh-Hans/videos/03/) · [MP4](https://nanomouse.2nori.com/media/app-previews/nanomouse-preview-03.mp4) · 26.27 秒

## 当前功能

| 功能 | 具体用途 |
| --- | --- |
| [Rime 中文输入法、本地纠错与多语言键盘](https://nanomouse.2nori.com/zh-Hans/features/keyboard/) | NanoMouse 为 iPhone 和 iPad 提供 Rime 中文输入、中文 26 键与九键、全拼与双拼，并结合中日英输入、本地纠错和可调节的键盘外观。 |
| [键盘内 AI 润色、续写与多语言翻译](https://nanomouse.2nori.com/zh-Hans/features/ai-writing-translation/) | NanoMouse 可以在输入工作流中润色和续写文字，调整篇幅、专业性、语气、情绪、Emoji 与结构，并提供候选翻译和多目标语言翻译。 |
| [语音输入、面对面对话翻译与声音工作室](https://nanomouse.2nori.com/zh-Hans/features/voice/) | NanoMouse 支持语音转文字与文字整理、面对面的双向对话翻译，以及文字转语音、声音选择和多人对白创作。 |
| [字节粘贴：常用语、Prompt 与多类型素材库](https://nanomouse.2nori.com/zh-Hans/features/byte-paste/) | NanoMouse 字节粘贴用固定格子保存常用语、Prompt、富文本、图片、链接、PDF 和文件，让用户在主 App、Mac 与键盘中复用内容。 |
| [iPhone、iPad、Mac 剪贴板与跨 Apple ID 共享](https://nanomouse.2nori.com/zh-Hans/features/clipboard-sync/) | NanoMouse 区分本机剪贴板历史、同 Apple ID 设备同步和受邀请控制的跨 Apple ID 剪贴板通道，适合在个人设备或获授权的协作者之间复用内容。 |
| [Markdown、画布、HTML、思维导图与输入日记](https://nanomouse.2nori.com/zh-Hans/features/workspace-diary/) | NanoMouse 将 Markdown、手写画布、HTML、因果图、思维导图和日记整合到输入工作区，方便保存想法、整理资料并再次调用。 |
| [本地输入、云端 AI、会员与隐私边界](https://nanomouse.2nori.com/zh-Hans/features/privacy-membership/) | NanoMouse 的本地输入、本地纠错、iCloud 同步与云端 AI 是不同的数据通路。免费账号每天有 7 次云端 AI 体验；付费会员按订阅周期使用额度。 |
| [摩斯电码键盘与文本加密面板](https://nanomouse.2nori.com/zh-Hans/features/morse-cipher/) | NanoMouse 的电报键盘提供点划输入与摩斯码转换；独立加密面板按所选算法、参数和口令进行文本加密与破译。 |

## 典型工作流

- **写邮件与聊天回复：** 输入或口述草稿 → 调整表达与结构 → 查看润色或翻译结果 → 在目标 App 中使用。
- **常用 Prompt 与资料：** 在字节粘贴保存角色设定、输出模板、代码、图片或文件 → 在键盘中选择复用。
- **跨设备继续工作：** Mac 复制素材 → 在自己的 iPhone / iPad 中取用；不同 Apple ID 需另行建立邀请共享关系。
- **面对面交流：** 选择双方语言 → 识别语音 → 查看译文并朗读。
- **整理想法：** 使用 Markdown、画布、HTML 或图表工具保存资料；主动开启日记模式后整理记录到的素材。

## 平台边界

| 平台 | 提供内容 |
| --- | --- |
| iPhone / iPad | App Store 主 App 与第三方键盘；不同设备和系统的能力有所区别。 |
| macOS | 配套工作区、字节粘贴、剪贴板和文件工具；系统输入法需要独立安装鼠须管 / Rime。 |
| Windows | 本仓库的小狼毫 / Rime 配置资源，不等同于 iOS / Mac 全功能客户端。 |

## 开始使用

1. 从 [App Store](https://apps.apple.com/app/id6757662900) 安装 NanoMouse。
2. 在 iOS「设置 → 通用 → 键盘 → 键盘 → 添加新键盘」中添加鼠输入法。
3. 在主 App 选择输入方案；需要网络或扩展共享功能时，按指南设置完全访问。
4. 在允许第三方键盘的 App 中，通过地球键切换到 NanoMouse。
5. 在主 App 保存常用内容，再从键盘工具栏打开字节粘贴。

普通文本可通过键盘输入；富文本、图片和文件是否可直接插入取决于目标 App，必要时使用复制、预览、导出或分享。

[完整指南](https://nanomouse.2nori.com/zh-Hans/guide/complete) · [Mac 下载与安装](https://nanomouse.2nori.com/zh-Hans/download) · [支持](https://nanomouse.2nori.com/zh-Hans/support)

## 免费、本地与云端 AI

本地输入和本地纠错不要求 NanoMouse 云端会员，也不扣云端次数。注册免费账号每天有 7 次云端 AI 体验，按北京时间重置；适用任务共用账号账本。有效付费会员使用 Pro 订阅周期额度。当前 3.4.7 及更早客户端的免费账号第 8 次起按旧版权限与限制处理；付费会员统一使用 Pro 规则。

云端模型和服务会随账号与配置变化。支持的自带 Key 直连由用户自行承担供应商费用；不扣 NanoMouse 云端额度。请以账号页面和购买页面确认具体权益与价格。

## 数据与隐私

基础输入、本地纠错、iCloud 同步和联网 AI 是不同功能。跨 Apple ID 剪贴板需要邀请接受，不会自动公开全部私有格子。语音录音由主 App 处理；云端 AI 任务会按所选通道处理相关文本、图片或音频。

[隐私政策](./PRIVACY.md) · [Privacy Policy](./PRIVACY_EN.md)

## 历史源码与配置资源

- [iOS](./ios/) · [macOS](./mac/) · [Windows](./windows/)
- [Rime 配置](./configs/) · [共享资源](./shared/) · [资源包](./zips/)
- [许可证](./LICENSE)

部分历史构建说明与当前 App 版本不同，请以相应目录的文档为准。

## 致谢

- [Rime](https://rime.im/)
- [Squirrel](https://github.com/rime/squirrel) / [Weasel](https://github.com/rime/weasel)
- [Hamster](https://github.com/imfuxiao/Hamster)
- [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit)
- [Rime Ice](https://github.com/iDvel/rime-ice)
