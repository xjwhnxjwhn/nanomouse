//
//  VoiceDictationViewController.swift
//
//
//  Created by Codex on 2026/2/6.
//

import HamsterKit
import HamsterUIKit
import UIKit

final class VoiceDictationViewController: NibLessViewController {
  private enum VoiceMode: Int {
    case dictation = 0
    case speakToEdit = 1
  }

  private var requestId: String
  private let speechEngine = VoiceSpeechRecognizerEngine()
  private let llmService: VoiceLLMService = .shared
  private let llmSettingsStore: VoiceLLMSettingsStore = .shared
  private let voiceInputBridge: AppVoiceInputBridge
  private var latestTranscript = ""
  private var latestCommittedText = ""
  private var isStarting = false
  private var isFinishing = false
  private var isRecording = false
  private var activeRoute: VoiceSpeechRecognizerEngine.Route = .appleOnDevice
  private var lastStartError: VoiceSpeechRecognizerEngine.EngineError?
  private var voiceMode: VoiceMode = .dictation
  private var llmTransformTask: Task<Void, Never>?

  private lazy var titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 28, weight: .bold)
    label.text = "语音输入"
    return label
  }()

  private lazy var statusLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .medium)
    label.textColor = .secondaryLabel
    label.text = "准备中..."
    return label
  }()

  private lazy var modeSegmentedControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["听写", "编辑"])
    control.translatesAutoresizingMaskIntoConstraints = false
    control.selectedSegmentIndex = VoiceMode.dictation.rawValue
    control.addTarget(self, action: #selector(handleModeChanged), for: .valueChanged)
    return control
  }()

  private lazy var transcriptView: UITextView = {
    let view = UITextView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isEditable = false
    view.font = .systemFont(ofSize: 22, weight: .semibold)
    view.textColor = .label
    view.backgroundColor = .secondarySystemBackground
    view.layer.cornerRadius = 16
    view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    view.text = "请开始说话"
    return view
  }()

  private lazy var stopButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("完成", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = .label
    button.layer.cornerRadius = 24
    button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 26, bottom: 12, right: 26)
    button.addTarget(self, action: #selector(handleStopTap), for: .touchUpInside)
    return button
  }()

  private lazy var cancelButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("取消", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
    button.setTitleColor(.secondaryLabel, for: .normal)
    button.addTarget(self, action: #selector(handleCancelTap), for: .touchUpInside)
    return button
  }()

  private lazy var tipLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.text = "识别完成后，请点击系统左上角“返回到上一应用”。"
    return label
  }()

  init(requestId: String, voiceInputBridge: AppVoiceInputBridge = .shared) {
    self.requestId = requestId
    self.voiceInputBridge = voiceInputBridge
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NibLessView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupView()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startRecognitionIfNeeded()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    llmTransformTask?.cancel()
    llmTransformTask = nil
    speechEngine.stop(cancel: true)
  }

  func updateRequestId(_ requestId: String) {
    llmTransformTask?.cancel()
    llmTransformTask = nil
    self.requestId = requestId
    latestTranscript = ""
    latestCommittedText = ""
    transcriptView.text = "请开始说话"
    statusLabel.text = "准备中..."
    tipLabel.text = makeModeHintText()
    isRecording = false
    isFinishing = false
    isStarting = false
    lastStartError = nil
    voiceMode = .dictation
    modeSegmentedControl.selectedSegmentIndex = VoiceMode.dictation.rawValue
    updateModeControlAvailability()
    configureStopButtonForFinish()
    voiceInputBridge.setState(requestId: requestId, state: .launching)
    speechEngine.stop(cancel: true)
    refreshUIForCurrentMode(keepTranscript: false)
    startRecognitionIfNeeded(force: true)
  }

  private func setupView() {
    view.backgroundColor = .systemBackground
    view.addSubview(titleLabel)
    view.addSubview(modeSegmentedControl)
    view.addSubview(statusLabel)
    view.addSubview(transcriptView)
    view.addSubview(stopButton)
    view.addSubview(cancelButton)
    view.addSubview(tipLabel)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      modeSegmentedControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      modeSegmentedControl.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      modeSegmentedControl.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

      statusLabel.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 10),
      statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

      transcriptView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 14),
      transcriptView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      transcriptView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      transcriptView.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),

      stopButton.topAnchor.constraint(equalTo: transcriptView.bottomAnchor, constant: 18),
      stopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      cancelButton.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 10),
      cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      tipLabel.leadingAnchor.constraint(equalTo: transcriptView.leadingAnchor),
      tipLabel.trailingAnchor.constraint(equalTo: transcriptView.trailingAnchor),
      tipLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
    ])
    updateModeControlAvailability()
    refreshUIForCurrentMode(keepTranscript: false)
  }

  private func startRecognitionIfNeeded(force: Bool = false) {
    if isStarting, !force { return }
    if force {
      speechEngine.stop(cancel: true)
      isRecording = false
      isFinishing = false
      latestTranscript = ""
    }
    isStarting = true
    lastStartError = nil
    configureStopButtonForFinish()
    voiceInputBridge.setState(requestId: requestId, state: .launching)
    statusLabel.text = "请求语音权限..."

    Task { [weak self] in
      guard let self else { return }
      do {
        let localeIdentifier = Locale.preferredLanguages.first ?? "zh-CN"
        let strategy = VoiceSpeechRecognizerEngine.StartStrategy.recommended(for: localeIdentifier)
        try await self.speechEngine.start(
          localeIdentifier: localeIdentifier,
          strategy: strategy,
          onResult: { [weak self] text, isFinal in
            guard let self else { return }
            self.latestTranscript = text
            self.transcriptView.text = text.isEmpty ? "请开始说话" : text
            if self.isFinishing && isFinal {
              self.completeFinishingFlow(rawText: text)
              return
            }
            self.statusLabel.text = isFinal ? "识别完成，点击“完成”回填" : self.makeRecordingStatusText()
          },
          onRouteChanged: { [weak self] route in
            guard let self else { return }
            self.activeRoute = route
            self.statusLabel.text = self.makeRecordingStatusText()
            if route == .whisperOnDevice {
              self.tipLabel.text = "已切换 Whisper 离线识别，点击“完成”后会进行本地转写。"
            } else {
              self.tipLabel.text = self.makeModeHintText()
            }
          },
          onError: { [weak self] error in
            guard let self else { return }
            self.handleRuntimeError(error)
          }
        )
        await MainActor.run {
          self.voiceInputBridge.setState(requestId: self.requestId, state: .recording)
          self.statusLabel.text = self.makeRecordingStatusText()
          self.tipLabel.text = self.makeModeHintText()
          self.isStarting = false
          self.isRecording = true
          self.lastStartError = nil
        }
      } catch let error as VoiceSpeechRecognizerEngine.EngineError {
        await MainActor.run {
          self.handleStartFailure(error)
        }
      } catch {
        await MainActor.run {
          self.handleStartFailure(.runtimeFailure(message: error.localizedDescription))
        }
      }
    }
  }

  @objc private func handleModeChanged() {
    let selected = VoiceMode(rawValue: modeSegmentedControl.selectedSegmentIndex) ?? .dictation
    if selected == .speakToEdit && latestCommittedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      voiceMode = .dictation
      modeSegmentedControl.selectedSegmentIndex = VoiceMode.dictation.rawValue
      statusLabel.text = "请先完成一次听写，再使用编辑模式"
      tipLabel.text = "先在“听写”模式说一句话并点击“完成”，然后再切换到“编辑”。"
      refreshUIForCurrentMode(keepTranscript: true)
      return
    }
    voiceMode = selected
    refreshUIForCurrentMode(keepTranscript: true)
  }

  private func updateModeControlAvailability() {
    let hasCommittedText = !latestCommittedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    modeSegmentedControl.setEnabled(hasCommittedText, forSegmentAt: VoiceMode.speakToEdit.rawValue)
    if !hasCommittedText, voiceMode == .speakToEdit {
      voiceMode = .dictation
      modeSegmentedControl.selectedSegmentIndex = VoiceMode.dictation.rawValue
    }
  }

  private func refreshUIForCurrentMode(keepTranscript: Bool) {
    switch voiceMode {
    case .dictation:
      titleLabel.text = "语音输入"
      if !keepTranscript || latestTranscript.isEmpty {
        transcriptView.text = latestCommittedText.isEmpty ? "请开始说话" : latestCommittedText
      }
    case .speakToEdit:
      titleLabel.text = "语音编辑"
      if !keepTranscript || latestTranscript.isEmpty {
        transcriptView.text = latestCommittedText.isEmpty
          ? "请先在“听写”模式生成一段文本，再说编辑指令。"
          : latestCommittedText
      }
    }
    tipLabel.text = makeModeHintText()
  }

  private func makeModeHintText() -> String {
    switch voiceMode {
    case .dictation:
      return "识别完成后，请点击系统左上角“返回到上一应用”。"
    case .speakToEdit:
      if !llmSettingsStore.isLLMEnabled() {
        return "AI 编辑已关闭，当前会使用本地编辑规则（删除、替换、翻译等）。"
      }
      return "示例：\"删除最后一句\"、\"把项目A改成项目B\"、\"更礼貌一点\"、\"翻译成英文\"。"
    }
  }

  @objc private func handleStopTap() {
    if !isRecording {
      guard lastStartError != nil else { return }
      startRecognitionIfNeeded(force: true)
      return
    }
    guard !isFinishing else { return }
    isFinishing = true
    isRecording = false
    statusLabel.text = "处理中..."
    voiceInputBridge.setState(requestId: requestId, state: .processing)
    speechEngine.stop(cancel: false)

    if activeRoute == .whisperOnDevice {
      tipLabel.text = "Whisper 正在本地转写，请稍候..."
      DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
        guard let self, self.isFinishing else { return }
        self.completeFinishingFlow(rawText: self.latestTranscript)
      }
      return
    }

    // 等待最后一批回调写入后再落盘，避免用户快速点击导致最后几个词丢失。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let self else { return }
      self.completeFinishingFlow(rawText: self.latestTranscript)
    }
  }

  @objc private func handleCancelTap() {
    llmTransformTask?.cancel()
    llmTransformTask = nil
    speechEngine.stop(cancel: true)
    isRecording = false
    isFinishing = false
    isStarting = false
    voiceInputBridge.setState(requestId: requestId, state: .cancelled)
    dismiss(animated: true)
  }

  private func makeRecordingStatusText() -> String {
    let modePrefix: String
    switch voiceMode {
    case .dictation:
      modePrefix = "听写"
    case .speakToEdit:
      modePrefix = "编辑"
    }
    switch activeRoute {
    case .appleOnDevice:
      return "正在\(modePrefix)（离线）..."
    case .appleNetwork:
      return "正在\(modePrefix)（在线）..."
    case .whisperOnDevice:
      return "正在\(modePrefix)（Whisper 离线）..."
    }
  }

  private func configureStopButtonForFinish() {
    stopButton.setTitle("完成", for: .normal)
    stopButton.isEnabled = true
    stopButton.alpha = 1
    stopButton.backgroundColor = .label
  }

  private func configureStopButtonForRetry() {
    stopButton.setTitle("重试", for: .normal)
    stopButton.isEnabled = true
    stopButton.alpha = 1
    stopButton.backgroundColor = .systemBlue
  }

  private func handleStartFailure(_ error: VoiceSpeechRecognizerEngine.EngineError) {
    statusLabel.text = "无法开始录音：\(error.localizedDescription)"
    tipLabel.text = makeHintText(for: error)
    voiceInputBridge.setState(
      requestId: requestId,
      state: .failed,
      errorMessage: error.localizedDescription
    )
    isStarting = false
    isRecording = false
    isFinishing = false
    lastStartError = error
    configureStopButtonForRetry()
  }

  private func handleRuntimeError(_ error: VoiceSpeechRecognizerEngine.EngineError) {
    if isFinishing {
      isFinishing = false
    }
    statusLabel.text = "识别中断：\(error.localizedDescription)"
    tipLabel.text = makeHintText(for: error)
    voiceInputBridge.setState(
      requestId: requestId,
      state: .failed,
      errorMessage: error.localizedDescription
    )
    isStarting = false
    isRecording = false
    isFinishing = false
    lastStartError = error
    configureStopButtonForRetry()
  }

  private func makeHintText(for error: VoiceSpeechRecognizerEngine.EngineError) -> String {
    switch error {
    case .microphonePermissionDenied:
      return "请在系统设置中开启麦克风权限，然后点击“重试”。"
    case .speechPermissionDenied:
      return "请在系统设置中开启语音识别权限，然后点击“重试”。"
    case .onDeviceRecognitionUnavailable:
      return "当前设备离线识别不可用，系统将尝试在线识别。请保持网络可用后重试。"
    case .networkUnavailable:
      return "当前网络不可用。请连接网络后重试，或者切换到可离线识别的设备。"
    case .whisperUnavailable:
      return "当前版本未启用 Whisper 引擎，请检查依赖配置后重试。"
    case .emptyAudio:
      return "没有捕获到有效语音，请贴近麦克风并重试。"
    case .recognizerUnavailable:
      return "系统语音服务暂不可用，请稍后重试。"
    case .inputNodeUnavailable:
      return "未检测到可用音频输入，请检查录音设备状态。"
    case .runtimeFailure(let message):
      return "详细错误：\(message)"
    }
  }

  private func postProcessTranscript(_ rawText: String, localeIdentifier: String?) -> String {
    var normalized = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }

    // 阶段2：先做去口癖，再做标点与基础格式化，减少用户二次编辑成本。
    normalized = removeFillerWords(from: normalized)
    normalized = normalizeListFormatting(normalized)
    normalized = normalizeSentenceEnding(normalized, localeIdentifier: localeIdentifier)
    normalized = normalized.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func removeFillerWords(from text: String) -> String {
    var output = text
    output = replaceRegex(
      pattern: "(^|[\\s，。！？、,.!?])(嗯+|呃+|额+|那个+|这个+)(?=[\\s，。！？、,.!?]|$)",
      in: output,
      with: "$1"
    )
    output = replaceRegex(
      pattern: "(^|\\s)(uh+|um+|you\\s+know)(?=\\s|$)",
      in: output,
      with: "$1",
      options: [.caseInsensitive]
    )
    return output
  }

  private func normalizeListFormatting(_ text: String) -> String {
    if text.contains("\n") {
      return text
    }
    return replaceRegex(
      pattern: "\\s+(\\d+[\\.、])\\s*",
      in: text,
      with: "\n$1 "
    )
  }

  private func normalizeSentenceEnding(_ text: String, localeIdentifier: String?) -> String {
    guard let last = text.last else { return text }
    let endingPunctuation = "。！？.!?"
    if endingPunctuation.contains(last) {
      return text
    }

    let locale = (localeIdentifier ?? "").lowercased()
    if locale.hasPrefix("zh") || locale.hasPrefix("ja") {
      return text + "。"
    }
    return text + "."
  }

  private func replaceRegex(
    pattern: String,
    in text: String,
    with template: String,
    options: NSRegularExpression.Options = []
  ) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return text
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
  }

  private struct OutputResolution {
    let text: String
    let usesLLM: Bool
    let fallbackReason: String?
  }

  private func resolveOutputTextLocally(
    mode: VoiceMode,
    rawText: String,
    localeIdentifier: String?
  ) -> String {
    // 阶段3：保留本地规则链路，作为 LLM 不可用时的稳定兜底。
    let normalizedInput = postProcessTranscript(rawText, localeIdentifier: localeIdentifier)
    switch mode {
    case .dictation:
      return normalizedInput
    case .speakToEdit:
      return applySpeakToEdit(commandText: normalizedInput)
    }
  }

  private func resolveOutputTextWithLLM(
    mode: VoiceMode,
    rawText: String,
    baseText: String,
    localeIdentifier: String?
  ) async -> OutputResolution {
    let normalizedInput = postProcessTranscript(rawText, localeIdentifier: localeIdentifier)
    switch mode {
    case .dictation:
      return OutputResolution(
        text: normalizedInput,
        usesLLM: false,
        fallbackReason: nil
      )
    case .speakToEdit:
      let normalizedBase = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalizedBase.isEmpty else {
        return OutputResolution(
          text: "",
          usesLLM: false,
          fallbackReason: "编辑模式需要先生成一段文本"
        )
      }
      let isTranslation = isTranslationCommand(normalizedInput)
      if !llmSettingsStore.isLLMEnabled() {
        return OutputResolution(
          text: isTranslation ? translateTranscript(normalizedBase, instruction: normalizedInput) : applySpeakToEdit(commandText: normalizedInput),
          usesLLM: false,
          fallbackReason: nil
        )
      }
      do {
        let task: VoiceLLMTask = isTranslation ? .translation : .speakToEdit
        let editedText = try await llmService.transform(
          task: task,
          sourceText: normalizedBase,
          instruction: normalizedInput,
          localeIdentifier: localeIdentifier
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !editedText.isEmpty {
          return OutputResolution(
            text: editedText,
            usesLLM: true,
            fallbackReason: nil
          )
        }
        if isTranslation {
          return OutputResolution(
            text: translateTranscript(normalizedBase, instruction: normalizedInput),
            usesLLM: false,
            fallbackReason: "AI 返回为空，已回退本地翻译规则"
          )
        }
        return OutputResolution(
          text: applySpeakToEdit(commandText: normalizedInput),
          usesLLM: false,
          fallbackReason: "AI 返回为空，已回退本地编辑规则"
        )
      } catch {
        if isTranslation {
          return OutputResolution(
            text: translateTranscript(normalizedBase, instruction: normalizedInput),
            usesLLM: false,
            fallbackReason: "AI 翻译失败：\(error.localizedDescription)"
          )
        }
        return OutputResolution(
          text: applySpeakToEdit(commandText: normalizedInput),
          usesLLM: false,
          fallbackReason: "AI 编辑失败：\(error.localizedDescription)"
        )
      }
    }
  }

  private func applySpeakToEdit(commandText: String) -> String {
    let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return "" }
    var base = latestCommittedText.trimmingCharacters(in: .whitespacesAndNewlines)
    if base.isEmpty {
      return ""
    }

    if isTranslationCommand(command) {
      return translateTranscript(base, instruction: command)
    }

    if command.contains("删除最后一句") || command.contains("删掉最后一句") {
      base = removeLastSentence(from: base)
      return base
    }

    if command.contains("更礼貌") || command.contains("礼貌一点") {
      let respectful = base
        .replacingOccurrences(of: "你", with: "您")
        .replacingOccurrences(of: "给我", with: "请给我")
      if respectful.hasPrefix("请") || respectful.hasPrefix("您好") {
        return respectful
      }
      return "请\(respectful)"
    }

    if command.contains("精简") || command.contains("简短") {
      return removeLastSentence(from: base)
    }

    if let replaceRange = command.range(of: "把"), let toRange = command.range(of: "改成") {
      let oldStart = replaceRange.upperBound
      let oldEnd = toRange.lowerBound
      if oldStart < oldEnd {
        let oldText = String(command[oldStart..<oldEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let newText = String(command[toRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !oldText.isEmpty, !newText.isEmpty {
          return base.replacingOccurrences(of: oldText, with: newText)
        }
      }
    }

    if command.hasPrefix("追加") || command.hasPrefix("加上") {
      let appendText = command
        .replacingOccurrences(of: "追加", with: "")
        .replacingOccurrences(of: "加上", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !appendText.isEmpty {
        if base.hasSuffix("。") || base.hasSuffix(".") || base.hasSuffix("!") || base.hasSuffix("！") {
          return base + " " + appendText
        }
        return base + "，" + appendText
      }
    }

    return base
  }

  private func removeLastSentence(from text: String) -> String {
    let separators = CharacterSet(charactersIn: "。！？.!?\n")
    if let range = text.rangeOfCharacter(from: separators, options: .backwards) {
      let trimmed = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed
    }
    return ""
  }

  private func translateTranscript(_ text: String, instruction: String? = nil) -> String {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }

    if let targetLanguage = detectTargetLanguage(from: instruction) {
      switch targetLanguage {
      case .english:
        return translateChineseToEnglish(normalized)
      case .chinese:
        return translateEnglishToChinese(normalized)
      }
    }

    let hasHan = normalized.range(of: "\\p{Han}", options: .regularExpression) != nil
    if hasHan {
      return translateChineseToEnglish(normalized)
    }
    return translateEnglishToChinese(normalized)
  }

  private enum TranslationTargetLanguage {
    case chinese
    case english
  }

  private func isTranslationCommand(_ commandText: String) -> Bool {
    let normalized = commandText.lowercased()
    if normalized.contains("翻译") || normalized.contains("translate") {
      return true
    }
    return false
  }

  private func detectTargetLanguage(from instruction: String?) -> TranslationTargetLanguage? {
    let normalized = (instruction ?? "").lowercased()
    guard !normalized.isEmpty else { return nil }
    if normalized.contains("英文") || normalized.contains("英语") || normalized.contains("english") {
      return .english
    }
    if normalized.contains("中文") || normalized.contains("汉语") || normalized.contains("chinese") {
      return .chinese
    }
    return nil
  }

  private func translateChineseToEnglish(_ text: String) -> String {
    let dictionary: [String: String] = [
      "你好": "Hello",
      "早上好": "Good morning",
      "下午好": "Good afternoon",
      "晚上好": "Good evening",
      "谢谢": "Thank you",
      "请帮我": "Please help me",
      "我已经到达": "I have arrived",
      "会议改到明天": "The meeting is moved to tomorrow",
      "我稍后回复": "I will reply later",
      "请确认时间": "Please confirm the time",
      "今天": "today",
      "明天": "tomorrow",
      "后天": "the day after tomorrow"
    ]
    if let exact = dictionary[text] {
      return exact
    }
    return text
  }

  private func translateEnglishToChinese(_ text: String) -> String {
    let normalized = text.lowercased()
    let dictionary: [String: String] = [
      "hello": "你好",
      "good morning": "早上好",
      "good afternoon": "下午好",
      "good evening": "晚上好",
      "thank you": "谢谢",
      "please help me": "请帮我",
      "i have arrived": "我已经到达",
      "the meeting is moved to tomorrow": "会议改到明天",
      "i will reply later": "我稍后回复",
      "please confirm the time": "请确认时间",
      "today": "今天",
      "tomorrow": "明天"
    ]
    if let exact = dictionary[normalized] {
      return exact
    }
    return text
  }

  private func completeFinishingFlow(rawText: String) {
    guard isFinishing else { return }
    let localeIdentifier = Locale.preferredLanguages.first
    let mode = voiceMode
    let baseText = latestCommittedText
    let requestIdSnapshot = requestId

    if mode == .dictation {
      let finalText = resolveOutputTextLocally(
        mode: mode,
        rawText: rawText,
        localeIdentifier: localeIdentifier
      )
      finalizeOutputText(finalText, localeIdentifier: localeIdentifier, mode: mode, fallbackReason: nil)
      return
    }

    if !llmSettingsStore.isLLMEnabled() {
      let finalText = resolveOutputTextLocally(
        mode: mode,
        rawText: rawText,
        localeIdentifier: localeIdentifier
      )
      finalizeOutputText(finalText, localeIdentifier: localeIdentifier, mode: mode, fallbackReason: nil)
      return
    }

    statusLabel.text = "AI 处理中..."
    tipLabel.text = "正在调用 AI 优化结果..."
    llmTransformTask?.cancel()
    llmTransformTask = Task { [weak self] in
      guard let self else { return }
      let resolution = await self.resolveOutputTextWithLLM(
        mode: mode,
        rawText: rawText,
        baseText: baseText,
        localeIdentifier: localeIdentifier
      )
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard self.requestId == requestIdSnapshot else { return }
        self.finalizeOutputText(
          resolution.text,
          localeIdentifier: localeIdentifier,
          mode: mode,
          fallbackReason: resolution.fallbackReason
        )
        if resolution.usesLLM {
          self.statusLabel.text = "AI 处理完成，请返回上一应用"
        }
      }
    }
  }

  private func finalizeOutputText(
    _ finalText: String,
    localeIdentifier: String?,
    mode: VoiceMode,
    fallbackReason: String?
  ) {
    let normalizedFinalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedFinalText.isEmpty {
      statusLabel.text = "未识别到语音，请重试"
      if mode == .speakToEdit {
        tipLabel.text = "编辑模式需要先有一段文本，请先切回“听写”模式生成文本。"
      } else {
        tipLabel.text = "请保持环境安静并清晰说话，然后点击“重试”。"
      }
      voiceInputBridge.setState(requestId: requestId, state: .failed, errorMessage: "empty transcript")
      configureStopButtonForRetry()
      lastStartError = .emptyAudio
      isFinishing = false
      return
    }

    voiceInputBridge.writeResult(
      requestId: requestId,
      text: normalizedFinalText,
      localeIdentifier: localeIdentifier
    )
    latestCommittedText = normalizedFinalText
    updateModeControlAvailability()
    _ = VoicePersonalDictionaryStore.shared.learnWords(from: normalizedFinalText, localeIdentifier: localeIdentifier)
    transcriptView.text = normalizedFinalText
    statusLabel.text = "完成，请返回上一应用"
    if let fallbackReason, !fallbackReason.isEmpty {
      tipLabel.text = "\(fallbackReason)。你可以继续使用，也可以在“账户 > AI 处理配置”调整。"
    } else {
      tipLabel.text = "你可以点击系统左上角返回原应用，文本会自动回填。"
    }
    stopButton.setTitle("已完成", for: .normal)
    stopButton.isEnabled = false
    stopButton.alpha = 0.72
    isFinishing = false
  }
}
