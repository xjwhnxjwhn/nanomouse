//
//  ChineseKeyboardLayoutProfile.swift
//
//
//  Created by OpenAI on 2026/5/11.
//

import Foundation

public struct ChineseKeyboardLayoutProfile: Codable, Hashable, Identifiable {
  public var id: String
  public var name: String
  /// key: default slot action id, value: assigned action id.
  public var mapping: [String: String]

  public init(id: String = UUID().uuidString, name: String, mapping: [String: String]) {
    self.id = id
    self.name = name
    self.mapping = mapping
  }
}

public enum ChineseKeyboardOneHandMode: String, Codable, CaseIterable {
  case off
  case leftArc
  case rightArc

  public var title: String {
    switch self {
    case .off: return "关闭"
    case .leftArc: return "左手圆盘"
    case .rightArc: return "右手圆盘"
    }
  }
}
