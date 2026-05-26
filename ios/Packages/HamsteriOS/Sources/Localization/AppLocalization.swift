import Foundation

enum AppDisplayLanguage: String, CaseIterable {
  case system
  case zhHans = "zh-Hans"
  case zhHant = "zh-Hant"
  case en
  case ja

  var nativeTitle: String {
    switch self {
    case .system:
      switch AppDisplayLanguage.resolveSystemLanguage() {
      case .zhHans, .system:
        return "跟随系统"
      case .zhHant:
        return "跟隨系統"
      case .en:
        return "Follow System"
      case .ja:
        return "システムに合わせる"
      }
    case .zhHans: return "简体中文"
    case .zhHant: return "繁體中文"
    case .en: return "English"
    case .ja: return "日本語"
    }
  }

  var localeIdentifier: String {
    switch self {
    case .system:
      return AppDisplayLanguage.resolveSystemLanguage().localeIdentifier
    case .zhHans:
      return "zh-Hans"
    case .zhHant:
      return "zh-Hant"
    case .en:
      return "en"
    case .ja:
      return "ja"
    }
  }

  static func resolveSystemLanguage() -> AppDisplayLanguage {
    resolveSystemLanguage(from: deviceLanguageIdentifiers())
  }

  static func resolveSystemLanguage(from preferredLanguages: [String]) -> AppDisplayLanguage {
    for identifier in preferredLanguages {
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

  private static func deviceLanguageIdentifiers() -> [String] {
    var identifiers: [String] = []
    // The global language list is the closest signal for the device system language.
    if let globalLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] {
      identifiers.append(contentsOf: globalLanguages)
    }
    if let standardLanguages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") {
      identifiers.append(contentsOf: standardLanguages)
    }
    identifiers.append(Locale.autoupdatingCurrent.identifier)
    identifiers.append(Locale.current.identifier)
    identifiers.append(contentsOf: Locale.preferredLanguages)

    return identifiers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
}

final class AppLocalization {
  static let shared = AppLocalization()
  static let userDefaultsKey = "nanomouse.app.display_language.v1"
  static let didChangeNotification = Notification.Name("NanomouseAppDisplayLanguageDidChange")

  private let userDefaults: UserDefaults

  private init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  var selectedLanguage: AppDisplayLanguage {
    get {
      guard let rawValue = userDefaults.string(forKey: Self.userDefaultsKey),
            let language = AppDisplayLanguage(rawValue: rawValue)
      else {
        return .system
      }
      return language
    }
    set {
      guard selectedLanguage != newValue else { return }
      userDefaults.set(newValue.rawValue, forKey: Self.userDefaultsKey)
      NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
  }

  var effectiveLanguage: AppDisplayLanguage {
    let selected = selectedLanguage
    return selected == .system ? AppDisplayLanguage.resolveSystemLanguage() : selected
  }

  func text(_ source: String) -> String {
    guard let localized = Self.translations[effectiveLanguage]?[source] else {
      return source
    }
    return localized
  }

  func format(_ source: String, _ arguments: CVarArg...) -> String {
    format(source, arguments: arguments)
  }

  func format(_ source: String, arguments: [CVarArg]) -> String {
    String(
      format: text(source),
      locale: Locale(identifier: effectiveLanguage.localeIdentifier),
      arguments: arguments
    )
  }
}

enum AppL10n {
  static func text(_ source: String) -> String {
    AppLocalization.shared.text(source)
  }

  static func format(_ source: String, _ arguments: CVarArg...) -> String {
    AppLocalization.shared.format(source, arguments: arguments)
  }
}

private extension AppLocalization {
  static let translations: [AppDisplayLanguage: [String: String]] = [
    .zhHans: [:],
    .zhHant: zhHant,
    .en: en,
    .ja: ja
  ]

