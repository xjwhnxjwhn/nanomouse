import Combine
import HamsterUIKit
import UIKit

public class FullAccessGuideViewModel: ObservableObject {
  private var cancellables = Set<AnyCancellable>()

  // 页面标题
  let title = "开启完全访问"

  // 引导内容数据模型
  struct GuideItem: Identifiable {
    let id = UUID()
    let icon: String // SF Symbol name
    let title: String
    let description: String
  }

  let guideItems: [GuideItem] = [
    GuideItem(
      icon: "externaldrive.badge.icloud",
      title: "iCloud 同步与备份",
      description: "应用需要联网权限才能将您的配置和词库同步到 iCloud，实现多设备间的数据漫游与备份。"
    ),
    GuideItem(
      icon: "waveform",
      title: "震动反馈与按键音",
      description: "键盘扩展在沙盒中运行，需要完全访问权限才能调用系统的震动马达和音频服务，提供更好的打字手感。"
    ),
    GuideItem(
      icon: "textformat.abc",
      title: "系统文本替换",
      description: "允许键盘读取您在 iOS 设置中配置的文本替换快捷键，让您在输入时快速展开常用短语。"
    )
  ]

  // 隐私承诺文案
  let privacyPromise = """
  鼠输入法（NanoMouse）是开源软件，代码完全公开可查。
  · 不收集输入内容
  · 不上传个人信息
  · 联网仅用于 iCloud 同步
  """

  // 顶部操作引导
  let actionGuide = "点击上方按钮 -> 选择键盘 -> 开启「允许完全访问」"

  init() {}

  @MainActor
  func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }
}
