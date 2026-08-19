import XCTest
@testable import Remaindr

/// Exercises SettingStore against a temporary home directory: no real ~/.remaindr,
/// no Keychain, no network.
final class SettingStoreTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("setting-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeStore() -> SettingStore {
        SettingStore(home: home)
    }

    private func permissions(of path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    func testFreshInstallCreatesDirectoryAndFileWithTightModes() throws {
        _ = makeStore()
        let directory = home.appendingPathComponent(".remaindr").path
        let file = home.appendingPathComponent(".remaindr/setting.json").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: file))
        XCTAssertEqual(try permissions(of: directory), 0o700)
        XCTAssertEqual(try permissions(of: file), 0o600)
    }

    func testRoundTripKeepsValuesAcrossInstances() throws {
        let store = makeStore()
        store.setApiKey("sk-test-zai", for: .zai)
        store.mutate { $0.refreshIntervalMinutes = 12 }

        // A second instance over the same home reads the same file.
        let reread = SettingStore(home: home)
        XCTAssertEqual(reread.apiKey(for: .zai), "sk-test-zai")
        XCTAssertEqual(reread.load().refreshIntervalMinutes, 12)
    }

    func testEmptyKeyRemovesEntry() throws {
        let store = makeStore()
        store.setApiKey("sk-test-zai", for: .zai)
        store.setApiKey("  ", for: .zai)
        XCTAssertFalse(store.hasApiKey(for: .zai))
        XCTAssertNil(store.load().apiKeys)
    }

    func testLegacyDotfileIsMigratedAsideAndDecoded() throws {
        let legacy = home.appendingPathComponent(".remaindr")
        let payload = #"{"refreshIntervalMinutes":7,"menuBarProvider":"deepseek","allowBilledClaudeProbe":true,"keychainAccessibilityUpgraded":true,"lastUpdateCheckAt":123.0}"#
        try Data(payload.utf8).write(to: legacy)

        let store = SettingStore(home: home)

        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".remaindr.old").path))
        XCTAssertEqual(store.load().refreshIntervalMinutes, 7)
        XCTAssertEqual(store.load().menuBarProvider, "deepseek")
        XCTAssertEqual(store.load().allowBilledClaudeProbe, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".remaindr/setting.json").path))
    }

    func testCorruptedFileYieldsDefaultsNotCrash() throws {
        let store = makeStore()
        try Data("not json at all".utf8)
            .write(to: home.appendingPathComponent(".remaindr/setting.json"))
        XCTAssertEqual(store.load(), SettingFile())
    }

    func testConcurrentMutationsDoNotClobberEachOther() async throws {
        let store = makeStore()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<50 { store.mutate { $0.refreshIntervalMinutes = i } }
            }
            group.addTask {
                for i in 0..<50 { store.mutate { $0.menuBarProvider = i.isMultiple(of: 2) ? "zai" : "claude" } }
            }
        }
        // The last writer of EACH field wins its own field; neither field is lost.
        XCTAssertNotNil(store.load().refreshIntervalMinutes)
        XCTAssertNotNil(store.load().menuBarProvider)
    }
}