  static let zhHant: [String: String] = [
    "OK": "OK",
    "知道了": "知道了",
    "确定": "確定",
    "取消": "取消",
    "保存": "儲存",
    "完成": "完成",
    "删除": "刪除",
    "清空": "清空",
    "编辑": "編輯",
    "重试": "重試",
    "（当前）": "（目前）",
    "已开启": "已開啟",
    "推荐": "推薦",
    "前往设置": "前往設定",
    "清空历史记录": "清空歷史記錄",
    "该操作仅会删除本机记录，是否继续？": "此操作只會刪除本機記錄，是否繼續？",
    "识别失败": "識別失敗",
    "操作失败": "操作失敗",
    "识别引擎": "識別引擎",
    "识别引擎是互斥单选：Apple / Whisper / 在线。若选择 Whisper，模型预热期间会临时使用 Apple，不改变你的勾选。点击 Whisper 或 在线可进入独立设置页面。": "識別引擎為互斥單選：Apple / Whisper / 線上。若選擇 Whisper，模型預熱期間會臨時使用 Apple，不會改變你的勾選。點擊 Whisper 或線上可進入獨立設定頁。",
    "设置": "設定",
    "输入法设置": "輸入法設定",
    "键盘": "鍵盤",
    "<账户": "<帳戶",
    "画布": "畫布",
    "语音": "語音",
    "账户": "帳戶",
    "字节粘贴": "位元組貼上",
    "字节粘贴设置": "位元組貼上設定",
    "格子": "格子",
    "剪贴板": "剪貼簿",
    "剪贴板历史": "剪貼簿歷史",
    "显示语言": "顯示語言",
    "跟随系统": "跟隨系統",
    "简体中文": "簡體中文",
    "当前语言": "目前語言",
    "默认跟随手机的语言设置。这里仅改变 App 内显示和说明文字，不影响键盘输入方案。": "預設跟隨手機的語言設定。這裡只會改變 App 內的顯示和說明文字，不影響鍵盤輸入方案。",
    "跟随系统语言": "跟隨系統語言",
    "系统当前会使用：%@": "系統目前會使用：%@",
    "产品通知": "產品通知",
    "开启完全访问": "開啟完整取用",
    "账号与订阅（开发中）": "帳戶與訂閱（開發中）",
    "账号与订阅": "帳戶與訂閱",
    "偏好设置": "偏好設定",
    "账号": "帳戶",
    "订阅": "訂閱",
    "社区支持": "社群支持",
    "隐私与权限": "隱私與權限",
    "打开失败": "開啟失敗",
    "GitHub 仓库地址无效。": "GitHub 倉庫地址無效。",
    "功能开发中": "功能開發中",
    "账号登录与订阅绑定正在开发中，请暂时不要输入任何账号信息。": "帳戶登入與訂閱綁定正在開發中，請暫時不要輸入任何帳戶資訊。",
    "隐私与权限说明": "隱私與權限說明",
    "前往系统设置": "前往系統設定",
    "Nanomouse 仅在你点击“开始口述”后请求麦克风与语音识别权限。键盘扩展本身不直接录音。若你启用在线 ASR 或在线 LLM，文本或音频会按你的配置发送到对应服务商。你可以随时在系统设置中关闭权限。": "Nanomouse 僅在你點擊「開始口述」後請求麥克風與語音識別權限。鍵盤擴充本身不直接錄音。若你啟用線上 ASR 或線上 LLM，文字或音訊會依你的設定傳送至對應服務商。你可以隨時在系統設定中關閉權限。",
    "如果你希望我加速推出订阅服务来使用在线大模型，请务必点赞让我看到；因为当前仅支持用户自带各厂商 API Key。": "如果你希望我加速推出訂閱服務來使用線上大模型，請務必按讚讓我看到；因為目前僅支援使用者自帶各廠商 API Key。",
    "上架审核提示：语音权限仅用于听写；你不使用语音输入时，应用不会主动录音。": "上架審核提示：語音權限僅用於聽寫；你不使用語音輸入時，App 不會主動錄音。",
    "账号系统开发中（暂不开放登录）": "帳戶系統開發中（暫不開放登入）",
    "管理订阅": "管理訂閱",
    "GitHub Stars 读取中...": "GitHub Stars 讀取中...",
    "GitHub Star 支持我们 ⭐（%d）": "GitHub Star 支持我們 ⭐（%d）",
    "GitHub Star 支持我们 ⭐（点击查看）": "GitHub Star 支持我們 ⭐（點擊查看）",
    "查看隐私与权限说明": "查看隱私與權限說明",
    "语音模型": "語音模型",
    "AI 处理配置": "AI 處理設定",
    "启用键盘扩展语音界面": "啟用鍵盤擴充語音介面",
    "词典": "詞典",
    "历史记录": "歷史記錄",
    "日记": "日記",
    "日历": "日曆",
    "文件": "檔案",
    "这一天还没有日记素材": "這一天還沒有日記素材",
    "还没有记录的日记素材": "還沒有記錄的日記素材",
    "清空所有日记素材？": "清空所有日記素材？",
    "该操作会删除本机 App Group 中保存的日记素材。": "此操作會刪除本機 App Group 中儲存的日記素材。",
    "日记文件": "日記檔案",
    "%d 条": "%d 條",
    "复制整天": "複製整天",
    "分享整天": "分享整天",
    "编辑文件": "編輯檔案",
    "删除文件": "刪除檔案",
    "输入密码": "輸入密碼",
    "验证身份后查看日记内容": "驗證身分後查看日記內容",
    "无法打开日记": "無法開啟日記",
    "请先在系统设置中开启 Face ID 或设备密码，再查看日记内容。": "請先在系統設定中開啟 Face ID 或裝置密碼，再查看日記內容。",
    "认证未通过": "認證未通過",
    "日记内容未打开。": "日記內容未開啟。",
    "画布保存位置": "畫布儲存位置",
    "打开系统设置": "開啟系統設定",
    "iCloud 同步与备份": "iCloud 同步與備份",
    "应用需要联网权限才能将您的配置和词库同步到 iCloud，实现多设备间的数据漫游与备份。": "App 需要網路權限，才能將您的設定和詞庫同步到 iCloud，實現多裝置間的資料漫遊與備份。",
    "震动反馈与按键音": "震動回饋與按鍵音",
    "键盘扩展在沙盒中运行，需要完全访问权限才能调用系统的震动马达和音频服务，提供更好的打字手感。": "鍵盤擴充在沙盒中執行，需要完整取用權限才能呼叫系統震動馬達和音訊服務，提供更好的打字手感。",
    "系统文本替换": "系統文字替換",
    "允许键盘读取您在 iOS 设置中配置的文本替换快捷键，让您在输入时快速展开常用短语。": "允許鍵盤讀取您在 iOS 設定中配置的文字替換快捷鍵，讓您輸入時快速展開常用短語。",
    "鼠输入法（NanoMouse）是开源软件，代码完全公开可查。\n· 不收集输入内容\n· 不上传个人信息\n· 联网仅用于 iCloud 同步": "鼠輸入法（NanoMouse）是開源軟體，程式碼完全公開可查。\n· 不收集輸入內容\n· 不上傳個人資訊\n· 連網僅用於 iCloud 同步",
    "打开系统设置后，进入“键盘”并开启“允许完全访问”。iOS 公开接口只能打开本 App 的系统设置页，后续路径需要用户按系统界面继续选择。": "開啟系統設定後，進入「鍵盤」並開啟「允許完整取用」。iOS 公開介面只能開啟本 App 的系統設定頁，後續路徑需要使用者依照系統介面繼續選擇。",
    "语音输入已暂停": "語音輸入已暫停",
    "你当前关闭了语音输入，请先在首页开启后再继续听写。": "你目前關閉了語音輸入，請先在首頁開啟後再繼續聽寫。",
    "语音输入状态": "語音輸入狀態",
    "你关闭开关后，首页入口会阻止新的听写会话；键盘入口会在启动时自动恢复语音状态。": "你關閉開關後，首頁入口會阻止新的聽寫會話；鍵盤入口會在啟動時自動恢復語音狀態。",
    "不活动自动关闭": "閒置自動關閉",
    "选择超过多久未使用后自动关闭语音输入。": "選擇超過多久未使用後自動關閉語音輸入。",
    "复制失败": "複製失敗",
    "桌面版链接暂不可用，请稍后重试。": "桌面版連結暫不可用，請稍後重試。",
    "已复制": "已複製",
    "桌面版下载链接已复制到剪贴板。": "桌面版下載連結已複製到剪貼簿。",
    "AI 语音输入": "AI 語音輸入",
    "总听写时间": "總聽寫時間",
    "字": "字",
    "听写字数": "聽寫字數",
    "节省的时间": "節省的時間",
    "每分钟字数": "每分鐘字數",
    "平均听写速度": "平均聽寫速度",
    "在桌面上使用 Nanomouse": "在桌面上使用 Nanomouse",
    "复制下载链接": "複製下載連結",
    "Nanomouse 已开启": "Nanomouse 已開啟",
    "Nanomouse 已暂停": "Nanomouse 已暫停",
    "开始口述": "開始口述",
    "轻触开关可暂停语音输入": "輕觸開關可暫停語音輸入",
    "语音输入已暂停，请先开启后再继续听写。": "語音輸入已暫停，請先開啟後再繼續聽寫。",
    "在不活动时关闭：%@ ▾": "閒置時關閉：%@ ▾",
    "%d 分钟": "%d 分鐘",
    "%d 小时": "%d 小時",
    "暂无历史记录": "暫無歷史記錄",
    "你完成一次语音输入后，历史记录会自动保存在本机。": "你完成一次語音輸入後，歷史記錄會自動保存在本機。",
    "保留历史": "保留歷史",
    "永久": "永久",
    "您的数据保持私密，听写记录仅存储在设备上。": "您的資料保持私密，聽寫記錄僅儲存在裝置上。",
    "添加词条": "新增詞條",
    "输入你想优先识别的词语。": "輸入你想優先識別的詞語。",
    "例如：Nanomouse、项目代号": "例如：Nanomouse、專案代號",
    "词典仅包含手动词条，这些词会注入 Apple Speech、Whisper 与在线 ASR（按引擎能力）以提升专有名词识别稳定性。": "詞典僅包含手動詞條，這些詞會注入 Apple Speech、Whisper 與線上 ASR（依引擎能力）以提升專有名詞識別穩定性。",
    "尚无手动词条": "尚無手動詞條",
    "点击右下角 + 添加你想优先识别的专有名词。": "點擊右下角 + 新增你想優先識別的專有名詞。",
    "键盘权限": "鍵盤權限",
    "未开启也可基础输入；开启“完全访问权限”后，可用完整词库写入、配置同步与键盘震动等功能。\n联网仅用于你的 iCloud 同步，不会上传到其他服务器。\n路径：点击“打开设置” -> 键盘 -> 开启“允许完全访问”": "未開啟也可基本輸入；開啟「完整取用」後，可使用完整詞庫寫入、設定同步與鍵盤震動等功能。\n連網僅用於你的 iCloud 同步，不會上傳到其他伺服器。\n路徑：點擊「開啟設定」 -> 鍵盤 -> 開啟「允許完整取用」",
    "输入方案与键盘布局": "輸入方案與鍵盤佈局",
    "输入相关": "輸入相關",
    "输入方案设置": "輸入方案設定",
    "Wi-Fi上传方案": "Wi-Fi 上傳方案",
    "文件管理": "檔案管理",
    "键盘相关": "鍵盤相關",
    "键盘设置": "鍵盤設定",
    "键盘布局": "鍵盤佈局",
    "键盘视觉效果": "鍵盤視覺效果",
    "键盘配色": "鍵盤配色",
    "启用": "啟用",
    "禁用": "停用",
    "按键音与震动": "按鍵音與震動",
    "同步与备份": "同步與備份",
    "iCloud同步": "iCloud 同步",
    "软件备份": "軟體備份",
    "关于": "關於",
    "重新部署": "重新部署",
    "RIME同步": "RIME 同步",
    "应用备份": "App 備份",
    "迁移 1.0 配置中……": "正在遷移 1.0 設定……",
    "迁移完成": "遷移完成",
    "初次启动，需要编译输入方案，请耐心等待……": "首次啟動需要編譯輸入方案，請稍候……",
    "部署完成": "部署完成",
    "导入数据异常": "匯入資料異常"
  ]

