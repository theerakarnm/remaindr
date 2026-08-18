# Release Trust and Update Checker Implementation Plan

> **Run with:** `/execute-plan docs/plans/2026-08-19-notarization-checksums-update-checker.md` - the runner that ticks these
> checkboxes and honours the track/merge layout below.
>
> **For the executing agent:** Implement this plan in task order in a single
> worktree (see Execution - there is only one track). Steps use checkbox (`- [ ]`)
> syntax for tracking; tick them as you go.
> Run the `## Preflight` checks BEFORE task 1 and report anything down.
>
> **Every fenced code block inside a Step is indented 6 spaces for Markdown list
> continuation.** Dedent by exactly 6 before writing it into a `.swift`, `.sh`, or
> `.md` file. Nothing else about the content changes.

**Goal:** Make a published Remaindr release verifiable end to end - notarized and stapled by `make-dmg.sh`, shipped with a SHA-256 sidecar, and discoverable by a first-party in-app update check against the latest GitHub release.

**Architecture:** Two independent halves that share only documentation.
The release half is entirely shell and Markdown: `make-dmg.sh` gains a fail-fast signing preflight, an asserted notarization verdict, a stapler/Gatekeeper validation pass, and a `.sha256` sidecar computed after stapling; the README stops describing releases as un-notarized and gains a verification recipe.
The app half adds a new `Update/` group of four small Foundation-first types (`AppVersion`, `UpdateChecker`, `UpdateStore`, `UpdateStatusText`) plus two thin view edits, mirroring the existing `ProviderStore` / `DeepSeekProvider.parse` / `CollapsedLabelText` split so comparison and parsing logic stay unit-testable without a running app.

**Tech Stack:** bash with `codesign` / `notarytool` / `stapler` / `spctl` / `shasum`; Swift 6, SwiftUI, `URLSession` + async/await, XCTest. No new dependencies of any kind.

**Spec:** none - planned from conversation, against three unchecked items in `FUTURE_FEATURES.md` "Distribution & trust" and finding **F-02** in `SECURITY_AUDIT.md:54-94`.

**Base commit:** `b6a740d`. Every line reference, anchor, and "already exists" claim below describes THIS tree, with one stated exception: inside Tasks 1 and 2 the `~L` hints for `make-dmg.sh` are pre-edit `b6a740d` positions, and the file grows by roughly 45 lines during Task 1, so Task 2's hints shift accordingly. The anchors are exact strings; grep them and treat the numbers as hints. Note also that this repo runs a background auto-commit daemon which commits plan files on save, so `git log --oneline b6a740d..HEAD` will show several `Add new file:` / `Update ...` commits for THIS plan document. Those touch no source file; ignore them when checking for drift. When an anchor does not match, run `git log --oneline b6a740d..HEAD` to tell "the plan was wrong" apart from "the file moved on".

**Confidence:** 9/10 - the one unresolved uncertainty is that this machine holds zero code-signing identities, so the *Accepted* branch of the notarization block in Task 1 is reference code no agent can execute here; its failure branches, its syntax, and every other task in the plan are agent-verifiable.

**Confidence arithmetic** (rubric from the writing-plans skill, counted against this file, not estimated):

```
10   start
 -0  Consumes: entries without a full signature          (0 found - every Consumes/Produces entry is a full signature)
 -0  Patterns-to-Mirror SOURCEs not verified             (0 - all 8 read from the real files at b6a740d)
 -0  Verify - Human: with no paired proxy                (0 - both 👤 items carry a Proxy: line)
 -0  NOT-building entries cutting a requirement on an
     unproven claim about the codebase                   (0 - F-01's block, the CI file's scope, the v1.0.0
                                                          asset list, and PinnedSession's fail-closed
                                                          behaviour each carry a file:line or a run command)
 -0  tasks touching a schema / inferred type without
     consumers listed                                    (0 - Preferences.ConfigFile is `private`; its one
                                                          consumer is named and grep-verified in Task 6)
 -0  Preflight checks written but never run              (0 - all 13 were executed while planning)
 -0  parallel tracks below the cost floor                (0 - the plan is single-track sequential)
 -1  named residual: the notarized/Accepted path of make-dmg.sh cannot be executed on any
     machine without a Developer ID certificate, so it ships as reviewed reference code
=  9
```


**Validated while planning (not just written):** every Swift file in Tasks 4-8 was applied to a throwaway copy of this repo at `b6a740d` and built - `** TEST SUCCEEDED **`, `Executed 27 tests, with 0 failures`, and `** BUILD SUCCEEDED **` for Release with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, matching the counts each task predicts. The `make-dmg.sh` edits were applied the same way: all three anchors matched exactly, `bash -n` passed, the `REQUIRE_NOTARIZATION=1` gate exited 1 in 0.7s with the quoted message, a full `./make-dmg.sh` run exited 0 and emitted a sidecar matching `^[0-9a-f]{64}  Remaindr-1\.0\.dmg$` that `shasum -c` reported as `OK`, and `hdiutil verify` reported the image VALID. Every `grep` Expected in Tasks 3 and 9 was run against edited copies and returned the stated value. What was NOT validated: the notarized path (no identity), and the two 👤 Human items.

**One deliberate deviation from the writing-plans checklist:** several tasks carry three `Verify - Run:` steps rather than one. Each extra step is a single cheap `grep` with a stated Expected, and no task exceeds three files or one commit, so the intent of the one-verify rule (small tasks) holds while the evidence per task is stronger. Flagged here so it reads as a choice, not an oversight.

**NOT building:**

- Developer ID signing configuration in `project.pbxproj` (`CODE_SIGN_STYLE`, `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`). That is audit **F-01**, recorded in `FUTURE_FEATURES.md` as "blocked on obtaining a signing identity", and Preflight confirms no identity exists. `make-dmg.sh:39-48` already discovers a Developer ID identity at runtime and re-signs with it; that stays the mechanism.
- Auto-download, auto-install, background daemons, delta updates, or a Sparkle-style appcast. The update checker performs one unauthenticated GET and renders a link. Anything that fetches or writes an executable turns this into the third-party-style framework the requirement forbids.
- A GitHub Actions release workflow that runs `make-dmg.sh` and uploads assets. `.github/workflows/ci.yml` is build-and-test only, and automating publication needs signing secrets that do not exist yet.
- Re-cutting or re-uploading the existing `v1.0.0` GitHub release (asset `AIUsageBar-v1.0.0.zip`, confirmed in Preflight). The README instead states plainly that a release without a `.sha256` sidecar predates this pipeline.
- Certificate pinning for `api.github.com`. See Global Constraints - a deliberate decision with a stated reason, not an omission.
- Any change to `UsageProvider`, `ProviderStatus`, `ProviderError`, or `ProviderKind`. The update checker is not a provider.
- A user-facing "check for updates automatically" toggle. Not requested; the 24-hour throttle plus a manual button is the whole surface.
- The app-icon asset catalog item that sits between the checksum and update-checker entries in the same `FUTURE_FEATURES.md` section (`:20`). It was not requested here and shares no code with this work; it stays unticked.

## Global Constraints

- **No third-party Swift packages** (`AGENTS.md`, "Hard rules"). If one seems needed, STOP and ask.
- **The build must succeed with zero warnings** (`AGENTS.md`, "Commands"). CI runs `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (`.github/workflows/ci.yml:21-37`), so a warning is a hard failure, not a nit.
- **The UI talks to providers only through `UsageProvider`, and that protocol's shape does not change** (`AGENTS.md`, "Stop and ask before"). `UpdateChecker` deliberately does NOT conform to `UsageProvider` and does NOT reuse `ProviderError`; an update check is not a provider reading and must not widen that surface.
- **API keys live in the macOS Keychain only** - never `UserDefaults`, plaintext, logs, or commits. Nothing here touches a credential; `Preferences` gains one non-secret timestamp, consistent with that file's own header ("Non-secret settings only", `Remaindr/Remaindr/Models/Preferences.swift:3`).
- **Use `URLSession.shared`, never `PinnedSession.shared`, for the GitHub call.** `PinnedSession.Delegate` is fail-closed: a host absent from `PinnedSession.pins` reaches `return (.cancelAuthenticationChallenge, nil)` (`Remaindr/Remaindr/Providers/PinnedSession.swift:64-67`), so routing the update check through it would cancel every check. Adding an `api.github.com` pin is explicitly rejected: the pins are hand-captured leaf certificate hashes (`PinnedSession.swift:20-34`) and GitHub rotates certificates far more often than this app ships, so a stale pin would silently disable update checking. System trust is the right level because no key or token is sent.
- **The link target is a compile-time constant, never a URL taken from the response.** The GitHub call is unauthenticated and unpinned, so an `html_url` read out of the payload would be an attacker-choosable link the user is invited to click. Link to `https://github.com/theerakarnm/remaindr/releases/latest` and derive nothing from the body but a version string.
- **Never fabricate a number, an endpoint, a field name, or a response shape.** `AGENTS.md` "Hard rules" says "Never invent an endpoint path, field name, or response shape you haven't verified"; the "never a fabricated number" rule is in its "Provider data" section. Applied to documentation here: the README must not describe releases as notarized in a way that misdescribes assets already published.
- **The collapsed menu bar label stays within `CollapsedLabelText.budget = 14` characters.** No task in this plan touches `MenuBarLabel.swift` or `CollapsedLabelText.swift`; the update notice lives in the dropdown and Settings only.
- **Only make the change directly requested** (`AGENTS.md`, "Hard rules"). No onboarding flows, no extra abstractions, no files beyond those in each task's **Files** block.
- **`make-dmg.sh` keeps `set -euo pipefail`** (`make-dmg.sh:10`). Every added command inherits fail-fast and pipefail semantics; write conditionals as `if` blocks rather than `a && b` statements, which `set -e` treats as a failing statement when `a` is false.
- **Stapling must be the last write to the DMG**, as the script already documents at `make-dmg.sh:97-98`. The SHA-256 sidecar is therefore computed after stapling, never before.

