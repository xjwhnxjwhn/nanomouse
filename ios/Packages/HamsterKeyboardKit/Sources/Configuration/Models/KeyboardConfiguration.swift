//
//  KeyboardConfiguration.swift
//
//
//  Created by morse on 2023/6/30.
//

import Foundation

/// 键盘配置
public struct KeyboardConfiguration: Codable, Hashable {
  /// 使用键盘类型
  public var useKeyboardType: String?

  /// 进入键盘默认语言
  public var defaultLanguageMode: KeyboardDefaultLanguage?

  /// 关闭划动显示文本
  public var disableSwipeLabel: Bool?

  /// 上划显示在左侧
  public var upSwipeOnLeft: Bool?

  /// 划动上下布局 or 左右布局
  public var swipeLabelUpAndDownLayout: Bool?

  /// 上下显示划动文本不规则布局
  public var swipeLabelUpAndDownIrregularLayout: Bool?

  /// 显示按键气泡
  /// true: 显示 false: 不显示
  public var displayButtonBubbles: Bool?

  /// 启用按键声音
  /// true: 启用 false 停用
  public var enableKeySounds: Bool?

  /// 启用震动反馈
  /// true: 启用 false 停用
  public var enableHapticFeedback: Bool?

  /// 震动反馈强度
  /// 目前支持5档震动强度: 0到4， 0表示最弱 4表示最强
  public var hapticFeedbackIntensity: Int?

  /// 显示分号按键
  public var displaySemicolonButton: Bool?

  /// 显示分类符号按键
  public var displayClassifySymbolButton: Bool?

  /// 显示空格左边按键
  public var displaySpaceLeftButton: Bool?

  /// 空格左侧按键由RIME处理
  public var spaceLeftButtonProcessByRIME: Bool?

  /// 空格左边按键对应的键值
  public var keyValueOfSpaceLeftButton: String?

  /// 显示空格右边按键
  public var displaySpaceRightButton: Bool?

  /// 空格右侧按键由RIME处理
  public var spaceRightButtonProcessByRIME: Bool?

  /// 空格右边按键对应的键值
  public var keyValueOfSpaceRightButton: String?

  /// 显示中英切换按键
  public var displayChineseEnglishSwitchButton: Bool?

  /// 中英切换按键在空格左侧
  /// true 位于左侧 false 位于右侧
  public var chineseEnglishSwitchButtonIsOnLeftOfSpaceButton: Bool?

  /// 启用九宫格数字键盘
  public var enableNineGridOfNumericKeyboard: Bool?

  /// 数字九宫格键盘: 数字键是否由 RIME 处理
  public var numberKeyProcessByRimeOnNineGridOfNumericKeyboard: Bool?

  /// 数字九宫格键盘：左侧符号列表符号是否由 RIME 处理
  public var leftSymbolProcessByRimeOnNineGridOfNumericKeyboard: Bool?

  /// 数字九宫格键盘：右侧符号否由 RIME 处理
  public var rightSymbolProcessByRimeOnNineGridOfNumericKeyboard: Bool?

  /// 九宫格数字键盘: 符号列表
  public var symbolsOfGridOfNumericKeyboard: [String]?

  /// Shift状态锁定
  public var lockShiftState: Bool?

  /// 启用嵌入式输入模式
  public var enableEmbeddedInputMode: Bool?

  /// 单手键盘宽度
  public var widthOfOneHandedKeyboard: Int?

  /// 符号上屏后光标回退
  public var symbolsOfCursorBack: [String]?

  /// 符号上屏后，键盘返回主键盘
  public var symbolsOfReturnToMainKeyboard: [String]?

  /// 中文九宫格符号列
  public var symbolsOfChineseNineGridKeyboard: [String]?

  /// 成对上屏的符号
  public var pairsOfSymbols: [String]?

  /// 启用符号键盘
  public var enableSymbolKeyboard: Bool?

