# Setting-File Credentials Implementation Plan

> **Run with:** `/execute-plan docs/plans/2026-08-19-setting-file-credentials.md` - the runner that ticks these
> checkboxes and honours the track/merge layout below.
>
> **For the executing agent:** Implement this plan in order, in a single worktree, from the repo root.
> Steps use checkbox (`- [ ]`) syntax for tracking; tick them as you go.
> Run the `## Preflight` checks BEFORE task 1 and report anything down.
>
> The code inside Steps is a reference implementation, not compiled text.
> When a tool rejects it the tool wins: correct minimally, keep the intent, and record a `> Deviation:` line under the step.

**Goal:** Move every credential and setting out of the macOS Keychain and the `~/.remaindr` dotfile into a single `~/.remaindr/setting.json` (directory 0700, file 0600), and keep Claude's exact `/usage` numbers via a manually connected OAuth token that is read from the Keychain at most twice per connection cycle.

**Architecture:** A new `SettingStore` owns `~/.remaindr/setting.json` as one locked read-modify-write file shared by `Preferences` (non-secret settings) and the providers (API keys, Claude OAuth token).
Providers keep their exact current shape - a store injected at init, credentials read at call time inside `fetch` - so only the store behind the seam changes.
`KeychainStore` is deleted; its single surviving duty, reading Claude Code's OAuth credential, becomes `ClaudeCodeCredential.readAccessToken()`, called only by the manual Connect action and one automatic retry.
A stored `invalid` flag ends all automatic Keychain reads until the user signs in to Claude Code and clicks Connect again.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, Foundation file IO (`Data.write(options: .atomic)`), Security framework (one `SecItemCopyMatching`), XCTest.

**Spec:** none - planned from conversation. The requirements, quoted from the owner: "Instead of store apikey or credential to the keychain. You have to store the apikey into the app configure file locate in the ~/.remaindr this folder will store all of the app configuation, logs, cached. After install the app should able to write every file in this folder. credential or setting should in the ~/.remaindr/setting.json"; keys: "start fresh" (no migration of stored keys); logs/cache subdirectories: "create ondemand"; Claude: "read the claude only once to get the token then save to the configuration. but after the token expired, them begging the access to the keychain to get the token again. If begging the token twice, but still cannot call api marked it invalid token, so user should generate new token of claude then manually click connect to claude again."

**Base commit:** `6d111c339082be2518be9cae1163cbc0bc407168`, working tree clean, `xcodebuild build` and `xcodebuild test` both green (27 tests, 0 failures) at this sha.
Every line reference, anchor, and "already exists" claim below describes THIS tree.
When an anchor does not match, the executor runs `git log --oneline 6d111c3..HEAD` to tell "the plan was wrong" apart from "the file moved on".

**Confidence:** 9/10. Rubric arithmetic: start at 10; every `Consumes:` entry carries a full signature (0); every Patterns-to-Mirror SOURCE was read at its exact lines while planning and copied (0); every `Verify - Human:` has a paired proxy (0); every NOT-building entry that cuts a requirement carries a `file:line` or a direct owner decision (0); the one schema change (`SettingFile`) lists every consumer by task (0); every Preflight command was actually executed while planning (outputs pasted below) (0); no parallel tracks exist (0). One judgement deduction of 1: `SettingStore`'s write path (atomic write plus explicit permission set) is reference code no compiler checks before Task 1 lands, mitigated by the permissions assertions in `SettingStoreTests`.

**NOT building:**

- Migrating existing Keychain keys into `setting.json`. The owner chose "start fresh". Users re-paste z.ai/DeepSeek keys and click Connect for Claude.
- Deleting the orphaned Keychain items (`com.theerakarn.Remaindr`, accounts `zai`/`deepseek`). Left in place deliberately; Task 6 documents in the README that they can be removed by hand in Keychain Access. No code reads them after Task 5 (proof: `grep -rn "keychain" Remaindr/Remaindr --include="*.swift"` after Task 5 returns only `ClaudeCodeCredential.swift`).
- Creating `~/.remaindr/logs/` or `~/.remaindr/cache/`. The owner chose "create ondemand": no logging or caching feature exists in this change, so no empty directories are pre-created.
- Renaming `ProviderKind.keychainAccount` (ProviderStatus.swift, anchor `var keychainAccount: String?`) to something like `credentialKey`. The strings ("zai", "deepseek", "anthropic") become the setting.json keys, so only the name would change, and the rename fans out into `KeychainStore.swift` (until Task 5 deletes it), `SettingStore.swift`, and docs. The doc comment is updated instead (Task 4).
- Sandbox entitlements of any kind. `Remaindr/Remaindr.entitlements` is an empty `<dict/>` and stays that way; an unsandboxed app can already create and write `~/.remaindr`.
- Any change to the `UsageProvider` protocol, `fetch(now:)`, or the provider row UI in `DropdownPanel` (repo rule: ask before changing the protocol shape).
- Developer ID signing, notarization changes, or touching `make-dmg.sh` / `.github/workflows/ci.yml`.
- Obfuscating or encrypting the keys inside `setting.json`. The owner explicitly chose a plaintext config file; the 0700/0600 permissions are the entire mitigation, recorded honestly in the Task 6 security-audit addendum.

## Global Constraints

- Build with zero warnings: every `Verify - Run:` passes `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, matching `.github/workflows/ci.yml`.
- No third-party Swift packages, no new dependencies (AGENTS.md "Hard rules").
- The `UsageProvider` protocol shape does not change; providers keep `fetch(now: Date) async throws -> ProviderStatus`.
- One provider failing must never blank or zero another provider's row (AGENTS.md "Hard rules").
- API keys and the Claude OAuth token live only in `~/.remaindr/setting.json`: never in `UserDefaults`, never in a log line, never in an error message, never committed.
- `~/.remaindr` is created with mode `0700`; `setting.json` is written with mode `0600`.
- The Keychain is touched only by `ClaudeCodeCredential.readAccessToken()`, only from the manual Connect action and the single automatic retry after an auth rejection, at most twice per connection cycle.
- The app has zero `print`/`NSLog`/`os_log` calls today (verified by grep across `Remaindr/Remaindr`); the new code keeps it that way.
- New `.swift` files are picked up automatically: both targets use `fileSystemSynchronizedGroups` (`Remaindr/Remaindr.xcodeproj/project.pbxproj:88` and `:109`). Never hand-edit `project.pbxproj` to register a file.
- Collapsed menu bar label stays within ~14 characters (untouched by this plan, but binding on any edit that strays).
- Only the requested change: no onboarding, no extra settings, no logging/cache features.
- Markdown edits put each full sentence on its own line (owner instruction in `~/.prime/agent/AGENTS.md`).
- Never write the em dash character in any file; use "-".

## Patterns to Mirror

### Naming: optional-field Codable config schema
SOURCE: `Remaindr/Remaindr/Models/Preferences.swift`, anchor `private struct ConfigFile: Codable`, ~L10-17
```swift
    /// Every field is optional on purpose. `ConfigFileStore.load` decodes with `try?`, so a
    /// single non-optional field missing from an older file would throw and silently reset
    /// *all* settings to their defaults. Optional fields let each key fall back on its own.
    private struct ConfigFile: Codable {
        var refreshIntervalMinutes: Int?
        var menuBarProvider: String?
        var allowBilledClaudeProbe: Bool?
        var keychainAccessibilityUpgraded: Bool?
        var lastUpdateCheckAt: Double?
    }
