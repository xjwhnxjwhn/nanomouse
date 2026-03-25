//
//  KeyboardToolbarConfiguration.swift
//
//
//  Created by morse on 2023/6/30.
//

import Foundation
import HamsterKit

/// 键盘工具栏偏好
/// 工具栏包含候选栏，如果关闭工具栏，则候选文字不会显示
public struct KeyboardToolbarConfiguration: Codable, Hashable {
  /// 工具栏
  public var enableToolbar: Bool?

  /// 工具栏高度
  public var heightOfToolbar: Int?

  /// 显示应用图标按钮
  public var displayAppIconButton: Bool?

  /// 显示键盘收起键
  public var displayKeyboardDismissButton: Bool?

  /// 编码区高度
  /// 编码区：指待上屏区域
  public var heightOfCodingArea: Int?

  /// 编码区字体大小
  public var codingAreaFontSize: Int?

  /// 候选字索引大小
  public var candidateLabelFontSize: Int?

  /// 候选字字体大小
  /// 指候选列表中的字体大小
  public var candidateWordFontSize: Int?

  /// 候选备注字体大小
  public var candidateCommentFontSize: Int?

  /// 显示候选文字索引
  public var displayIndexOfCandidateWord: Bool?

  /// 显示候选文字 Comment 信息
  public var displayCommentOfCandidateWord: Bool?

  /// 划动分页开关，默认为 true，
  /// 关闭后为手动分页模式，即通过发送上一页/下一页按键，使 rime 翻页
  public var swipePaging: Bool?

  /// 候选栏空闲时滚动显示用户引导
  public var enableUserGuideScrolling: Bool?

  /// 在工具栏中部显示天气指标
  public var enableWeatherIndicator: Bool?

  /// 天气指标类型
  public var weatherIndicatorMetric: KeyboardWeatherIndicatorMetric?

  /// 天气位置来源
  public var weatherIndicatorLocationMode: KeyboardWeatherIndicatorLocationMode?

  /// 固定城市名称
  public var weatherIndicatorFixedLocationName: String?

  /// 固定城市纬度
  public var weatherIndicatorFixedLatitude: Double?

  /// 固定城市经度
  public var weatherIndicatorFixedLongitude: Double?

  public init(
    enableToolbar: Bool? = true,
    heightOfToolbar: Int? = 60,
    displayAppIconButton: Bool? = true,
    displayKeyboardDismissButton: Bool? = true,
    heightOfCodingArea: Int? = 20,
    codingAreaFontSize: Int? = 20,
    candidateLabelFontSize: Int? = 12,
    candidateWordFontSize: Int? = 25,
    candidateCommentFontSize: Int? = 12,
    displayIndexOfCandidateWord: Bool? = false,
    displayCommentOfCandidateWord: Bool? = false,
    swipePaging: Bool? = true,
    enableUserGuideScrolling: Bool? = true,
    enableWeatherIndicator: Bool? = true,
    weatherIndicatorMetric: KeyboardWeatherIndicatorMetric? = .temperature,
    weatherIndicatorLocationMode: KeyboardWeatherIndicatorLocationMode? = .currentLocation,
    weatherIndicatorFixedLocationName: String? = nil,
    weatherIndicatorFixedLatitude: Double? = nil,
    weatherIndicatorFixedLongitude: Double? = nil)
  {
    self.enableToolbar = enableToolbar
    self.heightOfToolbar = heightOfToolbar
    self.displayAppIconButton = displayAppIconButton
    self.displayKeyboardDismissButton = displayKeyboardDismissButton
    self.heightOfCodingArea = heightOfCodingArea
    self.codingAreaFontSize = codingAreaFontSize
    self.candidateLabelFontSize = candidateLabelFontSize
    self.candidateWordFontSize = candidateWordFontSize
    self.candidateCommentFontSize = candidateCommentFontSize
    self.displayIndexOfCandidateWord = displayIndexOfCandidateWord
    self.displayCommentOfCandidateWord = displayCommentOfCandidateWord
    self.swipePaging = swipePaging
    self.enableUserGuideScrolling = enableUserGuideScrolling
    self.enableWeatherIndicator = enableWeatherIndicator
    self.weatherIndicatorMetric = weatherIndicatorMetric
    self.weatherIndicatorLocationMode = weatherIndicatorLocationMode
    self.weatherIndicatorFixedLocationName = weatherIndicatorFixedLocationName
    self.weatherIndicatorFixedLatitude = weatherIndicatorFixedLatitude
    self.weatherIndicatorFixedLongitude = weatherIndicatorFixedLongitude
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.enableToolbar = try container.decodeIfPresent(Bool.self, forKey: .enableToolbar)
    self.heightOfToolbar = try container.decodeIfPresent(Int.self, forKey: .heightOfToolbar)
    self.displayAppIconButton = try container.decodeIfPresent(Bool.self, forKey: .displayAppIconButton)
    self.displayKeyboardDismissButton = try container.decodeIfPresent(Bool.self, forKey: .displayKeyboardDismissButton)
    self.heightOfCodingArea = try container.decodeIfPresent(Int.self, forKey: .heightOfCodingArea)
    self.candidateLabelFontSize = try container.decodeIfPresent(Int.self, forKey: .candidateLabelFontSize)
    self.codingAreaFontSize = try container.decodeIfPresent(Int.self, forKey: .codingAreaFontSize)
    self.candidateWordFontSize = try container.decodeIfPresent(Int.self, forKey: .candidateWordFontSize)
    self.candidateCommentFontSize = try container.decodeIfPresent(Int.self, forKey: .candidateCommentFontSize)
    self.displayIndexOfCandidateWord = try container.decodeIfPresent(Bool.self, forKey: .displayIndexOfCandidateWord)
    self.displayCommentOfCandidateWord = try container.decodeIfPresent(Bool.self, forKey: .displayCommentOfCandidateWord)
    self.swipePaging = try container.decodeIfPresent(Bool.self, forKey: .swipePaging)
    self.enableUserGuideScrolling = try container.decodeIfPresent(Bool.self, forKey: .enableUserGuideScrolling)
    self.enableWeatherIndicator = try container.decodeIfPresent(Bool.self, forKey: .enableWeatherIndicator)
    self.weatherIndicatorMetric = try container.decodeIfPresent(KeyboardWeatherIndicatorMetric.self, forKey: .weatherIndicatorMetric)
    self.weatherIndicatorLocationMode = try container.decodeIfPresent(KeyboardWeatherIndicatorLocationMode.self, forKey: .weatherIndicatorLocationMode)
    self.weatherIndicatorFixedLocationName = try container.decodeIfPresent(String.self, forKey: .weatherIndicatorFixedLocationName)
    self.weatherIndicatorFixedLatitude = try container.decodeIfPresent(Double.self, forKey: .weatherIndicatorFixedLatitude)
    self.weatherIndicatorFixedLongitude = try container.decodeIfPresent(Double.self, forKey: .weatherIndicatorFixedLongitude)
  }

