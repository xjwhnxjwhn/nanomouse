import Foundation

/// Centralized UI strings for localization and easier maintenance.
struct L10n {
    private enum Language: Hashable {
        case zhHans
        case zhHant
        case en
        case ja
    }

    private static let helpMarkdownKey = "__help_markdown__"

    private static var currentLanguage: Language {
        for identifier in Locale.preferredLanguages + [Locale.autoupdatingCurrent.identifier, Locale.current.identifier] {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("zh-hant") ||
                normalized.hasPrefix("zh_hant") ||
                normalized.hasPrefix("zh-tw") ||
                normalized.hasPrefix("zh_tw") ||
                normalized.hasPrefix("zh-hk") ||
                normalized.hasPrefix("zh_hk") ||
                normalized.hasPrefix("zh-mo") ||
                normalized.hasPrefix("zh_mo") ||
                normalized.contains("hant") {
                return .zhHant
            }
            if normalized.hasPrefix("zh") {
                return .zhHans
            }
            if normalized.hasPrefix("ja") {
                return .ja
            }
            if normalized.hasPrefix("en") {
                return .en
            }
        }
        return .en
    }

    private static var locale: Locale {
        switch currentLanguage {
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .zhHant:
            return Locale(identifier: "zh-Hant")
        case .en:
            return Locale(identifier: "en")
        case .ja:
            return Locale(identifier: "ja")
        }
    }

    static func text(_ source: String) -> String {
        translations[currentLanguage]?[source] ?? source
    }

    static func format(_ source: String, _ arguments: CVarArg...) -> String {
        String(format: text(source), locale: locale, arguments: arguments)
    }

    static var localizedHelpMarkdown: String? {
        translations[currentLanguage]?[helpMarkdownKey]
    }

    // Sidebar & Navigation
    static let appTitle = "NanoMouse"
    static let nanomouse = "NanoMouse"
    static var schemes: String { text("输入方案") }
    static var panel: String { text("候选词面板") }
    static var behaviors: String { text("输入行为") }
    static var apps: String { text("应用程序") }
    static var advanced: String { text("高级设置") }
    static var help: String { text("帮助") }
    static var selectItem: String { text("请选择一个项目") }
    static let sctWebsite = "NanoMouse GitHub"
    static var squirrelWebsite: String { text("Squirrel 官网") }
    static var checkForUpdates: String { text("检查更新...") }

    // Status Messages
    static var loadingConfig: String { text("正在读取配置...") }
    static var loadingSchemas: String { text("正在读取方案...") }
    static var accessRequired: String { text("需要访问 ~/Library/Rime 目录的权限") }
    static var accessDenied: String { text("无权限访问 Rime 目录") }
    static var deployTriggered: String { text("已触发重新部署") }
    static var deployFailed: String { text("部署失败，尝试更新文件时间戳...") }
    static var timestampUpdated: String { text("已更新文件时间戳") }
    static var deployHelp: String { text("重新部署 Squirrel 以应用更改") }
    static var authFailed: String { text("授权失败：%@") }
    static var usingExampleConfig: String { text("使用示例配置") }
    static var readPath: String { text("已读取 %@") }
    static var schemaAdded: String { text("已添加方案: %@") }
    static var schemaAddFailed: String { text("创建方案失败: %@") }
    static var schemaDeleted: String { text("已删除方案文件并清理配置: %@") }
    static var configCleaned: String { text("已清理配置: %@") }
    static var schemaDeleteFailed: String { text("删除方案失败: %@") }
    static var saveSuccess: String { text("已保存 %@") }
    static var saveFailed: String { text("保存失败：%@") }

    // Access Request
    static var accessTitle: String { text("需要访问 Rime 配置目录") }
    static var accessDescription: String { text("为了读取和修改您的 Squirrel 配置，NanoMouse 需要访问您的 Rime 目录（通常位于 ~/Library/Rime）。") }
    static var accessButton: String { text("授权访问 ~/Library/Rime") }
    static var accessFooter: String { text("您的授权将被安全地存储，以便下次自动访问。") }
    static var accessPrompt: String { text("请选择您的 Rime 配置目录 (通常是 ~/Library/Rime)") }
    static var accessConfirm: String { text("授权访问") }
    static var sharedSupportAccessTitle: String { text("授权读取 Squirrel 内置方案") }
    static var sharedSupportAccessDescription: String { text("为了显示 Squirrel 内置方案，应用需要读取 Squirrel.app 的 SharedSupport 目录。") }
    static var sharedSupportAccessButton: String { text("授权访问 Squirrel 内置方案目录") }
    static var sharedSupportAccessPrompt: String { text("请选择 Squirrel.app 或 SharedSupport 目录") }
    static var sharedSupportAccessConfirm: String { text("授权读取") }
    static var sharedSupportAccessSuccess: String { text("已授权读取 Squirrel 内置方案") }
    static var sharedSupportAccessFailed: String { text("授权 Squirrel 内置方案失败：%@") }
    static var sharedSupportAccessInvalid: String { text("未找到 Squirrel 的 SharedSupport 目录") }
    static var sharedSupportAccessGranted: String { text("已授权读取 Squirrel 内置方案") }
    static var sharedSupportAccessReset: String { text("已重置 Squirrel 内置方案授权") }
    static var sharedSupportResetButton: String { text("重置 Squirrel 内置方案授权") }

    // Schema Driven View
    static var loadSchemaError: String { text("无法加载 Schema") }
    static var loadingSchema: String { text("正在加载 Schema...") }
    static var defaultTitle: String { text("Schema 驱动预览") }
    static var notSet: String { text("未设置") }
    static var invalidColor: String { text("无效颜色") }
    static var loadingFonts: String { text("正在加载字体...") }
    static var showMoreSchemas: String { text("显示更多方案 (%d)") }
    static var hideInactiveSchemas: String { text("收起未激活方案") }
    static var addSchema: String { text("添加新方案") }
    static var schemaIdPlaceholder: String { text("方案 ID (如 rime_ice)") }
    static var schemaNamePlaceholder: String { text("方案名称 (如 雾凇拼音)") }
    static var cancel: String { text("取消") }
    static var confirm: String { text("确定") }
    static var addHotkey: String { text("添加快捷键") }

    // App Options
    static var appId: String { text("应用程序 ID") }
    static var defaultEnglish: String { text("默认英文") }
    static var tempInline: String { text("临时内嵌") }
    static var disableInline: String { text("禁用内嵌") }
    static var vimMode: String { text("Vim 模式") }
    static var appIdPlaceholder: String { text("输入或选择应用程序 ID") }
    static var selectApp: String { text("选择应用...") }
    static var add: String { text("添加") }

    // Common Labels (for switches etc)
    static var asciiPunct: String { text("英文标点") }
    static var traditionalization: String { text("简繁体") }
    static var fullShape: String { text("全角半角") }
    static let emoji = "Emoji"
    static var searchSingleChar: String { text("单字模式") }
    static var noop: String { text("无操作") }
    static var clear: String { text("清除输入") }
    static var commitCode: String { text("提交编码") }
    static var commitText: String { text("提交文字") }
    static var inlineAscii: String { text("行内英文") }
    static let capsLock = "Caps Lock"
    static var shiftL: String { text("左 Shift") }
    static var shiftR: String { text("右 Shift") }
    static var controlL: String { text("左 Control") }
    static var controlR: String { text("右 Control") }

