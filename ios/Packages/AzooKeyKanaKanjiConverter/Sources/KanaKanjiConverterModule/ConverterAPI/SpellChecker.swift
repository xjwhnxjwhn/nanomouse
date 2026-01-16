//
//  SpellChecker.swift
//
//
//  Created by ensan on 2023/05/20.
//

import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class SpellChecker {
    init() {}

    #if os(iOS) || os(tvOS) || os(visionOS)
    // UITextChecker is main-actor isolated on iOS-family platforms.
    // Use a static instance to avoid capturing `self` in main-actor closures.
    @MainActor private static let checker = UITextChecker()
    #elseif os(macOS)
    private let checker = NSSpellChecker.shared
    #endif

    func completions(forPartialWordRange range: NSRange, in string: String, language: String) -> [String]? {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if Thread.isMainThread {
            // Already on main thread: enter main-actor context synchronously.
            return MainActor.assumeIsolated { Self.checker.completions(forPartialWordRange: range, in: string, language: language) }
        } else {
            // Hop to main thread synchronously and run in main-actor context.
            var result: [String]?
            DispatchQueue.main.sync {
                result = MainActor.assumeIsolated { Self.checker.completions(forPartialWordRange: range, in: string, language: language) }
            }
            return result
        }
        #elseif os(macOS)
        return checker.completions(forPartialWordRange: range, in: string, language: language, inSpellDocumentWithTag: 0)
        #else
        return nil
        #endif
    }
}
