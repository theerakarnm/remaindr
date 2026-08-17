# Keychain Prompt Storm Fix Implementation Plan

> **Run with:** `/execute-plan docs/plans/2026-08-17-keychain-prompt-storm.md` - the runner that ticks these
> checkboxes and honours the track/merge layout below.
>
> **For the executing agent:** Implement this plan in order, in a single worktree.
> Steps use checkbox (`- [ ]`) syntax for tracking; tick them as you go.
> Run the `## Preflight` checks BEFORE task 1 and report anything down.

**Goal:** Stop Remaindr asking for the login keychain password five or six times per run, by never reading secret data when a presence check will do, reading each secret at most once per launch, and saving keys in place instead of destroying and recreating the item.

**Architecture:** All three code changes live inside `KeychainStore`, the single chokepoint every provider and every view already goes through, so no call site changes and the `UsageProvider` boundary is untouched.
A `SecItemCopyMatching` that asks for `kSecValueData` is the operation macOS gates behind the item's ACL and partition list; an attributes-only match is answered from metadata and never prompts.
A process-wide `SecretCache` collapses the repeated data reads the five-minute refresh timer used to make, and caches denials so a refused prompt is not re-asked on the next tick.
`SecItemUpdate` replaces the `SecItemDelete` + `SecItemAdd` pair so a save keeps the item's existing ACL and partition list instead of throwing them away.

**Tech Stack:** Swift 6, Security.framework (`SecItem*`, legacy file-based login keychain), `swiftc -swift-version 6` harnesses for verification, `xcodebuild` for the build gate.

**Spec:** none - planned from conversation. The report is a screenshot of the macOS dialog "security wants to use your confidential information stored in "com.theerakarn.Remaindr.pdmn" in your keychain. To allow this, enter the "login" keychain password." plus the user's statement: "there is many of password prompt that make me annoying. I add password like 5-6 times after I have running this app."

**Base commit:** `78075e1`. Every line reference, anchor, and "already exists" claim below describes THIS tree. When an anchor does not match, run `git log --oneline 78075e1..HEAD` to tell "the plan was wrong" apart from "the file moved on".

**Confidence:** 9/10 - the mechanism and every Expected value below were measured on this machine, not inferred; the single deduction is that `Remaindr/Remaindr/Keychain/KeychainStore.swift` was being edited by a concurrent execution of `docs/plans/2026-08-17-security-audit-fixes.md` while this plan was written (six commits between 09:19 and 09:29), and all three code tasks touch that one file.

**NOT building:**
- Developer ID signing or notarization. It is the only thing that makes "Always Allow" survive an app update (measured: a signed app's partition entry is `teamid:XXXXXXXXXX`, this app's is `cdhash:<one build>`), but it needs a paid Apple Developer account this machine does not have (`security find-identity -v -p codesigning` prints `0 valid identities found`), and `make-dmg.sh` already has the signing hook from the in-flight security plan.
- Moving items to the data protection keychain (`kSecUseDataProtectionKeychain: true`), which has no ACL prompts at all. Measured on this machine: an entitlement-free binary gets `SecItemAdd` status `-34018` (`errSecMissingEntitlement`), so this is unreachable until the app is signed with a real Team ID and carries a `keychain-access-groups` entitlement. Revisit only after Developer ID signing lands.
- Loosening the items' ACL to "allow all applications" (`SecAccessCreate` with a nil trusted-application list). It would silence the prompts by letting any process on the machine read the API keys, which contradicts `Remaindr/Remaindr/Keychain/KeychainStore.swift:8-9` and `SECURITY_AUDIT.md`.
- Removing or re-scoping `upgradeAccessibility()` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:71-78`). It is already gated to run once by `preferences.keychainAccessibilityUpgraded` (`Remaindr/Remaindr/App/RemaindrApp.swift:11-14`), and Task 3 makes its rewrite prompt-free. See the note under Diagnosis for the measured fact that makes it a no-op on this keychain; that is the in-flight security plan's call to make, not this one's.
- Consolidating the z.ai and DeepSeek keys into one keychain item. It would cut the worst-case per-build prompt count from three to two, at the cost of a storage-format migration; not worth it once each item costs at most one prompt per launch.
- Any new UI, setting, toggle, or onboarding screen.

## Diagnosis - measured, not assumed

Every claim here was produced by running code against this machine's login keychain on macOS 26.2 (`sw_vers`), not inferred from documentation.

**1. Reading `kSecValueData` is gated; reading attributes is not.**
A binary whose code signature is not in an item's partition list, with `SecKeychainSetUserInteractionAllowed(false)` so a gated call fails instead of showing a modal:

```
zai: kSecReturnData=true                             status -25293 (errSecAuthFailed - would prompt)
zai: kSecReturnAttributes=true (presence only)       OK (no prompt)
deepseek: kSecReturnData=true                        status -25293
deepseek: kSecReturnAttributes=true (presence only)  OK (no prompt)
foreign Claude Code-credentials: data                status -25293
foreign Claude Code-credentials: attrs only          OK (no prompt)
```

**2. The app asks for data five times per refresh cycle, and `hasKey` is three of them.**
`hasKey(for:)` is implemented as `((try? value(for: kind)) ?? nil) != nil` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:80-82`), so every presence check is a full secret read.
Per cycle: `ProviderStore.anyConfigured` calls it for z.ai and DeepSeek (`Remaindr/Remaindr/UI/ProviderStore.swift:28`) on `RefreshScheduler.start()` and again on every tick (`Remaindr/Remaindr/Refresh/RefreshScheduler.swift:18-27`), then `refreshAll` reads the z.ai key (`Remaindr/Remaindr/Providers/ZAIProvider.swift:30`), the DeepSeek key (`Remaindr/Remaindr/Providers/DeepSeekProvider.swift:32`), and Claude Code's credential blob (`Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift:30`).
Opening Settings adds three more (`Remaindr/Remaindr/UI/SettingsView.swift:87`).
Nothing caches, so answering "Allow" rather than "Always Allow" means being asked again five minutes later, forever.

