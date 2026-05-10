import Combine
import HamsterUIKit
import UIKit

public class FullAccessGuideViewModel: ObservableObject {
  private var cancellables = Set<AnyCancellable>()

  // 页面标题
  var title: String { AppL10n.text("开启完全访问") }

  // 引导内容数据模型
  struct GuideItem: Identifiable {
    let id = UUID()
    let icon: String // SF Symbol name
    let title: String
    let description: String
  }

  var guideItems: [GuideItem] {
    [
      GuideItem(
        icon: "externaldrive.badge.icloud",
        title: AppL10n.text("iCloud 同步与备份"),
        description: AppL10n.text("应用需要联网权限才能将您的配置和词库同步到 iCloud，实现多设备间的数据漫游与备份。")
      ),
      GuideItem(
        icon: "waveform",
        title: AppL10n.text("震动反馈与按键音"),
        description: AppL10n.text("键盘扩展在沙盒中运行，需要完全访问权限才能调用系统的震动马达和音频服务，提供更好的打字手感。")
      ),
      GuideItem(
        icon: "textformat.abc",
        title: AppL10n.text("系统文本替换"),
        description: AppL10n.text("允许键盘读取您在 iOS 设置中配置的文本替换快捷键，让您在输入时快速展开常用短语。")
      )
    ]
  }

  // 隐私承诺文案
  var privacyPromise: String {
    AppL10n.text("""
    鼠输入法（NanoMouse）是开源软件，代码完全公开可查。
    · 不收集输入内容
    · 不上传个人信息
    · 联网仅用于 iCloud 同步
    """)
  }

  // 顶部操作引导
  var actionGuide: String {
    AppL10n.text("打开系统设置后，进入“键盘”并开启“允许完全访问”。iOS 公开接口只能打开本 App 的系统设置页，后续路径需要用户按系统界面继续选择。")
  }

  init() {}

  @MainActor
  func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }
}
