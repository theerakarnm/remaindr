import XCTest
@testable import Remaindr

/// Pins the version comparison the update checker depends on. The load-bearing case
/// is `testMissingComponentsCompareAsZero`: the app ships `1.0` and its matching
/// release is tagged `v1.0.0`, so a comparison without zero-padding would tell every
/// current user that an update exists.
final class AppVersionTests: XCTestCase {

    func testLeadingVIsOptional() {
        XCTAssertEqual(AppVersion("v1.2.3"), AppVersion("1.2.3"))
        XCTAssertEqual(AppVersion("V1.2.3"), AppVersion("1.2.3"))
    }

    func testMissingComponentsCompareAsZero() {
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertEqual(AppVersion("1"), AppVersion("1.0.0.0"))
    }

    func testOrdering() {
        XCTAssertLessThan(AppVersion("1.0")!, AppVersion("1.1")!)
        XCTAssertLessThan(AppVersion("1.9")!, AppVersion("1.10")!)
        XCTAssertLessThan(AppVersion("1.99.99")!, AppVersion("2.0")!)
        XCTAssertGreaterThan(AppVersion("v1.0.1")!, AppVersion("1.0")!)
    }

    func testNonNumericInputFailsToParse() {
        XCTAssertNil(AppVersion("1.0-beta"))
        XCTAssertNil(AppVersion("nightly"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("1..0"))
        XCTAssertNil(AppVersion("1.2.3.4.5"))
        XCTAssertNil(AppVersion("1.٢"))
    }

    func testDescriptionDropsTheLeadingV() {
        XCTAssertEqual(AppVersion("v1.2.3")!.description, "1.2.3")
        XCTAssertEqual("\(AppVersion("2.0")!)", "2.0")
    }
}
