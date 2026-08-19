import XCTest
@testable import Remaindr

/// Exercises the Connect flow and the expiry recovery against a fake credential
/// reader and a fake verifier: no Keychain, no network.
final class ClaudeAccountUsageTests: XCTestCase {
    private var home: URL!
    private var store: SettingStore!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-connect-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store = SettingStore(home: home)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testConnectSucceedsOnFirstRead() async {
        var reads = 0
        let ok = await ClaudeAccountUsage.connect(
            settings: store,
            readCredential: { reads += 1; return "token-1" },
            verify: { _ in true })
        XCTAssertTrue(ok)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(store.claudeOAuth.accessToken, "token-1")
        XCTAssertEqual(store.claudeOAuth.invalid, false)
    }

    func testConnectRetriesOnceWhenServerRejectsFirstToken() async {
        var reads = 0
        let ok = await ClaudeAccountUsage.connect(
            settings: store,
            readCredential: { reads += 1; return "token-\(reads)" },
            verify: { $0 == "token-2" })
        XCTAssertTrue(ok)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(store.claudeOAuth.accessToken, "token-2")
        XCTAssertEqual(store.claudeOAuth.invalid, false)
    }

    func testConnectMarksInvalidWhenSecondTokenAlsoFails() async {
        let ok = await ClaudeAccountUsage.connect(
            settings: store,
            readCredential: { "stale" },
            verify: { _ in false })
        XCTAssertFalse(ok)
        XCTAssertEqual(store.claudeOAuth.invalid, true)
    }

    func testConnectMarksInvalidWhenCredentialMissing() async {
        let ok = await ClaudeAccountUsage.connect(
            settings: store,
            readCredential: { nil },
            verify: { _ in true })
        XCTAssertFalse(ok)
        XCTAssertEqual(store.claudeOAuth.invalid, true)
    }

    func testRecoveryRejectsSameTokenClaudeCodeHasNotRotated() {
        store.setClaudeOAuth(ClaudeOAuthSetting(accessToken: "stale", invalid: false))
        XCTAssertNil(ClaudeAccountUsage.recoverExpiredToken(settings: store,
                                                            readCredential: { "stale" }))
        XCTAssertEqual(store.claudeOAuth.invalid, true)
    }

    func testRecoveryAcceptsRotatedToken() {
        store.setClaudeOAuth(ClaudeOAuthSetting(accessToken: "stale", invalid: false))
        XCTAssertEqual(ClaudeAccountUsage.recoverExpiredToken(settings: store,
                                                              readCredential: { "fresh" }), "fresh")
        XCTAssertEqual(store.claudeOAuth.accessToken, "fresh")
        XCTAssertEqual(store.claudeOAuth.invalid, false)
    }

    func testRecoveryRefusesWhenAlreadyInvalid() {
        store.setClaudeOAuth(ClaudeOAuthSetting(accessToken: "stale", invalid: true))
        XCTAssertNil(ClaudeAccountUsage.recoverExpiredToken(settings: store,
                                                            readCredential: { "fresh" }))
        XCTAssertEqual(store.claudeOAuth.accessToken, "stale")
    }
}
