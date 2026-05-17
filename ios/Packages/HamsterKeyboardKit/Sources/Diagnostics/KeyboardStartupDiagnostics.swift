//
//  KeyboardStartupDiagnostics.swift
//  HamsterKeyboardKit
//
//  Debug-only diagnostics for keyboard extension startup/layout hangs.
//

import Foundation
import CoreGraphics

enum KeyboardStartupDiagnostics {
  private static let marker = "NMKeyboardFreezeTrace"
  private static let startupSamplerMarker = "NMKeyboardStartup1msTrace"
  private static let startDate = Date()
  private static let lock = NSLock()
  private static var watchdogStarted = false
  private static var lastMainHeartbeat = Date()
  private static var lastLayoutSummaryByObject = [ObjectIdentifier: String]()
  private static var startupStateSamplingTimer: DispatchSourceTimer?
  private static var startupStateSamplingID = 0
  private static var startupStateSamples = [String]()
  private static var startupStatePhase = "idle"
  private static var lastStartupSampleTime: Date?

  private static var isEnabled: Bool {
    #if DEBUG
    true
    #else
    false
    #endif
  }

  static func log(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
    guard isEnabled else { return }
    let elapsed = Date().timeIntervalSince(startDate)
    let thread = Thread.isMainThread ? "main" : "bg"
    NSLog("⌨️ [%@ KeyboardDiag +%.3fs %@ %@:%u] %@", marker, elapsed, thread, "\(file)", line, message())
  }

