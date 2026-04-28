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

    if scenario == .keyboardExtension {
      installKeyboardExtensionScreenshotHost(on: rootViewController)
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

  private static func installKeyboardExtensionScreenshotHost(on rootViewController: UIViewController?) {
    guard let rootViewController else { return }
    guard rootViewController.children.contains(where: { $0 is KeyboardExtensionScreenshotHostViewController }) == false else {
      return
    }

    let host = KeyboardExtensionScreenshotHostViewController()
    rootViewController.addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    rootViewController.view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: rootViewController.view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: rootViewController.view.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: rootViewController.view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: rootViewController.view.bottomAnchor),
    ])
    host.didMove(toParent: rootViewController)
    rootViewController.view.setNeedsLayout()
    rootViewController.view.layoutIfNeeded()

    guard rootViewController.view.window != nil else { return }
    host.beginAppearanceTransition(true, animated: false)
    host.endAppearanceTransition()
  }
}