  static let en: [String: String] = [
    "OK": "OK",
    "知道了": "OK",
    "确定": "OK",
    "取消": "Cancel",
    "保存": "Save",
    "完成": "Done",
    "删除": "Delete",
    "清空": "Clear",
    "编辑": "Edit",
    "重试": "Retry",
    "（当前）": " (current)",
    "已开启": "On",
    "推荐": "Recommended",
    "前往设置": "Open Settings",
    "清空历史记录": "Clear History",
    "该操作仅会删除本机记录，是否继续？": "This only deletes local history on this device. Continue?",
    "识别失败": "Recognition failed",
    "操作失败": "Operation Failed",
    "识别引擎": "Recognition Engine",
    "识别引擎是互斥单选：Apple / Whisper / 在线。若选择 Whisper，模型预热期间会临时使用 Apple，不改变你的勾选。点击 Whisper 或 在线可进入独立设置页面。": "Recognition engines are mutually exclusive: Apple, Whisper, or Online. If Whisper is selected, Apple may be used temporarily while the model warms up. Tap Whisper or Online to open its settings.",
    "设置": "Settings",
    "输入法设置": "Keyboard Settings",
    "键盘": "Keyboard",
    "<账户": "< Account",
    "画布": "Canvas",
    "语音": "Voice",
    "账户": "Account",
    "字节粘贴": "Byte Paste",
    "字节粘贴设置": "Byte Paste Settings",
    "格子": "Slots",
    "剪贴板": "Clipboard",
    "剪贴板历史": "Clipboard History",
    "显示语言": "Display Language",
    "跟随系统": "Follow System",
    "简体中文": "Simplified Chinese",
    "当前语言": "Current Language",
    "默认跟随手机的语言设置。这里仅改变 App 内显示和说明文字，不影响键盘输入方案。": "By default, the app follows the phone language. This only changes in-app labels and help text; it does not change keyboard input layouts.",
    "跟随系统语言": "Follow System Language",
    "系统当前会使用：%@": "System currently uses: %@",
    "产品通知": "Product Notifications",
    "开启完全访问": "Enable Full Access",
    "账号与订阅（开发中）": "Account & Subscription (in development)",
    "账号与订阅": "Account & Subscription",
    "偏好设置": "Preferences",
    "账号": "Account",
    "订阅": "Subscription",
    "社区支持": "Community Support",
    "隐私与权限": "Privacy & Permissions",
    "打开失败": "Open Failed",
    "GitHub 仓库地址无效。": "The GitHub repository URL is invalid.",
    "功能开发中": "Feature in Development",
    "账号登录与订阅绑定正在开发中，请暂时不要输入任何账号信息。": "Account sign-in and subscription binding are still in development. Please do not enter account information yet.",
    "隐私与权限说明": "Privacy & Permissions",
    "前往系统设置": "Open System Settings",
    "Nanomouse 仅在你点击“开始口述”后请求麦克风与语音识别权限。键盘扩展本身不直接录音。若你启用在线 ASR 或在线 LLM，文本或音频会按你的配置发送到对应服务商。你可以随时在系统设置中关闭权限。": "Nanomouse requests microphone and speech recognition permissions only after you tap Start Dictation. The keyboard extension does not record audio by itself. If you enable online ASR or online LLM, text or audio is sent to the provider you configured. You can disable permissions in System Settings at any time.",
    "Nanomouse 只会在你主动使用对应功能时请求系统权限：点击“开始口述”后请求麦克风与语音识别；刷新当前位置天气时请求定位；拍照或导入/导出图片时请求相机或照片权限；开启产品通知时请求通知权限；查看日记时使用 Face ID 或设备密码；通过浏览器上传输入方案时会使用本地网络；启用 iCloud/CloudKit 同步时数据由 Apple iCloud 处理。键盘扩展本身不直接录音。若你启用在线 ASR 或在线 LLM，文本或音频会按你的配置发送到对应服务商。你可以随时在系统设置中关闭权限。": "Nanomouse requests system permissions only when you actively use the corresponding feature: microphone and speech recognition after you tap Start Dictation; location when refreshing current-location weather; camera or photo access when taking photos or importing/exporting images; notifications when enabling product notifications; Face ID or device passcode when viewing diary content; local network when uploading input schemas through a browser; and Apple iCloud handles data when iCloud/CloudKit sync is enabled. The keyboard extension does not record audio by itself. If you enable online ASR or online LLM, text or audio is sent to the provider you configured. You can disable permissions in System Settings at any time.",
    "如果你希望我加速推出订阅服务来使用在线大模型，请务必点赞让我看到；因为当前仅支持用户自带各厂商 API Key。": "If you want subscription-based online models to arrive sooner, please star the project so I can see the demand. Currently, only user-provided API keys are supported.",
    "上架审核提示：语音权限仅用于听写；你不使用语音输入时，应用不会主动录音。": "App Review note: speech permissions are used only for dictation. The app does not record when you are not using voice input.",
    "账号系统开发中（暂不开放登录）": "Account system in development (sign-in unavailable)",
    "管理订阅": "Manage Subscriptions",
    "GitHub Stars 读取中...": "Loading GitHub Stars...",
    "GitHub Star 支持我们 ⭐（%d）": "Support us with a GitHub Star ⭐ (%d)",
    "GitHub Star 支持我们 ⭐（点击查看）": "Support us with a GitHub Star ⭐ (tap to view)",
    "查看隐私与权限说明": "View Privacy & Permissions",
    "语音模型": "Voice Models",
    "AI 处理配置": "AI Processing Settings",
    "启用键盘扩展语音界面": "Voice UI in Keyboard Extension",
    "词典": "Dictionary",
    "历史记录": "History",
    "日记": "Diary",
    "日历": "Calendar",
    "文件": "Files",
    "这一天还没有日记素材": "No diary material for this day",
    "还没有记录的日记素材": "No recorded diary material yet",
    "清空所有日记素材？": "Clear all diary material?",
    "该操作会删除本机 App Group 中保存的日记素材。": "This will delete diary material saved in the local App Group.",
    "日记文件": "Diary Files",
    "%d 条": "%d items",
    "复制整天": "Copy Day",
    "分享整天": "Share Day",
    "编辑文件": "Edit File",
    "删除文件": "Delete File",
    "输入密码": "Enter Passcode",
    "验证身份后查看日记内容": "Authenticate to view diary content",
    "无法打开日记": "Cannot Open Diary",
    "请先在系统设置中开启 Face ID 或设备密码，再查看日记内容。": "Enable Face ID or a device passcode in System Settings before viewing diary content.",
    "认证未通过": "Authentication Failed",
    "日记内容未打开。": "Diary content was not opened.",
    "画布保存位置": "Canvas Save Location",
    "打开系统设置": "Open System Settings",
    "iCloud 同步与备份": "iCloud Sync & Backup",
    "应用需要联网权限才能将您的配置和词库同步到 iCloud，实现多设备间的数据漫游与备份。": "The app needs network access to sync your settings and dictionary to iCloud for backup and cross-device use.",
    "震动反馈与按键音": "Haptics & Key Sounds",
    "键盘扩展在沙盒中运行，需要完全访问权限才能调用系统的震动马达和音频服务，提供更好的打字手感。": "The keyboard extension runs in a sandbox. Full Access lets it use system haptics and audio services for better typing feedback.",
    "系统文本替换": "System Text Replacement",
    "允许键盘读取您在 iOS 设置中配置的文本替换快捷键，让您在输入时快速展开常用短语。": "Allow the keyboard to read text replacement shortcuts configured in iOS Settings, so common phrases can expand while typing.",
    "鼠输入法（NanoMouse）是开源软件，代码完全公开可查。\n· 不收集输入内容\n· 不上传个人信息\n· 联网仅用于 iCloud 同步": "NanoMouse is open source and its code is public.\n· Does not collect typed content\n· Does not upload personal information\n· Network access is used only for iCloud sync",
    "打开系统设置后，进入“键盘”并开启“允许完全访问”。iOS 公开接口只能打开本 App 的系统设置页，后续路径需要用户按系统界面继续选择。": "After opening System Settings, go to Keyboard and enable Allow Full Access. iOS only allows apps to open their own Settings page, so the remaining steps must be completed in the system UI.",
    "语音输入已暂停": "Voice Input Paused",
    "你当前关闭了语音输入，请先在首页开启后再继续听写。": "Voice input is currently off. Turn it on from the home page before continuing dictation.",
    "语音输入状态": "Voice Input Status",
    "你关闭开关后，首页入口会阻止新的听写会话；键盘入口会在启动时自动恢复语音状态。": "When this switch is off, the home entry blocks new dictation sessions. The keyboard entry restores voice status automatically when launched.",
    "不活动自动关闭": "Auto-close When Inactive",
    "选择超过多久未使用后自动关闭语音输入。": "Choose how long voice input can remain unused before it is turned off.",
    "复制失败": "Copy Failed",
    "桌面版链接暂不可用，请稍后重试。": "The desktop download link is unavailable. Please try again later.",
    "已复制": "Copied",
    "桌面版下载链接已复制到剪贴板。": "The desktop download link has been copied to the clipboard.",
    "AI 语音输入": "AI Voice Input",
    "总听写时间": "Total Dictation Time",
    "字": "chars",
    "听写字数": "Dictated Characters",
    "节省的时间": "Time Saved",
    "每分钟字数": "chars/min",
    "平均听写速度": "Average Dictation Speed",
    "在桌面上使用 Nanomouse": "Use Nanomouse on Desktop",
    "复制下载链接": "Copy Download Link",
    "Nanomouse 已开启": "Nanomouse is On",
    "Nanomouse 已暂停": "Nanomouse is Paused",
    "开始口述": "Start Dictation",
    "轻触开关可暂停语音输入": "Tap the switch to pause voice input",
    "语音输入已暂停，请先开启后再继续听写。": "Voice input is paused. Turn it on before continuing dictation.",
    "在不活动时关闭：%@ ▾": "Close when inactive: %@ ▾",
    "%d 分钟": "%d min",
    "%d 小时": "%d hr",
    "暂无历史记录": "No History Yet",
    "你完成一次语音输入后，历史记录会自动保存在本机。": "After you finish a dictation, the history is saved on this device.",
    "保留历史": "Keep History",
    "永久": "Forever",
    "您的数据保持私密，听写记录仅存储在设备上。": "Your data stays private. Dictation history is stored only on this device.",
    "添加词条": "Add Word",
    "输入你想优先识别的词语。": "Enter words you want the recognizer to prioritize.",
    "例如：Nanomouse、项目代号": "Example: Nanomouse, project codename",
    "词典仅包含手动词条，这些词会注入 Apple Speech、Whisper 与在线 ASR（按引擎能力）以提升专有名词识别稳定性。": "The dictionary contains manually added words. They are injected into Apple Speech, Whisper, and online ASR when supported to improve recognition of proper nouns.",
    "尚无手动词条": "No Manual Words",
    "点击右下角 + 添加你想优先识别的专有名词。": "Tap + in the lower-right corner to add proper nouns you want prioritized.",
    "键盘权限": "Keyboard Permissions",
    "未开启也可基础输入；开启“完全访问权限”后，可用完整词库写入、配置同步与键盘震动等功能。\n联网仅用于你的 iCloud 同步，不会上传到其他服务器。\n路径：点击“打开设置” -> 键盘 -> 开启“允许完全访问”": "Basic typing works without it. After enabling Full Access, the keyboard can write to the full dictionary, sync settings, and use haptics.\nNetwork access is used only for your iCloud sync and is not uploaded to other servers.\nPath: tap Open Settings -> Keyboard -> enable Allow Full Access",
    "输入方案与键盘布局": "Input Schemas & Keyboard Layout",
    "输入相关": "Input",
    "输入方案设置": "Input Schemas",
    "Wi-Fi上传方案": "Upload Schema via Wi-Fi",
    "文件管理": "File Manager",
    "键盘相关": "Keyboard",
    "键盘设置": "Keyboard Settings",
    "键盘布局": "Keyboard Layout",
    "键盘视觉效果": "Keyboard Visual Effects",
    "键盘配色": "Keyboard Colors",
    "启用": "Enabled",
    "禁用": "Disabled",
    "按键音与震动": "Key Sounds & Haptics",
    "同步与备份": "Sync & Backup",
    "iCloud同步": "iCloud Sync",
    "软件备份": "App Backup",
    "关于": "About",
    "重新部署": "Redeploy",
    "RIME同步": "RIME Sync",
    "应用备份": "App Backup",
    "迁移 1.0 配置中……": "Migrating 1.0 settings...",
    "迁移完成": "Migration Complete",
    "初次启动，需要编译输入方案，请耐心等待……": "First launch needs to compile input schemas. Please wait...",
    "部署完成": "Deployment Complete",
    "导入数据异常": "Data Import Error"
  ]