**3. The grant is pinned to one exact build.**
Dumping the `Partitions` ACL entry of the live items:

```
[a Developer ID signed browser]  partitions: teamid:<10-char team id>, teamid:<10-char team id>
[a second signed browser]        partitions: teamid:<10-char team id>
[Claude Code-credentials]        partitions: apple-tool:, cdhash:f3004479c1920aa471d3a5c6fe8ec31f03b37e93
[com.theerakarn.Remaindr]        partitions: cdhash:f3004479c1920aa471d3a5c6fe8ec31f03b37e93
```

Re-run it yourself with `SecKeychainItemCopyAccess` + `SecAccessCopyACLList` and decode the hex `Partitions` plist; the three third-party team identifiers are redacted here because this file is committed.

That cdhash is exactly `codesign -dvvv build/dmg-staging/Remaindr.app`'s `CDHash`, and its ACL names the trusted application as `/Volumes/Remaindr/Remaindr.app`, the DMG mount point.
Properly signed apps get a `teamid:` partition that survives every update; an ad-hoc signature gets a `cdhash:` partition that dies with the next build.
This is why "Always Allow" appears not to stick, and it is not fixable in code - see NOT building.

**4. After a rebuild, saving a key fails outright.**
`set(_:for:)` deletes then adds (`Remaindr/Remaindr/Keychain/KeychainStore.swift:36-42`).
Running the current `set` from a binary the item does not belong to returns `SAVE=threw unexpectedStatus(-25299)` - the delete is refused, then `SecItemAdd` hits `errSecDuplicateItem`, and `SettingsView` shows "Could not save the key to the Keychain." (`Remaindr/Remaindr/UI/SettingsView.swift:136`).
`SecItemUpdate` from the same foreign binary returns `errSecSuccess` with no prompt.

**5. Two things this plan deliberately records without acting on.**
The `.pdmn` suffix in the screenshot's item name is unexplained: `pdmn` is the data protection keychain's internal key for `kSecAttrAccessible`, but adding an item with `kSecAttrAccessible` to this file-based keychain creates no such item and stores no such attribute - a freshly written item reports attribute keys `acct, cdat, class, labl, mdat, svce` and `kSecAttrAccessible` reads back `<ABSENT>`.
The suffix is cosmetic and changes nothing about the fix.
The same measurement means `upgradeAccessibility()` can never observe its own effect on this keychain; it is already gated to run once, and Task 3 makes its rewrite prompt-free, so this plan leaves it alone.

## Global Constraints

- API keys live in the macOS Keychain only. Never `UserDefaults`, never plaintext, never logged, never committed. (`AGENTS.md`, Hard rules)
- No third-party Swift packages. (`AGENTS.md`, Hard rules)
- The UI layer never talks to a provider directly, only through `UsageProvider`; do not weaken that boundary. (`AGENTS.md`, Architecture)
- Do not change the `UsageProvider` protocol shape. (`AGENTS.md`, Stop and ask before)
- One provider failing must never blank or zero out the others. (`AGENTS.md`, Hard rules)
- Only make the change directly requested. No features, abstractions, onboarding flows, or files beyond what was asked. (`AGENTS.md`, Hard rules)
- Build must succeed with zero warnings before a task is considered done. (`AGENTS.md`, Commands)
- Never use the em dash character. Use a plain dash instead. (user instructions)
- Swift 6 language mode, macOS 14 deployment target: `SWIFT_VERSION = 6.0`, `MACOSX_DEPLOYMENT_TARGET = 14.0` (`Remaindr/Remaindr.xcodeproj/project.pbxproj:136-157`). Every new type must satisfy strict concurrency checking.
- No live provider API call is made by anything in this plan. Every verification is local Keychain work against a throwaway `com.theerakarn.Remaindr.verify` service.

## Patterns to Mirror

### Keychain query construction
<!-- SOURCE: Remaindr/Remaindr/Keychain/KeychainStore.swift:21-27 -->
```swift
    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
```

Build on `query(_:)` and mutate a local copy; never assemble a competing dictionary literal for this app's own items.

### Error handling
<!-- SOURCE: Remaindr/Remaindr/Keychain/KeychainStore.swift:4-6,51-55 -->
```swift
enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}
```
```swift
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
```

A missing item is `nil`, not an error; any other non-success `OSStatus` is `KeychainError.unexpectedStatus`, and the failing value itself never appears in the error.