```
`SettingFile` in Task 1 copies this all-optional contract verbatim, because `setting.json` must survive being read by an older build and must let each field fall back independently.

### Concurrency: locked process-wide store
SOURCE: `Remaindr/Remaindr/Keychain/KeychainStore.swift`, anchor `private final class SecretCache`, ~L20-43
```swift
private final class SecretCache: @unchecked Sendable {
    static let shared = SecretCache()

    private let lock = NSLock()
    private var entries: [String: Result<String?, KeychainError>] = [:]

    func value(forKey key: String, read: () -> Result<String?, KeychainError>) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        ...
    }
```
`SettingStore` mirrors `SecretCache`: `final class`, `@unchecked Sendable`, one `NSLock` held across the whole read-modify-write cycle, a `static let shared`.

### Error handling: typed provider errors with UI text
SOURCE: `Remaindr/Remaindr/Models/ProviderStatus.swift`, anchor `enum ProviderError: Error, Equatable, Sendable`, ~L43-67
```swift
enum ProviderError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    ...
    /// Short text shown next to a stale value. Never contains a key or a token.
    var shortDescription: String {
        switch self {
        case .notConfigured: return "Not configured"
        case .unauthorized: return "Key rejected"
```
Task 4's new `reconnectRequired` case follows this exact shape; `DropdownPanel.swift:78` renders `error.shortDescription` and needs no change.

### Providers: credentials read at call time from an injected store
SOURCE: `Remaindr/Remaindr/Providers/DeepSeekProvider.swift`, anchor `func fetch(now: Date) async throws -> ProviderStatus`, ~L29-33
```swift
    func fetch(now: Date) async throws -> ProviderStatus {
        guard let key = try keychain.value(for: kind), !key.isEmpty else {
            throw ProviderError.notConfigured
        }
```
Tasks 3-4 swap `keychain.value(for: kind)` for `settings.apiKey(for: kind)` and nothing else about this shape changes.

### Tests: pure XCTest with literal payloads and injected behavior
SOURCE: `Remaindr/RemaindrTests/UpdateCheckerTests.swift`, anchor `final class UpdateCheckerTests: XCTestCase`, ~L1-30
```swift
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
```
New tests copy this style: no network, no real Keychain, behavior injected as closures or temp directories.

## Preflight

### DURABLE - true until the repo itself changes

- [Repo is green at base] - Evidence: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData build` ended `** BUILD SUCCEEDED **` and the same command with `test` ended `** TEST SUCCEEDED ** - Executed 27 tests, with 0 failures` at `6d111c3`. - Consequence: every task's Verify can demand a green build and suite.
- [Both targets auto-include new files] - Evidence: `fileSystemSynchronizedGroups` at `project.pbxproj:88` (app) and `:109` (tests). - Consequence: Tasks 1 and 4 create files without touching the project file.
- [App is unsandboxed] - Evidence: `Remaindr/Remaindr/Remaindr.entitlements` is `<dict/>`. - Consequence: creating and writing `~/.remaindr` needs no entitlement change.
- [No logging exists anywhere in app sources] - Evidence: `grep -rn "print\|NSLog\|os_log" Remaindr/Remaindr --include="*.swift"` returns nothing. - Consequence: the "never logged" constraint is a held state, not a repair.
- [Existing tests never touch Preferences, providers' stores, or the network] - Evidence: the four test files exercise `AppVersion`, `CollapsedLabelText`, `UpdateChecker.parse`, `UpdateStatusText` only. - Consequence: Tasks 2-5 do not break existing test code.

### PERISHABLE - recapture before task 1

- [`~/.remaindr` exists as a FILE on this machine] - Check: `test -f ~/.remaindr && ! test -d ~/.remaindr && echo "legacy dotfile present"` - Needed by: Task 1 (migration path is exercised for real at first launch), End-to-end verification. While planning it printed `legacy dotfile present` and its content was the five non-secret settings fields (`keychainAccessibilityUpgraded` among them); it has never contained a key. If it is absent or already a directory at execution time, the fresh-install path applies and the `.remaindr.old` assertion in End-to-end verification is skipped.
- [Two orphaned Keychain items exist, accounts `zai` and `deepseek` under service `com.theerakarn.Remaindr`] - Check: `security dump-keychain | grep -c "com.theerakarn.Remaindr"` (attributes only; never add `-w` or `find-generic-password -w` - that reads secret data and prompts) - Needed by: nothing in the code; Task 6's README note tells the user these exist and can be deleted. Planning value: 2.
- [`Claude Code-credentials` Keychain item exists and was modified recently] - Check: `security find-generic-password -s "Claude Code-credentials" > /dev/null 2>&1 && echo present` (attributes-only query; no secret read, no prompt) - Needed by: the End-to-end Connect check (a Human item). Planning value: present, `mdat` within days of planning, proving Claude Code rotates this item regularly. If absent: the Connect E2E box stays unticked and is reported "awaiting human"; the unit tests in Task 4 still cover the flow.
- [Xcode toolchain works from this checkout] - Check: `xcodebuild -version` prints `Xcode 26.6` - Needed by: every Verify step. Planning output: `Xcode 26.6, Build version 17F113`.
- [Shell helpers for the E2E Manual items exist] - Check: `which python3 osascript open` prints three paths - Needed by: End-to-end verification Manual item 2 and both Human proxies. Planning output: `/opt/homebrew/bin/python3` (3.14.3), `/usr/bin/osascript`, `/usr/bin/open`.

## Execution

**Tracks:** single sequential track - Tasks 1 through 6 in order.
The change is one storage-contract migration whose slices share `ProviderStore.swift`, `ProviderStatus.swift`, and `SettingStore.swift`; parallel worktrees would collide on those files, so the plan runs in one worktree with no leases.

**Shared files:** none across parallel tracks (there are no parallel tracks). `UI/ProviderStore.swift` is modified by Tasks 3 and 4, and `Remaindr/Remaindr/Models/ProviderStatus.swift` by Task 4 only; both are sequenced.

**Worktree setup:** none - run in the current checkout.

**Teardown:** none.

---

### Track A (sequential)

#### Task 1: `SettingStore` - the `~/.remaindr/setting.json` owner

**Files:**
- Create: `Remaindr/Remaindr/Models/SettingStore.swift`
- Test: `Remaindr/RemaindrTests/SettingStoreTests.swift`

**Interfaces:**
- Consumes: `ProviderKind.keychainAccount: String?` (exists at `Remaindr/Remaindr/Models/ProviderStatus.swift`, anchor `var keychainAccount: String?`; values `"anthropic"`, `"zai"`, `"deepseek"`).
- Produces (consumed by Tasks 2-5):
  - `struct SettingFile: Codable, Equatable` with fields `refreshIntervalMinutes: Int?`, `menuBarProvider: String?`, `allowBilledClaudeProbe: Bool?`, `lastUpdateCheckAt: Double?`, `apiKeys: [String: String]?`, `claudeOAuth: ClaudeOAuthSetting?`
  - `struct ClaudeOAuthSetting: Codable, Equatable` with fields `accessToken: String?`, `invalid: Bool?`, and an init `ClaudeOAuthSetting(accessToken: String?, invalid: Bool?)`
  - `final class SettingStore: @unchecked Sendable` with `static let shared: SettingStore`, `init(directoryName: String = ".remaindr", fileName: String = "setting.json", home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default)`, `func load() -> SettingFile`, `func mutate(_ change: (inout SettingFile) -> Void)`, `func apiKey(for kind: ProviderKind) -> String?`, `func hasApiKey(for kind: ProviderKind) -> Bool`, `func setApiKey(_ value: String?, for kind: ProviderKind)`, `var claudeOAuth: ClaudeOAuthSetting { get }`, `func setClaudeOAuth(_ value: ClaudeOAuthSetting)`

**Gotcha:** `Data.write(to:options:.atomic)` does not reliably carry `attributes` through its temp-file rename on every macOS release, so the mode is set again explicitly after the write; `SettingStoreTests` asserts the final mode, not the write call.

**Steps:**
- [ ] Step 1: Create `Remaindr/Remaindr/Models/SettingStore.swift` with exactly this content:
      ```swift
      import Foundation

      /// The complete on-disk shape of ~/.remaindr/setting.json. Every field is optional so a
      /// file written by an older build decodes with per-field fallbacks instead of throwing
      /// and resetting everything, the same contract the previous dotfile always had.
      /// The old dotfile (same path, a file not a directory) decodes as a subset: its
      /// `keychainAccessibilityUpgraded` key is ignored as an unknown field.
      struct SettingFile: Codable, Equatable {
          var refreshIntervalMinutes: Int?
          var menuBarProvider: String?
          var allowBilledClaudeProbe: Bool?
          var lastUpdateCheckAt: Double?
          /// API keys by provider credential key ("zai", "deepseek", "anthropic").
          /// Secrets: never logged, never surfaced in an error. Guarded by the
          /// directory's 0700 and the file's 0600.
          var apiKeys: [String: String]?
          /// The Claude Code OAuth token copied out by the Connect action, plus the
          /// lockout flag that ends automatic Keychain re-reads once it stops working.
          var claudeOAuth: ClaudeOAuthSetting?
      }

      /// Connection state for Claude's account usage source. `invalid == true` means the
      /// token was rejected and re-begging the Keychain did not help: only the manual
      /// Connect action reads the Keychain again.
      struct ClaudeOAuthSetting: Codable, Equatable {
          var accessToken: String?
          var invalid: Bool?

          init(accessToken: String? = nil, invalid: Bool? = nil) {
              self.accessToken = accessToken
              self.invalid = invalid
          }
      }

      /// Owns ~/.remaindr/setting.json: the one file that holds both settings and secrets.
      /// All writes are locked read-modify-write cycles so `Preferences` (settings) and the
      /// providers (secrets) share the file without clobbering each other. App code must use
      /// `SettingStore.shared` so every writer goes through the same lock; tests inject
      /// their own instance pointed at a temporary home.
      final class SettingStore: @unchecked Sendable {
          static let shared = SettingStore()

          private let lock = NSLock()
          private let home: URL
          private let directoryURL: URL
          private let settingURL: URL
          private let fileManager: FileManager

          init(directoryName: String = ".remaindr",
               fileName: String = "setting.json",
               home: URL = FileManager.default.homeDirectoryForCurrentUser,
               fileManager: FileManager = .default) {
              self.home = home
              self.directoryURL = home.appendingPathComponent(directoryName, isDirectory: true)
              self.settingURL = directoryURL.appendingPathComponent(fileName)
              self.fileManager = fileManager
              bootstrap()
          }

          func load() -> SettingFile {
              lock.lock()
              defer { lock.unlock() }
              return readUnlocked() ?? SettingFile()
          }

          /// Locked read-modify-write. The change sees the file's current contents and the
          /// result is persisted atomically with mode 0600 before the lock is released.
          func mutate(_ change: (inout SettingFile) -> Void) {
              lock.lock()
              defer { lock.unlock() }
              var value = readUnlocked() ?? SettingFile()
              change(&value)
              writeUnlocked(value)
          }

          // MARK: - Credentials

          func apiKey(for kind: ProviderKind) -> String? {
              guard let key = kind.keychainAccount else { return nil }
              guard let value = load().apiKeys?[key] else { return nil }
              return value.isEmpty ? nil : value
          }

          func hasApiKey(for kind: ProviderKind) -> Bool {
              apiKey(for: kind) != nil
          }

          /// A nil or empty value removes the entry, mirroring the old Keychain `set` rule
          /// where an empty paste cleared the item.
          func setApiKey(_ value: String?, for kind: ProviderKind) {
              guard let key = kind.keychainAccount else { return }
              let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
              mutate { file in
                  var keys = file.apiKeys ?? [:]
                  if trimmed.isEmpty {
                      keys.removeValue(forKey: key)
                  } else {
                      keys[key] = trimmed
                  }
                  file.apiKeys = keys.isEmpty ? nil : keys
              }
          }

          var claudeOAuth: ClaudeOAuthSetting {
              load().claudeOAuth ?? ClaudeOAuthSetting()
          }

          func setClaudeOAuth(_ value: ClaudeOAuthSetting) {
              mutate { $0.claudeOAuth = value }
          }

          // MARK: - File plumbing

          private func readUnlocked() -> SettingFile? {
              guard let data = try? Data(contentsOf: settingURL) else { return nil }
              return try? JSONDecoder().decode(SettingFile.self, from: data)
          }

          private func writeUnlocked(_ value: SettingFile) {
              guard let data = try? JSONEncoder().encode(value) else { return }
              try? data.write(to: settingURL, options: .atomic)
              // `.atomic` does not carry attributes through the rename on every macOS
              // release, so the mode is forced here; the 0700 directory already bounds
              // who can reach the file between write and rename.
              try? fileManager.setAttributes([.posixPermissions: 0o600],
                                             ofItemAtPath: settingURL.path)
          }

          /// First-run bootstrap: create ~/.remaindr (0700) and an empty setting.json
          /// (0600) so the folder exists and is writable from the first launch, and clear
          /// the way when the name is still occupied by the pre-setting.json dotfile.
          private func bootstrap() {
              var isDirectory: ObjCBool = false
              let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
              if exists && isDirectory.boolValue {
                  try? fileManager.setAttributes([.posixPermissions: 0o700],
                                                 ofItemAtPath: directoryURL.path)
                  if !fileManager.fileExists(atPath: settingURL.path) {
                      writeUnlocked(SettingFile())
                  }
                  return
              }
              if exists {
                  migrateDotfileAside()
                  return
              }
              try? fileManager.createDirectory(at: directoryURL,
                                               withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
              writeUnlocked(SettingFile())
          }

          /// The previous build stored settings in a `~/.remaindr` FILE; this build needs
          /// that name for the directory. The old file carries only non-secret settings
          /// (keys always lived in the Keychain), and its schema is a subset of
          /// `SettingFile`, so it is decoded, moved aside to `~/.remaindr.old`, and its
          /// fields become the first `setting.json` contents. The owner chose "start
          /// fresh" for keys only; settings survive.
          private func migrateDotfileAside() {
              // Decode BEFORE moving the file: `readUnlocked` reads the directory's
              // setting.json, a path that cannot exist yet, so it would hand back nil
              // here and every migrated setting would be lost.
              let legacy = (try? Data(contentsOf: directoryURL))
                  .flatMap { try? JSONDecoder().decode(SettingFile.self, from: $0) }
              let aside = home.appendingPathComponent(".remaindr.old")
              try? fileManager.removeItem(at: aside)
              try? fileManager.moveItem(at: directoryURL, to: aside)
              try? fileManager.createDirectory(at: directoryURL,
                                               withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
              writeUnlocked(legacy ?? SettingFile())
          }
      }
      ```
- [ ] Step 2: Create `Remaindr/RemaindrTests/SettingStoreTests.swift`:
      ```swift
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
      ```
- [ ] Step 3: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -3` - Expected: `** TEST SUCCEEDED **` with `SettingStoreTests` in the executed suites (6 new tests) and the pre-existing 27 tests still passing.
- [ ] Step 4: Commit - `git commit -m "feat: add SettingStore owning ~/.remaindr/setting.json with 0700/0600 modes"`

#### Task 2: `Preferences` on `SettingStore`; dotfile store deleted

**Files:**
- Modify: `Remaindr/Remaindr/Models/Preferences.swift` (anchor: `private let store: ConfigFileStore<ConfigFile>`, ~L20)
- Delete: `Remaindr/Remaindr/Models/ConfigFileStore.swift`
- Modify: `Remaindr/Remaindr/App/RemaindrApp.swift` (anchor: `if !preferences.keychainAccessibilityUpgraded {`, ~L12)

**Interfaces:**
- Consumes: `SettingStore.shared`, `load()`, `mutate(_:)` (full signatures in Task 1 Produces).
- Produces (consumed by Task 5 wiring, already existing callers): `Preferences` keeps its public surface (`refreshIntervalMinutes`, `menuBarProvider`, `allowBilledClaudeProbe`, `lastUpdateCheck`) and LOSES `keychainAccessibilityUpgraded` (only consumer is the `RemaindrApp` block this task deletes).

**Steps:**
- [ ] Step 1: In `Preferences.swift`, replace the `ConfigFile` struct, both initializers, and `persist()` so the class reads and writes through a shared `SettingStore`. Reference implementation of the changed members:
      ```swift
      /// Non-secret settings only. Secrets (API keys, the Claude OAuth token) live in the
      /// same setting.json but are accessed through SettingStore's credential accessors,
      /// never through this type.
      @MainActor
      @Observable
      final class Preferences {
          private let store: SettingStore

          convenience init() {
              self.init(store: .shared)
          }

          init(store: SettingStore) {
              self.store = store
              let loaded = store.load()
              let stored = loaded.refreshIntervalMinutes ?? 5
              self.refreshIntervalMinutes = min(max(stored, 1), 60)
              self.menuBarProvider = loaded.menuBarProvider.flatMap(ProviderKind.init(rawValue:)) ?? .claude
              self.allowBilledClaudeProbe = loaded.allowBilledClaudeProbe ?? false
              self.lastUpdateCheck = loaded.lastUpdateCheckAt.map(Date.init(timeIntervalSince1970:))
          }
      ```
      and:
      ```swift
          private func persist() {
              store.mutate { file in
                  file.refreshIntervalMinutes = refreshIntervalMinutes
                  file.menuBarProvider = menuBarProvider.rawValue
                  file.allowBilledClaudeProbe = allowBilledClaudeProbe
                  file.lastUpdateCheckAt = lastUpdateCheck?.timeIntervalSince1970
              }
          }
      ```
      Delete the `keychainAccessibilityUpgraded` property and its `didSet`. Keep the doc comments on the surviving properties; update the class doc comment as shown.
- [ ] Step 2: `git rm Remaindr/Remaindr/Models/ConfigFileStore.swift`.
- [ ] Step 3: In `RemaindrApp.swift`, delete this block (anchor `if !preferences.keychainAccessibilityUpgraded {`):
      ```swift
          if !preferences.keychainAccessibilityUpgraded {
              KeychainStore().upgradeAccessibility()
              preferences.keychainAccessibilityUpgraded = true
          }
      ```
      leaving `let preferences = Preferences()` followed directly by `let store = ProviderStore(preferences: preferences)`.
      `KeychainStore` itself still exists until Task 5; do not touch it here.
- [ ] Step 4: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -2` - Expected: `** BUILD SUCCEEDED **`, zero warnings.
- [ ] Step 5: Verify - Run: same command with `test` - Expected: `** TEST SUCCEEDED **`, all suites green (no test referenced `Preferences` or `keychainAccessibilityUpgraded`; verified by grep in Preflight).
- [ ] Step 6: Commit - `git commit -m "refactor: back Preferences with SettingStore and drop the dotfile store"`

#### Task 3: z.ai and DeepSeek providers read their key from `setting.json`

**Files:**
- Modify: `Remaindr/Remaindr/Providers/ZAIProvider.swift` (anchor: `init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared)`, ~L24)
- Modify: `Remaindr/Remaindr/Providers/DeepSeekProvider.swift` (anchor: `init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared)`, ~L15)
- Modify: `Remaindr/Remaindr/UI/ProviderStore.swift` (anchor: `var anyConfigured: Bool`, ~L25)

**Interfaces:**
- Consumes: `SettingStore.shared`, `apiKey(for:)`, `hasApiKey(for:)` (Task 1 Produces).
- Produces (consumed by Task 5's UI and by this task's `ProviderStore`): `ZAIProvider.init(settings: SettingStore = .shared, session: URLSession = .shared)`, `DeepSeekProvider.init(settings: SettingStore = .shared, session: URLSession = .shared)`, `ProviderStore.init(settings: SettingStore = .shared, preferences: Preferences)`.

**Steps:**
- [ ] Step 1: In `ZAIProvider.swift`: change the stored property `private let keychain: KeychainStore` to `private let settings: SettingStore`; change the initializer to
      ```swift
      init(settings: SettingStore = .shared, session: URLSession = .shared) {
          self.settings = settings
          self.session = session
      }
      ```
      and in `fetch` change
      ```swift
          guard let key = try keychain.value(for: kind), !key.isEmpty else {
      ```
      to
      ```swift
          guard let key = settings.apiKey(for: kind), !key.isEmpty else {
      ```
- [ ] Step 2: Apply the identical three edits to `DeepSeekProvider.swift` (same anchors: stored property `private let keychain: KeychainStore`, its `init`, and the `guard let key = try keychain.value(for: kind), !key.isEmpty else` line in `fetch`).
- [ ] Step 3: In `ProviderStore.swift`: change `private let keychain: KeychainStore` to `private let settings: SettingStore`; change the initializer to
      ```swift
      init(settings: SettingStore = .shared, preferences: Preferences) {
          self.settings = settings
          self.preferences = preferences
          self.slots = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, ProviderSlot()) })
      }
      ```
      In `anyConfigured`, replace the first line of the body with
      ```swift
          if settings.hasApiKey(for: .zai) || settings.hasApiKey(for: .deepseek) { return true }
      ```
      keeping the `~/.claude/projects` directory check as the fallback return. In `provider(for:)`, construct `.zai` and `.deepseek` with `settings: settings, session: PinnedSession.shared`; leave the `.claude` case untouched this task (it still compiles against `KeychainStore`, which still exists).
- [ ] Step 4: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -2` - Expected: `** BUILD SUCCEEDED **` - note: `SettingsView` still uses `KeychainStore` for save/clear badges and still compiles; that migrates in Task 5.
- [ ] Step 5: Verify - Run: same command with `test` - Expected: `** TEST SUCCEEDED **`.
- [ ] Step 6: Commit - `git commit -m "refactor: z.ai and DeepSeek read their keys from setting.json"`

#### Task 4: Claude account source - Connect flow, saved token, invalid lockout

**Files:**
- Create: `Remaindr/Remaindr/Keychain/ClaudeCodeCredential.swift`
- Modify: `Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift` (anchor: `static func accessToken(keychain: KeychainStore) -> String?`, ~L29)
- Modify: `Remaindr/Remaindr/Providers/ClaudeProvider.swift` (anchor: `init(keychain: KeychainStore = KeychainStore(),`, ~L32)
- Modify: `Remaindr/Remaindr/Models/ProviderStatus.swift` (anchor: `enum ProviderError: Error, Equatable, Sendable {`, ~L50)
- Modify: `Remaindr/Remaindr/UI/ProviderStore.swift` (anchor: `case .claude:` inside `provider(for:)`, ~L34)
- Test: `Remaindr/RemaindrTests/ClaudeAccountUsageTests.swift`

Six files, one commit: this is a single contract slice. `ClaudeAccountUsage` stops taking a `KeychainStore`, `ClaudeProvider` changes initializer signature, and `ProviderStore` constructs it - none of these compiles without the others, and splitting them would create a red interval.

**Interfaces:**
- Consumes: `SettingStore` credential accessors and `ClaudeOAuthSetting` (Task 1 Produces).
- Produces (consumed by Task 5):
  - `enum ClaudeCodeCredential` with `static let service: String` and `static func readAccessToken() -> String?`
  - `ClaudeAccountUsage.fetch(token: String, session: URLSession) async throws -> ClaudeAccountUsage` (was `fetch(keychain:session:)`; body unchanged except the token arrives as a parameter)
  - `ClaudeAccountUsage.connect(settings: SettingStore, readCredential: () -> String? = ClaudeCodeCredential.readAccessToken, verify: @Sendable (String) async -> Bool) async -> Bool`
  - `ClaudeAccountUsage.recoverExpiredToken(settings: SettingStore, readCredential: () -> String? = ClaudeCodeCredential.readAccessToken) -> String?`
  - `ProviderError.reconnectRequired` with `shortDescription` `"Reconnect Claude in Settings"`
  - `ClaudeProvider.init(settings: SettingStore = .shared, session: URLSession = .shared, projectsDirectory: URL = ClaudeProvider.defaultProjectsDirectory, allowBilledProbe: Bool = false)`

**Gotcha:** `recoverExpiredToken` must compare the fresh Keychain token against the stored one and mark the connection invalid when they are equal - Claude Code has not rotated yet, so retrying would burn a Keychain prompt per refresh interval forever (the exact prompt storm this project already fixed once).

**Steps:**
- [ ] Step 1: Create `Remaindr/Remaindr/Keychain/ClaudeCodeCredential.swift`:
      ```swift
      import Foundation
      import Security

      /// The single remaining Keychain touchpoint. Claude Code stores its OAuth
      /// credential as a JSON blob in the login Keychain under this service name; the
      /// manual Connect action copies the token out once into setting.json, and after
      /// that only the expiry retry ever comes back here.
      enum ClaudeCodeCredential {
          static let service = "Claude Code-credentials"

          /// One call can surface one login-keychain password prompt. Callers must be
          /// the manual Connect action or the single automatic retry after an auth
          /// rejection - never a periodic refresh.
          /// Returns nil for every failure: missing item, denied read, or a blob with
          /// no access token. The token is never logged and never persisted anywhere
          /// except setting.json.
          static func readAccessToken() -> String? {
              let query: [String: Any] = [
                  kSecClass as String: kSecClassGenericPassword,
                  kSecAttrService as String: service,
                  kSecReturnData as String: true,
                  kSecMatchLimit as String: kSecMatchLimitOne,
              ]
              var result: CFTypeRef?
              guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                    let data = result as? Data,
                    let text = String(data: data, encoding: .utf8),
                    let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                    let oauth = root["claudeAiOauth"] as? [String: Any],
                    let token = oauth["accessToken"] as? String,
                    !token.isEmpty
              else { return nil }
              return token
          }
      }
      ```
- [ ] Step 2: In `ClaudeAccountUsage.swift`:
      - Delete `static func accessToken(keychain:)` (its JSON parsing moved into `ClaudeCodeCredential.readAccessToken`).
      - Delete `static let credentialService` and `enum AccountUsageError` (both dead after this change: `ClaudeCodeCredential.service` replaces the first, and `noCredential` is never thrown once `fetch` takes the token directly - grep confirms their only references are inside this file).
      - Change `fetch` to take the token directly:
      ```swift
      static func fetch(token: String, session: URLSession) async throws -> ClaudeAccountUsage {
          var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
          request.httpMethod = "GET"
          request.timeoutInterval = 15
          request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
          // ... the existing body from `let (data, response): (Data, URLResponse)` down
          // through `return usage` stays exactly as it is today.
      }
      ```
      The 401/403 branch's `keychain.invalidateForeign(...)` call is deleted (there is no cache to invalidate any more); the comment explaining rotation moves to `recoverExpiredToken`.
      - Add the two flow functions:
      ```swift
      /// The manual Connect action. Keychain read #1; if the server rejects that
      /// token, Keychain read #2; if that still cannot call the API, the stored token
      /// is marked invalid and the user is told to sign in to Claude Code and click
      /// Connect again. Returns true when the account source is usable right now.
      static func connect(settings: SettingStore,
                          readCredential: () -> String? = ClaudeCodeCredential.readAccessToken,
                          verify: @Sendable (String) async -> Bool) async -> Bool {
          guard let first = readCredential() else {
              markConnectionInvalid(in: settings)
              return false
          }
          settings.setClaudeOAuth(ClaudeOAuthSetting(accessToken: first, invalid: false))
          if await verify(first) { return true }
          guard let second = readCredential() else {
              markConnectionInvalid(in: settings)
              return false
          }
          settings.setClaudeOAuth(ClaudeOAuthSetting(accessToken: second, invalid: false))
          if await verify(second) { return true }
          markConnectionInvalid(in: settings)
          return false
      }

      /// The one automatic Keychain re-read, run only after the server rejected the
      /// saved token. A nil return means "give up": no credential, the connection is
      /// already locked out, or the Keychain still holds the same token Claude Code
      /// has not rotated yet - retrying that would burn a Keychain prompt every
      /// refresh interval, the exact storm this project fixed once already. Every
      /// give-up path marks the connection invalid here, so no caller has to remember to.
      static func recoverExpiredToken(settings: SettingStore,
                                      readCredential: () -> String? = ClaudeCodeCredential.readAccessToken) -> String? {
          let stored = settings.claudeOAuth
          guard let oldToken = stored.accessToken, !(stored.invalid ?? false) else { return nil }
          guard let fresh = readCredential(), fresh != oldToken else {
              markConnectionInvalid(in: settings)
              return nil
          }
          settings.setClaudeOAuth(ClaudeOAuthSetting(accessToken: fresh, invalid: false))
          return fresh
      }

      /// Internal rather than private: `ClaudeProvider` calls it after a recovered
      /// token is itself rejected by the server - the second failed beg that ends
      /// the cycle.
      static func markConnectionInvalid(in settings: SettingStore) {
          let stored = settings.claudeOAuth
          settings.setClaudeOAuth(ClaudeOAuthSetting(accessToken: stored.accessToken, invalid: true))
      }
      ```
- [ ] Step 3: In `ProviderStatus.swift`, add to `ProviderError` (after `case untrustedServer`):
      ```swift
          /// The saved Claude OAuth token was rejected and re-reading the Keychain did not
          /// help. The user must sign in to Claude Code and click Connect again in Settings.
          case reconnectRequired
      ```
      and to `shortDescription`:
      ```swift
          case .reconnectRequired: return "Reconnect Claude in Settings"
      ```
      Also update the doc comment on `ProviderKind.keychainAccount` (anchor `var keychainAccount: String?`) to:
      ```swift
          /// Credential key in setting.json (a historical name: these strings were the
          /// Keychain account names before credentials moved to the config file).
          /// Claude's entry is the billed-header-probe API key; its primary source is
          /// the OAuth token stored by the Connect action.
      ```
      The property name and values stay unchanged.
- [ ] Step 4: In `ClaudeProvider.swift`:
      - Replace `private let keychain: KeychainStore` with `private let settings: SettingStore` and the initializer with:
      ```swift
      init(settings: SettingStore = .shared,
           session: URLSession = .shared,
           projectsDirectory: URL = ClaudeProvider.defaultProjectsDirectory,
           allowBilledProbe: Bool = false) {
          self.settings = settings
          self.session = session
          self.projectsDirectory = projectsDirectory
          self.allowBilledProbe = allowBilledProbe
      }
      ```
      - Restructure `fetch`'s account-source section to:
      ```swift
      func fetch(now: Date) async throws -> ProviderStatus {
          // Door 1: the account endpoint, authenticated with the token the Connect
          // action saved. Unavailable (never connected, or locked out as invalid)
          // simply means "fall through", exactly like every other account failure.
          // An untrusted server is the exception: surfacing it is the only way a pin
          // failure becomes visible instead of silently downgrading.
          if let status = try? await accountUsageStatus(now: now) {
              return status
          }
          do {
              return try await accountUsageStatus(now: now)
          } catch ProviderError.untrustedServer {
              throw ProviderError.untrustedServer
          } catch ProviderError.unauthorized {
              // The saved token was rejected. One Keychain re-read, one retry; if
              // either fails the connection is marked invalid and automatic
              // Keychain reads stop until the user clicks Connect again.
              if let fresh = ClaudeAccountUsage.recoverExpiredToken(settings: settings) {
                  if let status = try? await accountUsage(withToken: fresh, now: now) {
                      return status
                  }
                  // The rotated token was rejected too: the second failed beg.
                  ClaudeAccountUsage.markConnectionInvalid(in: settings)
              }
          } catch {
          }
      ```
      The recovery marking is single-sourced: `recoverExpiredToken` marks invalid on its own give-up paths (no credential, already locked out, or same unrotated token), and the snippet above marks it when a recovered token is itself rejected. Then continue into the existing local-files scan and probe fallback unchanged, except:
      - The billed-probe guard becomes `guard allowBilledProbe, let key = settings.apiKey(for: kind), !key.isEmpty else`.
      - The final "nothing worked" exit becomes:
      ```swift
          let oauth = settings.claudeOAuth
          if let invalid = oauth.invalid, invalid, oauth.accessToken != nil {
              throw ProviderError.reconnectRequired
          }
          throw ProviderError.notConfigured
      ```
      - Split the current `accountUsageStatus(now:)` into `private func accountUsage(withToken token: String, now: Date) async throws -> ProviderStatus` plus a `private func accountUsageStatus(now: Date) async throws -> ProviderStatus` that reads the stored token, throws when it is absent or flagged invalid, and delegates to `accountUsage(withToken:)`. The recovery path reuses `accountUsage(withToken:)`.
      The `try? then do/catch` pair above is the reference for "untrusted server still surfaces"; the executor may collapse it to a single `do/catch` with an `isUntrusted` helper if the compiler rejects the double call - intent: untrustedServer is NEVER swallowed, every other account error falls through.
      The two helpers it depends on, written out:
      ```swift
      /// Reads the token saved by Connect. Absent or flagged invalid both throw, which
      /// the caller treats as "account source unavailable, fall through" - never as an
      /// error for the user (the reconnect-required signal is raised only at the very
      /// end of fetch, after every source has failed).
      private func accountUsageStatus(now: Date) async throws -> ProviderStatus {
          let oauth = settings.claudeOAuth
          guard let token = oauth.accessToken, !(oauth.invalid ?? false) else {
              throw ProviderError.notConfigured
          }
          return try await accountUsage(withToken: token, now: now)
      }

      private func accountUsage(withToken token: String, now: Date) async throws -> ProviderStatus {
          let usage: ClaudeAccountUsage
          do {
              usage = try await ClaudeAccountUsage.fetch(token: token, session: session)
          } catch {
              throw mapTransportFailure(error)
          }
          return ProviderStatus(
              kind: .claude,
              reading: .fraction(used: usage.fiveHourUsedFraction, resetsAt: usage.fiveHourResetsAt),
              detail: "Plan limits reported by claude.ai (same source as Claude Code /usage)",
              fetchedAt: now,
              weekly: usage.weekly
          )
      }
      ```
- [ ] Step 5: In `ProviderStore.swift` `provider(for:)`, change the `.claude` case to:
      ```swift
          case .claude:
              return ClaudeProvider(settings: settings,
                                    session: PinnedSession.shared,
                                    allowBilledProbe: preferences.allowBilledClaudeProbe)
      ```
- [ ] Step 6: Create `Remaindr/RemaindrTests/ClaudeAccountUsageTests.swift`:
      ```swift
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
      ```
- [ ] Step 7: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -3` - Expected: `** TEST SUCCEEDED **`; `ClaudeAccountUsageTests` executes 7 tests, 0 failures; all earlier suites still green. `SettingsView` still compiles against the not-yet-deleted `KeychainStore`.
- [ ] Step 8: Commit - `git commit -m "feat: Claude account source connects once, saves the token, and locks out after failed recovery"`

#### Task 5: Settings UI on `SettingStore`; `KeychainStore` deleted

**Files:**
- Modify: `Remaindr/Remaindr/UI/SettingsView.swift` (anchor: `private let keychain = KeychainStore()`, ~L8)
- Delete: `Remaindr/Remaindr/Keychain/KeychainStore.swift`

**Interfaces:**
- Consumes: `SettingStore` credential accessors (Task 1), `ClaudeAccountUsage.connect(settings:readCredential:verify:)` and `fetch(token:session:)` (Task 4 Produces, full signatures above).
- Produces: none (leaf task for code).

**Gotcha:** after this task nothing in the app may reference `KeychainStore` or `SecretCache`. `grep -rn "KeychainStore\|SecretCache" Remaindr/Remaindr --include="*.swift"` must return only hits inside `ClaudeCodeCredential.swift`'s own doc comment if any - ideally zero.

**Steps:**
- [ ] Step 1: In `SettingsView.swift`, replace `private let keychain = KeychainStore()` with `private let settings = SettingStore.shared` and add state for the Claude connection:
      ```swift
      @State private var claudeConnected = false
      @State private var claudeInvalid = false
      @State private var isConnectingClaude = false
      ```
- [ ] Step 2: Replace the Claude `LabeledContent("Claude")` block (anchor `Text("Reads ~/.claude/projects. No key needed.")`) with:
      ```swift
      LabeledContent("Claude") {
          HStack {
              claudeBadge
              Button(claudeConnected ? "Reconnect" : "Connect") {
                  Task { await connectClaude() }
              }
              .disabled(isConnectingClaude)
          }
      }
      ```
      and add the supporting members:
      ```swift
      @ViewBuilder
      private var claudeBadge: some View {
          if claudeInvalid {
              Label("Invalid token", systemImage: "exclamationmark.triangle.fill")
                  .labelStyle(.iconOnly)
                  .foregroundStyle(.orange)
                  .help("Sign in to Claude Code, then click Connect again")
          } else if claudeConnected {
              Label("Connected", systemImage: "checkmark.circle.fill")
                  .labelStyle(.iconOnly)
                  .foregroundStyle(.green)
                  .help("Reading plan limits with the token saved in setting.json")
          } else {
              Label("Not connected", systemImage: "circle")
                  .labelStyle(.iconOnly)
                  .foregroundStyle(.secondary)
                  .help("Connect copies Claude Code's sign-in token into setting.json, once")
          }
      }

      /// The manual Connect action. Prompts for the login keychain password at most
      /// twice; on failure the badge turns to "Invalid token" and stays there until
      /// the user signs in to Claude Code and clicks Connect again.
      private func connectClaude() async {
          isConnectingClaude = true
          defer { isConnectingClaude = false }
          let ok = await ClaudeAccountUsage.connect(
              settings: settings,
              verify: { token in
                  // PinnedSession, not .shared: this request carries the OAuth token,
                  // and every credential-bearing request must fail closed on a pin
                  // mismatch (PinnedSession.swift documents the invariant).
                  (try? await ClaudeAccountUsage.fetch(token: token, session: PinnedSession.shared)) != nil
              })
          reloadClaudeState()
          if !ok {
              message = "Could not connect. Sign in to Claude Code, then click Connect again."
          } else {
              message = nil
              scheduler.reschedule()
          }
      }

      private func reloadClaudeState() {
          let oauth = settings.claudeOAuth
          claudeConnected = oauth.accessToken != nil && !(oauth.invalid ?? false)
          claudeInvalid = oauth.invalid == true && oauth.accessToken != nil
      }
      ```
      Call `reloadClaudeState()` in the existing `.onAppear` (anchor `savedKinds = Set(`).
- [ ] Step 3: In the same file, swap every remaining `keychain` use: `statusBadge`'s two `.help` strings change "saved in Keychain" to "saved in setting.json" and "No \(kind.displayName) key saved" stays; `save(_:)` becomes
      ```swift
      private func save(_ kind: ProviderKind) {
          settings.setApiKey(draftKeys[kind] ?? "", for: kind)
          draftKeys[kind] = ""
          savedKinds = Set(ProviderKind.allCases.filter { settings.hasApiKey(for: $0) })
          scheduler.reschedule()
          message = nil
      }
      ```
      `clear(_:)` becomes
      ```swift
      private func clear(_ kind: ProviderKind) {
          settings.setApiKey(nil, for: kind)
          draftKeys[kind] = ""
          savedKinds = Set(ProviderKind.allCases.filter { settings.hasApiKey(for: $0) })
          scheduler.reschedule()
          message = nil
      }
      ```
      the `onAppear` line becomes `savedKinds = Set(ProviderKind.allCases.filter { settings.hasApiKey(for: $0) })`, and the two `message = "Could not save the key to the Keychain."` / `"Could not clear the key from the Keychain."` error lines are deleted (file writes through `SettingStore` cannot throw user-actionably here). The key row caption text stays as is otherwise.
- [ ] Step 4: `git rm Remaindr/Remaindr/Keychain/KeychainStore.swift` (the `Keychain/` directory then contains only `ClaudeCodeCredential.swift`).
- [ ] Step 5: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -3` - Expected: `** TEST SUCCEEDED **`.
- [ ] Step 6: Verify - Run: `grep -rn "KeychainStore\|SecretCache" Remaindr/Remaindr --include="*.swift"; echo "exit=$?"` - Expected: no output and `exit=1` (zero references to the deleted types).
- [ ] Step 7: Commit - `git commit -m "feat: Settings saves keys to setting.json and connects Claude once; delete KeychainStore"`

#### Task 6: Documentation follows the new storage policy

**Files:**
- Modify: `AGENTS.md` (anchor: `## Hard rules`, ~L60)
- Modify: `README.md` (anchor: `## Privacy & security`)
- Modify: `FUTURE_FEATURES.md` (anchor: the paragraph `Ground rules that still apply to every item below (see \`AGENTS.md\`):`, ~L7-9; the rule itself is the bullet at L9)
- Modify: `SECURITY_AUDIT.md` (anchor: `# SECURITY_AUDIT.md - Security Audit Report`)

**Interfaces:**
- Consumes: the shipped behavior of Tasks 1-5.
- Produces: none.

**Steps:**
- [ ] Step 1: `AGENTS.md`:
      - Replace the hard rule "API keys live in the macOS Keychain only. Never `UserDefaults`, never plaintext, never logged, never committed." with:
        "Credentials (API keys and the Claude OAuth token) live in `~/.remaindr/setting.json` only: directory mode 0700, file mode 0600. Never `UserDefaults`, never logged, never committed. The macOS Keychain is read only by `ClaudeCodeCredential.readAccessToken()` - from the manual Connect action and the single expiry retry, at most twice per connection cycle."
      - Update the Stack line "Keychain Services (via `Security` framework) for credential storage" to "One `Security` framework call (`ClaudeCodeCredential`) that copies Claude Code's OAuth token into `setting.json` on Connect".
      - In the architecture tree, replace `Keychain/
    KeychainStore.swift  # read/write wrapper, no plaintext fallback` with `Keychain/
    ClaudeCodeCredential.swift  # the one Keychain read (Claude Connect)` and add `Models/SettingStore.swift  # owns ~/.remaindr/setting.json` under `Models/`.
      - Rewrite the Claude provider-data bullet 1 to describe the new lifecycle: Connect reads the Keychain once and saves the token to `setting.json`; refreshes use the saved token; one automatic re-read after a 401; an `invalid` flag stops all automatic reads until the user signs in to Claude Code and clicks Connect again.
      - Keep every sentence on its own line; no em dashes.
- [ ] Step 2: `README.md`:
      - Feature bullet at ~L38: "🔒 **Keychain-backed credentials** — API keys are never stored in plaintext or in `UserDefaults`" becomes "🔒 **Config-file credentials** — API keys live in `~/.remaindr/setting.json` (0700 directory, 0600 file), never in `UserDefaults`".
      - Setup step 2 becomes: paste the API key - keys are written to `~/.remaindr/setting.json` (mode 0600, in a 0700 directory).
      - Add a setup step for Claude: click **Connect** once; macOS may ask for the login keychain password (at most twice); after that the app uses the saved token.
      - Privacy & security: replace "API keys are stored exclusively in the macOS Keychain, scoped to this app" with the setting.json policy including the file modes, and state plainly that a process running as your user can read the file - the tradeoff chosen for zero keychain prompts.
      - Project structure: `Keychain/KeychainStore.swift` line becomes `Keychain/ClaudeCodeCredential.swift  # the one Keychain read (Claude Connect)`; add `Models/SettingStore.swift` under `Models/`. The bare `  Keychain/` tree line stays: the directory keeps its name.
      - The CLAUDE.md pointer sentence at ~L152: "provider protocol boundaries, Keychain-only rule, etc." becomes "provider protocol boundaries, the setting.json credential rule, etc.".
      - Troubleshooting table row at ~L177: "macOS asks for your login keychain password | Expected once per key after installing or updating the app - see below" becomes "Claude shows Reconnect Claude in Settings | The saved token expired and re-reading it did not help - see below" (replacing the row rather than leaving it pointing at the removed section).
      - Troubleshooting: replace the "Why macOS asks for the keychain password" section with "Claude shows `Reconnect Claude in Settings`" - sign in to Claude Code (run `claude` and log in) so it writes a fresh credential, then click Connect in Remaindr; and add one line: versions before this change stored keys in the login Keychain under service `com.theerakarn.Remaindr`; those items are no longer read and can be deleted in Keychain Access.
- [ ] Step 3: `FUTURE_FEATURES.md`:
      - Change the ground rule (the bullet at ~L9) "API keys live in the macOS Keychain only, never in `UserDefaults`, plaintext, logs, or commits." to "Credentials live in `~/.remaindr/setting.json` only (0700 directory, 0600 file), never in `UserDefaults`, logs, or commits. The Keychain is read only by the Claude Connect flow."
      - Item at ~L16: "Developer ID signed Release builds so keychain grants survive updates and `get-task-allow` never ships (audit F-01; blocked on obtaining a signing identity)." becomes "Developer ID signed Release builds so the Connect flow's keychain grant survives updates and `get-task-allow` never ships (audit F-01; blocked on obtaining a signing identity)." - signing is still wanted; only the grant's reason changes.
      - Item at ~L65: the decision item "stop reading Claude Code's foreign keychain credential in favor of an explicit user-pasted token (audit F-08; deliberately kept because removing it deletes a feature)" is now resolved differently - mark it `[x]` and append "; resolved 2026-08-19: the credential is still read, but only by the manual Connect action and one expiry retry, at most twice per connection cycle."
- [ ] Step 4: `SECURITY_AUDIT.md`: insert a dated addendum immediately under the title:
      "**Addendum 2026-08-19 (owner decision):** credential storage moved from the login Keychain to `~/.remaindr/setting.json` (directory 0700, file 0600). The threat-model trade is explicit: any process running as the user can now read z.ai/DeepSeek keys and the Claude OAuth token from the file, where the keychain ACL previously gated reads behind a prompt. Accepted in exchange for eliminating all periodic keychain prompts. F-03's remediation (accessibility class) is superseded for this app's own items; F-08 is narrowed - the foreign `Claude Code-credentials` item is still read, but only on the manual Connect action and one expiry retry, at most twice per connection cycle."
- [ ] Step 5: Verify - Run: `grep -n "Keychain" README.md AGENTS.md FUTURE_FEATURES.md | grep -vi "ClaudeCodeCredential\|Connect\|Keychain Access\|login keychain password\|Keychain is read only\|one Keychain read"` - Expected: exactly two output lines, both bare tree lines reading `  Keychain/` (one in AGENTS.md's architecture tree, one in README.md's project structure - the directory keeps its name). Any other line means a Keychain mention survived unedited.
- [ ] Step 6: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -2` - Expected: `** BUILD SUCCEEDED **` (docs cannot break the build; this guards against accidental source edits).
- [ ] Step 7: Commit - `git commit -m "docs: document setting.json credential storage and the Claude Connect flow"`

## Failure handling summary

- **`~/.remaindr` exists as something that is neither a plain file nor a directory the app can replace** (a symlink, or an unwritable path) - Detect: `SettingStore` bootstrap finds `fileExists == false` for the directory after `migrateDotfileAside` or `createDirectory` (both `try?`), and End-to-end verification's `stat` fails. Respond: STOP after Task 1's E2E check, report the path's `ls -la` output, and ask the owner; do not invent a fallback location.
- **Tests that hit the real home directory instead of the injected temp home** - Detect: a `SettingStore()` default constructed inside a test, or a test that suddenly prompts for the login keychain password. Respond: every test constructs `SettingStore(home:)` against `FileManager.default.temporaryDirectory`; no test may call `ClaudeCodeCredential.readAccessToken()` for real.
- **The executing agent is asked for the login keychain password at any point outside the two End-to-end Human steps** - Detect: a security prompt appears during build/test. Respond: that means a test reached the real Keychain or the real home - a defect, not a step; fix the test before continuing.

## End-to-end verification

Run after all tasks are merged, from the repo root.

- [ ] Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -3` - Expected: `** TEST SUCCEEDED **` with 40 total tests (27 pre-existing + 6 `SettingStoreTests` + 7 `ClaudeAccountUsageTests`), 0 failures.
- [ ] Manual: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData build > /dev/null 2>&1 && open build/DerivedData/Build/Products/Release/Remaindr.app && sleep 5 && stat -f '%Sp %N' ~/.remaindr ~/.remaindr/setting.json` - Expected: `drwx------ .../.remaindr` and `-rw------- .../setting.json`; because this machine carries the legacy dotfile, `test -f ~/.remaindr.old && echo migrated` also prints `migrated`, and `python3 -c "import json,os; json.load(open(os.path.expanduser('~/.remaindr/setting.json'))); print('valid json')"` prints `valid json` with the previous refresh interval preserved (check with `python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.remaindr/setting.json'))).get('refreshIntervalMinutes'))"` - it must equal the pre-launch value from Preflight). Quit the app afterwards (`osascript -e 'quit app "Remaindr"'`).
  Rollback (runtime, not git): this launch migrates the real `~/.remaindr` dotfile on this machine. To undo by hand, quit the app first, then `rm -rf ~/.remaindr && mv ~/.remaindr.old ~/.remaindr`.
- [ ] Manual: `grep -c "KeychainStore\|SecretCache" $(find Remaindr/Remaindr -name '*.swift') | grep -v ':0' ; echo "exit=$?"` - Expected: no file lists a nonzero count; `exit=1`.
- [ ] 👤 Human: open Settings, paste a real z.ai key, click Save - Expected: the z.ai row shows the green "Set" badge, and the dropdown's z.ai row stops saying "Not configured" after a refresh - Proxy: `Remaindr/RemaindrTests/SettingStoreTests.testRoundTripKeepsValuesAcrossInstances` proves the save path, and after the human acts the agent runs `python3 -c "import json,os; print('zai' in json.load(open(os.path.expanduser('~/.remaindr/setting.json'))).get('apiKeys', {}))"` and expects `True` (presence only - the key value is never printed).
- [ ] 👤 Human: in Settings, click Connect under Claude - Expected: at most one login-keychain password prompt (answer it), then the badge shows "Connected" in green, and the Claude row in the dropdown shows plan-limit percentages again - Proxy: `ClaudeAccountUsageTests` proves the whole connect/retry/invalid state machine without the keychain, and after the human acts the agent runs `python3 -c "import json,os; o=json.load(open(os.path.expanduser('~/.remaindr/setting.json'))).get('claudeOAuth',{}); print(bool(o.get('accessToken')) and not o.get('invalid'))"` and expects `True` (shape only - the token is never printed).
