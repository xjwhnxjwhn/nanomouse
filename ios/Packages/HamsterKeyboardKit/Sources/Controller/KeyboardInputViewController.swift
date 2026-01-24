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
  // MARK: - View Controller Lifecycle ViewController 生命周期

  override open func viewDidLoad() {
    super.viewDidLoad()
    // setupInitialWidth()
    // setupLocaleObservation()
    // setupNextKeyboardBehavior()
    // KeyboardUrlOpener.shared.controller = self
    setupCombineRIMEInput()
    setupRIMELanguageObservation()
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
    setupRIME()
    viewWillSetupKeyboard()
    viewWillSyncWithContext()
    syncKeyboardTypeForJapaneseIfNeeded(reason: "willAppear")
    alignAsciiModeWithKeyboardTypeIfNeeded(reason: "willAppear")
    if shouldPrewarmAzooKeyOnAppear {
      azooKeyEngine.prewarmIfNeeded()
    }

    // 加载系统文本替换
    let enableTextReplacement = keyboardContext.hamsterConfiguration?.keyboard?.enableSystemTextReplacement ?? false
    Logger.statistics.info("SystemTextReplacement: enableSystemTextReplacement = \(enableTextReplacement)")
    if enableTextReplacement {
      systemTextReplacementManager.loadLexicon(from: self)
    }

    // fix: 屏幕边缘按键触摸延迟
    // https://stackoverflow.com/questions/39813245/touchesbeganwithevent-is-delayed-at-left-edge-of-screen
    // 注意：添加代码日志中会有警告
    // [Warning] Trying to set delaysTouchesBegan to NO on a system gate gesture recognizer - this is unsupported and will have undesired side effects
    // 如果后续有更好的解决方案，可以替换此方案
    view.window?.gestureRecognizers?.forEach {
      $0.delaysTouchesBegan = false
    }
  }

  override open func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
