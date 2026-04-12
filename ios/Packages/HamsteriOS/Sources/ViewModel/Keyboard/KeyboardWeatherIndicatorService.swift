import CoreLocation
import HamsterKeyboardKit
import HamsterKit
import OSLog
import UIKit
import WeatherKit

@MainActor
public final class KeyboardWeatherIndicatorService: NSObject {
  public static let shared = KeyboardWeatherIndicatorService()

  private enum WeatherIndicatorError: LocalizedError {
    case featureDisabled
    case locationServicesDisabled
    case locationPermissionRequired
    case locationPermissionDenied
    case locationUnavailable
    case fixedCityMissing
    case fixedCityNotFound
    case refreshCoolingDown(TimeInterval)

    var errorDescription: String? {
      switch self {
      case .featureDisabled:
        return "请先开启顶部天气显示。"
      case .locationServicesDisabled:
        return "系统定位服务当前不可用。"
      case .locationPermissionRequired:
        return "请先允许 Nanomouse 使用定位。"
      case .locationPermissionDenied:
        return "Nanomouse 当前没有定位权限。"
      case .locationUnavailable:
        return "当前位置暂时不可用，请稍后重试。"
      case .fixedCityMissing:
        return "请先选择固定城市。"
      case .fixedCityNotFound:
        return "没有解析到这个固定城市，请重新选择。"
      case .refreshCoolingDown(let remainingTime):
        return "天气刷新冷却中，请\(Self.cooldownText(for: remainingTime))后再试。"
      }
    }

    fileprivate static func cooldownText(for remainingTime: TimeInterval) -> String {
      let seconds = max(Int(ceil(remainingTime)), 1)
      if seconds >= 60 {
        return "\(Int(ceil(Double(seconds) / 60.0))) 分钟"
      }
      return "\(seconds) 秒"
    }
  }

  private struct ResolvedWeatherLocation {
    let mode: KeyboardWeatherIndicatorLocationMode
    let query: String?
    let displayName: String
    let location: CLLocation
  }

  private let locationManager = CLLocationManager()
  private let geocoder = CLGeocoder()
  private var authorizationContinuation: CheckedContinuation<Void, Error>?
  private var locationContinuation: CheckedContinuation<CLLocation, Error>?
  private static let refreshCooldown: TimeInterval = 10 * 60

