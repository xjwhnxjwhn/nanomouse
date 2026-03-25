import Foundation
import HamsterKit
import OSLog
import UIKit
import UserNotifications

public enum AppNotificationCardAction {
  case requestAuthorization
  case openSystemSettings
  case none
}

public enum AppNotificationToggleOutcome {
  case updated
  case openSystemSettings
}

public struct AppNotificationCardState {
  public let title: String
  public let subtitle: String
  public let buttonTitle: String
  public let tintColor: UIColor
  public let action: AppNotificationCardAction

  public init(
    title: String,
    subtitle: String,
    buttonTitle: String,
    tintColor: UIColor,
    action: AppNotificationCardAction
  ) {
    self.title = title
    self.subtitle = subtitle
    self.buttonTitle = buttonTitle
    self.tintColor = tintColor
    self.action = action
  }
}

public enum AppNotificationRoute: Equatable {
  case home
  case voice
  case clipboard
  case canvas
  case markdown
  case settings
  case deeplink(URL)
}

public extension Notification.Name {
  static let appNotificationStateDidChange = Notification.Name("com.XiangqingZHANG.nanomouse.notification.stateDidChange")
  static let appNotificationRouteDidChange = Notification.Name("com.XiangqingZHANG.nanomouse.notification.routeDidChange")
}

@MainActor
public final class AppNotificationManager: NSObject {
  public static let shared = AppNotificationManager()

  private enum Constants {
    static let installationIdKey = "com.XiangqingZHANG.nanomouse.notification.installationId"
    static let backendBaseURLInfoKey = "NanomouseBackendBaseURL"
    static let productAnnouncementsEnabledKey = "com.XiangqingZHANG.nanomouse.notification.productAnnouncementsEnabled"
  }

  private let center = UNUserNotificationCenter.current()
  private let defaults: UserDefaults
  private let session: URLSession
  private var hasStarted = false
  private var pendingRoute: AppNotificationRoute?

  public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
  public private(set) var deviceTokenHex: String?
  public private(set) var lastRegistrationErrorMessage: String?

  public var installationId: String {
    if let existing = defaults.string(forKey: Constants.installationIdKey), !existing.isEmpty {
      return existing
    }
    let newValue = UUID().uuidString.lowercased()
    defaults.set(newValue, forKey: Constants.installationIdKey)
    return newValue
  }