//    viewWillHandleDictationResult()
  }

  override open func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    didApplyDefaultLanguage = false
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

  func shouldAppendPunctuationToCompositionPrefix(_ text: String) -> Bool {
    guard isUnifiedCompositionBufferEnabled else { return false }
    guard text.count == 1, let scalar = text.unicodeScalars.first else { return false }
    if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
    if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) { return false }
    return CharacterSet.punctuationCharacters.contains(scalar)
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
      if self.isAzooKeyActive {
        self.azooKeyEngine.reset()
        self.clearAzooKeyState()
      }
    }
    
    // 更新文本替换建议
    updateTextReplacementSuggestion()
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
    if rimeContext.mixedInputManager.hasLiteral {
      // 检查最后一个段是否为数字
      if let lastSegment = rimeContext.mixedInputManager.segments.last, lastSegment.isLiteral {
        // 删除数字
        rimeContext.mixedInputManager.deleteBackward()
        // 更新显示
        let rimePreedit = rimeContext.rimeContext?.composition?.preedit ?? ""
        if rimeContext.mixedInputManager.hasLiteral {
          rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
        } else {
          rimeContext.userInputKey = rimeContext.compositionPrefix + rimePreedit
        }
        Logger.statistics.info("DBG_MIXEDINPUT delete literal, display: \(self.rimeContext.userInputKey, privacy: .public)")
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
    Logger.statistics.info("DBG_RIMEINPUT insertSymbol: \(symbol.char, privacy: .public), keyboardType: \(String(describing: self.keyboardContext.keyboardType), privacy: .public), asciiSnapshot: \(self.rimeContext.asciiModeSnapshot), schema: \(self.rimeContext.currentSchema?.schemaId ?? "nil", privacy: .public)")
    if isUnifiedCompositionBufferEnabled, symbol.char == .space {
      insertRimeKeyCode(XK_space)
      return
    }
    if shouldAppendPunctuationToCompositionPrefix(symbol.char) {
      if hasActiveCompositionForBuffer() {
        commitFirstCandidateForLanguageSwitchIfNeeded()
      }
      appendToCompositionPrefix(symbol.char)
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
      let char = symbol.char
      // 借鉴 AzooKey 独立应用：数字也传给引擎，使用 .direct 样式
      // AzooKey 的 composingText 会统一管理所有输入（包括数字）
      let isDigit = char.count == 1 && char.first?.isNumber == true
      if isDigit && azooKeyEngine.isComposing {
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
      if char == "ー", azooKeyEngine.isComposing {
        let suggestions = azooKeyEngine.handleInput(char, inputStyle: .direct, leftSideContext: azooKeyLeftSideContext())
        if azooKeyEngine.isComposing {
          updateAzooKeySuggestions(suggestions)
        } else {
          clearAzooKeyState()
          self.insertTextPatch(char)
        }
        return
      }
      if azooKeyEngine.isComposing, let commit = azooKeyEngine.commitCandidate(at: 0) {
        textDocumentProxy.insertText(commit)
        clearAzooKeyState()
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
    let char = symbol.char
    let isDigit = char.count == 1 && char.first?.isNumber == true
    if isDigit && !rimeContext.userInputKey.isEmpty {
      commitCurrentRimeCandidateForLiteralSeparatorIfNeeded()
      // 数字添加到混合输入管理器，不触发顶码上屏
      rimeContext.mixedInputManager.insertAtCursorPosition(char, isLiteral: true)
      // 更新显示：将数字追加到 userInputKey
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      Logger.statistics.info("DBG_MIXEDINPUT insertSymbol digit intercepted: \(char, privacy: .public), display: \(self.rimeContext.userInputKey, privacy: .public)")
      // 更新候选词（将数字与候选词合并）
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
        self.insertTextPatch(symbol.char)
      }
      return
    }

    self.insertTextPatch(symbol.char)
  }

  open func insertText(_ text: String) {
    Logger.statistics.info("DBG_RIMEINPUT insertText: \(text, privacy: .public), keyboardType: \(String(describing: self.keyboardContext.keyboardType), privacy: .public), asciiSnapshot: \(self.rimeContext.asciiModeSnapshot), schema: \(self.rimeContext.currentSchema?.schemaId ?? "nil", privacy: .public)")
    if isUnifiedCompositionBufferEnabled, text == .space {
      insertRimeKeyCode(XK_space)
      return
    }
    if shouldAppendPunctuationToCompositionPrefix(text) {
      if hasActiveCompositionForBuffer() {
        commitFirstCandidateForLanguageSwitchIfNeeded()
      }
      appendToCompositionPrefix(text)
      return
    }
    if isAzooKeyInputActive {
      // 借鉴 AzooKey 独立应用：数字也传给引擎，使用 .direct 样式
      let isDigit = text.count == 1 && text.first?.isNumber == true
      if isDigit && azooKeyEngine.isComposing {
        // 数字使用 .direct 样式传给 AzooKey 引擎
        let suggestions = azooKeyEngine.handleInput(text, inputStyle: .direct, leftSideContext: azooKeyLeftSideContext())
        if azooKeyEngine.isComposing {
          updateAzooKeySuggestions(suggestions)
        } else {
          clearAzooKeyState()
          self.insertTextPatch(text)
        }
        return
      }

      let style = azooKeyInputStyle(for: text)
      let suggestions = azooKeyEngine.handleInput(text, inputStyle: style, leftSideContext: azooKeyLeftSideContext())
      if azooKeyEngine.isComposing {
        updateAzooKeySuggestions(suggestions)
      } else {
        clearAzooKeyState()
        self.insertTextPatch(text)
      }
      return
    }
    if isEnglishInputActive {
      // 英语输入模式：使用候选栏
      Logger.statistics.info("DBG_ENGLISH insertText: \(text, privacy: .public), asciiMode: true")
      let isLetter = text.count == 1 && text.rangeOfCharacter(from: CharacterSet.letters) != nil
      let isDigit = text.count == 1 && text.first?.isNumber == true
      Logger.statistics.info("DBG_ENGLISH isLetter: \(isLetter), isComposing: \(self.englishEngine.isComposing)")
      if isLetter || (englishEngine.isComposing && isDigit) {
        let suggestions = englishEngine.handleInput(text)
        Logger.statistics.info("DBG_ENGLISH suggestions count: \(suggestions.count), isComposing: \(self.englishEngine.isComposing)")
        if englishEngine.isComposing {
          updateEnglishSuggestions(suggestions)
        } else {
          // 非字母输入且没有正在输入的内容，直接上屏
          clearEnglishState()
          self.textDocumentProxy.insertText(text)
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
        self.textDocumentProxy.insertText(text)
      }
      return
    }

    // 借鉴 AzooKey：检查是否为数字且当前有 RIME 输入
    let isDigit = text.count == 1 && text.first?.isNumber == true
    if isDigit && !rimeContext.userInputKey.isEmpty {
      commitCurrentRimeCandidateForLiteralSeparatorIfNeeded()
      // 数字添加到混合输入管理器，不发送给 RIME
      rimeContext.mixedInputManager.insertAtCursorPosition(text, isLiteral: true)
      // 更新显示：将数字追加到 userInputKey
      rimeContext.userInputKey = rimeContext.compositionPrefix + rimeContext.mixedInputManager.displayText
      Logger.statistics.info("DBG_MIXEDINPUT digit intercepted: \(text, privacy: .public), display: \(self.rimeContext.userInputKey, privacy: .public)")
      // 更新候选词（将数字与候选词合并）
      updateMixedInputSuggestions()
      return
    }

    // 非数字字符，同时添加到混合输入管理器
    if !isDigit && !rimeContext.userInputKey.isEmpty {
      rimeContext.mixedInputManager.insertAtCursorPosition(text, isLiteral: false)
    } else if !isDigit && rimeContext.userInputKey.isEmpty {
      // 首次输入，初始化混合输入管理器
      rimeContext.mixedInputManager.reset()
      rimeContext.mixedInputManager.insertAtCursorPosition(text, isLiteral: false)
    }

    // 字母输入模式，不经过 rime 引擎
    // if rimeContext.asciiMode {
    //  textDocumentProxy.insertText(text)
    //  return
    // }
    // rime 引擎处理
    let handled = self.rimeContext.tryHandleInputText(text)
    Logger.statistics.info("DBG_RIMEINPUT tryHandleInputText: \(text, privacy: .public), handled: \(handled)")
    if !handled {
      Logger.statistics.error("try handle input text: \(text), handle false")
      Logger.statistics.error("DBG_RIMEINPUT fallback insertTextPatch for: \(text, privacy: .public)")
      self.insertTextPatch(text)
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
    // 获取当前的 RIME 候选词（避免基于已合成候选再次合成导致重复）
    var rimeCandidates: [String] = []
    if let menu = rimeContext.rimeContext?.menu {
      let highlightIndex = Int(menu.pageSize * menu.pageNo + menu.highlightedCandidateIndex)
      let baseCandidates = rimeContext.candidateListLimit(
        index: rimeContext.candidateIndex,
        highlightIndex: highlightIndex,
        count: rimeContext.maximumNumberOfCandidateWords
      )
      rimeCandidates = baseCandidates.map { $0.text }
    } else {
      rimeCandidates = rimeContext.suggestions.map { $0.text }
    }

    // 使用混合输入管理器组合候选词
    let composedCandidates = rimeContext.mixedInputManager.composeCandidates(rimeCandidates: rimeCandidates)

    // 更新 suggestions
    Task { @MainActor in
      var newSuggestions: [CandidateSuggestion] = []
      for (index, text) in composedCandidates.enumerated() {
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
      }
    }
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
    if let commit = azooKeyEngine.commitCandidate(at: index) {
      if isUnifiedCompositionBufferEnabled {
        appendToCompositionPrefix(commit)
      } else {
        textDocumentProxy.insertText(commit)
      }
    }
    clearAzooKeyState()
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
      return
    }
    if isAzooKeyInputActive {
      azooKeyEngine.reset()
      clearAzooKeyState()
      rimeContext.compositionPrefix = ""
      rimeContext.userInputKey = ""
      return
    }
    rimeContext.compositionPrefix = ""
    rimeContext.reset()
  }

  open func insertRimeKeyCode(_ keyCode: Int32) {
    if isUnifiedCompositionBufferEnabled, keyCode == XK_Return, hasActiveCompositionForBuffer() {
      commitCurrentCompositionToPrefixAndReset()
      flushCompositionPrefixIfNeeded()
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

  func applyDefaultLanguageIfNeeded(reason: String) {
    guard didApplyDefaultLanguage == false else { return }
    let configuredMode = keyboardContext.hamsterConfiguration?.keyboard?.defaultLanguageMode ?? .followLast
    didApplyDefaultLanguage = true

    switch configuredMode {
    case .followLast:
      syncKeyboardTypeForJapaneseIfNeeded(reason: "defaultFollowLast-\(reason)")
    case .chinese:
      setLanguageMode(.chinese)
    case .japanese:
      setLanguageMode(.japanese)
    case .english:
      setLanguageMode(.english)
    }
  }

  func syncKeyboardTypeForJapaneseIfNeeded(reason: String) {
    let japaneseActive = (rimeContext.asciiModeSnapshot == false && rimeContext.currentSchema?.isJapaneseSchema == true)
      || isAzooKeyInputActive
    let englishActive = rimeContext.asciiModeSnapshot
    keyboardContext.isAutoCapitalizationEnabled = !(japaneseActive || englishActive)
    keyboardContext.autocapitalizationTypeOverride = englishActive ? .none : nil

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
    // 异步 RIME 引擎启动
    Task.detached { [weak self] in
      guard let self else { return }
//      if await rimeContext.isRunning {
//        Logger.statistics.debug("shutdown rime engine")
//        // 这里关闭引擎是为了使 RIME 内存中的自造词落盘。
//        await shutdownRIME()
//      }

      // 检测是否需要覆盖 RIME 目录
      // let overrideRimeDirectory = UserDefaults.hamster.overrideRimeDirectory

      // 检测对 appGroup 路径下是否有写入权限，如果没有写入权限，则需要将 appGroup 下文件复制到键盘的 Sandbox 路径下
//      if await !self.hasFullAccess {
//        do {
//          try FileManager.syncAppGroupUserDataDirectoryToSandbox(override: overrideRimeDirectory)
//
//          // 注意：如果没有开启键盘完全访问权限，则无权对 UserDefaults.hamster 写入
//          UserDefaults.hamster.overrideRimeDirectory = false
//        } catch {
//          Logger.statistics.error("FileManager.syncAppGroupUserDataDirectoryToSandbox(override: \(overrideRimeDirectory)) error: \(error.localizedDescription)")
//        }
//      }

      if await self.rimeContext.isRunning {
        await self.rimeContext.syncAsciiModeFromEngine()
        await MainActor.run { [weak self] in
          self?.applyDefaultLanguageIfNeeded(reason: "alreadyRunning")
        }
        return
      }

      if let maximumNumberOfCandidateWords = await self.keyboardContext.hamsterConfiguration?.rime?.maximumNumberOfCandidateWords {
        await self.rimeContext.setMaximumNumberOfCandidateWords(maximumNumberOfCandidateWords)
      }

      if let swipePaging = await self.keyboardContext.hamsterConfiguration?.toolbar?.swipePaging {
        await self.rimeContext.setUseContextPaging(swipePaging == false)
      }

      await self.rimeContext.start(hasFullAccess: true)

      let simplifiedModeKey = await self.keyboardContext.hamsterConfiguration?.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
      await self.rimeContext.syncTraditionalSimplifiedChineseMode(simplifiedModeKey: simplifiedModeKey)

      await MainActor.run { [weak self] in
        self?.applyDefaultLanguageIfNeeded(reason: "startup")
      }
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
            commitText = self.rimeContext.mixedInputManager.getCommitText(rimeCommitText: commitText)
            Logger.statistics.info("DBG_MIXEDINPUT commit with literal: \(commitText, privacy: .public)")
            // 重置混合输入管理器
            self.rimeContext.mixedInputManager.reset()
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
