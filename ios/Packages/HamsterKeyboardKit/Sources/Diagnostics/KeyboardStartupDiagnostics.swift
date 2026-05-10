//
//  KeyboardStartupDiagnostics.swift
//  HamsterKeyboardKit
//
//  Release-visible diagnostics for keyboard extension startup/layout hangs.
//

import Foundation

enum KeyboardStartupDiagnostics {
  private static let marker = "NMKeyboardFreezeTrace"
  private static let startDate = Date()
  private static let lock = NSLock()
  private static var watchdogStarted = false
  private static var lastMainHeartbeat = Date()
  private static var lastLayoutSummaryByObject = [ObjectIdentifier: String]()

  static func log(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
    let elapsed = Date().timeIntervalSince(startDate)
    let thread = Thread.isMainThread ? "main" : "bg"
    NSLog("⌨️ [%@ KeyboardDiag +%.3fs %@ %@:%u] %@", marker, elapsed, thread, "\(file)", line, message())
  }

  @discardableResult
  static func measure<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
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
    lock.lock()
    lastMainHeartbeat = Date()
    lock.unlock()
    log("main heartbeat: \(reason)")
  }

  static func shouldLogLayoutSummary(object: AnyObject, summary: String) -> Bool {
    let id = ObjectIdentifier(object)
    lock.lock()
    defer { lock.unlock() }
    if lastLayoutSummaryByObject[id] == summary {
      return false
    }
    lastLayoutSummaryByObject[id] = summary
    return true
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
}
