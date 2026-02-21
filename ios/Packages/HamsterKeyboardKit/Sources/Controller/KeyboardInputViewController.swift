//
//  KeyboardViewController.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2018-03-13.
//  Copyright © 2018-2023 Daniel Saidi. All rights reserved.
//

import Combine
import HamsterKit
import KanaKanjiConverterModule
import OSLog
import UIKit
import UniformTypeIdentifiers

/**
 This class extends `UIInputViewController` with KeyboardKit
 specific functionality.

 该类扩展了 `UIInputViewController` 的 KeyboardKit 特定功能。

 When you use KeyboardKit, simply inherit this class instead
 of `UIInputViewController` to extend your controller with a
 set of additional lifecycle functions, properties, services
 etc. such as ``viewWillSetupKeyboard()``, ``keyboardContext``
 and ``keyboardActionHandler``.

 当您使用 KeyboardKit 时，只需继承该类而非 `UIInputViewController` 类，
 即可使用一组附加的生命周期函数、属性、服务等来扩展您的控制器，
 例如 `viewWillSetupKeyboard()``、`keyboardContext`` 和 `keyboardActionHandler``。

 You may notice that KeyboardKit's own views use initializer
 parameters instead of environment objects. It's intentional,
 to better communicate the dependencies of each view.

 您可能会注意到，KeyboardKit 自己的视图使用初始化器参数而非环境对象。这是有意为之，以便更好地传达每个视图的依赖关系。
 */
open class KeyboardInputViewController: UIInputViewController, KeyboardController {
  /// 语言切换循环抑制窗口（用于长按气泡选择时，避免 release 触发循环切换）
  var languageCycleSuppressionUntil: Date?
  private var keyboardRootView: KeyboardRootView?
  private var didApplyDefaultLanguage = false
  private var wasJapaneseActive = false
  private let mixedInputAppendDigitCandidateCount = 2
  private let mixedInputInjectedCandidateIndexBase = -1000
  private let mixedInputPrefixCandidateIndexBase = -2000
  private let mixedInputPinyinPrefixCandidateIndexBase = -3000
  private let mixedInputCombinedCandidateIndexBase = -4000
  private var mixedInputSelectedNumericPrefix: String?
  private var mixedInputSelectedPinyinPrefix: String?
  private var mixedInputPrefixCandidates: [(text: String, subtitle: String?)] = []
  private var mixedInputPrefixPinyinLetterCount: Int = 0
  private var mixedInputSuffixMode = false
  private var mixedInputResyncing = false
  private let voiceInputBridge: KeyboardVoiceInputBridge = .shared
  private let canvasInputBridge: KeyboardCanvasBridge = .shared
  private var lastVoiceInsertedCharacterCount = 0
  private var lastVoiceInsertedRequestId: String?
  private var hideVoiceUndoWorkItem: DispatchWorkItem?
  private var voiceResultPollingTimer: Timer?
  private var voiceResultPollingDeadline: Date?
  private let rimeStartupStateQueue = DispatchQueue(label: "com.XiangqingZHANG.nanomouse.rime.startup.state")
  private var rimeStartupTask: Task<Void, Never>?
  private var rimeStartupInProgress = false
  private var rimeStartupWatchdogTriggered = false
  private var rimeStartupSequenceID: Int = 0
  private var rimeStartupRetryCount = 0
  private let rimeStartupMaxRetryCount = 1
  private let rimeStartupRetryDelay: TimeInterval = 0.35
  private let rimeStartupTimeout: TimeInterval = 5.0
  private let rimeStartupWatchdogPollNanoseconds: UInt64 = 150_000_000

  private struct RimeStartupConfig {
    let maximumNumberOfCandidateWords: Int?
    let useContextPaging: Bool?
    let simplifiedModeKey: String
  }

  private enum RimeStartupWatchdogAction {
    case ignore
    case retry
    case degrade
  }

  private lazy var voiceUndoButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isHidden = true
    button.alpha = 0
    button.setTitle("已插入，撤销", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = UIColor.black.withAlphaComponent(0.78)
    button.layer.cornerRadius = 16
    button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
    button.addTarget(self, action: #selector(handleVoiceUndoTap), for: .touchUpInside)
    return button
  }()

  // MARK: - View Controller Lifecycle ViewController 生命周期

  override open func viewDidLoad() {
    super.viewDidLoad()
    // setupInitialWidth()
    // setupLocaleObservation()
    // setupNextKeyboardBehavior()
    // KeyboardUrlOpener.shared.controller = self
    setupCombineRIMEInput()
    setupRIMELanguageObservation()
    setupBackgroundCommitObservation()
    azooKeyEngine.onCandidatesUpdated = { [weak self] suggestions in
      guard let self else { return }
      guard self.isAzooKeyInputActive else { return }
      if self.azooKeyEngine.isComposing {
        self.updateAzooKeySuggestions(suggestions)
      } else {
        self.clearAzooKeyState()
      }
    }
  }

  override open func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    viewWillSetupKeyboard()
    viewWillSyncWithContext()
    setupRIME()
    syncKeyboardTypeForJapaneseIfNeeded(reason: "willAppear")
    if shouldPrewarmAzooKeyOnAppear {
      azooKeyEngine.prewarmIfNeeded()
    }

    // 加载系统文本替换
    let enableTextReplacement = keyboardContext.hamsterConfiguration?.keyboard?.enableSystemTextReplacement ?? false
    Logger.statistics.info("SystemTextReplacement: enableSystemTextReplacement = \(enableTextReplacement)")
    if enableTextReplacement {
      systemTextReplacementManager.loadLexicon(from: self)
    }

    // 这里不再修改 window 级手势识别器，避免在 Chrome 等宿主中触发系统级副作用。
  }

  override open func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startVoiceResultPollingIfNeeded()
    _ = viewWillHandleVoiceInputResult() || viewWillHandleCanvasInputResult()
  }

  override open func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    didApplyDefaultLanguage = false
    stopVoiceResultPolling()
    hideVoiceUndoButton(animated: false)
  }

  override open func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // Logger.statistics.debug("KeyboardInputViewController: viewDidLayoutSubviews()")
    keyboardContext.syncAfterLayout(with: self)
  }

  override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    // Logger.statistics.info("controller traitCollectionDidChange()")
    super.traitCollectionDidChange(previousTraitCollection)
    viewWillSyncWithContext()
  }

  /// 内存回收
  override open func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    resetAutocomplete()
    systemTextReplacementManager.clear()
    Task { @MainActor in
      rimeContext.reset()
      resetMixedInputFreezeState()
      rimeContext.textReplacementSuggestions = []
    }
  }

  // MARK: - Keyboard View Controller Lifecycle

  /**
   This function is called whenever the keyboard view must
   be created or updated.

   每当必须创建或更新键盘视图时，都会调用该函数。

   This will by default set up a ``KeyboardRootView`` as the
   main view, but you can override it to use a custom view.

   默认情况下，这将设置一个 "KeyboardRootView"（系统键盘）作为主视图，但你可以覆盖它以使用自定义视图。
   */

  open func viewWillSetupKeyboard() {
    rimeContext.prefersTwoTierCandidateBar = isUnifiedCompositionBufferEnabled
    if !isUnifiedCompositionBufferEnabled {
      rimeContext.compositionPrefix = ""
    }
    if let keyboardRootView = keyboardRootView {
      if keyboardRootView.superview == nil {
        keyboardRootView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardRootView)
        NSLayoutConstraint.activate([
          keyboardRootView.topAnchor.constraint(equalTo: view.topAnchor),
          keyboardRootView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
          keyboardRootView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
          keyboardRootView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
      }
      return
    }

    let keyboardRootView = KeyboardRootView(
      keyboardLayoutProvider: keyboardLayoutProvider,
      appearance: keyboardAppearance,
      actionHandler: keyboardActionHandler,
      keyboardContext: keyboardContext,
      calloutContext: calloutContext,
      rimeContext: rimeContext
    )
    self.keyboardRootView = keyboardRootView

    // 设置键盘的View
    keyboardRootView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(keyboardRootView)
    NSLayoutConstraint.activate([
      keyboardRootView.topAnchor.constraint(equalTo: view.topAnchor),
      keyboardRootView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      keyboardRootView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      keyboardRootView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  deinit {
    rimeStartupTaskSnapshot()?.cancel()
    view.subviews.forEach { $0.removeFromSuperview() }
  }

  /**
   This function is called whenever the controller must be
   synced with its ``keyboardContext``.

   每当 controller 必须与其 ``keyboardContext`` 同步时，就会调用此函数。

   This will by default sync with keyboard contexts if the
   ``isContextSyncEnabled`` is `true`. You can override it
   to customize syncing or sync with more contexts.

   如果 ``isContextSyncEnabled`` 为 `true`，默认情况下将与 KeyboardContext 同步。
   你可以覆盖它以自定义同步或与更多上下文同步。
   */
  open func viewWillSyncWithContext() {
    keyboardContext.sync(with: self)
    keyboardTextContext.sync(with: self)
  }

  // MARK: - Combine

  var cancellables = Set<AnyCancellable>()

  // MARK: - Properties

  /**
   The original text document proxy that was used to start
   the keyboard extension.

   用于启动键盘扩展程序的原生文本文档代理。

   This stays the same even if a ``textInputProxy`` is set,
   which makes ``textDocumentProxy`` return the custom one
   instead of the original one.

   即使设置了 ``textInputProxy`` 也不会改变，这将使 ``textDocumentProxy`` 返回自定义的文档，而不是原始文档。
   */
  open var mainTextDocumentProxy: UITextDocumentProxy {
    super.textDocumentProxy
  }

  /**
   The text document proxy to use, which can either be the
   original text input proxy or the ``textInputProxy``, if
   it is set to a custom value.

   要使用的 document proxy，可以是原生的文本输入代理，也可以是 ``textInputProxy``（如果设置为自定义值）。
   */
  override open var textDocumentProxy: UITextDocumentProxy {
//    textInputProxy ?? mainTextDocumentProxy
    mainTextDocumentProxy
  }

  /**
   A custom text input proxy to which text can be routed.

   自定义文本输入代理，可将文本传送到该代理。

   Setting the property makes ``textDocumentProxy`` return
   the custom proxy instead of the original one.

   设置该属性可使 ``textDocumentProxy`` 返回自定义代理，而不是原始代理。
   */
//  public var textInputProxy: TextInputProxy? {
//    didSet { viewWillSyncWithContext() }
//  }

  // MARK: - Observables

  /**
   The default, observable autocomplete context.

   默认的、可观察的自动完成上下文。

   This context is used as global state for the keyboard's
   autocomplete, e.g. the current suggestions.

   该上下文用作键盘自动完成的全局状态，例如当前建议。
   */
  public lazy var autocompleteContext = AutocompleteContext()

  /**
   The default, observable callout context.

   默认的可观察呼出上下文。

   This is used as global state for the callouts that show
   the currently typed character.

   这将作为显示当前键入字符的呼出的全局状态。
   */
  public lazy var calloutContext = KeyboardCalloutContext(
    action: ActionCalloutContext(
      actionHandler: keyboardActionHandler,
      actionProvider: calloutActionProvider
    ),
    input: InputCalloutContext(
      isEnabled: UIDevice.current.userInterfaceIdiom == .phone)
  )

  /**
   The default, observable dictation context.

   默认的, 可观测听写上下文。

   This is used as global dictation state and will be used
   to communicate between an app and its keyboard.

   这是全局听写状态，将用于应用程序与其键盘之间的通信。
   */
  // public lazy var dictationContext = DictationContext()

  /**
   The default, observable keyboard context.

   默认的, 可观察键盘上下文。

   This is used as global state for the keyboard's overall
   state and configuration like locale, device, screen etc.

   这是键盘整体状态和配置（如本地、设备、屏幕等）的全局状态。
   */
  public lazy var keyboardContext = KeyboardContext(controller: self)

  /**
   The default, observable feedback settings.

   默认的，可观察的反馈设置。

   This property is used as a global configuration for the
   keyboard's feedback, e.g. audio and haptic feedback.

   该属性用作键盘反馈（如音频和触觉反馈）的全局配置。
   */
  public lazy var keyboardFeedbackSettings: KeyboardFeedbackSettings = {
    let enableAudio = keyboardContext.hamsterConfiguration?.keyboard?.enableKeySounds ?? false
    let enableHaptic = keyboardContext.hamsterConfiguration?.keyboard?.enableHapticFeedback ?? false
    let hapticFeedbackIntensity = keyboardContext.hamsterConfiguration?.keyboard?.hapticFeedbackIntensity ?? 2
    let hapticFeedback = HapticIntensity(rawValue: hapticFeedbackIntensity)?.hapticFeedback() ?? .mediumImpact
    return KeyboardFeedbackSettings(
      audioConfiguration: enableAudio ? .enabled : .noFeedback,
      hapticConfiguration: enableHaptic ? .init(
        tap: hapticFeedback,
        doubleTap: hapticFeedback,
        longPress: hapticFeedback,
        longPressOnSpace: hapticFeedback,
        repeat: .selectionChanged
      ) : .noFeedback
    )
  }()

  /**
   The default, observable keyboard text context.

   默认的、可观察到的键盘文本上下文。

   This is used as global state to let you observe text in
   the ``textDocumentProxy``.

   这将作为全局状态，让您观察 ``textDocumentProxy`` 中的文本。
   */
  public lazy var keyboardTextContext = KeyboardTextContext()

  // MARK: - Services

  /**
   The autocomplete provider that is used to provide users
   with autocomplete suggestions.

   用于向用户提供自动完成建议的自动完成 provider。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var autocompleteProvider: AutocompleteProvider = DisabledAutocompleteProvider()

  /**
   The callout action provider that is used to provide the
   keyboard with secondary callout actions.

   用于为键盘提供辅助呼出操作的呼出操作 provider。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var calloutActionProvider: CalloutActionProvider = StandardCalloutActionProvider(
    keyboardContext: keyboardContext
  ) {
    didSet { refreshProperties() }
  }

  /**
   The input set provider that is used to define the input
   keys of the keyboard.

   输入集提供程序，用于定义键盘的输入键。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var inputSetProvider: InputSetProvider = StandardInputSetProvider(
    keyboardContext: keyboardContext,
    rimeContext: rimeContext
  ) {
    didSet { refreshProperties() }
  }

  /**
   The action handler that will be used by the keyboard to
   handle keyboard actions.

   用于处理按键 action 的 action 处理程序。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardActionHandler: KeyboardActionHandler = StandardKeyboardActionHandler(
    controller: self,
    keyboardContext: keyboardContext,
    rimeContext: rimeContext,
    keyboardBehavior: keyboardBehavior,
    autocompleteContext: autocompleteContext,
    keyboardFeedbackHandler: keyboardFeedbackHandler,
    spaceDragGestureHandler: SpaceCursorDragGestureHandler(
      feedbackHandler: keyboardFeedbackHandler,
      sensitivity: .custom(points: keyboardContext.hamsterConfiguration?.swipe?.spaceDragSensitivity ?? 5),
      action: { [weak self] in
        guard let self = self else { return }
        let offset = self.textDocumentProxy.spaceDragOffset(for: $0)
        self.adjustTextPosition(byCharacterOffset: offset ?? $0)
      }
    )
  ) {
    didSet { refreshProperties() }
  }

  /**
   The appearance that is used to customize the keyboard's
   design, such as its colors, fonts etc.

   用于自定义键盘的外观，如颜色、字体等。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardAppearance: KeyboardAppearance = StandardKeyboardAppearance(keyboardContext: keyboardContext)

  /**
   The behavior that is used to determine how the keyboard
   should behave when certain things happen.

   用于确定在某些事情发生时键盘应表现的行为。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardBehavior: KeyboardBehavior = StandardKeyboardBehavior(keyboardContext: keyboardContext)

  /**
   The feedback handler that is used to trigger haptic and
   audio feedback.

   用于触发触觉和音频反馈的反馈处理程序。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardFeedbackHandler: KeyboardFeedbackHandler = StandardKeyboardFeedbackHandler(settings: keyboardFeedbackSettings)

  /**
   This keyboard layout provider that is used to setup the
   complete set of keys and their layout.

   此键盘布局 provider 用于设置整套键盘按键及其布局。

   You can replace this with a custom implementation.

   您可以用自定义实现来替代它。
   */
  public lazy var keyboardLayoutProvider: KeyboardLayoutProvider = StandardKeyboardLayoutProvider(
    keyboardContext: keyboardContext,
    inputSetProvider: inputSetProvider
  )

  /**
   RIME 引擎上下文
   */
  public lazy var rimeContext = RimeContext()

  /// AzooKey 输入引擎（日语专用）
  lazy var azooKeyEngine = AzooKeyInputEngine()

  /// 英语输入引擎
  lazy var englishEngine = EnglishInputEngine()

  /// 系统文本替换管理器
  /// 用于读取和应用 iOS 系统的「文本替换」设置
  public lazy var systemTextReplacementManager = SystemTextReplacementManager()

  var isAzooKeyActive: Bool {
    rimeContext.currentSchema?.schemaId == HamsterConstants.azooKeySchemaId
  }

  var isAzooKeyInputActive: Bool {
    isAzooKeyActive && rimeContext.asciiModeSnapshot == false
  }

  /// 是否处于英语输入模式（ASCII模式 + 字母/中文主键盘）
  var isEnglishInputActive: Bool {
    guard rimeContext.asciiModeSnapshot else { return false }
    if englishEngine.isComposing { return true }
    if keyboardContext.keyboardType.isAlphabetic { return true }
    return isUnifiedCompositionBufferEnabled && keyboardContext.keyboardType.isChinesePrimaryKeyboard
  }

  func updateAzooKeySuggestions(_ suggestions: [CandidateSuggestion]) {
    if isUnifiedCompositionBufferEnabled {
      rimeContext.userInputKey = rimeContext.compositionPrefix + azooKeyEngine.currentRawInputText
    } else {
      rimeContext.userInputKey = azooKeyEngine.currentDisplayText
    }
    Task { @MainActor in
      self.rimeContext.suggestions = suggestions
      self.rimeContext.textReplacementSuggestions = []
    }
  }

  func updateEnglishSuggestions(_ suggestions: [CandidateSuggestion]) {
    rimeContext.userInputKey = rimeContext.compositionPrefix + englishEngine.currentDisplayText
    Task { @MainActor in
      self.rimeContext.suggestions = suggestions
      self.rimeContext.textReplacementSuggestions = []
    }
  }

  func clearEnglishState() {
    englishEngine.reset()
    rimeContext.userInputKey = rimeContext.compositionPrefix
    Task { @MainActor in
      self.rimeContext.suggestions = []
      self.rimeContext.textReplacementSuggestions = []
    }
  }

  func clearAzooKeyState() {
    rimeContext.userInputKey = rimeContext.compositionPrefix
    Task { @MainActor in
      self.rimeContext.suggestions = []
      self.rimeContext.textReplacementSuggestions = []
    }
  }

  private func azooKeyInputStyle(for text: String) -> InputStyle {
    guard text.count == 1, let scalar = text.unicodeScalars.first, scalar.isASCII else {
      return .direct
    }
    if CharacterSet.letters.contains(scalar) || text == "-" {
      return .roman2kana
    }
    return .direct
  }

  private func azooKeyLeftSideContext() -> String? {
    guard azooKeyEngine.requiresLeftSideContext else {
      return nil
    }
    let beforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
    var left = beforeInput.components(separatedBy: "\n").last ?? ""
    if beforeInput.contains("\n") && left.isEmpty {
      left = "\n"
    }
    let composing = azooKeyEngine.currentDisplayText
    if !composing.isEmpty, left.hasSuffix(composing) {
      left.removeLast(composing.count)
    }
    return left.isEmpty ? nil : left
  }

  var isUnifiedCompositionBufferEnabled: Bool {
    keyboardContext.enableMultiLanguageQuickMix
  }

  var isNumericCandidateModeEnabledOnChineseKeyboard: Bool {
    guard keyboardContext.enableNumericCandidateModeOnChineseKeyboard else { return false }
    if rimeContext.currentSchema?.isJapaneseSchema == true { return false }
    if rimeContext.asciiModeSnapshot { return false }
    return true
  }

  var isNumericCandidateModeEnabledOnJapaneseAzooKey: Bool {
    guard keyboardContext.enableNumericCandidateModeOnJapaneseAzooKey else { return false }
    return isAzooKeyInputActive
  }

  private var mixedInputDebugAlwaysOn: Bool {
    true
  }

  private var mixedInputDebugEnabled: Bool {
    mixedInputDebugAlwaysOn || keyboardContext.enableNumericCandidateModeOnChineseKeyboard
  }

  private func mixedInputDebugLog(_ message: String) {
    guard mixedInputDebugEnabled else { return }
    Logger.statistics.info("\(message, privacy: .public)")
    NSLog("%@", message)
  }

  private func mixedInputDebugSegmentsString() -> String {
    let segments = rimeContext.mixedInputManager.segments.map { segment -> String in
      switch segment.type {
      case .pinyin(let text):
        return "P:\(text)"
      case .literal(let display, let commit):
        return "L:\(display)|\(commit)"
      }
    }
    return segments.joined(separator: "|")
  }

  func shouldAppendPunctuationToCompositionPrefix(_ text: String) -> Bool {
    guard isUnifiedCompositionBufferEnabled else { return false }
    guard text.count == 1, let scalar = text.unicodeScalars.first else { return false }
    if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
    if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) { return false }
    return CharacterSet.punctuationCharacters.contains(scalar)
  }

  private func shouldTreatSymbolAsMixedInputLiteral(_ text: String) -> Bool {
    guard isNumericCandidateModeEnabledOnChineseKeyboard else { return false }
    guard text.count == 1, let scalar = text.unicodeScalars.first else { return false }
    if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
    if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) { return false }
    let shouldTreat = CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar)
    if shouldTreat {
      mixedInputDebugLog(
        "DBG_MIXEDINPUT symbolDecision char=\(text) numericMode=\(self.isNumericCandidateModeEnabledOnChineseKeyboard) userInputKey=\(self.rimeContext.userInputKey)"
      )
    }
    return shouldTreat
  }

  private func adjustedSymbolForContext(_ text: String) -> String {
    guard text.count == 1, let scalar = text.unicodeScalars.first else { return text }
    guard CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) else { return text }
    if isAzooKeyInputActive || isEnglishInputActive { return text }
    if rimeContext.currentSchema?.isJapaneseSchema == true { return text }

    var preferHalfwidth = rimeContext.asciiModeSnapshot
    func lastMeaningfulChar(in text: String) -> Character? {
      for ch in text.reversed() {
        if ch.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) {
          continue
        }
        return ch
      }
      return nil
    }

    func containsASCIILetters(_ text: String) -> Bool {
      text.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
    }

    let composingTextForLetterCheck: String? = {
      if let preedit = rimeContext.rimeContext?.composition?.preedit, !preedit.isEmpty {
        return preedit
      }
      if rimeContext.mixedInputManager.hasLiteral {
        return rimeContext.mixedInputManager.displayText
      }
      return nil
    }()

    if let composing = composingTextForLetterCheck, containsASCIILetters(composing) {
      // Pinyin composing: treat punctuation as fullwidth (e.g., "shuo:" -> "说：").
      preferHalfwidth = false
      return text.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? text
    }

    let contextTail: Character? = {
      if rimeContext.mixedInputManager.hasLiteral,
         let tail = lastMeaningfulChar(in: rimeContext.mixedInputManager.displayText)
      {
        return tail
      }
      if let preedit = rimeContext.rimeContext?.composition?.preedit,
         let tail = lastMeaningfulChar(in: preedit)
      {
        return tail
      }
      if let before = textDocumentProxy.documentContextBeforeInput,
         let tail = lastMeaningfulChar(in: before)
      {
        return tail
      }
      return nil
    }()

    if let tail = contextTail {
      if tail.unicodeScalars.contains(where: { $0.isASCII && (CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)) }) {
        preferHalfwidth = true
      } else {
        // Non-ASCII context forces fullwidth to keep behavior stable after Hanzi.
        preferHalfwidth = false
      }
    }

    if preferHalfwidth {
      return text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
    }
    return text.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? text
  }


  func hasActiveCompositionForBuffer() -> Bool {
    if !rimeContext.compositionPrefix.isEmpty {
      return true
    }
    if isAzooKeyInputActive {
      return azooKeyEngine.isComposing
    }
    if isEnglishInputActive {
      return englishEngine.isComposing
    }
    return !rimeContext.userInputKey.isEmpty
  }

  func hasPendingCompositionBeyondPrefix() -> Bool {
    if isAzooKeyInputActive {
      return azooKeyEngine.isComposing
    }
    if isEnglishInputActive {
      return englishEngine.isComposing
    }
    if rimeContext.mixedInputManager.hasLiteral {
      return true
    }
    if let preedit = rimeContext.rimeContext?.composition?.preedit, !preedit.isEmpty {
      return true
    }
    let prefix = rimeContext.compositionPrefix
    let display = rimeContext.userInputKey
    if !display.isEmpty {
      if !prefix.isEmpty, display.hasPrefix(prefix) {
        return !display.dropFirst(prefix.count).isEmpty
      }
      return true
    }
    return false
  }

  func currentComposingTextForRawCommit() -> String {
    if isAzooKeyInputActive {
      return azooKeyEngine.currentRawInputText
    }
    if isEnglishInputActive {
      return englishEngine.currentDisplayText
    }
    if rimeContext.mixedInputManager.hasLiteral {
      return rimeContext.mixedInputManager.displayText
    }
    if let preedit = rimeContext.rimeContext?.composition?.preedit, !preedit.isEmpty {
      return preedit
    }
    let display = rimeContext.userInputKey
    let prefix = rimeContext.compositionPrefix
    if !prefix.isEmpty, display.hasPrefix(prefix) {
      return String(display.dropFirst(prefix.count))
    }
    return display
  }

  func appendToCompositionPrefix(_ text: String) {
    guard isUnifiedCompositionBufferEnabled, !text.isEmpty else { return }
    rimeContext.compositionPrefix += text
    rimeContext.userInputKey = rimeContext.compositionPrefix
    Task { @MainActor in
      self.rimeContext.suggestions = []
      self.rimeContext.textReplacementSuggestions = []
    }
    clearMarkedTextIfNeeded()
  }

  func markedTextForCurrentInput(_ inputText: String) -> String {
    if !isUnifiedCompositionBufferEnabled {
      return inputText
    }
    if isAzooKeyInputActive {
      return azooKeyEngine.currentRawInputText
    }
    if isEnglishInputActive {
      return englishEngine.currentDisplayText
    }
    let prefix = rimeContext.compositionPrefix
    if !prefix.isEmpty, inputText.hasPrefix(prefix) {
      return String(inputText.dropFirst(prefix.count))
    }
    return inputText
  }

  func currentRimePreeditText() -> String {
    if let preedit = rimeContext.rimeContext?.composition?.preedit, !preedit.isEmpty {
      return preedit
    }
    let display = rimeContext.userInputKey
    let prefix = rimeContext.compositionPrefix
    if !prefix.isEmpty, display.hasPrefix(prefix) {
      return String(display.dropFirst(prefix.count))
    }
    return display
  }

  private func rawPinyinFromMixedInputIfPossible() -> String? {
    let display = rimeContext.mixedInputManager.displayText
    guard !display.isEmpty else { return nil }
    if display.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil { return nil }
    for scalar in display.unicodeScalars {
      if scalar == " " || scalar == "'" { continue }
      if scalar.value <= 0x7F, CharacterSet.letters.contains(scalar) { continue }
      if scalar == "ü" || scalar == "Ü" { continue }
      return nil
    }
    let raw = display.replacingOccurrences(of: " ", with: "")
    return raw.isEmpty ? nil : raw
  }

  func prepareMixedInputForDigitInsertion() {
    if !rimeContext.mixedInputManager.hasLiteral {
      rimeContext.mixedInputManager.reset()
      mixedInputSelectedNumericPrefix = nil
      resetMixedInputPrefixCache()
      let preedit = currentRimePreeditText()
      mixedInputDebugLog(
        "DBG_MIXEDINPUT prepareDigit preedit=\(preedit) display=\(self.rimeContext.userInputKey)"
      )
      if !preedit.isEmpty {
        mixedInputPrefixCandidates = snapshotMixedInputPrefixCandidates(limit: rimeContext.maximumNumberOfCandidateWords)
        mixedInputPrefixPinyinLetterCount = mixedInputPinyinLetterCount(preedit)
        mixedInputDebugLog(
          "DBG_MIXEDINPUT prepareDigit prefixCandidates=\(self.mixedInputPrefixCandidates.count) prefixLetters=\(self.mixedInputPrefixPinyinLetterCount)"
        )
        rimeContext.mixedInputManager.insertAtCursorPosition(preedit, isLiteral: false)
        rimeContext.resetCompositionKeepingMixedInput()
        mixedInputSuffixMode = true
      }
    }
  }

  func applyMarkedText(_ inputText: String) {
    guard keyboardContext.enableEmbeddedInputMode || isUnifiedCompositionBufferEnabled else { return }
    let markedText = markedTextForCurrentInput(inputText)
    if markedText.isEmpty {
      clearMarkedTextIfNeeded()
      return
    }
    textDocumentProxy.setMarkedText(markedText, selectedRange: NSMakeRange(markedText.utf8.count, 0))
  }

  func clearMarkedTextIfNeeded() {
    guard keyboardContext.enableEmbeddedInputMode || isUnifiedCompositionBufferEnabled else { return }
    textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
  }

  func commitCurrentCompositionToPrefixAndReset() {
    guard isUnifiedCompositionBufferEnabled else { return }
    let raw = currentComposingTextForRawCommit()
    if !raw.isEmpty {
      appendToCompositionPrefix(raw)
    }
    if isAzooKeyInputActive {
      azooKeyEngine.reset()
      clearAzooKeyState()
      return
    }
    if isEnglishInputActive {
      englishEngine.reset()
      clearEnglishState()
      return
    }
    rimeContext.reset()
    resetMixedInputFreezeState()
  }

  func commitFirstCandidateForLanguageSwitchIfNeeded() {
    guard isUnifiedCompositionBufferEnabled, hasActiveCompositionForBuffer() else { return }
    if isAzooKeyInputActive, azooKeyEngine.isComposing {
      if let commit = azooKeyEngine.commitCandidate(at: 0) {
        appendToCompositionPrefix(commit)
      } else {
        let fallback = azooKeyEngine.currentRawInputText
        if !fallback.isEmpty {
          appendToCompositionPrefix(fallback)
        }
      }
      clearAzooKeyState()
      return
    }

    if isEnglishInputActive, englishEngine.isComposing {
      if let commit = englishEngine.commitCandidate(at: 0) {
        appendToCompositionPrefix(commit)
      } else if let raw = englishEngine.commitRawText() {
        appendToCompositionPrefix(raw)
      }
      clearEnglishState()
      return
    }

    if !rimeContext.userInputKey.isEmpty {
      if let replacement = rimeContext.textReplacementSuggestions.first {
        appendToCompositionPrefix(replacement.text)
        Task { @MainActor in
          self.rimeContext.textReplacementSuggestions = []
        }
        rimeContext.reset()
        resetMixedInputFreezeState()
        return
      }
      if !rimeContext.suggestions.isEmpty {
        rimeContext.selectCandidate(index: 0)
        let commit = rimeContext.commitText
        rimeContext.resetCommitText()
        if !commit.isEmpty {
          appendToCompositionPrefix(commit)
          return
        }
      }
    }

    commitCurrentCompositionToPrefixAndReset()
  }

  func flushCompositionPrefixIfNeeded() {
    guard isUnifiedCompositionBufferEnabled else { return }
    let prefix = rimeContext.compositionPrefix
    guard !prefix.isEmpty else { return }
    textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
    textDocumentProxy.insertText(prefix)
    rimeContext.compositionPrefix = ""
    rimeContext.userInputKey = ""
    Task { @MainActor in
      self.rimeContext.suggestions = []
      self.rimeContext.textReplacementSuggestions = []
    }
  }

  // MARK: - Text And Selection, Implementations UITextInputDelegate

  /// 当文档中的选择即将发生变化时，通知输入委托。
  override open func selectionWillChange(_ textInput: UITextInput?) {
    super.selectionWillChange(textInput)
    resetAutocomplete()
  }

  /// 当文档中的选择发生变化时，通知输入委托。
  override open func selectionDidChange(_ textInput: UITextInput?) {
    super.selectionDidChange(textInput)
    resetAutocomplete()
  }

  /// 当 Document 中的 text 即将发生变化时，通知输入委托。
  /// - parameters:
  ///   * textInput: 采用 UITextInput 协议的文档实例。
  override open func textWillChange(_ textInput: UITextInput?) {
    super.textWillChange(textInput)

    // fix: 键盘跟随环境显示数字键盘
    if let keyboardType = textDocumentProxy.keyboardType, keyboardType.isNumberType {
      keyboardContext.setKeyboardType(.numericNineGrid)
    }

    if keyboardContext.textDocumentProxy === textDocumentProxy { return }
    keyboardContext.textDocumentProxy = textDocumentProxy
  }

  /// 当 Document 中的 text 发生变化时，通知输入委托。
  /// - parameters:
  ///   * textInput: 采用 UITextInput 协议的文档实例。
  override open func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
