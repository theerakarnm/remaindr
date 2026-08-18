import XCTest
@testable import Remaindr

/// Smoke tests that exercise app code through the test host. They pin the
/// collapsed-label contract: the string never exceeds `CollapsedLabelText.budget`
/// and degrades to placeholders instead of provider text.
final class CollapsedLabelTextTests: XCTestCase {

    func testNilSlotShowsPlaceholder() {
        XCTAssertEqual(CollapsedLabelText.text(for: nil), "--")
    }

    func testUnconfiguredSlotShowsPlaceholder() {
        var slot = ProviderSlot()
        slot.error = .notConfigured
        XCTAssertEqual(CollapsedLabelText.text(for: slot), "--")
    }

    func testFractionReadingShowsRoundedPercent() {
        let status = ProviderStatus(
            kind: .claude,
            reading: .fraction(used: 0.426, resetsAt: nil),
            detail: "",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        let slot = ProviderSlot(status: status)
        XCTAssertEqual(CollapsedLabelText.text(for: slot), "43%")
    }

    func testBalanceReadingShowsSymbolAndCompactAmount() {
        let status = ProviderStatus(
            kind: .deepseek,
            reading: .balance(amount: 1234.5, currency: "usd"),
            detail: "",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        let slot = ProviderSlot(status: status)
        XCTAssertEqual(CollapsedLabelText.text(for: slot), "$1.2k")
    }

    func testStaleReadingWithErrorAppendsBang() {
        let status = ProviderStatus(
            kind: .zai,
            reading: .fraction(used: 0.5, resetsAt: nil),
            detail: "",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        var slot = ProviderSlot(status: status)
        slot.error = .offline
        XCTAssertEqual(CollapsedLabelText.text(for: slot), "50%!")
    }

    func testLabelNeverExceedsBudget() {
        // An unknown long currency forces the widest possible string.
        let status = ProviderStatus(
            kind: .deepseek,
            reading: .balance(amount: 1_234_567, currency: "WOWSUCHCURRENCY"),
            detail: "",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        let slot = ProviderSlot(status: status)
        let text = CollapsedLabelText.text(for: slot)
        XCTAssertLessThanOrEqual(text.count, CollapsedLabelText.budget)
        XCTAssertTrue(text.hasSuffix("\u{2026}"))
    }
}