    // Advanced Settings
    static var searchPlaceholder: String { text("搜索键名或值...") }
    static var modifiedOnly: String { text("仅显示已修改") }
    static var sourceCodeMode: String { text("源码模式") }
    static var keyHeader: String { text("键名") }
    static var valueHeader: String { text("当前值") }
    static var sourceHeader: String { text("来源") }
    static var customize: String { text("自定义") }
    static var reset: String { text("重置") }
    static var defaultValue: String { text("默认") }
    static var patchedValue: String { text("已修改") }
    static var when: String { text("When") }
    static var accept: String { text("Accept") }
    static var sendToggle: String { text("Send / Toggle") }
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

    static var save: String { text("保存") }
    static var rawYamlDescription: String { text("直接编辑 .custom.yaml 文件。请确保 YAML 格式正确。") }
    static var configFile: String { text("配置文件") }
    static let defaultYaml = "default.yaml"
    static let squirrelYaml = "squirrel.yaml"
    static var noResults: String { text("无匹配结果") }

    // Help & About
    static var loadingHelp: String { text("正在加载帮助内容...") }
    static var showInFinder: String { text("在 Finder 中显示 Rime 目录") }
    static var helpLoadError: String { text("无法加载帮助文档。") }
    static var version: String { text("版本 %@") }
    static let copyright = "© 2026 NanoMouse. All rights reserved."
    static var checkUpdates: String { text("检查更新...") }
    static var rateApp: String { text("给 NanoMouse 评分") }
    static var resetAccess: String { text("重置目录授权") }
    static var on: String { text("开启") }
    static var off: String { text("关闭") }
    static var bytePasteAbout: String { text("字节粘贴关于") }
    static var bytePasteAboutDescription: String { text("此区域直接映射“字节粘贴偏好设置 -> 关于”的内容。") }
    static var project: String { text("项目") }
    static var upstreamRepository: String { text("上游仓库") }
    static var squirrelProject: String { text("鼠须管项目") }
    static var sctOriginalProjectInfo: String { text("SCT 原项目信息") }

    // Hotkey Recorder
    static var pressKey: String { text("请按下按键...") }
    static var clickToRecord: String { text("点击录制") }

    // Schema Store
    static var schemaNotFound: String { text("ConfigSchema.json 未找到") }
    static var schemaParseFailed: String { text("Schema 解析失败：%@") }

    // Nanomouse
    static var nanomouseIntro: String { text("NanoMouse 会为所选方案追加拼音优化规则（ng→nn 等）。") }
    static var nanomouseHint: String { text("提示：这些规则写入对应的 *.custom.yaml，不会覆盖你的其他配置。") }
    static var nanomouseEnabled: String { text("已启用 NanoMouse 规则：%@") }
    static var nanomouseDisabled: String { text("已关闭 NanoMouse 规则：%@") }
    static var nanomouseNoChange: String { text("NanoMouse 规则无变化：%@") }
    static var nanomousePresetDescription: String { text("启用 NanoMouse 拼音优化规则（ng→nn，uan→vn，uang→vnn）") }

    // Mac Welcome
    static var welcomeTitle: String { text("欢迎使用鼠输入法") }
    static var welcomeSubtitle: String { text("这是一个菜单栏常驻工具。首次打开后，主窗口会自动收起，不是闪退。") }
    static var welcomeMenuBarHint: String { text("看右上角菜单栏") }
    static var welcomeMenuBarTitle: String { text("常驻菜单栏") }
    static var welcomeMenuBarDetail: String { text("启动后不会一直占用 Dock 窗口，请看屏幕右上角的鼠图标。") }
    static var welcomeHotkeyTitle: String { text("快捷键呼出") }
    static var welcomeHotkeyDetail: String { text("默认按 ⌥ Space 打开或隐藏字节粘贴，可在设置中修改。") }
    static var welcomeGridTitle: String { text("字节粘贴格子") }
    static var welcomeGridDetail: String { text("保存常用文本、富文本、图片、PDF、文件和链接，点击或回车快速粘贴。") }
    static var welcomeWorkspaceTitle: String { text("画布、Markdown、因果图") }
    static var welcomeWorkspaceDetail: String { text("在同一个菜单栏窗口中手绘、写 Markdown、整理因果图，并可保存到文件系统。") }
    static var welcomeSyncTitle: String { text("跨设备同步") }
    static var welcomeSyncDetail: String { text("iPhone、iPad、Mac 与键盘扩展可以通过 iCloud 同步格子与文件。") }
    static var welcomeEntryTitle: String { text("两种入口") }
    static var welcomeEntryDetail: String { text("点击菜单栏鼠图标打开；右键菜单可进入设置、帮助和其他管理功能。") }
    static var welcomeOpenSettings: String { text("打开设置") }
    static var welcomeStart: String { text("我知道了，开始使用") }

    private static let translations: [Language: [String: String]] = [
        .zhHant: zhHant,
        .en: en,
        .ja: ja
    ]

