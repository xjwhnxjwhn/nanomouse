//
//  Logger.swift
//  Hamster
//
//  Created by morse on 2/8/2023.
//

import OSLog

public extension Logger {
  private static var subsystem = Bundle.main.bundleIdentifier ?? "com.nanomouse"

  private static let isKeyboardExtension: Bool = {
    let identifier = Bundle.main.bundleIdentifier ?? ""
    return identifier.contains(".keyboard")
  }()

  static let statistics: Logger = {
    if isKeyboardExtension {
      return Logger(OSLog.disabled)
    }
    return Logger(subsystem: subsystem, category: "statistics")
  }()
}