### Doc comments carry the reasoning
<!-- SOURCE: Remaindr/Remaindr/Keychain/KeychainStore.swift:84-86 -->
```swift
    /// Reads a generic-password item another app stored, such as Claude Code's OAuth
    /// credential. Read-only: this app never writes or deletes a foreign item, and the
    /// value never leaves memory except into a request header.
```

Every non-obvious decision in this file is explained in a `///` comment saying why, not what. Match that.

### Concurrency
<!-- SOURCE: Remaindr/Remaindr/Keychain/KeychainStore.swift:10, Remaindr/Remaindr/UI/ProviderStore.swift:11-13 -->
```swift
struct KeychainStore: Sendable {
```
```swift
@MainActor
@Observable
final class ProviderStore {
```

`KeychainStore` is a `Sendable` value type reached from a `withTaskGroup` off the main actor (`Remaindr/Remaindr/UI/ProviderStore.swift:54-64`), so anything it touches must be safe from multiple threads without an actor hop.

### Verification harness
<!-- SOURCE: docs/plans/2026-08-16-aiusagebar-menu-bar-app.md:755-775 -->
```bash
mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/main.swift <<'EOF'
import Foundation
let store = KeychainStore(service: "com.theerakarn.AIUsageBar.verify")
try store.set("sk-verify-123", for: .deepseek)
print("READBACK=\(try store.value(for: .deepseek) ?? "nil")")
EOF
swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/keychain && /tmp/aiub-verify/keychain
```

The repo has no test target, so deterministic checks compile the real source files together with a throwaway `main.swift` and assert exact stdout.
Two details this plan depends on: the harness file must be named `main.swift` (Swift only allows top-level statements in that filename), and each harness needs its own directory so several can coexist.

### Tests

No test target exists: `xcodebuild -project Remaindr/Remaindr.xcodeproj -list` reports exactly one target, `Remaindr`, and `git ls-files | grep -ci test` is 0.
Establishing new convention: none. This plan reuses the `swiftc` harness precedent above rather than introducing XCTest.

## Preflight

### DURABLE - true until the repo itself changes

- **No test target; verification is `swiftc` harnesses.** Evidence: `xcodebuild -project Remaindr/Remaindr.xcodeproj -list` printed `Targets:` then only `Remaindr`. Consequence: every Verify below is a `swiftc` harness plus `xcodebuild build`, never `xcodebuild test`.
- **A `swiftc` harness can round-trip the Keychain with no GUI prompt for items it creates itself.** Evidence: `SEED=wrote present=true` from a freshly compiled harness. Consequence: Tasks 1-3 are real `Verify - Run` steps, not Human checks.
- **The app is ad-hoc signed and its keychain grants are pinned to one build.** Evidence: `codesign -dvvv build/dmg-staging/Remaindr.app` prints `Signature=adhoc`, `TeamIdentifier=not set`; the live items' partition list is `cdhash:f3004479c1920aa471d3a5c6fe8ec31f03b37e93`. Consequence: after this plan lands, a fresh build still asks once per item on first launch. That is expected, is called out in Task 4's README text, and is NOT a failure of the End-to-end verification.
- **The data protection keychain is unavailable to this app.** Evidence: `SecItemAdd` with `kSecUseDataProtectionKeychain: true` from an entitlement-free binary returned `-34018`. Consequence: the NOT-building entry stands; do not "fix" the prompts that way mid-run.
- **This keychain silently drops `kSecAttrAccessible`.** Evidence: an item added with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` reads back attribute keys `acct, cdat, class, labl, mdat, svce` and `kSecAttrAccessible` as `<ABSENT>`. Consequence: Task 3 keeps passing the attribute (harmless, and correct if the app ever moves keychains) and does not build any logic on reading it back.
- **`SecItemUpdate` is not ACL-gated where `SecItemDelete` is.** Evidence: from a binary outside the item's partition list, `SecItemUpdate` returned `OK (no prompt)` while `SecItemDelete` returned `-25244`. Consequence: Task 3's approach is sound.

### PERISHABLE - recapture before task 1

- **A concurrent agent was executing `docs/plans/2026-08-17-security-audit-fixes.md` against this same file.** Check: `git log --format='%h %ad %s' --date=format:'%H:%M:%S' -5 && git status --porcelain && md5 -q Remaindr/Remaindr/Keychain/KeychainStore.swift` - the file was `a86bdb722b1c76ce46a3080ad397b36a` at `78075e1`. Needed by: Tasks 1, 2, 3, which all edit that file. If the hash differs, re-read the file and re-anchor before editing; if the working tree is dirty or that plan still has unticked tasks touching `KeychainStore.swift`, STOP and ask rather than racing it.
- **Baseline build is green with zero warnings.** Check: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Debug -derivedDataPath /tmp/kc-dd build 2>&1 | tee /tmp/kc-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/kc-build.log || true)"` - recorded: `** BUILD SUCCEEDED **` and `warnings=0`, in about 13 seconds. Needed by: every task's Verify, which asserts the same two lines.
- **No leftover verify items in the login keychain.** Check: `security find-generic-password -s com.theerakarn.Remaindr.verify >/dev/null 2>&1 && echo LEFTOVER || echo clean` - recorded: `clean`. Needed by: Tasks 1-3, whose harnesses seed and delete under that service. If it prints `LEFTOVER`, clear it with the Rollback command on Task 1 before starting.
- **The user's real keys may or may not be stored.** Check: `for a in zai deepseek anthropic; do security find-generic-password -s com.theerakarn.Remaindr -a $a >/dev/null 2>&1 && echo "$a present" || echo "$a absent"; done` - recorded: `zai present`, `deepseek present`, `anthropic absent`. Needed by: the End-to-end verification only. No task Expected depends on it; the task harnesses use the throwaway `.verify` service precisely so they do not.

