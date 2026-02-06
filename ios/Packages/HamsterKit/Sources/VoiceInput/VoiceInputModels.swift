//
//  VoiceInputModels.swift
//
//
//  Created by Codex on 2026/2/6.
//

import Foundation

public enum VoiceInputState: String, Codable {
  case idle
  case launching
  case recording
  case processing
  case ready
  case inserted
  case undoWindow
  case cancelled
  case failed
}

public struct VoiceInputSessionPayload: Codable {
  public let requestId: String
  public let state: VoiceInputState
  public let updatedAt: TimeInterval
  public let errorMessage: String?

  public init(requestId: String, state: VoiceInputState, updatedAt: TimeInterval, errorMessage: String? = nil) {
    self.requestId = requestId
    self.state = state
    self.updatedAt = updatedAt
    self.errorMessage = errorMessage
  }
}

public struct VoiceInputResultPayload: Codable {
  public let requestId: String
  public let text: String
  public let localeIdentifier: String?
  public let createdAt: TimeInterval
  public let updatedAt: TimeInterval
  public let consumed: Bool
  public let consumedAt: TimeInterval?

  public init(
    requestId: String,
    text: String,
    localeIdentifier: String?,
    createdAt: TimeInterval,
    updatedAt: TimeInterval,
    consumed: Bool,
    consumedAt: TimeInterval?
  ) {
    self.requestId = requestId
    self.text = text
    self.localeIdentifier = localeIdentifier
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.consumed = consumed
    self.consumedAt = consumedAt
  }
}
