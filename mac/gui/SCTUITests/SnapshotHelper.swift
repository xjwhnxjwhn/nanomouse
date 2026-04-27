//
//  SnapshotHelper.swift
//  SCTUITests
//
//  Minimal fastlane-compatible snapshot hooks. fastlane can replace this file
//  with its generated helper later without changing ScreenshotTests.
//

import Foundation
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
        SnapshotOutput.write(screenshot, name: name)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        activity.add(attachment)
    }
}

private enum SnapshotOutput {
    private static let rootDirectory = URL(
        fileURLWithPath: "/Users/zhangxiangqing/Desktop/ipt/TESTProduct",
        isDirectory: true
    )

    private static let runDirectory: URL = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"

        let directory = rootDirectory.appendingPathComponent(
            "\(formatter.string(from: Date()))-macOS",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create screenshot output directory: \(directory.path), error: \(error)")
        }

        return directory
    }()

    static func write(_ screenshot: XCUIScreenshot, name: String) {
        let fileURL = runDirectory.appendingPathComponent("\(sanitizedFileName(name)).png")

        do {
            try screenshot.pngRepresentation.write(to: fileURL, options: .atomic)
        } catch {
            XCTFail("Failed to write screenshot: \(fileURL.path), error: \(error)")
        }
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = name.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()

        return sanitized.isEmpty ? "snapshot" : sanitized
    }
}
