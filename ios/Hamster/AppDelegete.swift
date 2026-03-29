//
//  AppDelegete.swift
//  Hamster
//
//  Created by morse on 2023/6/5.
//

import CloudKit
import HamsteriOS
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    MainAppEmbeddedModuleRegistry.shared.registerDefaultPrivateProvidersIfNeeded()
    AppNotificationManager.shared.start(application: application)
    // Override point for customization after application launch.
    return true
  }

  // MARK: UISceneSession Lifecycle

  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }

  func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    _ = application
    AppNotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    _ = application
    AppNotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    _ = application

    guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
      completionHandler(.noData)
      return
    }

    Task {
      let handled = await MainAppEmbeddedModuleRegistry.shared.handleRemoteNotification(userInfo: userInfo)
      completionHandler(handled ? .newData : .noData)
    }
  }
}
