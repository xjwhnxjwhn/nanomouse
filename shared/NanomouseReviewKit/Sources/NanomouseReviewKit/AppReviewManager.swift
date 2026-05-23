import Foundation
import StoreKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public final class AppReviewManager {
    public static let shared = AppReviewManager()

    private let defaults: UserDefaults
    private let bundle: Bundle
    private let policy: AppReviewPolicy
    private let now: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        policy: AppReviewPolicy = AppReviewPolicy(),
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.bundle = bundle
        self.policy = policy
        self.now = now
    }

    public func registerLaunchIfNeeded() {
        var state = loadState()
        guard state.firstLaunchDate == nil else { return }
        state.firstLaunchDate = now()
        saveState(state)
    }

    public func recordSuccessfulUse() {
        registerLaunchIfNeeded()

        var state = loadState()
        state.successfulUseCount += 1
        saveState(state)
        maybeRequestAutomaticReview()
    }

    public func maybeRequestAutomaticReview() {
        registerLaunchIfNeeded()
        performOnMain { [self] in
            let state = loadState()
            guard policy.isEligibleForAutomaticRequest(
                state: state,
                appVersion: appVersion,
                now: now()
            ) else {
                return
            }

            guard canPresentAutomaticReview() else {
                return
            }

            guard presentAutomaticReviewPrompt() else {
                return
            }

            var updatedState = state
            updatedState.lastAutomaticRequestDate = now()
            updatedState.lastAutomaticRequestAppVersion = appVersion
            saveState(updatedState)
        }
    }

    public func requestManualReview() {
        performOnMain { [self] in
            let configuration = AppReviewConfiguration(bundle: bundle)
            if let reviewURL = configuration.appStoreWriteReviewURL {
                open(url: reviewURL)
                return
            }

            requestSystemReview()
        }
    }

#if DEBUG
    public func debugResetReviewState() {
        defaults.removeObject(forKey: stateKey)
    }
#endif

    private var appVersion: String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let version, let build, !version.isEmpty, !build.isEmpty {
            return "\(version)-\(build)"
        }
        if let version, !version.isEmpty {
            return version
        }
        if let build, !build.isEmpty {
            return build
        }
        return "0"
    }

    private var stateKey: String {
        let bundleIdentifier = bundle.bundleIdentifier ?? "main"
        return "NanomouseReviewKit.AppReviewState.\(bundleIdentifier)"
    }

    private func loadState() -> AppReviewState {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? decoder.decode(AppReviewState.self, from: data) else {
            return AppReviewState()
        }
        return state
    }

    private func saveState(_ state: AppReviewState) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    private func requestSystemReview() {
        #if canImport(UIKit)
        if let windowScene = activeWindowScene() {
            SKStoreReviewController.requestReview(in: windowScene)
            return
        }
        SKStoreReviewController.requestReview()
        #else
        SKStoreReviewController.requestReview()
        #endif
    }

    @discardableResult
    private func presentAutomaticReviewPrompt() -> Bool {
        #if canImport(AppKit)
        guard NSApp != nil else { return false }
        #endif
        requestSystemReview()
        return true
    }

    private func canPresentAutomaticReview() -> Bool {
        #if canImport(UIKit)
        guard let windowScene = activeWindowScene() else {
            return false
        }

        let visibleWindow = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
        let rootViewController = visibleWindow?.rootViewController
        return rootViewController?.presentedViewController == nil
        #else
        return NSApp != nil
        #endif
    }

    private func open(url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    private func performOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    #if canImport(UIKit)
    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }

    private func topViewController(from rootViewController: UIViewController) -> UIViewController {
        if let navigationController = rootViewController as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return topViewController(from: visibleViewController)
        }
        if let tabBarController = rootViewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return topViewController(from: selectedViewController)
        }
        if let presentedViewController = rootViewController.presentedViewController {
            return topViewController(from: presentedViewController)
        }
        return rootViewController
    }
    #endif
}

private struct AppReviewPromptStrings {
    let title: String
    let message: String
    let rateButtonTitle: String
    let laterButtonTitle: String

    static var current: AppReviewPromptStrings {
        for identifier in Locale.preferredLanguages + [Locale.autoupdatingCurrent.identifier, Locale.current.identifier] {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("ja") {
                return AppReviewPromptStrings(
                    title: "NanoMouse は役に立っていますか？",
                    message: "よろしければ、数秒だけ時間を取って App Store で評価してください。",
                    rateButtonTitle: "評価する",
                    laterButtonTitle: "あとで"
                )
            }
            if normalized.hasPrefix("zh-hant") ||
                normalized.hasPrefix("zh_hant") ||
                normalized.hasPrefix("zh-tw") ||
                normalized.hasPrefix("zh_tw") ||
                normalized.hasPrefix("zh-hk") ||
                normalized.hasPrefix("zh_hk") ||
                normalized.contains("hant") {
                return AppReviewPromptStrings(
                    title: "喜歡 NanoMouse 嗎？",
                    message: "如果 NanoMouse 對你有幫助，請花幾秒鐘到 App Store 給我們評分。",
                    rateButtonTitle: "去評分",
                    laterButtonTitle: "稍後"
                )
            }
            if normalized.hasPrefix("zh") {
                return AppReviewPromptStrings(
                    title: "喜欢 NanoMouse 吗？",
                    message: "如果 NanoMouse 对你有帮助，请花几秒钟到 App Store 给我们评分。",
                    rateButtonTitle: "去评分",
                    laterButtonTitle: "稍后"
                )
            }
            if normalized.hasPrefix("en") {
                return AppReviewPromptStrings(
                    title: "Enjoying NanoMouse?",
                    message: "If NanoMouse has been helpful, please take a few seconds to rate it on the App Store.",
                    rateButtonTitle: "Rate NanoMouse",
                    laterButtonTitle: "Later"
                )
            }
        }
        return AppReviewPromptStrings(
            title: "Enjoying NanoMouse?",
            message: "If NanoMouse has been helpful, please take a few seconds to rate it on the App Store.",
            rateButtonTitle: "Rate NanoMouse",
            laterButtonTitle: "Later"
        )
    }
}