//    performAutocomplete()
//    performTextContextSync()
//    tryChangeToPreferredKeyboardTypeAfterTextDidChange()

    // fix: 输出栏点击右侧x形按钮后, 输入法候选栏内容没有跟随输入栏一同清空
    if !self.textDocumentProxy.hasText {
      self.rimeContext.reset()
      resetMixedInputFreezeState()
      if self.isAzooKeyActive {
        self.azooKeyEngine.reset()
        self.clearAzooKeyState()
      }
    }
    
    // 更新文本替换建议
    updateTextReplacementSuggestion()
    if viewWillHandleVoiceInputResult() || viewWillHandleCanvasInputResult() {
      stopVoiceResultPolling()
    }
  }
  
  /// 更新文本替换建议
  /// - Parameters:
  ///   - pendingText: 刚刚输入但尚未反映在 documentContextBeforeInput 中的文本
  ///   - rimePreview: RIME 引擎中待上屏的预览文本（用于中文/日文输入时预判）
  /// 更新文本替换建议
  /// - Parameters:
  ///   - pendingText: 刚刚输入但尚未反映在 documentContextBeforeInput 中的文本
  ///   - rimePreview: RIME 引擎中待上屏的预览文本（用于中文/日文输入时预判）
  func updateTextReplacementSuggestion(pendingText: String = "", rimePreview: String = "") {
    guard keyboardContext.hamsterConfiguration?.keyboard?.enableSystemTextReplacement == true else {
      rimeContext.textReplacementSuggestions = []
      return
    }
    
    // 获取光标前的文本
    let baseBeforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
    var suggestions = [(shortcut: String, replacement: String)]()
    var seenReplacements = Set<String>()

    // 本地函数：尝试匹配并添加结果
    func tryMatch(with content: String) {
      var beforeInput = baseBeforeInput
      beforeInput.append(content)

      guard !beforeInput.isEmpty else { return }

      let lastWord = systemTextReplacementManager.extractLastShortcut(from: beforeInput)
      guard !lastWord.isEmpty else { return }

      let matches = systemTextReplacementManager.getAllSuggestions(for: lastWord)
      for match in matches {
        if !seenReplacements.contains(match.replacement) {
          suggestions.append(match)
          seenReplacements.insert(match.replacement)
        }
      }
      if !matches.isEmpty {
        Logger.statistics.info("SystemTextReplacement: matched '\(lastWord, privacy: .public)' -> \(matches.count) results")
      }
    }
    
    // 1. 尝试使用 pendingText (英文输入)
    if !pendingText.isEmpty {
      tryMatch(with: pendingText)
    }
    
    // 2. 尝试使用 rimePreview (RIME 候选文字，如 '抽')
    if !rimePreview.isEmpty {
      tryMatch(with: rimePreview)
    }
    
    // 3. 尝试使用 userInputKey (RIME 原始输入码，如 'chou')
    // 只有在没有 pendingText 的情况下（即中文输入模式），且 userInputKey 不为空
    if pendingText.isEmpty, !rimeContext.userInputKey.isEmpty, rimeContext.userInputKey != rimePreview {
      tryMatch(with: rimeContext.userInputKey)
      
      // 额外尝试去除空格的 userInputKey (处理 RIME 拼音分词 'na ga' -> 'naga')
      let cleanedKey = rimeContext.userInputKey.replacingOccurrences(of: " ", with: "")
      if cleanedKey != rimeContext.userInputKey {
        tryMatch(with: cleanedKey)
      }
    }
    
    if !suggestions.isEmpty {
      var candidates = [CandidateSuggestion]()
      for (index, suggestion) in suggestions.enumerated() {
        let candidate = CandidateSuggestion(
          index: -(index + 1),
          label: "⇥",
          text: suggestion.replacement,
          title: suggestion.replacement,
          isAutocomplete: index == 0,
          subtitle: suggestion.shortcut
        )
        candidates.append(candidate)
      }
      rimeContext.textReplacementSuggestions = candidates
      Logger.statistics.info("SystemTextReplacement: showing total \(candidates.count) suggestions")
    } else {
      rimeContext.textReplacementSuggestions = []
    }
  }

  func applyTextReplacementCandidate(_ candidate: CandidateSuggestion) {
    let replacement = candidate.text
    let shortcut = candidate.subtitle ?? ""
    let preservedPrefix = preservedPrefixForTextReplacement(shortcut: shortcut)
    let hasComposing = isUnifiedCompositionBufferEnabled
      || keyboardContext.enableEmbeddedInputMode
      || azooKeyEngine.isComposing
      || englishEngine.isComposing
      || !rimeContext.userInputKey.isEmpty

    if isUnifiedCompositionBufferEnabled {
      resetComposingStateForTextReplacement()
      appendToCompositionPrefix(preservedPrefix + replacement)
      Task { @MainActor in
        self.rimeContext.textReplacementSuggestions = []
      }
      return
    }

    if hasComposing {
      resetComposingStateForTextReplacement()
      clearMarkedTextIfNeeded()
      textDocumentProxy.insertText(preservedPrefix + replacement)
      Task { @MainActor in
        self.rimeContext.textReplacementSuggestions = []
      }
      return
    }

    if !shortcut.isEmpty {
      textDocumentProxy.deleteBackward(times: shortcut.count)
    }
    textDocumentProxy.insertText(replacement)
    rimeContext.textReplacementSuggestions = []
  }

  private func preservedPrefixForTextReplacement(shortcut: String) -> String {
    guard !shortcut.isEmpty else { return "" }
    let composing = currentComposingTextForRawCommit()
    guard composing.hasSuffix(shortcut) else { return "" }
    return String(composing.dropLast(shortcut.count))
  }

  private func resetComposingStateForTextReplacement() {
    if isAzooKeyInputActive {
      azooKeyEngine.reset()
      clearAzooKeyState()
    }
    if isEnglishInputActive {
      englishEngine.reset()
      clearEnglishState()
    }
    if !rimeContext.userInputKey.isEmpty {
      rimeContext.reset()
      resetMixedInputFreezeState()
    }
  }

  // MARK: - Implementations KeyboardController

  open func adjustTextPosition(byCharacterOffset offset: Int) {
    textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
  }

  open func deleteBackward() {
    // 英语输入模式的删除处理
    if isEnglishInputActive && englishEngine.isComposing {
      let suggestions = englishEngine.deleteBackward()
      if suggestions.isEmpty {
        clearEnglishState()
      } else {
        updateEnglishSuggestions(suggestions)
      }
      return
    }

    if isAzooKeyInputActive {
      if azooKeyEngine.isComposing {
        let suggestions = azooKeyEngine.deleteBackward(leftSideContext: azooKeyLeftSideContext())
        if suggestions.isEmpty {
          clearAzooKeyState()
        } else {
          updateAzooKeySuggestions(suggestions)
        }
        return
      }
    }

    if isUnifiedCompositionBufferEnabled,
       !rimeContext.compositionPrefix.isEmpty,
       rimeContext.userInputKey == rimeContext.compositionPrefix
    {
      rimeContext.compositionPrefix.removeLast()
      rimeContext.userInputKey = rimeContext.compositionPrefix
      Task { @MainActor in
        self.rimeContext.suggestions = []
        self.rimeContext.textReplacementSuggestions = []
      }
      clearMarkedTextIfNeeded()
      return
    }
    guard !rimeContext.userInputKey.isEmpty else {
      // 获取光标前后上下文，用于删除需要光标居中的符号
      let beforeInput = self.textDocumentProxy.documentContextBeforeInput ?? ""
      let afterInput = self.textDocumentProxy.documentContextAfterInput ?? ""
      let text = String(beforeInput.suffix(1) + afterInput.prefix(1))
      // 光标可以居中的符号，需要成对删除
      if keyboardContext.cursorBackOfSymbols(key: text) {
        self.textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
        self.textDocumentProxy.deleteBackward(times: 2)
      } else {
        textDocumentProxy.deleteBackward(range: keyboardBehavior.backspaceRange)
      }
      return
    }

    // 借鉴 AzooKey：如果混合输入管理器中有直接文本（数字），先删除数字
    if rimeContext.hasMixedInputRevertSelection {
      if rimeContext.mixedInputManager.hasLiteral {
        _ = rimeContext.consumeMixedInputRevertSelection()
      } else if let restore = rimeContext.consumeMixedInputRevertSelection() {
        Task { @MainActor in
          func isPinyinLetter(_ scalar: UnicodeScalar) -> Bool {
            if scalar == "ü" || scalar == "Ü" { return true }
            return scalar.isASCII && CharacterSet.letters.contains(scalar)
          }

          let display = restore.displayText.isEmpty ? restore.rawInputKeys : restore.displayText
          let lettersOnly = display.unicodeScalars.filter { isPinyinLetter($0) }.map(String.init).joined()

          self.rimeContext.reset()
          self.resetMixedInputFreezeState()
          for char in lettersOnly {
            _ = self.rimeContext.tryHandleInputText(String(char))
          }

          self.rimeContext.mixedInputManager.reset()
          self.mixedInputSelectedNumericPrefix = nil
          self.rimeContext.mixedInputManager.rebuildSegments(from: display)
          if !restore.prefixLiteral.isEmpty {
            var remaining = restore.prefixLiteral
            var count = 0
            for segment in self.rimeContext.mixedInputManager.segments {
              guard segment.isLiteral else { break }
              let text = segment.text
              if remaining.hasPrefix(text) {
                remaining.removeFirst(text.count)
                count += 1
                if remaining.isEmpty { break }
              } else {
                break
              }
            }
            self.rimeContext.mixedInputManager.literalPrefixSegmentCount = max(count, 1)
          }
          self.rimeContext.userInputKey = self.rimeContext.compositionPrefix + self.rimeContext.mixedInputManager.displayText
          self.updateMixedInputSuggestions()
        }
        return
      }
    }

    if rimeContext.mixedInputManager.hasLiteral {
      // 检查最后一个段是否为数字
      if let lastSegment = rimeContext.mixedInputManager.segments.last, lastSegment.isLiteral {
        // 删除数字
        rimeContext.mixedInputManager.deleteBackward()
        if let raw = rawPinyinFromMixedInputIfPossible() {
          Task { @MainActor in
            self.rimeContext.reset()
            self.resetMixedInputFreezeState()
            for char in raw {
              _ = self.rimeContext.tryHandleInputText(String(char))
            }
          }
          return
        }
        // 更新显示
        if rimeContext.mixedInputManager.hasLiteral {
          rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        } else {
          // 已无混输内容时，清空 RIME 组字，避免残留原始拼音
          resetMixedInputFreezeState()
          rimeContext.reset()
          clearMarkedTextIfNeeded()
          return
        }
        mixedInputDebugLog("DBG_MIXEDINPUT delete literal, display: \(self.rimeContext.userInputKey)")
        // 更新候选词
        updateMixedInputSuggestions()
        return
      }
    }

    // 同步删除混合输入管理器中的拼音
    if !rimeContext.mixedInputManager.isEmpty {
      rimeContext.mixedInputManager.deleteBackward()
    }

    // 拼音九宫格处理
    if keyboardContext.keyboardType.isChineseNineGrid {
      if let selectCandidatePinyin = rimeContext.selectCandidatePinyin {
        if let t9pinyin = pinyinToT9Mapping[selectCandidatePinyin.0] {
          let handled = rimeContext.tryHandleReplaceInputTexts(t9pinyin, startPos: selectCandidatePinyin.1, count: selectCandidatePinyin.2)
          Logger.statistics.info("change input text handled: \(handled)")
        }
        rimeContext.selectCandidatePinyin = nil
        return
      }
    }

    // 非九宫格处理
    rimeContext.deleteBackward()

    // 如果还有混合输入（数字），更新候选词
    if rimeContext.mixedInputManager.hasLiteral {
      updateMixedInputSuggestions()
    }
  }

  open func deleteBackward(times: Int) {
    textDocumentProxy.deleteBackward(times: times)
  }

  open func insertSymbol(_ symbol: Symbol) {
    let adjustedChar = adjustedSymbolForContext(symbol.char)
    Logger.statistics.info("DBG_RIMEINPUT insertSymbol: \(adjustedChar, privacy: .public), keyboardType: \(String(describing: self.keyboardContext.keyboardType), privacy: .public), asciiSnapshot: \(self.rimeContext.asciiModeSnapshot), schema: \(self.rimeContext.currentSchema?.schemaId ?? "nil", privacy: .public)")
    if adjustedChar.count == 1, let scalar = adjustedChar.unicodeScalars.first,
       (CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar))
    {
      let treatAsLiteral = shouldTreatSymbolAsMixedInputLiteral(adjustedChar)
      mixedInputDebugLog(
        "DBG_MIXEDINPUT symbolCheck insertSymbol char=\(adjustedChar) treatAsLiteral=\(treatAsLiteral) hasLiteral=\(self.rimeContext.mixedInputManager.hasLiteral) display=\(self.rimeContext.userInputKey)"
      )
    }
    if isUnifiedCompositionBufferEnabled, adjustedChar == .space {
      insertRimeKeyCode(XK_space)
      return
    }
    if shouldAppendPunctuationToCompositionPrefix(adjustedChar)
        && !shouldTreatSymbolAsMixedInputLiteral(adjustedChar)
    {
      if hasActiveCompositionForBuffer() {
        commitFirstCandidateForLanguageSwitchIfNeeded()
      }
      appendToCompositionPrefix(adjustedChar)
      return
    }

    // 英语输入模式：使用候选栏
    if isEnglishInputActive {
      let text = symbol.char
      Logger.statistics.info("DBG_ENGLISH insertSymbol: \(text, privacy: .public)")
      let isLetter = text.count == 1 && text.rangeOfCharacter(from: CharacterSet.letters) != nil
      let isDigit = text.count == 1 && text.first?.isNumber == true
      if isLetter || (englishEngine.isComposing && isDigit) {
        let suggestions = englishEngine.handleInput(text)
        Logger.statistics.info("DBG_ENGLISH suggestions count: \(suggestions.count), isComposing: \(self.englishEngine.isComposing)")
        if englishEngine.isComposing {
          updateEnglishSuggestions(suggestions)
        } else {
          clearEnglishState()
          self.textDocumentProxy.insertText(text)
        }
      } else {
        // 非字母且没有正在输入的内容，提交当前输入后直接上屏
        if englishEngine.isComposing {
          if let commit = englishEngine.commitCandidate(at: 0) {
            textDocumentProxy.insertText(commit)
          } else if let raw = englishEngine.commitRawText() {
            textDocumentProxy.insertText(raw)
          }
          clearEnglishState()
        }
        self.textDocumentProxy.insertText(text)
      }
      return
    }

    if isAzooKeyActive {
      let char = adjustedChar
      // 借鉴 AzooKey 独立应用：数字也传给引擎，使用 .direct 样式
      // AzooKey 的 composingText 会统一管理所有输入（包括数字）
      let isDigit = char.count == 1 && char.first?.isNumber == true
      let isSymbol = char.count == 1 && char.unicodeScalars.contains {
        CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
      }
      if isDigit && (azooKeyEngine.isComposing || isNumericCandidateModeEnabledOnJapaneseAzooKey) {
        // 数字使用 .direct 样式传给 AzooKey 引擎
        let suggestions = azooKeyEngine.handleInput(char, inputStyle: .direct, leftSideContext: azooKeyLeftSideContext())
        if azooKeyEngine.isComposing {
          updateAzooKeySuggestions(suggestions)
        } else {
          clearAzooKeyState()
          self.insertTextPatch(char)
        }
        return
      }
      if isSymbol && isNumericCandidateModeEnabledOnJapaneseAzooKey {
        let suggestions = azooKeyEngine.handleInput(char, inputStyle: .direct, leftSideContext: azooKeyLeftSideContext())
        if azooKeyEngine.isComposing {
          updateAzooKeySuggestions(suggestions)
        } else {
          clearAzooKeyState()
          self.insertTextPatch(char)
        }
        return
      }

      let style = azooKeyInputStyle(for: char)
      if style == .roman2kana {
        let suggestions = azooKeyEngine.handleInput(char, inputStyle: style, leftSideContext: azooKeyLeftSideContext())
        if azooKeyEngine.isComposing {
          updateAzooKeySuggestions(suggestions)
        } else {
          clearAzooKeyState()
          self.insertTextPatch(char)
        }
        return
      }
      if azooKeyEngine.isComposing {
        let suggestions = azooKeyEngine.handleInput(char, inputStyle: .direct, leftSideContext: azooKeyLeftSideContext())
        if azooKeyEngine.isComposing {
          updateAzooKeySuggestions(suggestions)
        } else {
          clearAzooKeyState()
          self.insertTextPatch(char)
        }
        return
      }
      self.insertTextPatch(char)
      return
    }
    if self.keyboardContext.keyboardType.isAlphabetic,
       self.rimeContext.asciiModeSnapshot == false,
       self.rimeContext.currentSchema?.isJapaneseSchema == true
    {
      let char = symbol.char
      if char == "-" || (char.count == 1 && char.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.letters.contains($0) })) {
        let handled = self.rimeContext.tryHandleInputText(char)
        Logger.statistics.info("DBG_RIMEINPUT routeSymbolToRime: \(char, privacy: .public), handled: \(handled)")
        if handled { return }
      }
    }
    // 借鉴 AzooKey：检查是否为数字且当前有 RIME 输入（在 insertSymbol 中也需要拦截）
    let char = adjustedChar
    let isDigit = char.count == 1 && char.first?.isNumber == true
    if isDigit && rimeContext.userInputKey.isEmpty && isNumericCandidateModeEnabledOnChineseKeyboard {
      rimeContext.mixedInputManager.reset()
      mixedInputSelectedNumericPrefix = nil
      rimeContext.mixedInputManager.insertAtCursorPosition(char, isLiteral: true)
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      updateMixedInputSuggestions()
      return
    }
    if isDigit && !rimeContext.userInputKey.isEmpty {
      prepareMixedInputForDigitInsertion()
      // 数字添加到混合输入管理器，不触发顶码上屏
      rimeContext.mixedInputManager.insertAtCursorPosition(char, isLiteral: true)
      // 更新显示：将数字追加到 userInputKey
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      // 更新候选词（将数字与候选词合并）
      updateMixedInputSuggestions()
      return
    }

    if shouldTreatSymbolAsMixedInputLiteral(char),
       rimeContext.currentSchema?.isJapaneseSchema != true
    {
      if rimeContext.userInputKey.isEmpty && !rimeContext.mixedInputManager.hasLiteral {
        rimeContext.mixedInputManager.reset()
        mixedInputSelectedNumericPrefix = nil
        rimeContext.mixedInputManager.insertAtCursorPosition(char, isLiteral: true)
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        mixedInputDebugLog(
          "DBG_MIXEDINPUT insertSymbol literal start=\(char) display=\(self.rimeContext.userInputKey) segments=\(self.mixedInputDebugSegmentsString())"
        )
        updateMixedInputSuggestions()
        return
      }
      prepareMixedInputForDigitInsertion()
      rimeContext.mixedInputManager.insertAtCursorPosition(char, isLiteral: true)
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      mixedInputDebugLog(
        "DBG_MIXEDINPUT insertSymbol literal=\(char) display=\(self.rimeContext.userInputKey) segments=\(self.mixedInputDebugSegmentsString())"
      )
      updateMixedInputSuggestions()
      return
    }

    // 检测是否需要顶字上屏（非数字符号才触发）
    if !rimeContext.userInputKey.isEmpty {
      // 内嵌模式需要先清空
      if keyboardContext.enableEmbeddedInputMode {
        self.textDocumentProxy.setMarkedText("", selectedRange: NSMakeRange(0, 0))
      }
      // fix: 内嵌模式问题
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
        guard let self = self else { return }
        // 顶码上屏
        if self.keyboardContext.swipePaging {
          if let firstCandidate = self.rimeContext.suggestions.first {
            self.textDocumentProxy.insertText(firstCandidate.text)
          }
        } else {
          if let commit = self.rimeContext.rimeContext?.commitTextPreview {
            self.textDocumentProxy.insertText(commit)
          }
        }
        self.rimeContext.reset()
        self.resetMixedInputFreezeState()
        self.insertTextPatch(adjustedChar)
      }
      return
    }
    self.insertTextPatch(adjustedChar)
  }

  open func insertText(_ text: String) {
    let adjustedText = adjustedSymbolForContext(text)
    Logger.statistics.info("DBG_RIMEINPUT insertText: \(adjustedText, privacy: .public), keyboardType: \(String(describing: self.keyboardContext.keyboardType), privacy: .public), asciiSnapshot: \(self.rimeContext.asciiModeSnapshot), schema: \(self.rimeContext.currentSchema?.schemaId ?? "nil", privacy: .public)")
    if adjustedText.count == 1, let scalar = adjustedText.unicodeScalars.first,
       (CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar))
    {
      let treatAsLiteral = shouldTreatSymbolAsMixedInputLiteral(adjustedText)
      mixedInputDebugLog(
        "DBG_MIXEDINPUT symbolCheck insertText char=\(adjustedText) treatAsLiteral=\(treatAsLiteral) hasLiteral=\(self.rimeContext.mixedInputManager.hasLiteral) display=\(self.rimeContext.userInputKey)"
      )
    }
    if isUnifiedCompositionBufferEnabled, adjustedText == .space {
      insertRimeKeyCode(XK_space)
      return
    }
    if shouldAppendPunctuationToCompositionPrefix(adjustedText)
        && !shouldTreatSymbolAsMixedInputLiteral(adjustedText)
    {
      if hasActiveCompositionForBuffer() {
        commitFirstCandidateForLanguageSwitchIfNeeded()
      }
      appendToCompositionPrefix(adjustedText)
      return
    }
    if isAzooKeyInputActive {
      // 借鉴 AzooKey 独立应用：数字也传给引擎，使用 .direct 样式
      let isDigit = adjustedText.count == 1 && adjustedText.first?.isNumber == true
      let isSymbol = adjustedText.count == 1 && adjustedText.unicodeScalars.contains {
        CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
      }
      if isDigit && (azooKeyEngine.isComposing || isNumericCandidateModeEnabledOnJapaneseAzooKey) {
        // 数字使用 .direct 样式传给 AzooKey 引擎
        let suggestions = azooKeyEngine.handleInput(adjustedText, inputStyle: .direct, leftSideContext: azooKeyLeftSideContext())
        if azooKeyEngine.isComposing {
          updateAzooKeySuggestions(suggestions)
        } else {
          clearAzooKeyState()
          self.insertTextPatch(adjustedText)
        }
        return
      }
      if isSymbol && isNumericCandidateModeEnabledOnJapaneseAzooKey {
        let suggestions = azooKeyEngine.handleInput(adjustedText, inputStyle: .direct, leftSideContext: azooKeyLeftSideContext())
        if azooKeyEngine.isComposing {
          updateAzooKeySuggestions(suggestions)
        } else {
          clearAzooKeyState()
          self.insertTextPatch(adjustedText)
        }
        return
      }

      let style = azooKeyInputStyle(for: adjustedText)
      let suggestions = azooKeyEngine.handleInput(adjustedText, inputStyle: style, leftSideContext: azooKeyLeftSideContext())
      if azooKeyEngine.isComposing {
        updateAzooKeySuggestions(suggestions)
      } else {
        clearAzooKeyState()
        self.insertTextPatch(adjustedText)
      }
      return
    }
    if isEnglishInputActive {
      // 英语输入模式：使用候选栏
      Logger.statistics.info("DBG_ENGLISH insertText: \(adjustedText, privacy: .public), asciiMode: true")
      let isLetter = adjustedText.count == 1 && adjustedText.rangeOfCharacter(from: CharacterSet.letters) != nil
      let isDigit = adjustedText.count == 1 && adjustedText.first?.isNumber == true
      Logger.statistics.info("DBG_ENGLISH isLetter: \(isLetter), isComposing: \(self.englishEngine.isComposing)")
      if isLetter || (englishEngine.isComposing && isDigit) {
        let suggestions = englishEngine.handleInput(adjustedText)
        Logger.statistics.info("DBG_ENGLISH suggestions count: \(suggestions.count), isComposing: \(self.englishEngine.isComposing)")
        if englishEngine.isComposing {
          updateEnglishSuggestions(suggestions)
        } else {
          // 非字母输入且没有正在输入的内容，直接上屏
          clearEnglishState()
          self.textDocumentProxy.insertText(adjustedText)
        }
      } else {
        // 非字母且没有正在输入的内容，直接上屏
        if englishEngine.isComposing {
          if let commit = englishEngine.commitCandidate(at: 0) {
            textDocumentProxy.insertText(commit)
          } else if let raw = englishEngine.commitRawText() {
            textDocumentProxy.insertText(raw)
          }
          clearEnglishState()
        }
        self.textDocumentProxy.insertText(adjustedText)
      }
      return
    }

    // 借鉴 AzooKey：检查是否为数字且当前有 RIME 输入
    let isDigit = adjustedText.count == 1 && adjustedText.first?.isNumber == true
    if isDigit && rimeContext.userInputKey.isEmpty && isNumericCandidateModeEnabledOnChineseKeyboard {
      rimeContext.mixedInputManager.reset()
      mixedInputSelectedNumericPrefix = nil
      rimeContext.mixedInputManager.insertAtCursorPosition(adjustedText, isLiteral: true)
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      updateMixedInputSuggestions()
      return
    }
    if isDigit && !rimeContext.userInputKey.isEmpty {
      prepareMixedInputForDigitInsertion()
      // 数字添加到混合输入管理器，不发送给 RIME
      rimeContext.mixedInputManager.insertAtCursorPosition(adjustedText, isLiteral: true)
      // 更新显示：将数字追加到 userInputKey
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      // 更新候选词（将数字与候选词合并）
      updateMixedInputSuggestions()
      return
    }

    if shouldTreatSymbolAsMixedInputLiteral(adjustedText),
       rimeContext.currentSchema?.isJapaneseSchema != true
    {
      if rimeContext.userInputKey.isEmpty && !rimeContext.mixedInputManager.hasLiteral {
        rimeContext.mixedInputManager.reset()
        mixedInputSelectedNumericPrefix = nil
        rimeContext.mixedInputManager.insertAtCursorPosition(adjustedText, isLiteral: true)
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        mixedInputDebugLog(
          "DBG_MIXEDINPUT insertText literal start=\(adjustedText) display=\(self.rimeContext.userInputKey) segments=\(self.mixedInputDebugSegmentsString())"
        )
        updateMixedInputSuggestions()
        return
      }
      prepareMixedInputForDigitInsertion()
      rimeContext.mixedInputManager.insertAtCursorPosition(adjustedText, isLiteral: true)
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      mixedInputDebugLog(
        "DBG_MIXEDINPUT insertText literal=\(adjustedText) display=\(self.rimeContext.userInputKey) segments=\(self.mixedInputDebugSegmentsString())"
      )
      updateMixedInputSuggestions()
      return
    }

    // 非数字字符，同时添加到混合输入管理器
    if !isDigit && rimeContext.mixedInputManager.hasLiteral {
      rimeContext.mixedInputManager.insertAtCursorPosition(adjustedText, isLiteral: false)
    }

    // 字母输入模式，不经过 rime 引擎
    // if rimeContext.asciiMode {
    //  textDocumentProxy.insertText(text)
    //  return
    // }
    // rime 引擎处理
    let handled = self.rimeContext.tryHandleInputText(adjustedText)
    Logger.statistics.info("DBG_RIMEINPUT tryHandleInputText: \(adjustedText, privacy: .public), handled: \(handled)")
    if !handled {
      Logger.statistics.error("try handle input text: \(adjustedText), handle false")
      Logger.statistics.error("DBG_RIMEINPUT fallback insertTextPatch for: \(adjustedText, privacy: .public)")
      self.insertTextPatch(adjustedText)
      return
    }

    // 更新文本替换建议（使用 RIME 预览文本来预判匹配）
    let rimePreview = self.rimeContext.rimeContext?.commitTextPreview ?? ""
    updateTextReplacementSuggestion(rimePreview: rimePreview)

    // 如果有混合输入（数字），更新候选词
    if rimeContext.mixedInputManager.hasLiteral {
      updateMixedInputSuggestions()
    }
  }

  /// 更新混合输入候选词（将数字与 RIME 候选词合并）
  private func updateMixedInputSuggestions() {
    if rimeContext.mixedInputManager.hasLiteral,
       rimeContext.mixedInputManager.pinyinOnly.isEmpty
    {
      let literalOnly = rimeContext.mixedInputManager.literalOnly
      let configuredPrefixCount = rimeContext.mixedInputManager.literalPrefixSegmentCount
      let literalExcludingPrefix: String
      if configuredPrefixCount > 0 {
        var skipped = 0
        var result = ""
        for segment in rimeContext.mixedInputManager.segments {
          guard segment.isLiteral else { continue }
          if skipped < configuredPrefixCount {
            skipped += 1
            continue
          }
          result += segment.commitText
        }
        literalExcludingPrefix = result
      } else {
        literalExcludingPrefix = literalOnly
      }

      let literalSuffix = rimeContext.mixedInputManager.literalOnlyExcludingPrefix
      let canUseSuffixOnly = !literalSuffix.isEmpty
        && (isNumericLiteralText(literalSuffix) || isSymbolLiteralText(literalSuffix))
      let literal: String
      if configuredPrefixCount > 0, canUseSuffixOnly {
        literal = literalSuffix
      } else if configuredPrefixCount > 0, !literalExcludingPrefix.isEmpty,
                (isNumericLiteralText(literalExcludingPrefix) || isSymbolLiteralText(literalExcludingPrefix)) {
        literal = literalExcludingPrefix
      } else {
        literal = literalOnly
      }
      var texts: [String] = []
      if !literal.isEmpty {
        if isSymbolLiteralText(literal) {
          texts = symbolCandidates(for: literal)
        } else if isNumericLiteralText(literal) {
          var seen = Set<String>()
          func appendUnique(_ text: String) {
            guard !text.isEmpty else { return }
            if seen.insert(text).inserted {
              texts.append(text)
            }
          }

          for text in NumericCandidateGenerator.candidateTexts(for: literal) {
            appendUnique(text)
          }

          if let split = splitNumericSuffix(literal) {
            let digits = split.digits
            let suffix = split.suffix
            if !digits.isEmpty {
              if !suffix.isEmpty {
                for text in NumericCandidateGenerator.candidateTexts(for: digits) {
                  appendUnique(text)
                }
              }
              if digits.count > 1 {
                let leading = String(digits.prefix(1))
                for text in NumericCandidateGenerator.candidateTexts(for: leading) {
                  appendUnique(text)
                }
              }
            }
          }
        } else {
          texts = [literal]
        }
      }
      mixedInputDebugLog(
        "DBG_MIXEDINPUT updateSuggestions literalOnly=\(literalOnly) literalExcludingPrefix=\(literalExcludingPrefix) literalSuffix=\(literalSuffix) literal=\(literal) texts=\(texts.prefix(8).joined(separator: "|"))"
      )
      Task { @MainActor in
        var newSuggestions: [CandidateSuggestion] = []
        for (index, text) in texts.enumerated() {
          let suggestion = CandidateSuggestion(
            index: index,
            label: "\(index + 1)",
            text: text,
            title: text,
            isAutocomplete: index == 0,
            subtitle: nil
          )
          newSuggestions.append(suggestion)
        }
        if !newSuggestions.isEmpty {
          self.rimeContext.suggestions = newSuggestions
        } else {
          self.rimeContext.suggestions = []
        }
      }
      return
    }

    // 获取当前的 RIME 候选词（避免基于已合成候选再次合成导致重复）
    func fetchBaseCandidates() -> [CandidateSuggestion] {
      var candidates: [CandidateSuggestion] = []
      let hasRimePreedit = !(rimeContext.rimeContext?.composition?.preedit?.isEmpty ?? true)
      let rimeComposing = rimeContext.isComposing && hasRimePreedit
      if rimeComposing, let menu = rimeContext.rimeContext?.menu {
        let highlightIndex = Int(menu.pageSize * menu.pageNo + menu.highlightedCandidateIndex)
        candidates = rimeContext.candidateListLimit(
          index: rimeContext.candidateIndex,
          highlightIndex: highlightIndex,
          count: rimeContext.maximumNumberOfCandidateWords
        )
      } else if rimeComposing, !rimeContext.getInputKeys().isEmpty {
        candidates = rimeContext.candidateListLimit(
          index: rimeContext.candidateIndex,
          highlightIndex: 0,
          count: rimeContext.maximumNumberOfCandidateWords
        )
        if candidates.isEmpty {
          candidates = rimeContext.suggestions
        }
      }
      return candidates
    }

    var baseCandidates = fetchBaseCandidates()
    let prefixPending = rimeContext.mixedInputManager.pinyinOnlyBeforeFirstDigitLiteral
    if rimeContext.mixedInputManager.hasLiteral,
       mixedInputSelectedPinyinPrefix != nil,
       !prefixPending.isEmpty,
       !mixedInputResyncing
    {
      mixedInputResyncing = true
      syncRimeInputWithMixedPinyinIfNeeded()
      baseCandidates = fetchBaseCandidates()
      mixedInputResyncing = false
    } else if baseCandidates.isEmpty,
              rimeContext.mixedInputManager.hasLiteral,
              !prefixPending.isEmpty,
              mixedInputSelectedPinyinPrefix != nil,
              !mixedInputResyncing
    {
      mixedInputResyncing = true
      syncRimeInputWithMixedPinyinIfNeeded()
      baseCandidates = fetchBaseCandidates()
      mixedInputResyncing = false
    }
    if rimeContext.mixedInputManager.hasLiteral,
       mixedInputSelectedPinyinPrefix != nil,
       !prefixPending.isEmpty,
       mixedInputPrefixCandidates.isEmpty
    {
      mixedInputPrefixCandidates = snapshotMixedInputPrefixCandidates(limit: rimeContext.maximumNumberOfCandidateWords)
      mixedInputPrefixPinyinLetterCount = mixedInputPinyinLetterCount(currentRimePreeditText())
    }
    let composedCandidates: [CandidateSuggestion]
    if rimeContext.mixedInputManager.hasLiteral, !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
      let digitPrefix = rimeContext.mixedInputManager.digitLiteralBeforeFirstPinyin
      let syllablesBeforeMiddleDigit = rimeContext.mixedInputManager.syllableCountBeforeMiddleDigit
      let hasPinyinPrefixCandidates = !mixedInputPrefixCandidates.isEmpty
      let prefixLiteral = rimeContext.mixedInputManager.literalPrefixText
      let hasNumericPrefix = !prefixLiteral.isEmpty && isNumericLiteralText(prefixLiteral)
      let hasNonDigitPrefixLiteral = !prefixLiteral.isEmpty && !isNumericLiteralText(prefixLiteral)
      if !hasNumericPrefix {
        mixedInputSelectedNumericPrefix = nil
      } else if let selected = mixedInputSelectedNumericPrefix, selected != prefixLiteral {
        mixedInputSelectedNumericPrefix = nil
      }
      let prefixCandidateSeed = hasNumericPrefix ? prefixLiteral : ""
      let configuredPrefixCount = rimeContext.mixedInputManager.literalPrefixSegmentCount
      let leadingPrefixCount = rimeContext.mixedInputManager.leadingLiteralSegmentCount
      let hasCommittedPrefixSegments = configuredPrefixCount > 0
        && leadingPrefixCount > 0
        && configuredPrefixCount >= leadingPrefixCount
      let includePrefixLiteral = hasNumericPrefix
        && mixedInputSelectedNumericPrefix == nil
        && !hasCommittedPrefixSegments
      let shouldInjectPrefixCandidates = hasNumericPrefix && mixedInputSelectedNumericPrefix == nil
      let maxCandidates = max(1, rimeContext.maximumNumberOfCandidateWords)
      let limited = Array(baseCandidates.prefix(maxCandidates))
      let hasDigitPrefix = !digitPrefix.isEmpty
      let prioritizeDigitPrefix = hasDigitPrefix && hasNonDigitPrefixLiteral
      let appendCount = min(hasDigitPrefix ? 1 : mixedInputAppendDigitCandidateCount, limited.count)

      var mergedTexts: [(text: String, index: Int, subtitle: String?)] = []
      var seen = Set<String>()
      var injectedIndex = mixedInputInjectedCandidateIndexBase
      var prefixInjectedIndex = mixedInputPrefixCandidateIndexBase
      var pinyinPrefixInjectedIndex = mixedInputPinyinPrefixCandidateIndexBase

      func appendCandidate(text: String, index: Int, subtitle: String?) {
        guard !text.isEmpty else { return }
        if seen.insert(text).inserted {
          mergedTexts.append((text: text, index: index, subtitle: subtitle))
        }
      }

      func appendDigitPrefixCandidates(includeCombo: Bool) {
        let numericTexts = NumericCandidateGenerator.candidateTexts(for: digitPrefix)
        for text in numericTexts {
          appendCandidate(text: text, index: injectedIndex, subtitle: nil)
          injectedIndex -= 1
        }

        guard includeCombo else { return }
        let preedit = currentRimePreeditText()
        let rawTail = preedit.replacingOccurrences(of: " ", with: "")
        if !rawTail.isEmpty {
          let asciiCombo = digitPrefix + rawTail
          appendCandidate(text: asciiCombo, index: injectedIndex, subtitle: nil)
          injectedIndex -= 1

          let fullwidthTail = rawTail.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? rawTail
          let fullwidthCombo = digitPrefix + fullwidthTail
          if fullwidthCombo != asciiCombo {
            appendCandidate(text: fullwidthCombo, index: injectedIndex, subtitle: nil)
            injectedIndex -= 1
          }
        }
      }

      let middleDigitLiteral = rimeContext.mixedInputManager.digitLiteralAfterFirstPinyin
      let trailingSymbolLiteral = mixedInputTrailingSymbolLiteralAfterLastPinyin()
      let hasTrailingSymbolLiteral = !trailingSymbolLiteral.isEmpty
      let hasMiddleDigit = !middleDigitLiteral.isEmpty
      let prefixPending = rimeContext.mixedInputManager.pinyinOnlyBeforeFirstDigitLiteral
      let hasSuffixPinyin = !rimeContext.mixedInputManager.pinyinOnlyAfterFirstLiteral.isEmpty
      let prefixChosen = mixedInputSelectedPinyinPrefix != nil
      let effectiveSuffixMode = (mixedInputSuffixMode || hasMiddleDigit) && (prefixPending.isEmpty || !prefixChosen)
      let shouldUseSuffixCandidates = hasSuffixPinyin && !prefixChosen
      let suppressSuffixCandidates = hasMiddleDigit && !prefixChosen
      let deferPrefixCandidates = hasMiddleDigit && prefixChosen && !prefixPending.isEmpty

      if hasMiddleDigit,
         hasTrailingSymbolLiteral,
         let prefixCandidate = mixedInputPrefixCandidates.first?.text,
         !prefixCandidate.isEmpty
      {
        let suffixCandidate = shouldUseSuffixCandidates ? (baseCandidates.first?.text ?? "") : ""
        if !suffixCandidate.isEmpty || !hasSuffixPinyin {
          let combinedText = prefixCandidate + middleDigitLiteral + suffixCandidate + trailingSymbolLiteral
          appendCandidate(text: combinedText, index: mixedInputCombinedCandidateIndexBase, subtitle: nil)
        }
      }

      if hasMiddleDigit,
         let prefixCandidate = mixedInputPrefixCandidates.first?.text,
         !prefixCandidate.isEmpty
      {
        let suffixCandidate = shouldUseSuffixCandidates ? (baseCandidates.first?.text ?? "") : ""
        let combinedText = prefixCandidate + middleDigitLiteral + suffixCandidate
        appendCandidate(text: combinedText, index: mixedInputCombinedCandidateIndexBase, subtitle: nil)
      }

      if prioritizeDigitPrefix {
        let suffixCandidate = shouldUseSuffixCandidates ? (baseCandidates.first?.text ?? "") : ""
        let combinedText = digitPrefix + suffixCandidate
        appendCandidate(text: combinedText, index: mixedInputCombinedCandidateIndexBase, subtitle: nil)
      }

      if hasTrailingSymbolLiteral, !hasMiddleDigit, !hasSuffixPinyin {
        if let prefixCandidate = mixedInputPrefixCandidates.first?.text, !prefixCandidate.isEmpty {
          let combinedText = prefixCandidate + trailingSymbolLiteral
          appendCandidate(text: combinedText, index: mixedInputCombinedCandidateIndexBase, subtitle: nil)
        } else if let firstBase = baseCandidates.first?.text, !firstBase.isEmpty {
          let baseText = includePrefixLiteral
            ? rimeContext.mixedInputManager.composeCandidateForDisplay(firstBase, includePrefixLiteral: true)
            : firstBase
          let combinedText = baseText + trailingSymbolLiteral
          appendCandidate(text: combinedText, index: mixedInputCombinedCandidateIndexBase, subtitle: nil)
        }
      }

      if hasPinyinPrefixCandidates, !deferPrefixCandidates {
        if hasMiddleDigit {
          let headCount = min(4, mixedInputPrefixCandidates.count)
          for candidate in mixedInputPrefixCandidates.prefix(headCount) {
            appendCandidate(text: candidate.text, index: pinyinPrefixInjectedIndex, subtitle: candidate.subtitle)
            pinyinPrefixInjectedIndex -= 1
          }
        } else {
          for candidate in mixedInputPrefixCandidates {
            appendCandidate(text: candidate.text, index: pinyinPrefixInjectedIndex, subtitle: candidate.subtitle)
            pinyinPrefixInjectedIndex -= 1
          }
        }
      }

      if hasMiddleDigit, prefixPending.isEmpty {
        let numericTexts = NumericCandidateGenerator.candidateTexts(for: middleDigitLiteral)
        for text in numericTexts {
          appendCandidate(text: text, index: injectedIndex, subtitle: nil)
          injectedIndex -= 1
        }
      }

      if hasPinyinPrefixCandidates, hasMiddleDigit, !deferPrefixCandidates, mixedInputPrefixCandidates.count > 4 {
        for candidate in mixedInputPrefixCandidates.dropFirst(4) {
          appendCandidate(text: candidate.text, index: pinyinPrefixInjectedIndex, subtitle: candidate.subtitle)
          pinyinPrefixInjectedIndex -= 1
        }
      }
      if hasPinyinPrefixCandidates, deferPrefixCandidates {
        for candidate in mixedInputPrefixCandidates {
          appendCandidate(text: candidate.text, index: pinyinPrefixInjectedIndex, subtitle: candidate.subtitle)
          pinyinPrefixInjectedIndex -= 1
        }
      }

      if prioritizeDigitPrefix {
        appendDigitPrefixCandidates(includeCombo: false)
      }

      if appendCount > 0, !suppressSuffixCandidates {
        for index in 0..<appendCount {
          let candidate = limited[index]
          let text = effectiveSuffixMode
            ? candidate.text
            : rimeContext.mixedInputManager.composeCandidateForDisplay(
              candidate.text,
              includePrefixLiteral: includePrefixLiteral
            )
          appendCandidate(text: text, index: candidate.index, subtitle: candidate.subtitle)
        }
      }

      if hasDigitPrefix && !prioritizeDigitPrefix {
        appendDigitPrefixCandidates(includeCombo: true)
      }

      let shouldFilterBySyllables = syllablesBeforeMiddleDigit > 0 && !effectiveSuffixMode
      if !suppressSuffixCandidates {
        for candidate in limited {
          if shouldFilterBySyllables, candidate.text.count > syllablesBeforeMiddleDigit {
            continue
          }
          let text = effectiveSuffixMode
            ? candidate.text
            : (includePrefixLiteral
              ? rimeContext.mixedInputManager.composeCandidateForDisplay(candidate.text, includePrefixLiteral: true)
              : candidate.text)
          appendCandidate(text: text, index: candidate.index, subtitle: candidate.subtitle)
        }
      }

      if shouldInjectPrefixCandidates {
        let prefixTexts = NumericCandidateGenerator.candidateTexts(for: prefixCandidateSeed)
        for text in prefixTexts {
          appendCandidate(text: text, index: prefixInjectedIndex, subtitle: nil)
          prefixInjectedIndex -= 1
        }
      }

      let filteredMergedTexts: [(text: String, index: Int, subtitle: String?)]
      if suppressSuffixCandidates {
        filteredMergedTexts = mergedTexts.filter { $0.index < 0 }
      } else {
        filteredMergedTexts = mergedTexts
      }

      composedCandidates = filteredMergedTexts.enumerated().map { index, item in
        CandidateSuggestion(
          index: item.index,
          label: "\(index + 1)",
          text: item.text,
          title: item.text,
          isAutocomplete: index == 0,
          subtitle: item.subtitle
        )
      }
    } else {
      // 使用混合输入管理器组合候选词
      let composed = rimeContext.mixedInputManager.composeCandidates(
        rimeCandidates: baseCandidates.map { $0.text }
      )
      composedCandidates = composed.enumerated().map { index, text in
        let baseIndex = index < baseCandidates.count ? baseCandidates[index].index : index
        let subtitle = index < baseCandidates.count ? baseCandidates[index].subtitle : nil
        return CandidateSuggestion(
          index: baseIndex,
          label: "\(index + 1)",
          text: text,
          title: text,
          isAutocomplete: index == 0,
          subtitle: subtitle
        )
      }
    }

    // 更新 suggestions
    Task { @MainActor in
      if !composedCandidates.isEmpty {
        self.rimeContext.suggestions = composedCandidates
      }
    }
  }

  private func mixedInputEffectiveAppendDigitCandidateCount() -> Int {
    let digitPrefix = rimeContext.mixedInputManager.digitLiteralBeforeFirstPinyin
    return digitPrefix.isEmpty ? mixedInputAppendDigitCandidateCount : 1
  }

  private func resetMixedInputPrefixCache() {
    mixedInputSelectedPinyinPrefix = nil
    mixedInputPrefixCandidates.removeAll()
    mixedInputPrefixPinyinLetterCount = 0
    mixedInputSuffixMode = false
  }

  private func resetMixedInputFreezeState() {
    resetMixedInputPrefixCache()
  }

  private func mixedInputPinyinLetterCount(_ text: String) -> Int {
    var count = 0
    for scalar in text.unicodeScalars {
      if scalar == "ü" || scalar == "Ü" {
        count += 1
        continue
      }
      if scalar.isASCII, CharacterSet.letters.contains(scalar) {
        count += 1
      }
    }
    return count
  }

  private func snapshotMixedInputPrefixCandidates(limit: Int = 10) -> [(text: String, subtitle: String?)] {
    var results: [(text: String, subtitle: String?)] = []
    var candidates: [CandidateSuggestion] = []
    let hasRimePreedit = !(rimeContext.rimeContext?.composition?.preedit?.isEmpty ?? true)
    let rimeComposing = rimeContext.isComposing && hasRimePreedit
    if rimeComposing, let menu = rimeContext.rimeContext?.menu {
      let highlightIndex = Int(menu.pageSize * menu.pageNo + menu.highlightedCandidateIndex)
      candidates = rimeContext.candidateListLimit(
        index: rimeContext.candidateIndex,
        highlightIndex: highlightIndex,
        count: rimeContext.maximumNumberOfCandidateWords
      )
    } else if rimeComposing {
      candidates = rimeContext.candidateListLimit(
        index: rimeContext.candidateIndex,
        highlightIndex: 0,
        count: rimeContext.maximumNumberOfCandidateWords
      )
      if candidates.isEmpty {
        candidates = rimeContext.suggestions
      }
    } else {
      candidates = rimeContext.suggestions
    }
    for candidate in candidates {
      results.append((text: candidate.text, subtitle: candidate.subtitle))
      if results.count >= limit { break }
    }
    return results
  }

  private func mixedInputCandidateContainsLetters(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
      if scalar == "ü" || scalar == "Ü" { return true }
      if scalar.isASCII, CharacterSet.letters.contains(scalar) { return true }
      if (0xFF21...0xFF3A).contains(scalar.value) || (0xFF41...0xFF5A).contains(scalar.value) {
        return true
      }
    }
    return false
  }

  private func isDecimalDigit(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
  }

  private func isNumericSeparator(_ character: Character) -> Bool {
    character == "," || character == "." || character == "，" || character == "．"
  }

  private func isPunctuationOrSymbol(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
    if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
      return false
    }
    return CharacterSet.punctuationCharacters.contains(scalar)
      || CharacterSet.symbols.contains(scalar)
  }

  private func isNumericLiteralText(_ text: String) -> Bool {
    var sawDigit = false
    var inSuffix = false
    for char in text {
      if !inSuffix {
        if char.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
          sawDigit = true
          continue
        }
        if char.isNumber {
          sawDigit = true
          continue
        }
        if isNumericSeparator(char) {
          continue
        }
        if isPunctuationOrSymbol(char) {
          if !sawDigit { return false }
          inSuffix = true
          continue
        }
        return false
      } else {
        if isPunctuationOrSymbol(char) { continue }
        return false
      }
    }
    return sawDigit
  }

  private func isNumericCoreLiteralText(_ text: String) -> Bool {
    var sawDigit = false
    for char in text {
      if char.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) || char.isNumber {
        sawDigit = true
        continue
      }
      if isNumericSeparator(char) {
        continue
      }
      return false
    }
    return sawDigit
  }

  private func isSymbolLiteralText(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    for scalar in text.unicodeScalars {
      if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
      if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
        return false
      }
    }
    return true
  }

  private func splitNumericSuffix(_ literal: String) -> (digits: String, suffix: String)? {
    var digits = ""
    var suffix = ""
    var sawDigit = false
    var inSuffix = false
    for char in literal {
      if !inSuffix {
        if let value = char.wholeNumberValue, (0...9).contains(value) {
          digits.append(String(value))
          sawDigit = true
          continue
        }
        if isNumericSeparator(char) {
          digits.append(char)
          continue
        }
        if isPunctuationOrSymbol(char) {
          if !sawDigit { return nil }
          inSuffix = true
          suffix.append(char)
          continue
        }
        return nil
      } else {
        if isPunctuationOrSymbol(char) {
          suffix.append(char)
          continue
        }
        return nil
      }
    }
    return sawDigit ? (digits: digits, suffix: suffix) : nil
  }

  private func splitNumericLiteralWithNonASCIISuffix(_ literal: String) -> (digits: String, suffix: String)? {
    var digits = ""
    var suffix = ""
    var sawDigit = false
    var inSuffix = false
    for char in literal {
      if !inSuffix {
        if let value = char.wholeNumberValue, (0...9).contains(value) {
          digits.append(String(value))
          sawDigit = true
          continue
        }
        if isNumericSeparator(char) {
          digits.append(char)
          continue
        }
        inSuffix = true
      }

      guard let scalar = char.unicodeScalars.first else { return nil }
      if CharacterSet.whitespacesAndNewlines.contains(scalar) { return nil }
      // 只接受非 ASCII 后缀（如“个/位/天”），避免把英文输入误判为数字后缀。
      if scalar.isASCII { return nil }
      suffix.append(char)
    }
    return sawDigit && !suffix.isEmpty ? (digits: digits, suffix: suffix) : nil
  }

  private func splitNumericPrefixCandidate(
    candidate: String,
    prefixLiteral: String
  ) -> (digits: String, suffix: String)? {
    let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPrefix = prefixLiteral.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedCandidate.isEmpty, !trimmedPrefix.isEmpty else { return nil }

    if let split = splitNumericLiteralWithNonASCIISuffix(trimmedCandidate) {
      return split
    }

    let normalizedCandidate = trimmedCandidate.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trimmedCandidate
    let normalizedPrefix = trimmedPrefix.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trimmedPrefix
    guard normalizedCandidate.hasPrefix(normalizedPrefix) else { return nil }

    var suffix = String(trimmedCandidate.dropFirst(min(trimmedPrefix.count, trimmedCandidate.count)))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if suffix.isEmpty {
      var digits = ""
      var suffixChars = ""
      var sawDigit = false
      var inSuffix = false
      for char in trimmedCandidate {
        if !inSuffix {
          if let value = char.wholeNumberValue, (0...9).contains(value) {
            digits.append(String(value))
            sawDigit = true
            continue
          }
          if isNumericSeparator(char) {
            digits.append(char)
            continue
          }
          if CharacterSet.whitespacesAndNewlines.contains(char.unicodeScalars.first ?? " ") {
            continue
          }
          inSuffix = true
        }
        suffixChars.append(char)
      }
      suffix = suffixChars.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedDigits = digits.isEmpty ? trimmedPrefix : digits
      guard sawDigit, !suffix.isEmpty, !mixedInputCandidateContainsLetters(suffix) else { return nil }
      return (digits: resolvedDigits, suffix: suffix)
    }

    guard !mixedInputCandidateContainsLetters(suffix) else { return nil }
    return (digits: trimmedPrefix, suffix: suffix)
  }

  private func prefixLengthForDigits(in text: String, digitCount: Int) -> Int? {
    guard digitCount > 0 else { return nil }
    var remaining = digitCount
    var length = 0
    for char in text {
      if char.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) || char.isNumber {
        remaining -= 1
      } else if isNumericSeparator(char) {
        // do not decrement
      } else {
        break
      }
      length += 1
      if remaining <= 0 { return length }
    }
    return nil
  }

  private func symbolCandidates(for literal: String) -> [String] {
    return SymbolCandidateGenerator.candidateTexts(for: literal)
  }

  private func normalizedAsciiDigits(from text: String) -> String? {
    guard !text.isEmpty else { return nil }
    var result = ""
    for char in text {
      if char.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
         let value = char.wholeNumberValue,
         (0...9).contains(value)
      {
        result.append(String(value))
        continue
      }
      if isNumericSeparator(char) {
        continue
      }
      return nil
    }
    return result.isEmpty ? nil : result
  }

  private func numericCandidates(for literal: String) -> Set<String> {
    guard !literal.isEmpty else { return [] }
    let seed = normalizedAsciiDigits(from: literal) ?? literal
    return Set(NumericCandidateGenerator.candidateTexts(for: seed))
  }

  private func mixedInputTrailingDigitLiteralAfterLastPinyin() -> String {
    let segments = rimeContext.mixedInputManager.segments
    guard let lastPinyinIndex = segments.lastIndex(where: { $0.isPinyin }) else { return "" }
    guard lastPinyinIndex < segments.count - 1 else { return "" }
    var digits = ""
    for index in (lastPinyinIndex + 1)..<segments.count {
      let segment = segments[index]
      guard segment.isLiteral else { return "" }
      let commit = segment.commitText
      guard !commit.isEmpty, isNumericLiteralText(commit) else { return "" }
      digits += commit
    }
    return digits
  }

  private func mixedInputTrailingSymbolLiteralAfterLastPinyin() -> String {
    let segments = rimeContext.mixedInputManager.segments
    guard let lastPinyinIndex = segments.lastIndex(where: { $0.isPinyin }) else { return "" }
    guard lastPinyinIndex < segments.count - 1 else { return "" }
    var symbols = ""
    for index in (lastPinyinIndex + 1)..<segments.count {
      let segment = segments[index]
      guard segment.isLiteral else { return "" }
      let commit = segment.commitText
      guard !commit.isEmpty, isSymbolLiteralText(commit) else { return "" }
      symbols += commit
    }
    return symbols
  }

  private func mixedInputTrailingDigitSegmentCount() -> Int {
    let segments = rimeContext.mixedInputManager.segments
    var count = 0
    for segment in segments.reversed() {
      guard segment.isLiteral else { break }
      let commit = segment.commitText
      if !commit.isEmpty, isNumericLiteralText(commit) {
        count += 1
      } else {
        break
      }
    }
    return count
  }

  private func mixedInputTrailingSymbolSegmentCount() -> Int {
    let segments = rimeContext.mixedInputManager.segments
    var count = 0
    for segment in segments.reversed() {
      guard segment.isLiteral else { break }
      let commit = segment.commitText
      if !commit.isEmpty, isSymbolLiteralText(commit) {
        count += 1
      } else {
        break
      }
    }
    return count
  }

  private func mixedInputConfiguredPrefixText() -> String {
    let prefixCount = rimeContext.mixedInputManager.literalPrefixSegmentCount
    guard prefixCount > 0 else { return "" }
    var result = ""
    var taken = 0
    for segment in rimeContext.mixedInputManager.segments {
      guard segment.isLiteral else { break }
      result += segment.commitText
      taken += 1
      if taken >= prefixCount { break }
    }
    return result
  }

  private func mixedInputLeadingNonDigitLiteralSegmentCount() -> Int {
    var count = 0
    for segment in rimeContext.mixedInputManager.segments {
      guard segment.isLiteral else { break }
      let commit = segment.commitText
      if !commit.isEmpty, isNumericLiteralText(commit) {
        break
      }
      count += 1
    }
    return count
  }

  private func mixedInputLeadingLiteralSegmentCountBeforeSelectableLiteral() -> Int {
    // 选择了前缀候选（如“个”）后，前导 literal（例如“3”“个”）都应被视为固定前缀，
    // 后续候选不应再次拼回这些前缀，避免出现“3个的/个小的”重复显示。
    return rimeContext.mixedInputManager.leadingLiteralSegmentCount
  }

  private func syncRimeInputWithMixedPinyinIfNeeded() {
    rimeContext.resetCompositionKeepingMixedInput()
    rimeContext.selectCandidatePinyin = nil
    let hasMiddleDigit = !rimeContext.mixedInputManager.digitLiteralAfterFirstPinyin.isEmpty
    let prefixPending = rimeContext.mixedInputManager.pinyinOnlyBeforeFirstDigitLiteral
    let hasSuffixPinyin = !rimeContext.mixedInputManager.pinyinOnlyAfterFirstLiteral.isEmpty
    let prefixChosen = mixedInputSelectedPinyinPrefix != nil
    let effectiveSuffixMode = (mixedInputSuffixMode || hasMiddleDigit) && (prefixPending.isEmpty || !prefixChosen)
    let pinyinSource: String
    if hasMiddleDigit, hasSuffixPinyin, !prefixChosen {
      pinyinSource = rimeContext.mixedInputManager.pinyinOnlyAfterFirstLiteral
    } else if !prefixPending.isEmpty {
      pinyinSource = prefixPending
    } else if effectiveSuffixMode {
      pinyinSource = rimeContext.mixedInputManager.pinyinOnlyAfterFirstLiteral
    } else {
      pinyinSource = rimeContext.mixedInputManager.pinyinOnly
    }
    let mixedPinyin = pinyinSource.replacingOccurrences(of: " ", with: "")
    guard !mixedPinyin.isEmpty else { return }
    for char in mixedPinyin {
      _ = rimeContext.tryHandleInputText(String(char))
    }
  }

  private func mixedInputCandidateIsDigitsOnly(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return isNumericCoreLiteralText(text)
  }

  func handleMixedInputDigitCandidateIfNeeded(_ text: String, candidateIndex _: Int? = nil) -> Bool {
    if isAzooKeyActive { return false }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    let prefixLiteral = rimeContext.mixedInputManager.literalPrefixText
    if !prefixLiteral.isEmpty, isNumericLiteralText(prefixLiteral) {
      let prefixCandidates = numericCandidates(for: prefixLiteral)
      let normalizedTrimmed = trimmed.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trimmed
      let normalizedPrefixLiteral = prefixLiteral.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? prefixLiteral
      let looksLikeCombinedPrefixCandidate = normalizedTrimmed.hasPrefix(normalizedPrefixLiteral)
        && !mixedInputCandidateContainsLetters(trimmed)
      if prefixCandidates.contains(trimmed) || looksLikeCombinedPrefixCandidate {
        if let split = splitNumericPrefixCandidate(candidate: trimmed, prefixLiteral: prefixLiteral),
           rimeContext.mixedInputManager.replaceLeadingLiteral(with: split.digits)
        {
          let committedCount = mixedInputCommittedPinyinCountBySyllables(targetSyllables: split.suffix.count)
          if committedCount > 0, !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
            rimeContext.mixedInputManager.commitLeadingPinyinAsLiteral(
              committedCount: committedCount,
              commitText: split.suffix
            )
          } else {
            rimeContext.mixedInputManager.insertLiteralSegment(
              split.suffix,
              at: 1,
              mergeWithPreviousNonDigit: false
            )
          }
          mixedInputSelectedNumericPrefix = split.digits
          syncRimeInputWithMixedPinyinIfNeeded()
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
          rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
          rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
          updateMixedInputSuggestions()
          return true
        }
        if rimeContext.mixedInputManager.replaceLeadingLiteral(with: trimmed) {
          mixedInputSelectedNumericPrefix = trimmed
          syncRimeInputWithMixedPinyinIfNeeded()
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
          rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
          rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
          updateMixedInputSuggestions()
          return true
        }
      }
    }

    let middleDigit = rimeContext.mixedInputManager.digitLiteralAfterFirstPinyin
    if !middleDigit.isEmpty {
      let middleCandidates = numericCandidates(for: middleDigit)
      if middleCandidates.contains(trimmed),
         rimeContext.mixedInputManager.replaceDigitLiteralAfterFirstPinyin(with: trimmed)
      {
        syncRimeInputWithMixedPinyinIfNeeded()
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return true
      }
    }

    if rimeContext.mixedInputManager.hasLiteral {
      let rawInputKeys = rimeContext.getInputKeys()
      let prefixLiteral = rimeContext.mixedInputManager.segments.first?.isLiteral == true
        ? rimeContext.mixedInputManager.segments.first?.text ?? ""
        : ""
      let literalSuffix = rimeContext.mixedInputManager.literalOnlyExcludingPrefix
      let displayText = rimeContext.mixedInputManager.displayText
      if !rawInputKeys.isEmpty {
        rimeContext.prepareMixedInputRevertSelection(
          rawInputKeys: rawInputKeys,
          prefixLiteral: prefixLiteral,
          literalSuffix: literalSuffix,
          displayText: displayText
        )
      }
    }

    let digitLiteral = rimeContext.mixedInputManager.digitLiteralBeforeFirstPinyin
    if !digitLiteral.isEmpty {
      let digitCandidates = numericCandidates(for: digitLiteral)
      if digitCandidates.contains(trimmed),
         rimeContext.mixedInputManager.upsertDigitLiteralBeforeFirstPinyin(with: trimmed)
      {
        syncRimeInputWithMixedPinyinIfNeeded()
        if !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
        }
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return true
      }
    }

    if handleMixedInputLiteralOnlyCandidate(trimmed) {
      return true
    }

    guard mixedInputCandidateIsDigitsOnly(trimmed) else { return false }

    let display = rimeContext.mixedInputManager.hasLiteral
      ? rimeContext.mixedInputManager.displayText
      : (!rimeContext.mixedInputLastDisplayText.isEmpty ? rimeContext.mixedInputLastDisplayText : rimeContext.userInputKey)
    let displayHasLetters = display.unicodeScalars.contains {
      ($0.isASCII && CharacterSet.letters.contains($0)) || $0 == "ü" || $0 == "Ü"
    }
    let displayHasSymbols = display.unicodeScalars.contains {
      if CharacterSet.whitespacesAndNewlines.contains($0) { return false }
      if CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) { return false }
      return CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
    }

    if !rimeContext.mixedInputManager.hasLiteral
        || (displayHasLetters && !rimeContext.mixedInputManager.segments.contains(where: { $0.isPinyin }))
    {
      if display.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
          || (displayHasSymbols && isNumericCandidateModeEnabledOnChineseKeyboard)
      {
        mixedInputDebugLog(
          "DBG_MIXEDINPUT rebuildSegments display=\(display) hasSymbols=\(displayHasSymbols)"
        )
        rimeContext.mixedInputManager.rebuildSegments(from: display)
        rimeContext.mixedInputManager.literalPrefixSegmentCount =
          rimeContext.mixedInputManager.segments.first?.isLiteral == true ? 1 : 0
        rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
        mixedInputDebugLog(
          "DBG_MIXEDINPUT rebuildSegments done segments=\(self.mixedInputDebugSegmentsString())"
        )
      }
    }

    let hasPinyinSegment = rimeContext.mixedInputManager.segments.contains { $0.isPinyin }
    guard hasPinyinSegment else { return false }

    if rimeContext.mixedInputManager.upsertDigitLiteralBeforeFirstPinyin(with: trimmed) {
      if !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
        rimeContext.mixedInputManager.literalPrefixSegmentCount =
          rimeContext.mixedInputManager.leadingLiteralSegmentCount
      }
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
      updateMixedInputSuggestions()
      return true
    }
    return display.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
  }

  private func handleMixedInputLiteralOnlyCandidate(_ candidate: String) -> Bool {
    guard rimeContext.mixedInputManager.hasLiteral,
          rimeContext.mixedInputManager.pinyinOnly.isEmpty
    else { return false }
    guard !candidate.isEmpty else { return false }

    let prefixCount = rimeContext.mixedInputManager.literalPrefixSegmentCount
    let segments = rimeContext.mixedInputManager.segments
    guard prefixCount < segments.count else { return false }
    guard segments[prefixCount].isLiteral else { return false }

    let suffixLiteral = rimeContext.mixedInputManager.literalOnlyExcludingPrefix
    guard !suffixLiteral.isEmpty else { return false }

    if let split = splitNumericSuffix(suffixLiteral) {
      let digits = split.digits
      if !digits.isEmpty {
        if candidate.allSatisfy({ $0.isNumber }),
           let candidateDigits = normalizedAsciiDigits(from: candidate),
           !candidateDigits.isEmpty,
           digits.hasPrefix(candidateDigits)
        {
          let shouldSplit = candidateDigits.count < digits.count || !split.suffix.isEmpty
          if shouldSplit,
             let prefixLength = prefixLengthForDigits(in: segments[prefixCount].commitText, digitCount: candidateDigits.count),
             rimeContext.mixedInputManager.splitLiteralSegment(
               at: prefixCount,
               prefixLength: prefixLength,
               replacementPrefix: candidate
             )
          {
            rimeContext.mixedInputManager.literalPrefixSegmentCount = prefixCount + 1
            rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
            rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
            updateMixedInputSuggestions()
            return true
          }
        }

        let digitVariants = numericCandidates(for: digits)
        if digitVariants.contains(candidate),
           let prefixLength = prefixLengthForDigits(in: segments[prefixCount].commitText, digitCount: digits.count),
           rimeContext.mixedInputManager.splitLiteralSegment(
             at: prefixCount,
             prefixLength: prefixLength,
             replacementPrefix: candidate
           )
        {
          rimeContext.mixedInputManager.literalPrefixSegmentCount = prefixCount + 1
          rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
          rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
          updateMixedInputSuggestions()
          return true
        }
      }
    }

    if prefixCount + 1 < segments.count {
      let targetLiteral = segments[prefixCount].commitText
      let isNumericMatch = isNumericLiteralText(targetLiteral)
        && numericCandidates(for: targetLiteral).contains(candidate)
      let isSymbolMatch = isSymbolLiteralText(targetLiteral)
        && symbolCandidates(for: targetLiteral).contains(candidate)
      if isNumericMatch || isSymbolMatch {
        _ = rimeContext.mixedInputManager.replaceLiteralSegment(at: prefixCount, with: candidate)
        rimeContext.mixedInputManager.literalPrefixSegmentCount = prefixCount + 1
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return true
      }
    }

    return false
  }

  private func commitCurrentRimeCandidateForLiteralSeparatorIfNeeded() {
    guard rimeContext.mixedInputManager.lastSegmentIsPinyin else { return }
    let commit = rimeContext.suggestions.first?.text
      ?? rimeContext.rimeContext?.commitTextPreview
      ?? rimeContext.userInputKey
    if !commit.isEmpty {
      rimeContext.mixedInputManager.commitLastPinyinAsLiteral(commit)
      rimeContext.resetCompositionKeepingMixedInput()
    }
  }

  func selectAzooKeyCandidate(index: Int) {
    guard isAzooKeyInputActive else { return }
    let leftContext = azooKeyLeftSideContext()
    let candidateText = azooKeyEngine.candidate(at: index).map { Candidate.parseTemplate($0.text) } ?? ""
    let rawInputText = azooKeyEngine.currentRawInputText
    let leadingNumericCount = azooKeyLeadingNumericCount(in: rawInputText)
    let hasTrailingInput = leadingNumericCount > 0 && leadingNumericCount < rawInputText.count
    let composingOverride: ComposingCount? =
      (hasTrailingInput && azooKeyCandidateIsNumericOnly(candidateText))
        ? .inputCount(leadingNumericCount)
        : nil
    if let result = azooKeyEngine.commitCandidatePartially(
      at: index,
      leftSideContext: leftContext,
      composingCountOverride: composingOverride
    ) {
      if !result.commitText.isEmpty {
        if isUnifiedCompositionBufferEnabled {
          appendToCompositionPrefix(result.commitText)
        } else {
          textDocumentProxy.insertText(result.commitText)
        }
      }
      if result.isComposing {
        updateAzooKeySuggestions(result.suggestions)
      } else {
        clearAzooKeyState()
      }
    }
  }

  func selectEnglishCandidate(index: Int) {
    guard isEnglishInputActive else { return }
    if let commit = englishEngine.commitCandidate(at: index) {
      if isUnifiedCompositionBufferEnabled {
        appendToCompositionPrefix(commit)
      } else {
        textDocumentProxy.insertText(commit)
      }
    }
    clearEnglishState()
  }

  /// 提交英语原始输入文本（用于回车键）
  func commitEnglishRawText() {
    guard isEnglishInputActive, englishEngine.isComposing else { return }
    if let text = englishEngine.commitRawText() {
      if isUnifiedCompositionBufferEnabled {
        appendToCompositionPrefix(text)
      } else {
        textDocumentProxy.insertText(text)
      }
    }
    clearEnglishState()
  }

  func commitMixedInputCandidateDirectly(_ text: String) {
    guard !text.isEmpty else { return }
    if handleMixedInputDigitCandidateIfNeeded(text) {
      return
    }
    var prefix = rimeContext.mixedInputManager.literalPrefixText
    if prefix.isEmpty,
       rimeContext.mixedInputManager.pinyinOnly.isEmpty,
       rimeContext.mixedInputManager.literalPrefixSegmentCount > 0
    {
      prefix = mixedInputConfiguredPrefixText()
    }
    let normalizedText = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
    let commit: String
    if !prefix.isEmpty, normalizedText.hasPrefix(prefix) {
      commit = text
    } else {
      commit = prefix.isEmpty ? text : prefix + text
    }
    commitMixedInputText(commit)
  }

  private func commitMixedInputText(_ text: String) {
    guard !text.isEmpty else { return }
    if isUnifiedCompositionBufferEnabled {
      appendToCompositionPrefix(text)
    } else {
      textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
      insertTextPatch(text)
    }
    rimeContext.reset()
    mixedInputSelectedNumericPrefix = nil
    resetMixedInputFreezeState()
    Task { @MainActor in
      self.rimeContext.textReplacementSuggestions = []
    }
  }

  private func mixedInputCommittedPinyinCount(from comment: String?) -> Int {
    guard let comment, !comment.isEmpty else { return 0 }
    let normalized = comment.applyingTransform(.stripDiacritics, reverse: false) ?? comment
    var count = 0
    for scalar in normalized.unicodeScalars {
      if scalar == "ü" || scalar == "Ü" {
        count += 1
        continue
      }
      if scalar.isASCII && CharacterSet.letters.contains(scalar) {
        count += 1
      }
    }
    return count
  }

  private func mixedInputLetterCount(_ text: String) -> Int {
    var count = 0
    for scalar in text.unicodeScalars {
      if scalar == "ü" || scalar == "Ü" {
        count += 1
        continue
      }
      if scalar.isASCII && CharacterSet.letters.contains(scalar) {
        count += 1
      }
    }
    return count
  }

  private func mixedInputPinyinPrefixLength(_ text: String, syllableCount: Int) -> Int {
    guard syllableCount > 0 else { return 0 }
    let vowels = Set("aeiouüAEIOUÜ")
    let initials = Set([
      "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
      "j", "q", "x", "r", "z", "c", "s", "y", "w", "zh", "ch", "sh"
    ])
    let chars = Array(text)
    var consumed = 0
    var syllables = 0
    var prevWasVowel = false
    var reachedTarget = false
    var index = 0

    while index < chars.count {
      let char = chars[index]
      if char == " " || char == "'" {
        if reachedTarget { break }
        consumed += 1
        prevWasVowel = false
        index += 1
        continue
      }

      let isVowel = vowels.contains(char)
      if reachedTarget {
        if isVowel {
          consumed += 1
          prevWasVowel = true
          index += 1
          continue
        }

        // 已到目标音节后，避免吃掉下一音节声母（如 gexiaode 中的 x / d）
        var clusterEnd = index
        while clusterEnd < chars.count {
          let c = chars[clusterEnd]
          if c == " " || c == "'" || vowels.contains(c) { break }
          clusterEnd += 1
        }
        let hasFutureVowel = clusterEnd < chars.count && vowels.contains(chars[clusterEnd])
        if !hasFutureVowel {
          consumed += (chars.count - index)
          break
        }

        let cluster = String(chars[index..<clusterEnd]).lowercased()
        var codaLength = 0
        if cluster.hasPrefix("ng") {
          codaLength = 2
        } else if cluster.hasPrefix("n") || cluster.hasPrefix("r") {
          codaLength = 1
        }
        // 如果整个 cluster 更像合法声母（含 zh/ch/sh），则不吞并到上一音节
        if initials.contains(cluster) {
          codaLength = 0
        }

        consumed += min(codaLength, max(0, clusterEnd - index))
        break
      }

      consumed += 1
      if isVowel && !prevWasVowel {
        syllables += 1
        if syllables >= syllableCount {
          reachedTarget = true
        }
      }
      prevWasVowel = isVowel
      index += 1
    }

    return consumed
  }

  private func mixedInputCommittedPinyinCountFromPreedit(
    preedit: String,
    targetSyllables: Int
  ) -> Int {
    guard targetSyllables > 0, !preedit.isEmpty else { return 0 }
    let tokens = preedit.split { $0 == " " || $0 == "'" }
    guard !tokens.isEmpty else { return 0 }
    let consumeSyllables = min(targetSyllables, tokens.count)
    let total = tokens.prefix(consumeSyllables).reduce(0) {
      $0 + mixedInputLetterCount(String($1))
    }
    return total
  }

  private func mixedInputCommittedPinyinCountBySyllables(targetSyllables: Int) -> Int {
    guard targetSyllables > 0 else { return 0 }
    let preeditCount = mixedInputCommittedPinyinCountFromPreedit(
      preedit: currentRimePreeditText(),
      targetSyllables: targetSyllables
    )
    if preeditCount > 0 {
      return preeditCount
    }
    var remaining = targetSyllables
    var total = 0
    func countLetters(_ text: Substring) -> Int {
      var count = 0
      for scalar in text.unicodeScalars {
        if scalar == "ü" || scalar == "Ü" {
          count += 1
          continue
        }
        if scalar.isASCII && CharacterSet.letters.contains(scalar) {
          count += 1
        }
      }
      return count
    }
    for segment in rimeContext.mixedInputManager.segments {
      guard segment.isPinyin else { continue }
      let text = segment.text
      guard !text.isEmpty else { continue }
      if text.contains(" ") || text.contains("'") {
        let tokens = text.split { $0 == " " || $0 == "'" }
        for token in tokens {
          if remaining <= 0 { break }
          total += countLetters(token)
          remaining -= 1
        }
        if remaining == 0 { break }
        continue
      }
      let syllables = rimeContext.mixedInputManager.countSyllables(text)
      if remaining >= syllables {
        total += text.count
        remaining -= syllables
        if remaining == 0 { break }
      } else {
        total += mixedInputPinyinPrefixLength(text, syllableCount: remaining)
        remaining = 0
        break
      }
    }
    return total
  }

  private func azooKeyLeadingNumericCount(in text: String) -> Int {
    var count = 0
    for char in text {
      if char.isNumber {
        count += 1
      } else {
        break
      }
    }
    return count
  }

  private func azooKeyCandidateIsNumericOnly(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return text.allSatisfy { $0.isNumber }
  }

  func commitMixedInputCandidateWithLiteralOption(
    rimeIndex: Int,
    displayIndex: Int,
    candidateText: String,
    candidateSubtitle: String?
  ) {
    let preedit = currentRimePreeditText()
    mixedInputDebugLog(
      "DBG_MIXEDINPUT commitCandidate start text=\(candidateText) rimeIndex=\(rimeIndex) displayIndex=\(displayIndex) preedit=\(preedit) segments=\(self.mixedInputDebugSegmentsString())"
    )
    if handleMixedInputDigitCandidateIfNeeded(candidateText, candidateIndex: rimeIndex) {
      mixedInputDebugLog("DBG_MIXEDINPUT commitCandidate handledByDigitCandidate")
      return
    }
    let prefixLiteral = rimeContext.mixedInputManager.literalPrefixText
    if !prefixLiteral.isEmpty, isNumericLiteralText(prefixLiteral) {
      let prefixCandidates = numericCandidates(for: prefixLiteral)
      if prefixCandidates.contains(candidateText),
         rimeContext.mixedInputManager.replaceLeadingLiteral(with: candidateText)
      {
        mixedInputSelectedNumericPrefix = candidateText
        if !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
        }
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return
      }
    }
    if rimeContext.mixedInputManager.hasLiteral {
      let rawInputKeys = rimeContext.getInputKeys()
      let prefixLiteral = rimeContext.mixedInputManager.segments.first?.isLiteral == true
        ? rimeContext.mixedInputManager.segments.first?.text ?? ""
        : ""
      let literalSuffix = rimeContext.mixedInputManager.literalOnlyExcludingPrefix
      let displayText = rimeContext.mixedInputManager.displayText
      if !rawInputKeys.isEmpty {
        rimeContext.prepareMixedInputRevertSelection(
          rawInputKeys: rawInputKeys,
          prefixLiteral: prefixLiteral,
          literalSuffix: literalSuffix,
          displayText: displayText
        )
      }
    }

    let hasMiddleDigitLiteral = !rimeContext.mixedInputManager.digitLiteralAfterFirstPinyin.isEmpty
    let hasSuffixPinyin = !rimeContext.mixedInputManager.pinyinOnlyAfterFirstLiteral.isEmpty
    let syllablesBeforeMiddleDigit = rimeContext.mixedInputManager.syllableCountBeforeMiddleDigit
    let digitsInCandidate = candidateText.filter { isDecimalDigit($0) }
    let nonDigitsInCandidate = candidateText.filter { !isDecimalDigit($0) }
    let isCombinedCandidate = rimeIndex <= mixedInputCombinedCandidateIndexBase
    let combinedTrailingSymbols = mixedInputTrailingSymbolLiteralAfterLastPinyin()
    let shouldSegmentCombinedCandidate = hasMiddleDigitLiteral
      && hasSuffixPinyin
      && !digitsInCandidate.isEmpty
      && !nonDigitsInCandidate.isEmpty
      && nonDigitsInCandidate.count <= syllablesBeforeMiddleDigit
    if isCombinedCandidate,
       !combinedTrailingSymbols.isEmpty
    {
      let normalizedCandidate = candidateText.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? candidateText
      let normalizedTrailing = combinedTrailingSymbols.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? combinedTrailingSymbols
      if !normalizedCandidate.hasSuffix(normalizedTrailing) {
        var prefixLiteral = rimeContext.mixedInputManager.literalPrefixText
        var commitText = candidateText
        if !prefixLiteral.isEmpty, commitText.hasPrefix(prefixLiteral) {
          commitText = String(commitText.dropFirst(prefixLiteral.count))
          commitText = commitText.trimmingCharacters(in: .whitespaces)
        }

        rimeContext.mixedInputManager.reset()
        var insertIndex = 0
        var prefixCount = 0
        if !prefixLiteral.isEmpty {
          rimeContext.mixedInputManager.insertLiteralSegment(prefixLiteral, at: insertIndex, mergeWithPreviousNonDigit: false)
          insertIndex += 1
          prefixCount += 1
        }
        if !commitText.isEmpty {
          rimeContext.mixedInputManager.insertLiteralSegment(commitText, at: insertIndex, mergeWithPreviousNonDigit: false)
          insertIndex += 1
          prefixCount += 1
        }
        rimeContext.mixedInputManager.insertLiteralSegment(combinedTrailingSymbols, at: insertIndex, mergeWithPreviousNonDigit: false)
        rimeContext.mixedInputManager.literalPrefixSegmentCount = prefixCount

        rimeContext.resetCompositionKeepingMixedInput()
        rimeContext.resetCommitText()
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return
      }
    }
    if isCombinedCandidate, !shouldSegmentCombinedCandidate {
      let normalizedCandidate = candidateText.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? candidateText
      let normalizedPrefixLiteral = prefixLiteral.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? prefixLiteral
      let canPromoteToLiteralPrefix = !normalizedPrefixLiteral.isEmpty
        && isNumericLiteralText(prefixLiteral)
        && normalizedCandidate.hasPrefix(normalizedPrefixLiteral)
        && !mixedInputCandidateContainsLetters(candidateText)
      if canPromoteToLiteralPrefix {
        // “3个”直接选中时，沿用“3”->“个”的增量更新路径，避免状态机分叉。
        if let split = splitNumericPrefixCandidate(candidate: candidateText, prefixLiteral: prefixLiteral),
           rimeContext.mixedInputManager.replaceLeadingLiteral(with: split.digits)
        {
          let committedCount = mixedInputCommittedPinyinCountBySyllables(targetSyllables: split.suffix.count)
          if committedCount > 0, !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
            rimeContext.mixedInputManager.commitLeadingPinyinAsLiteral(
              committedCount: committedCount,
              commitText: split.suffix
            )
          } else {
            let segments = rimeContext.mixedInputManager.segments
            let shouldInsertSuffix: Bool
            if segments.count > 1,
               case .literal(_, let commit) = segments[1].type,
               commit == split.suffix
            {
              shouldInsertSuffix = false
            } else {
              shouldInsertSuffix = true
            }
            if shouldInsertSuffix {
              rimeContext.mixedInputManager.insertLiteralSegment(
                split.suffix,
                at: 1,
                mergeWithPreviousNonDigit: false
              )
            }
          }
          mixedInputSelectedNumericPrefix = split.digits
          mixedInputSelectedPinyinPrefix = nil
          mixedInputPrefixCandidates.removeAll()
          mixedInputPrefixPinyinLetterCount = 0
          syncRimeInputWithMixedPinyinIfNeeded()
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
          rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
          rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
          updateMixedInputSuggestions()
          return
        }

        if rimeContext.mixedInputManager.replaceLeadingLiteral(with: candidateText) {
          mixedInputSelectedNumericPrefix = candidateText
          mixedInputSelectedPinyinPrefix = nil
          mixedInputPrefixCandidates.removeAll()
          mixedInputPrefixPinyinLetterCount = 0
          syncRimeInputWithMixedPinyinIfNeeded()
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
          rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
          rimeContext.mixedInputLastDisplayText = rimeContext.mixedInputManager.displayText
          updateMixedInputSuggestions()
          return
        }
      }
      commitMixedInputCandidateDirectly(candidateText)
      return
    }

    if !mixedInputPrefixCandidates.isEmpty,
       !isCombinedCandidate,
       rimeIndex <= mixedInputPinyinPrefixCandidateIndexBase
    {
      let commentCount = mixedInputCommittedPinyinCount(from: candidateSubtitle)
      let syllableCount = mixedInputCommittedPinyinCountBySyllables(targetSyllables: candidateText.count)
      var committedCount = syllableCount
      if committedCount == 0 {
        committedCount = min(commentCount, mixedInputPrefixPinyinLetterCount)
      }
      if committedCount == 0 { committedCount = mixedInputPrefixPinyinLetterCount }
      if committedCount > 0 {
        rimeContext.mixedInputManager.commitLeadingPinyinAsLiteral(
          committedCount: committedCount,
          commitText: candidateText
        )
        rimeContext.mixedInputManager.literalPrefixSegmentCount =
          mixedInputLeadingLiteralSegmentCountBeforeSelectableLiteral()
        mixedInputSelectedPinyinPrefix = candidateText
        mixedInputPrefixCandidates.removeAll()
        mixedInputPrefixPinyinLetterCount = 0
        syncRimeInputWithMixedPinyinIfNeeded()
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return
      }
    }

    if rimeIndex < 0, !isCombinedCandidate {
      if mixedInputCandidateContainsLetters(candidateText) {
        commitMixedInputCandidateDirectly(candidateText)
        return
      }
      if rimeContext.mixedInputManager.upsertDigitLiteralBeforeFirstPinyin(with: candidateText) {
        if !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
        }
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return
      }
    }

    if mixedInputCandidateIsDigitsOnly(candidateText), !isCombinedCandidate {
      if rimeContext.mixedInputManager.upsertDigitLiteralBeforeFirstPinyin(with: candidateText) {
        if !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
        }
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return
      }
    }

    var subtitle = candidateSubtitle
    if subtitle == nil,
       let menu = rimeContext.rimeContext?.menu,
       displayIndex >= 0,
       displayIndex < menu.candidates.count
    {
      subtitle = menu.candidates[displayIndex].comment
    }

    let prefixPendingBeforeDigit = rimeContext.mixedInputManager.pinyinOnlyBeforeFirstDigitLiteral
    if syllablesBeforeMiddleDigit > 0,
       !digitsInCandidate.isEmpty,
       !nonDigitsInCandidate.isEmpty,
       nonDigitsInCandidate.count <= syllablesBeforeMiddleDigit
    {
      let committedCount = mixedInputCommittedPinyinCountBySyllables(targetSyllables: syllablesBeforeMiddleDigit)
      if committedCount > 0 {
        rimeContext.mixedInputManager.trimLeadingPinyinLetters(committedCount)

        let insertIndex = min(
          rimeContext.mixedInputManager.literalPrefixSegmentCount,
          rimeContext.mixedInputManager.segments.count
        )
        rimeContext.mixedInputManager.insertLiteralSegment(String(nonDigitsInCandidate), at: insertIndex)

        if !rimeContext.mixedInputManager.replaceDigitLiteralAfterFirstPinyin(with: String(digitsInCandidate)) {
          _ = rimeContext.mixedInputManager.upsertDigitLiteralBeforeFirstPinyin(with: String(digitsInCandidate))
        }

        let residualPrefix = rimeContext.mixedInputManager.pinyinOnlyBeforeFirstDigitLiteral
        if !residualPrefix.isEmpty {
          let residualCount = mixedInputLetterCount(residualPrefix)
          if residualCount > 0 {
            rimeContext.mixedInputManager.trimLeadingPinyinLetters(residualCount)
          }
        }

        if !rimeContext.mixedInputManager.pinyinOnly.isEmpty {
          rimeContext.mixedInputManager.literalPrefixSegmentCount =
            rimeContext.mixedInputManager.leadingLiteralSegmentCount
        }

        mixedInputPrefixCandidates.removeAll()
        mixedInputPrefixPinyinLetterCount = 0

        syncRimeInputWithMixedPinyinIfNeeded()
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return
      }
    }

    var committedCount = mixedInputCommittedPinyinCount(from: subtitle)
    if committedCount == 0 {
      let fromPreedit = mixedInputCommittedPinyinCountFromPreedit(
        preedit: preedit,
        targetSyllables: candidateText.count
      )
      if fromPreedit > 0 {
        committedCount = fromPreedit
      }
    }
    if committedCount == 0 {
      let estimated = mixedInputCommittedPinyinCountBySyllables(targetSyllables: candidateText.count)
      if estimated > 0 {
        committedCount = estimated
      }
    }
    if committedCount == 0, !preedit.isEmpty {
      committedCount = mixedInputCommittedPinyinCountFromPreedit(
        preedit: preedit,
        targetSyllables: candidateText.count
      )
    }
    if committedCount == 0, !preedit.isEmpty {
      let fallback = mixedInputPinyinLetterCount(preedit)
      if fallback > 0 {
        committedCount = fallback
      }
    }
    let literalSuffix = rimeContext.mixedInputManager.literalOnlyExcludingPrefix
    if committedCount == 0,
       !literalSuffix.isEmpty,
       (isNumericLiteralText(literalSuffix) || isSymbolLiteralText(literalSuffix))
    {
      let fallback = mixedInputLetterCount(rimeContext.mixedInputManager.pinyinOnly)
      if fallback > 0 {
        committedCount = fallback
      }
    }

    mixedInputDebugLog(
      "DBG_MIXEDINPUT commitCandidate resolved committedCount=\(committedCount) literalSuffix=\(literalSuffix)"
    )

    if syllablesBeforeMiddleDigit > 0,
       mixedInputSelectedPinyinPrefix == nil,
       committedCount > 0,
       prefixPendingBeforeDigit.isEmpty,
       rimeContext.mixedInputManager.commitTrailingPinyinAsLiteralAfterMiddleDigit(
         committedCount: committedCount,
         commitText: candidateText
       )
    {
      rimeContext.resetCompositionKeepingMixedInput()
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      updateMixedInputSuggestions()
      return
    }

    let trailingDigits = mixedInputTrailingDigitLiteralAfterLastPinyin()
    if rimeIndex >= 0, !trailingDigits.isEmpty, committedCount > 0 {
      let normalizedCandidate = candidateText.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? candidateText
      let normalizedTrailing = normalizedAsciiDigits(from: trailingDigits) ?? trailingDigits
      if normalizedCandidate.hasSuffix(normalizedTrailing) {
        commitMixedInputCandidateDirectly(candidateText)
        return
      }
      rimeContext.mixedInputManager.commitLeadingPinyinAsLiteral(
        committedCount: committedCount,
        commitText: candidateText
      )
      let trailingDigitSegments = mixedInputTrailingDigitSegmentCount()
      if trailingDigitSegments > 0 {
        let prefixCount = max(0, rimeContext.mixedInputManager.segments.count - trailingDigitSegments)
        rimeContext.mixedInputManager.literalPrefixSegmentCount = prefixCount
      } else {
        rimeContext.mixedInputManager.literalPrefixSegmentCount =
          rimeContext.mixedInputManager.leadingLiteralSegmentCount
      }

      rimeContext.resetCompositionKeepingMixedInput()
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      updateMixedInputSuggestions()
      return
    }

    let trailingSymbols = mixedInputTrailingSymbolLiteralAfterLastPinyin()
    if committedCount == 0, !trailingSymbols.isEmpty {
      let fallback = mixedInputLetterCount(rimeContext.mixedInputManager.pinyinOnly)
      if fallback > 0 {
        committedCount = fallback
      }
    }
    if !trailingSymbols.isEmpty {
      mixedInputDebugLog(
        "DBG_MIXEDINPUT commitCandidate trailingSymbols=\(trailingSymbols) committedCount=\(committedCount)"
      )
    }
    if rimeIndex >= 0, !trailingSymbols.isEmpty, committedCount > 0 {
      let normalizedCandidate = candidateText.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? candidateText
      let normalizedTrailing = trailingSymbols.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trailingSymbols
      if normalizedCandidate.hasSuffix(normalizedTrailing) {
        commitMixedInputCandidateDirectly(candidateText)
        return
      }
      rimeContext.mixedInputManager.commitLeadingPinyinAsLiteral(
        committedCount: committedCount,
        commitText: candidateText
      )
      let trailingSymbolSegments = mixedInputTrailingSymbolSegmentCount()
      if trailingSymbolSegments > 0 {
        let prefixCount = max(0, rimeContext.mixedInputManager.segments.count - trailingSymbolSegments)
        rimeContext.mixedInputManager.literalPrefixSegmentCount = prefixCount
      } else {
        rimeContext.mixedInputManager.literalPrefixSegmentCount =
          rimeContext.mixedInputManager.leadingLiteralSegmentCount
      }

      rimeContext.resetCompositionKeepingMixedInput()
      rimeContext.resetCommitText()
      mixedInputDebugLog(
        "DBG_MIXEDINPUT commitCandidate keepTrailingSymbols display=\(self.rimeContext.mixedInputManager.displayText) segments=\(self.mixedInputDebugSegmentsString())"
      )
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      updateMixedInputSuggestions()
      return
    }

    let appendCount = mixedInputEffectiveAppendDigitCandidateCount()
    let hasMiddleDigit = !rimeContext.mixedInputManager.digitLiteralAfterFirstPinyin.isEmpty
    let prefixPending = rimeContext.mixedInputManager.pinyinOnlyBeforeFirstDigitLiteral
    let hasTrailingLiteral = (!literalSuffix.isEmpty && (isNumericLiteralText(literalSuffix) || isSymbolLiteralText(literalSuffix)))
      || !trailingDigits.isEmpty
      || !trailingSymbols.isEmpty
    let allowAppendLiteral = !(hasMiddleDigit && !prefixPending.isEmpty) && !hasTrailingLiteral
    if displayIndex < appendCount, allowAppendLiteral {
      rimeContext.mixedInputCommitBehavior = .appendLiteral
      rimeContext.selectCandidate(index: rimeIndex)
      return
    }
    if hasMiddleDigit, !prefixPending.isEmpty {
      let syllableCommit = mixedInputCommittedPinyinCountBySyllables(targetSyllables: candidateText.count)
      if syllableCommit > 0 {
        committedCount = syllableCommit
      }
    }
    if committedCount > 0 {
      // 直接选中“3个”这类带数字前缀的候选时，也需要标记前缀已确认，
      // 否则后续候选会继续重复拼回前缀，表现为“看起来没有变化”。
      let currentPrefixLiteral = rimeContext.mixedInputManager.literalPrefixText
      if !currentPrefixLiteral.isEmpty,
         isNumericLiteralText(currentPrefixLiteral),
         candidateText.hasPrefix(currentPrefixLiteral),
         !mixedInputCandidateContainsLetters(candidateText)
      {
        mixedInputSelectedNumericPrefix = currentPrefixLiteral
      }

      rimeContext.mixedInputManager.commitLeadingPinyinAsLiteral(
        committedCount: committedCount,
        commitText: candidateText
      )
      let hasMiddleDigit = !rimeContext.mixedInputManager.digitLiteralAfterFirstPinyin.isEmpty
      let pendingPrefix = rimeContext.mixedInputManager.pinyinOnlyBeforeFirstDigitLiteral
      if hasMiddleDigit {
        rimeContext.mixedInputManager.literalPrefixSegmentCount =
          mixedInputLeadingNonDigitLiteralSegmentCount()
        if !pendingPrefix.isEmpty {
          mixedInputSelectedPinyinPrefix = candidateText
          mixedInputPrefixCandidates.removeAll()
          mixedInputPrefixPinyinLetterCount = 0
        }
      } else {
        // 无中间数字时，前导 literal（如“3”“个”）都应固定为前缀，
        // 以免后续候选再次重复拼接这些前缀。
        rimeContext.mixedInputManager.literalPrefixSegmentCount =
          rimeContext.mixedInputManager.leadingLiteralSegmentCount
      }

      if rimeContext.mixedInputManager.pinyinOnly.isEmpty {
        let literalSuffix = rimeContext.mixedInputManager.literalOnlyExcludingPrefix
      if !literalSuffix.isEmpty,
         (isNumericLiteralText(literalSuffix) || isSymbolLiteralText(literalSuffix))
      {
        rimeContext.resetCompositionKeepingMixedInput()
        rimeContext.resetCommitText()
        rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        updateMixedInputSuggestions()
        return
      }
        let commitText = rimeContext.mixedInputManager.displayText.replacingOccurrences(of: " ", with: "")
        commitMixedInputText(commitText)
        return
      }

      syncRimeInputWithMixedPinyinIfNeeded()
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      updateMixedInputSuggestions()
      return
    }

    rimeContext.mixedInputCommitBehavior = .suppressLiteralAndKeep
    rimeContext.selectCandidate(index: rimeIndex)
  }

  open func selectNextKeyboard() {
    if isUnifiedCompositionBufferEnabled, hasActiveCompositionForBuffer() {
      commitCurrentCompositionToPrefixAndReset()
      flushCompositionPrefixIfNeeded()
    }
    // advanceToNextInputMode()
  }

  open func selectNextLocale() {
//    keyboardContext.selectNextLocale()
  }

  open func setKeyboardType(_ type: KeyboardType) {
    // TODO: 键盘切换
//    if !rimeContext.userInputKey.isEmpty, type.isCustom || type.isChinesePrimaryKeyboard || type.isChineseNineGrid || type.isAlphabetic {
//      textDocumentProxy.insertText(rimeContext.userInputKey)
//      rimeContext.reset()
//    }
    keyboardContext.setKeyboardType(type)
    if type.isAlphabetic {
      keyboardContext.isAutoCapitalizationEnabled = false
      keyboardContext.autocapitalizationTypeOverride = .none
    }
  }

  open func setKeyboardCase(_ casing: KeyboardCase) {
    if keyboardContext.keyboardType.isChinesePrimaryKeyboard {
      keyboardContext.setKeyboardType(.chinese(casing))
      return
    }

    if case .custom(let name, _) = keyboardContext.keyboardType {
      keyboardContext.setKeyboardType(.custom(named: name, case: casing))
      return
    }

    keyboardContext.setKeyboardType(.alphabetic(casing))
  }

  open func openUrl(_ url: URL?) {
    guard let url = url else {
      Logger.statistics.error("openUrl: URL is nil")
      return
    }

    Logger.statistics.info("openUrl: Attempting to open URL: \(url.absoluteString, privacy: .public)")

    // 键盘扩展中打开 URL 的方法：
    // 通过响应链向上查找 UIApplication 实例，调用新版 open 方法

    var responder: UIResponder? = self
    while let r = responder {
      // 检查类名是否为 UIApplication（避免直接引用 UIApplication.shared）
      let className = String(describing: type(of: r))
      if className == "UIApplication" {
        Logger.statistics.info("openUrl: Found UIApplication via responder chain")

        // 使用新版 open:options:completionHandler: 选择器
        // 方法签名: - (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        if r.responds(to: selector) {
          Logger.statistics.info("openUrl: Calling open:options:completionHandler:")

          // 使用 NSInvocation 风格调用（通过 perform 无法传递三个参数）
          // 改用闭包包装的方式
          let imp = r.method(for: selector)
          typealias OpenURLFunction = @convention(c) (AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], ((Bool) -> Void)?) -> Void
          let function = unsafeBitCast(imp, to: OpenURLFunction.self)
          function(r, selector, url, [:], { success in
            Logger.statistics.info("openUrl: open:options:completionHandler: completed, success: \(success)")
          })
          return
        }
      }

      responder = r.next
    }

    Logger.statistics.info("openUrl: UIApplication not found in responder chain, trying extensionContext")

    // 如果响应链方法都失败了，尝试 extensionContext
    if let extensionContext = extensionContext {
      Logger.statistics.info("openUrl: Using extensionContext")
      extensionContext.open(url, completionHandler: { success in
        Logger.statistics.info("openUrl: extensionContext.open completed, success: \(success)")
      })
      return
    }

    Logger.statistics.error("openUrl: All methods failed, URL not opened")
  }

  open func resetInputEngine() {
    if isEnglishInputActive && englishEngine.isComposing {
      englishEngine.reset()
      clearEnglishState()
      rimeContext.compositionPrefix = ""
      rimeContext.userInputKey = ""
      resetMixedInputFreezeState()
      return
    }
    if isAzooKeyInputActive {
      azooKeyEngine.reset()
      clearAzooKeyState()
      rimeContext.compositionPrefix = ""
      rimeContext.userInputKey = ""
      resetMixedInputFreezeState()
      return
    }
    rimeContext.compositionPrefix = ""
    rimeContext.reset()
    resetMixedInputFreezeState()
  }

  open func insertRimeKeyCode(_ keyCode: Int32) {
    if isUnifiedCompositionBufferEnabled, keyCode == XK_Return, hasActiveCompositionForBuffer() {
      commitCurrentCompositionToPrefixAndReset()
      flushCompositionPrefixIfNeeded()
      return
    }
    if keyCode == XK_Return,
       rimeContext.mixedInputManager.hasLiteral,
       !rimeContext.userInputKey.isEmpty
    {
      let commit = rimeContext.mixedInputManager.displayText.replacingOccurrences(of: " ", with: "")
      if !commit.isEmpty {
        commitMixedInputText(commit)
      } else {
        rimeContext.reset()
        resetMixedInputFreezeState()
      }
      return
    }
    if isUnifiedCompositionBufferEnabled, keyCode == XK_space {
      if hasActiveCompositionForBuffer() {
        commitFirstCandidateForLanguageSwitchIfNeeded()
      }
      appendToCompositionPrefix(.space)
      return
    }
    // 英语输入模式的特殊键处理
    if isEnglishInputActive && englishEngine.isComposing {
      switch keyCode {
      case XK_Return:
        // 回车键：提交原始输入
        commitEnglishRawText()
        return
      case XK_space:
        // 空格键：确认第一个候选词
        if let commit = englishEngine.commitCandidate(at: 0) {
          if isUnifiedCompositionBufferEnabled {
            appendToCompositionPrefix(commit + " ")
          } else {
            textDocumentProxy.insertText(commit)
            textDocumentProxy.insertText(.space)
          }
        }
        clearEnglishState()
        return
      case XK_BackSpace:
        deleteBackward()
        return
      default:
        break
      }
    }

    if isAzooKeyInputActive {
      switch keyCode {
      case XK_Return:
        if azooKeyEngine.isComposing {
          let commit = isUnifiedCompositionBufferEnabled ? azooKeyEngine.currentRawInputText : azooKeyEngine.currentDisplayText
          if !commit.isEmpty {
            if isUnifiedCompositionBufferEnabled {
              appendToCompositionPrefix(commit)
            } else {
              textDocumentProxy.insertText(commit)
            }
          }
          azooKeyEngine.reset()
          clearAzooKeyState()
          return
        }
        textDocumentProxy.insertText(.newline)
        return
      case XK_space:
        if azooKeyEngine.isComposing {
          if let commit = azooKeyEngine.commitCandidate(at: 0) {
            if isUnifiedCompositionBufferEnabled {
              appendToCompositionPrefix(commit)
            } else {
              textDocumentProxy.insertText(commit)
            }
          } else {
            let fallback = isUnifiedCompositionBufferEnabled ? azooKeyEngine.currentRawInputText : azooKeyEngine.currentDisplayText
            if !fallback.isEmpty {
              if isUnifiedCompositionBufferEnabled {
                appendToCompositionPrefix(fallback)
              } else {
                textDocumentProxy.insertText(fallback)
              }
            }
          }
          clearAzooKeyState()
          return
        }
        if keyboardContext.hamsterConfiguration?.keyboard?.enableSystemTextReplacement == true {
          Logger.statistics.info("SystemTextReplacement: space key pressed (AzooKey), trying replacement")
          if systemTextReplacementManager.tryReplace(in: textDocumentProxy) {
            textDocumentProxy.insertText(.space)
            return
          }
        }
        textDocumentProxy.insertText(.space)
        return
      default:
        tryHandleSpecificCode(keyCode)
        return
      }
    }
    // 空格键特殊处理：当没有 RIME 用户输入时，尝试执行文本替换
    if keyCode == XK_space && rimeContext.userInputKey.isEmpty {
      if keyboardContext.hamsterConfiguration?.keyboard?.enableSystemTextReplacement == true {
        Logger.statistics.info("SystemTextReplacement: space key pressed with no RIME input, trying replacement")
        if systemTextReplacementManager.tryReplace(in: textDocumentProxy) {
          textDocumentProxy.insertText(.space)
          return
        }
      }
    }
    
    guard rimeContext.tryHandleInputCode(keyCode) else {
      tryHandleSpecificCode(keyCode)
      return
    }
  }

  open func returnLastKeyboard() {
    keyboardContext.setKeyboardType(keyboardContext.returnKeyboardType())
  }

  // MARK: - Syncing

  /**
   Perform a text context sync.

   执行文本上下文同步。

   This is performed anytime the text is changed to ensure
   that ``keyboardTextContext`` is synced with the current
   text document context content.

   在更改文本时执行此操作，以确保 ``keyboardTextContext`` 与当前文本文档上下文内容同步。
   */
  open func performTextContextSync() {
    keyboardTextContext.sync(with: self)
  }

  // MARK: - Autocomplete

  /**
   The text that is provided to the ``autocompleteProvider``
   when ``performAutocomplete()`` is called.

   调用 ``performAutocomplete()`` 时提供给 ``autocompleteProvider`` 的文本。

   By default, the text document proxy's current word will
   be used. You can override this property to change that.

   默认情况下，将使用文本文档代理的当前单词。
   您可以覆盖此属性来更改。
   */
  open var autocompleteText: String? {
    textDocumentProxy.currentWord
  }

  /**
   Insert an autocomplete suggestion into the document.

   在文档中插入自动完成建议。

   By default, this call the `insertAutocompleteSuggestion`
   in the text document proxy, and then triggers a release
   in the keyboard action handler.

   默认情况下，这会调用文本文档代理中的 `insertAutocompleteSuggestion`，
   然后在键盘操作 handler 中触发 .release 操作。
   */
  open func insertAutocompleteSuggestion(_ suggestion: AutocompleteSuggestion) {
    textDocumentProxy.insertAutocompleteSuggestion(suggestion)
    keyboardActionHandler.handle(.release, on: .character(""))
  }

  /**
   Whether or not autocomplete is enabled.

   是否启用自动完成功能。

   By default, autocomplete is enabled as long as
   ``AutocompleteContext/isEnabled`` is `true`.

   默认情况下，只要 ``AutocompleteContext/isEnabled`` 为 `true`，自动完成功能就会启用。
   */
  open var isAutocompleteEnabled: Bool {
    autocompleteContext.isEnabled
  }

  /**
   Perform an autocomplete operation.

   执行自动完成操作。

   You can override this function to extend or replace the
   default logic. By default, it uses the `currentWord` of
   the ``textDocumentProxy`` to perform autocomplete using
   the current ``autocompleteProvider``.

   您可以重载此函数来扩展或替换默认逻辑。
   默认情况下，它会使用 ``textDocumentProxy`` 的 `currentWord`
   来使用当前的 ``autocompleteProvider`` 执行自动完成。
   */
  open func performAutocomplete() {
    guard isAutocompleteEnabled else { return }
    guard let text = autocompleteText else { return resetAutocomplete() }
    autocompleteProvider.autocompleteSuggestions(for: text) { [weak self] result in
      self?.updateAutocompleteContext(with: result)
    }
  }

  /**
   Reset the current autocomplete state.

   重置当前的自动完成状态。

   You can override this function to extend or replace the
   default logic. By default, it resets the suggestions in
   the ``autocompleteContext``.

   您可以重载此函数来扩展或替换默认逻辑。
   默认情况下，它会重置 ``autocompleteContext`` 中的 suggestion。
   */
  open func resetAutocomplete() {
    autocompleteContext.reset()
  }

  // MARK: - Dictation 听写

  /**
   The configuration to use when performing dictation from
   the keyboard extension.

   使用键盘扩展功能进行听写时要使用的配置。

   By default, this uses the `appGroupId` and `appDeepLink`
   properties from ``dictationContext``, so make sure that
   you call ``DictationContext/setup(with:)`` before using
   the dictation features in your keyboard extension.

   默认情况下，它会使用 ``dictationContext`` 中的 `appGroupId` 和 `appDeepLink` 属性，
   因此请确保在键盘扩展中使用听写功能前调用 ``DictationContext/setup(with:)` 。
   */