## Execution

**Tracks:**
- Single sequential track. Tasks 1, 2 and 3 all edit `Remaindr/Remaindr/Keychain/KeychainStore.swift`, so they cannot run concurrently, and Task 4 documents the behaviour the first three produce.

**Merge order:** not applicable - one branch, tasks in order 1, 2, 3, 4.
**Shared files:** `Remaindr/Remaindr/Keychain/KeychainStore.swift` is touched by Tasks 1, 2 and 3, which is why the plan is sequential. No barrel file, no schema, no dependency manifest, no migration directory, and no route registration exists in this project to contend over.
**Worktree setup:** none. A single-track plan does not earn a `treehouse` worktree (the cost floor is 3 tasks or 5 files per track); work in the repo directory on the current branch.

---

### Task 1: Presence check stops reading the secret

**Files:**
- Modify: `Remaindr/Remaindr/Keychain/KeychainStore.swift` (anchor: `/// Cheap presence check for the Settings UI`, ~L79-82)
- Harness (throwaway, written by Step 2, never committed): `/tmp/kc-verify/seed/main.swift`, `/tmp/kc-verify/check/main.swift`

**Interfaces:**
- Consumes: `ProviderKind.keychainAccount` (`Remaindr/Remaindr/Models/ProviderStatus.swift:33-39`) and the existing `private func query(_ account: String) -> [String: Any]`.
- Produces: `func hasKey(for kind: ProviderKind) -> Bool` - signature unchanged, so the four call sites (`Remaindr/Remaindr/UI/ProviderStore.swift:28`, `Remaindr/Remaindr/UI/SettingsView.swift:87,132,144`) need no edit.

**Gotcha:** the answer changes meaning in one edge case, and that is the point.
Today `hasKey` returns `false` for an item that exists but whose read was denied, so a configured provider silently reports "Not configured" and Settings shows "Not set" over a saved key.
After this change it returns `true` for any item that exists, whether or not this build may read it.

**Rollback:** ordinary code change - `git revert` is the answer. If Preflight found a leftover verify item, clear it with `security delete-generic-password -s com.theerakarn.Remaindr.verify -a deepseek 2>/dev/null; security delete-generic-password -s com.theerakarn.Remaindr.verify -a zai 2>/dev/null; true`.

**Steps:**
- [ ] Step 1: In `Remaindr/Remaindr/Keychain/KeychainStore.swift`, replace the whole `hasKey(for:)` member - the doc comment on line 79 through the closing brace on line 82 - with:

      ```swift
      /// Cheap presence check for the Settings UI and for pausing the refresh timer.
      /// It must never ask for `kSecValueData`: the data read is the operation macOS gates
      /// behind the item's ACL and partition list, and answering it costs the user a login
      /// keychain password prompt. An attributes-only match is served from the item's
      /// metadata and never prompts. Measured on macOS 26.2 with prompts disabled: the data
      /// query returns errSecAuthFailed (-25293), the attributes query returns errSecSuccess.
      /// The trade is deliberate - this now answers "does the item exist", not "can this
      /// build read it", so a saved key stops reading as "Not set" after an app update.
      func hasKey(for kind: ProviderKind) -> Bool {
          guard let account = kind.keychainAccount else { return false }
          var attributes = query(account)
          attributes[kSecReturnAttributes as String] = true
          attributes[kSecMatchLimit as String] = kSecMatchLimitOne
          var result: CFTypeRef?
          return SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess
      }
      ```

- [ ] Step 2: Verify - Run:

      ```bash
      rm -rf /tmp/kc-verify && mkdir -p /tmp/kc-verify/seed /tmp/kc-verify/check
      cat > /tmp/kc-verify/seed/main.swift <<'EOF'
      import Foundation
      let store = KeychainStore(service: "com.theerakarn.Remaindr.verify")
      if CommandLine.arguments.contains("clean") {
          try? store.remove(.deepseek)
          print("SEED=cleaned")
      } else {
          try? store.remove(.deepseek)
          try store.set("probe-secret", for: .deepseek)
          print("SEED=wrote")
      }
      EOF
      cat > /tmp/kc-verify/check/main.swift <<'EOF'
      import Foundation
      import Security
      // A different binary from the seeder, so its code signature is absent from the item's
      // partition list - exactly the position the app is in after any rebuild. Prompts are
      // disabled, so a gated operation fails instead of blocking on a modal dialog.
      SecKeychainSetUserInteractionAllowed(false)
      let store = KeychainStore(service: "com.theerakarn.Remaindr.verify")
      print("PRESENCE=\(store.hasKey(for: .deepseek))")
      EOF
      SRC="Remaindr/Remaindr/Models/ProviderStatus.swift Remaindr/Remaindr/Keychain/KeychainStore.swift"
      swiftc -swift-version 6 $SRC /tmp/kc-verify/seed/main.swift  -o /tmp/kc-verify/seed  2>/dev/null
      swiftc -swift-version 6 $SRC /tmp/kc-verify/check/main.swift -o /tmp/kc-verify/check 2>/dev/null
      /tmp/kc-verify/seed && /tmp/kc-verify/check && /tmp/kc-verify/seed clean
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Debug -derivedDataPath /tmp/kc-dd build 2>&1 | tee /tmp/kc-build.log | tail -1
      echo "warnings=$(grep -c ': warning: ' /tmp/kc-build.log || true)"
      ```

      Expected, exactly these five lines:

      ```
      SEED=wrote
      PRESENCE=true
      SEED=cleaned
      ** BUILD SUCCEEDED **
      warnings=0
      ```

      `PRESENCE=false` is the pre-change behaviour and means the edit did not take.

