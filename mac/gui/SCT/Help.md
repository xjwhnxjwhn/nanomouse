**Nanomouse GUI - Squirrel Configuration Tool**

**核心理念：尊重 Rime 逻辑，简化用户操作**

- **非破坏性**：Nanomouse GUI 永远不会修改 Rime 的默认配置文件（`default.yaml` 和 `squirrel.yaml`），所有更改都写入 `default.custom.yaml` 或 `squirrel.custom.yaml` 的 `patch` 键下。
- **原生体验**：使用 SwiftUI 构建，提供原生 macOS 体验。
- **透明度**：您可以在“高级设置”中随时查看合并后的 YAML 配置。

**常见问题**

1. 为什么我的更改没有生效？

   在 Nanomouse GUI 中修改配置后，您需要点击工具栏上的“部署”按钮（或使用快捷键 `Cmd+R`），这会触发 Squirrel 重新加载配置。

2. 如何添加新的输入方案？

   在“输入方案”页面，点击底部的“添加新方案”按钮，输入方案 ID（如 `rime_ice`）和名称，Nanomouse GUI 会自动为您创建基础的方案文件并将其添加到激活列表中。

3. 什么是“高级设置”？

   “高级设置”允许您浏览 Rime 的完整配置树，您可以直接修改其中的任何值，Nanomouse GUI 会自动将其添加到对应的 `.custom.yaml` 文件中。注意：这是一个只面向高级用户的功能，如果你不确定你是不是该使用它那就尽量不要用，仅使用本工具提供的其他页面来编辑常用的配置项。

4. 沙盒访问权限

   Nanomouse GUI 会读写你的 Squirrel 配置文件，它们通常位于 `~/Library/Rime` 目录下；为了安全地访问 `~/Library/Rime` 目录，Nanomouse GUI 需要您的授权；如果您移动了 Rime 目录，可以在此处重新授权。
