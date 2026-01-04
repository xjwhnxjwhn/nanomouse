//
//  StringError.swift
//
//
//  Created by morse on 2026/1/4.
//

import Foundation

/// Simple error wrapper for string messages.
public struct StringError: LocalizedError, CustomStringConvertible {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var errorDescription: String? {
    message
  }

  public var description: String {
    message
  }
}