## Patterns to Mirror

Follow these exactly; do not invent alternatives. Every snippet is copied verbatim from the file named in its SOURCE comment, at base commit `b6a740d`.

### Naming and file layout

New Swift files go in a new group directory `Remaindr/Remaindr/Update/`, alongside the existing `Providers/`, `Models/`, `Keychain/`, `UI/`, `Refresh/`, `App/`.

**No `project.pbxproj` edit is needed to add a file.** Both targets use file-system-synchronised groups, so any `.swift` file dropped under `Remaindr/Remaindr/` (app) or `Remaindr/RemaindrTests/` (tests) is compiled automatically:

<!-- SOURCE: Remaindr/Remaindr.xcodeproj/project.pbxproj:9-19 -->
```
/* Begin PBXFileSystemSynchronizedRootGroup section */
		AA0000000000000000000010 /* Remaindr */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Remaindr;
			sourceTree = "<group>";
		};
		AA0000000000000000000011 /* RemaindrTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RemaindrTests;
			sourceTree = "<group>";
		};
```

### Networked type: injected session, status classified before decoding, pure static parser

<!-- SOURCE: Remaindr/Remaindr/Providers/DeepSeekProvider.swift:8-19 and :36-66 -->
```swift
struct DeepSeekProvider: UsageProvider {
    let kind: ProviderKind = .deepseek

    private let keychain: KeychainStore
    private let session: URLSession
    private static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

    init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }
    // ...
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportFailure(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("no HTTP response")
        }
        // The 401 body is plain text, so status is classified before decoding.
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw ProviderError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ProviderError.serverError(status: http.statusCode)
        }

        return try Self.parse(data, now: now)
    }
```

Decodable payloads keep the server's raw snake_case field names rather than declaring `CodingKeys`, and the parser is `static` with a doc comment saying why:

<!-- SOURCE: Remaindr/Remaindr/Providers/DeepSeekProvider.swift:20-29 and :68-75 -->
```swift
    private struct Payload: Decodable {
        struct BalanceInfo: Decodable {
            let currency: String
            let total_balance: String
            let granted_balance: String?
            let topped_up_balance: String?
        }
        let is_available: Bool?
        let balance_infos: [BalanceInfo]
    }
    // ...
    /// Pure so a harness can exercise it without a key or a network.
    static func parse(_ data: Data, now: Date) throws -> ProviderStatus {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ProviderError.malformedResponse("balance payload not decodable")
        }
```

### Error enum: `Error, Equatable, Sendable` with a `shortDescription` that leaks nothing

<!-- SOURCE: Remaindr/Remaindr/Models/ProviderStatus.swift:42-67 -->
```swift
/// Every distinct failure the UI must be able to show differently.
enum ProviderError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case offline
    case malformedResponse(String)
    case serverError(status: Int)
    case noActivePlan
    /// The server's certificate chain did not match a pinned certificate.
    case untrustedServer

    /// Short text shown next to a stale value. Never contains a key or a token.
    var shortDescription: String {
        switch self {
        case .notConfigured: return "Not configured"
        case .unauthorized: return "Key rejected"
        case .rateLimited: return "Rate limited"
        case .offline: return "Offline"
        case .malformedResponse: return "Bad response"
        case .serverError(let status): return "Server error \(status)"
        case .noActivePlan: return "No active plan"
        case .untrustedServer: return "Connection untrusted"
        }
    }
}
```

### Observable store: `@MainActor @Observable final class`, `private(set)` state, failure never blanks the last good value

<!-- SOURCE: Remaindr/Remaindr/UI/ProviderStore.swift:11-23 and :79-89 -->
```swift
@MainActor
@Observable
final class ProviderStore {
    private(set) var slots: [ProviderKind: ProviderSlot]

    private let keychain: KeychainStore
    private let preferences: Preferences

    init(keychain: KeychainStore = KeychainStore(), preferences: Preferences) {
        self.keychain = keychain
        self.preferences = preferences
        self.slots = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, ProviderSlot()) })
    }
    // ...
    /// Keeps the previous status on failure. Never writes nil, never writes a zero.
    private func apply(_ result: Result<ProviderStatus, any Error>, to kind: ProviderKind) {
        switch result {
        case .success(let status):
            slots[kind] = ProviderSlot(status: status, error: nil, isRefreshing: slots[kind]?.isRefreshing ?? false)
        case .failure(let error as ProviderError):
            slots[kind, default: ProviderSlot()].error = error
        case .failure:
            slots[kind, default: ProviderSlot()].error = .malformedResponse("unexpected failure")
        }
    }
}
```

### Preferences: every persisted field optional, `didSet { persist() }`, one `persist()` writing the whole struct

<!-- SOURCE: Remaindr/Remaindr/Models/Preferences.swift:9-17 and :59-71 -->
```swift
    /// Every field is optional on purpose. `ConfigFileStore.load` decodes with `try?`, so a
    /// single non-optional field missing from an older file would throw and silently reset
    /// *all* settings to their defaults. Optional fields let each key fall back on its own.
    private struct ConfigFile: Codable {
        var refreshIntervalMinutes: Int?
        var menuBarProvider: String?
        var allowBilledClaudeProbe: Bool?
        var keychainAccessibilityUpgraded: Bool?
    }
    // ...
    /// True once the one-time Keychain accessibility rewrite has run. macOS does
    /// not report a stored item's accessibility class, so the rewrite cannot
    /// detect "already done" and must be gated here instead.
    var keychainAccessibilityUpgraded: Bool {
        didSet { persist() }
    }

    private func persist() {
        store.save(ConfigFile(refreshIntervalMinutes: refreshIntervalMinutes,
                               menuBarProvider: menuBarProvider.rawValue,
                               allowBilledClaudeProbe: allowBilledClaudeProbe,
                               keychainAccessibilityUpgraded: keychainAccessibilityUpgraded))
    }
```

### Pure presentation helper: a Foundation-only `enum` namespace so UI wording is testable without a running app

This is the precedent `UpdateStatusText` (Task 7) follows exactly.

<!-- SOURCE: Remaindr/Remaindr/Models/CollapsedLabelText.swift:1-13 -->
```swift
import Foundation

/// Builds the collapsed menu bar string. Foundation-only on purpose, so the width budget
/// is checkable without a running app.
enum CollapsedLabelText {
    /// Hard character budget for the text beside the provider glyph.
    static let budget = 14

    /// The label reports exactly one provider, and the glyph beside it says which one, so
    /// no short-name prefix is needed here.
    static func text(for slot: ProviderSlot?) -> String {
        clamp(single(slot))
    }
```

### Tests: XCTest, `@testable import Remaindr`, one behaviour per method, `XCTAssertEqual` on a value

<!-- SOURCE: Remaindr/RemaindrTests/CollapsedLabelTextTests.swift:1-11 and :19-28 -->
```swift
import XCTest
@testable import Remaindr

/// Smoke tests that exercise app code through the test host. They pin the
/// collapsed-label contract: the string never exceeds `CollapsedLabelText.budget`
/// and degrades to placeholders instead of provider text.
final class CollapsedLabelTextTests: XCTestCase {

    func testNilSlotShowsPlaceholder() {
        XCTAssertEqual(CollapsedLabelText.text(for: nil), "--")
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
```

`CollapsedLabelTextTests.swift` is the ONLY test file in the repo and every assertion in it is a pure value comparison - there is no existing test that touches a `URLSession`. Tasks 4, 5 and 7 preserve that property; no task in this plan adds a test that calls `api.github.com`.

### Shell: fail-fast guard that prints to stderr and exits non-zero

<!-- SOURCE: make-dmg.sh:50-54 -->
```bash
# 1c. Refuse to ship any build that still carries the debug entitlement.
if codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q get-task-allow; then
  echo "ERROR: $APP_PATH still carries com.apple.security.get-task-allow; not shipping." >&2
  exit 1
fi
```

### SwiftUI: a labelled, non-interactive Settings row