- [ ] Step 3: Commit - `git add Remaindr/Remaindr/Keychain/KeychainStore.swift && git commit -m "fix(keychain): answer presence checks from item metadata, not the secret"`

---

### Task 2: Read each secret at most once per launch

**Files:**
- Modify: `Remaindr/Remaindr/Keychain/KeychainStore.swift` (anchors: `/// The only place an API key is ever read or written.` ~L8, `private func query(_ account: String)` ~L21, `func value(for kind: ProviderKind)` ~L45, `func remove(_ kind: ProviderKind)` ~L59, `func foreignValue(service: String)` ~L87)
- Harness (throwaway, written by Step 4, never committed): `/tmp/kc-verify/cache/main.swift`

**Interfaces:**
- Consumes: `KeychainError.unexpectedStatus(OSStatus)` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:4-6`), `private func query(_ account: String) -> [String: Any]`.
- Produces: `func value(for kind: ProviderKind) throws -> String?` and `func foreignValue(service: String) throws -> String?` - both signatures unchanged, so `ZAIProvider.fetch`, `DeepSeekProvider.fetch`, `ClaudeProvider.fetch` and `ClaudeAccountUsage.accessToken` need no edit. New private `final class SecretCache`, not visible outside the file.

**Gotcha:** three things that are easy to get wrong here.
`entries[key]` on a `[String: Result<String?, KeychainError>]` yields a double optional, so `if let cached = entries[key] { return try cached.get() }` is the correct shape and does exactly one dictionary lookup.
The lock is held across the `read` closure on purpose: `ProviderStore.refreshAll` fetches all three providers inside one `withTaskGroup` (`Remaindr/Remaindr/UI/ProviderStore.swift:54-64`), and without that the same item could raise two dialogs at once.
`SecretCache` cannot be an `actor`, because `value(for:)` is a synchronous throwing function called from non-async code; `@unchecked Sendable` with an `NSLock` is the shape that satisfies Swift 6 strict concurrency here.

**Rollback:** ordinary code change - `git revert` is the answer.

**Steps:**
- [ ] Step 1: In `Remaindr/Remaindr/Keychain/KeychainStore.swift`, insert the cache immediately above the `/// The only place an API key is ever read or written.` doc comment (line 8), so it sits between `KeychainError` and `KeychainStore`:

      ```swift
      /// Process-wide cache of the secret material already read out of the Keychain.
      ///
      /// Reading `kSecValueData` is the operation macOS gates behind the item's ACL and
      /// partition list, so an uncached read is a possible "enter the login keychain
      /// password" dialog. The refresh timer fires every `refreshIntervalMinutes` and each
      /// cycle re-read the z.ai key, the DeepSeek key and Claude Code's credential blob, so
      /// a user who answered "Allow" rather than "Always Allow" was asked again on every
      /// tick, forever. Caching makes any one item cost at most one prompt per app launch.
      ///
      /// Failures are cached too, deliberately: a denied read retried every five minutes
      /// re-prompts every five minutes. A cached `.success(nil)` means "asked, nothing
      /// there". Values live in memory only - nothing here is written to disk or logged.
      private final class SecretCache: @unchecked Sendable {
          static let shared = SecretCache()

          private let lock = NSLock()
          private var entries: [String: Result<String?, KeychainError>] = [:]

          /// `read` runs at most once per key for the lifetime of the process. The lock is
          /// held across it on purpose: two providers refreshing concurrently must not
          /// stack two dialogs for the same item.
          func value(forKey key: String, read: () -> Result<String?, KeychainError>) throws -> String? {
              lock.lock()
              defer { lock.unlock() }
              if let cached = entries[key] { return try cached.get() }
              let fresh = read()
              entries[key] = fresh
              return try fresh.get()
          }

          func invalidate(_ key: String) {
              lock.lock()
              defer { lock.unlock() }
              entries.removeValue(forKey: key)
          }
      }

      ```

