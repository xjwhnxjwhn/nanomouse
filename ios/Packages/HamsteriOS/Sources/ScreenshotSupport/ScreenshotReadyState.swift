//
//  ScreenshotReadyState.swift
//
//
//  Exposes stable accessibility identifiers that UI tests can wait for.
//

import UIKit

public enum ScreenshotReadyState {
  private static let readyViewTag = 0x5C5C_2026

  @MainActor
  public static func markReady(on rootView: UIView, for scenario: ScreenshotScenario) {
    clear(from: rootView)

    let readyView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    readyView.translatesAutoresizingMaskIntoConstraints = false
    readyView.tag = readyViewTag
    readyView.isUserInteractionEnabled = false
    readyView.isAccessibilityElement = true
    readyView.accessibilityIdentifier = scenario.readyIdentifier
    readyView.accessibilityLabel = scenario.readyIdentifier
    readyView.backgroundColor = .clear

    rootView.addSubview(readyView)
    NSLayoutConstraint.activate([
      readyView.widthAnchor.constraint(equalToConstant: 1),
      readyView.heightAnchor.constraint(equalToConstant: 1),
      readyView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      readyView.topAnchor.constraint(equalTo: rootView.topAnchor),
    ])
  }

  @MainActor
  public static func clear(from rootView: UIView) {
    rootView.subviews
      .filter { $0.tag == readyViewTag }
      .forEach { $0.removeFromSuperview() }
  }
}
