import XCTest
@testable import NanomouseReviewKit

final class AppReviewPolicyTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testRejectsWhenSuccessfulUseCountBelowThreshold() {
        let policy = AppReviewPolicy(minimumInstallAgeDays: 7, minimumSuccessfulUses: 8, automaticCooldownDays: 90)
        let now = date(year: 2026, month: 3, day: 24)
        let state = AppReviewState(
            firstLaunchDate: date(year: 2026, month: 3, day: 1),
            successfulUseCount: 7
        )

        XCTAssertFalse(policy.isEligibleForAutomaticRequest(state: state, appVersion: "1.0", now: now, calendar: calendar))
    }

    func testRejectsWhenInstallAgeBelowThreshold() {
        let policy = AppReviewPolicy(minimumInstallAgeDays: 7, minimumSuccessfulUses: 8, automaticCooldownDays: 90)
        let now = date(year: 2026, month: 3, day: 24)
        let state = AppReviewState(
            firstLaunchDate: date(year: 2026, month: 3, day: 20),
            successfulUseCount: 8
        )

        XCTAssertFalse(policy.isEligibleForAutomaticRequest(state: state, appVersion: "1.0", now: now, calendar: calendar))
    }

    func testAcceptsWhenThresholdsSatisfied() {
        let policy = AppReviewPolicy(minimumInstallAgeDays: 7, minimumSuccessfulUses: 8, automaticCooldownDays: 90)
        let now = date(year: 2026, month: 3, day: 24)
        let state = AppReviewState(
            firstLaunchDate: date(year: 2026, month: 3, day: 1),
            successfulUseCount: 8
        )

        XCTAssertTrue(policy.isEligibleForAutomaticRequest(state: state, appVersion: "1.0", now: now, calendar: calendar))
    }

    func testRejectsRepeatedAutomaticRequestInSameVersion() {
        let policy = AppReviewPolicy()
        let now = date(year: 2026, month: 3, day: 24)
        let state = AppReviewState(
            firstLaunchDate: date(year: 2025, month: 12, day: 1),
            successfulUseCount: 16,
            lastAutomaticRequestDate: date(year: 2025, month: 12, day: 15),
            lastAutomaticRequestAppVersion: "1.0"
        )

        XCTAssertFalse(policy.isEligibleForAutomaticRequest(state: state, appVersion: "1.0", now: now, calendar: calendar))
    }

    func testRejectsWhenCooldownNotElapsed() {
        let policy = AppReviewPolicy(minimumInstallAgeDays: 7, minimumSuccessfulUses: 8, automaticCooldownDays: 90)
        let now = date(year: 2026, month: 3, day: 24)
        let state = AppReviewState(
            firstLaunchDate: date(year: 2025, month: 12, day: 1),
            successfulUseCount: 16,
            lastAutomaticRequestDate: date(year: 2026, month: 2, day: 1),
            lastAutomaticRequestAppVersion: "0.9"
        )

        XCTAssertFalse(policy.isEligibleForAutomaticRequest(state: state, appVersion: "1.0", now: now, calendar: calendar))
    }

    func testAllowsNewVersionAfterCooldown() {
        let policy = AppReviewPolicy(minimumInstallAgeDays: 7, minimumSuccessfulUses: 8, automaticCooldownDays: 90)
        let now = date(year: 2026, month: 6, day: 24)
        let state = AppReviewState(
            firstLaunchDate: date(year: 2025, month: 12, day: 1),
            successfulUseCount: 16,
            lastAutomaticRequestDate: date(year: 2026, month: 2, day: 1),
            lastAutomaticRequestAppVersion: "1.0"
        )

        XCTAssertTrue(policy.isEligibleForAutomaticRequest(state: state, appVersion: "1.1", now: now, calendar: calendar))
    }

    func testAppStoreWriteReviewURLUsesConfiguredID() {
        let configuration = AppReviewConfiguration(appStoreID: "1234567890")

        XCTAssertEqual(configuration.appStoreWriteReviewURL?.absoluteString, "https://apps.apple.com/app/id1234567890?action=write-review")
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