- [ ] Step 2: In the same file, add the cache key helper and the single gated read directly after the closing brace of `query(_:)` (line 27):

      ```swift

          private func cacheKey(_ account: String) -> String { "\(service)/\(account)" }

          /// The one place `kSecValueData` is requested. Every call is a possible Keychain
          /// prompt, which is why `SecretCache` wraps it.
          private static func readData(_ base: [String: Any]) -> Result<String?, KeychainError> {
              var attributes = base
              attributes[kSecReturnData as String] = true
              attributes[kSecMatchLimit as String] = kSecMatchLimitOne
              var result: CFTypeRef?
              let status = SecItemCopyMatching(attributes as CFDictionary, &result)
              if status == errSecItemNotFound { return .success(nil) }
              guard status == errSecSuccess, let data = result as? Data else {
                  return .failure(.unexpectedStatus(status))
              }
              return .success(String(data: data, encoding: .utf8))
          }
      ```

- [ ] Step 3: In the same file, route the three readers and the two writers through the cache.
      Replace the whole `value(for:)` member (lines 45-57) with:

      ```swift
          /// Reads the stored key, at most once per process. See `SecretCache`.
          func value(for kind: ProviderKind) throws -> String? {
              guard let account = kind.keychainAccount else { return nil }
              let base = query(account)
              return try SecretCache.shared.value(forKey: cacheKey(account)) {
                  Self.readData(base)
              }
          }
      ```

      Replace the whole `foreignValue(service:)` member (doc comment on line 84 through its closing brace on line 101) with:

      ```swift
          /// Reads a generic-password item another app stored, such as Claude Code's OAuth
          /// credential. Read-only: this app never writes or deletes a foreign item, and the
          /// value never leaves memory except into a request header. Read at most once per
          /// process: the item belongs to another app, so its ACL cannot list this one until
          /// the user grants access by hand, and re-reading it every refresh means re-asking
          /// every refresh.
          func foreignValue(service: String) throws -> String? {
              let base: [String: Any] = [
                  kSecClass as String: kSecClassGenericPassword,
                  kSecAttrService as String: service,
              ]
              return try SecretCache.shared.value(forKey: "foreign/\(service)") {
                  Self.readData(base)
              }
          }
      ```

      In `set(_:for:)`, insert `SecretCache.shared.invalidate(cacheKey(account))` as the line directly above the `// SecItemAdd returns errSecDuplicateItem` comment (line 36).
      In `remove(_:)`, insert the same call directly above `let status = SecItemDelete(query(account) as CFDictionary)` (line 61).

- [ ] Step 4: Verify - Run:

      ```bash
      mkdir -p /tmp/kc-verify/cache
      cat > /tmp/kc-verify/cache/main.swift <<'EOF'
      import Foundation
      import Security
      // One binary, so it owns the item and its first read succeeds. The item is then
      // deleted behind the store's back: a cached value survives that, an uncached one
      // does not, which is the difference this task introduces.
      let store = KeychainStore(service: "com.theerakarn.Remaindr.verify")
      try? store.remove(.zai)
      try store.set("probe-secret", for: .zai)
      let first = try store.value(for: .zai) ?? "nil"
      let raw: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.theerakarn.Remaindr.verify",
          kSecAttrAccount as String: "zai",
      ]
      let deleted = SecItemDelete(raw as CFDictionary)
      let second = (try? store.value(for: .zai)) ?? "nil"
      print("CACHE first=\(first) deleted=\(deleted) second=\(second ?? "nil")")
      EOF
      SRC="Remaindr/Remaindr/Models/ProviderStatus.swift Remaindr/Remaindr/Keychain/KeychainStore.swift"
      swiftc -swift-version 6 $SRC /tmp/kc-verify/cache/main.swift -o /tmp/kc-verify/cache-run 2>/dev/null
      /tmp/kc-verify/cache-run
      security delete-generic-password -s com.theerakarn.Remaindr.verify -a zai >/dev/null 2>&1; true
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Debug -derivedDataPath /tmp/kc-dd build 2>&1 | tee /tmp/kc-build.log | tail -1
      echo "warnings=$(grep -c ': warning: ' /tmp/kc-build.log || true)"
      ```

      Expected, exactly these three lines:

      ```
      CACHE first=probe-secret deleted=0 second=probe-secret
      ** BUILD SUCCEEDED **
      warnings=0
      ```

      `second=nil` is the pre-change behaviour and means the read is still going to the Keychain every time.

- [ ] Step 5: Commit - `git add Remaindr/Remaindr/Keychain/KeychainStore.swift && git commit -m "fix(keychain): read each secret at most once per launch"`

---

### Task 3: Save a key in place instead of destroying the item

**Files:**
- Modify: `Remaindr/Remaindr/Keychain/KeychainStore.swift` (anchor: `// SecItemAdd returns errSecDuplicateItem for an existing account, so replace.`, ~L36-42 at base, shifted down by Task 2)
- Harness (throwaway, written by Step 2, never committed): `/tmp/kc-verify/save/main.swift`, reusing `/tmp/kc-verify/seed/main.swift` from Task 1

**Interfaces:**
- Consumes: `KeychainStore.accessibility` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:19`), `private func query(_ account: String) -> [String: Any]`, `SecretCache.invalidate(_:)` from Task 2.
- Produces: `func set(_ value: String, for kind: ProviderKind) throws` - signature unchanged, so `SettingsView.save` (`Remaindr/Remaindr/UI/SettingsView.swift:130`) and `upgradeAccessibility` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:71-78`) need no edit.

