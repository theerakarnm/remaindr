import XCTest
@testable import Remaindr

/// Pins the exact update wording. These assertions are the non-visual proxy for the
/// dropdown and Settings rendering that only a human can eyeball.
final class UpdateStatusTextTests: XCTestCase {

    func testCheckingBeatsEveryOtherState() {
        let text = UpdateStatusText.settings(status: .upToDate(current: AppVersion("1.0")!),
                                             error: .offline,
                                             isChecking: true)
        XCTAssertEqual(text, "Checking\u{2026}")
    }

    func testErrorIsReportedWithItsShortDescription() {
        let text = UpdateStatusText.settings(status: nil, error: .rateLimited, isChecking: false)
        XCTAssertEqual(text, "Check failed: Rate limited")
    }

    func testUpToDateShowsTheRunningVersion() {
        let text = UpdateStatusText.settings(status: .upToDate(current: AppVersion("1.0")!),
                                             error: nil,
                                             isChecking: false)
        XCTAssertEqual(text, "Up to date (1.0)")
    }

    func testUpdateAvailableShowsTheNewVersionWithoutTheTagPrefix() {
        let text = UpdateStatusText.settings(status: .updateAvailable(latest: AppVersion("v1.1.0")!),
                                             error: nil,
                                             isChecking: false)
        XCTAssertEqual(text, "Update available: 1.1.0")
    }

    func testNeverCheckedSaysSo() {
        XCTAssertEqual(UpdateStatusText.settings(status: nil, error: nil, isChecking: false),
                       "Not checked yet")
    }

    func testDropdownIsNilWhenThereIsNothingToOffer() {
        XCTAssertNil(UpdateStatusText.dropdown(available: nil))
        XCTAssertEqual(UpdateStatusText.dropdown(available: AppVersion("v2.0")!),
                       "Update available: 2.0")
    }
}
