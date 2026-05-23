import CoreLocation
import Foundation
import HamsterKit
import OSLog
import WeatherKit

@MainActor
final class KeyboardWeatherIndicatorExtensionRefreshService {
  static let shared = KeyboardWeatherIndicatorExtensionRefreshService()

  private struct WeatherRefreshRequest {
    let enabled: Bool
    let locationMode: KeyboardWeatherIndicatorLocationMode
    let fixedLocationName: String?
    let fixedLatitude: Double?
    let fixedLongitude: Double?

    init(toolbar: KeyboardToolbarConfiguration?) {
      self.enabled = toolbar?.enableWeatherIndicator ?? true
      self.locationMode = toolbar?.weatherIndicatorLocationMode ?? .currentLocation
      self.fixedLocationName = toolbar?.weatherIndicatorFixedLocationName
      self.fixedLatitude = toolbar?.weatherIndicatorFixedLatitude
      self.fixedLongitude = toolbar?.weatherIndicatorFixedLongitude
    }
  }

  private struct ResolvedWeatherLocation {
    let mode: KeyboardWeatherIndicatorLocationMode
    let query: String?
    let displayName: String
    let location: CLLocation
  }

  private enum WeatherRefreshError: Error {
    case noFullAccess
    case currentLocationUnavailableInExtension
    case fixedCityMissing
    case fixedCityNotFound
  }

  private let geocoder = CLGeocoder()
  private var refreshTask: Task<Bool, Never>?
  private var lastFailedRefreshAttemptAt: Date?

  private static let failedRetryInterval: TimeInterval = 5 * 60
  private static let successCooldown: TimeInterval = 60

  private init() {}

  func refreshIfNeeded(toolbar: KeyboardToolbarConfiguration?, hasFullAccess: Bool) async -> Bool {
    if let refreshTask {
      return await refreshTask.value
    }

    let request = WeatherRefreshRequest(toolbar: toolbar)
    guard shouldAttemptRefresh(request: request, hasFullAccess: hasFullAccess) else {
      return false
    }

    let task = Task { [weak self] in
      guard let self else { return false }
      do {
        _ = try await self.refresh(request: request)
        self.lastFailedRefreshAttemptAt = nil
        return true
      } catch {
        self.lastFailedRefreshAttemptAt = Date()
        Logger.statistics.error("keyboard extension weather refresh failed: \(error.localizedDescription)")
        return false
      }
    }
    refreshTask = task
    let didRefresh = await task.value
    refreshTask = nil
    return didRefresh
  }

  private func shouldAttemptRefresh(request: WeatherRefreshRequest, hasFullAccess: Bool) -> Bool {
    guard request.enabled else { return false }
    guard hasFullAccess else {
      Logger.statistics.debug("skip keyboard extension weather refresh: full access disabled")
      return false
    }
    if let cache = UserDefaults.hamster.keyboardWeatherIndicatorCache,
       cache.isDisplayable(
         enabled: true,
         locationMode: request.locationMode,
         fixedLocationName: request.fixedLocationName,
         fixedLatitude: request.fixedLatitude,
         fixedLongitude: request.fixedLongitude
       )
    {
      return false
    }
    if let lastFailedRefreshAttemptAt,
       Date().timeIntervalSince(lastFailedRefreshAttemptAt) < Self.failedRetryInterval
    {
      return false
    }
    if let lastRefreshAt = UserDefaults.hamster.keyboardWeatherIndicatorLastRefreshAt,
       Date().timeIntervalSince(lastRefreshAt) < Self.successCooldown
    {
      return false
    }

    switch request.locationMode {
    case .currentLocation:
      return false
    case .fixedCity:
      return !KeyboardWeatherIndicatorCache.normalizedLocationQuery(request.fixedLocationName).isEmpty
    }
  }

  @discardableResult
  private func refresh(request: WeatherRefreshRequest) async throws -> KeyboardWeatherIndicatorCache {
    let resolvedLocation = try await resolveLocation(request: request)
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
    UserDefaults.hamster.keyboardWeatherIndicatorLastRefreshAt = cache.updatedAt
    return cache
  }

  private func resolveLocation(request: WeatherRefreshRequest) async throws -> ResolvedWeatherLocation {
    switch request.locationMode {
    case .currentLocation:
      throw WeatherRefreshError.currentLocationUnavailableInExtension
    case .fixedCity:
      let normalizedQuery = KeyboardWeatherIndicatorCache.normalizedLocationQuery(request.fixedLocationName)
      guard !normalizedQuery.isEmpty else {
        throw WeatherRefreshError.fixedCityMissing
      }
      if let fixedLatitude = request.fixedLatitude,
         let fixedLongitude = request.fixedLongitude
      {
        return ResolvedWeatherLocation(
          mode: .fixedCity,
          query: request.fixedLocationName,
          displayName: request.fixedLocationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "固定城市",
          location: CLLocation(latitude: fixedLatitude, longitude: fixedLongitude)
        )
      }
      let placemarks = try await geocoder.geocodeAddressString(request.fixedLocationName ?? "")
      guard let placemark = placemarks.first, let location = placemark.location else {
        throw WeatherRefreshError.fixedCityNotFound
      }
      return ResolvedWeatherLocation(
        mode: .fixedCity,
        query: request.fixedLocationName,
        displayName: placemark.locality ?? placemark.name ?? (request.fixedLocationName ?? "固定城市"),
        location: location
      )
    }
  }

}