//  public var dictationConfig: KeyboardDictationConfiguration {
//    .init(
//      appGroupId: dictationContext.appGroupId ?? "",
//      appDeepLink: dictationContext.appDeepLink ?? ""
//    )
//  }

  /**
   Perform a keyboard-initiated dictation operation.

   执行键盘启动的听写操作。

   > Important: ``DictationContext/appDeepLink`` must have
   been set before this is called. The link must open your
   app and start dictation. See the docs for more info.

   > 重要：必须在调用此链接之前设置``DictationContext/appDeepLink``。
   > 链接必须打开主应用程序并开始听写。更多信息请参阅文档。
   */
//  public func performDictation() {
//    Task {
//      do {
//        try await dictationService.startDictationFromKeyboard(with: dictationConfig)
//      } catch {
//        await MainActor.run {
//          dictationContext.lastError = error
//        }
//      }
//    }
//  }
}

// MARK: - Private Functions

private extension KeyboardInputViewController {
  /// 刷新属性
  func refreshProperties() {
    refreshLayoutProvider()
    refreshCalloutActionContext()
  }

  /// 刷新呼出操作上下文
  func refreshCalloutActionContext() {
    calloutContext.action = ActionCalloutContext(
      actionHandler: keyboardActionHandler,
      actionProvider: calloutActionProvider
    )
  }

