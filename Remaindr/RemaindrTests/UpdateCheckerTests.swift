import XCTest
@testable import Remaindr

/// Exercises the pure parser against literal payloads, the same way the provider
/// clients are tested: no network, no credential.
final class UpdateCheckerTests: XCTestCase {

    private func json(_ text: String) -> Data {
        Data(text.utf8)
    }

    private var current: AppVersion { AppVersion("1.0")! }

    func testMatchingTagIsUpToDate() throws {
        // The live case today: the app ships 1.0 and the release is tagged v1.0.0.
        let data = json(#"{"tag_name":"v1.0.0","draft":false,"prerelease":false}"#)
        let status = try UpdateChecker.parse(data, currentVersion: current)
        XCTAssertEqual(status, .upToDate(current: current))
    }

    func testNewerTagOffersAnUpdate() throws {
        let data = json(#"{"tag_name":"v1.1.0","draft":false,"prerelease":false}"#)
        let status = try UpdateChecker.parse(data, currentVersion: current)
        XCTAssertEqual(status, .updateAvailable(latest: AppVersion("1.1.0")!))
    }

    func testOlderTagIsUpToDate() throws {
        let data = json(#"{"tag_name":"v0.9.0","draft":false,"prerelease":false}"#)
        let status = try UpdateChecker.parse(data, currentVersion: current)
        XCTAssertEqual(status, .upToDate(current: current))
    }

    func testMissingDraftAndPrereleaseKeysAreTreatedAsPublished() throws {
        let data = json(#"{"tag_name":"v2.0.0"}"#)
        let status = try UpdateChecker.parse(data, currentVersion: current)
        XCTAssertEqual(status, .updateAvailable(latest: AppVersion("2.0.0")!))
    }

    func testDraftIsNotOffered() {
        let data = json(#"{"tag_name":"v9.9.9","draft":true,"prerelease":false}"#)
        XCTAssertThrowsError(try UpdateChecker.parse(data, currentVersion: current)) {
            XCTAssertEqual($0 as? UpdateCheckError, .noRelease)
        }
    }

    func testPrereleaseIsNotOffered() {
        let data = json(#"{"tag_name":"v9.9.9","draft":false,"prerelease":true}"#)
        XCTAssertThrowsError(try UpdateChecker.parse(data, currentVersion: current)) {
            XCTAssertEqual($0 as? UpdateCheckError, .noRelease)
        }
    }

    func testUnparseableTagIsMalformed() {
        let data = json(#"{"tag_name":"nightly","draft":false,"prerelease":false}"#)
        XCTAssertThrowsError(try UpdateChecker.parse(data, currentVersion: current)) {
            XCTAssertEqual($0 as? UpdateCheckError, .malformedResponse("tag_name is not a version"))
        }
    }

    func testMissingTagIsMalformed() {
        let data = json(#"{"draft":false}"#)
        XCTAssertThrowsError(try UpdateChecker.parse(data, currentVersion: current)) {
            XCTAssertEqual($0 as? UpdateCheckError, .malformedResponse("release payload not decodable"))
        }
    }

    func testTheLinkTargetIsAConstantAndNotTakenFromAPayload() {
        XCTAssertEqual(UpdateChecker.releasesPageURL.absoluteString,
                       "https://github.com/theerakarnm/remaindr/releases/latest")
    }

    func testErrorTextLeaksNothing() {
        XCTAssertEqual(UpdateCheckError.rateLimited.shortDescription, "Rate limited")
        XCTAssertEqual(UpdateCheckError.serverError(status: 500).shortDescription, "Server error 500")
        XCTAssertEqual(UpdateCheckError.malformedResponse("tag_name is not a version").shortDescription,
                       "Bad response")
    }
}