  @discardableResult
  static func measure<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
    guard isEnabled else { return try work() }
    let started = Date()
    log("BEGIN \(label)")
    do {
      let value = try work()
      log(String(format: "END %@ %.3fs", label, Date().timeIntervalSince(started)))
      return value
    } catch {
      log(String(format: "FAIL %@ %.3fs error=%@", label, Date().timeIntervalSince(started), error.localizedDescription))
      throw error
    }
  }

  static func startMainThreadWatchdog() {
    guard isEnabled else { return }
    lock.lock()
    if watchdogStarted {
      lock.unlock()
      return
    }
    watchdogStarted = true
    lock.unlock()

    log("main-thread watchdog started")
    scheduleWatchdogTick()
  }

  static func markMainHeartbeat(_ reason: String) {
    guard isEnabled else { return }
    lock.lock()
    lastMainHeartbeat = Date()
    lock.unlock()
    log("main heartbeat: \(reason)")
  }

  static func shouldLogLayoutSummary(object: AnyObject, summary: String) -> Bool {
    guard isEnabled else { return false }
    let id = ObjectIdentifier(object)
    lock.lock()
    defer { lock.unlock() }
    if lastLayoutSummaryByObject[id] == summary {
      return false
    }
    lastLayoutSummaryByObject[id] = summary
    return true
  }

  static func startStartupStateSampling(
    label: String,
    duration: TimeInterval = 6.0,
    intervalMilliseconds: Int = 1,
    snapshot: @escaping () -> String
  ) {
    guard isEnabled else { return }
    let startedAt = Date()
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"

    lock.lock()
    startupStateSamplingTimer?.cancel()
    startupStateSamplingTimer = nil
    startupStateSamples.removeAll(keepingCapacity: true)
    startupStateSamplingID += 1
    startupStatePhase = "sampling-start"
    lastStartupSampleTime = nil
    let samplingID = startupStateSamplingID
    lock.unlock()

    log("1ms sampler start id=\(samplingID) label=\(label) duration=\(duration)s interval=\(intervalMilliseconds)ms os=\(osVersion)")

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMilliseconds), leeway: .nanoseconds(0))
    timer.setEventHandler {
      let now = Date()
      let elapsedMilliseconds = Int(now.timeIntervalSince(startedAt) * 1000)
      let timing = updateStartupSampleTiming(now: now)
      let sample = "t=\(elapsedMilliseconds)ms gap=\(String(format: "%.1f", timing.gapMilliseconds))ms phase=\(timing.phase) \(snapshot())"
      let isSuspicious = sample.contains("bad=1")
        || sample.contains("rows=0")
        || sample.contains("root=nil")
        || timing.gapMilliseconds > 20
      let chunk = appendStartupStateSample(sample, samplingID: samplingID, forceFlush: isSuspicious)

      if timing.gapMilliseconds > 20 {
        log(String(format: "1ms sampler main-gap %.1fms phase=%@", timing.gapMilliseconds, timing.phase))
      }
      if isSuspicious {
        logStartupSampleChunk([sample], samplingID: samplingID, reason: "suspicious")
      }
      if let chunk {
        logStartupSampleChunk(chunk.samples, samplingID: samplingID, reason: chunk.reason)
      }

      guard Date().timeIntervalSince(startedAt) >= duration else { return }
      stopStartupStateSampling(reason: "duration")
    }

    lock.lock()
    startupStateSamplingTimer = timer
    lock.unlock()
    timer.resume()
  }

  static func setStartupPhase(_ phase: String, file: StaticString = #fileID, line: UInt = #line) {
    guard isEnabled else { return }
    lock.lock()
    if startupStatePhase == phase {
      lock.unlock()
      return
    }
    startupStatePhase = phase
    lock.unlock()
    log("startup phase -> \(phase)", file: file, line: line)
  }

  static func stopStartupStateSampling(reason: String) {
    guard isEnabled else { return }
    lock.lock()
    let samplingID = startupStateSamplingID
    let samples = startupStateSamples
    startupStateSamples.removeAll(keepingCapacity: true)
    startupStateSamplingTimer?.cancel()
    startupStateSamplingTimer = nil
    startupStatePhase = "stopped-\(reason)"
    lastStartupSampleTime = nil
    lock.unlock()

    if !samples.isEmpty {
      logStartupSampleChunk(samples, samplingID: samplingID, reason: "stop-\(reason)")
    }
    log("1ms sampler stop id=\(samplingID) reason=\(reason)")
  }

  static func format(_ rect: CGRect) -> String {
    "(\(rounded(rect.minX)),\(rounded(rect.minY)),\(rounded(rect.width)),\(rounded(rect.height)))"
  }

  static func format(_ size: CGSize) -> String {
    "(\(rounded(size.width)),\(rounded(size.height)))"
  }

  private static func scheduleWatchdogTick() {
    let requestedAt = Date()
    DispatchQueue.main.async {
      lock.lock()
      lastMainHeartbeat = Date()
      lock.unlock()
      log(String(format: "main ping ok latency=%.3fs", Date().timeIntervalSince(requestedAt)))
    }

    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
      lock.lock()
      let started = watchdogStarted
      let gap = Date().timeIntervalSince(lastMainHeartbeat)
      lock.unlock()

      guard started else { return }
      if gap > 2.5 {
        log(String(format: "MAIN THREAD STALL suspected gap=%.3fs", gap))
      }
      scheduleWatchdogTick()
    }
  }

  private static func appendStartupStateSample(
    _ sample: String,
    samplingID: Int,
    forceFlush: Bool
  ) -> (samples: [String], reason: String)? {
    lock.lock()
    defer { lock.unlock() }
    guard samplingID == startupStateSamplingID else { return nil }

    startupStateSamples.append(sample)
    if forceFlush {
      let samples = startupStateSamples
      startupStateSamples.removeAll(keepingCapacity: true)
      return (samples, "forced")
    }
    guard startupStateSamples.count >= 25 else { return nil }
    let samples = startupStateSamples
    startupStateSamples.removeAll(keepingCapacity: true)
    return (samples, "chunk")
  }

  private static func updateStartupSampleTiming(now: Date) -> (gapMilliseconds: Double, phase: String) {
    lock.lock()
    defer { lock.unlock() }
    let gapMilliseconds: Double
    if let lastStartupSampleTime {
      gapMilliseconds = now.timeIntervalSince(lastStartupSampleTime) * 1000
    } else {
      gapMilliseconds = 0
    }
    lastStartupSampleTime = now
    return (gapMilliseconds, startupStatePhase)
  }

  private static func logStartupSampleChunk(_ samples: [String], samplingID: Int, reason: String) {
    guard !samples.isEmpty else { return }
    let joinedSamples = samples.joined(separator: " || ")
    DispatchQueue.global(qos: .utility).async {
      NSLog("⌨️ [%@ id=%d reason=%@ count=%d] %@", startupSamplerMarker, samplingID, reason, samples.count, joinedSamples)
    }
  }

  private static func rounded(_ value: CGFloat) -> String {
    String(format: "%.1f", Double(value))
  }
}
