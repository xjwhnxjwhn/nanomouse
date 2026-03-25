import Foundation

public enum KeyboardWeatherIndicatorMetric: String, Codable, CaseIterable, Hashable {
  case temperature
  case apparentTemperature
  case uvIndex
  case humidity

  public var title: String {
    switch self {
    case .temperature:
      return "温度"
    case .apparentTemperature:
      return "体感温度"
    case .uvIndex:
      return "紫外线"
    case .humidity:
      return "湿度"
    }
  }

  public var keyboardDisplayPrefix: String {
    switch self {
    case .temperature:
      return ""
    case .apparentTemperature:
      return "体感 "
    case .uvIndex:
      return "UV "
    case .humidity:
      return "湿度 "
    }
  }
}

public enum KeyboardWeatherIndicatorLocationMode: String, Codable, CaseIterable, Hashable {
  case currentLocation
  case fixedCity

  public var title: String {
    switch self {
    case .currentLocation:
      return "当前位置"
    case .fixedCity:
      return "固定城市"
    }
  }
}

public struct KeyboardWeatherIndicatorCache: Codable, Hashable {
  public static let validDuration: TimeInterval = 3 * 60 * 60

  public var sourceLocationMode: KeyboardWeatherIndicatorLocationMode
  public var sourceLocationQuery: String?
  public var resolvedLocationName: String
  public var latitude: Double
  public var longitude: Double
  public var symbolName: String
  public var temperatureCelsius: Double
  public var apparentTemperatureCelsius: Double
  public var uvIndexValue: Int
  public var humidityFraction: Double
  public var updatedAt: Date
  public var attributionServiceName: String?
  public var attributionLegalPageURLString: String?
  public var attributionLegalText: String?

  public init(
    sourceLocationMode: KeyboardWeatherIndicatorLocationMode,
    sourceLocationQuery: String? = nil,
    resolvedLocationName: String,
    latitude: Double,
    longitude: Double,
    symbolName: String,
    temperatureCelsius: Double,
    apparentTemperatureCelsius: Double,
    uvIndexValue: Int,
    humidityFraction: Double,
    updatedAt: Date,
    attributionServiceName: String? = nil,
    attributionLegalPageURLString: String? = nil,
    attributionLegalText: String? = nil)
  {
    self.sourceLocationMode = sourceLocationMode
    self.sourceLocationQuery = sourceLocationQuery
    self.resolvedLocationName = resolvedLocationName
    self.latitude = latitude
    self.longitude = longitude
    self.symbolName = symbolName
    self.temperatureCelsius = temperatureCelsius
    self.apparentTemperatureCelsius = apparentTemperatureCelsius
    self.uvIndexValue = uvIndexValue
    self.humidityFraction = humidityFraction
    self.updatedAt = updatedAt
    self.attributionServiceName = attributionServiceName
    self.attributionLegalPageURLString = attributionLegalPageURLString
    self.attributionLegalText = attributionLegalText
  }

  public var isFresh: Bool {
    Date().timeIntervalSince(updatedAt) <= Self.validDuration
  }

  public func matchesConfiguration(
    locationMode: KeyboardWeatherIndicatorLocationMode,
    fixedLocationName: String?,
    fixedLatitude: Double? = nil,
    fixedLongitude: Double? = nil) -> Bool
  {
    guard sourceLocationMode == locationMode else { return false }
    switch locationMode {
    case .currentLocation:
      return true
    case .fixedCity:
      if let fixedLatitude, let fixedLongitude {
        guard Self.matchesCoordinate(lhs: latitude, rhs: fixedLatitude),
              Self.matchesCoordinate(lhs: longitude, rhs: fixedLongitude)
        else {
          return false
        }
      }
      let configName = Self.normalizedLocationQuery(fixedLocationName)
      let cachedName = Self.normalizedLocationQuery(sourceLocationQuery)
      return !configName.isEmpty && configName == cachedName
    }
  }

  public func displayText(for metric: KeyboardWeatherIndicatorMetric) -> String {
    switch metric {
    case .temperature:
      return "\(Int(temperatureCelsius.rounded()))°"
    case .apparentTemperature:
      return "体感 \(Int(apparentTemperatureCelsius.rounded()))°"
    case .uvIndex:
      return "UV \(uvIndexValue)"
    case .humidity:
      return "湿度 \(Int((humidityFraction * 100).rounded()))%"
    }
  }

  public func isDisplayable(
    enabled: Bool,
    locationMode: KeyboardWeatherIndicatorLocationMode,
    fixedLocationName: String?,
    fixedLatitude: Double? = nil,
    fixedLongitude: Double? = nil) -> Bool
  {
    guard enabled else { return false }
    guard isFresh else { return false }
    return matchesConfiguration(
      locationMode: locationMode,
      fixedLocationName: fixedLocationName,
      fixedLatitude: fixedLatitude,
      fixedLongitude: fixedLongitude
    )
  }

  public static func normalizedLocationQuery(_ value: String?) -> String {
    value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .lowercased() ?? ""
  }

  private static func matchesCoordinate(lhs: Double, rhs: Double) -> Bool {
    abs(lhs - rhs) <= 0.0005
  }
}
