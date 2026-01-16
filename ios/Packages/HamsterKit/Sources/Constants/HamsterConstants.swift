//
//  HamsterConstants.swift
//
//
//  Created by morse on 2023/7/3.
//

import Foundation

/// 鼠输入法应用常量
public enum HamsterConstants {
  /// AppGroup ID
  public static let appGroupName = "group.com.XiangqingZHANG.nanomouse"

  /// iCloud ID
  public static let iCloudID = "iCloud.com.XiangqingZHANG.nanomouse"

  /// keyboard Bundle ID
  public static let keyboardBundleID = "com.XiangqingZHANG.nanomouse.keyboard"

  /// 跳转至系统添加键盘URL
  public static let addKeyboardPath = "app-settings:root=General&path=Keyboard/KEYBOARDS"

  // MARK: 与Squirrel.app保持一致

  /// RIME 预先构建的数据目录中
  public static let rimeSharedSupportPathName = "SharedSupport"

  /// RIME UserData目录
  public static let rimeUserPathName = "Rime"

  /// RIME 内置输入方案及配置zip包
  public static let inputSchemaZipFile = "SharedSupport.zip"

  /// 额外输入方案 zip 包（按需下载，不随包内置）
  public static let extraInputSchemaZipFiles: [String] = []

  /// 按需下载的 zip 包基础地址（GitHub raw）
  public static let onDemandInputSchemaZipBaseURL = "https://raw.githubusercontent.com/xjwhnxjwhn/nanomouse/main/zips"

  /// 日语方案 zip 包（按需下载）
  public static let onDemandJapaneseSchemaZipMap: [String: String] = [
    "japanese": "rime-japanese.zip",
    "jaroomaji": "rime-jaroomaji.zip",
    "jaroomaji-easy": "rime-jaroomaji-easy.zip",
  ]

  /// AzooKey 方案 schemaId
  public static let azooKeySchemaId = "azookey"

  /// AzooKey 词库 zip 包（按需下载）
  public static let azooKeyDictionaryZipFile = "azookey-dictionary.zip"

  /// AzooKey Zenzai 权重 zip 包（按需下载）
  public static let azooKeyZenzaiZipFile = "azookey-zenzai.zip"

  /// 其他可选方案 zip 包（按需下载）
  public static let onDemandExtraZipFiles: [String] = [
    "rime-terra-pinyin.zip",
    "rime-stroke.zip",
    "rime-hangyl.zip",
    "rime-hannomps.zip",
  ]

  /// 仓内置方案 zip 包
  public static let userDataZipFile = "rime-ice.zip"

  /// APP URL
  /// 注意: 此值需要与info.plist中的参数保持一致
  public static let appURL = "nanomouse://com.XiangqingZHANG.nanomouse"
}