    private static let zhHant: [String: String] = [
        "输入方案": "輸入方案",
        "候选词面板": "候選詞面板",
        "输入行为": "輸入行為",
        "应用程序": "應用程式",
        "高级设置": "進階設定",
        "帮助": "說明",
        "请选择一个项目": "請選擇一個項目",
        "Squirrel 官网": "Squirrel 官網",
        "检查更新...": "檢查更新...",
        "正在读取配置...": "正在讀取設定...",
        "正在读取方案...": "正在讀取方案...",
        "需要访问 ~/Library/Rime 目录的权限": "需要取用 ~/Library/Rime 目錄的權限",
        "无权限访问 Rime 目录": "無權限取用 Rime 目錄",
        "已触发重新部署": "已觸發重新部署",
        "部署失败，尝试更新文件时间戳...": "部署失敗，嘗試更新檔案時間戳...",
        "已更新文件时间戳": "已更新檔案時間戳",
        "重新部署 Squirrel 以应用更改": "重新部署 Squirrel 以套用變更",
        "授权失败：%@": "授權失敗：%@",
        "使用示例配置": "使用範例設定",
        "已读取 %@": "已讀取 %@",
        "已添加方案: %@": "已新增方案：%@",
        "创建方案失败: %@": "建立方案失敗：%@",
        "已删除方案文件并清理配置: %@": "已刪除方案檔案並清理設定：%@",
        "已清理配置: %@": "已清理設定：%@",
        "删除方案失败: %@": "刪除方案失敗：%@",
        "已保存 %@": "已儲存 %@",
        "保存失败：%@": "儲存失敗：%@",
        "需要访问 Rime 配置目录": "需要取用 Rime 設定目錄",
        "为了读取和修改您的 Squirrel 配置，NanoMouse 需要访问您的 Rime 目录（通常位于 ~/Library/Rime）。": "為了讀取和修改你的 Squirrel 設定，NanoMouse 需要取用你的 Rime 目錄（通常位於 ~/Library/Rime）。",
        "授权访问 ~/Library/Rime": "授權取用 ~/Library/Rime",
        "您的授权将被安全地存储，以便下次自动访问。": "你的授權會被安全儲存，方便下次自動取用。",
        "请选择您的 Rime 配置目录 (通常是 ~/Library/Rime)": "請選擇你的 Rime 設定目錄（通常是 ~/Library/Rime）",
        "授权访问": "授權取用",
        "授权读取 Squirrel 内置方案": "授權讀取 Squirrel 內建方案",
        "为了显示 Squirrel 内置方案，应用需要读取 Squirrel.app 的 SharedSupport 目录。": "為了顯示 Squirrel 內建方案，App 需要讀取 Squirrel.app 的 SharedSupport 目錄。",
        "授权访问 Squirrel 内置方案目录": "授權取用 Squirrel 內建方案目錄",
        "请选择 Squirrel.app 或 SharedSupport 目录": "請選擇 Squirrel.app 或 SharedSupport 目錄",
        "授权读取": "授權讀取",
        "已授权读取 Squirrel 内置方案": "已授權讀取 Squirrel 內建方案",
        "授权 Squirrel 内置方案失败：%@": "授權 Squirrel 內建方案失敗：%@",
        "未找到 Squirrel 的 SharedSupport 目录": "找不到 Squirrel 的 SharedSupport 目錄",
        "已重置 Squirrel 内置方案授权": "已重置 Squirrel 內建方案授權",
        "重置 Squirrel 内置方案授权": "重置 Squirrel 內建方案授權",
        "无法加载 Schema": "無法載入 Schema",
        "正在加载 Schema...": "正在載入 Schema...",
        "Schema 驱动预览": "Schema 驅動預覽",
        "未设置": "未設定",
        "无效颜色": "無效顏色",
        "正在加载字体...": "正在載入字體...",
        "显示更多方案 (%d)": "顯示更多方案（%d）",
        "收起未激活方案": "收合未啟用方案",
        "添加新方案": "新增方案",
        "方案 ID (如 rime_ice)": "方案 ID（如 rime_ice）",
        "方案名称 (如 雾凇拼音)": "方案名稱（如 雾凇拼音）",
        "取消": "取消",
        "确定": "確定",
        "添加快捷键": "新增快捷鍵",
        "应用程序 ID": "應用程式 ID",
        "默认英文": "預設英文",
        "临时内嵌": "臨時內嵌",
        "禁用内嵌": "停用內嵌",
        "Vim 模式": "Vim 模式",
        "输入或选择应用程序 ID": "輸入或選擇應用程式 ID",
        "选择应用...": "選擇應用程式...",
        "添加": "新增",
        "英文标点": "英文標點",
        "简繁体": "簡繁體",
        "全角半角": "全形半形",
        "单字模式": "單字模式",
        "无操作": "無操作",
        "清除输入": "清除輸入",
        "提交编码": "提交編碼",
        "提交文字": "提交文字",
        "行内英文": "行內英文",
        "左 Shift": "左 Shift",
        "右 Shift": "右 Shift",
        "左 Control": "左 Control",
        "右 Control": "右 Control",
        "搜索键名或值...": "搜尋鍵名或值...",
        "仅显示已修改": "僅顯示已修改",
        "源码模式": "原始碼模式",
        "键名": "鍵名",
        "当前值": "目前值",
        "来源": "來源",
        "自定义": "自訂",
        "重置": "重置",
        "默认": "預設",
        "已修改": "已修改",
        "When": "條件",
        "Accept": "接收",
        "Send / Toggle": "發送 / 切換",
        "保存": "儲存",
        "直接编辑 .custom.yaml 文件。请确保 YAML 格式正确。": "直接編輯 .custom.yaml 檔案。請確保 YAML 格式正確。",
        "配置文件": "設定檔",
        "无匹配结果": "沒有符合的結果",
        "正在加载帮助内容...": "正在載入說明內容...",
        "在 Finder 中显示 Rime 目录": "在 Finder 中顯示 Rime 目錄",
        "无法加载帮助文档。": "無法載入說明文件。",
        "版本": "版本",
        "版本 %@": "版本 %@",
        "给 NanoMouse 评分": "為 NanoMouse 評分",
        "重置目录授权": "重置目錄授權",
        "开启": "開啟",
        "关闭": "關閉",
        "字节粘贴关于": "位元組貼上關於",
        "此区域直接映射“字节粘贴偏好设置 -> 关于”的内容。": "此區域直接對應「位元組貼上偏好設定 -> 關於」的內容。",
        "项目": "專案",
        "上游仓库": "上游倉庫",
        "鼠须管项目": "鼠鬚管專案",
        "SCT 原项目信息": "SCT 原專案資訊",
        "请按下按键...": "請按下按鍵...",
        "点击录制": "點擊錄製",
        "ConfigSchema.json 未找到": "找不到 ConfigSchema.json",
        "Schema 解析失败：%@": "Schema 解析失敗：%@",
        "NanoMouse 会为所选方案追加拼音优化规则（ng→nn 等）。": "NanoMouse 會為所選方案追加拼音最佳化規則（ng→nn 等）。",
        "提示：这些规则写入对应的 *.custom.yaml，不会覆盖你的其他配置。": "提示：這些規則會寫入對應的 *.custom.yaml，不會覆蓋你的其他設定。",
        "已启用 NanoMouse 规则：%@": "已啟用 NanoMouse 規則：%@",
        "已关闭 NanoMouse 规则：%@": "已關閉 NanoMouse 規則：%@",
        "NanoMouse 规则无变化：%@": "NanoMouse 規則無變化：%@",
        "启用 NanoMouse 拼音优化规则（ng→nn，uan→vn，uang→vnn）": "啟用 NanoMouse 拼音最佳化規則（ng→nn，uan→vn，uang→vnn）",
        "欢迎使用鼠输入法": "歡迎使用鼠輸入法",
        "这是一个菜单栏常驻工具。首次打开后，主窗口会自动收起，不是闪退。": "這是一個常駐選單列的工具。首次開啟後，主視窗會自動收起，並不是閃退。",
        "看右上角菜单栏": "請看右上角選單列",
        "常驻菜单栏": "常駐選單列",
        "启动后不会一直占用 Dock 窗口，请看屏幕右上角的鼠图标。": "啟動後不會一直佔用 Dock 視窗，請看螢幕右上角的鼠圖示。",
        "快捷键呼出": "用快捷鍵呼出",
        "默认按 ⌥ Space 打开或隐藏字节粘贴，可在设置中修改。": "預設按 ⌥ Space 開啟或隱藏字節貼上，可在設定中修改。",
        "字节粘贴格子": "字節貼上格子",
        "保存常用文本、富文本、图片、PDF、文件和链接，点击或回车快速粘贴。": "儲存常用文字、富文字、圖片、PDF、檔案和連結，點擊或按 Return 快速貼上。",
        "画布、Markdown、因果图": "畫布、Markdown、因果圖",
        "在同一个菜单栏窗口中手绘、写 Markdown、整理因果图，并可保存到文件系统。": "在同一個選單列視窗中手繪、撰寫 Markdown、整理因果圖，並可儲存到檔案系統。",
        "跨设备同步": "跨裝置同步",
        "iPhone、iPad、Mac 与键盘扩展可以通过 iCloud 同步格子与文件。": "iPhone、iPad、Mac 與鍵盤延伸功能可以透過 iCloud 同步格子與檔案。",
        "两种入口": "兩種入口",
        "点击菜单栏鼠图标打开；右键菜单可进入设置、帮助和其他管理功能。": "點擊選單列鼠圖示即可開啟；右鍵選單可進入設定、說明和其他管理功能。",
        "打开设置": "開啟設定",
        "我知道了，开始使用": "我知道了，開始使用",
        "方案列表": "方案列表",
        "面板菜单": "面板選單",
        "候选词个数": "候選詞個數",
        "每页显示的候选词数量 (3-10)": "每頁顯示的候選詞數量（3-10）",
        "方案选单": "方案選單",
        "标题": "標題",
        "快捷键": "快捷鍵",
        "触发方案选单的全局快捷键": "觸發方案選單的全域快捷鍵",
        "记忆选项": "記憶選項",
        "在方案选单中切换后需要记住的状态": "在方案選單中切換後需要記住的狀態",
        "折叠菜单": "摺疊選單",
        "折叠缩写": "摺疊縮寫",
        "选项分隔符": "選項分隔符",
        "中英切换": "中英切換",
        "保持 Caps Lock 原功能": "保留 Caps Lock 原功能",
        "勾选此项后 Caps Lock 键用于切换大写锁定，否则用于切换中英文输入状态": "勾選此項後 Caps Lock 鍵用於切換大寫鎖定，否則用於切換中英文輸入狀態",
        "切换按键设置": "切換按鍵設定",
        "切换到英文模式前的行为，‘行内英文’会在回车输入英文后切回中文模式": "切換到英文模式前的行為，「行內英文」會在按 Return 輸入英文後切回中文模式",
        "标点与识别": "標點與識別",
        "数字连续上屏": "數字連續上屏",
        "数字符号行为": "數字符號行為",
        "全角映射": "全形映射",
        "半角映射": "半形映射",
        "识别模式": "識別模式",
        "以词定字": "以詞定字",
        "首字": "首字",
        "末字": "末字",
        "移动光标": "移動游標",
        "上个拼音": "上個拼音",
        "下个拼音": "下個拼音",
        "翻页": "翻頁",
        "上页": "上頁",
        "下页": "下頁",
        "键盘体验": "鍵盤體驗",
        "拉丁键盘布局": "拉丁鍵盤配置",
        "和弦时间": "和弦時間",
        "通知时机": "通知時機",
        "面板样式": "面板樣式",
        "亮色皮肤": "亮色佈景",
        "暗色皮肤": "暗色佈景",
        "排列方式": "排列方式",
        "stack 为竖排，linear 为横排": "stack 為直排，linear 為橫排",
        "文字方向": "文字方向",
        "内嵌编码": "內嵌編碼",
        "内嵌候选": "內嵌候選",
        "记忆窗口尺寸": "記憶視窗尺寸",
        "色彩不叠加": "色彩不疊加",
        "磨砂效果": "磨砂效果",
        "显示翻页箭头": "顯示翻頁箭頭",
        "字体": "字體",
        "字号": "字號",
        "圆角": "圓角",
        "高亮圆角": "高亮圓角",
        "边框高度": "邊框高度",
        "边框宽度": "邊框寬度",
        "候选行距": "候選行距",
        "拼音间距": "拼音間距",
        "透明度": "透明度",
        "阴影": "陰影",
        "候选格式": "候選格式",
        "应用列表": "應用程式列表",
        "为特定应用程序设置输入行为（如在终端中默认使用英文）": "為特定應用程式設定輸入行為（例如在終端機中預設使用英文）",
        "皮肤库": "佈景庫",
        "皮肤集合": "佈景集合",
        "名称": "名稱",
        "作者": "作者",
        "排列": "排列",
        "行距": "行距",
        "间距": "間距",
        "色域": "色域",
        "背景色": "背景色",
        "候选文字": "候選文字",
        "高亮背景": "高亮背景",
        "高亮文字": "高亮文字",
        "注释文字": "註解文字",
        "高亮注释": "高亮註解",
        "拼音": "拼音",
        "高亮拼音": "高亮拼音",
        helpMarkdownKey: """
        **NanoMouse**

        **核心理念：尊重 Rime 邏輯，簡化使用者操作**

        - **非破壞性**：NanoMouse 永遠不會修改 Rime 的預設設定檔（`default.yaml` 和 `squirrel.yaml`），所有變更都寫入 `default.custom.yaml` 或 `squirrel.custom.yaml` 的 `patch` 鍵下。
        - **原生體驗**：使用 SwiftUI 建構，提供原生 macOS 體驗。
        - **透明度**：你可以在「進階設定」中隨時查看合併後的 YAML 設定。

        **常見問題**

        1. 為什麼我的變更沒有生效？

           在 NanoMouse 中修改設定後，你需要點擊工具列上的「部署」按鈕（或使用快捷鍵 `Cmd+R`），這會觸發 Squirrel 重新載入設定。

        2. 如何新增新的輸入方案？

           在「輸入方案」頁面，點擊底部的「新增方案」按鈕，輸入方案 ID（如 `rime_ice`）和名稱，NanoMouse 會自動為你建立基礎方案檔案並將其加入啟用列表。

        3. 什麼是「進階設定」？

           「進階設定」允許你瀏覽 Rime 的完整設定樹，並直接修改其中的任何值。NanoMouse 會自動將變更加入對應的 `.custom.yaml` 檔案。這是面向進階使用者的功能；如果你不確定是否需要它，請優先使用本工具提供的其他頁面來編輯常用設定。

        4. 沙盒取用權限

           NanoMouse 會讀寫你的 Squirrel 設定檔，它們通常位於 `~/Library/Rime` 目錄下。為了安全取用該目錄，NanoMouse 需要你的授權；如果你移動了 Rime 目錄，可以在此處重新授權。
        """
    ]