  private override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
  }

  public func refreshIfNeeded(allowAuthorizationPrompt: Bool = false) async {
    let config = currentWeatherConfiguration()
    guard config.enabled else { return }
    if let cache = UserDefaults.hamster.keyboardWeatherIndicatorCache,
       cache.isDisplayable(
         enabled: true,
         locationMode: config.locationMode,
         fixedLocationName: config.fixedLocationName,
         fixedLatitude: config.fixedLatitude,
         fixedLongitude: config.fixedLongitude
       ) {
      return
    }

    do {
      _ = try await refresh(forceAuthorizationPrompt: allowAuthorizationPrompt)
    } catch {
      UserDefaults.hamster.keyboardWeatherIndicatorCache = nil
      Logger.statistics.error("refresh weather indicator failed: \(error.localizedDescription)")
    }
  }

  @discardableResult
  public func refresh(forceAuthorizationPrompt: Bool) async throws -> KeyboardWeatherIndicatorCache {
    let config = currentWeatherConfiguration()
    guard config.enabled else {
      UserDefaults.hamster.keyboardWeatherIndicatorCache = nil
      throw WeatherIndicatorError.featureDisabled
    }
    try enforceRefreshCooldownIfNeeded()

    do {
      let resolvedLocation = try await resolveLocation(
        mode: config.locationMode,
        fixedLocationName: config.fixedLocationName,
        fixedLatitude: config.fixedLatitude,
        fixedLongitude: config.fixedLongitude,
        allowAuthorizationPrompt: forceAuthorizationPrompt
      )
      UserDefaults.hamster.keyboardWeatherIndicatorLastRefreshAt = Date()
      let currentWeather = try await WeatherService.shared.weather(for: resolvedLocation.location, including: .current)
      let attribution = try? await WeatherService.shared.attribution
      let attributionText: String?
      if #available(iOS 16.4, *) {
        attributionText = attribution?.legalAttributionText
      } else {
        attributionText = nil
      }
      let cache = KeyboardWeatherIndicatorCache(
        sourceLocationMode: resolvedLocation.mode,
        sourceLocationQuery: resolvedLocation.query,
        resolvedLocationName: resolvedLocation.displayName,
        latitude: resolvedLocation.location.coordinate.latitude,
        longitude: resolvedLocation.location.coordinate.longitude,
        symbolName: currentWeather.symbolName,
        temperatureCelsius: currentWeather.temperature.converted(to: .celsius).value,
        apparentTemperatureCelsius: currentWeather.apparentTemperature.converted(to: .celsius).value,
        uvIndexValue: currentWeather.uvIndex.value,
        humidityFraction: currentWeather.humidity,
        updatedAt: Date(),
        attributionServiceName: attribution?.serviceName,
        attributionLegalPageURLString: attribution?.legalPageURL.absoluteString,
        attributionLegalText: attributionText
      )
      UserDefaults.hamster.keyboardWeatherIndicatorCache = cache
      return cache
    } catch {
      UserDefaults.hamster.keyboardWeatherIndicatorCache = nil
      throw error
    }
  }

  public func openLegalAttributionPage() throws {
    guard let cache = UserDefaults.hamster.keyboardWeatherIndicatorCache,
          let rawValue = cache.attributionLegalPageURLString,
          let url = URL(string: rawValue)
    else {
      throw StringError("请先刷新一次天气缓存，再查看 Apple Weather 归因。")
    }
    UIApplication.shared.open(url)
  }

  public func openApplicationSettings() throws {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      throw StringError("无法打开系统设置。")
    }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }

  public func shouldShowOpenLocationSettingsButton(locationMode: KeyboardWeatherIndicatorLocationMode) -> Bool {
    guard locationMode == .currentLocation else { return false }
    switch locationManager.authorizationStatus {
    case .denied, .restricted:
      return true
    default:
      return false
    }
  }

  public func cacheStatusText() -> String {
    let config = currentWeatherConfiguration()
    guard config.enabled else { return "未启用" }
    guard let cache = UserDefaults.hamster.keyboardWeatherIndicatorCache else {
      return missingCacheReasonText(locationMode: config.locationMode, fixedLocationName: config.fixedLocationName)
    }
    guard cache.matchesConfiguration(
      locationMode: config.locationMode,
      fixedLocationName: config.fixedLocationName,
      fixedLatitude: config.fixedLatitude,
      fixedLongitude: config.fixedLongitude
    ) else {
      return "配置已变更，请刷新天气缓存。"
    }
    guard cache.isFresh else {
      if shouldShowOpenLocationSettingsButton(locationMode: config.locationMode) {
        return "缓存已过期，请在系统设置中允许定位。"
      }
      if config.locationMode == .currentLocation, locationManager.authorizationStatus == .notDetermined {
        return "缓存已过期，请点击刷新并允许定位。"
      }
      if let cooldownText = refreshCooldownText() {
        return "缓存已过期，\(cooldownText)后可再次刷新。"
      }
      return "缓存已过期，请刷新天气缓存。"
    }
    return "已更新 · \(cache.resolvedLocationName) · \(Self.statusDateFormatter.string(from: cache.updatedAt))"
  }

  public func attributionSummaryText() -> String {
    if let cache = UserDefaults.hamster.keyboardWeatherIndicatorCache,
       let serviceName = cache.attributionServiceName,
       !serviceName.isEmpty {
      return serviceName
    }
    return "Apple Weather"
  }

  private func resolveLocation(
    mode: KeyboardWeatherIndicatorLocationMode,
    fixedLocationName: String?,
    fixedLatitude: Double?,
    fixedLongitude: Double?,
    allowAuthorizationPrompt: Bool) async throws -> ResolvedWeatherLocation
  {
    switch mode {
    case .currentLocation:
      let location = try await requestCurrentLocation(allowAuthorizationPrompt: allowAuthorizationPrompt)
      let displayName = await reverseLocationName(for: location) ?? "当前位置"
      return ResolvedWeatherLocation(mode: .currentLocation, query: nil, displayName: displayName, location: location)
    case .fixedCity:
      let normalizedQuery = KeyboardWeatherIndicatorCache.normalizedLocationQuery(fixedLocationName)
      guard !normalizedQuery.isEmpty else {
        throw WeatherIndicatorError.fixedCityMissing
      }
      if let fixedLatitude,
         let fixedLongitude
      {
        let location = CLLocation(latitude: fixedLatitude, longitude: fixedLongitude)
        let displayName = fixedLocationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "固定城市"
        return ResolvedWeatherLocation(mode: .fixedCity, query: fixedLocationName, displayName: displayName, location: location)
      }
      let placemarks = try await geocoder.geocodeAddressString(fixedLocationName ?? "")
      guard let placemark = placemarks.first, let location = placemark.location else {
        throw WeatherIndicatorError.fixedCityNotFound
      }
      let displayName = placemark.locality ?? placemark.name ?? (fixedLocationName ?? "固定城市")
      return ResolvedWeatherLocation(mode: .fixedCity, query: fixedLocationName, displayName: displayName, location: location)
    }
  }

  private func requestCurrentLocation(allowAuthorizationPrompt: Bool) async throws -> CLLocation {
    switch locationManager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      break
    case .notDetermined:
      guard allowAuthorizationPrompt else {
        throw WeatherIndicatorError.locationPermissionRequired
      }
      try await withCheckedThrowingContinuation { continuation in
        authorizationContinuation = continuation
        locationManager.requestWhenInUseAuthorization()
      }
    case .restricted, .denied:
      throw WeatherIndicatorError.locationPermissionDenied
    @unknown default:
      throw WeatherIndicatorError.locationPermissionDenied
    }

    return try await withCheckedThrowingContinuation { continuation in
      locationContinuation = continuation
      locationManager.requestLocation()
    }
  }

  private func reverseLocationName(for location: CLLocation) async -> String? {
    do {
      let placemarks = try await geocoder.reverseGeocodeLocation(location)
      let placemark = placemarks.first
      return placemark?.locality ?? placemark?.subLocality ?? placemark?.name
    } catch {
      return nil
    }
  }

  private func currentWeatherConfiguration() -> (
    enabled: Bool,
    locationMode: KeyboardWeatherIndicatorLocationMode,
    fixedLocationName: String?,
    fixedLatitude: Double?,
    fixedLongitude: Double?)
  {
    let toolbar = HamsterAppDependencyContainer.shared.configuration.toolbar
    let enabled = toolbar?.enableWeatherIndicator ?? true
    let locationMode = toolbar?.weatherIndicatorLocationMode ?? .currentLocation
    let fixedLocationName = toolbar?.weatherIndicatorFixedLocationName
    let fixedLatitude = toolbar?.weatherIndicatorFixedLatitude
    let fixedLongitude = toolbar?.weatherIndicatorFixedLongitude
    return (enabled, locationMode, fixedLocationName, fixedLatitude, fixedLongitude)
  }

  private func enforceRefreshCooldownIfNeeded() throws {
#if DEBUG
    return
#else
    guard let lastRefreshAt = UserDefaults.hamster.keyboardWeatherIndicatorLastRefreshAt else { return }
    let elapsed = Date().timeIntervalSince(lastRefreshAt)
    guard elapsed < Self.refreshCooldown else { return }
    throw WeatherIndicatorError.refreshCoolingDown(Self.refreshCooldown - elapsed)
#endif
  }

  private func refreshCooldownText() -> String? {
#if DEBUG
    return nil
#else
    guard let lastRefreshAt = UserDefaults.hamster.keyboardWeatherIndicatorLastRefreshAt else { return nil }
    let elapsed = Date().timeIntervalSince(lastRefreshAt)
    guard elapsed < Self.refreshCooldown else { return nil }
    let remaining = Self.refreshCooldown - elapsed
    return WeatherIndicatorError.cooldownText(for: remaining)
#endif
  }

  private func missingCacheReasonText(
    locationMode: KeyboardWeatherIndicatorLocationMode,
    fixedLocationName: String?) -> String
  {
    switch locationMode {
    case .currentLocation:
      switch locationManager.authorizationStatus {
      case .restricted, .denied:
        return "请在系统设置中允许定位。"
      case .notDetermined:
        if let cooldownText = refreshCooldownText() {
          return "暂无天气缓存，\(cooldownText)后可再次刷新。"
        }
        return "请点击刷新并允许定位。"
      case .authorizedAlways, .authorizedWhenInUse:
        if let cooldownText = refreshCooldownText() {
          return "暂无天气缓存，\(cooldownText)后可再次刷新。"
        }
        return "暂无天气缓存，请点击刷新。"
      @unknown default:
        return "暂无天气缓存，请点击刷新。"
      }
    case .fixedCity:
      if KeyboardWeatherIndicatorCache.normalizedLocationQuery(fixedLocationName).isEmpty {
        return "请先选择固定城市。"
      }
      if let cooldownText = refreshCooldownText() {
        return "暂无天气缓存，\(cooldownText)后可再次刷新。"
      }
      return "暂无天气缓存，请点击刷新。"
    }
  }

  private static let statusDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter
  }()
}