<!-- SOURCE: Remaindr/Remaindr/UI/SettingsView.swift:41-45 -->
```swift
                LabeledContent("Claude") {
                    Text("Reads ~/.claude/projects. No key needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

## Preflight

Run every command in this section BEFORE Task 1 and report anything that has drifted.

### DURABLE - true until the repo itself changes

- **No `project.pbxproj` edit is required to add a Swift file to either target.** Evidence: the `PBXFileSystemSynchronizedRootGroup` entries at `Remaindr/Remaindr.xcodeproj/project.pbxproj:9-19`, referenced from both targets' `fileSystemSynchronizedGroups` lists (`:88-90` and `:109-111`). Consequence: Tasks 4-7 create files and nothing else. If the executor finds itself editing `project.pbxproj`, it has gone wrong - STOP and re-read this entry.
- **No test in the suite touches a network or a `URLSession`.** Evidence: `Remaindr/RemaindrTests/` contains exactly one file, `CollapsedLabelTextTests.swift`, and every assertion in it is a pure value comparison. Consequence: Tasks 5 and 7 test `static` parsers and text builders against `Data`/value literals; the executor must not add a test that calls `api.github.com`.
- **`PinnedSession` is fail-closed for unpinned hosts.** Evidence: `Remaindr/Remaindr/Providers/PinnedSession.swift:64-67` returns `.cancelAuthenticationChallenge` when `pins[host]` is nil, and `pins` holds only `api.anthropic.com`, `api.z.ai`, `api.deepseek.com` (`:20-34`). Consequence: Task 5 uses `URLSession.shared`. Repeated as a Gotcha on that task because it is the single most likely wrong turn in this plan.
- **The app's `CFBundleShortVersionString` is `1.0`, generated from `MARKETING_VERSION`.** Evidence: `GENERATE_INFOPLIST_FILE = YES` with `MARKETING_VERSION = 1.0` in both app build configurations (`project.pbxproj:242,249` Debug and `:264,271` Release); cross-checked against a built artifact - `/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/dmg-staging/Remaindr.app/Contents/Info.plist` printed `1.0`. The `project.pbxproj` half is the durable evidence; that `build/` path is git-ignored and will not exist in a fresh clone, so re-derive from the pbxproj rather than treating the missing file as drift. Consequence: Task 4's zero-padding comparison is load-bearing, not decorative.
- **`notarytool`, `stapler`, `spctl`, `shasum` and `codesign` are all present.** Evidence: `xcrun --find notarytool` printed `/Applications/Xcode.app/Contents/Developer/usr/bin/notarytool`; `xcrun --find stapler` printed the same directory; `which spctl` printed `/usr/sbin/spctl`; `which shasum` printed `/usr/bin/shasum`. Consequence: Tasks 1 and 2 install nothing.
- **`shellcheck` is NOT installed.** Evidence: `which shellcheck` returned nothing. Consequence: shell verification in Tasks 1 and 2 uses `bash -n` plus behavioural runs, not a linter. Do not add a `shellcheck` step.
- **`treehouse` IS installed** at `/Users/jametirakarn/.local/bin/treehouse`, but this plan is single-track and does not use it. Consequence: work in the repo directory directly; do not lease a worktree.
- **The repo has no `docs/adr/`, no `CONTEXT.md`, and no `docs/agents/domain.md`.** Evidence: `ls` on all three returned "No such file or directory". Consequence: `AGENTS.md` is the sole source of project rules and there are no ADRs for this plan to contradict.
- **`build/` is git-ignored.** Evidence: `.gitignore` at the repo root; `git status --short` was empty at `b6a740d` despite `build/Remaindr-1.0.dmg` and `build/dmg-staging/` existing on disk. Consequence: Task 2's artifacts are never committed, and its Step 6 asserts exactly that.

### PERISHABLE - recapture before task 1

- **Baseline red count: ZERO. The tree is green at `b6a740d`.** Check: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` - Recorded while planning: `** TEST SUCCEEDED **`, `Executed 6 tests, with 0 failures (0 unexpected)`, 9.6s wall clock. Needed by: every Swift task's Verify. Because the baseline is 0 failures and 0 warnings, every "Expected" in Tasks 4-8 is an absolute count, never "no new errors". If this is not green before Task 1, STOP and report - do not start on a red tree.
- **`make-dmg.sh` parses cleanly.** Check: `bash -n make-dmg.sh` - Recorded: exit 0, no output. Needed by: Tasks 1 and 2, which both use it as their syntax gate.
- **NO code-signing identity exists on this machine - zero valid identities.** Check: `security find-identity -v -p codesigning | tail -1` - Recorded: `0 valid identities found`; the narrower `security find-identity -v -p codesigning | grep "Developer ID Application"` matched nothing. Needed by: Tasks 1 and 2 and the End-to-end section. **This is the single biggest constraint on the plan.** `make-dmg.sh` will always take its ad-hoc branch here, so the *Accepted* path of the notarization block cannot be executed by any agent on this machine. Task 1 therefore verifies the branches that ARE reachable - the `REQUIRE_NOTARIZATION=1` hard-failure gate and the un-notarized warning - and the notarized path is a `Verify - Human:` on the End-to-end list, with an explicit non-browser proxy. Do not fabricate an identity, do not mint a self-signed certificate to make a box tickable, and do not weaken an assertion so it passes ad-hoc.
- **`NOTARY_PROFILE` is NOT set.** Check: `test -n "${NOTARY_PROFILE:-}" && echo set || echo "NOT set"` - Recorded: `NOT set`. Needed by: Task 1 Step 5, whose expected failure depends on the variable being absent. If a later run has it set, `unset NOTARY_PROFILE` for that one verify and say so when ticking.
- **The GitHub releases endpoint answers 200 with a parseable tag.** Check: `curl -s -o /tmp/rel.json -w "%{http_code}\n" -H "Accept: application/vnd.github+json" https://api.github.com/repos/theerakarnm/remaindr/releases/latest` then `python3 -c "import json;d=json.load(open('/tmp/rel.json'));print(d['tag_name'], d['draft'], d['prerelease'], [a['name'] for a in d['assets']])"` - Recorded while planning: HTTP `200`, then `v1.0.0 False False ['AIUsageBar-v1.0.0.zip']`. Needed by: Task 5's endpoint and field claims, and the End-to-end live check. **Live consequence:** tag `v1.0.0` against bundle version `1.0` must compare EQUAL, so a correct build reports "Up to date" today. A build that says "Update available: 1.0.0" has a broken comparison, not a new release to celebrate.
- **GitHub's unauthenticated rate limit is 60 requests per hour per IP.** Check: `curl -sI https://api.github.com/repos/theerakarnm/remaindr/releases/latest | grep -i x-ratelimit` - Recorded: `x-ratelimit-limit: 60`, `x-ratelimit-remaining: 57`. Needed by: Task 5's 403 handling and Task 6's 24-hour throttle. If `x-ratelimit-remaining` is `0` when the End-to-end live check runs, wait for `x-ratelimit-reset` rather than recording a false failure.
- **Xcode toolchain.** Check: `xcodebuild -version` - Recorded: `Xcode 26.6`, `Build version 17F113`. Needed by: every Swift task. A materially older Xcode may reject the Swift 6 `@Observable` and strict-concurrency code as written.
- **`python3` is on PATH.** Check: `python3 -c "print(1)"` - Recorded: `1`. Needed by: the GitHub-payload Preflight check above and two End-to-end items, which use it to pretty-print JSON. If absent, substitute any JSON reader; nothing in the app depends on it.
- **Working tree is clean at `b6a740d`.** Check: `git status --short` - Recorded: empty. Needed by: every task's Commit step.
- **Network reachability to `api.github.com`.** Check: `curl -sS -o /dev/null -w "%{http_code}\n" https://api.github.com` - Recorded: `200`. Needed by: the End-to-end live check only. If down: the End-to-end "Update check reports up to date against the live endpoint" item is deferred and reported, not ticked.

## Execution

**Tracks:** one, sequential. Tasks 1-9 in order, in the repository working directory, on a branch cut from `b6a740d`.

**Why not parallel:** the shell/docs half and the Swift half are genuinely independent in code, but both need `README.md` and `FUTURE_FEATURES.md`. Once those two shared documentation files are pulled into their own task, the release half is left with two tasks touching one file - below the cost floor of ">=3 tasks or >=5 files" that justifies a `treehouse` worktree, and `treehouse get` plus a cold Xcode build in a fresh checkout costs more wall clock than the split could save. A single sequential track is cheaper and removes the merge hazard on the two shared files entirely.

**Branch:** `git checkout -b release-trust-and-update-checker`

**Merge order:** not applicable - one branch, merged once at the end.

**Shared files:** `README.md` is written by Task 3 (release-trust wording) and again by Task 9 (update-checker wording); `FUTURE_FEATURES.md` by Task 9 only; `make-dmg.sh` by Tasks 1 and 2. Because execution is sequential these are ordinary successive edits, not cross-track collisions. The repo has no barrel/index file, no DI container wiring, no `package.json` or lockfile, no migration directory, and no `.env.example` - all five checked and absent.

**Worktree setup / teardown:** not applicable (single track).

---

### Task 1: Fail-fast signing preflight and an asserted notarization verdict in `make-dmg.sh`

**Files:**
- Modify: `make-dmg.sh` (anchors: `LAYOUT_SCRIPT="$LAYOUT_DIR/layout.applescript"` ~L20; `IDENTITY=$(security find-identity` ~L40; `# 5. Notarize and staple when both a Developer ID identity` ~L103-109)

**Interfaces:**
- Produces (consumed by Tasks 2 and 3):
  - shell variable `IDENTITY` - the Developer ID Application identity hash, discovered once near the top of the script; empty string when none exists.
  - shell variable `NOTARIZED` - `"1"` when the DMG was signed, notarized, stapled and passed `spctl`; `"0"` otherwise. Initialised before first use so `set -u` is satisfied on every path.
  - shell variable `DMG` - unchanged from today: `build/$APP_NAME-$VERSION.dmg`.
  - environment input `REQUIRE_NOTARIZATION` - `"1"` makes a run that cannot notarize exit 1 before the build starts; anything else, including unset, permits the ad-hoc path with a loud warning.

**Gotcha:** the script runs under `set -euo pipefail` (`make-dmg.sh:10`). Two consequences. (a) Write every conditional as an `if` block: a bare `[ -n "$X" ] && cmd` statement returns non-zero when the test fails, and `set -e` then kills the script. (b) `pipefail` is already on, so `xcrun notarytool submit ... | tee file` correctly surfaces `notarytool`'s exit status - do not add `|| true` to that pipeline. Separately, `xcrun notarytool submit --wait` has historically exited 0 on a *rejected* submission, so the exit code alone is not sufficient evidence; the `status: Accepted` line must be asserted from the captured output.

**Steps:**

- [x] Step 1: Hoist identity discovery and add the hard gate. Immediately after the `LAYOUT_SCRIPT="$LAYOUT_DIR/layout.applescript"` line (~L20) and before the `# 1. Build the app` comment, insert:
      ```bash

      # 0. Signing preflight, before the build. A release run that cannot notarize
      #    should fail in seconds, not after a full xcodebuild.
      IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')
      REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
      NOTARIZED=0

      if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
        if [ -z "$IDENTITY" ]; then
          echo "ERROR: REQUIRE_NOTARIZATION=1 but no Developer ID Application identity is available." >&2
          echo "       Install one from developer.apple.com, or drop REQUIRE_NOTARIZATION for a local ad-hoc build." >&2
          exit 1
        fi
        if [ -z "${NOTARY_PROFILE:-}" ]; then
          echo "ERROR: REQUIRE_NOTARIZATION=1 but NOTARY_PROFILE is not set." >&2
          echo "       Store one once with:" >&2
          echo "         xcrun notarytool store-credentials <name> --apple-id <id> --team-id <team>" >&2
          exit 1
        fi
      fi
      ```
