import Foundation

public struct AppReviewState: Codable, Equatable {
    public var firstLaunchDate: Date?
    public var successfulUseCount: Int
    public var lastAutomaticRequestDate: Date?
    public var lastAutomaticRequestAppVersion: String?

    public init(
        firstLaunchDate: Date? = nil,
        successfulUseCount: Int = 0,
        lastAutomaticRequestDate: Date? = nil,
        lastAutomaticRequestAppVersion: String? = nil
    ) {
        self.firstLaunchDate = firstLaunchDate
        self.successfulUseCount = successfulUseCount
        self.lastAutomaticRequestDate = lastAutomaticRequestDate
        self.lastAutomaticRequestAppVersion = lastAutomaticRequestAppVersion
    }
}

public struct AppReviewConfiguration: Equatable {
    public static let appStoreIDInfoKey = "NanomouseAppStoreID"

    public let appStoreID: String

    public init(appStoreID: String = "") {
        self.appStoreID = appStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(bundle: Bundle) {
        let rawValue = bundle.object(forInfoDictionaryKey: Self.appStoreIDInfoKey) as? String ?? ""
        self.init(appStoreID: rawValue)
    }

    public var appStoreWriteReviewURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}

public struct AppReviewPolicy {
    public var minimumInstallAgeDays: Int
    public var minimumSuccessfulUses: Int
    public var automaticCooldownDays: Int

    public init(
        minimumInstallAgeDays: Int = 7,
        minimumSuccessfulUses: Int = 8,
        automaticCooldownDays: Int = 90
    ) {
        self.minimumInstallAgeDays = minimumInstallAgeDays
        self.minimumSuccessfulUses = minimumSuccessfulUses
        self.automaticCooldownDays = automaticCooldownDays
    }

    public func isEligibleForAutomaticRequest(
        state: AppReviewState,
        appVersion: String,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard state.successfulUseCount >= minimumSuccessfulUses else {
            return false
        }

        guard let firstLaunchDate = state.firstLaunchDate else {
            return false
        }

        guard daysElapsed(since: firstLaunchDate, now: now, calendar: calendar) >= minimumInstallAgeDays else {
            return false
        }

        if state.lastAutomaticRequestAppVersion == appVersion {
            return false
        }

        if let lastAutomaticRequestDate = state.lastAutomaticRequestDate,
           daysElapsed(since: lastAutomaticRequestDate, now: now, calendar: calendar) < automaticCooldownDays {
            return false
        }

        return true
    }

    private func daysElapsed(since date: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: date, to: now).day ?? 0
    }
}
