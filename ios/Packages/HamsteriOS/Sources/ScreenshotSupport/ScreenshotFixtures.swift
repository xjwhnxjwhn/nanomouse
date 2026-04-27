//
//  ScreenshotFixtures.swift
//
//
//  Stable in-memory fixture values used only during screenshot automation.
//

import Foundation
import UIKit

public enum ScreenshotFixtures {
  public static let fixedUserName = "Alex Chen"
  public static let fixedDisplayDate = Date(timeIntervalSince1970: 1_800_000_000)

  public static let markdownDocument = """
  # NanoMouse Studio

  - Capture reusable notes.
  - Turn canvas sketches into files.
  - Send content into Byte Paste slots.

  `Screenshot Mode` keeps this page deterministic for App Store assets.
  """

  static let causalEdges: [VoiceCausalEdgeDraft] = [
    VoiceCausalEdgeDraft(id: "screenshot-causal-1", from: "Idea", to: "Canvas", note: "Sketch"),
    VoiceCausalEdgeDraft(id: "screenshot-causal-2", from: "Canvas", to: "Byte Paste", note: "Store"),
    VoiceCausalEdgeDraft(id: "screenshot-causal-3", from: "Byte Paste", to: "Share", note: "Reuse"),
  ]

  @MainActor
  public static func install(for scenario: ScreenshotScenario) {
    guard ScreenshotMode.isEnabled else { return }
    UIView.setAnimationsEnabled(false)
  }
}