extension KeyboardWeatherIndicatorService: CLLocationManagerDelegate {
  public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      guard let authorizationContinuation else { return }
      switch manager.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse:
        self.authorizationContinuation = nil
        authorizationContinuation.resume()
      case .denied, .restricted:
        self.authorizationContinuation = nil
        authorizationContinuation.resume(throwing: WeatherIndicatorError.locationPermissionDenied)
      case .notDetermined:
        break
      @unknown default:
        self.authorizationContinuation = nil
        authorizationContinuation.resume(throwing: WeatherIndicatorError.locationPermissionDenied)
      }
    }
  }

  public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in
      guard let locationContinuation else { return }
      self.locationContinuation = nil
      if let location = locations.last {
        locationContinuation.resume(returning: location)
      } else {
        locationContinuation.resume(throwing: WeatherIndicatorError.locationUnavailable)
      }
    }
  }

  public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      guard let locationContinuation else { return }
      self.locationContinuation = nil
      if let locationError = error as? CLError {
        switch locationError.code {
        case .denied:
          locationContinuation.resume(throwing: WeatherIndicatorError.locationPermissionDenied)
        case .locationUnknown:
          locationContinuation.resume(throwing: WeatherIndicatorError.locationUnavailable)
        default:
          locationContinuation.resume(throwing: error)
        }
      } else {
        locationContinuation.resume(throwing: error)
      }
    }
  }
}