  enum CodingKeys: CodingKey {
    case enableToolbar
    case heightOfToolbar
    case displayAppIconButton
    case displayKeyboardDismissButton
    case heightOfCodingArea
    case codingAreaFontSize
    case candidateLabelFontSize
    case candidateWordFontSize
    case candidateCommentFontSize
    case displayIndexOfCandidateWord
    case displayCommentOfCandidateWord
    case swipePaging
    case enableUserGuideScrolling
    case enableWeatherIndicator
    case weatherIndicatorMetric
    case weatherIndicatorLocationMode
    case weatherIndicatorFixedLocationName
    case weatherIndicatorFixedLatitude
    case weatherIndicatorFixedLongitude
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(self.enableToolbar, forKey: .enableToolbar)
    try container.encodeIfPresent(self.heightOfToolbar, forKey: .heightOfToolbar)
    try container.encodeIfPresent(self.displayAppIconButton, forKey: .displayAppIconButton)
    try container.encodeIfPresent(self.displayKeyboardDismissButton, forKey: .displayKeyboardDismissButton)
    try container.encodeIfPresent(self.heightOfCodingArea, forKey: .heightOfCodingArea)
    try container.encodeIfPresent(self.codingAreaFontSize, forKey: .codingAreaFontSize)
    try container.encodeIfPresent(self.candidateLabelFontSize, forKey: .candidateLabelFontSize)
    try container.encodeIfPresent(self.candidateWordFontSize, forKey: .candidateWordFontSize)
    try container.encodeIfPresent(self.candidateCommentFontSize, forKey: .candidateCommentFontSize)
    try container.encodeIfPresent(self.displayIndexOfCandidateWord, forKey: .displayIndexOfCandidateWord)
    try container.encodeIfPresent(self.displayCommentOfCandidateWord, forKey: .displayCommentOfCandidateWord)
    try container.encodeIfPresent(self.swipePaging, forKey: .swipePaging)
    try container.encodeIfPresent(self.enableUserGuideScrolling, forKey: .enableUserGuideScrolling)
    try container.encodeIfPresent(self.enableWeatherIndicator, forKey: .enableWeatherIndicator)
    try container.encodeIfPresent(self.weatherIndicatorMetric, forKey: .weatherIndicatorMetric)
    try container.encodeIfPresent(self.weatherIndicatorLocationMode, forKey: .weatherIndicatorLocationMode)
    try container.encodeIfPresent(self.weatherIndicatorFixedLocationName, forKey: .weatherIndicatorFixedLocationName)
    try container.encodeIfPresent(self.weatherIndicatorFixedLatitude, forKey: .weatherIndicatorFixedLatitude)
    try container.encodeIfPresent(self.weatherIndicatorFixedLongitude, forKey: .weatherIndicatorFixedLongitude)
  }
}
