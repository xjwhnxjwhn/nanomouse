import SwiftUI

enum MacScreenshotTheme: String {
    case light
    case dark

    var colorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum MacScreenshotScenario: String, CaseIterable {
    case bytePaste
    case bytePasteEditor
    case canvas
    case markdown
    case causal

    var readyIdentifier: String {
        "screenshot_ready_\(rawValue)"
    }

    var outputName: String {
        switch self {
        case .bytePaste:
            return "01_byte_paste"
        case .bytePasteEditor:
            return "02_byte_paste_editor"
        case .canvas:
            return "03_canvas"
        case .markdown:
            return "04_markdown"
        case .causal:
            return "05_causal"
        }
    }
}

enum MacScreenshotMode {
    static var isEnabled: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-screenshotMode")
            || ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
        #else
        false
        #endif
    }

    static var scenario: MacScreenshotScenario? {
        #if DEBUG
        stringValue(argument: "-scenario", environmentKey: "SCREENSHOT_SCENARIO")
            .flatMap(MacScreenshotScenario.init(rawValue:))
        #else
        nil
        #endif
    }

    static var theme: MacScreenshotTheme? {
        #if DEBUG
        stringValue(argument: "-theme", environmentKey: "SCREENSHOT_THEME")
            .flatMap { MacScreenshotTheme(rawValue: $0.lowercased()) }
        #else
        nil
        #endif
    }

    private static func stringValue(argument: String, environmentKey: String) -> String? {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: argument),
           arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }
        return ProcessInfo.processInfo.environment[environmentKey]
    }
}