  public var isSystemNotificationAuthorized: Bool {
    switch authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    default:
      return false
    }
  }

  public var prefersProductAnnouncementsEnabled: Bool {
    if defaults.object(forKey: Constants.productAnnouncementsEnabledKey) == nil {
      return true
    }
    return defaults.bool(forKey: Constants.productAnnouncementsEnabledKey)
  }

  public var isNotificationEnabled: Bool {
    isSystemNotificationAuthorized && prefersProductAnnouncementsEnabled
  }

  public init(
    defaults: UserDefaults = .hamster,
    session: URLSession = .shared
  ) {
    self.defaults = defaults
    self.session = session
    super.init()
  }

  public func start(application: UIApplication) {
    guard hasStarted == false else { return }
    hasStarted = true
    center.delegate = self

    Task {
      await refreshAuthorizationStatus()
      if isSystemNotificationAuthorized {
        application.registerForRemoteNotifications()
      }
      await syncCurrentStatusIfPossible()
    }
  }

  public func currentCardState() -> AppNotificationCardState {
    switch authorizationStatus {
    case .denied:
      return AppNotificationCardState(
        title: "通知：已拒绝",
        subtitle: "系统当前未允许 Nanomouse 发送通知。你可以前往系统设置重新开启。",
        buttonTitle: "前往系统设置",
        tintColor: .systemOrange,
        action: .openSystemSettings
      )
    case .authorized, .provisional, .ephemeral:
      return AppNotificationCardState(
        title: "通知：已开启",
        subtitle: "你将收到产品更新、重要公告和服务状态提示。通知仅作用于主 App。",
        buttonTitle: "通知已开启",
        tintColor: .systemGreen,
        action: .none
      )
    case .notDetermined:
      fallthrough
    @unknown default:
      return AppNotificationCardState(
        title: "通知：未开启",
        subtitle: "开启通知以获取有用提示，并第一时间了解新功能。通知仅作用于主 App。",
        buttonTitle: "开启通知",
        tintColor: .systemRed,
        action: .requestAuthorization
      )
    }
  }

  public func refreshAuthorizationStatus() async {
    let settings = await notificationSettings()
    authorizationStatus = settings.authorizationStatus
    postStateDidChange()
  }

  @discardableResult
  public func requestAuthorizationAndRegister(application: UIApplication = .shared) async -> Bool {
    let granted = await requestAuthorization(options: [.alert, .badge, .sound])
    await refreshAuthorizationStatus()
    if granted {
      application.registerForRemoteNotifications()
    }
    await syncCurrentStatusIfPossible()
    return granted
  }

  public func handleUserToggleChange(
    to isOn: Bool,
    application: UIApplication = .shared
  ) async -> AppNotificationToggleOutcome {
    if !isOn {
      defaults.set(false, forKey: Constants.productAnnouncementsEnabledKey)
      await syncCurrentStatusIfPossible()
      postStateDidChange()
      return .updated
    }

    defaults.set(true, forKey: Constants.productAnnouncementsEnabledKey)
    switch authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      application.registerForRemoteNotifications()
      await syncCurrentStatusIfPossible()
      postStateDidChange()
      return .updated
    case .denied:
      postStateDidChange()
      return .openSystemSettings
    case .notDetermined:
      _ = await requestAuthorizationAndRegister(application: application)
      postStateDidChange()
      return .updated
    @unknown default:
      postStateDidChange()
      return .updated
    }
  }

  public func didRegisterForRemoteNotifications(deviceToken: Data) {
    deviceTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
    lastRegistrationErrorMessage = nil
    postStateDidChange()

    Task {
      await syncCurrentStatusIfPossible()
    }
  }

  public func didFailToRegisterForRemoteNotifications(error: Error) {
    lastRegistrationErrorMessage = error.localizedDescription
    Logger.statistics.error("Debug: APNs register failed: \(error.localizedDescription)")
    postStateDidChange()
  }

  public func stageRoute(from userInfo: [AnyHashable: Any]) {
    pendingRoute = route(from: userInfo)
    guard pendingRoute != nil else { return }
    NotificationCenter.default.post(name: .appNotificationRouteDidChange, object: nil)
  }

  public func consumePendingRoute() -> AppNotificationRoute? {
    let route = pendingRoute
    pendingRoute = nil
    return route
  }

  public func syncCurrentStatusIfPossible() async {
    guard let request = makePushSyncRequest() else {
      return
    }

    do {
      let (_, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      guard (200..<300).contains(httpResponse.statusCode) else {
        throw NSError(
          domain: "NanomousePushSync",
          code: httpResponse.statusCode,
          userInfo: [NSLocalizedDescriptionKey: "Push sync failed with status \(httpResponse.statusCode)"]
        )
      }
      lastRegistrationErrorMessage = nil
      postStateDidChange()
    } catch {
      lastRegistrationErrorMessage = error.localizedDescription
      Logger.statistics.error("Debug: APNs sync failed: \(error.localizedDescription)")
      postStateDidChange()
    }
  }
}

private extension AppNotificationManager {
  func notificationSettings() async -> UNNotificationSettings {
    await withCheckedContinuation { continuation in
      center.getNotificationSettings { settings in
        continuation.resume(returning: settings)
      }
    }
  }