**Gotcha:** `SecItemUpdate`'s second argument carries only the attributes to change, never `kSecClass`, `kSecAttrService` or `kSecAttrAccount` - those stay in the query.
Passing `kSecAttrAccessible` in the update dictionary is accepted by this keychain (measured: `errSecSuccess`) even though it stores nothing, so keep it for the day the app moves to the data protection keychain.
`errSecItemNotFound` from the update is the ordinary first-save path, not a failure; every other non-success status is a real error and must throw.

**Rollback:** ordinary code change - `git revert` is the answer. The task writes only to `com.theerakarn.Remaindr.verify`, cleaned up by its own Verify.

**Steps:**
- [ ] Step 1: In `Remaindr/Remaindr/Keychain/KeychainStore.swift`, replace the body of `set(_:for:)` from the `// SecItemAdd returns errSecDuplicateItem` comment through the `guard status == errSecSuccess else { throw ... }` line with:

      ```swift
              let data = Data(trimmed.utf8)
              // Update in place when the item already exists. The previous delete-then-add
              // cycle threw the item's ACL and partition list away along with the item, so
              // every save re-authorised the app from scratch - and once the running build's
              // signature no longer matched the item, SecItemDelete was itself refused and
              // SecItemAdd then failed with errSecDuplicateItem, surfacing as "Could not
              // save the key to the Keychain." SecItemUpdate needs no authorisation and
              // preserves both lists. Measured: update returns errSecSuccess where delete
              // returns -25244 from a signature the item does not know.
              var updates: [String: Any] = [kSecValueData as String: data]
              updates[kSecAttrAccessible as String] = Self.accessibility
              let updateStatus = SecItemUpdate(query(account) as CFDictionary, updates as CFDictionary)
              if updateStatus == errSecSuccess { return }
              guard updateStatus == errSecItemNotFound else {
                  throw KeychainError.unexpectedStatus(updateStatus)
              }
              var attributes = query(account)
              attributes[kSecValueData as String] = data
              attributes[kSecAttrAccessible as String] = Self.accessibility
              let status = SecItemAdd(attributes as CFDictionary, nil)
              guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
      ```

      Keep the `SecretCache.shared.invalidate(cacheKey(account))` line Task 2 added as the first statement after the blank-value guard.

- [ ] Step 2: Verify - Run:

      ```bash
      mkdir -p /tmp/kc-verify/save
      cat > /tmp/kc-verify/save/main.swift <<'EOF'
      import Foundation
      import Security
      // A different binary from the seeder: saving over an item this signature does not own
      // is what a user does after every app update. Prompts are disabled so the call fails
      // instead of blocking on a modal dialog.
      SecKeychainSetUserInteractionAllowed(false)
      let store = KeychainStore(service: "com.theerakarn.Remaindr.verify")
      do {
          try store.set("replacement-secret", for: .deepseek)
          print("SAVE=ok")
      } catch {
          print("SAVE=threw \(error)")
      }
      EOF
      SRC="Remaindr/Remaindr/Models/ProviderStatus.swift Remaindr/Remaindr/Keychain/KeychainStore.swift"
      swiftc -swift-version 6 $SRC /tmp/kc-verify/seed/main.swift -o /tmp/kc-verify/seed 2>/dev/null
      swiftc -swift-version 6 $SRC /tmp/kc-verify/save/main.swift -o /tmp/kc-verify/save-run 2>/dev/null
      /tmp/kc-verify/seed && /tmp/kc-verify/save-run && /tmp/kc-verify/seed clean
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Debug -derivedDataPath /tmp/kc-dd build 2>&1 | tee /tmp/kc-build.log | tail -1
      echo "warnings=$(grep -c ': warning: ' /tmp/kc-build.log || true)"
      ```

      Expected, exactly these five lines:

      ```
      SEED=wrote
      SAVE=ok
      SEED=cleaned
      ** BUILD SUCCEEDED **
      warnings=0
      ```

      `SAVE=threw unexpectedStatus(-25299)` is the pre-change behaviour: the delete was refused and the add hit `errSecDuplicateItem`.

- [ ] Step 3: Commit - `git add Remaindr/Remaindr/Keychain/KeychainStore.swift && git commit -m "fix(keychain): update items in place so a save keeps its access grant"`

---

### Task 4: Tell the user what the remaining prompt means

**Files:**
- Modify: `README.md` (anchor: `## Troubleshooting`, ~L138-146)

**Interfaces:**
- Consumes: the behaviour Tasks 1-3 produce. Nothing consumes this task.

**Gotcha:** the README is user-facing, so it must not promise the prompt is gone.
After this plan the app asks at most once per keychain item on the first launch of a given build, and asks again after an app update because the build is ad-hoc signed.
Do not soften that into "you will not be asked again".

**Rollback:** ordinary docs change - `git revert` is the answer.

**Steps:**
- [ ] Step 1: In `README.md`, add one row to the Troubleshooting table, directly after the `| Collapsed label missing | ... |` row:

      ```markdown
      | macOS asks for your login keychain password | Expected once per key after installing or updating the app - see below |
      ```

