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
        return "请先填写固定城市名称。"
      case .fixedCityNotFound:
        return "没有解析到这个固定城市，请换一个名称再试。"
      }
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

  private override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
  }

  public func refreshIfNeeded(allowAuthorizationPrompt: Bool = false) async {
    let config = currentWeatherConfiguration()
    guard config.enabled else { return }
    if let cache = UserDefaults.hamster.keyboardWeatherIndicatorCache,
       cache.isDisplayable(enabled: true, locationMode: config.locationMode, fixedLocationName: config.fixedLocationName) {
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

    do {
      let resolvedLocation = try await resolveLocation(mode: config.locationMode, fixedLocationName: config.fixedLocationName, allowAuthorizationPrompt: forceAuthorizationPrompt)
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

  public func cacheStatusText() -> String {
    let config = currentWeatherConfiguration()
    guard config.enabled else { return "未启用" }
    guard let cache = UserDefaults.hamster.keyboardWeatherIndicatorCache else {
      return missingCacheReasonText(locationMode: config.locationMode, fixedLocationName: config.fixedLocationName)
    }
    guard cache.matchesConfiguration(locationMode: config.locationMode, fixedLocationName: config.fixedLocationName) else {
      return "配置已变更，请刷新天气缓存。"
    }
    guard cache.isFresh else {
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

  private func currentWeatherConfiguration() -> (enabled: Bool, locationMode: KeyboardWeatherIndicatorLocationMode, fixedLocationName: String?) {
    let toolbar = HamsterAppDependencyContainer.shared.configuration.toolbar
    let enabled = toolbar?.enableWeatherIndicator ?? false
    let locationMode = toolbar?.weatherIndicatorLocationMode ?? .currentLocation
    let fixedLocationName = toolbar?.weatherIndicatorFixedLocationName
    return (enabled, locationMode, fixedLocationName)
  }

  private func missingCacheReasonText(
    locationMode: KeyboardWeatherIndicatorLocationMode,
    fixedLocationName: String?) -> String
  {
    switch locationMode {
    case .currentLocation:
      switch locationManager.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse:
        return "暂无天气缓存，请点击刷新。"
      case .notDetermined:
        return "请点击刷新并允许定位。"
      case .restricted, .denied:
        return "请在系统设置中允许定位。"
      @unknown default:
        return "暂无天气缓存，请点击刷新。"
      }
    case .fixedCity:
      if KeyboardWeatherIndicatorCache.normalizedLocationQuery(fixedLocationName).isEmpty {
        return "请先填写固定城市名称。"
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
