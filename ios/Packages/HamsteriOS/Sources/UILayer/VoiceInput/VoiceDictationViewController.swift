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
    isStarting = true
    voiceInputBridge.setState(requestId: requestId, state: .launching)
    statusLabel.text = "请求语音权限..."

    Task { [weak self] in
      guard let self else { return }
      do {
        try await self.speechEngine.start(
          localeIdentifier: Locale.preferredLanguages.first ?? "zh-CN",
          onResult: { [weak self] text, isFinal in
            guard let self else { return }
            self.latestTranscript = text
            self.transcriptView.text = text.isEmpty ? "请开始说话" : text
            self.statusLabel.text = isFinal ? "识别完成" : "正在听写..."
          }
        )
        await MainActor.run {
          self.voiceInputBridge.setState(requestId: self.requestId, state: .recording)
          self.statusLabel.text = "正在听写..."
          self.isStarting = false
        }
      } catch {
        await MainActor.run {
          self.statusLabel.text = "无法开始录音：\(error.localizedDescription)"
          self.voiceInputBridge.setState(
            requestId: self.requestId,
            state: .failed,
            errorMessage: error.localizedDescription
          )
          self.isStarting = false
        }
      }
    }
  }

  @objc private func handleStopTap() {
    guard !isFinishing else { return }
    isFinishing = true
    statusLabel.text = "处理中..."
    voiceInputBridge.setState(requestId: requestId, state: .processing)
    speechEngine.stop(cancel: false)

    // 等待最后一批回调写入后再落盘，避免用户快速点击导致最后几个词丢失。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let self else { return }
      let finalText = self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      if finalText.isEmpty {
        self.statusLabel.text = "未识别到语音，请重试"
        self.voiceInputBridge.setState(requestId: self.requestId, state: .failed, errorMessage: "empty transcript")
        self.isFinishing = false
        return
      }
      self.voiceInputBridge.writeResult(
        requestId: self.requestId,
        text: finalText,
        localeIdentifier: Locale.preferredLanguages.first
      )
      self.transcriptView.text = finalText
      self.statusLabel.text = "完成，请返回上一应用"
      self.stopButton.setTitle("已完成", for: .normal)
      self.stopButton.isEnabled = false
      self.stopButton.alpha = 0.72
      self.isFinishing = false
    }
  }

  @objc private func handleCancelTap() {
    speechEngine.stop(cancel: true)
    voiceInputBridge.setState(requestId: requestId, state: .cancelled)
    dismiss(animated: true)
  }
}
