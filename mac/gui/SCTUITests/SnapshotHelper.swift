//
//  SnapshotHelper.swift
//  SCTUITests
//
//  Minimal fastlane-compatible snapshot hooks. fastlane can replace this file
//  with its generated helper later without changing ScreenshotTests.
//

import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

func setupSnapshot(_ app: XCUIApplication) {
    app.launchEnvironment["FASTLANE_SNAPSHOT"] = "YES"
}

func openSnapshotDesktopBackgroundFullScreen() throws {
    try SnapshotDesktopBackground.shared.openFullScreen()
}

func closeSnapshotDesktopBackground() {
    SnapshotDesktopBackground.shared.close()
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

private final class SnapshotDesktopBackground {
    static let shared = SnapshotDesktopBackground()

    private let imageURL = URL(
        fileURLWithPath: "/Users/zhangxiangqing/Desktop/ipt/TESTProduct/desktop_no_icons.png",
        isDirectory: false
    )
    private var window: NSWindow?

    private init() {}

    func openFullScreen() throws {
        try runOnMain {
            guard FileManager.default.fileExists(atPath: self.imageURL.path) else {
                throw SnapshotDesktopBackgroundError.missingImage(self.imageURL.path)
            }
            guard let image = NSImage(contentsOf: self.imageURL) else {
                throw SnapshotDesktopBackgroundError.unreadableImage(self.imageURL.path)
            }
            guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                throw SnapshotDesktopBackgroundError.missingScreen
            }

            let screenFrame = screen.frame
            let backgroundWindow: NSWindow
            if let existingWindow = self.window {
                backgroundWindow = existingWindow
                if let imageView = existingWindow.contentView as? NSImageView {
                    imageView.image = image
                }
            } else {
                let imageView = NSImageView(frame: NSRect(origin: .zero, size: screenFrame.size))
                imageView.image = image
                imageView.imageScaling = .scaleAxesIndependently

                backgroundWindow = NSWindow(
                    contentRect: screenFrame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                backgroundWindow.backgroundColor = .black
                backgroundWindow.isOpaque = true
                backgroundWindow.hasShadow = false
                backgroundWindow.ignoresMouseEvents = true
                backgroundWindow.level = .normal
                backgroundWindow.collectionBehavior = [
                    .canJoinAllSpaces,
                    .fullScreenAuxiliary,
                    .stationary,
                    .ignoresCycle
                ]
                backgroundWindow.setAccessibilityIdentifier("snapshot_desktop_background")
                backgroundWindow.setAccessibilityLabel("snapshot_desktop_background")
                backgroundWindow.contentView = imageView
                backgroundWindow.isReleasedWhenClosed = false
                self.window = backgroundWindow
            }

            backgroundWindow.setFrame(screenFrame, display: true)
            backgroundWindow.contentView?.frame = NSRect(origin: .zero, size: screenFrame.size)
            backgroundWindow.orderFrontRegardless()
        }
    }

    func close() {
        runOnMain {
            self.window?.orderOut(nil)
            self.window = nil
        }
    }

    private func runOnMain<T>(_ work: @escaping () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try work()
        }

        var result: Result<T, Error>!
        DispatchQueue.main.sync {
            result = Result {
                try work()
            }
        }
        return try result.get()
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}

private enum SnapshotDesktopBackgroundError: LocalizedError {
    case missingImage(String)
    case unreadableImage(String)
    case missingScreen

    var errorDescription: String? {
        switch self {
        case .missingImage(let path):
            return "Missing no-icon desktop background image: \(path)"
        case .unreadableImage(let path):
            return "Failed to read no-icon desktop background image: \(path)"
        case .missingScreen:
            return "No screen is available for the no-icon desktop background."
        }
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

    static func capturePNGData() -> Data {
        let fullScreenPNGData = XCUIScreen.main.screenshot().pngRepresentation
        return SnapshotImageProcessor.cropAndResizePNGData(fullScreenPNGData)
    }

    static func write(_ pngData: Data, name: String) {
        let fileURL = runDirectory.appendingPathComponent("\(sanitizedFileName(name)).png")

        do {
            try pngData.write(to: fileURL, options: .atomic)
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

private enum SnapshotImageProcessor {
    private static let outputWidth = 2560
    private static let outputHeight = 1600
    private static let outputSize = CGSize(width: CGFloat(outputWidth), height: CGFloat(outputHeight))
    private static let outputAspectRatio = CGFloat(outputWidth) / CGFloat(outputHeight)

    static func cropAndResizePNGData(_ pngData: Data) -> Data {
        guard let imageSource = CGImageSourceCreateWithData(pngData as CFData, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            XCTFail("Failed to decode full-screen screenshot PNG data.")
            return pngData
        }

        guard let croppedImage = sourceImage.cropping(to: cropRect(for: sourceImage)) else {
            XCTFail("Failed to crop full-screen screenshot to 16:10.")
            return pngData
        }

        guard let resizedImage = resizedImage(from: croppedImage) else {
            XCTFail("Failed to resize screenshot to \(outputWidth)x\(outputHeight).")
            return pngData
        }

        guard let outputData = encodedPNGData(from: resizedImage) else {
            XCTFail("Failed to encode \(outputWidth)x\(outputHeight) screenshot PNG data.")
            return pngData
        }

        return outputData
    }

    private static func cropRect(for image: CGImage) -> CGRect {
        let sourceWidth = image.width
        let sourceHeight = image.height
        let sourceAspectRatio = CGFloat(sourceWidth) / CGFloat(sourceHeight)

        if sourceAspectRatio > outputAspectRatio {
            let cropWidth = min(
                sourceWidth,
                Int((CGFloat(sourceHeight) * outputAspectRatio).rounded(.toNearestOrAwayFromZero))
            )
            let cropX = max(0, (sourceWidth - cropWidth) / 2)
            return CGRect(
                x: CGFloat(cropX),
                y: 0,
                width: CGFloat(cropWidth),
                height: CGFloat(sourceHeight)
            )
        }

        let cropHeight = min(
            sourceHeight,
            Int((CGFloat(sourceWidth) / outputAspectRatio).rounded(.toNearestOrAwayFromZero))
        )
        // Full-screen macOS captures include the menu bar at the top. When the
        // source is too tall, trimming from the top removes that bar first.
        let cropY = max(0, sourceHeight - cropHeight)
        return CGRect(
            x: 0,
            y: CGFloat(cropY),
            width: CGFloat(sourceWidth),
            height: CGFloat(cropHeight)
        )
    }

    private static func resizedImage(from image: CGImage) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: outputSize))
        return context.makeImage()
    }

    private static func encodedPNGData(from image: CGImage) -> Data? {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return outputData as Data
    }
}