    private static let en: [String: String] = [
        "输入方案": "Input Schemas",
        "候选词面板": "Candidate Panel",
        "输入行为": "Input Behavior",
        "应用程序": "Applications",
        "高级设置": "Advanced",
        "帮助": "Help",
        "请选择一个项目": "Select an item",
        "Squirrel 官网": "Squirrel Website",
        "检查更新...": "Check for Updates...",
        "正在读取配置...": "Loading configuration...",
        "正在读取方案...": "Loading schemas...",
        "需要访问 ~/Library/Rime 目录的权限": "Access to ~/Library/Rime is required",
        "无权限访问 Rime 目录": "No permission to access the Rime directory",
        "已触发重新部署": "Redeploy triggered",
        "部署失败，尝试更新文件时间戳...": "Deploy failed, trying to update file timestamps...",
        "已更新文件时间戳": "File timestamps updated",
        "重新部署 Squirrel 以应用更改": "Redeploy Squirrel to apply changes",
        "授权失败：%@": "Authorization failed: %@",
        "使用示例配置": "Using example configuration",
        "已读取 %@": "Loaded %@",
        "已添加方案: %@": "Schema added: %@",
        "创建方案失败: %@": "Failed to create schema: %@",
        "已删除方案文件并清理配置: %@": "Deleted schema files and cleaned configuration: %@",
        "已清理配置: %@": "Configuration cleaned: %@",
        "删除方案失败: %@": "Failed to delete schema: %@",
        "已保存 %@": "Saved %@",
        "保存失败：%@": "Save failed: %@",
        "需要访问 Rime 配置目录": "Rime Configuration Access Required",
        "为了读取和修改您的 Squirrel 配置，NanoMouse 需要访问您的 Rime 目录（通常位于 ~/Library/Rime）。": "NanoMouse needs access to your Rime directory, usually ~/Library/Rime, to read and edit your Squirrel configuration.",
        "授权访问 ~/Library/Rime": "Grant Access to ~/Library/Rime",
        "您的授权将被安全地存储，以便下次自动访问。": "Your authorization is stored securely so the app can access it automatically next time.",
        "请选择您的 Rime 配置目录 (通常是 ~/Library/Rime)": "Choose your Rime configuration directory, usually ~/Library/Rime",
        "授权访问": "Grant Access",
        "授权读取 Squirrel 内置方案": "Grant Access to Squirrel Built-in Schemas",
        "为了显示 Squirrel 内置方案，应用需要读取 Squirrel.app 的 SharedSupport 目录。": "To show Squirrel built-in schemas, the app needs to read Squirrel.app's SharedSupport directory.",
        "授权访问 Squirrel 内置方案目录": "Grant Access to Squirrel Built-in Schema Directory",
        "请选择 Squirrel.app 或 SharedSupport 目录": "Choose Squirrel.app or the SharedSupport directory",
        "授权读取": "Grant Read Access",
        "已授权读取 Squirrel 内置方案": "Squirrel built-in schemas can be read",
        "授权 Squirrel 内置方案失败：%@": "Failed to authorize Squirrel built-in schemas: %@",
        "未找到 Squirrel 的 SharedSupport 目录": "Squirrel SharedSupport directory was not found",
        "已重置 Squirrel 内置方案授权": "Squirrel built-in schema authorization has been reset",
        "重置 Squirrel 内置方案授权": "Reset Squirrel Built-in Schema Access",
        "无法加载 Schema": "Cannot Load Schema",
        "正在加载 Schema...": "Loading Schema...",
        "Schema 驱动预览": "Schema Preview",
        "未设置": "Not Set",
        "无效颜色": "Invalid Color",
        "正在加载字体...": "Loading fonts...",
        "显示更多方案 (%d)": "Show More Schemas (%d)",
        "收起未激活方案": "Hide Inactive Schemas",
        "添加新方案": "Add New Schema",
        "方案 ID (如 rime_ice)": "Schema ID (for example, rime_ice)",
        "方案名称 (如 雾凇拼音)": "Schema Name (for example, Rime Ice)",
        "取消": "Cancel",
        "确定": "OK",
        "添加快捷键": "Add Hotkey",
        "应用程序 ID": "Application ID",
        "默认英文": "Default English",
        "临时内嵌": "Temporary Inline",
        "禁用内嵌": "Disable Inline",
        "Vim 模式": "Vim Mode",
        "输入或选择应用程序 ID": "Enter or choose an application ID",
        "选择应用...": "Choose App...",
        "添加": "Add",
        "英文标点": "English Punctuation",
        "简繁体": "Simplified/Traditional",
        "全角半角": "Full/Half Width",
        "单字模式": "Single Character Mode",
        "无操作": "No Operation",
        "清除输入": "Clear Input",
        "提交编码": "Commit Code",
        "提交文字": "Commit Text",
        "行内英文": "Inline ASCII",
        "左 Shift": "Left Shift",
        "右 Shift": "Right Shift",
        "左 Control": "Left Control",
        "右 Control": "Right Control",
        "搜索键名或值...": "Search keys or values...",
        "仅显示已修改": "Modified Only",
        "源码模式": "Source Mode",
        "键名": "Key",
        "当前值": "Current Value",
        "来源": "Source",
        "自定义": "Customize",
        "重置": "Reset",
        "默认": "Default",
        "已修改": "Modified",
        "保存": "Save",
        "直接编辑 .custom.yaml 文件。请确保 YAML 格式正确。": "Edit the .custom.yaml file directly. Make sure the YAML format is valid.",
        "配置文件": "Configuration File",
        "无匹配结果": "No Results",
        "正在加载帮助内容...": "Loading help content...",
        "在 Finder 中显示 Rime 目录": "Show Rime Directory in Finder",
        "无法加载帮助文档。": "Cannot load the help document.",
        "版本": "Version",
        "版本 %@": "Version %@",
        "给 NanoMouse 评分": "Rate NanoMouse",
        "重置目录授权": "Reset Directory Access",
        "开启": "On",
        "关闭": "Off",
        "字节粘贴关于": "Byte Paste About",
        "此区域直接映射“字节粘贴偏好设置 -> 关于”的内容。": "This area mirrors Byte Paste Preferences -> About.",
        "项目": "Project",
        "上游仓库": "Upstream Repository",
        "鼠须管项目": "Squirrel Project",
        "SCT 原项目信息": "Original SCT Project Info",
        "请按下按键...": "Press a key...",
        "点击录制": "Click to Record",
        "ConfigSchema.json 未找到": "ConfigSchema.json was not found",
        "Schema 解析失败：%@": "Schema parse failed: %@",
        "NanoMouse 会为所选方案追加拼音优化规则（ng→nn 等）。": "NanoMouse appends Pinyin optimization rules such as ng->nn to the selected schemas.",
        "提示：这些规则写入对应的 *.custom.yaml，不会覆盖你的其他配置。": "Tip: these rules are written to the matching *.custom.yaml file and will not overwrite your other configuration.",
        "已启用 NanoMouse 规则：%@": "NanoMouse rules enabled: %@",
        "已关闭 NanoMouse 规则：%@": "NanoMouse rules disabled: %@",
        "NanoMouse 规则无变化：%@": "NanoMouse rules unchanged: %@",
        "启用 NanoMouse 拼音优化规则（ng→nn，uan→vn，uang→vnn）": "Enable NanoMouse Pinyin optimization rules (ng->nn, uan->vn, uang->vnn)",
        "欢迎使用鼠输入法": "Welcome to NanoMouse",
        "这是一个菜单栏常驻工具。首次打开后，主窗口会自动收起，不是闪退。": "NanoMouse lives in the menu bar. On first launch, the main window hides itself; it has not crashed.",
        "看右上角菜单栏": "Look at the menu bar",
        "常驻菜单栏": "Menu Bar App",
        "启动后不会一直占用 Dock 窗口，请看屏幕右上角的鼠图标。": "After launch, NanoMouse does not keep a Dock window open. Look for the mouse icon in the top-right menu bar.",
        "快捷键呼出": "Open by Hotkey",
        "默认按 ⌥ Space 打开或隐藏字节粘贴，可在设置中修改。": "Press ⌥ Space by default to show or hide Byte Paste. You can change this in Settings.",
        "字节粘贴格子": "Byte Paste Grid",
        "保存常用文本、富文本、图片、PDF、文件和链接，点击或回车快速粘贴。": "Store text, rich text, images, PDFs, files, and links. Click or press Return to paste quickly.",
        "画布、Markdown、因果图": "Canvas, Markdown, Causal Graph",
        "在同一个菜单栏窗口中手绘、写 Markdown、整理因果图，并可保存到文件系统。": "Draw, write Markdown, and organize causal graphs in the same menu bar window, with file-system saving.",
        "跨设备同步": "Cross-Device Sync",
        "iPhone、iPad、Mac 与键盘扩展可以通过 iCloud 同步格子与文件。": "Sync snippets and files across iPhone, iPad, Mac, and the keyboard extension via iCloud.",
        "两种入口": "Two Ways to Open",
        "点击菜单栏鼠图标打开；右键菜单可进入设置、帮助和其他管理功能。": "Click the mouse icon in the menu bar to open. Right-click it for Settings, Help, and management actions.",
        "打开设置": "Open Settings",
        "我知道了，开始使用": "Got it, start using",
        "方案列表": "Schema List",
        "面板菜单": "Panel Menu",
        "候选词个数": "Candidates per Page",
        "每页显示的候选词数量 (3-10)": "Number of candidates shown on each page (3-10)",
        "方案选单": "Schema Menu",
        "标题": "Title",
        "快捷键": "Hotkeys",
        "触发方案选单的全局快捷键": "Global hotkeys that open the schema menu",
        "记忆选项": "Remembered Options",
        "在方案选单中切换后需要记住的状态": "States to remember after switching in the schema menu",
        "折叠菜单": "Fold Menu",
        "折叠缩写": "Folded Abbreviation",
        "选项分隔符": "Option Separator",
        "中英切换": "Chinese/English Switch",
        "保持 Caps Lock 原功能": "Keep Caps Lock Behavior",
        "勾选此项后 Caps Lock 键用于切换大写锁定，否则用于切换中英文输入状态": "When enabled, Caps Lock toggles uppercase lock; otherwise it switches Chinese/English input state.",
        "切换按键设置": "Switch Key Settings",
        "切换到英文模式前的行为，‘行内英文’会在回车输入英文后切回中文模式": "Behavior before switching to English mode. Inline ASCII switches back to Chinese after committing English with Return.",
        "标点与识别": "Punctuation & Recognition",
        "数字连续上屏": "Commit Consecutive Numbers",
        "数字符号行为": "Number/Symbol Behavior",
        "全角映射": "Full-width Mapping",
        "半角映射": "Half-width Mapping",
        "识别模式": "Recognition Patterns",
        "以词定字": "Select Character by Word",
        "首字": "First Character",
        "末字": "Last Character",
        "移动光标": "Move Cursor",
        "上个拼音": "Previous Pinyin",
        "下个拼音": "Next Pinyin",
        "翻页": "Paging",
        "上页": "Previous Page",
        "下页": "Next Page",
        "键盘体验": "Keyboard Experience",
        "拉丁键盘布局": "Latin Keyboard Layout",
        "和弦时间": "Chord Duration",
        "通知时机": "Notification Timing",
        "面板样式": "Panel Style",
        "亮色皮肤": "Light Theme",
        "暗色皮肤": "Dark Theme",
        "排列方式": "Layout",
        "stack 为竖排，linear 为横排": "stack is vertical, linear is horizontal",
        "文字方向": "Text Direction",
        "内嵌编码": "Inline Preedit",
        "内嵌候选": "Inline Candidate",
        "记忆窗口尺寸": "Remember Window Size",
        "色彩不叠加": "Do Not Overlay Colors",
        "磨砂效果": "Blur Effect",
        "显示翻页箭头": "Show Paging Arrows",
        "字体": "Font",
        "字号": "Font Size",
        "圆角": "Corner Radius",
        "高亮圆角": "Highlighted Corner Radius",
        "边框高度": "Border Height",
        "边框宽度": "Border Width",
        "候选行距": "Candidate Line Spacing",
        "拼音间距": "Pinyin Spacing",
        "透明度": "Opacity",
        "阴影": "Shadow",
        "候选格式": "Candidate Format",
        "应用列表": "Application List",
        "为特定应用程序设置输入行为（如在终端中默认使用英文）": "Set input behavior for specific apps, such as using English by default in Terminal.",
        "皮肤库": "Theme Library",
        "皮肤集合": "Theme Collection",
        "名称": "Name",
        "作者": "Author",
        "排列": "Layout",
        "行距": "Line Spacing",
        "间距": "Spacing",
        "色域": "Color Space",
        "背景色": "Background",
        "候选文字": "Candidate Text",
        "高亮背景": "Highlighted Background",
        "高亮文字": "Highlighted Text",
        "注释文字": "Comment Text",
        "高亮注释": "Highlighted Comment",
        "拼音": "Pinyin",
        "高亮拼音": "Highlighted Pinyin",
        helpMarkdownKey: """
        **NanoMouse**

        **Core idea: respect Rime logic and simplify user operations**

        - **Non-destructive**: NanoMouse never edits Rime's default configuration files (`default.yaml` and `squirrel.yaml`). All changes are written under the `patch` key in `default.custom.yaml` or `squirrel.custom.yaml`.
        - **Native experience**: Built with SwiftUI for a native macOS experience.
        - **Transparency**: You can view the merged YAML configuration at any time in Advanced.

        **FAQ**

        1. Why did my changes not take effect?

           After editing configuration in NanoMouse, click the Deploy button in the toolbar or press `Cmd+R`. This triggers Squirrel to reload its configuration.

        2. How do I add a new input schema?

           On the Input Schemas page, click Add New Schema, enter a schema ID such as `rime_ice` and a name. NanoMouse creates a base schema file and adds it to the active list.

        3. What is Advanced?

           Advanced lets you browse the full Rime configuration tree and edit any value directly. NanoMouse automatically writes changes to the corresponding `.custom.yaml` file. This is intended for advanced users. If you are unsure, use the other pages in this tool for common settings.

        4. Sandbox access

           NanoMouse reads and writes your Squirrel configuration files, usually in `~/Library/Rime`. macOS requires your authorization before the app can access that directory safely. If you move the Rime directory, authorize it again here.
        """
    ]

