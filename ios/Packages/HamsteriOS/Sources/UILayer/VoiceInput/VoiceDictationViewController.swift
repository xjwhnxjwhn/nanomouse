//
//  VoiceDictationViewController.swift
//
//
//  Created by Codex on 2026/2/6.
//

import HamsterKit
import HamsterUIKit
import UIKit

@MainActor
final class VoiceDictationViewController: NibLessViewController {
  private var requestId: String
  private let speechEngine = VoiceSpeechRecognizerEngine()
  private let llmService: VoiceLLMService = .shared
  private let llmSettingsStore: VoiceLLMSettingsStore = .shared
  private let voiceInputBridge: AppVoiceInputBridge
  private var latestTranscript = ""
  private var latestNonEmptyTranscript = ""
  private var latestCommittedText = ""
  private var isStarting = false
  private var isFinishing = false
  private var isRecording = false
  private var activeRoute: VoiceSpeechRecognizerEngine.Route = .appleOnDevice
  private var lastStartError: VoiceSpeechRecognizerEngine.EngineError?
  private var llmTransformTask: Task<Void, Never>?
  private var stopTapTranscriptSnapshot = ""
  private var finishTimeoutWorkItem: DispatchWorkItem?

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

  private lazy var llmIndicatorLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.backgroundColor = .tertiarySystemBackground
    label.layer.cornerRadius = 10
    label.layer.masksToBounds = true
    label.isHidden = true
    label.text = ""
    return label
  }()

  private lazy var dictationSectionTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .secondaryLabel
    label.text = "听写文本"
    return label
  }()

  private lazy var editSectionTitleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .secondaryLabel
    label.text = "预设整理结果"
    return label
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

  private lazy var editCommandView: UITextView = {
    let view = UITextView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isEditable = false
    view.font = .systemFont(ofSize: 17, weight: .regular)
    view.textColor = .label
    view.backgroundColor = .tertiarySystemBackground
    view.layer.cornerRadius = 16
    view.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    view.text = "完成听写后，系统会按当前预设自动整理，并在这里显示结果。"
    return view
  }()

  private lazy var stopButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("完成", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = .systemBlue
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
    label.text = "请先完成听写。"
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
    cancelFinishingTimeout()
    llmTransformTask?.cancel()
    llmTransformTask = nil
    speechEngine.stop(cancel: true)
  }

  func updateRequestId(_ requestId: String) {
    llmTransformTask?.cancel()
    llmTransformTask = nil
    cancelFinishingTimeout()
    self.requestId = requestId
    latestTranscript = ""
    latestNonEmptyTranscript = ""
    latestCommittedText = ""
    transcriptView.text = "请开始说话"
    editCommandView.text = "完成听写后，系统会按当前预设自动整理，并在这里显示结果。"
    statusLabel.text = "准备中..."
    tipLabel.text = makeModeHintText()
    isRecording = false
    isFinishing = false
    isStarting = false
    lastStartError = nil
    configureStopButtonForFinish()
    voiceInputBridge.setState(requestId: requestId, state: .launching)
    speechEngine.stop(cancel: true)
    refreshUIForCurrentMode(keepTranscript: false)
    startRecognitionIfNeeded(force: true)
  }

  private func setupView() {
    view.backgroundColor = .systemBackground
    view.addSubview(titleLabel)
    view.addSubview(statusLabel)
    view.addSubview(llmIndicatorLabel)
    view.addSubview(dictationSectionTitleLabel)
    view.addSubview(transcriptView)
    view.addSubview(editSectionTitleLabel)
    view.addSubview(editCommandView)
    view.addSubview(stopButton)
    view.addSubview(cancelButton)
    view.addSubview(tipLabel)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

      llmIndicatorLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
      llmIndicatorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      llmIndicatorLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

      dictationSectionTitleLabel.topAnchor.constraint(equalTo: llmIndicatorLabel.bottomAnchor, constant: 12),
      dictationSectionTitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      dictationSectionTitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

      transcriptView.topAnchor.constraint(equalTo: dictationSectionTitleLabel.bottomAnchor, constant: 8),
      transcriptView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      transcriptView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      transcriptView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),

      editSectionTitleLabel.topAnchor.constraint(equalTo: transcriptView.bottomAnchor, constant: 10),
      editSectionTitleLabel.leadingAnchor.constraint(equalTo: transcriptView.leadingAnchor),
      editSectionTitleLabel.trailingAnchor.constraint(equalTo: transcriptView.trailingAnchor),

      editCommandView.topAnchor.constraint(equalTo: editSectionTitleLabel.bottomAnchor, constant: 8),
      editCommandView.leadingAnchor.constraint(equalTo: transcriptView.leadingAnchor),
      editCommandView.trailingAnchor.constraint(equalTo: transcriptView.trailingAnchor),
      editCommandView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),

      stopButton.topAnchor.constraint(equalTo: editCommandView.bottomAnchor, constant: 16),
      stopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      cancelButton.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 10),
      cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      tipLabel.leadingAnchor.constraint(equalTo: transcriptView.leadingAnchor),
      tipLabel.trailingAnchor.constraint(equalTo: transcriptView.trailingAnchor),
      tipLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
    ])
    refreshUIForCurrentMode(keepTranscript: false)
  }

  private func startRecognitionIfNeeded(force: Bool = false) {
    if isStarting, !force { return }
    if force {
      cancelFinishingTimeout()
      speechEngine.stop(cancel: true)
      isRecording = false
      isFinishing = false
      latestTranscript = ""
      latestNonEmptyTranscript = ""
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
            Task { @MainActor [weak self] in
              guard let self else { return }
              let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
              if self.isFinishing {
                // 完成阶段禁止空回调覆盖已有文本，避免“点完成后文本消失”。
                if !trimmed.isEmpty {
                  self.latestTranscript = text
                  self.latestNonEmptyTranscript = text
                  self.transcriptView.text = text
                }
                if isFinal {
                  let candidate = trimmed.isEmpty ? self.stopTapTranscriptSnapshot : text
                  self.completeFinishingFlow(rawText: candidate)
                }
                return
              }

              if trimmed.isEmpty {
                // 识别过程中引擎可能回空包；如果已有文本，则保持现状，避免“突然清空”。
                if self.latestNonEmptyTranscript.isEmpty {
                  self.latestTranscript = ""
                  self.transcriptView.text = "请开始说话"
                } else {
                  self.latestTranscript = self.latestNonEmptyTranscript
                }
              } else {
                let acceptedText = self.acceptedTranscriptCandidate(newText: text, isFinal: isFinal)
                self.latestTranscript = acceptedText
                self.latestNonEmptyTranscript = acceptedText
                self.transcriptView.text = acceptedText
              }
              if isFinal {
                self.statusLabel.text = "识别完成，点击“完成”生成结果"
              } else {
                self.statusLabel.text = self.makeRecordingStatusText()
              }
            }
          },
          onRouteChanged: { [weak self] route in
            Task { @MainActor [weak self] in
              guard let self else { return }
              self.activeRoute = route
              self.statusLabel.text = self.makeRecordingStatusText()
              if route == .whisperOnDevice {
                self.tipLabel.text = "已切换 Whisper 离线识别，点击“完成”后会进行本地转写。"
              } else if route == .cloudNetwork {
                self.tipLabel.text = "已切换在线 ASR，点击“完成”后会上传音频并返回识别结果。"
              } else {
                self.tipLabel.text = self.makeModeHintText()
              }
            }
          },
          onError: { [weak self] error in
            Task { @MainActor [weak self] in
              guard let self else { return }
              self.handleRuntimeError(error)
            }
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

  private func refreshUIForCurrentMode(keepTranscript: Bool) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.refreshUIForCurrentMode(keepTranscript: keepTranscript)
      }
      return
    }
    titleLabel.text = "语音输入"
    if !keepTranscript || latestTranscript.isEmpty {
      transcriptView.text = latestCommittedText.isEmpty ? "请开始说话" : latestCommittedText
    }
    if latestCommittedText.isEmpty {
      editCommandView.text = "完成听写后，系统会按当前预设自动整理，并在这里显示结果。"
    } else {
      editCommandView.text = latestCommittedText
    }
    tipLabel.text = makeModeHintText()
    hideLLMIndicator()
  }

  private func makeModeHintText() -> String {
    let asrConfig = VoiceASRSettingsStore.shared.runtimeConfig()
    let selectedEngines = asrConfig.selectedEngines
    let engineText = selectedEngines.map { engine -> String in
      if engine == .cloud {
        return "在线（优先）"
      }
      return engine.displayName
    }.joined(separator: " + ")
    let asrHint = "ASR 引擎：\(engineText)。"

    if !llmSettingsStore.isLLMEnabled() {
      return "\(asrHint) AI 预设整理已关闭，完成后仅使用本地文本清洗规则。"
    }
    return "\(asrHint) 完成听写后，系统会按当前预设自动整理。"
  }

  private func currentLLMProviderModelText() -> String {
    let config = llmSettingsStore.runtimeConfig()
    let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? config.provider.defaultModel
      : config.model.trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(config.provider.displayName) / \(model)"
  }

  private func updateLLMIndicator(text: String, textColor: UIColor = .secondaryLabel) {
    // UILabel 没有内边距，这里通过空格让提示条可读性更稳定。
    llmIndicatorLabel.text = "  \(text)  "
    llmIndicatorLabel.textColor = textColor
    llmIndicatorLabel.isHidden = false
  }

  private func hideLLMIndicator() {
    llmIndicatorLabel.isHidden = true
    llmIndicatorLabel.text = ""
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
    cancelFinishingTimeout()
    statusLabel.text = "处理中..."
    voiceInputBridge.setState(requestId: requestId, state: .processing)
    stopButton.isEnabled = false
    stopButton.alpha = 0.72
    stopTapTranscriptSnapshot = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    if stopTapTranscriptSnapshot.isEmpty {
      let nonEmpty = latestNonEmptyTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      if !nonEmpty.isEmpty {
        stopTapTranscriptSnapshot = nonEmpty
      }
    }
    if stopTapTranscriptSnapshot.isEmpty {
      let uiText = transcriptView.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if uiText != "请开始说话" {
        stopTapTranscriptSnapshot = uiText
      }
    }
    speechEngine.stop(cancel: false)

    if activeRoute == .whisperOnDevice {
      tipLabel.text = "Whisper 正在本地转写，请稍候..."
      scheduleFinishingTimeout(
        after: 90,
        timeoutMessage: "Whisper 转写超时，请重试"
      )
      return
    }

    if activeRoute == .cloudNetwork {
      tipLabel.text = "云端 ASR 正在处理，请稍候..."
      scheduleFinishingTimeout(
        after: 60,
        timeoutMessage: "在线 ASR 处理超时，请重试"
      )
      return
    }

    // 等待最后一批回调写入后再落盘，避免用户快速点击导致最后几个词丢失。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let self else { return }
      let candidate = self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? self.stopTapTranscriptSnapshot
        : self.latestTranscript
      self.completeFinishingFlow(rawText: candidate)
    }
  }

  @objc private func handleCancelTap() {
    cancelFinishingTimeout()
    llmTransformTask?.cancel()
    llmTransformTask = nil
    speechEngine.stop(cancel: true)
    isRecording = false
    isFinishing = false
    isStarting = false
    latestTranscript = ""
    latestNonEmptyTranscript = ""
    stopTapTranscriptSnapshot = ""
    voiceInputBridge.setState(requestId: requestId, state: .cancelled)
    dismiss(animated: true)
  }

  private func makeRecordingStatusText() -> String {
    switch activeRoute {
    case .appleOnDevice:
      return "正在听写（离线）..."
    case .appleNetwork:
      return "正在听写（在线）..."
    case .whisperOnDevice:
      return "正在听写（Whisper 离线）..."
    case .cloudNetwork:
      return "正在听写（云端 ASR）..."
    }
  }

  private func configureStopButtonForFinish() {
    stopButton.setTitle("完成", for: .normal)
    stopButton.isEnabled = true
    stopButton.alpha = 1
    stopButton.backgroundColor = .systemBlue
  }

  private func configureStopButtonForRetry() {
    stopButton.setTitle("重试", for: .normal)
    stopButton.isEnabled = true
    stopButton.alpha = 1
    stopButton.backgroundColor = .systemBlue
  }

  private func handleStartFailure(_ error: VoiceSpeechRecognizerEngine.EngineError) {
    cancelFinishingTimeout()
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
    hideLLMIndicator()
  }

  private func handleRuntimeError(_ error: VoiceSpeechRecognizerEngine.EngineError) {
    cancelFinishingTimeout()
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
    hideLLMIndicator()
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
      return "Whisper 当前不可用。请确认已启用 WhisperKit，并下载可运行模型（建议 tiny/small）后重试。"
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

  private func acceptedTranscriptCandidate(newText: String, isFinal: Bool) -> String {
    let trimmedNew = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedNew.isEmpty else { return latestNonEmptyTranscript }
    if isFinal { return newText }

    let previous = latestNonEmptyTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !previous.isEmpty else { return newText }

    // 某些引擎会偶发短回退（例如从整句退回到几个词），这里过滤明显异常抖动。
    if trimmedNew.count >= previous.count { return newText }
    if previous.hasPrefix(trimmedNew) { return newText }

    let collapseThreshold = max(12, previous.count / 2)
    if trimmedNew.count < collapseThreshold {
      return latestNonEmptyTranscript
    }
    return newText
  }

  private struct OutputResolution {
    let text: String
    let usesLLM: Bool
    let fallbackReason: String?
  }

  private func resolveOutputTextLocally(rawText: String, localeIdentifier: String?) -> String {
    // 阶段3：保留本地规则链路，作为 LLM 不可用时的稳定兜底。
    postProcessTranscript(rawText, localeIdentifier: localeIdentifier)
  }

  private func resolveOutputTextWithLLM(
    rawText: String,
    localeIdentifier: String?
  ) async -> OutputResolution {
    let normalizedInput = resolveOutputTextLocally(rawText: rawText, localeIdentifier: localeIdentifier)
    guard !normalizedInput.isEmpty else {
      return OutputResolution(text: "", usesLLM: false, fallbackReason: nil)
    }
    do {
      let editedText = try await llmService.transform(
        task: .speakToEdit,
        sourceText: normalizedInput,
        instruction: nil,
        localeIdentifier: localeIdentifier
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      if !editedText.isEmpty {
        return OutputResolution(text: editedText, usesLLM: true, fallbackReason: nil)
      }
      return OutputResolution(
        text: normalizedInput,
        usesLLM: false,
        fallbackReason: "AI 返回为空，已回退本地整理规则"
      )
    } catch {
      return OutputResolution(
        text: normalizedInput,
        usesLLM: false,
        fallbackReason: userFacingLLMFailureReason(error)
      )
    }
  }

  private func userFacingLLMFailureReason(_ error: Error) -> String {
    let raw = error.localizedDescription
    let lowered = raw.lowercased()
    if lowered.contains("incorrect api key") || lowered.contains("invalid_api_key") || lowered.contains("api key") {
      return "AI 处理失败：API Key 无效或已过期，请在“账户 > AI 处理配置”更新后重试"
    }
    if lowered.contains("insufficient_quota") || lowered.contains("quota") || lowered.contains("billing") {
      return "AI 处理失败：账户额度不足或计费不可用，请检查供应商账户状态"
    }
    if lowered.contains("rate limit") || lowered.contains("too many requests") || lowered.contains("429") {
      return "AI 处理失败：请求过于频繁，请稍后重试"
    }
    if lowered.contains("timeout") || lowered.contains("timed out") || lowered.contains("network") {
      return "AI 处理失败：网络超时或连接失败，请检查网络后重试"
    }

    let sanitized = sanitizeSensitiveErrorText(raw)
    if sanitized.isEmpty {
      return "AI 处理失败：请求未成功，已回退本地整理规则"
    }
    return "AI 处理失败：\(sanitized)"
  }

  private func sanitizeSensitiveErrorText(_ text: String) -> String {
    var output = text
    output = replaceRegex(
      pattern: "sk-[A-Za-z0-9_\\-]{6,}",
      in: output,
      with: "sk-****"
    )
    output = replaceRegex(
      pattern: "https?://\\S+",
      in: output,
      with: ""
    )
    output = replaceRegex(
      pattern: "\\s+",
      in: output,
      with: " "
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    if output.count > 72 {
      let index = output.index(output.startIndex, offsetBy: 72)
      output = String(output[..<index]) + "..."
    }
    return output
  }

  private func completeFinishingFlow(rawText: String) {
    // 防御式兜底：该方法会修改多处 Auto Layout 相关 UI，必须在主线程执行。
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.completeFinishingFlow(rawText: rawText)
      }
      return
    }
    guard isFinishing else { return }
    cancelFinishingTimeout()
    // 先将 finishing 置为 false，避免 stop 回调和延迟兜底同时触发重复落盘。
    isFinishing = false
    let localeIdentifier = Locale.preferredLanguages.first
    let requestIdSnapshot = requestId
    let fallbackRawText: String = {
      let primary = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !primary.isEmpty { return rawText }
      let latest = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      if !latest.isEmpty { return latestTranscript }
      let nonEmpty = latestNonEmptyTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      if !nonEmpty.isEmpty { return latestNonEmptyTranscript }
      let snap = stopTapTranscriptSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
      if !snap.isEmpty { return stopTapTranscriptSnapshot }
      let uiText = transcriptView.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !uiText.isEmpty && uiText != "请开始说话" { return transcriptView.text }
      return ""
    }()
    let localText = resolveOutputTextLocally(rawText: fallbackRawText, localeIdentifier: localeIdentifier)

    if !llmSettingsStore.isLLMEnabled() {
      finalizeOutputText(
        localText,
        localeIdentifier: localeIdentifier,
        fallbackReason: nil,
        usedLLM: false,
        llmAttempted: false
      )
      return
    }

    statusLabel.text = "AI 处理中..."
    tipLabel.text = "正在调用 AI 优化结果..."
    updateLLMIndicator(text: "AI 整理：请求中（\(currentLLMProviderModelText())）", textColor: .systemOrange)
    llmTransformTask?.cancel()
    llmTransformTask = Task { [weak self] in
      guard let self else { return }
      let resolution = await self.resolveOutputTextWithLLM(
        rawText: fallbackRawText,
        localeIdentifier: localeIdentifier
      )
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard self.requestId == requestIdSnapshot else { return }
        self.finalizeOutputText(
          resolution.text,
          localeIdentifier: localeIdentifier,
          fallbackReason: resolution.fallbackReason,
          usedLLM: resolution.usesLLM,
          llmAttempted: true
        )
      }
    }
  }

  private func finalizeOutputText(
    _ finalText: String,
    localeIdentifier: String?,
    fallbackReason: String?,
    usedLLM: Bool,
    llmAttempted: Bool
  ) {
    // 防御式兜底：避免后台线程触发布局引擎修改导致主线程检查崩溃。
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.finalizeOutputText(
          finalText,
          localeIdentifier: localeIdentifier,
          fallbackReason: fallbackReason,
          usedLLM: usedLLM,
          llmAttempted: llmAttempted
        )
      }
      return
    }
    let normalizedFinalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedFinalText.isEmpty {
      cancelFinishingTimeout()
      statusLabel.text = "未识别到语音，请重试"
      tipLabel.text = "请保持环境安静并清晰说话，然后点击“重试”。"
      voiceInputBridge.setState(requestId: requestId, state: .failed, errorMessage: "empty transcript")
      configureStopButtonForRetry()
      lastStartError = .emptyAudio
      hideLLMIndicator()
      return
    }

    voiceInputBridge.writeResult(
      requestId: requestId,
      text: normalizedFinalText,
      localeIdentifier: localeIdentifier
    )
    latestCommittedText = normalizedFinalText
    _ = VoicePersonalDictionaryStore.shared.learnWords(from: normalizedFinalText, localeIdentifier: localeIdentifier)
    if transcriptView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      transcriptView.text = latestTranscript.isEmpty ? normalizedFinalText : latestTranscript
    }
    editCommandView.text = normalizedFinalText
    statusLabel.text = usedLLM ? "AI 处理完成，请返回上一应用" : "处理完成，请返回上一应用"
    if llmAttempted {
      if usedLLM {
        updateLLMIndicator(text: "AI 整理：已完成（\(currentLLMProviderModelText())）", textColor: .systemGreen)
      } else if let fallbackReason, !fallbackReason.isEmpty {
        updateLLMIndicator(text: "AI 整理：失败，已回退本地", textColor: .systemOrange)
      } else {
        updateLLMIndicator(text: "AI 整理：未生效，已回退本地", textColor: .systemOrange)
      }
    } else {
      hideLLMIndicator()
    }
    if let fallbackReason, !fallbackReason.isEmpty {
      tipLabel.text = "\(fallbackReason)。你可以继续使用，也可以在“账户 > AI 处理配置”调整。"
    } else {
      tipLabel.text = "你可以点击系统左上角返回原应用，文本会自动回填。"
    }
    stopButton.setTitle("已完成", for: .normal)
    stopButton.isEnabled = false
    stopButton.alpha = 0.72
    latestTranscript = normalizedFinalText
    latestNonEmptyTranscript = normalizedFinalText
    stopTapTranscriptSnapshot = ""
  }

  private func bestAvailableTranscriptCandidate() -> String {
    let latest = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    if !latest.isEmpty { return latestTranscript }
    let nonEmpty = latestNonEmptyTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    if !nonEmpty.isEmpty { return latestNonEmptyTranscript }
    let snapshot = stopTapTranscriptSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
    if !snapshot.isEmpty { return stopTapTranscriptSnapshot }
    let uiText = transcriptView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !uiText.isEmpty && uiText != "请开始说话" { return transcriptView.text }
    return ""
  }

  private func scheduleFinishingTimeout(after seconds: TimeInterval, timeoutMessage: String) {
    cancelFinishingTimeout()
    // Whisper/在线 ASR 的最终结果是异步回调；超时只做最后兜底，不应提前覆盖成功结果。
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.isFinishing else { return }
      let candidate = self.bestAvailableTranscriptCandidate()
      if !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self.completeFinishingFlow(rawText: candidate)
        return
      }
      self.speechEngine.stop(cancel: true)
      self.isFinishing = false
      self.isRecording = false
      self.statusLabel.text = timeoutMessage
      self.tipLabel.text = "请点击“重试”，或切换到 Apple Speech / 在线 ASR 后再试。"
      self.voiceInputBridge.setState(requestId: self.requestId, state: .failed, errorMessage: "transcription timeout")
      self.configureStopButtonForRetry()
      self.lastStartError = .runtimeFailure(message: timeoutMessage)
      self.hideLLMIndicator()
      self.finishTimeoutWorkItem = nil
    }
    finishTimeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
  }

  private func cancelFinishingTimeout() {
    finishTimeoutWorkItem?.cancel()
    finishTimeoutWorkItem = nil
  }
}