- [x] Step 2: Delete the now-duplicated discovery line inside step 1b. Remove exactly this one line (~L40), leaving the `ENTITLEMENTS=` line above it and the `if [ -n "$IDENTITY" ]; then` block below it untouched:
      ```bash
      IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')
      ```
- [x] Step 3: Replace the whole of step 5. Delete these lines (~L103-109):
      ```bash
      # 5. Notarize and staple when both a Developer ID identity and a stored notary
      #    profile exist. Store the profile once with:
      #      xcrun notarytool store-credentials NOTARY_PROFILE --apple-id <id> --team-id <team>
      if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
      fi
      ```
      and write in their place:
      ```bash
      # 5. Sign, notarize, staple, and then prove all three. Stapling is the last write
      #    to the image; the checksum in step 6 is taken after it for exactly that reason.
      if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
        # The image itself is signed, not just the app inside it: a ticket stapled to an
        # unsigned image cannot produce a Developer ID assessment.
        codesign --force --sign "$IDENTITY" --timestamp "$DMG"

        SUBMIT_LOG="$LAYOUT_DIR/notary.txt"
        if ! xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$SUBMIT_LOG"; then
          echo "ERROR: notarytool submit failed; see the output above." >&2
          exit 1
        fi
        # --wait has historically exited 0 on a rejected submission, so the verdict is
        # asserted from the output rather than inferred from the exit code.
        if ! grep -qE '^[[:space:]]*status: Accepted' "$SUBMIT_LOG"; then
          SUBMISSION_ID=$(awk '/^[[:space:]]*id:/ {print $2; exit}' "$SUBMIT_LOG")
          echo "ERROR: notarization was not Accepted; this DMG must not be published." >&2
          if [ -n "$SUBMISSION_ID" ]; then
            xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
          fi
          exit 1
        fi

        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
        # Gatekeeper's own verdict on the artifact a user will actually double-click.
        spctl --assess --type open --context context:primary-signature -vv "$DMG"
        NOTARIZED=1
      else
        echo "WARNING: this DMG is NOT notarized (no Developer ID identity and/or no NOTARY_PROFILE)." >&2
        echo "         Gatekeeper will refuse it on any other Mac. Do not publish it." >&2
        echo "         Re-run with both set, and with REQUIRE_NOTARIZATION=1 to make this a hard failure." >&2
      fi
      ```
- [x] Step 4: Verify - Run: `bash -n make-dmg.sh && echo SYNTAX_OK` - Expected: prints `SYNTAX_OK`, exit 0, no other output.
- [x] Step 5: Verify - Run: `env -u NOTARY_PROFILE REQUIRE_NOTARIZATION=1 ./make-dmg.sh; echo "exit=$?"` - Expected: exits within ~2 seconds and **before any `xcodebuild` output appears**, printing `exit=1`, with stderr containing `ERROR: REQUIRE_NOTARIZATION=1 but no Developer ID Application identity is available.` This is the reachable half of the notarization gate on a machine with no signing identity (see Preflight); the Accepted path is a Human check in the End-to-end section.
- [x] Step 6: Verify - Run: `grep -c 'security find-identity' make-dmg.sh` - Expected: `1` - only the hoisted copy remains, the step-1b duplicate is gone.
- [x] Step 7: Commit - `git commit -m "build: fail fast when a release run cannot notarize, and assert the notarization verdict"`
  > Deviation: this repo runs a background auto-commit daemon that committed the task's files under its own generated message ("Update 2 files: major changes") before the plan's commit step ran. Recovered with `git reset --soft <pre-task sha>` followed by the plan's exact commit message; file contents are unaffected. Same recovery applied to every later task.

---

### Task 2: Publish a SHA-256 sidecar next to the DMG

**Files:**
- Modify: `make-dmg.sh` (anchor: `echo "Created: $DMG"`, in the trailing summary block, ~L111-113)

