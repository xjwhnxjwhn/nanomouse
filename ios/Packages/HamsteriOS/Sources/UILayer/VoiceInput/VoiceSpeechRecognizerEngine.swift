//
//  VoiceSpeechRecognizerEngine.swift
//
//
//  Created by Codex on 2026/2/6.
//

import AVFoundation
import Foundation
import Speech

final class VoiceSpeechRecognizerEngine {
  private let audioEngine = AVAudioEngine()
  private var recognitionTask: SFSpeechRecognitionTask?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognizer: SFSpeechRecognizer?

  enum EngineError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case recognizerUnavailable
    case inputNodeUnavailable

    var errorDescription: String? {
      switch self {
      case .microphonePermissionDenied:
        return "麦克风权限未开启"
      case .speechPermissionDenied:
        return "语音识别权限未开启"
      case .recognizerUnavailable:
        return "语音识别服务不可用"
      case .inputNodeUnavailable:
        return "音频输入不可用"
      }
    }
  }

  func start(
    localeIdentifier: String,
    onResult: @escaping (String, Bool) -> Void
  ) async throws {
    try await requestPermissions()
    stop(cancel: true)

    let locale = Locale(identifier: localeIdentifier)
    let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    guard let recognizer, recognizer.isAvailable else {
      throw EngineError.recognizerUnavailable
    }
    self.recognizer = recognizer

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    self.recognitionRequest = request

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    guard recordingFormat.channelCount > 0 else {
      throw EngineError.inputNodeUnavailable
    }

    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()

    recognitionTask = recognizer.recognitionTask(with: request) { result, _ in
      guard let result else { return }
      let text = result.bestTranscription.formattedString
      DispatchQueue.main.async {
        onResult(text, result.isFinal)
      }
    }
  }

  func stop(cancel: Bool) {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    audioEngine.inputNode.removeTap(onBus: 0)
    if cancel {
      recognitionTask?.cancel()
    } else {
      recognitionRequest?.endAudio()
    }
    recognitionTask = nil
    recognitionRequest = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func requestPermissions() async throws {
    let microphoneGranted = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    guard microphoneGranted else { throw EngineError.microphonePermissionDenied }

    let speechAuthorization = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
    guard speechAuthorization == .authorized else {
      throw EngineError.speechPermissionDenied
    }
  }
}