  /// 符号键盘锁定
  /// 锁定后键盘不会自动返回主键盘
  public var lockForSymbolKeyboard: Bool?

  /// 启用颜色方案
  public var enableColorSchema: Bool?

  /// 浅色模式下颜色方案
  public var useColorSchemaForLight: String?

  /// 暗色模式下颜色方案
  public var useColorSchemaForDark: String?

  /// 键盘颜色方案列表
  public var colorSchemas: [KeyboardColorSchema]?

  // 是否启用空格加载文本
  public var enableLoadingTextForSpaceButton: Bool?

  // 空格按钮加载文本
  public var loadingTextForSpaceButton: String?

  // 空格按钮长显文本
  public var labelTextForSpaceButton: String?

  // 空格按钮长显为当前输入方案
  // 当开启此选项后，labelForSpaceButton 设置的值无效
  public var showCurrentInputSchemaNameForSpaceButton: Bool?

  // 空格按钮加载文字显示当前输入方案
  // 当开启此选项后， loadingTextForSpaceButton 设置的值无效
  public var showCurrentInputSchemaNameOnLoadingTextForSpaceButton: Bool?

  // 中文26键显示大写字符
  public var showUppercasedCharacterOnChineseKeyboard: Bool?

  // 按键下方边框
  public var enableButtonUnderBorder: Bool?

  /// 启用系统文本替换
  /// 开启后，键盘会读取 iOS 系统设置中的「文本替换」并自动应用
  public var enableSystemTextReplacement: Bool?

  /// 多语言快速混输
  public var enableMultiLanguageQuickMix: Bool?

  /// 中文键盘数字候选模式
  public var enableNumericCandidateModeOnChineseKeyboard: Bool?

  /// 日语 AzooKey 键盘数字候选模式
  public var enableNumericCandidateModeOnJapaneseAzooKey: Bool?