**Interfaces:**
- Consumes (from Task 1): shell variables `DMG` and `NOTARIZED`.
- Produces (consumed by Task 3's README wording and by the End-to-end section):
  - build artifact `build/Remaindr-<version>.dmg.sha256` - one line in `shasum -a 256` output format, whose filename column is the **bare** DMG basename (`Remaindr-1.0.dmg`), never a path (`build/Remaindr-1.0.dmg`).
  - the user-facing verification contract, run from whatever folder the two files were downloaded into: `shasum -a 256 -c Remaindr-<version>.dmg.sha256` prints `Remaindr-<version>.dmg: OK`.

**Gotcha:** two ordering and formatting traps. First, the checksum must be computed AFTER the `xcrun stapler staple` added in Task 1 - stapling rewrites the disk image, so a hash taken before it will not match what a user downloads; the script already flags this constraint in its own comment at `make-dmg.sh:97-98`. Second, `shasum -a 256 "build/x.dmg"` writes the *path* into the sidecar, and `shasum -c` then fails for anyone who put both files in `~/Downloads`. Use a subshell `cd` so only the basename is recorded.

**Steps:**

- [x] Step 1: Insert the sidecar step between the step 5 block added in Task 1 and the trailing `echo ""` summary:
      ```bash

      # 6. Publish the SHA-256 sidecar. Taken AFTER stapling: `stapler staple` rewrites
      #    the image, so a checksum computed before it would not match the download.
      DMG_NAME=$(basename "$DMG")
      DMG_DIR=$(dirname "$DMG")
      # The subshell cd keeps the bare filename in the sidecar, so a user can verify from
      # whatever folder they downloaded both files into. The `&&` here is deliberate and is
      # NOT the pattern Global Constraints warns about: a failing cd must abort the line,
      # and under set -e the failing subshell aborts the script - which is what is wanted.
      ( cd "$DMG_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256" )
      ( cd "$DMG_DIR" && shasum -a 256 -c "$DMG_NAME.sha256" )
      ```
- [x] Step 2: Replace the trailing summary block - today exactly `echo ""`, `echo "Created: $DMG"`, `echo "Verify with: hdiutil verify $DMG"` - with:
      ```bash
      echo ""
      echo "Created:   $DMG"
      echo "Checksum:  $DMG.sha256"
      cat "$DMG.sha256"
      if [ "$NOTARIZED" = "1" ]; then
        echo "Notarized: yes, ticket stapled"
      else
        echo "Notarized: NO - do not publish this build"
      fi
      echo ""
      echo "Upload BOTH $DMG_NAME and $DMG_NAME.sha256 to the GitHub release."
      echo "Verify with: hdiutil verify $DMG"
      ```
- [x] Step 3: Verify - Run: `bash -n make-dmg.sh && echo SYNTAX_OK` - Expected: prints `SYNTAX_OK`, exit 0.
- [x] Step 4: Verify - Run: `./make-dmg.sh` (a full ad-hoc Release build plus DMG creation; measured at ~20s while planning, allow a few minutes on a cold DerivedData) - Expected: exit 0; stderr carries the `WARNING: this DMG is NOT notarized` banner; stdout ends with `Notarized: NO - do not publish this build`; and the `shasum -c` line printed `Remaindr-1.0.dmg: OK`.
- [x] Step 5: Verify - Run: `(cd build && cat Remaindr-1.0.dmg.sha256 && shasum -a 256 -c Remaindr-1.0.dmg.sha256)` - Expected: the file holds exactly one line matching `^[0-9a-f]{64}  Remaindr-1\.0\.dmg$` (two spaces, bare filename, no `build/` prefix), and the check prints `Remaindr-1.0.dmg: OK`.
- [x] Step 6: Verify - Run: `git status --short build/` - Expected: no output - `build/` is git-ignored, so the new artifacts are not about to be committed. If output appears, do NOT `git add` it; report instead.
- [x] Step 7: Commit - `git commit -m "build: publish a SHA-256 sidecar alongside the release DMG"`

---

### Task 3: Rewrite the README's distribution-trust wording

**Files:**
- Modify: `README.md` (anchors: `> Early-development builds are not notarized.` ~L70-72; `A release of Remaindr is ad-hoc signed` in "Why macOS asks for the keychain password" ~L155-158; `- [ ] Notarized, signed release build` in "## Roadmap" ~L164)

**Interfaces:**
- Consumes (from Task 2): the sidecar filename contract `Remaindr-<version>.dmg.sha256` and the verification command `shasum -a 256 -c Remaindr-<version>.dmg.sha256`, both quoted verbatim in the README.
- Produces: a `### Verifying your download` subsection under `## Installation`. Documentation only - no code consumes it.

**Gotcha:** the honesty trap. The already-published `v1.0.0` GitHub release ships `AIUsageBar-v1.0.0.zip`, which is ad-hoc signed, un-notarized, and has no sidecar (all confirmed in Preflight). A README that flatly declares "releases are notarized" would misdescribe the one asset a user can actually download today - precisely the "never fabricate a claim" rule in `AGENTS.md`. Tie the claim to an observable property of the download instead: a release that ships a `.sha256` sidecar came from this pipeline, one that does not predates it. For the same reason the Roadmap entry is reworded rather than simply ticked - the *pipeline* is done, the first notarized *release* still waits on the Developer ID certificate that audit F-01 is blocked on.

**Steps:**

- [ ] Step 1: Replace the three-line blockquote at ~L70-72 (from `> Early-development builds are not notarized.` through `> ... before opening it.`) with the following. Note this both removes the F-02 wording and adds the new subsection, so `## Setup` now follows the new subsection:
      ~~~markdown
      > Release DMGs are signed with a Developer ID certificate, notarized by Apple, and carry a
      > stapled notarization ticket, so they open with an ordinary double-click. There is no
      > Gatekeeper workaround to perform and none is supported: if macOS refuses to open a
      > download, the artifact is wrong, not the warning. Verify it (below), then open an issue.
      >
      > A release that ships a `.sha256` sidecar came from this pipeline. The older `v1.0.0`
      > asset predates it and is neither notarized nor checksummed - build from source rather
      > than using it.

      ### Verifying your download

      Every release publishes `Remaindr-<version>.dmg` together with `Remaindr-<version>.dmg.sha256`.
      Download both into the same folder, then:

      ```bash
      shasum -a 256 -c Remaindr-<version>.dmg.sha256
      spctl --assess --type open --context context:primary-signature -vv Remaindr-<version>.dmg
      ```

      The first command must print `Remaindr-<version>.dmg: OK`.
      The second must print `accepted` together with `source=Notarized Developer ID`.
      Anything else - a checksum mismatch, `rejected`, or a missing signature - means the file is
      not the one that was published.
      Delete it and download again rather than opening it.
      ~~~
- [ ] Step 2: Replace the second paragraph of "Why macOS asks for the keychain password" (~L155-158, the one beginning `A release of Remaindr is ad-hoc signed`) with:
      ```markdown
      A published release is signed with a stable Developer ID certificate, so macOS records the
      grant against that identity and updating to a newer release does not ask again.
      A build you compiled yourself is ad-hoc signed, which ties the grant to that exact binary, so
      every local rebuild asks once more per key.
      ```
- [ ] Step 3: Reword the first Roadmap entry (~L164) from `- [ ] Notarized, signed release build` to:
      ```markdown
      - [x] Notarized, stapled, checksummed release pipeline in `make-dmg.sh` - the first notarized *release* still needs a Developer ID certificate
      ```
- [ ] Step 4: Verify - Run: `grep -ni "right-click\|not notarized\|bypass\|early-development" README.md; echo "grep_exit=$?"` - Expected: no matching lines, and `grep_exit=1` (grep's no-match status). The Gatekeeper-bypass and un-notarized wording that audit F-02 named is gone.
- [ ] Step 5: Verify - Run: `grep -c "Verifying your download" README.md; grep -c "shasum -a 256 -c" README.md; grep -c "source=Notarized Developer ID" README.md` - Expected: `1`, `1`, `1`.
- [ ] Step 6: Verify - Run: `grep -o "Remaindr-<version>\.dmg\.sha256" README.md | sort -u` - Expected: exactly the one string `Remaindr-<version>.dmg.sha256`, matching the filename Task 2's script emits.
- [ ] Step 7: Commit - `git commit -m "docs: describe releases as notarized and document how to verify a download"`

---

### Task 4: `AppVersion` - a dotted numeric version that compares correctly

**Files:**
- Create: `Remaindr/Remaindr/Update/AppVersion.swift`
- Test:   `Remaindr/RemaindrTests/AppVersionTests.swift`

**Interfaces:**
- Produces (consumed by Tasks 5, 6, 7, 8):
  - `struct AppVersion: Comparable, Sendable, CustomStringConvertible`
  - `init?(_ raw: String)` - nil unless the string is 1 to 4 dot-separated ASCII-numeric components, after an optional leading `v` or `V`
  - `static var current: AppVersion { get }` - the running bundle's `CFBundleShortVersionString`, falling back to `AppVersion("0")!`
  - `static func < (lhs: AppVersion, rhs: AppVersion) -> Bool`
  - `static func == (lhs: AppVersion, rhs: AppVersion) -> Bool`
  - `var description: String { get }` - dotted components, no leading `v`
  - `let components: [Int]`

**Gotcha:** the zero-padding inside `<` is the entire point of this type, not a nicety. The app ships `MARKETING_VERSION = 1.0` while the matching GitHub release is tagged `v1.0.0` (both confirmed in Preflight). Compare the component arrays without padding and `1.0` reads as older than `1.0.0`, so **every user on a current build is told an update exists** - the most visible possible failure of this feature. `testMissingComponentsCompareAsZero` pins exactly that case. Second: `Character.isNumber` is true for non-ASCII digits such as `½`, so the parser guards `isASCII` as well. Third: keep `current` a computed `static var`, not a `static let` - a stored static initialised from `Bundle.main` invites a Swift 6 concurrency diagnostic for no benefit, since this is read only a handful of times per launch.

**Steps:**

- [ ] Step 1: Create the directory and `Remaindr/Remaindr/Update/AppVersion.swift`:
      ```swift
      import Foundation

      /// A dotted numeric version, compared component by component. Foundation-only on
      /// purpose so the comparison is checkable without a running app, the same reason
      /// `CollapsedLabelText` exists.
      ///
      /// Accepts an optional leading `v` because GitHub release tags carry one (`v1.0.0`)
      /// while `CFBundleShortVersionString` does not (`1.0`). Anything that is not purely
      /// numeric components - `1.0-beta`, `2026.08.19-rc1`, an empty string - fails to
      /// parse rather than silently comparing as some fallback.
      struct AppVersion: Comparable, Sendable, CustomStringConvertible {
          /// One to four non-negative components, in order of significance.
          let components: [Int]

          init?(_ raw: String) {
              var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
              if text.hasPrefix("v") || text.hasPrefix("V") {
                  text.removeFirst()
              }
              let parts = text.split(separator: ".", omittingEmptySubsequences: false)
              guard !parts.isEmpty, parts.count <= 4 else { return nil }
              var parsed: [Int] = []
              for part in parts {
                  // `isNumber` alone is true for non-ASCII digits such as "½".
                  guard !part.isEmpty,
                        part.allSatisfy({ $0.isASCII && $0.isNumber }),
                        let value = Int(part) else { return nil }
                  parsed.append(value)
              }
              self.components = parsed
          }

          /// The running app's version. Falls back to `0` so a bundle with no version
          /// string can never read as newer than a published release.
          static var current: AppVersion {
              let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
              return raw.flatMap(AppVersion.init) ?? AppVersion("0")!
          }

          /// Zero-pads the shorter side, so `1.0` and `1.0.0` are equal rather than `1.0`
          /// reading as older. The app ships MARKETING_VERSION 1.0 while the matching
          /// release is tagged v1.0.0; without this padding every user would be told an
          /// update exists.
          static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
              let width = max(lhs.components.count, rhs.components.count)
              for index in 0..<width {
                  let left = index < lhs.components.count ? lhs.components[index] : 0
                  let right = index < rhs.components.count ? rhs.components[index] : 0
                  if left != right { return left < right }
              }
              return false
          }

          /// Defined explicitly rather than synthesised, so `1.0` equals `1.0.0`.
          static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
              !(lhs < rhs) && !(rhs < lhs)
          }

          /// Rendered without the leading `v`, so UI text reads `1.1.0`, not `v1.1.0`.
          var description: String {
              components.map(String.init).joined(separator: ".")
          }
      }
      ```
- [ ] Step 2: Create `Remaindr/RemaindrTests/AppVersionTests.swift`:
      ```swift
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
      ```
- [ ] Step 3: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -20` - Expected: `** TEST SUCCEEDED **` and `Executed 11 tests, with 0 failures` (the 6 baseline tests plus the 5 added here).
- [ ] Step 4: Verify - Run: `git status --short Remaindr/Remaindr.xcodeproj/` - Expected: no output - the file-system-synchronised groups picked the new files up without a project-file edit.
- [ ] Step 5: Commit - `git commit -m "feat: add AppVersion, a dotted numeric version with zero-padded comparison"`

---

### Task 5: `UpdateChecker` - one unauthenticated GET against the latest GitHub release

**Files:**
- Create: `Remaindr/Remaindr/Update/UpdateChecker.swift`
- Test:   `Remaindr/RemaindrTests/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes (from Task 4): `AppVersion.init?(_ raw: String)`, `AppVersion.current`, `<`, `>`, `CustomStringConvertible`.
- Produces (consumed by Tasks 6, 7, 8):
  - `enum UpdateStatus: Equatable, Sendable { case upToDate(current: AppVersion); case updateAvailable(latest: AppVersion) }`
  - `enum UpdateCheckError: Error, Equatable, Sendable { case offline; case rateLimited; case noRelease; case malformedResponse(String); case serverError(status: Int) }` with `var shortDescription: String { get }`
  - `struct UpdateChecker: Sendable`
  - `static let releasesPageURL: URL`
  - `init(session: URLSession = .shared, currentVersion: AppVersion = AppVersion.current)`
  - `func check() async throws -> UpdateStatus`
  - `static func parse(_ data: Data, currentVersion: AppVersion) throws -> UpdateStatus`

**Gotcha:** **use `URLSession.shared`, not `PinnedSession.shared`.** `PinnedSession.Delegate` cancels the challenge for any host absent from its pin table (`PinnedSession.swift:64-67`), and `api.github.com` is not in that table, so routing this call through the app's usual session would make every check fail with a cancelled task. Adding a pin is explicitly rejected in Global Constraints. Second gotcha: do not use the payload's `html_url` for the link - GitHub answers this endpoint unauthenticated and unpinned, so a tampered `html_url` would become an attacker-chosen destination the user is invited to click; `releasesPageURL` is a constant for that reason. Third: GitHub answers **403**, not 429, when an unauthenticated caller exhausts its 60-per-hour budget, so both map to `.rateLimited`. Fourth: `catch let error as URLError` is a non-exhaustive catch inside a `throws` function - that is legal Swift and intentional, letting any non-`URLError` propagate unchanged, mirroring how `mapTransportFailure` rethrows what it does not recognise (`UsageProvider.swift:17`).

**Steps:**

- [ ] Step 1: Create `Remaindr/Remaindr/Update/UpdateChecker.swift`:
      ```swift
      import Foundation

      /// What a completed update check concluded.
      enum UpdateStatus: Equatable, Sendable {
          case upToDate(current: AppVersion)
          case updateAvailable(latest: AppVersion)
      }

      /// Every distinct failure the Settings row must be able to show differently.
      /// Deliberately separate from `ProviderError`: an update check is not a provider
      /// reading and must not widen the `UsageProvider` surface.
      enum UpdateCheckError: Error, Equatable, Sendable {
          case offline
          case rateLimited
          case noRelease
          case malformedResponse(String)
          case serverError(status: Int)

          /// Short text shown in Settings. Never contains a URL or a response body.
          var shortDescription: String {
              switch self {
              case .offline: return "Offline"
              case .rateLimited: return "Rate limited"
              case .noRelease: return "No release found"
              case .malformedResponse: return "Bad response"
              case .serverError(let status): return "Server error \(status)"
              }
          }
      }

      /// Reads the newest published release from GitHub and compares its tag with the
      /// running bundle's version. It downloads nothing, installs nothing, and sends no
      /// credential: the whole feature is one unauthenticated GET plus a link.
      struct UpdateChecker: Sendable {
          /// The page the UI links to. A constant, never a URL taken from the response:
          /// this endpoint is unauthenticated and unpinned, so a tampered `html_url`
          /// would otherwise become an attacker-chosen link the user is invited to click.
          static let releasesPageURL = URL(string: "https://github.com/theerakarnm/remaindr/releases/latest")!

          private static let endpoint = URL(string: "https://api.github.com/repos/theerakarnm/remaindr/releases/latest")!

          private let session: URLSession
          private let currentVersion: AppVersion

          /// `URLSession.shared`, not `PinnedSession.shared`. The pinning delegate is
          /// fail-closed for any host with no pins, so routing this call through it would
          /// cancel every check; and pinning github.com would break silently the next time
          /// GitHub rotates a certificate. System trust is the right level here because no
          /// key or token is sent.
          init(session: URLSession = .shared, currentVersion: AppVersion = AppVersion.current) {
              self.session = session
              self.currentVersion = currentVersion
          }

          private struct Payload: Decodable {
              let tag_name: String
              let draft: Bool?
              let prerelease: Bool?
          }

          func check() async throws -> UpdateStatus {
              var request = URLRequest(url: Self.endpoint)
              request.httpMethod = "GET"
              request.timeoutInterval = 15
              request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
              request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

              let data: Data
              let response: URLResponse
              do {
                  (data, response) = try await session.data(for: request)
              } catch let error as URLError {
                  // A cancelled task is the caller going away, not a connectivity failure.
                  if error.code == .cancelled { throw error }
                  throw UpdateCheckError.offline
              }

              guard let http = response as? HTTPURLResponse else {
                  throw UpdateCheckError.malformedResponse("no HTTP response")
              }
              // The 403 body is a rate-limit message, so status is classified before decoding.
              switch http.statusCode {
              case 200:
                  break
              case 403, 429:
                  // Unauthenticated callers get 60 requests an hour per IP, and GitHub
                  // answers 403 rather than 429 once that budget is gone.
                  throw UpdateCheckError.rateLimited
              case 404:
                  throw UpdateCheckError.noRelease
              default:
                  throw UpdateCheckError.serverError(status: http.statusCode)
              }

              return try Self.parse(data, currentVersion: currentVersion)
          }

          /// Pure so a harness can exercise it without a network.
          static func parse(_ data: Data, currentVersion: AppVersion) throws -> UpdateStatus {
              let payload: Payload
              do {
                  payload = try JSONDecoder().decode(Payload.self, from: data)
              } catch {
                  throw UpdateCheckError.malformedResponse("release payload not decodable")
              }
              // A draft or a pre-release is not something to point a user at.
              guard payload.draft != true, payload.prerelease != true else {
                  throw UpdateCheckError.noRelease
              }
              guard let latest = AppVersion(payload.tag_name) else {
                  throw UpdateCheckError.malformedResponse("tag_name is not a version")
              }
              return latest > currentVersion
                  ? .updateAvailable(latest: latest)
                  : .upToDate(current: currentVersion)
          }
      }
      ```
- [ ] Step 2: Create `Remaindr/RemaindrTests/UpdateCheckerTests.swift`:
      ```swift
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
      ```
- [ ] Step 3: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -20` - Expected: `** TEST SUCCEEDED **` and `Executed 21 tests, with 0 failures` (6 baseline + 5 from Task 4 + 10 here).
- [ ] Step 4: Verify - Run: `grep -rn "PinnedSession" Remaindr/Remaindr/Update/; echo "grep_exit=$?"` - Expected: no matching lines and `grep_exit=1`. The update path must never reach the fail-closed pinning session.
- [ ] Step 5: Verify - Run: `grep -n "html_url" Remaindr/Remaindr/Update/UpdateChecker.swift; echo "grep_exit=$?"` - Expected: no matching lines and `grep_exit=1`. The link is a constant, and `html_url` is not even decoded.
- [ ] Step 6: Commit - `git commit -m "feat: add UpdateChecker, an unauthenticated GitHub latest-release version check"`

---

### Task 6: `UpdateStore` and the throttle timestamp in `Preferences`

**Files:**
- Create: `Remaindr/Remaindr/Update/UpdateStore.swift`
- Modify: `Remaindr/Remaindr/Models/Preferences.swift` (anchors: `private struct ConfigFile: Codable` ~L12-17; `var keychainAccessibilityUpgraded: Bool {` ~L62-64; `private func persist()` ~L66-72; the `self.keychainAccessibilityUpgraded = loaded?` line inside `private init(store:)` ~L32)

**Interfaces:**
- Consumes (from Tasks 4 and 5): `AppVersion`; `UpdateStatus`; `UpdateCheckError`; `UpdateChecker.init(session:currentVersion:)`; `func check() async throws -> UpdateStatus`.
- Produces (consumed by Tasks 7 and 8):
  - `@MainActor @Observable final class UpdateStore`
  - `static let minimumInterval: TimeInterval` (86400)
  - `init(checker: UpdateChecker = UpdateChecker(), preferences: Preferences)`
  - `private(set) var status: UpdateStatus?`, `private(set) var error: UpdateCheckError?`, `private(set) var isChecking: Bool`
  - `var availableVersion: AppVersion? { get }`
  - `func checkIfDue(now: Date = Date()) async`
  - `func check(now: Date = Date()) async`
  - on `Preferences`: `var lastUpdateCheck: Date?` with `didSet { persist() }`

**Gotcha:** `Preferences.ConfigFile` is a `private` nested struct read and written only inside `Preferences.swift` - verified with `grep -rn "ConfigFile" Remaindr/`, which matches that one file. Adding an **optional** field to it is therefore backward compatible in both directions: an existing `~/.remaindr` written before this change decodes with `lastUpdateCheckAt == nil`, and the file's own header comment (`Preferences.swift:9-11`) explains why every field must stay optional. Do not make it non-optional. Second gotcha: `didSet` does not fire for assignments made inside `init`, which is what keeps the current initialiser from writing the file on every launch - assign `lastUpdateCheck` in `init` like every other field, not through a setter. Third: a *failed* check still stamps `lastUpdateCheck`, deliberately, so a persistently offline machine does not retry on every single launch; the cost is that an offline launch spends that day's slot, which the manual "Check now" button exists to override.

**Steps:**

- [ ] Step 1: In `Remaindr/Remaindr/Models/Preferences.swift`, add the field to `ConfigFile` (last member, after `keychainAccessibilityUpgraded`):
      ```swift
              var lastUpdateCheckAt: Double?
      ```
- [ ] Step 2: In the same file's `private init(store:)`, add one line after the existing `self.keychainAccessibilityUpgraded = ...` assignment:
      ```swift
              self.lastUpdateCheck = loaded?.lastUpdateCheckAt.map(Date.init(timeIntervalSince1970:))
      ```
- [ ] Step 3: Add the stored property immediately after `keychainAccessibilityUpgraded`'s closing brace and before `private func persist()`:
      ```swift
          /// When the update check last completed a network round trip, successful or not.
          /// Non-secret, like every other field here. Stored as epoch seconds so the dotfile
          /// stays readable and independent of any date-encoding strategy.
          var lastUpdateCheck: Date? {
              didSet { persist() }
          }
      ```
- [ ] Step 4: Extend `persist()` with the new argument, keeping the existing alignment:
      ```swift
          private func persist() {
              store.save(ConfigFile(refreshIntervalMinutes: refreshIntervalMinutes,
                                     menuBarProvider: menuBarProvider.rawValue,
                                     allowBilledClaudeProbe: allowBilledClaudeProbe,
                                     keychainAccessibilityUpgraded: keychainAccessibilityUpgraded,
                                     lastUpdateCheckAt: lastUpdateCheck?.timeIntervalSince1970))
          }
      ```
- [ ] Step 5: Create `Remaindr/Remaindr/Update/UpdateStore.swift`:
      ```swift
      import Foundation

      /// Update state for the UI, mirroring `ProviderStore`: a failure writes `error` and
      /// leaves the last `status` alone, so a known result stays on screen instead of
      /// blanking.
      @MainActor
      @Observable
      final class UpdateStore {
          /// At most one automatic check a day. GitHub allows 60 unauthenticated requests
          /// an hour per IP, and a menu bar app that stays running for weeks must not
          /// spend that budget on version strings.
          static let minimumInterval: TimeInterval = 24 * 60 * 60

          private(set) var status: UpdateStatus?
          private(set) var error: UpdateCheckError?
          private(set) var isChecking = false

          private let checker: UpdateChecker
          private let preferences: Preferences

          init(checker: UpdateChecker = UpdateChecker(), preferences: Preferences) {
              self.checker = checker
              self.preferences = preferences
          }

          /// The version to offer, or nil when up to date or not yet checked.
          var availableVersion: AppVersion? {
              guard case .updateAvailable(let latest) = status else { return nil }
              return latest
          }

          /// Called the first time the dropdown is built. Skips the network entirely when
          /// the last check is recent. Note this is NOT app launch: `MenuBarExtra(.window)`
          /// builds its content lazily, so the first check happens on first dropdown open.
          func checkIfDue(now: Date = Date()) async {
              if let last = preferences.lastUpdateCheck,
                 now.timeIntervalSince(last) < Self.minimumInterval {
                  return
              }
              await check(now: now)
          }

          /// The "Check now" button. Always makes the request.
          func check(now: Date = Date()) async {
              isChecking = true
              defer { isChecking = false }
              do {
                  status = try await checker.check()
                  error = nil
              } catch let failure as UpdateCheckError {
                  error = failure
              } catch let urlError as URLError where urlError.code == .cancelled {
                  // The caller went away; leave the timestamp alone so the next launch retries.
                  return
              } catch {
                  self.error = .malformedResponse("unexpected failure")
              }
              // Stamped even on failure, so a persistently offline machine does not retry
              // on every launch. "Check now" is the override.
              preferences.lastUpdateCheck = now
          }
      }
      ```
- [ ] Step 6: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -20` - Expected: `** TEST SUCCEEDED **` and `Executed 21 tests, with 0 failures` - unchanged from Task 5, because this task adds behaviour but no test. A *warning* here is a failure: strict concurrency must accept `UpdateStore` as written.
- [ ] Step 7: Verify - Run: `grep -rnw "ConfigFile" Remaindr/ --include=*.swift` - Expected: matches only inside `Remaindr/Remaindr/Models/Preferences.swift` (lines 12, 19, 25, 67 after this edit), confirming the Codable struct still has exactly one consumer and that no hand-built fixture elsewhere broke. `-w` is required: without it the unrelated `ConfigFileStore` type in `Models/ConfigFileStore.swift:6` matches on the substring and the result reads as drift.
- [ ] Step 8: Commit - `git commit -m "feat: add UpdateStore with a once-a-day throttle persisted in Preferences"`

---

### Task 7: `UpdateStatusText` - the exact strings the UI renders

**Files:**
- Create: `Remaindr/Remaindr/Update/UpdateStatusText.swift`
- Test:   `Remaindr/RemaindrTests/UpdateStatusTextTests.swift`

**Interfaces:**
- Consumes (from Tasks 4, 5, 6): `AppVersion` (`CustomStringConvertible`); `UpdateStatus`; `UpdateCheckError.shortDescription`.
- Produces (consumed by Task 8):
  - `enum UpdateStatusText`
  - `static func settings(status: UpdateStatus?, error: UpdateCheckError?, isChecking: Bool) -> String`
  - `static func dropdown(available: AppVersion?) -> String?`

**Gotcha:** this task exists so Task 8's rendering has a non-visual proxy. Keep every user-visible update string in this file and interpolate nothing else in the views - a string literal that lives in `DropdownPanel.swift` or `SettingsView.swift` is invisible to the test suite and to the reviewer, which is exactly the gap `CollapsedLabelText` was created to close (`CollapsedLabelText.swift:3-4`).

**Steps:**

- [ ] Step 1: Create `Remaindr/Remaindr/Update/UpdateStatusText.swift`:
      ```swift
      import Foundation

      /// Builds the two update strings the UI shows. Foundation-only on purpose, so the
      /// wording is checkable without a running app - the same reason `CollapsedLabelText`
      /// exists. No update string is written anywhere else.
      enum UpdateStatusText {
          /// The Settings row. Reports the in-flight state first, then a failure, then the
          /// result, then "never checked".
          static func settings(status: UpdateStatus?,
                               error: UpdateCheckError?,
                               isChecking: Bool) -> String {
              if isChecking { return "Checking\u{2026}" }
              if let error { return "Check failed: \(error.shortDescription)" }
              switch status {
              case .updateAvailable(let latest): return "Update available: \(latest)"
              case .upToDate(let current): return "Up to date (\(current))"
              case nil: return "Not checked yet"
              }
          }

          /// The dropdown line. Nil when there is nothing to offer, so the panel stays as
          /// compact as it is today for the overwhelmingly common case.
          static func dropdown(available: AppVersion?) -> String? {
              guard let available else { return nil }
              return "Update available: \(available)"
          }
      }
      ```
- [ ] Step 2: Create `Remaindr/RemaindrTests/UpdateStatusTextTests.swift`:
      ```swift
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
      ```
- [ ] Step 3: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -20` - Expected: `** TEST SUCCEEDED **` and `Executed 27 tests, with 0 failures` (21 from Task 5 plus the 6 added here).
- [ ] Step 4: Commit - `git commit -m "feat: add UpdateStatusText so the update wording is testable without a running app"`

---

### Task 8: Wire the update check into the app, the dropdown, and Settings

**Files:**
- Modify: `Remaindr/Remaindr/App/RemaindrApp.swift` (anchors: `@State private var scheduler: RefreshScheduler` ~L7; `let scheduler = RefreshScheduler(store: store, preferences: preferences)` ~L16; `.task { scheduler.start() }` ~L25; `SettingsView(preferences: preferences, scheduler: scheduler)` ~L32)
- Modify: `Remaindr/Remaindr/UI/DropdownPanel.swift` (anchors: `let store: ProviderStore` ~L6; `Divider()` immediately preceding `Button("Refresh")`, ~L13)
- Modify: `Remaindr/Remaindr/UI/SettingsView.swift` (anchors: `let scheduler: RefreshScheduler` ~L5; `if let message {` inside `Section("General")`, ~L78)

**Interfaces:**
- Consumes (from Tasks 5, 6, 7): `UpdateStore.init(checker:preferences:)`; `UpdateStore.availableVersion`; `UpdateStore.status`; `UpdateStore.error`; `UpdateStore.isChecking`; `func check(now:) async`; `func checkIfDue(now:) async`; `UpdateChecker.releasesPageURL`; `UpdateStatusText.settings(status:error:isChecking:)`; `UpdateStatusText.dropdown(available:)`.
- Produces: no new API - the last task in the app half.

**Gotcha:** `DropdownPanel`'s `.task` modifier is where `scheduler.start()` already lives (`RemaindrApp.swift:25`), so it is the established place to kick off deferred work in this app - attach `await updateStore.checkIfDue()` to that same modifier rather than inventing a new lifecycle hook. **Know what that means:** `MenuBarExtra` with `.menuBarExtraStyle(.window)` builds its content view lazily, so this fires on the first dropdown open, not at app launch - exactly the same timing the existing `scheduler.start()` already has. That is the deliberate choice (mirror the established convention, do not add a second lifecycle mechanism), and the End-to-end section verifies it in that order. Do not "fix" it by moving the call into `RemaindrApp.init()`, which would put a network request on the launch path. Second: `DropdownPanel` is `.frame(width: 300)` (`DropdownPanel.swift:22`), and "Update available: 1.1.0" at `.font(.caption)` fits comfortably; do not widen the frame. Third: this task deliberately adds no test - every string it renders is already asserted by Task 7, and the visual result is the End-to-end Human check.

**Steps:**

- [ ] Step 1: In `RemaindrApp.swift`, add the state property after `scheduler`:
      ```swift
          @State private var updateStore: UpdateStore
      ```
- [ ] Step 2: In `RemaindrApp.init()`, construct it after the `scheduler` line and register it with the other three:
      ```swift
              let updateStore = UpdateStore(preferences: preferences)
              _preferences = State(initialValue: preferences)
              _store = State(initialValue: store)
              _scheduler = State(initialValue: scheduler)
              _updateStore = State(initialValue: updateStore)
      ```
- [ ] Step 3: In `RemaindrApp.body`, pass the store to both scenes and extend the existing `.task`:
      ```swift
              MenuBarExtra {
                  DropdownPanel(store: store, updateStore: updateStore)
                      .task {
                          scheduler.start()
                          await updateStore.checkIfDue()
                      }
              } label: {
                  MenuBarLabel(store: store, preferences: preferences)
              }
              .menuBarExtraStyle(.window)

              Settings {
                  SettingsView(preferences: preferences, scheduler: scheduler, updateStore: updateStore)
              }
      ```
- [ ] Step 4: In `DropdownPanel.swift`, add the property and the conditional link. The property goes directly under `let store: ProviderStore`:
      ```swift
          let updateStore: UpdateStore
      ```
      and the link goes between the existing `Divider()` and the `HStack` that holds Refresh / Settings / Quit, so the panel is unchanged in the common case:
      ```swift
                  Divider()
                  if let line = UpdateStatusText.dropdown(available: updateStore.availableVersion) {
                      Link(destination: UpdateChecker.releasesPageURL) {
                          Label(line, systemImage: "arrow.down.circle.fill")
                      }
                      .font(.caption)
                  }
                  HStack {
      ```
- [ ] Step 5: In `SettingsView.swift`, add the property directly under `let scheduler: RefreshScheduler`:
      ```swift
          let updateStore: UpdateStore
      ```
      and add the row inside `Section("General")`, after the "Launch at login" `Toggle` and before `if let message {`:
      ```swift
                  LabeledContent("Updates") {
                      HStack {
                          Text(UpdateStatusText.settings(status: updateStore.status,
                                                         error: updateStore.error,
                                                         isChecking: updateStore.isChecking))
                              .font(.caption)
                              .foregroundStyle(.secondary)
                          Button("Check now") { Task { await updateStore.check() } }
                              .disabled(updateStore.isChecking)
                      }
                  }
      ```
- [ ] Step 6: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -20` - Expected: `** TEST SUCCEEDED **` and `Executed 27 tests, with 0 failures`, with zero warnings (warnings are errors here).
- [ ] Step 7: Verify - Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tail -5` - Expected: `** BUILD SUCCEEDED **`. Release uses `SWIFT_COMPILATION_MODE = wholemodule` (`project.pbxproj:229`), which surfaces cross-file diagnostics the Debug test build can miss.
- [ ] Step 8: Verify - Run: `grep -rn '"Update available\|"Up to date\|"Checking' Remaindr/Remaindr/UI/ Remaindr/Remaindr/App/; echo "grep_exit=$?"` - Expected: no matching lines and `grep_exit=1`. Every user-visible update string lives in `UpdateStatusText`, so Task 7's tests really are the proxy for what the views render.
- [ ] Step 9: Commit - `git commit -m "feat: surface the update check in the dropdown and Settings"`

---

### Task 9: Tick the shipped items and document the update checker

**Files:**
- Modify: `FUTURE_FEATURES.md` (anchors: `- [ ] Notarize and staple the DMG in ` ~L18; `- [ ] Publish SHA-256 checksums alongside each release download.` ~L19; `- [ ] First-party update checker` ~L21 - all three verified present at `b6a740d`)
- Modify: `README.md` (anchors: `- 🪶 **Zero third-party dependencies**` at the end of "## Features"; `## Privacy & security` list; `## Project structure` code block)

**Interfaces:**
- Consumes: nothing executable. Describes the behaviour built in Tasks 1-8.
- Produces: documentation only.

**Gotcha:** `FUTURE_FEATURES.md` is a hand-maintained checklist, not a generated file, so editing it is allowed. (The repo has no `CHANGELOG.md`; the "never hand-edit an auto-generated changelog" rule lives in the user-level agent instructions, not in this repo's `AGENTS.md`.) Tick exactly the three items this plan delivered and leave the Developer ID line (audit F-01) unticked: no signing identity exists, so that item is genuinely still blocked.

**Steps:**

- [ ] Step 1: In `FUTURE_FEATURES.md`, change the `- [ ]` marker to `- [x]` on exactly the three lines that begin with the following text, leaving the rest of each line byte-identical:
      1. "Notarize and staple the DMG in" (~L18)
      2. "Publish SHA-256 checksums alongside each release download." (~L19)
      3. "First-party update checker (version check against the latest GitHub release" (~L21)
      Do NOT touch the "Developer ID signed Release builds" line (~L17) or any other checkbox in the file.
- [ ] Step 2: In `README.md` "## Features", add one bullet immediately before the `Zero third-party dependencies` bullet:
      ```markdown
      - 🆕 **Update check** — compares the running version against the latest GitHub release once a day and links to the release page; it never downloads or installs anything
      ```
- [ ] Step 3: In `README.md` "## Privacy & security", add one bullet after the existing "No usage data, keys, or telemetry..." bullet:
      ```markdown
      - The update check is a single unauthenticated `GET` to `api.github.com` that sends no key, no identifier, and no usage data; the download link it shows is a fixed URL compiled into the app, never one read out of the response.
      ```
- [ ] Step 4: In `README.md` "## Project structure", add the new group to the tree, after the `Keychain/` entry:
      ```
        Update/
          AppVersion.swift      # dotted version parse + compare
          UpdateChecker.swift   # latest GitHub release lookup
          UpdateStore.swift     # observable state + once-a-day throttle
          UpdateStatusText.swift # the exact strings the UI renders
      ```
- [ ] Step 5: Verify - Run: `grep -c "^- \[x\]" FUTURE_FEATURES.md` - Expected: `3`.
- [ ] Step 6: Verify - Run: `grep -n "Developer ID signed Release builds" FUTURE_FEATURES.md` - Expected: the line is still prefixed `- [ ]`, unticked. Audit F-01 remains blocked on a signing identity.
- [ ] Step 7: Verify - Run: `grep -c "api.github.com" README.md; grep -c "UpdateChecker.swift" README.md` - Expected: `1`, `1`.
- [ ] Step 8: Commit - `git commit -m "docs: record the notarization, checksum, and update-checker work"`

---

## Failure handling summary

- **`REQUIRE_NOTARIZATION=1` gate fires on a machine that DOES have an identity.** Detect: Task 1 Step 5 exits 0, or fails with the `NOTARY_PROFILE` message instead of the identity message. Respond: the Preflight signing entry has drifted. Re-run `security find-identity -v -p codesigning`, record what is actually there, and tick Step 5 against the message that genuinely applies - do not edit the script to force the expected failure.
- **`xcodebuild` fails on `@Observable` or strict-concurrency grounds in Task 6 or 8.** Detect: a Swift 6 isolation diagnostic naming `UpdateStore`. Respond: `ProviderStore` (`UI/ProviderStore.swift:12-24`) is the working precedent for the same shape in this codebase - align with it exactly rather than adding `@unchecked Sendable`, `nonisolated`, or a detached task. If it still fails, STOP: the mismatch is a real design problem, not a fix-forward deviation.
- **The GitHub call returns 403 during the End-to-end live check.** Detect: Settings shows `Check failed: Rate limited`. Respond: confirm with `curl -sI https://api.github.com/repos/theerakarnm/remaindr/releases/latest | grep -i x-ratelimit-remaining`. If it reads `0`, this is the documented 60-per-hour limit, not a defect - wait for `x-ratelimit-reset` and re-run. Do not add an API token to raise the limit; that would put a credential in the app.
- **`hdiutil` or `codesign` fails inside `make-dmg.sh` while `build/dmg-staging` is half-written.** Detect: non-zero exit part way through Task 2 Step 4. Respond: the script is idempotent - it does `rm -rf "$DIST" "$DMG"` at step 2 - so simply re-run it. There is nothing to roll back, and no state outside `build/` is touched.

## End-to-end verification

Run after all nine tasks are committed and the branch is ready to merge.

- [ ] Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath build/DerivedData test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` - Expected: `** TEST SUCCEEDED **`, `Executed 27 tests, with 0 failures (0 unexpected)`, and zero warnings.
- [ ] Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` - Expected: `** BUILD SUCCEEDED **`.
- [ ] Run: `./make-dmg.sh` - Expected: exit 0; a `WARNING: this DMG is NOT notarized` banner on stderr; `Notarized: NO - do not publish this build` on stdout; `Remaindr-1.0.dmg: OK` from the built-in `shasum -c`; and both `build/Remaindr-1.0.dmg` and `build/Remaindr-1.0.dmg.sha256` present afterwards.
- [ ] Run: `env -u NOTARY_PROFILE REQUIRE_NOTARIZATION=1 ./make-dmg.sh; echo "exit=$?"` - Expected: `exit=1` within ~2 seconds, before any `xcodebuild` output, naming the missing Developer ID identity.
- [ ] Run: `hdiutil verify build/Remaindr-1.0.dmg` - Expected: the checksum-verification lines end with a valid result and exit 0.
- [ ] Manual: `curl -s -H "Accept: application/vnd.github+json" https://api.github.com/repos/theerakarnm/remaindr/releases/latest | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['tag_name'], d['draft'], d['prerelease'])"` - Expected: `v1.0.0 False False`, which is exactly the payload `UpdateCheckerTests.testMatchingTagIsUpToDate` asserts against, confirming the live endpoint still matches the shape the parser expects.
- [ ] Manual: `cp ~/.remaindr ~/.remaindr.e2e-backup 2>/dev/null; rm -f ~/.remaindr; open build/DerivedData/Build/Products/Release/Remaindr.app; sleep 20; pgrep -x Remaindr >/dev/null && echo RUNNING; test -f ~/.remaindr && python3 -c "import json;print(sorted(json.load(open('$HOME/.remaindr'))))" || echo "no config file yet"` - Expected: `RUNNING`, and either `no config file yet` or a key list WITHOUT `lastUpdateCheckAt`. This is the correct result, not a failure: `checkIfDue()` hangs off `DropdownPanel`'s `.task`, and `MenuBarExtra(.window)` builds that content view lazily, so nothing is checked until the menu bar icon is first clicked. The next item is what actually triggers it. Leave the app running.

- [ ] Run: `grep -ni "right-click\|not notarized\|bypass\|early-development" README.md; echo "grep_exit=$?"` - Expected: no lines and `grep_exit=1`. Audit F-02's README half is closed.
- [ ] 👤 Human: with the app still running from the previous step, click the menu bar icon and read the dropdown, then open **Settings → General**, then quit the app from the dropdown's Quit button and restore the config with `mv ~/.remaindr.e2e-backup ~/.remaindr 2>/dev/null || true` - Expected: the dropdown shows the three provider rows with **no** update line (the app is current), and Settings shows an `Updates` row reading `Up to date (1.0)` beside a `Check now` button; clicking `Check now` briefly shows `Checking…` and returns to `Up to date (1.0)`. If it instead reads `Update available: 1.0.0`, the zero-padding in `AppVersion` is broken - see Task 4's Gotcha. Afterwards `python3 -c "import json;print(sorted(json.load(open('$HOME/.remaindr'))))"` (run before the restore) must list `lastUpdateCheckAt`, proving the check really fired on first dropdown open and the throttle persisted. - Proxy: `UpdateStatusTextTests` (Task 7, 6 assertions) pins every one of those strings character for character, and `UpdateCheckerTests.testMatchingTagIsUpToDate` (Task 5) pins that the live `v1.0.0` tag resolves to `.upToDate` against the shipped `1.0`; together they prove everything except the rendering.
- [ ] 👤 Human: on a machine with a Developer ID Application certificate installed and a stored notary profile, run `NOTARY_PROFILE=<profile> REQUIRE_NOTARIZATION=1 ./make-dmg.sh`, then on a *second* Mac that has never seen this build, download the DMG and its sidecar and run `shasum -a 256 -c Remaindr-<version>.dmg.sha256` followed by `spctl --assess --type open --context context:primary-signature -vv Remaindr-<version>.dmg` - Expected: the script prints `Notarized: yes, ticket stapled` and exits 0; `stapler validate` and the in-script `spctl` both pass; on the second Mac the checksum reports `OK`, `spctl` reports `accepted` with `source=Notarized Developer ID`, and the DMG opens with a plain double-click and no Gatekeeper prompt. **This is the only unverifiable-by-agent item in the plan** - Preflight records that this machine holds zero code-signing identities, so no agent can reach the Accepted branch. - Proxy: Task 1 Step 5 proves the gate rejects a run that cannot notarize; Task 1 Step 4 and Task 2 Step 3 prove the script parses; Task 2 Steps 4-5 prove the sidecar is produced, correctly formatted, and self-verifying on the ad-hoc path, which is byte-identical machinery to the notarized path apart from the signature. Everything except Apple's own verdict is covered.