    private static let ja: [String: String] = [
        "输入方案": "入力方式",
        "候选词面板": "候補パネル",
        "输入行为": "入力動作",
        "应用程序": "アプリケーション",
        "高级设置": "詳細設定",
        "帮助": "ヘルプ",
        "请选择一个项目": "項目を選択してください",
        "Squirrel 官网": "Squirrel 公式サイト",
        "检查更新...": "アップデートを確認...",
        "正在读取配置...": "設定を読み込み中...",
        "正在读取方案...": "入力方式を読み込み中...",
        "需要访问 ~/Library/Rime 目录的权限": "~/Library/Rime ディレクトリへのアクセスが必要です",
        "无权限访问 Rime 目录": "Rime ディレクトリにアクセスできません",
        "已触发重新部署": "再デプロイを開始しました",
        "部署失败，尝试更新文件时间戳...": "デプロイに失敗しました。ファイルのタイムスタンプを更新しています...",
        "已更新文件时间戳": "ファイルのタイムスタンプを更新しました",
        "重新部署 Squirrel 以应用更改": "変更を適用するために Squirrel を再デプロイ",
        "授权失败：%@": "認証に失敗しました：%@",
        "使用示例配置": "サンプル設定を使用中",
        "已读取 %@": "%@ を読み込みました",
        "已添加方案: %@": "入力方式を追加しました：%@",
        "创建方案失败: %@": "入力方式の作成に失敗しました：%@",
        "已删除方案文件并清理配置: %@": "入力方式ファイルを削除し設定を整理しました：%@",
        "已清理配置: %@": "設定を整理しました：%@",
        "删除方案失败: %@": "入力方式の削除に失敗しました：%@",
        "已保存 %@": "%@ を保存しました",
        "保存失败：%@": "保存に失敗しました：%@",
        "需要访问 Rime 配置目录": "Rime 設定ディレクトリへのアクセスが必要です",
        "为了读取和修改您的 Squirrel 配置，NanoMouse 需要访问您的 Rime 目录（通常位于 ~/Library/Rime）。": "Squirrel の設定を読み書きするため、NanoMouse は通常 ~/Library/Rime にある Rime ディレクトリへアクセスする必要があります。",
        "授权访问 ~/Library/Rime": "~/Library/Rime へのアクセスを許可",
        "您的授权将被安全地存储，以便下次自动访问。": "許可情報は安全に保存され、次回から自動的にアクセスできます。",
        "请选择您的 Rime 配置目录 (通常是 ~/Library/Rime)": "Rime 設定ディレクトリを選択してください（通常は ~/Library/Rime）",
        "授权访问": "アクセスを許可",
        "授权读取 Squirrel 内置方案": "Squirrel 内蔵入力方式の読み取りを許可",
        "为了显示 Squirrel 内置方案，应用需要读取 Squirrel.app 的 SharedSupport 目录。": "Squirrel 内蔵入力方式を表示するため、アプリは Squirrel.app の SharedSupport ディレクトリを読み取る必要があります。",
        "授权访问 Squirrel 内置方案目录": "Squirrel 内蔵入力方式ディレクトリへのアクセスを許可",
        "请选择 Squirrel.app 或 SharedSupport 目录": "Squirrel.app または SharedSupport ディレクトリを選択してください",
        "授权读取": "読み取りを許可",
        "已授权读取 Squirrel 内置方案": "Squirrel 内蔵入力方式の読み取りが許可されています",
        "授权 Squirrel 内置方案失败：%@": "Squirrel 内蔵入力方式の許可に失敗しました：%@",
        "未找到 Squirrel 的 SharedSupport 目录": "Squirrel の SharedSupport ディレクトリが見つかりません",
        "已重置 Squirrel 内置方案授权": "Squirrel 内蔵入力方式の許可をリセットしました",
        "重置 Squirrel 内置方案授权": "Squirrel 内蔵入力方式の許可をリセット",
        "无法加载 Schema": "Schema を読み込めません",
        "正在加载 Schema...": "Schema を読み込み中...",
        "Schema 驱动预览": "Schema プレビュー",
        "未设置": "未設定",
        "无效颜色": "無効な色",
        "正在加载字体...": "フォントを読み込み中...",
        "显示更多方案 (%d)": "さらに入力方式を表示（%d）",
        "收起未激活方案": "無効な入力方式を隠す",
        "添加新方案": "新しい入力方式を追加",
        "方案 ID (如 rime_ice)": "入力方式 ID（例：rime_ice）",
        "方案名称 (如 雾凇拼音)": "入力方式名（例：Rime Ice）",
        "取消": "キャンセル",
        "确定": "OK",
        "添加快捷键": "ショートカットを追加",
        "应用程序 ID": "アプリケーション ID",
        "默认英文": "英語をデフォルト",
        "临时内嵌": "一時インライン",
        "禁用内嵌": "インライン無効",
        "Vim 模式": "Vim モード",
        "输入或选择应用程序 ID": "アプリケーション ID を入力または選択",
        "选择应用...": "アプリを選択...",
        "添加": "追加",
        "英文标点": "英語句読点",
        "简繁体": "簡繁変換",
        "全角半角": "全角/半角",
        "单字模式": "単字モード",
        "无操作": "操作なし",
        "清除输入": "入力を消去",
        "提交编码": "コードを確定",
        "提交文字": "文字を確定",
        "行内英文": "インライン英字",
        "左 Shift": "左 Shift",
        "右 Shift": "右 Shift",
        "左 Control": "左 Control",
        "右 Control": "右 Control",
        "搜索键名或值...": "キー名または値を検索...",
        "仅显示已修改": "変更済みのみ表示",
        "源码模式": "ソースモード",
        "键名": "キー名",
        "当前值": "現在値",
        "来源": "ソース",
        "自定义": "カスタム",
        "重置": "リセット",
        "默认": "デフォルト",
        "已修改": "変更済み",
        "When": "条件",
        "Accept": "入力",
        "Send / Toggle": "送信 / 切替",
        "保存": "保存",
        "直接编辑 .custom.yaml 文件。请确保 YAML 格式正确。": ".custom.yaml ファイルを直接編集します。YAML の形式が正しいことを確認してください。",
        "配置文件": "設定ファイル",
        "无匹配结果": "一致する結果はありません",
        "正在加载帮助内容...": "ヘルプを読み込み中...",
        "在 Finder 中显示 Rime 目录": "Finder で Rime ディレクトリを表示",
        "无法加载帮助文档。": "ヘルプ文書を読み込めません。",
        "版本": "バージョン",
        "版本 %@": "バージョン %@",
        "给 NanoMouse 评分": "NanoMouse を評価",
        "重置目录授权": "ディレクトリ許可をリセット",
        "开启": "オン",
        "关闭": "オフ",
        "字节粘贴关于": "Byte Paste について",
        "此区域直接映射“字节粘贴偏好设置 -> 关于”的内容。": "この領域は Byte Paste 環境設定 -> 情報 の内容に対応しています。",
        "项目": "プロジェクト",
        "上游仓库": "上流リポジトリ",
        "鼠须管项目": "Squirrel プロジェクト",
        "SCT 原项目信息": "SCT 元プロジェクト情報",
        "请按下按键...": "キーを押してください...",
        "点击录制": "クリックして記録",
        "ConfigSchema.json 未找到": "ConfigSchema.json が見つかりません",
        "Schema 解析失败：%@": "Schema の解析に失敗しました：%@",
        "NanoMouse 会为所选方案追加拼音优化规则（ng→nn 等）。": "NanoMouse は選択した入力方式に ng->nn などのピンイン最適化ルールを追加します。",
        "提示：这些规则写入对应的 *.custom.yaml，不会覆盖你的其他配置。": "ヒント：これらのルールは対応する *.custom.yaml に書き込まれ、他の設定は上書きされません。",
        "已启用 NanoMouse 规则：%@": "NanoMouse ルールを有効にしました：%@",
        "已关闭 NanoMouse 规则：%@": "NanoMouse ルールを無効にしました：%@",
        "NanoMouse 规则无变化：%@": "NanoMouse ルールに変更はありません：%@",
        "启用 NanoMouse 拼音优化规则（ng→nn，uan→vn，uang→vnn）": "NanoMouse ピンイン最適化ルール（ng->nn、uan->vn、uang->vnn）を有効化",
        "欢迎使用鼠输入法": "NanoMouse へようこそ",
        "这是一个菜单栏常驻工具。首次打开后，主窗口会自动收起，不是闪退。": "NanoMouse はメニューバー常駐アプリです。初回起動後にメインウィンドウが自動で隠れても、クラッシュではありません。",
        "看右上角菜单栏": "右上のメニューバーを確認",
        "常驻菜单栏": "メニューバー常駐",
        "启动后不会一直占用 Dock 窗口，请看屏幕右上角的鼠图标。": "起動後、Dock のウィンドウを開きっぱなしにはしません。画面右上のマウスアイコンを確認してください。",
        "快捷键呼出": "ショートカットで呼び出し",
        "默认按 ⌥ Space 打开或隐藏字节粘贴，可在设置中修改。": "デフォルトでは ⌥ Space で Byte Paste を表示・非表示にできます。設定で変更できます。",
        "字节粘贴格子": "Byte Paste グリッド",
        "保存常用文本、富文本、图片、PDF、文件和链接，点击或回车快速粘贴。": "よく使うテキスト、リッチテキスト、画像、PDF、ファイル、リンクを保存し、クリックまたは Return ですばやく貼り付けます。",
        "画布、Markdown、因果图": "キャンバス、Markdown、因果図",
        "在同一个菜单栏窗口中手绘、写 Markdown、整理因果图，并可保存到文件系统。": "同じメニューバーウィンドウで手描き、Markdown、因果図の整理ができ、ファイルシステムに保存できます。",
        "跨设备同步": "デバイス間同期",
        "iPhone、iPad、Mac 与键盘扩展可以通过 iCloud 同步格子与文件。": "iCloud により、iPhone、iPad、Mac、キーボード拡張のグリッドとファイルを同期できます。",
        "两种入口": "2つの開き方",
        "点击菜单栏鼠图标打开；右键菜单可进入设置、帮助和其他管理功能。": "メニューバーのマウスアイコンをクリックして開きます。右クリックメニューから設定、ヘルプ、管理機能に入れます。",
        "打开设置": "設定を開く",
        "我知道了，开始使用": "了解して使い始める",
        "方案列表": "入力方式リスト",
        "面板菜单": "パネルメニュー",
        "候选词个数": "候補数",
        "每页显示的候选词数量 (3-10)": "1ページに表示する候補数（3-10）",
        "方案选单": "入力方式メニュー",
        "标题": "タイトル",
        "快捷键": "ショートカット",
        "触发方案选单的全局快捷键": "入力方式メニューを開くグローバルショートカット",
        "记忆选项": "記憶するオプション",
        "在方案选单中切换后需要记住的状态": "入力方式メニューで切り替えた後に記憶する状態",
        "折叠菜单": "メニューを折りたたむ",
        "折叠缩写": "折りたたみ略称",
        "选项分隔符": "オプション区切り文字",
        "中英切换": "中国語/英語切替",
        "保持 Caps Lock 原功能": "Caps Lock の元の動作を保持",
        "勾选此项后 Caps Lock 键用于切换大写锁定，否则用于切换中英文输入状态": "有効にすると Caps Lock は大文字ロックを切り替えます。無効の場合は中国語/英語入力状態を切り替えます。",
        "切换按键设置": "切替キー設定",
        "切换到英文模式前的行为，‘行内英文’会在回车输入英文后切回中文模式": "英語モードに切り替える前の動作です。インライン英字は Return で英語を確定した後、中国語モードに戻ります。",
        "标点与识别": "句読点と認識",
        "数字连续上屏": "連続数字を確定",
        "数字符号行为": "数字/記号の動作",
        "全角映射": "全角マッピング",
        "半角映射": "半角マッピング",
        "识别模式": "認識パターン",
        "以词定字": "単語から文字を選択",
        "首字": "先頭文字",
        "末字": "末尾文字",
        "移动光标": "カーソル移動",
        "上个拼音": "前のピンイン",
        "下个拼音": "次のピンイン",
        "翻页": "ページ送り",
        "上页": "前のページ",
        "下页": "次のページ",
        "键盘体验": "キーボード体験",
        "拉丁键盘布局": "ラテンキーボード配列",
        "和弦时间": "コード時間",
        "通知时机": "通知タイミング",
        "面板样式": "パネルスタイル",
        "亮色皮肤": "ライトテーマ",
        "暗色皮肤": "ダークテーマ",
        "排列方式": "レイアウト",
        "stack 为竖排，linear 为横排": "stack は縦並び、linear は横並びです",
        "文字方向": "文字方向",
        "内嵌编码": "インライン入力",
        "内嵌候选": "インライン候補",
        "记忆窗口尺寸": "ウィンドウサイズを記憶",
        "色彩不叠加": "色を重ねない",
        "磨砂效果": "ぼかし効果",
        "显示翻页箭头": "ページ矢印を表示",
        "字体": "フォント",
        "字号": "フォントサイズ",
        "圆角": "角丸",
        "高亮圆角": "ハイライト角丸",
        "边框高度": "枠線の高さ",
        "边框宽度": "枠線の幅",
        "候选行距": "候補行間",
        "拼音间距": "ピンイン間隔",
        "透明度": "透明度",
        "阴影": "影",
        "候选格式": "候補形式",
        "应用列表": "アプリリスト",
        "为特定应用程序设置输入行为（如在终端中默认使用英文）": "Terminal で英語をデフォルトにするなど、特定のアプリに入力動作を設定します。",
        "皮肤库": "テーマライブラリ",
        "皮肤集合": "テーマコレクション",
        "名称": "名前",
        "作者": "作者",
        "排列": "レイアウト",
        "行距": "行間",
        "间距": "間隔",
        "色域": "色空間",
        "背景色": "背景色",
        "候选文字": "候補文字",
        "高亮背景": "ハイライト背景",
        "高亮文字": "ハイライト文字",
        "注释文字": "コメント文字",
        "高亮注释": "ハイライトコメント",
        "拼音": "ピンイン",
        "高亮拼音": "ハイライトピンイン",
        helpMarkdownKey: """
        **NanoMouse**

        **基本方針：Rime の仕組みを尊重し、操作を簡単にする**

        - **非破壊**：NanoMouse は Rime のデフォルト設定ファイル（`default.yaml` と `squirrel.yaml`）を直接変更しません。すべての変更は `default.custom.yaml` または `squirrel.custom.yaml` の `patch` キーに書き込まれます。
        - **ネイティブ体験**：SwiftUI で構築し、macOS らしい操作感を提供します。
        - **透明性**：詳細設定で、マージ後の YAML 設定をいつでも確認できます。

        **よくある質問**

        1. 変更が反映されないのはなぜですか？

           NanoMouse で設定を変更した後、ツールバーの「デプロイ」ボタンをクリックするか `Cmd+R` を押してください。これにより Squirrel が設定を再読み込みします。

        2. 新しい入力方式を追加するには？

           「入力方式」ページで「新しい入力方式を追加」をクリックし、`rime_ice` などの ID と名前を入力します。NanoMouse が基本ファイルを作成し、有効リストに追加します。

        3. 「詳細設定」とは？

           「詳細設定」では Rime の完全な設定ツリーを閲覧し、任意の値を直接編集できます。NanoMouse は変更を対応する `.custom.yaml` ファイルに自動的に書き込みます。これは上級者向け機能です。不明な場合は、通常の設定ページでよく使う項目だけを編集してください。

        4. サンドボックスアクセス

           NanoMouse は通常 `~/Library/Rime` にある Squirrel 設定ファイルを読み書きします。安全にアクセスするため、macOS 上で許可が必要です。Rime ディレクトリを移動した場合は、ここで再度許可してください。
        """
    ]
}
