//
//  KeyboardType+OneHand.swift
//
//
//  Created by Codex on 2026/05/23.
//

extension KeyboardType {
  var supportsChineseOneHandToolbarSwitch: Bool {
    switch self {
    case .chinese, .chineseNumeric, .chineseSymbolic, .calculatorNumeric:
      return true
    default:
      return false
    }
  }

  var supportsChineseOneHandKeyboardHeight: Bool {
    supportsChineseOneHandToolbarSwitch
  }
}