  func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
    await withCheckedContinuation { continuation in
      center.requestAuthorization(options: options) { granted, _ in
        continuation.resume(returning: granted)
      }
    }
  }

  func postStateDidChange() {
    NotificationCenter.default.post(name: .appNotificationStateDidChange, object: nil)
  }

  func route(from userInfo: [AnyHashable: Any]) -> AppNotificationRoute {
    if let deeplink = stringValue(forAnyOf: ["deeplink", "deepLink", "url"], in: userInfo),
       let url = URL(string: deeplink) {
      return .deeplink(url)
    }

    let target = stringValue(forAnyOf: ["target_tab", "targetTab"], in: userInfo)?.lowercased() ?? ""
    switch target {
    case "voice":
      return .voice
    case "clipboard":
      return .clipboard
    case "canvas":
      return .canvas
    case "markdown":
      return .markdown
    case "settings":
      return .settings
    default:
      return .home
    }
  }

  func stringValue(forAnyOf keys: [String], in userInfo: [AnyHashable: Any]) -> String? {
    for key in keys {
      if let value = userInfo[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          return trimmed
        }
      }
    }
    return nil
  }

  func makePushSyncRequest() -> URLRequest? {
    guard let endpointURL = resolvedBackendEndpoint() else {
      return nil
    }

    let hasToken = deviceTokenHex?.isEmpty == false
    let routePath = hasToken ? "/push/register" : "/push/status"
    guard let url = URL(string: routePath, relativeTo: endpointURL)?.absoluteURL else {
      return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    if let accessToken = VoiceBackendAuthStore.shared.sessionState().accessToken,
       accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    let payload: [String: Any?] = [
      "installationId": installationId,
      "platform": "ios",
      "bundleId": Bundle.main.bundleIdentifier ?? "com.XiangqingZHANG.nanomouse",
      "environment": currentPushEnvironment(),
      "deviceToken": hasToken ? deviceTokenHex : nil,
      "pushEnabled": isNotificationEnabled,
      "authorizationStatus": authorizationStatusString(),
      "locale": Locale.preferredLanguages.first ?? Locale.current.identifier,
      "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
      "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
      "timezoneIdentifier": TimeZone.current.identifier
    ]

    let jsonPayload = payload.compactMapValues { $0 }
    request.httpBody = try? JSONSerialization.data(withJSONObject: jsonPayload, options: [])
    return request
  }

  func resolvedBackendEndpoint() -> URL? {
    if let configured = Bundle.main.object(forInfoDictionaryKey: Constants.backendBaseURLInfoKey) as? String {
      let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty, let url = URL(string: trimmed) {
        return normalizedBackendURL(url)
      }
    }

    let loginEndpoint = VoiceBackendAuthStore.shared.loginEndpoint().trimmingCharacters(in: .whitespacesAndNewlines)
    if !loginEndpoint.isEmpty, let url = URL(string: loginEndpoint) {
      if url.path.hasSuffix("/auth/login") {
        let suffix = "/auth/login"
        let path = String(url.path.dropLast(suffix.count))
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = path.isEmpty ? "/" : path
        components?.query = nil
        components?.fragment = nil
        if let normalizedURL = components?.url {
          return normalizedBackendURL(normalizedURL)
        }
      }
      return normalizedBackendURL(url)
    }

    return nil
  }

  func normalizedBackendURL(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }
    if components.path.isEmpty {
      components.path = "/"
    }
    components.query = nil
    components.fragment = nil
    return components.url ?? url
  }

  func currentPushEnvironment() -> String {
    #if DEBUG
    return "Sandbox"
    #else
    return "Production"
    #endif
  }

  func authorizationStatusString() -> String {
    switch authorizationStatus {
    case .notDetermined:
      return "not_determined"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    case .provisional:
      return "provisional"
    case .ephemeral:
      return "ephemeral"
    @unknown default:
      return "unknown"
    }
  }
}

extension AppNotificationManager: UNUserNotificationCenterDelegate {
  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    Task { @MainActor in
      self.stageRoute(from: response.notification.request.content.userInfo)
    }
    completionHandler()
  }
}