  static let ja: [String: String] = [
    "OK": "OK",
    "知道了": "OK",
    "确定": "OK",
    "取消": "キャンセル",
    "保存": "保存",
    "完成": "完了",
    "删除": "削除",
    "清空": "消去",
    "编辑": "編集",
    "重试": "再試行",
    "（当前）": "（現在）",
    "已开启": "オン",
    "推荐": "推奨",
    "前往设置": "設定へ移動",
    "清空历史记录": "履歴を消去",
    "该操作仅会删除本机记录，是否继续？": "この操作では、このデバイスの履歴のみ削除されます。続行しますか？",
    "识别失败": "認識に失敗しました",
    "操作失败": "操作に失敗しました",
    "识别引擎": "認識エンジン",
    "识别引擎是互斥单选：Apple / Whisper / 在线。若选择 Whisper，模型预热期间会临时使用 Apple，不改变你的勾选。点击 Whisper 或 在线可进入独立设置页面。": "認識エンジンは Apple / Whisper / オンラインのいずれか一つです。Whisperを選んだ場合、モデルの準備中は一時的にAppleを使うことがあります。Whisperまたはオンラインをタップすると個別設定を開けます。",
    "设置": "設定",
    "输入法设置": "キーボード設定",
    "键盘": "キーボード",
    "<账户": "< アカウント",
    "画布": "キャンバス",
    "语音": "音声",
    "账户": "アカウント",
    "字节粘贴": "Byte Paste",
    "字节粘贴设置": "Byte Paste設定",
    "格子": "スロット",
    "剪贴板": "クリップボード",
    "剪贴板历史": "クリップボード履歴",
    "显示语言": "表示言語",
    "跟随系统": "システムに合わせる",
    "简体中文": "簡体字中国語",
    "当前语言": "現在の言語",
    "默认跟随手机的语言设置。这里仅改变 App 内显示和说明文字，不影响键盘输入方案。": "初期設定では端末の言語に従います。ここで変更されるのはアプリ内の表示と説明文のみで、キーボードの入力方式には影響しません。",
    "跟随系统语言": "システム言語に合わせる",
    "系统当前会使用：%@": "システムでは現在 %@ が使われます",
    "产品通知": "製品のお知らせ",
    "开启完全访问": "フルアクセスを有効化",
    "账号与订阅（开发中）": "アカウントとサブスクリプション（開発中）",
    "账号与订阅": "アカウントとサブスクリプション",
    "偏好设置": "環境設定",
    "账号": "アカウント",
    "订阅": "サブスクリプション",
    "社区支持": "コミュニティ支援",
    "隐私与权限": "プライバシーと権限",
    "打开失败": "開けませんでした",
    "GitHub 仓库地址无效。": "GitHubリポジトリのURLが無効です。",
    "功能开发中": "機能は開発中です",
    "账号登录与订阅绑定正在开发中，请暂时不要输入任何账号信息。": "アカウントログインとサブスクリプション連携は開発中です。現時点ではアカウント情報を入力しないでください。",
    "隐私与权限说明": "プライバシーと権限",
    "前往系统设置": "システム設定へ移動",
    "Nanomouse 仅在你点击“开始口述”后请求麦克风与语音识别权限。键盘扩展本身不直接录音。若你启用在线 ASR 或在线 LLM，文本或音频会按你的配置发送到对应服务商。你可以随时在系统设置中关闭权限。": "Nanomouseは「音声入力を開始」をタップした後にのみ、マイクと音声認識の権限を要求します。キーボード拡張自体は録音しません。オンラインASRまたはオンラインLLMを有効にした場合、設定したプロバイダにテキストまたは音声が送信されます。権限はシステム設定でいつでも無効にできます。",
    "如果你希望我加速推出订阅服务来使用在线大模型，请务必点赞让我看到；因为当前仅支持用户自带各厂商 API Key。": "オンライン大規模モデルを使うためのサブスクリプション機能を早く使いたい場合は、需要が分かるようにGitHubでスターをお願いします。現在は各プロバイダのAPIキー持ち込みのみ対応しています。",
    "上架审核提示：语音权限仅用于听写；你不使用语音输入时，应用不会主动录音。": "審査向け注記：音声権限は音声入力にのみ使用されます。音声入力を使っていないとき、アプリが録音することはありません。",
    "账号系统开发中（暂不开放登录）": "アカウント機能は開発中です（ログイン不可）",
    "管理订阅": "サブスクリプションを管理",
    "GitHub Stars 读取中...": "GitHub Starsを読み込み中...",
    "GitHub Star 支持我们 ⭐（%d）": "GitHub Starで応援 ⭐（%d）",
    "GitHub Star 支持我们 ⭐（点击查看）": "GitHub Starで応援 ⭐（タップして表示）",
    "查看隐私与权限说明": "プライバシーと権限の説明を見る",
    "语音模型": "音声モデル",
    "AI 处理配置": "AI処理設定",
    "启用键盘扩展语音界面": "キーボード拡張の音声UIを有効化",
    "词典": "辞書",
    "历史记录": "履歴",
    "日记": "日記",
    "日历": "カレンダー",
    "文件": "ファイル",
    "这一天还没有日记素材": "この日の日記素材はまだありません",
    "还没有记录的日记素材": "記録された日記素材はまだありません",
    "清空所有日记素材？": "すべての日記素材を消去しますか？",
    "该操作会删除本机 App Group 中保存的日记素材。": "この操作により、このデバイスのApp Groupに保存された日記素材が削除されます。",
    "日记文件": "日記ファイル",
    "%d 条": "%d件",
    "复制整天": "1日分をコピー",
    "分享整天": "1日分を共有",
    "编辑文件": "ファイルを編集",
    "删除文件": "ファイルを削除",
    "输入密码": "パスコードを入力",
    "验证身份后查看日记内容": "日記の内容を表示するには認証してください",
    "无法打开日记": "日記を開けません",
    "请先在系统设置中开启 Face ID 或设备密码，再查看日记内容。": "日記の内容を表示する前に、システム設定でFace IDまたはデバイスのパスコードを有効にしてください。",
    "认证未通过": "認証に失敗しました",
    "日记内容未打开。": "日記の内容は開かれませんでした。",
    "画布保存位置": "キャンバスの保存先",
    "打开系统设置": "システム設定を開く",
    "iCloud 同步与备份": "iCloud同期とバックアップ",
    "应用需要联网权限才能将您的配置和词库同步到 iCloud，实现多设备间的数据漫游与备份。": "設定と辞書をiCloudに同期し、複数デバイスで共有・バックアップするためにネットワークアクセスが必要です。",
    "震动反馈与按键音": "触覚フィードバックとキー音",
    "键盘扩展在沙盒中运行，需要完全访问权限才能调用系统的震动马达和音频服务，提供更好的打字手感。": "キーボード拡張はサンドボックス内で動作します。フルアクセスを許可すると、システムの触覚フィードバックと音声サービスを使って入力感を向上できます。",
    "系统文本替换": "システムのユーザ辞書",
    "允许键盘读取您在 iOS 设置中配置的文本替换快捷键，让您在输入时快速展开常用短语。": "iOS設定のテキスト置換を読み取り、入力中によく使う語句をすばやく展開できるようにします。",
    "鼠输入法（NanoMouse）是开源软件，代码完全公开可查。\n· 不收集输入内容\n· 不上传个人信息\n· 联网仅用于 iCloud 同步": "NanoMouseはオープンソースで、コードは公開されています。\n· 入力内容を収集しません\n· 個人情報をアップロードしません\n· ネットワークはiCloud同期のみに使用します",
    "打开系统设置后，进入“键盘”并开启“允许完全访问”。iOS 公开接口只能打开本 App 的系统设置页，后续路径需要用户按系统界面继续选择。": "システム設定を開いた後、「キーボード」に進み「フルアクセスを許可」をオンにしてください。iOSの公開APIではこのアプリの設定ページまでしか開けないため、その後の操作はシステム画面で行う必要があります。",
    "语音输入已暂停": "音声入力は一時停止中",
    "你当前关闭了语音输入，请先在首页开启后再继续听写。": "音声入力がオフになっています。ホームでオンにしてから音声入力を続けてください。",
    "语音输入状态": "音声入力の状態",
    "你关闭开关后，首页入口会阻止新的听写会话；键盘入口会在启动时自动恢复语音状态。": "このスイッチをオフにすると、ホームから新しい音声入力を開始できません。キーボードから起動した場合は音声状態が自動的に復元されます。",
    "不活动自动关闭": "未使用時に自動終了",
    "选择超过多久未使用后自动关闭语音输入。": "未使用のままどれくらい経過したら音声入力を自動でオフにするかを選びます。",
    "复制失败": "コピーに失敗しました",
    "桌面版链接暂不可用，请稍后重试。": "デスクトップ版のリンクは現在利用できません。後でもう一度お試しください。",
    "已复制": "コピーしました",
    "桌面版下载链接已复制到剪贴板。": "デスクトップ版のダウンロードリンクをクリップボードにコピーしました。",
    "AI 语音输入": "AI音声入力",
    "总听写时间": "音声入力の合計時間",
    "字": "文字",
    "听写字数": "入力文字数",
    "节省的时间": "短縮できた時間",
    "每分钟字数": "文字/分",
    "平均听写速度": "平均入力速度",
    "在桌面上使用 Nanomouse": "デスクトップでNanomouseを使う",
    "复制下载链接": "ダウンロードリンクをコピー",
    "Nanomouse 已开启": "Nanomouseはオンです",
    "Nanomouse 已暂停": "Nanomouseは一時停止中",
    "开始口述": "音声入力を開始",
    "轻触开关可暂停语音输入": "スイッチをタップすると音声入力を一時停止できます",
    "语音输入已暂停，请先开启后再继续听写。": "音声入力は一時停止中です。オンにしてから続けてください。",
    "在不活动时关闭：%@ ▾": "未使用時に閉じる：%@ ▾",
    "%d 分钟": "%d分",
    "%d 小时": "%d時間",
    "暂无历史记录": "履歴はまだありません",
    "你完成一次语音输入后，历史记录会自动保存在本机。": "音声入力を完了すると、履歴はこのデバイスに保存されます。",
    "保留历史": "履歴を保存",
    "永久": "無期限",
    "您的数据保持私密，听写记录仅存储在设备上。": "データはプライベートに保たれます。音声入力の履歴はこのデバイスにのみ保存されます。",
    "添加词条": "単語を追加",
    "输入你想优先识别的词语。": "優先して認識させたい単語を入力してください。",
    "例如：Nanomouse、项目代号": "例：Nanomouse、プロジェクト名",
    "词典仅包含手动词条，这些词会注入 Apple Speech、Whisper 与在线 ASR（按引擎能力）以提升专有名词识别稳定性。": "辞書には手動で追加した単語のみが含まれます。対応する範囲でApple Speech、Whisper、オンラインASRに渡され、固有名詞の認識精度を高めます。",
    "尚无手动词条": "手動単語はまだありません",
    "点击右下角 + 添加你想优先识别的专有名词。": "右下の + をタップして、優先して認識させたい固有名詞を追加します。",
    "键盘权限": "キーボード権限",
    "未开启也可基础输入；开启“完全访问权限”后，可用完整词库写入、配置同步与键盘震动等功能。\n联网仅用于你的 iCloud 同步，不会上传到其他服务器。\n路径：点击“打开设置” -> 键盘 -> 开启“允许完全访问”": "有効にしなくても基本入力は使えます。フルアクセスを有効にすると、辞書への書き込み、設定同期、触覚フィードバックなどを利用できます。\nネットワークはiCloud同期のみに使用し、他のサーバーへはアップロードしません。\n手順：「設定を開く」-> キーボード ->「フルアクセスを許可」をオン",
    "输入方案与键盘布局": "入力方式とキーボード配列",
    "输入相关": "入力",
    "输入方案设置": "入力方式の設定",
    "Wi-Fi上传方案": "Wi-Fiで入力方式をアップロード",
    "文件管理": "ファイル管理",
    "键盘相关": "キーボード",
    "键盘设置": "キーボード設定",
    "键盘布局": "キーボード配列",
    "键盘视觉效果": "キーボード視覚効果",
    "键盘配色": "キーボード配色",
    "启用": "有効",
    "禁用": "無効",
    "按键音与震动": "キー音と触覚",
    "同步与备份": "同期とバックアップ",
    "iCloud同步": "iCloud同期",
    "软件备份": "アプリのバックアップ",
    "关于": "情報",
    "重新部署": "再デプロイ",
    "RIME同步": "RIME同期",
    "应用备份": "アプリのバックアップ",
    "迁移 1.0 配置中……": "1.0設定を移行中...",
    "迁移完成": "移行が完了しました",
    "初次启动，需要编译输入方案，请耐心等待……": "初回起動では入力方式のコンパイルが必要です。しばらくお待ちください...",
    "部署完成": "デプロイが完了しました",
    "导入数据异常": "データの読み込みエラー"
  ]
}
