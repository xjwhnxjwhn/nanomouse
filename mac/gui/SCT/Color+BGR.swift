import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Helpers for converting between Rime's BGR hex colors (0xBBGGRR) and SwiftUI Color.
extension Color {
    /// Initializes a Color from a Rime BGR hex string such as "0xBBGGRR".
    init?(bgrHex: String) {
        let sanitized = Color.normalizeHexString(bgrHex)
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return nil
        }

        let blue = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let red = Double(value & 0x0000FF) / 255.0

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }

    /// Returns the Rime BGR hex string representation (0xBBGGRR) of this Color, if available.
    #if canImport(AppKit)
    func bgrHexString(includePrefix: Bool = true) -> String? {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let red = max(0, min(1, nsColor.redComponent))
        let green = max(0, min(1, nsColor.greenComponent))
        let blue = max(0, min(1, nsColor.blueComponent))

        let redInt = UInt32(round(red * 255))
        let greenInt = UInt32(round(green * 255))
        let blueInt = UInt32(round(blue * 255))

        let value = (blueInt << 16) | (greenInt << 8) | redInt
        return String(format: includePrefix ? "0x%06X" : "%06X", value)
    }
    #endif

    private static func normalizeHexString(_ string: String) -> String {
        var sanitized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if sanitized.hasPrefix("0x") {
            sanitized.removeFirst(2)
        }
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }
        return sanitized.uppercased()
    }
}