- [ ] Step 2: In `README.md`, add this subsection immediately after the Troubleshooting table and before `## Roadmap`:

      ```markdown
      ### Why macOS asks for the keychain password

      Remaindr reads three keychain items: your z.ai key, your DeepSeek key, and the OAuth
      credential Claude Code already stores. macOS asks you to authorise each item the first
      time a given build of the app reads it. Choose **Always Allow** and that build will not
      ask again.

      A release of Remaindr is ad-hoc signed, which means macOS records the grant against
      that exact build rather than against a developer identity. Installing a new version
      therefore asks once more per key. A Developer ID signed build would record the grant
      against the identity instead and never re-ask; that is on the roadmap.

      If you are asked repeatedly *within a single run*, that is a bug - please open an issue.
      ```

- [ ] Step 3: Verify - Run:

      ```bash
      grep -c 'Why macOS asks for the keychain password' README.md
      grep -c 'macOS asks for your login keychain password' README.md
      git diff -- README.md | grep '^+' | LC_ALL=C grep -c $'\xe2\x80\x94'; true
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Debug -derivedDataPath /tmp/kc-dd build 2>&1 | tee /tmp/kc-build.log | tail -1
      echo "warnings=$(grep -c ': warning: ' /tmp/kc-build.log || true)"
      ```

      Expected, exactly these five lines:

      ```
      1
      1
      0
      ** BUILD SUCCEEDED **
      warnings=0
      ```

      The third line is a count of the em dash character in the added README lines; the repo forbids it, so it must be `0`.

- [ ] Step 4: Commit - `git add README.md && git commit -m "docs: explain the keychain password prompt and when it recurs"`

## Failure handling summary

- **A Verify prints a keychain status other than the Expected one (`-25293`, `-25299`, `-25244`, `-34018`).** Detect: the harness line differs from the Expected block. Respond: do NOT relax the Expected. Re-run the Preflight leftover check, clear `com.theerakarn.Remaindr.verify` with the Task 1 Rollback command, and re-run once. If it still differs, STOP and report the exact status - the mechanism this plan is built on has changed.
- **A modal keychain dialog appears while running a Verify.** Detect: the harness hangs instead of printing. Respond: the harness lost its `SecKeychainSetUserInteractionAllowed(false)` line. Cancel, restore the line, re-run. Never answer the dialog to make a Verify pass - that grants the harness binary access and destroys the test's meaning.
- **`Remaindr/Remaindr/Keychain/KeychainStore.swift` differs from md5 `a86bdb722b1c76ce46a3080ad397b36a`.** Detect: the PERISHABLE Preflight check. Respond: re-read the file, confirm the concurrent security-audit plan is not mid-task in it, re-anchor the edits by symbol rather than line number, and note the drift on the task. If that plan still has unticked steps touching this file, STOP and ask.

## End-to-end verification

Run after all four tasks are committed.

- [ ] Run: `git diff --name-only HEAD~4..HEAD` - Expected: exactly two paths, `README.md` and `Remaindr/Remaindr/Keychain/KeychainStore.swift`. Anchored on this plan's own four commits rather than on the base sha, because a concurrent plan may have landed commits in between.
- [ ] Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -derivedDataPath /tmp/kc-dd-release build 2>&1 | tee /tmp/kc-release.log | tail -1; echo "warnings=$(grep -c ': warning: ' /tmp/kc-release.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [ ] Run: `grep -c 'kSecReturnData' Remaindr/Remaindr/Keychain/KeychainStore.swift` - Expected: `1`. The whole file must request secret data from exactly one place, `readData(_:)`, which is what makes the cache the only door.
- [ ] Run: `grep -n 'SecItemDelete' Remaindr/Remaindr/Keychain/KeychainStore.swift` - Expected: exactly one hit, inside `remove(_:)`. `set(_:for:)` must no longer delete.
- [ ] Manual: launch the Release build with prompts observable and count the dialogs: `/tmp/kc-dd-release/Build/Products/Release/Remaindr.app/Contents/MacOS/Remaindr & sleep 45; osascript -e 'tell application "System Events" to count (every window of (every process whose name is "SecurityAgent"))'; kill %1` - Expected: `0` after the user has answered "Always Allow" once per item for this build, and never more than three distinct dialogs (z.ai, DeepSeek, Claude Code credential) on the first launch of a build. Before this plan the same 45 seconds produced a dialog per item per refresh cycle.
- [ ] Manual: `security find-generic-password -s com.theerakarn.Remaindr -a zai >/dev/null 2>&1 && echo present` then open Settings in the running app - Expected: `present`, and the z.ai row shows the green "Set" badge rather than "Not set". This is the user-visible half of Task 1: before the fix a denied read made a saved key read as unset.
- [ ] 👤 Human: leave the app running for at least three refresh intervals (15 minutes at the default `refreshIntervalMinutes = 5`), answering the first prompt for each item with **Always Allow** - Expected: no further keychain password dialog appears after the first cycle, for the whole session. Proxy: the `CACHE first=probe-secret deleted=0 second=probe-secret` assertion in Task 2 proves the second and later reads never reach the Keychain, which is everything except the dialog itself.
- [ ] 👤 Human: in Settings, paste a new z.ai key over the existing one and press Save - Expected: the row shows no error message and the green "Set" badge stays. Proxy: the `SAVE=ok` assertion in Task 3 proves the same write path succeeds from a signature the item does not know, which is the case that used to throw `errSecDuplicateItem`.
