//
//  SnapshotHelper.swift
//  SCTUITests
//
//  Minimal fastlane-compatible snapshot hooks. fastlane can replace this file
//  with its generated helper later without changing ScreenshotTests.
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import ImageIO
import XCTest

func setupSnapshot(_ app: XCUIApplication) {
    app.launchEnvironment["FASTLANE_SNAPSHOT"] = "YES"
    SnapshotOutput.application = app
}

func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 1) {
    if timeout > 0 {
        Thread.sleep(forTimeInterval: timeout)
    }

    XCTContext.runActivity(named: "Snapshot: \(name)") { activity in
        let pngData = SnapshotOutput.capturePNGData()
        SnapshotOutput.write(pngData, name: name)

        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = name
        attachment.lifetime = .keepAlways
        activity.add(attachment)
    }
}

private enum SnapshotOutput {
    fileprivate static weak var application: XCUIApplication?

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

    static func capturePNGData() -> Data {
        if let pngData = preferredContentScreenshotPNGData() {
            return pngData
        }
        let screenScreenshot = XCUIScreen.main.screenshot()
        if let windowBounds = screenshotWindowBounds(),
           let pngData = cropScreenScreenshot(screenScreenshot.pngRepresentation, to: windowBounds) {
            return pngData
        }
        return fallbackScreenshot(screenScreenshot).pngRepresentation
    }

    static func write(_ pngData: Data, name: String) {
        let fileURL = runDirectory.appendingPathComponent("\(sanitizedFileName(name)).png")

        do {
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            XCTFail("Failed to write screenshot: \(fileURL.path), error: \(error)")
        }
    }

    private static func fallbackScreenshot(_ screenScreenshot: XCUIScreenshot) -> XCUIScreenshot {
        if let window = application?.windows
            .matching(identifier: "screenshot_window")
            .firstMatch,
           window.exists {
            return window.screenshot()
        }
        if let window = application?.windows.firstMatch, window.exists {
            return window.screenshot()
        }
        return screenScreenshot
    }

    private static func preferredContentScreenshotPNGData() -> Data? {
        guard let application else { return nil }
        let contentElement = application.descendants(matching: .any)
            .matching(identifier: "screenshot_content")
            .firstMatch
        guard contentElement.waitForExistence(timeout: 1) else {
            return nil
        }

        let frame = contentElement.frame
        guard frame.width >= 600, frame.height >= 400 else {
            return nil
        }

        return contentElement.screenshot().pngRepresentation
    }

    private static func screenshotWindowBounds() -> CGRect? {
        guard let screenFrame = NSScreen.main?.frame else {
            return nil
        }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else {
            return nil
        }

        let candidate = windows
            .compactMap { info -> (bounds: CGRect, area: CGFloat)? in
                guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                      ownerName == "NanoMouse",
                      let layer = info[kCGWindowLayer as String] as? Int,
                      layer == 0,
                      let boundsValue = info[kCGWindowBounds as String],
                      CFGetTypeID(boundsValue as CFTypeRef) == CFDictionaryGetTypeID(),
                      var bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary),
                      bounds.width >= 700,
                      bounds.height >= 500 else {
                    return nil
                }
                bounds.origin.x = max(0, min(bounds.origin.x, screenFrame.width))
                bounds.origin.y = max(0, min(bounds.origin.y, screenFrame.height))
                bounds.size.width = min(bounds.width, screenFrame.width - bounds.minX)
                bounds.size.height = min(bounds.height, screenFrame.height - bounds.minY)
                guard bounds.width > 0, bounds.height > 0 else { return nil }
                return (bounds, bounds.width * bounds.height)
            }
            .max(by: { $0.area < $1.area })

        return candidate?.bounds
    }

    private static func cropScreenScreenshot(_ pngData: Data, to windowBounds: CGRect) -> Data? {
        guard let screenFrame = NSScreen.main?.frame,
              let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let scaleX = CGFloat(image.width) / screenFrame.width
        let scaleY = CGFloat(image.height) / screenFrame.height
        let cropRect = CGRect(
            x: windowBounds.minX * scaleX,
            y: (screenFrame.height - windowBounds.maxY) * scaleY,
            width: windowBounds.width * scaleX,
            height: windowBounds.height * scaleY
        ).integral

        guard cropRect.width > 0,
              cropRect.height > 0,
              let cropped = image.cropping(to: cropRect) else {
            return nil
        }

        let representation = NSBitmapImageRep(cgImage: cropped)
        return representation.representation(using: .png, properties: [:])
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = name.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()

        return sanitized.isEmpty ? "snapshot" : sanitized
    }
}
