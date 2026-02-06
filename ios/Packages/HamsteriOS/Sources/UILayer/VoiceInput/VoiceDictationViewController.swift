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
  private var requestId: String
  private let speechEngine = VoiceSpeechRecognizerEngine()
  private let voiceInputBridge: AppVoiceInputBridge
  private var latestTranscript = ""
  private var isStarting = false
  private var isFinishing = false
  private var isRecording = false
  private var activeRoute: VoiceSpeechRecognizerEngine.Route = .appleOnDevice
  private var lastStartError: VoiceSpeechRecognizerEngine.EngineError?

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
    speechEngine.stop(cancel: true)
  }

  func updateRequestId(_ requestId: String) {
    self.requestId = requestId
    latestTranscript = ""
    transcriptView.text = "请开始说话"
    statusLabel.text = "准备中..."
    tipLabel.text = "识别完成后，请点击系统左上角“返回到上一应用”。"
    isRecording = false
    isFinishing = false
    isStarting = false
    lastStartError = nil
    configureStopButtonForFinish()
    voiceInputBridge.setState(requestId: requestId, state: .launching)
    speechEngine.stop(cancel: true)
    startRecognitionIfNeeded(force: true)
  }

  private func setupView() {
    view.backgroundColor = .systemBackground
    view.addSubview(titleLabel)
    view.addSubview(statusLabel)
    view.addSubview(transcriptView)
    view.addSubview(stopButton)
    view.addSubview(cancelButton)
    view.addSubview(tipLabel)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
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
              self.tipLabel.text = "识别完成后，请点击系统左上角“返回到上一应用”。"
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
          self.tipLabel.text = "识别完成后，请点击系统左上角“返回到上一应用”。"
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
    speechEngine.stop(cancel: true)
    isRecording = false
    isFinishing = false
    isStarting = false
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

  private func completeFinishingFlow(rawText: String) {
    guard isFinishing else { return }
    let finalText = postProcessTranscript(
      rawText,
      localeIdentifier: Locale.preferredLanguages.first
    )
    if finalText.isEmpty {
      statusLabel.text = "未识别到语音，请重试"
      tipLabel.text = "请保持环境安静并清晰说话，然后点击“重试”。"
      voiceInputBridge.setState(requestId: requestId, state: .failed, errorMessage: "empty transcript")
      configureStopButtonForRetry()
      lastStartError = .emptyAudio
      isFinishing = false
      return
    }

    voiceInputBridge.writeResult(
      requestId: requestId,
      text: finalText,
      localeIdentifier: Locale.preferredLanguages.first
    )
    transcriptView.text = finalText
    statusLabel.text = "完成，请返回上一应用"
    tipLabel.text = "你可以点击系统左上角返回原应用，文本会自动回填。"
    stopButton.setTitle("已完成", for: .normal)
    stopButton.isEnabled = false
    stopButton.alpha = 0.72
    isFinishing = false
  }
}