  /// 刷新布局 Provider
  func refreshLayoutProvider() {
    keyboardLayoutProvider.register(
      inputSetProvider: inputSetProvider
    )
  }

  func setupRIMELanguageObservation() {
    NotificationCenter.default.publisher(for: RimeContext.rimeSchemaDidChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.syncKeyboardTypeForJapaneseIfNeeded(reason: "schema")
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: RimeContext.rimeAsciiModeDidChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.syncKeyboardTypeForJapaneseIfNeeded(reason: "ascii")
      }
      .store(in: &cancellables)

    keyboardContext.keyboardTypePublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.normalizeJapaneseAlphabeticCaseIfNeeded(reason: "keyboardType")
      }
      .store(in: &cancellables)
  }

  func setupBackgroundCommitObservation() {
    let names: [Notification.Name] = [
      Notification.Name.NSExtensionHostWillResignActive,
      Notification.Name.NSExtensionHostDidEnterBackground,
      UIApplication.willResignActiveNotification,
      UIApplication.didEnterBackgroundNotification
    ]

    for name in names {
      NotificationCenter.default.publisher(for: name)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          self?.commitPendingCompositionForBackground()
        }
        .store(in: &cancellables)
    }
  }

  func commitPendingCompositionForBackground() {
    guard hasActiveCompositionForBuffer() || rimeContext.mixedInputManager.hasLiteral else { return }
    insertRimeKeyCode(XK_Return)
  }

  func applyDefaultLanguageIfNeeded(reason: String) {
    guard didApplyDefaultLanguage == false else { return }
    didApplyDefaultLanguage = true

    if let configuredLanguageMode = resolvedConfiguredLanguageMode() {
      if configuredLanguageMode == currentLanguageMode() {
        syncKeyboardTypeForJapaneseIfNeeded(reason: "defaultConfiguredNoSwitch-\(reason)")
      } else {
        setLanguageMode(configuredLanguageMode)
      }
      return
    }

    // followLast 且无历史记录时，默认回到中文，避免在部分宿主中被 ascii 状态拉到英文
    setLanguageMode(.chinese)
  }

  func syncKeyboardTypeForJapaneseIfNeeded(reason: String) {
    // RIME 启动期间只做最小化处理，避免在宿主输入框刚激活时触发 schema/ascii 的重入切换。
    if isRimeStartupInProgress() {
      Logger.statistics.info("DBG_LANGSWITCH skip sync while rime startup in progress, reason: \(reason, privacy: .public)")
      return
    }

    let japaneseActive = (rimeContext.asciiModeSnapshot == false && rimeContext.currentSchema?.isJapaneseSchema == true)
      || isAzooKeyInputActive
    let englishActive = rimeContext.asciiModeSnapshot
    keyboardContext.isAutoCapitalizationEnabled = !(japaneseActive || englishActive)
    keyboardContext.autocapitalizationTypeOverride = englishActive ? .none : nil

    if englishActive {
      if let configuredLanguageMode = resolvedConfiguredLanguageMode(), configuredLanguageMode != .english {
        Logger.statistics.info("DBG_LANGSWITCH force restore non-english mode: \(configuredLanguageMode.rawValue, privacy: .public), reason: \(reason, privacy: .public)")
        setLanguageMode(configuredLanguageMode)
        return
      }
      if !keyboardContext.keyboardType.isAlphabetic(.lowercased) {
        Logger.statistics.info("DBG_LANGSWITCH sync keyboardType -> alphabetic.lowercased (english, reason: \(reason, privacy: .public))")
        setKeyboardType(.alphabetic(.lowercased))
        return
      }
      return
    }

    if japaneseActive {
      wasJapaneseActive = true
      if !keyboardContext.keyboardType.isAlphabetic(.lowercased) {
        Logger.statistics.info("DBG_LANGSWITCH sync keyboardType -> alphabetic.lowercased (reason: \(reason, privacy: .public))")
        setKeyboardType(.alphabetic(.lowercased))
        return
      }
      Logger.statistics.info("DBG_LANGSWITCH reload alphabetic keyboard (reason: \(reason, privacy: .public))")
      keyboardRootView?.reloadKeyboardView()
      return
    }

    if wasJapaneseActive {
      wasJapaneseActive = false
      if keyboardContext.keyboardType.isAlphabetic {
        Logger.statistics.info("DBG_LANGSWITCH reload alphabetic keyboard (leave japanese, reason: \(reason, privacy: .public))")
        keyboardRootView?.reloadKeyboardView()
      }
    }

    if keyboardContext.keyboardType.isAlphabetic && keyboardContext.selectKeyboard.isChinesePrimaryKeyboard {
      Logger.statistics.info("DBG_LANGSWITCH sync keyboardType -> selectKeyboard (chinese, reason: \(reason, privacy: .public))")
      setKeyboardType(keyboardContext.selectKeyboard)
    }
  }

  func alignAsciiModeWithKeyboardTypeIfNeeded(reason: String) {
    let japaneseActive = (rimeContext.currentSchema?.isJapaneseSchema == true) || isAzooKeyInputActive
    if keyboardContext.keyboardType.isAlphabetic && !japaneseActive && rimeContext.asciiModeSnapshot == false {
      Logger.statistics.info("DBG_LANGSWITCH align ascii -> true (reason: \(reason, privacy: .public))")
      rimeContext.applyAsciiMode(true, overrideWindow: 0.5)
    }
    if keyboardContext.keyboardType.isChinesePrimaryKeyboard && rimeContext.asciiModeSnapshot && !japaneseActive {
      Logger.statistics.info("DBG_LANGSWITCH align ascii -> false (reason: \(reason, privacy: .public))")
      rimeContext.applyAsciiMode(false, overrideWindow: 0.5)
    }
  }

  func normalizeJapaneseAlphabeticCaseIfNeeded(reason: String) {
    guard rimeContext.asciiModeSnapshot == false, rimeContext.currentSchema?.isJapaneseSchema == true else {
      return
    }
    guard keyboardContext.keyboardType.isAlphabetic(.auto) else { return }
    Logger.statistics.info("DBG_LANGSWITCH normalize alphabetic.auto -> lowercased (reason: \(reason, privacy: .public))")
    setKeyboardType(.alphabetic(.lowercased))
  }

  /**
   Set up an initial width to avoid broken SwiftUI layouts.

   设置键盘初始宽度，以避免 SwiftUI 布局被破坏。
   */
  func setupInitialWidth() {
    view.frame.size.width = UIScreen.main.bounds.width
    Logger.statistics.debug("view frame width: \(UIScreen.main.bounds.width)")
  }

  /**
   Setup locale observation to handle locale-based changes.

   设置本地化观测，以处理基于本地化的更改。
   */
  func setupLocaleObservation() {
//    keyboardContext.$locale.sink { [weak self] in
//      guard let self = self else { return }
//      let locale = $0
//      self.primaryLanguage = locale.identifier
//      self.autocompleteProvider.locale = locale
//    }.store(in: &cancellables)
  }

  /**
   Set up the standard next keyboard button behavior.

   设置标准的下一个键盘按钮行为。
   */
  func setupNextKeyboardBehavior() {
    NextKeyboardController.shared = self
  }

  var needNumberKeyboard: Bool {
    switch textDocumentProxy.keyboardType {
    case .numbersAndPunctuation, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad: return true
    default: return false
    }
  }

  /**
   RIME 引擎设置
   */
  func setupRIME() {
    guard let startupID = beginRimeStartupIfNeeded() else {
      Logger.statistics.info("RIME startup is already in progress, skip duplicate trigger.")
      return
    }

    launchRimeStartupWatchdog(startupID: startupID)

    let startupTask = Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }

      let startupConfig = await MainActor.run { self.currentRimeStartupConfig() }
      let startupSucceeded = await self.performRimeStartupSequence(config: startupConfig)
      guard !Task.isCancelled else {
        self.finishRimeStartup(startupID: startupID, startupSucceeded: false)
        return
      }

      if startupSucceeded {
        await self.rimeContext.syncAsciiModeFromEngine()
        await MainActor.run { [weak self] in
          self?.applyDefaultLanguageIfNeeded(reason: "startupOrAlreadyRunning")
        }
      } else {
        await MainActor.run { [weak self] in
          self?.enterDegradedKeyboardModeForRimeStartupFailure(reason: "startupFailed")
        }
      }

      self.finishRimeStartup(startupID: startupID, startupSucceeded: startupSucceeded)
    }
    storeRimeStartupTask(startupTask)
  }

  private func performRimeStartupSequence(config: RimeStartupConfig) async -> Bool {
    if rimeContext.isRunning { return true }

    if let maximumNumberOfCandidateWords = config.maximumNumberOfCandidateWords {
      await rimeContext.setMaximumNumberOfCandidateWords(maximumNumberOfCandidateWords)
    }

    if let useContextPaging = config.useContextPaging {
      await rimeContext.setUseContextPaging(useContextPaging)
    }

    await rimeContext.start(hasFullAccess: true)

    await rimeContext.syncTraditionalSimplifiedChineseMode(simplifiedModeKey: config.simplifiedModeKey)
    return rimeContext.isRunning
  }

  private func currentRimeStartupConfig() -> RimeStartupConfig {
    let maximumNumberOfCandidateWords = keyboardContext.hamsterConfiguration?.rime?.maximumNumberOfCandidateWords
    let useContextPaging = keyboardContext.hamsterConfiguration?.toolbar?.swipePaging.map { $0 == false }
    let simplifiedModeKey = keyboardContext.hamsterConfiguration?.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
    return RimeStartupConfig(
      maximumNumberOfCandidateWords: maximumNumberOfCandidateWords,
      useContextPaging: useContextPaging,
      simplifiedModeKey: simplifiedModeKey
    )
  }

  private func launchRimeStartupWatchdog(startupID: Int) {
    Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }

      let deadline = Date().addingTimeInterval(self.rimeStartupTimeout)
      while Date() < deadline {
        if !self.isRimeStartupInProgress(startupID: startupID) { return }
        try? await Task.sleep(nanoseconds: self.rimeStartupWatchdogPollNanoseconds)
      }

      let (action, timeoutTask) = self.consumeWatchdogTimeout(startupID: startupID)
      timeoutTask?.cancel()

      switch action {
      case .ignore:
        return
      case .retry:
        Logger.statistics.error("RIME startup timeout, retry startup once.")
        await MainActor.run { [weak self] in
          guard let self else { return }
          DispatchQueue.main.asyncAfter(deadline: .now() + self.rimeStartupRetryDelay) { [weak self] in
            self?.setupRIME()
          }
        }
      case .degrade:
        Logger.statistics.error("RIME startup timeout, fallback to degraded mode.")
        await MainActor.run { [weak self] in
          self?.enterDegradedKeyboardModeForRimeStartupFailure(reason: "timeout")
        }
      }
    }
  }

  private func beginRimeStartupIfNeeded() -> Int? {
    rimeStartupStateQueue.sync {
      if rimeStartupInProgress { return nil }
      rimeStartupInProgress = true
      rimeStartupWatchdogTriggered = false
      rimeStartupSequenceID += 1
      return rimeStartupSequenceID
    }
  }

  private func finishRimeStartup(startupID: Int, startupSucceeded: Bool) {
    rimeStartupStateQueue.sync {
      guard rimeStartupInProgress, rimeStartupSequenceID == startupID else { return }
      rimeStartupInProgress = false
      rimeStartupWatchdogTriggered = false
      rimeStartupTask = nil
      if startupSucceeded {
        rimeStartupRetryCount = 0
      }
    }
  }

  private func isRimeStartupInProgress(startupID: Int? = nil) -> Bool {
    rimeStartupStateQueue.sync {
      guard let startupID else { return rimeStartupInProgress }
      return rimeStartupInProgress && rimeStartupSequenceID == startupID
    }
  }

  private func consumeWatchdogTimeout(startupID: Int) -> (action: RimeStartupWatchdogAction, task: Task<Void, Never>?) {
    rimeStartupStateQueue.sync {
      guard rimeStartupInProgress,
            rimeStartupSequenceID == startupID,
            !rimeStartupWatchdogTriggered else {
        return (.ignore, nil)
      }
      rimeStartupWatchdogTriggered = true
      let task = rimeStartupTask
      rimeStartupTask = nil
      rimeStartupInProgress = false
      if rimeStartupRetryCount < rimeStartupMaxRetryCount {
        rimeStartupRetryCount += 1
        rimeStartupWatchdogTriggered = false
        return (.retry, task)
      }
      return (.degrade, task)
    }
  }

  private func storeRimeStartupTask(_ task: Task<Void, Never>) {
    rimeStartupStateQueue.sync {
      rimeStartupTask = task
    }
  }

  private func rimeStartupTaskSnapshot() -> Task<Void, Never>? {
    rimeStartupStateQueue.sync { rimeStartupTask }
  }

  @MainActor
  private func enterDegradedKeyboardModeForRimeStartupFailure(reason: String) {
    Logger.statistics.error("RIME startup failed, using degraded mode. reason: \(reason, privacy: .public)")
    rimeContext.reset()
    rimeContext.clearAsciiModeOverride()
    // 降级模式优先回到中文主键盘，避免宿主输入框中被永久拉到英语布局。
    let configuredLanguageMode = resolvedConfiguredLanguageMode()
    if configuredLanguageMode == .english {
      rimeContext.applyAsciiMode(true)
      keyboardContext.isAutoCapitalizationEnabled = false
      keyboardContext.autocapitalizationTypeOverride = .none
      setKeyboardType(.alphabetic(.lowercased))
    } else {
      rimeContext.applyAsciiMode(false)
      keyboardContext.isAutoCapitalizationEnabled = true
      keyboardContext.autocapitalizationTypeOverride = nil
      if needNumberKeyboard {
        setKeyboardType(.numericNineGrid)
      } else if keyboardContext.selectKeyboard.isChinesePrimaryKeyboard {
        setKeyboardType(keyboardContext.selectKeyboard)
      } else {
        setKeyboardType(.chinese(.lowercased))
      }
    }
    if !isUnifiedCompositionBufferEnabled {
      textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
    }
  }

  func shutdownRIME() {
    /// 停止引擎，触发自造词等数据落盘
    rimeContext.shutdown()

    /// 重新启动引擎
    /// rimeContext.start(hasFullAccess: hasFullAccess)
  }

  /// Combine 观测 RIME 引擎中的用户输入及上屏文字
  func setupCombineRIMEInput() {
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] inputText in
        guard let self = self else { return }

        // 获取与清空在一起，防止重复上屏
        var commitText = self.rimeContext.commitText
        self.rimeContext.resetCommitText()

        // 写入上屏文字
        if !commitText.isEmpty {
          // 九宫格编码转换
          if self.keyboardContext.keyboardType.isChineseNineGrid {
            commitText = commitText.replaceT9pinyin
          }

          // 借鉴 AzooKey：如果有混合输入（数字），合并到上屏文字
          if self.rimeContext.mixedInputManager.hasLiteral {
            if self.rimeContext.mixedInputKeepLiteralAfterCommit {
              self.rimeContext.mixedInputKeepLiteralAfterCommit = false
            } else {
              commitText = self.rimeContext.mixedInputManager.getCommitText(rimeCommitText: commitText)
              self.mixedInputDebugLog("DBG_MIXEDINPUT commit with literal: \(commitText)")
              // 重置混合输入管理器
              self.rimeContext.mixedInputManager.reset()
              self.mixedInputSelectedNumericPrefix = nil
            }
          }
          if self.isUnifiedCompositionBufferEnabled {
            self.appendToCompositionPrefix(commitText)
          } else {
            self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))

            // 写入 userInputKey
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
              self.insertTextPatch(commitText)
            }
          }
        }

        // 非嵌入模式在 CandidateWordsView.swift 中处理，直接输入 Label 中
        guard self.keyboardContext.enableEmbeddedInputMode || self.isUnifiedCompositionBufferEnabled else { return }

        // 写入 userInputKey
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
          if self.keyboardContext.keyboardType.isChineseNineGrid {
            let t9UserInputKey = self.rimeContext.t9UserInputKey
            self.applyMarkedText(t9UserInputKey)
            return
          }
          self.applyMarkedText(inputText)
        }
      }
      .store(in: &cancellables)

