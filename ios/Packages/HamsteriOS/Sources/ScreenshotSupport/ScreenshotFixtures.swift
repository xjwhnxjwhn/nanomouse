//
//  ScreenshotFixtures.swift
//
//
//  Stable in-memory fixture values used only during screenshot automation.
//

import Foundation
import HamsterKit
import PencilKit
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

  public static func nanoMouseDrawing() -> PKDrawing {
    let color = UIColor.label
    let strokes = nanoMouseStrokePointGroups().compactMap { points -> PKStroke? in
      guard points.count > 1 else { return nil }
      let fittedPoints = points.map { point in
        CGPoint(
          x: (point.x - 34) * 1.24,
          y: (point.y - 96) * 1.75
        )
      }
      let controlPoints = fittedPoints.enumerated().map { index, point in
        PKStrokePoint(
          location: point,
          timeOffset: TimeInterval(index) * 0.012,
          size: CGSize(width: 12, height: 12),
          opacity: 0.96,
          force: 1,
          azimuth: 0,
          altitude: .pi / 2
        )
      }
      let path = PKStrokePath(controlPoints: controlPoints, creationDate: fixedDisplayDate)
      return PKStroke(ink: PKInk(.pen, color: color), path: path)
    }
    return PKDrawing(strokes: strokes)
  }

  public static func nanoMouseCanvasImage(color: UIColor) -> UIImage {
    let size = CGSize(width: 760, height: 180)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
      color.setStroke()

      for points in nanoMouseStrokePointGroups() where points.count > 1 {
        let transformed = points.map { point in
          CGPoint(
            x: (point.x - 34) * 1.12,
            y: 18 + (point.y - 96) * 1.48
          )
        }

        let path = UIBezierPath()
        path.move(to: transformed[0])
        for point in transformed.dropFirst() {
          path.addLine(to: point)
        }
        path.lineWidth = 10
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
      }
    }
  }

  @MainActor
  public static func install(for scenario: ScreenshotScenario) {
    guard ScreenshotMode.isEnabled else { return }
    UIView.setAnimationsEnabled(false)
    disableSimulatorHardwareKeyboardIfNeeded()
    configureKeyboardScreenshotRuntime(for: scenario)
  }

  private static func disableSimulatorHardwareKeyboardIfNeeded() {
    #if DEBUG && targetEnvironment(simulator)
    let selector = NSSelectorFromString("setHardwareLayout:")
    for inputMode in UITextInputMode.activeInputModes where inputMode.responds(to: selector) {
      _ = inputMode.perform(selector, with: nil)
    }
    #endif
  }

  private static func configureKeyboardScreenshotRuntime(for scenario: ScreenshotScenario) {
    let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName)
    defaults?.set(scenario.isKeyboardScreenshot, forKey: "NanoMouseScreenshotKeyboardMode")
    defaults?.set(scenario.rawValue, forKey: "NanoMouseScreenshotKeyboardScenario")
    defaults?.synchronize()
  }

  private static func nanoMouseStrokePointGroups() -> [[CGPoint]] {
    [
      [CGPoint(x: 34, y: 184), CGPoint(x: 34, y: 96), CGPoint(x: 86, y: 182), CGPoint(x: 86, y: 96)],
      [CGPoint(x: 106, y: 158), CGPoint(x: 126, y: 128), CGPoint(x: 154, y: 146), CGPoint(x: 148, y: 180), CGPoint(x: 118, y: 184), CGPoint(x: 102, y: 162), CGPoint(x: 151, y: 160), CGPoint(x: 166, y: 184)],
      [CGPoint(x: 184, y: 184), CGPoint(x: 184, y: 126), CGPoint(x: 204, y: 150), CGPoint(x: 224, y: 126), CGPoint(x: 224, y: 184)],
      [CGPoint(x: 250, y: 154), CGPoint(x: 270, y: 128), CGPoint(x: 300, y: 144), CGPoint(x: 298, y: 174), CGPoint(x: 268, y: 186), CGPoint(x: 248, y: 164)],
      [CGPoint(x: 326, y: 184), CGPoint(x: 326, y: 96), CGPoint(x: 368, y: 156), CGPoint(x: 410, y: 96), CGPoint(x: 410, y: 184)],
      [CGPoint(x: 436, y: 154), CGPoint(x: 456, y: 128), CGPoint(x: 486, y: 144), CGPoint(x: 484, y: 174), CGPoint(x: 454, y: 186), CGPoint(x: 434, y: 164)],
      [CGPoint(x: 510, y: 126), CGPoint(x: 510, y: 174), CGPoint(x: 532, y: 184), CGPoint(x: 554, y: 126), CGPoint(x: 554, y: 184)],
      [CGPoint(x: 588, y: 132), CGPoint(x: 558, y: 142), CGPoint(x: 588, y: 158), CGPoint(x: 562, y: 184), CGPoint(x: 596, y: 178)],
      [CGPoint(x: 620, y: 156), CGPoint(x: 670, y: 156), CGPoint(x: 650, y: 126), CGPoint(x: 622, y: 144), CGPoint(x: 638, y: 184), CGPoint(x: 678, y: 174)]
    ]
  }
}