  public init(
    useKeyboardType: String? = "chinese",
    defaultLanguageMode: KeyboardDefaultLanguage? = .followLast,
    disableSwipeLabel: Bool? = true,
    upSwipeOnLeft: Bool? = false,
    swipeLabelUpAndDownLayout: Bool? = true,
    swipeLabelUpAndDownIrregularLayout: Bool? = false,
    displayButtonBubbles: Bool? = true,
    enableKeySounds: Bool? = false,
    enableHapticFeedback: Bool? = false,
    hapticFeedbackIntensity: Int? = 3,
    displaySemicolonButton: Bool? = false,
    displayClassifySymbolButton: Bool? = false,
    displaySpaceLeftButton: Bool? = false,
    spaceLeftButtonProcessByRIME: Bool? = true,
    keyValueOfSpaceLeftButton: String? = ",",
    displaySpaceRightButton: Bool? = false,
    spaceRightButtonProcessByRIME: Bool? = true,
    keyValueOfSpaceRightButton: String? = ".",
    displayChineseEnglishSwitchButton: Bool? = true,
    chineseEnglishSwitchButtonIsOnLeftOfSpaceButton: Bool? = false,
    enableNineGridOfNumericKeyboard: Bool? = false,
    numberKeyProcessByRimeOnNineGridOfNumericKeyboard: Bool? = false,
    leftSymbolProcessByRimeOnNineGridOfNumericKeyboard: Bool? = false,
    rightSymbolProcessByRimeOnNineGridOfNumericKeyboard: Bool? = false,
    symbolsOfGridOfNumericKeyboard: [String]? = ["+", "-", "*", "/"],
    lockShiftState: Bool? = false,
    enableEmbeddedInputMode: Bool? = true,
    widthOfOneHandedKeyboard: Int? = 80,
    symbolsOfCursorBack: [String]? = ["\"\"", "“”", "[]"],
    symbolsOfReturnToMainKeyboard: [String]? = ["，", "。", "！"],
    symbolsOfChineseNineGridKeyboard: [String]? = ["，", "。", "？", "！", "…", "~", "'", "、"],
    pairsOfSymbols: [String]? = ["[]", "()", "“”"],
    enableSymbolKeyboard: Bool? = true,
    lockForSymbolKeyboard: Bool? = false,
    enableColorSchema: Bool? = false,
    useColorSchemaForLight: String? = "",
    useColorSchemaForDark: String? = "",
    colorSchemas: [KeyboardColorSchema]? = [
      KeyboardColorSchema(
        schemaName: "solarized_dark",
        name: "曬經・月／Solarized Dark",
        author: "雪齋 <lyc20041@gmail.com>/Morse <nanomouse.official@gmail.com>",
        backColor: "0xF0352A0A",
        buttonBackColor: "0xF0352A0A",
        buttonPressedBackColor: "0x403516",
        buttonFrontColor: "0x7389FF",
        buttonPressedFrontColor: "0x7389FF",
        buttonSwipeFrontColor: "0x7389FF",
        cornerRadius: 5,
        borderColor: "0x2A1F00",
        textColor: "0x756E5D",
        hilitedCandidateTextColor: "0x989F52",
        hilitedCandidateBackColor: "0x403516",
        hilitedCommentTextColor: "0x289989",
        hilitedCandidateLabelColor: "0xCC8947",
        candidateTextColor: "0x7389FF",
        commentTextColor: "0xC38AFF",
        labelColor: "0x478DF4"
      ),
      KeyboardColorSchema(
        schemaName: "solarized_light",
        name: "曬經・日／Solarized Light",
        author: "雪齋 <lyc20041@gmail.com>/Morse <nanomouse.official@gmail.com>",
        backColor: "0xF0E5F6FB",
        buttonBackColor: "0xF0E5F6FB",
        buttonPressedBackColor: "0xD7E8ED",
        buttonFrontColor: "0x595E00",
        buttonPressedFrontColor: "0x595E00",
        buttonSwipeFrontColor: "0x595E00",
        cornerRadius: 5,
        borderColor: "0xEDFFFF",
        textColor: "0xA1A095",
        hilitedCandidateTextColor: "0x3942CB",
        hilitedCandidateBackColor: "0xD7E8ED",
        hilitedCommentTextColor: "0x8144C2",
        hilitedCandidateLabelColor: "0x2566C6",
        candidateTextColor: "0x595E00",
        commentTextColor: "0x005947",
        labelColor: "0xA36407"
      )
    ],
    enableLoadingTextForSpaceButton: Bool? = true,
    loadingTextForSpaceButton: String? = "",
    labelTextForSpaceButton: String? = "",
    showCurrentInputSchemaNameForSpaceButton: Bool? = false,
    showCurrentInputSchemaNameOnLoadingTextForSpaceButton: Bool? = true,
    showUppercasedCharacterOnChineseKeyboard: Bool? = false,
    enableButtonUnderBorder: Bool? = true,
    enableSystemTextReplacement: Bool? = true,
    enableMultiLanguageQuickMix: Bool? = false,
    enableNumericCandidateModeOnChineseKeyboard: Bool? = false,
    enableNumericCandidateModeOnJapaneseAzooKey: Bool? = true) {
    self.useKeyboardType = useKeyboardType
    self.defaultLanguageMode = defaultLanguageMode
    self.disableSwipeLabel = disableSwipeLabel
    self.upSwipeOnLeft = upSwipeOnLeft
    self.swipeLabelUpAndDownLayout = swipeLabelUpAndDownLayout
    self.swipeLabelUpAndDownIrregularLayout = swipeLabelUpAndDownIrregularLayout
    self.displayButtonBubbles = displayButtonBubbles
    self.enableKeySounds = enableKeySounds
    self.enableHapticFeedback = enableHapticFeedback
    self.hapticFeedbackIntensity = hapticFeedbackIntensity
    self.displaySemicolonButton = displaySemicolonButton
    self.displayClassifySymbolButton = displayClassifySymbolButton
    self.displaySpaceLeftButton = displaySpaceLeftButton
    self.spaceLeftButtonProcessByRIME = spaceLeftButtonProcessByRIME
    self.keyValueOfSpaceLeftButton = keyValueOfSpaceLeftButton
    self.displaySpaceRightButton = displaySpaceRightButton
    self.spaceRightButtonProcessByRIME = spaceRightButtonProcessByRIME
    self.keyValueOfSpaceRightButton = keyValueOfSpaceRightButton
    self.displayChineseEnglishSwitchButton = displayChineseEnglishSwitchButton
    self.chineseEnglishSwitchButtonIsOnLeftOfSpaceButton = chineseEnglishSwitchButtonIsOnLeftOfSpaceButton
    self.enableNineGridOfNumericKeyboard = enableNineGridOfNumericKeyboard
    self.numberKeyProcessByRimeOnNineGridOfNumericKeyboard = numberKeyProcessByRimeOnNineGridOfNumericKeyboard
    self.leftSymbolProcessByRimeOnNineGridOfNumericKeyboard = leftSymbolProcessByRimeOnNineGridOfNumericKeyboard
    self.rightSymbolProcessByRimeOnNineGridOfNumericKeyboard = rightSymbolProcessByRimeOnNineGridOfNumericKeyboard
    self.symbolsOfGridOfNumericKeyboard = symbolsOfGridOfNumericKeyboard
    self.lockShiftState = lockShiftState
    self.enableEmbeddedInputMode = enableEmbeddedInputMode
    self.widthOfOneHandedKeyboard = widthOfOneHandedKeyboard
    self.symbolsOfCursorBack = symbolsOfCursorBack
    self.symbolsOfReturnToMainKeyboard = symbolsOfReturnToMainKeyboard
    self.symbolsOfChineseNineGridKeyboard = symbolsOfChineseNineGridKeyboard
    self.pairsOfSymbols = pairsOfSymbols
    self.enableSymbolKeyboard = enableSymbolKeyboard
    self.lockForSymbolKeyboard = lockForSymbolKeyboard
    self.enableColorSchema = enableColorSchema
    self.useColorSchemaForLight = useColorSchemaForLight
    self.useColorSchemaForDark = useColorSchemaForDark
    self.colorSchemas = colorSchemas
    self.enableLoadingTextForSpaceButton = enableLoadingTextForSpaceButton
    self.loadingTextForSpaceButton = loadingTextForSpaceButton
    self.labelTextForSpaceButton = labelTextForSpaceButton
    self.showCurrentInputSchemaNameForSpaceButton = showCurrentInputSchemaNameForSpaceButton
    self.showCurrentInputSchemaNameOnLoadingTextForSpaceButton = showCurrentInputSchemaNameOnLoadingTextForSpaceButton
    self.showUppercasedCharacterOnChineseKeyboard = showUppercasedCharacterOnChineseKeyboard
    self.enableButtonUnderBorder = enableButtonUnderBorder
    self.enableSystemTextReplacement = enableSystemTextReplacement
    self.enableMultiLanguageQuickMix = enableMultiLanguageQuickMix
    self.enableNumericCandidateModeOnChineseKeyboard = enableNumericCandidateModeOnChineseKeyboard
    self.enableNumericCandidateModeOnJapaneseAzooKey = enableNumericCandidateModeOnJapaneseAzooKey
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.useKeyboardType = try container.decodeIfPresent(String.self, forKey: .useKeyboardType)
    self.defaultLanguageMode = try container.decodeIfPresent(KeyboardDefaultLanguage.self, forKey: .defaultLanguageMode)
    self.disableSwipeLabel = try container.decodeIfPresent(Bool.self, forKey: .disableSwipeLabel)
    self.upSwipeOnLeft = try container.decodeIfPresent(Bool.self, forKey: .upSwipeOnLeft)
    self.swipeLabelUpAndDownLayout = try container.decodeIfPresent(Bool.self, forKey: .swipeLabelUpAndDownLayout)
    self.swipeLabelUpAndDownIrregularLayout = try container.decodeIfPresent(Bool.self, forKey: .swipeLabelUpAndDownIrregularLayout)
    self.displayButtonBubbles = try container.decodeIfPresent(Bool.self, forKey: .displayButtonBubbles)
    self.enableKeySounds = try container.decodeIfPresent(Bool.self, forKey: .enableKeySounds)
    self.enableHapticFeedback = try container.decodeIfPresent(Bool.self, forKey: .enableHapticFeedback)
    self.hapticFeedbackIntensity = try container.decodeIfPresent(Int.self, forKey: .hapticFeedbackIntensity)
    self.displaySemicolonButton = try container.decodeIfPresent(Bool.self, forKey: .displaySemicolonButton)
    self.displayClassifySymbolButton = try container.decodeIfPresent(Bool.self, forKey: .displayClassifySymbolButton)
    self.displaySpaceLeftButton = try container.decodeIfPresent(Bool.self, forKey: .displaySpaceLeftButton)
    self.spaceLeftButtonProcessByRIME = try container.decodeIfPresent(Bool.self, forKey: .spaceLeftButtonProcessByRIME)
    self.keyValueOfSpaceLeftButton = try container.decodeIfPresent(String.self, forKey: .keyValueOfSpaceLeftButton)
    self.displaySpaceRightButton = try container.decodeIfPresent(Bool.self, forKey: .displaySpaceRightButton)
    self.spaceRightButtonProcessByRIME = try container.decodeIfPresent(Bool.self, forKey: .spaceRightButtonProcessByRIME)
    self.keyValueOfSpaceRightButton = try container.decodeIfPresent(String.self, forKey: .keyValueOfSpaceRightButton)
    self.displayChineseEnglishSwitchButton = try container.decodeIfPresent(Bool.self, forKey: .displayChineseEnglishSwitchButton)
    self.chineseEnglishSwitchButtonIsOnLeftOfSpaceButton = try container.decodeIfPresent(Bool.self, forKey: .chineseEnglishSwitchButtonIsOnLeftOfSpaceButton)
    self.enableNineGridOfNumericKeyboard = try container.decodeIfPresent(Bool.self, forKey: .enableNineGridOfNumericKeyboard)
    self.numberKeyProcessByRimeOnNineGridOfNumericKeyboard = try container.decodeIfPresent(Bool.self, forKey: .numberKeyProcessByRimeOnNineGridOfNumericKeyboard)
    self.leftSymbolProcessByRimeOnNineGridOfNumericKeyboard = try container.decodeIfPresent(Bool.self, forKey: .leftSymbolProcessByRimeOnNineGridOfNumericKeyboard)
    self.rightSymbolProcessByRimeOnNineGridOfNumericKeyboard = try container.decodeIfPresent(Bool.self, forKey: .rightSymbolProcessByRimeOnNineGridOfNumericKeyboard)
    self.symbolsOfGridOfNumericKeyboard = try container.decodeIfPresent([String].self, forKey: .symbolsOfGridOfNumericKeyboard)
    self.lockShiftState = try container.decodeIfPresent(Bool.self, forKey: .lockShiftState)
    self.enableEmbeddedInputMode = try container.decodeIfPresent(Bool.self, forKey: .enableEmbeddedInputMode)
    self.widthOfOneHandedKeyboard = try container.decodeIfPresent(Int.self, forKey: .widthOfOneHandedKeyboard)
    self.symbolsOfCursorBack = try container.decodeIfPresent([String].self, forKey: .symbolsOfCursorBack)
    self.symbolsOfReturnToMainKeyboard = try container.decodeIfPresent([String].self, forKey: .symbolsOfReturnToMainKeyboard)
    self.symbolsOfChineseNineGridKeyboard = try container.decodeIfPresent([String].self, forKey: .symbolsOfChineseNineGridKeyboard)
    self.pairsOfSymbols = try container.decodeIfPresent([String].self, forKey: .pairsOfSymbols)
    self.enableSymbolKeyboard = try container.decodeIfPresent(Bool.self, forKey: .enableSymbolKeyboard)
    self.lockForSymbolKeyboard = try container.decodeIfPresent(Bool.self, forKey: .lockForSymbolKeyboard)
    self.enableColorSchema = try container.decodeIfPresent(Bool.self, forKey: .enableColorSchema)
    self.useColorSchemaForLight = try container.decodeIfPresent(String.self, forKey: .useColorSchemaForLight)
    self.useColorSchemaForDark = try container.decodeIfPresent(String.self, forKey: .useColorSchemaForDark)
    self.colorSchemas = try container.decodeIfPresent([KeyboardColorSchema].self, forKey: .colorSchemas)
    self.enableLoadingTextForSpaceButton = try container.decodeIfPresent(Bool.self, forKey: .enableLoadingTextForSpaceButton)
    self.loadingTextForSpaceButton = try container.decodeIfPresent(String.self, forKey: .loadingTextForSpaceButton)
    self.labelTextForSpaceButton = try container.decodeIfPresent(String.self, forKey: .labelTextForSpaceButton)
    self.showCurrentInputSchemaNameForSpaceButton = try container.decodeIfPresent(Bool.self, forKey: .showCurrentInputSchemaNameForSpaceButton)
    self.showCurrentInputSchemaNameOnLoadingTextForSpaceButton = try container.decodeIfPresent(Bool.self, forKey: .showCurrentInputSchemaNameOnLoadingTextForSpaceButton)
    self.showUppercasedCharacterOnChineseKeyboard = try container.decodeIfPresent(Bool.self, forKey: .showUppercasedCharacterOnChineseKeyboard)
    self.enableButtonUnderBorder = try container.decodeIfPresent(Bool.self, forKey: .enableButtonUnderBorder)
    self.enableSystemTextReplacement = try container.decodeIfPresent(Bool.self, forKey: .enableSystemTextReplacement)
    self.enableMultiLanguageQuickMix = try container.decodeIfPresent(Bool.self, forKey: .enableMultiLanguageQuickMix)
    self.enableNumericCandidateModeOnChineseKeyboard = try container.decodeIfPresent(
      Bool.self, forKey: .enableNumericCandidateModeOnChineseKeyboard
    )
    self.enableNumericCandidateModeOnJapaneseAzooKey = try container.decodeIfPresent(
      Bool.self, forKey: .enableNumericCandidateModeOnJapaneseAzooKey
    )
  }