//    rimeContext.registryHandleUserInputKeyChanged { [weak self] inputText in
//      guard let self = self else { return }
//
//      // 获取与清空在一起，防止重复上屏
//      let commitText = self.rimeContext.commitText
//      self.rimeContext.resetCommitText()
//
//      // 写入上屏文字
//      if !commitText.isEmpty {
//        self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
//
//        // 写入 userInputKey
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
//          self.insertTextPatch(commitText)
//        }
//      }
//
//      // 非嵌入模式在 CandidateWordsView.swift 中处理，直接输入 Label 中
//      guard self.keyboardContext.enableEmbeddedInputMode else { return }
//
//      // 写入 userInputKey
//      DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
//        if self.keyboardContext.keyboardType.isChineseNineGrid {
//          let t9UserInputKey = self.rimeContext.t9UserInputKey
//          self.textDocumentProxy.setMarkedText(t9UserInputKey, selectedRange: NSMakeRange(t9UserInputKey.utf8.count, 0))
//          return
//        }
//        self.textDocumentProxy.setMarkedText(inputText, selectedRange: NSMakeRange(inputText.utf8.count, 0))
//      }
//    }
  }

  /// 在 ``textDocumentProxy`` 的文本发生变化后，尝试更改为首选键盘类型
  func tryChangeToPreferredKeyboardTypeAfterTextDidChange() {
    let context = keyboardContext
    let shouldSwitch = keyboardBehavior.shouldSwitchToPreferredKeyboardTypeAfterTextDidChange()
    guard shouldSwitch else { return }
    setKeyboardType(context.preferredKeyboardType)
  }

  /**
   Update the autocomplete context with a certain result.

   根据特定结果更新自动完成的上下文。

   This is performed async to avoid that any network-based
   operations update the context from a background thread.

   这是同步执行的，需要避免任何基于网络的操作从后台线程更新上下文。
   */
  func updateAutocompleteContext(with result: AutocompleteResult) {
    DispatchQueue.main.async { [weak self] in
      guard let context = self?.autocompleteContext else { return }
      switch result {
      case .failure(let error): context.lastError = error
      case .success(let result): context.suggestions = result
      }
    }
  }

  /// 键盘回到前台后，尝试读取主 App 写入的语音结果并自动回填。
  @discardableResult
  func viewWillHandleVoiceInputResult() -> Bool {
    voiceInputBridge.cleanupExpiredData()
    guard let payload = voiceInputBridge.readLatestUnconsumedResult() else { return false }
    guard !payload.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
      voiceInputBridge.markResultConsumed(requestId: payload.requestId)
      return false
    }
    textDocumentProxy.insertText(payload.text)
    voiceInputBridge.markResultConsumed(requestId: payload.requestId)
    voiceInputBridge.setState(requestId: payload.requestId, state: KeyboardVoiceInputState.inserted)
    showVoiceUndoButton(requestId: payload.requestId, insertedTextCount: payload.text.count)
    return true
  }

  /// 键盘回到前台后，尝试读取主 App 写入的画布结果并复制到剪贴板。
  @discardableResult
  func viewWillHandleCanvasInputResult() -> Bool {
    canvasInputBridge.cleanupExpiredData()
    guard let payload = canvasInputBridge.readLatestUnconsumedResult() else { return false }
    let relativePath = payload.imageRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !relativePath.isEmpty else {
      canvasInputBridge.markResultConsumed(requestId: payload.requestId)
      return false
    }

    let imageURL = canvasInputBridge.resolveImageURL(relativePath: relativePath)
    guard let data = try? Data(contentsOf: imageURL), let image = UIImage(data: data) else {
      canvasInputBridge.markResultConsumed(requestId: payload.requestId)
      canvasInputBridge.setState(requestId: payload.requestId, state: .failed, errorMessage: "invalid canvas image")
      return false
    }

    copyCanvasImageToPasteboard(image, originalJPEGData: data)
    canvasInputBridge.markResultConsumed(requestId: payload.requestId)
    canvasInputBridge.setState(requestId: payload.requestId, state: .inserted)
    showTransientHint("画布已复制，可粘贴发送")
    return true
  }

  /// 语音回填轮询兜底：解决“先返回键盘、后写入结果”时的一次性漏插入问题。
  func startVoiceResultPollingIfNeeded() {
    voiceResultPollingDeadline = Date().addingTimeInterval(20)
    if voiceResultPollingTimer != nil {
      return
    }

    let timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
      guard let self else { return }
      if self.viewWillHandleVoiceInputResult() || self.viewWillHandleCanvasInputResult() {
        self.stopVoiceResultPolling()
        return
      }
      if let deadline = self.voiceResultPollingDeadline, Date() >= deadline {
        self.stopVoiceResultPolling()
      }
    }
    timer.tolerance = 0.2
    voiceResultPollingTimer = timer
  }

  func stopVoiceResultPolling() {
    voiceResultPollingTimer?.invalidate()
    voiceResultPollingTimer = nil
    voiceResultPollingDeadline = nil
  }

  func showVoiceUndoButton(requestId: String, insertedTextCount: Int) {
    guard insertedTextCount > 0 else { return }
    ensureVoiceUndoButton()
    voiceUndoButton.setTitle("已插入，撤销", for: .normal)
    lastVoiceInsertedCharacterCount = insertedTextCount
    lastVoiceInsertedRequestId = requestId
    voiceInputBridge.setState(requestId: requestId, state: KeyboardVoiceInputState.undoWindow)

    hideVoiceUndoWorkItem?.cancel()
    voiceUndoButton.isHidden = false
    UIView.animate(withDuration: 0.18) {
      self.voiceUndoButton.alpha = 1
    }

    let workItem = DispatchWorkItem { [weak self] in
      self?.hideVoiceUndoButton(animated: true)
    }
    hideVoiceUndoWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
  }

  func hideVoiceUndoButton(animated: Bool) {
    hideVoiceUndoWorkItem?.cancel()
    hideVoiceUndoWorkItem = nil
    let hideView = {
      self.voiceUndoButton.alpha = 0
    }
    let completion: (Bool) -> Void = { _ in
      self.voiceUndoButton.isHidden = true
    }
    if animated {
      UIView.animate(withDuration: 0.18, animations: hideView, completion: completion)
    } else {
      hideView()
      voiceUndoButton.isHidden = true
    }
  }

  func showTransientHint(_ text: String) {
    ensureVoiceUndoButton()
    lastVoiceInsertedCharacterCount = 0
    lastVoiceInsertedRequestId = nil
    voiceUndoButton.setTitle(text, for: .normal)

    hideVoiceUndoWorkItem?.cancel()
    voiceUndoButton.isHidden = false
    UIView.animate(withDuration: 0.18) {
      self.voiceUndoButton.alpha = 1
    }

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.hideVoiceUndoButton(animated: true)
      self.voiceUndoButton.setTitle("已插入，撤销", for: .normal)
    }
    hideVoiceUndoWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: workItem)
  }

  func copyCanvasImageToPasteboard(_ image: UIImage, originalJPEGData: Data) {
    let jpeg = originalJPEGData.isEmpty ? (image.jpegData(compressionQuality: 0.88) ?? Data()) : originalJPEGData
    guard !jpeg.isEmpty else {
      UIPasteboard.general.image = image
      return
    }
    // 部分应用（微信）优先读取 JPEG + public.image。
    UIPasteboard.general.items = [[
      UTType.jpeg.identifier: jpeg,
      UTType.image.identifier: image
    ]]
  }

  func ensureVoiceUndoButton() {
    guard voiceUndoButton.superview == nil else { return }
    view.addSubview(voiceUndoButton)
    NSLayoutConstraint.activate([
      voiceUndoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      voiceUndoButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8)
    ])
  }

  @objc func handleVoiceUndoTap() {
    guard lastVoiceInsertedCharacterCount > 0 else {
      hideVoiceUndoButton(animated: true)
      return
    }
    deleteBackward(times: lastVoiceInsertedCharacterCount)
    if let requestId = lastVoiceInsertedRequestId {
      voiceInputBridge.setState(requestId: requestId, state: KeyboardVoiceInputState.cancelled)
    }
    lastVoiceInsertedCharacterCount = 0
    lastVoiceInsertedRequestId = nil
    hideVoiceUndoButton(animated: true)
  }

  /// 上屏补丁：增加了成对符号/光标回退/返回主键盘的支持
  func insertTextPatch(_ insertText: String) {
    // 替换为成对符号
    let text = keyboardContext.getPairSymbols(insertText)
    
    // 先更新文本替换建议（在插入文本之前）
    updateTextReplacementSuggestion(pendingText: text)

    // 检测光标是否需要回退
    if keyboardContext.cursorBackOfSymbols(key: text) {
      // 检测是否有选中的文字，可以居中的光标将自动包裹选中的文本
      if text.count > 0, text.count % 2 == 0 {
        let selectText = textDocumentProxy.selectedText ?? ""
        let halfLength = text.count / 2
        let firstHalf = String(text.prefix(halfLength))
        let secondHalf = String(text.suffix(halfLength))
        textDocumentProxy.insertText("\(firstHalf)\(selectText)\(secondHalf)")
        // 如果选中的文字为空，将光标挪到中间，否则不用移动
        let offset = selectText.count == 0 ? halfLength : 0
        self.adjustTextPosition(byCharacterOffset: -offset)
      } else {
        textDocumentProxy.insertText(text)
        self.adjustTextPosition(byCharacterOffset: -1)
      }
    } else {
      textDocumentProxy.insertText(text)
    }

    // 检测是否需要返回主键盘
    let returnToPrimaryKeyboard = keyboardContext.returnToPrimaryKeyboardOfSymbols(key: insertText)
    if returnToPrimaryKeyboard {
      keyboardContext.setKeyboardType(keyboardContext.returnKeyboardType())
    }
  }
}

extension UIKeyboardType {
  var isNumberType: Bool {
    switch self {
    // 数字键盘
    case .numberPad, .numbersAndPunctuation, .phonePad, .decimalPad, .asciiCapableNumberPad: return true
    default: return false
    }
  }
}
