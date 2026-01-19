//
//  UserGuideTips.swift
//
//
//  Created by Codex on 2026/01/19.
//

import Foundation

/// 用户引导提示内容
public struct UserGuideTips {
  /// 所有提示内容（共9条）
  public static let tips: [String] = [
    // 音节替换类
    "nn代替ng：neng可用nenn打出",
    "v代替ua：chuan可用chvn打出",
    "vnn代替uang：chuang可用chvnn打出",
    // 长按技巧类
    "长按语言键：快速切换中日英",
    "长按候选栏：切换繁简体",
    "长按123：调出小键盘和计算器",
    "长按Shift：锁定大写模式",
    "长按字母：显示拉丁字符全集",
    "长按符号键：打开复杂符号键盘",
  ]

  /// 获取指定索引的提示（顺序循环）
  public static func tip(at index: Int) -> String {
    tips[index % tips.count]
  }

  /// 提示总数
  public static var count: Int {
    tips.count
  }
}
