//
//  ScreenshotRouter.swift
//
//
//  Direct scenario router for fastlane / XCUITest screenshot launches.
//

import UIKit

@MainActor
public final class ScreenshotRouter {
  @discardableResult
  public static func routeIfNeeded(from rootViewController: UIViewController?) -> Bool {
    guard ScreenshotMode.isEnabled else { return false }
    let scenario = ScreenshotMode.scenario ?? .home

    ScreenshotFixtures.install(for: scenario)

    if let theme = ScreenshotMode.theme {
      rootViewController?.overrideUserInterfaceStyle = theme.userInterfaceStyle
    }

    rootViewController?.loadViewIfNeeded()

    if let theme = ScreenshotMode.theme {
      rootViewController?.view.window?.overrideUserInterfaceStyle = theme.userInterfaceStyle
    }

    if let tabBarController = rootViewController as? MainTabBarController {
      tabBarController.activateScreenshotScenario(scenario)
    }

    if let rootView = rootViewController?.view {
      rootView.setNeedsLayout()
      rootView.layoutIfNeeded()
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: scenario.readyDelayNanoseconds)
        ScreenshotReadyState.markReady(on: rootView, for: scenario)
      }
    }

    return true
  }
}
