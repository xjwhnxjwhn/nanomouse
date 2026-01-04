import Foundation

/// Centralized UI strings for localization and easier maintenance.
struct L10n {
    // Sidebar & Navigation
    static let appTitle = "Nanomouse 配置"
    static let nanomouse = "Nanomouse"
    static let schemes = "输入方案"
    static let panel = "候选词面板"
    static let behaviors = "输入行为"
    static let apps = "应用程序"
    static let advanced = "高级设置"
    static let help = "帮助"
    static let selectItem = "请选择一个项目"
    static let sctWebsite = "Nanomouse GitHub"
    static let squirrelWebsite = "Squirrel 官网"
    static let checkForUpdates = "检查更新..."

    // Status Messages
    static let loadingConfig = "正在读取配置..."
    static let loadingSchemas = "正在读取方案..."
    static let accessRequired = "需要访问 ~/Library/Rime 目录的权限"
    static let accessDenied = "无权限访问 Rime 目录"
    static let deployTriggered = "已触发重新部署"
    static let deployFailed = "部署失败，尝试更新文件时间戳..."
    static let timestampUpdated = "已更新文件时间戳"
    static let deployHelp = "重新部署 Squirrel 以应用更改"
    static let authFailed = "授权失败：%@"
    static let usingExampleConfig = "使用示例配置"
    static let readPath = "已读取 %@"
    static let schemaAdded = "已添加方案: %@"
    static let schemaAddFailed = "创建方案失败: %@"
    static let schemaDeleted = "已删除方案文件并清理配置: %@"
    static let configCleaned = "已清理配置: %@"
    static let schemaDeleteFailed = "删除方案失败: %@"
    static let saveSuccess = "已保存 %@"
    static let saveFailed = "保存失败：%@"

    // Access Request
    static let accessTitle = "需要访问 Rime 配置目录"
    static let accessDescription = "为了读取和修改您的 Squirrel 配置，Nanomouse GUI 需要访问您的 Rime 目录（通常位于 ~/Library/Rime）。"
    static let accessButton = "授权访问 ~/Library/Rime"
    static let accessFooter = "您的授权将被安全地存储，以便下次自动访问。"
    static let accessPrompt = "请选择您的 Rime 配置目录 (通常是 ~/Library/Rime)"
    static let accessConfirm = "授权访问"
    static let sharedSupportAccessTitle = "授权读取 Squirrel 内置方案"
    static let sharedSupportAccessDescription = "为了显示 Squirrel 内置方案，应用需要读取 Squirrel.app 的 SharedSupport 目录。"
    static let sharedSupportAccessButton = "授权访问 Squirrel 内置方案目录"
    static let sharedSupportAccessPrompt = "请选择 Squirrel.app 或 SharedSupport 目录"
    static let sharedSupportAccessConfirm = "授权读取"
    static let sharedSupportAccessSuccess = "已授权读取 Squirrel 内置方案"
    static let sharedSupportAccessFailed = "授权 Squirrel 内置方案失败：%@"
    static let sharedSupportAccessInvalid = "未找到 Squirrel 的 SharedSupport 目录"
    static let sharedSupportAccessGranted = "已授权读取 Squirrel 内置方案"
    static let sharedSupportAccessReset = "已重置 Squirrel 内置方案授权"
    static let sharedSupportResetButton = "重置 Squirrel 内置方案授权"

    // Schema Driven View
    static let loadSchemaError = "无法加载 Schema"
    static let loadingSchema = "正在加载 Schema..."
    static let defaultTitle = "Schema 驱动预览"
    static let notSet = "未设置"
    static let invalidColor = "无效颜色"
    static let loadingFonts = "正在加载字体..."
    static let showMoreSchemas = "显示更多方案 (%d)"
    static let hideInactiveSchemas = "收起未激活方案"
    static let addSchema = "添加新方案"
    static let schemaIdPlaceholder = "方案 ID (如 rime_ice)"
    static let schemaNamePlaceholder = "方案名称 (如 雾凇拼音)"
    static let cancel = "取消"
    static let confirm = "确定"
    static let addHotkey = "添加快捷键"

    // App Options
    static let appId = "应用程序 ID"
    static let defaultEnglish = "默认英文"
    static let tempInline = "临时内嵌"
    static let disableInline = "禁用内嵌"
    static let vimMode = "Vim 模式"
    static let appIdPlaceholder = "输入或选择应用程序 ID"
    static let selectApp = "选择应用..."
    static let add = "添加"

    // Common Labels (for switches etc)
    static let asciiPunct = "英文标点"
    static let traditionalization = "简繁体"
    static let fullShape = "全角半角"
    static let emoji = "Emoji"
    static let searchSingleChar = "单字模式"
    static let noop = "无操作"
    static let clear = "清除输入"
    static let commitCode = "提交编码"
    static let commitText = "提交文字"
    static let inlineAscii = "行内英文"
    static let capsLock = "Caps Lock"
    static let shiftL = "左 Shift"
    static let shiftR = "右 Shift"
    static let controlL = "左 Control"
    static let controlR = "右 Control"

    // Advanced Settings
    static let searchPlaceholder = "搜索键名或值..."
    static let modifiedOnly = "仅显示已修改"
    static let sourceCodeMode = "源码模式"
    static let keyHeader = "键名"
    static let valueHeader = "当前值"
    static let sourceHeader = "来源"
    static let customize = "自定义"
    static let reset = "重置"
    static let defaultValue = "默认"
    static let patchedValue = "已修改"
    static let when = "When"
    static let accept = "Accept"
    static let sendToggle = "Send / Toggle"
    static let whenAlways = "always"
    static let whenComposing = "composing"
    static let whenHasMenu = "has_menu"
    static let whenPaging = "paging"

    static func whenLabel(_ when: String) -> String {
        switch when {
        case "always": return whenAlways
        case "composing": return whenComposing
        case "has_menu": return whenHasMenu
        case "paging": return whenPaging
        default: return when
        }
    }

    static let save = "保存"
    static let rawYamlDescription = "直接编辑 .custom.yaml 文件。请确保 YAML 格式正确。"
    static let configFile = "配置文件"
    static let defaultYaml = "default.yaml"
    static let squirrelYaml = "squirrel.yaml"
    static let noResults = "无匹配结果"

    // Help & About
    static let loadingHelp = "正在加载帮助内容..."
    static let showInFinder = "在 Finder 中显示 Rime 目录"
    static let helpLoadError = "无法加载帮助文档。"
    static let version = "版本 %@"
    static let copyright = "© 2026 Nanomouse. All rights reserved."
    static let checkUpdates = "检查更新..."
    static let resetAccess = "重置目录授权"
    static let on = "开启"
    static let off = "关闭"

    // Hotkey Recorder
    static let pressKey = "请按下按键..."
    static let clickToRecord = "点击录制"

    // Schema Store
    static let schemaNotFound = "ConfigSchema.json 未找到"
    static let schemaParseFailed = "Schema 解析失败：%@"

    // Nanomouse
    static let nanomouseIntro = "Nanomouse 会为所选方案追加拼音优化规则（ng→nn 等）。"
    static let nanomouseHint = "提示：这些规则写入对应的 *.custom.yaml，不会覆盖你的其他配置。"
    static let nanomouseEnabled = "已启用 Nanomouse 规则：%@"
    static let nanomouseDisabled = "已关闭 Nanomouse 规则：%@"
    static let nanomouseNoChange = "Nanomouse 规则无变化：%@"
}