  enum CodingKeys: CodingKey {
    case useKeyboardType
    case defaultLanguageMode
    case disableSwipeLabel
    case upSwipeOnLeft
    case swipeLabelUpAndDownLayout
    case swipeLabelUpAndDownIrregularLayout
    case displayButtonBubbles
    case enableKeySounds
    case enableHapticFeedback
    case hapticFeedbackIntensity
    case displaySemicolonButton
    case displayClassifySymbolButton
    case displaySpaceLeftButton
    case spaceLeftButtonProcessByRIME
    case keyValueOfSpaceLeftButton
    case displaySpaceRightButton
    case spaceRightButtonProcessByRIME
    case keyValueOfSpaceRightButton
    case displayChineseEnglishSwitchButton
    case chineseEnglishSwitchButtonIsOnLeftOfSpaceButton
    case enableNineGridOfNumericKeyboard
    case numberKeyProcessByRimeOnNineGridOfNumericKeyboard
    case leftSymbolProcessByRimeOnNineGridOfNumericKeyboard
    case rightSymbolProcessByRimeOnNineGridOfNumericKeyboard
    case symbolsOfGridOfNumericKeyboard
    case lockShiftState
    case enableEmbeddedInputMode
    case widthOfOneHandedKeyboard
    case symbolsOfCursorBack
    case symbolsOfReturnToMainKeyboard
    case symbolsOfChineseNineGridKeyboard
    case pairsOfSymbols
    case enableSymbolKeyboard
    case lockForSymbolKeyboard
    case enableColorSchema
    case useColorSchemaForLight
    case useColorSchemaForDark
    case colorSchemas
    case enableLoadingTextForSpaceButton
    case loadingTextForSpaceButton
    case labelTextForSpaceButton
    case showCurrentInputSchemaNameForSpaceButton
    case showCurrentInputSchemaNameOnLoadingTextForSpaceButton
    case showUppercasedCharacterOnChineseKeyboard
    case enableButtonUnderBorder
    case enableSystemTextReplacement
    case enableMultiLanguageQuickMix
    case enableNumericCandidateModeOnChineseKeyboard
    case enableNumericCandidateModeOnJapaneseAzooKey
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(self.useKeyboardType, forKey: .useKeyboardType)
    try container.encodeIfPresent(self.defaultLanguageMode, forKey: .defaultLanguageMode)
    try container.encodeIfPresent(self.disableSwipeLabel, forKey: .disableSwipeLabel)
    try container.encodeIfPresent(self.upSwipeOnLeft, forKey: .upSwipeOnLeft)
    try container.encodeIfPresent(self.swipeLabelUpAndDownLayout, forKey: .swipeLabelUpAndDownLayout)
    try container.encodeIfPresent(self.swipeLabelUpAndDownIrregularLayout, forKey: .swipeLabelUpAndDownIrregularLayout)
    try container.encodeIfPresent(self.displayButtonBubbles, forKey: .displayButtonBubbles)
    try container.encodeIfPresent(self.enableKeySounds, forKey: .enableKeySounds)
    try container.encodeIfPresent(self.enableHapticFeedback, forKey: .enableHapticFeedback)
    try container.encodeIfPresent(self.hapticFeedbackIntensity, forKey: .hapticFeedbackIntensity)
    try container.encodeIfPresent(self.displaySemicolonButton, forKey: .displaySemicolonButton)
    try container.encodeIfPresent(self.displayClassifySymbolButton, forKey: .displayClassifySymbolButton)
    try container.encodeIfPresent(self.displaySpaceLeftButton, forKey: .displaySpaceLeftButton)
    try container.encodeIfPresent(self.spaceLeftButtonProcessByRIME, forKey: .spaceLeftButtonProcessByRIME)
    try container.encodeIfPresent(self.keyValueOfSpaceLeftButton, forKey: .keyValueOfSpaceLeftButton)
    try container.encodeIfPresent(self.displaySpaceRightButton, forKey: .displaySpaceRightButton)
    try container.encodeIfPresent(self.spaceRightButtonProcessByRIME, forKey: .spaceRightButtonProcessByRIME)
    try container.encodeIfPresent(self.keyValueOfSpaceRightButton, forKey: .keyValueOfSpaceRightButton)
    try container.encodeIfPresent(self.displayChineseEnglishSwitchButton, forKey: .displayChineseEnglishSwitchButton)
    try container.encodeIfPresent(self.chineseEnglishSwitchButtonIsOnLeftOfSpaceButton, forKey: .chineseEnglishSwitchButtonIsOnLeftOfSpaceButton)
    try container.encodeIfPresent(self.enableNineGridOfNumericKeyboard, forKey: .enableNineGridOfNumericKeyboard)
    try container.encodeIfPresent(self.numberKeyProcessByRimeOnNineGridOfNumericKeyboard, forKey: .numberKeyProcessByRimeOnNineGridOfNumericKeyboard)
    try container.encodeIfPresent(self.leftSymbolProcessByRimeOnNineGridOfNumericKeyboard, forKey: .leftSymbolProcessByRimeOnNineGridOfNumericKeyboard)
    try container.encodeIfPresent(self.rightSymbolProcessByRimeOnNineGridOfNumericKeyboard, forKey: .rightSymbolProcessByRimeOnNineGridOfNumericKeyboard)
    try container.encodeIfPresent(self.symbolsOfGridOfNumericKeyboard, forKey: .symbolsOfGridOfNumericKeyboard)
    try container.encodeIfPresent(self.lockShiftState, forKey: .lockShiftState)
    try container.encodeIfPresent(self.enableEmbeddedInputMode, forKey: .enableEmbeddedInputMode)
    try container.encodeIfPresent(self.widthOfOneHandedKeyboard, forKey: .widthOfOneHandedKeyboard)
    try container.encodeIfPresent(self.symbolsOfCursorBack, forKey: .symbolsOfCursorBack)
    try container.encodeIfPresent(self.symbolsOfReturnToMainKeyboard, forKey: .symbolsOfReturnToMainKeyboard)
    try container.encodeIfPresent(self.symbolsOfChineseNineGridKeyboard, forKey: .symbolsOfChineseNineGridKeyboard)
    try container.encodeIfPresent(self.pairsOfSymbols, forKey: .pairsOfSymbols)
    try container.encodeIfPresent(self.enableSymbolKeyboard, forKey: .enableSymbolKeyboard)
    try container.encodeIfPresent(self.lockForSymbolKeyboard, forKey: .lockForSymbolKeyboard)
    try container.encodeIfPresent(self.enableColorSchema, forKey: .enableColorSchema)
    try container.encodeIfPresent(self.useColorSchemaForLight, forKey: .useColorSchemaForLight)
    try container.encodeIfPresent(self.useColorSchemaForDark, forKey: .useColorSchemaForDark)
    try container.encodeIfPresent(self.colorSchemas, forKey: .colorSchemas)
    try container.encodeIfPresent(self.enableLoadingTextForSpaceButton, forKey: .enableLoadingTextForSpaceButton)
    try container.encodeIfPresent(self.loadingTextForSpaceButton, forKey: .loadingTextForSpaceButton)
    try container.encodeIfPresent(self.labelTextForSpaceButton, forKey: .labelTextForSpaceButton)
    try container.encodeIfPresent(self.showCurrentInputSchemaNameForSpaceButton, forKey: .showCurrentInputSchemaNameForSpaceButton)
    try container.encodeIfPresent(self.showCurrentInputSchemaNameOnLoadingTextForSpaceButton, forKey: .showCurrentInputSchemaNameOnLoadingTextForSpaceButton)
    try container.encodeIfPresent(self.showUppercasedCharacterOnChineseKeyboard, forKey: .showUppercasedCharacterOnChineseKeyboard)
    try container.encodeIfPresent(self.enableButtonUnderBorder, forKey: .enableButtonUnderBorder)
    try container.encodeIfPresent(self.enableSystemTextReplacement, forKey: .enableSystemTextReplacement)
    try container.encodeIfPresent(self.enableMultiLanguageQuickMix, forKey: .enableMultiLanguageQuickMix)
    try container.encodeIfPresent(
      self.enableNumericCandidateModeOnChineseKeyboard, forKey: .enableNumericCandidateModeOnChineseKeyboard
    )
    try container.encodeIfPresent(
      self.enableNumericCandidateModeOnJapaneseAzooKey, forKey: .enableNumericCandidateModeOnJapaneseAzooKey
    )
  }
}

/// 键盘默认语言模式
public enum KeyboardDefaultLanguage: String, Codable, CaseIterable {
  /// 跟随上次使用的语言
  case followLast
  /// 中文
  case chinese
  /// 日语
  case japanese
  /// 英文
  case english
}
