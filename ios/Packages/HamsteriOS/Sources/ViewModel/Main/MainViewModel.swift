//
//  File.swift
//
//
//  Created by morse on 2023/7/7.
//

import Combine
import Foundation
import HamsterKit

public class MainViewModel: ObservableObject {
  public let subViewSubject = PassthroughSubject<SettingsSubView, Never>()
  public var subViewPublished: AnyPublisher<SettingsSubView, Never> {
    subViewSubject.eraseToAnyPublisher()
  }
  private var pendingKeyboardSettingsNavigationRequested = false
  private var pendingKeyboardSettingsSubView: KeyboardSettingsSubView?
  private var pendingKeyboardToolbarSettingsFocus: KeyboardToolbarSettingsFocus?

  public let shortcutItemTypeSubject = PassthroughSubject<ShortcutItemType, Never>()
  public var shortcutItemTypePublished: AnyPublisher<ShortcutItemType, Never> {
    shortcutItemTypeSubject.eraseToAnyPublisher()
  }

  /// 导航到输入方案页面
  public func navigationToInputSchema() {
    subViewSubject.send(.inputSchema)
  }

  /// 导航到 RIME 设置页面
  public func navigationToRIME() {
    subViewSubject.send(.rime)
  }

  public func stageKeyboardSettingsNavigation(
    subView: KeyboardSettingsSubView? = nil,
    toolbarFocus: KeyboardToolbarSettingsFocus? = nil)
  {
    pendingKeyboardSettingsNavigationRequested = true
    pendingKeyboardSettingsSubView = subView
    pendingKeyboardToolbarSettingsFocus = toolbarFocus
  }

  public func navigationToKeyboardSettings(
    subView: KeyboardSettingsSubView? = nil,
    toolbarFocus: KeyboardToolbarSettingsFocus? = nil)
  {
    stageKeyboardSettingsNavigation(subView: subView, toolbarFocus: toolbarFocus)
    subViewSubject.send(.keyboardSettings)
  }

  public func consumePendingKeyboardSettingsNavigationRequested() -> Bool {
    let requested = pendingKeyboardSettingsNavigationRequested
    pendingKeyboardSettingsNavigationRequested = false
    return requested
  }

  public func consumePendingKeyboardSettingsSubView() -> KeyboardSettingsSubView? {
    let subView = pendingKeyboardSettingsSubView
    pendingKeyboardSettingsSubView = nil
    return subView
  }

  public func consumePendingKeyboardToolbarSettingsFocus() -> KeyboardToolbarSettingsFocus? {
    let focus = pendingKeyboardToolbarSettingsFocus
    pendingKeyboardToolbarSettingsFocus = nil
    return focus
  }

  public func execShortcutCommand(_ shortItemType: ShortcutItemType) {
    shortcutItemTypeSubject.send(shortItemType)
  }

  public func navigation(_ subView: SettingsSubView) {
    subViewSubject.send(subView)
  }
}
