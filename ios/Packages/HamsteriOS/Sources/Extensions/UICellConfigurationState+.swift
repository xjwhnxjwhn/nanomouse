//
//  UICellConfigurationState+.swift
//
//
//  Created by morse on 2023/9/24.
//

import UIKit

extension UIConfigurationStateCustomKey {
  static let settingItemModel = UIConfigurationStateCustomKey("com.XiangqingZHANG.nanomouse.keyboard.settings.SettingItem")
}

extension UICellConfigurationState {
  var settingItemModel: SettingItemModel? {
    set { self[.settingItemModel] = newValue }
    get { return self[.settingItemModel] as? SettingItemModel }
  }
}
