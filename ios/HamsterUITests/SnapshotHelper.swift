//
//  SnapshotHelper.swift
//  HamsterUITests
//
//  Minimal fastlane-compatible snapshot hooks. fastlane can replace this file
//  with its generated helper later without changing ScreenshotTests.
//

import Foundation
import UIKit
import XCTest

func setupSnapshot(_ app: XCUIApplication) {
  app.launchEnvironment["FASTLANE_SNAPSHOT"] = "YES"
}

func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 1) {
  if timeout > 0 {
    Thread.sleep(forTimeInterval: timeout)
  }

  XCTContext.runActivity(named: "Snapshot: \(name)") { activity in
    let screenshot = XCUIScreen.main.screenshot()
    SnapshotOutput.write(screenshot, name: name, purpose: .default)

    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    activity.add(attachment)
  }
}

func webSnapshot(_ name: String, category: String, timeWaitingForIdle timeout: TimeInterval = 1) {
  if timeout > 0 {
    Thread.sleep(forTimeInterval: timeout)
  }

  XCTContext.runActivity(named: "Website Snapshot: \(category)/\(name)") { activity in
    let screenshot = XCUIScreen.main.screenshot()
    SnapshotOutput.write(screenshot, name: name, purpose: .website(category: category))

    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "\(category)-\(name)"
    attachment.lifetime = .keepAlways
    activity.add(attachment)
  }
}

private enum SnapshotPurpose: Hashable {
  case `default`
  case website(category: String)
}

private enum SnapshotOutput {
  private static let rootDirectory = URL(
    fileURLWithPath: "/Users/zhangxiangqing/Desktop/ipt/TESTProduct",
    isDirectory: true
  )

  private static let runStamp: String = {
    if let forcedStamp = ProcessInfo.processInfo.environment["NANOMOUSE_WEBSITE_RUN_STAMP"],
       !forcedStamp.isEmpty {
      return forcedStamp
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return formatter.string(from: Date())
  }()

  private static var runDirectories: [SnapshotPurpose: URL] = [:]

  private static func runDirectory(for purpose: SnapshotPurpose) -> URL {
    if let directory = runDirectories[purpose] {
      return directory
    }

    let directory: URL
    switch purpose {
    case .default:
      directory = rootDirectory.appendingPathComponent(
        "\(runStamp)-\(platformName)",
        isDirectory: true
      )
    case .website(let category):
      directory = categoryPathComponents(category).reduce(
        rootDirectory
          .appendingPathComponent("\(runStamp)-web", isDirectory: true)
      ) { partialURL, component in
        partialURL.appendingPathComponent(component, isDirectory: true)
      }
    }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      XCTFail("Failed to create screenshot output directory: \(directory.path), error: \(error)")
    }

    runDirectories[purpose] = directory
    return directory
  }

  private static var platformName: String {
    UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
  }

  static func write(_ screenshot: XCUIScreenshot, name: String, purpose: SnapshotPurpose) {
    let fileURL = runDirectory(for: purpose)
      .appendingPathComponent("\(sanitizedFileName(name)).png")

    do {
      try screenshot.pngRepresentation.write(to: fileURL, options: .atomic)
    } catch {
      XCTFail("Failed to write screenshot: \(fileURL.path), error: \(error)")
    }
  }

  private static func categoryPathComponents(_ category: String) -> [String] {
    let components = category.split(separator: "/").map { sanitizedFileName(String($0)) }
    return components.isEmpty ? ["screenshots"] : components
  }

  private static func sanitizedFileName(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let sanitized = name.unicodeScalars
      .map { allowed.contains($0) ? String($0) : "_" }
      .joined()

    return sanitized.isEmpty ? "snapshot" : sanitized
  }
}
