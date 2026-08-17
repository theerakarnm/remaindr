# Keychain Prompt Storm Fix Implementation Plan

> **Run with:** `/execute-plan docs/plans/2026-08-17-keychain-prompt-storm.md` - the runner that ticks these
> checkboxes and honours the track/merge layout below.
>
> **For the executing agent:** Implement this plan in order, in a single worktree, from the repo root.
> Steps use checkbox (`- [ ]`) syntax for tracking; tick them as you go.
> Run the `## Preflight` checks BEFORE task 1 and report anything down.
>
> **Read this first.** While this plan was being written, a second agent was executing
> `docs/plans/2026-08-17-security-audit-fixes.md` against the same file this plan edits.
> It rewrote `Remaindr/Remaindr/Keychain/KeychainStore.swift` three times, and twice deleted
> this plan file outright as a "stray plan file" (commits `a505d84` and `a38c628`); the copy
> you are reading was restored by hand. That run reported itself finished at `a38c628`.
> Before starting, confirm it is no longer running, confirm the Preflight md5 still matches,
> and work from the anchors rather than the line numbers.

**Goal:** Stop Remaindr asking for the login keychain password five or six times per run, by never reading secret data when a presence check will do, reading each secret at most once per launch, and saving a key in place instead of destroying and recreating its keychain item.

**Architecture:** Three of the four changes live inside `KeychainStore`, the single chokepoint every provider and every view already goes through, so no call site changes and the `UsageProvider` boundary is untouched.
A `SecItemCopyMatching` that asks for `kSecValueData` is the operation macOS gates behind the item's ACL and partition list; an attributes-only match is answered from plaintext metadata columns and never prompts.
A process-wide `SecretCache` collapses the repeated data reads the refresh timer used to make and caches denials, so a refused prompt is not re-asked on the next tick; one escape hatch on the Claude path drops the cached credential when the server rejects it, so a rotated token still recovers without a restart.
`SecItemUpdate` replaces the `SecItemDelete` + `SecItemAdd` pair so a save keeps the item's existing ACL and partition list instead of throwing them away.

**Tech Stack:** Swift 6, Security.framework (`SecItem*` against the legacy file-based login keychain), `swiftc -swift-version 6` harnesses for verification, `xcodebuild` for the build gate.

**Spec:** none - planned from conversation. The report is a screenshot of the macOS dialog "security wants to use your confidential information stored in "com.theerakarn.Remaindr.pdmn" in your keychain. To allow this, enter the "login" keychain password." plus the user's statement: "there is many of password prompt that make me annoying. I add password like 5-6 times after I have running this app."

**Base commit:** `a38c628`, with `Remaindr/Remaindr/Keychain/KeychainStore.swift` at md5 `1b663660a4588856f8ca3959714d40b4`. Every line reference, anchor, and "already exists" claim below describes THIS tree. When an anchor does not match, run `git log --oneline a38c628..HEAD` to tell "the plan was wrong" apart from "the file moved on".

**Confidence:** 9/10. Rubric arithmetic: start at 10; no `Consumes:` entry lacks a full signature (0); every Patterns-to-Mirror SOURCE was read at its exact lines and copied, and an independent reviewer re-verified all five (0); no `Verify - Human:` lacks a paired proxy (0); no NOT-building entry cuts a requirement on an unproven claim - each carries a measured status code or a `file:line` (0); no task touches a schema or an inferred type (0); every Preflight command was actually executed while planning (0); there are no parallel tracks (0). One judgement deduction of 1: `Remaindr/Remaindr/Keychain/KeychainStore.swift` was rewritten three times by a concurrent plan execution while this plan was being written, and three of the four tasks edit that one file, so the anchors are more trustworthy than the line numbers.

**NOT building:**
- Developer ID signing or notarization. It is the thing that makes "Always Allow" survive an app update (measured: a signed app's partition entry is `teamid:XXXXXXXXXX` while this app's is `cdhash:<one build>`, and `securityd/src/clientid.cpp:259-287` shows only Apple, Mac App Store, Development and Developer ID signatures earn a `teamid:` partition), but it needs a paid Apple Developer account this machine does not have (`security find-identity -v -p codesigning` prints `0 valid identities found`), and `make-dmg.sh` already carries the signing hook from the in-flight security plan.
- Signing local builds with a self-signed code signing certificate. It would give a stable designated requirement (`identifier "com.theerakarn.Remaindr" and certificate leaf H"..."`) so the trusted-application half of the grant survives a rebuild, but per `securityd/src/clientid.cpp:259-287` a self-signed identity still lands in the `cdhash:` partition branch, so the partition half can still mismatch; it also has to be re-applied on every build and buys nothing for distribution. It is a developer-workflow change, not the app fix the user asked for.
- Moving items to the data protection keychain (`kSecUseDataProtectionKeychain: true`), which has no ACL prompts at all. Measured on this machine: an entitlement-free binary gets `SecItemAdd` and `SecItemDelete` status `-34018` (`errSecMissingEntitlement`) and `SecItemCopyMatching` `-25300`, and adding a `keychain-access-groups` entitlement to an ad-hoc signature gets the process SIGKILLed by AMFI. It needs a real Team ID plus a provisioning profile (Apple TN3137). The Claude fallback also has to keep reading the file-based keychain regardless, because that is where Claude Code writes its credential.
- Loosening the items' ACL to "allow all applications" (`SecAccessCreate` with a nil trusted-application list). It would silence the prompts by letting any process on the machine read the API keys, which contradicts `Remaindr/Remaindr/Keychain/KeychainStore.swift:8-9` and `SECURITY_AUDIT.md`.
- Making Settings' **Clear** button prompt-free. `remove(_:)` has to call `SecItemDelete`, and a delete is ACL-gated exactly like a read (measured: `-25244` from a signature the item does not know, with prompts suppressed). With prompts enabled the user answers one dialog and the delete succeeds, so Clear costs at most one prompt and is not broken; there is no update-in-place equivalent for a delete, so this one is accepted rather than fixed.
- Touching `upgradeAccessibility()` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:67-78`). At the base commit it already updates the accessibility attribute in place with `SecItemUpdate`, never reads the secret, and is gated to run once by `preferences.keychainAccessibilityUpgraded` (`Remaindr/Remaindr/App/RemaindrApp.swift:11-14`), so it costs no prompt. See Diagnosis point 7 for the measured fact that makes it a no-op on this keychain; acting on that is the in-flight security plan's call, not this one's.
- Consolidating the z.ai and DeepSeek keys into one keychain item. It would cut the worst-case per-build prompt count from three to two, at the cost of a storage-format migration; not worth it once each item costs at most one prompt per launch.
- Any new UI, setting, toggle, or onboarding screen.

## Diagnosis - measured, not assumed

Every claim here was produced by running code against this machine's login keychain on macOS 26.2 (`sw_vers`), or read out of Apple's published `Security` sources, not inferred.

**1. Reading `kSecValueData` is gated; reading attributes is not.**
A binary whose code signature is not in an item's partition list, run with `SecKeychainSetUserInteractionAllowed(false)` so a gated call fails instead of showing a modal:

```
zai: kSecReturnData=true                             status -25293 (errSecAuthFailed - would prompt)
zai: kSecReturnAttributes=true (presence only)       OK (no prompt)
deepseek: kSecReturnData=true                        status -25293
deepseek: kSecReturnAttributes=true (presence only)  OK (no prompt)
foreign Claude Code-credentials: data                status -25293
foreign Claude Code-credentials: attrs only          OK (no prompt)
```

The reason is in the default ACL: `Access::makeStandard()` grants `ENCRYPT` to any application and `DECRYPT` only to the trusted list (`OSX/libsecurity_keychain/lib/Access.cpp:83-110`), and attributes are plaintext columns.
Every prompt in the unified log is `AclValidationContext(action:24)`, and `CSSM_WORDID_DECRYPT` is 24; the extra password field belongs to action `65538`, `CSSM_ACL_AUTHORIZATION_PARTITION_ID`, which is the "Always Allow" write.

**2. The app asks for secret data five times per refresh cycle, and `hasKey` is two of them.**
`hasKey(for:)` is implemented as `((try? value(for: kind)) ?? nil) != nil` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:81-83`), so every presence check is a full secret read.
Per cycle: `ProviderStore.anyConfigured` calls it for z.ai and DeepSeek (`Remaindr/Remaindr/UI/ProviderStore.swift:28`) on `RefreshScheduler.start()` and again on every tick (`Remaindr/Remaindr/Refresh/RefreshScheduler.swift:17,24`), then `refreshAll` reads the z.ai key (`Remaindr/Remaindr/Providers/ZAIProvider.swift:30`), the DeepSeek key (`Remaindr/Remaindr/Providers/DeepSeekProvider.swift:32`), and Claude Code's credential blob (`Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift:30`).
Opening Settings adds three more (`Remaindr/Remaindr/UI/SettingsView.swift:87`).
Nothing caches, so answering "Allow" rather than "Always Allow" means being asked again on the next tick, forever.

**3. The grant is pinned to one exact build.**
Decoding the `Partitions` ACL entry of the live items with `SecKeychainItemCopyAccess` + `SecAccessCopyACLList`:

```
[a Developer ID signed browser]  partitions: teamid:<10-char team id>, teamid:<10-char team id>
[a second signed browser]        partitions: teamid:<10-char team id>
[Claude Code-credentials]        partitions: apple-tool:, cdhash:<Remaindr build hash>
[com.theerakarn.Remaindr]        partitions: cdhash:<same Remaindr build hash>
```

The same hash appears twice because it is Remaindr's own cdhash: it is in its own items' partition list because Remaindr created them, and in Claude Code's item because the user granted Remaindr access to that item once.
The three third-party team identifiers are redacted because this file is committed.
Properly signed apps get a `teamid:` partition that survives every update; an ad-hoc signature gets a `cdhash:` partition that dies with the next build, and the log shows the failure directly: `ACL partition mismatch: client cdhash:<new> ACL ("cdhash:<old>", "cdhash:<older>")`.
This is why "Always Allow" appears not to stick, and it is not fixable in code - see NOT building.

**4. After a rebuild, saving a key costs an extra prompt and then discards every grant on the item.**
`set(_:for:)` deletes then adds (`Remaindr/Remaindr/Keychain/KeychainStore.swift:36-42`).
`SecItemDelete` is ACL-gated, so with prompts enabled the user answers one more dialog before the save proceeds; run with prompts suppressed, the same call fails outright and the harness prints `SAVE=threw unexpectedStatus(-25299)` - the delete is refused and `SecItemAdd` then hits `errSecDuplicateItem`, which `SettingsView` reports as "Could not save the key to the Keychain." (`Remaindr/Remaindr/UI/SettingsView.swift:136`).
Worse, the add rebuilds the item's ACL from scratch: `ItemImpl::updateSSGroup` copies the existing ACL on the update path but constructs a new one trusting only the adding process on the add path (`OSX/libsecurity_keychain/lib/Item.cpp:924-941`, `Access.cpp:70-75`), so every previously granted "Always Allow" on that item is thrown away.
`SecItemUpdate` from the same foreign signature returns `errSecSuccess` with no prompt and keeps the ACL.

**5. The `.pdmn` in the screenshot is a red herring, and it is worth knowing why.**
`pdmn` really is the data protection keychain's internal key for `kSecAttrAccessible` (`SEC_CONST_DECL (kSecAttrAccessible, "pdmn")`, `OSX/sec/Security/SecItemConstants.c`), but macOS never renders an item name that way.
The ACL dialog shows the item's PrintName, which for a generic password defaults to its service (`OSX/libsecurity_keychain/lib/Item.cpp:680-707,936-939`).
The unified log holds exactly one such prompt on this machine - `securityd ... displaying keychain prompt for /usr/bin/security(21784) ... KeychainPromptAclSubject(desc:com.theerakarn.Remaindr.pdmn)` at 09:11:52 - and the scratch script that created that item, `/private/tmp/fix-kc/dbg3.swift` from an earlier debugging session, literally sets `let svc = "com.theerakarn.Remaindr.pdmn"`.
The dialog in the screenshot was therefore raised by `/usr/bin/security` against a leftover debug item, not by the app.
Reproduce with `log show --last 12h --predicate 'subsystem == "com.apple.securityd"' --style ndjson | grep kcacl`.
The user's underlying complaint is still real and is what points 1 through 4 explain; do not design anything around the `.pdmn` string.

**6. Caching Claude Code's credential has one failure mode that has to be closed at the same time.**
The credential blob holds an OAuth access token that Claude Code rotates.
`ClaudeProvider` is written on the assumption that an expired token simply means "fall through to the next source" and that the next cycle re-reads it (`Remaindr/Remaindr/Providers/ClaudeProvider.swift:42-45`, `ClaudeAccountUsage.swift:30`).
A process-lifetime cache breaks that assumption in an app that is `LSUIElement` and runs for days, so Task 2 adds `invalidateForeign(service:)` and calls it from the 401/403 branch of `ClaudeAccountUsage.fetch`. Caching and its escape hatch are one change, not two commits.

**7. One thing this plan deliberately records without acting on.**
This keychain drops `kSecAttrAccessible` entirely - `SecItemCopyTranslatedAttributes` does `CFDictionaryRemoveValue(result, kSecAttrAccessible)` (`OSX/libsecurity_keychain/lib/SecItem.cpp:4821`), and a freshly written item reports attribute keys `acct, cdat, class, labl, mdat, svce` with `kSecAttrAccessible` reading back `<ABSENT>` - so `upgradeAccessibility()` can never observe its own effect here.
At the base commit it is already harmless: it uses `SecItemUpdate`, never reads the secret, and runs once.
This plan therefore leaves it and the `kSecAttrAccessible` argument alone rather than reopening the in-flight security plan's F-03 decision.

## Global Constraints

- API keys live in the macOS Keychain only. Never `UserDefaults`, never plaintext, never logged, never committed. (`AGENTS.md`, Hard rules)
- No third-party Swift packages. (`AGENTS.md`, Hard rules)
- The UI layer never talks to a provider directly, only through `UsageProvider`; do not weaken that boundary. (`AGENTS.md`, Architecture)
- Do not change the `UsageProvider` protocol shape. (`AGENTS.md`, Stop and ask before)
- One provider failing must never blank or zero out the others. (`AGENTS.md`, Hard rules)
- Claude's primary source is the account usage endpoint, and its numbers must match what Claude Code shows; a local approximation is the fallback, never the default. (`AGENTS.md`, Provider data)
- Only make the change directly requested. No features, abstractions, onboarding flows, or files beyond what was asked. (`AGENTS.md`, Hard rules)
- Build must succeed with zero warnings before a task is considered done. (`AGENTS.md`, Commands)
- Never use the em dash character. Use a plain dash instead. (user instructions)
- Swift 6 language mode, macOS 14 deployment target: `SWIFT_VERSION = 6.0`, `MACOSX_DEPLOYMENT_TARGET = 14.0` (`Remaindr/Remaindr.xcodeproj/project.pbxproj:136,141,154,157`). Every new type must satisfy strict concurrency checking.
- No live provider API call is made by anything in this plan. Every verification is local Keychain work against a throwaway `com.theerakarn.Remaindr.verify` service, which each harness cleans up after itself.

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
<!-- SOURCE: Remaindr/Remaindr/Keychain/KeychainStore.swift:85-87 -->
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

`KeychainStore` is a `Sendable` value type reached from a `withTaskGroup` off the main actor (`Remaindr/Remaindr/UI/ProviderStore.swift:54-64`), so anything it touches must be safe from several threads without an actor hop.

### Verification harness
<!-- SOURCE: docs/plans/2026-08-16-aiusagebar-menu-bar-app.md:758-762,769-770 -->
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
Four details this plan depends on: the harness file must be named `main.swift` (Swift only allows top-level statements in that filename), each harness needs its own directory so several can coexist, the `-o` output must NOT be one of those directory paths or the linker fails with `errno=21 (Is a directory)`, and every `<<'EOF'` block must be **dedented to column 0 before it is run** - the six-space indentation below is markdown formatting, and a `bash` heredoc terminator that is not at the start of its line never terminates.

### Tests

No test target exists: `xcodebuild -project Remaindr/Remaindr.xcodeproj -list` reports exactly one target, `Remaindr`, and `git ls-files | grep -ci test` is 0.
Establishing new convention: none. This plan reuses the `swiftc` harness precedent above rather than introducing XCTest.

## Preflight

### DURABLE - true until the repo itself changes

- **No test target; verification is `swiftc` harnesses.** Evidence: `xcodebuild -project Remaindr/Remaindr.xcodeproj -list` printed `Targets:` then only `Remaindr`, and `git ls-files | grep -ci test` printed `0`. Consequence: every Verify below is a `swiftc` harness plus `xcodebuild build`, never `xcodebuild test`.
- **A `swiftc` harness can round-trip the Keychain with no GUI prompt for items it creates itself.** Evidence: `SEED=wrote` from a freshly compiled harness. Consequence: Tasks 1-3 are real `Verify - Run` steps, not Human checks.
- **The app is ad-hoc signed, so its keychain grants can only ever be pinned to one build.** Evidence: `codesign -dvvv build/dmg-staging/Remaindr.app` prints `Signature=adhoc` and `TeamIdentifier=not set`; `security find-identity -v -p codesigning` prints `0 valid identities found`. Consequence: after this plan lands, a fresh build still asks once per item on first launch. That is expected, is called out in Task 4's README text, and is NOT a failure of the End-to-end verification.
- **The data protection keychain is unavailable to this app.** Evidence: `SecItemAdd` with `kSecUseDataProtectionKeychain: true` from an entitlement-free binary returned `-34018`. Consequence: the NOT-building entry stands; do not "fix" the prompts that way mid-run.
- **This keychain silently drops `kSecAttrAccessible`.** Evidence: an item added with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` reads back attribute keys `acct, cdat, class, labl, mdat, svce` and `kSecAttrAccessible` as `<ABSENT>`. Consequence: Task 3 keeps passing the attribute (harmless, and correct if the app ever moves keychains) and builds no logic on reading it back.
- **`SecItemUpdate` is not ACL-gated where `SecItemDelete` is.** Evidence: from a binary outside the item's partition list, `SecItemUpdate` returned `OK (no prompt)` while `SecItemDelete` returned `-25244`. Consequence: Task 3's approach is sound, and Settings' Clear button is knowingly left costing one prompt.
- **Every command in this plan assumes the repo root as the working directory.** Evidence: each harness passes relative source paths (`Remaindr/Remaindr/Models/ProviderStatus.swift`) and `-project Remaindr/Remaindr.xcodeproj`. Consequence: `cd` to the repo root before task 1 and stay there.

### PERISHABLE - recapture before task 1

- **A concurrent agent was executing `docs/plans/2026-08-17-security-audit-fixes.md` against this same file, and deleted this plan file twice (commits `a505d84`, `a38c628`).** Check: `git log --format='%h %ad %s' --date=format:'%H:%M:%S' -5 && git status --porcelain && md5 -q Remaindr/Remaindr/Keychain/KeychainStore.swift` - the file was `1b663660a4588856f8ca3959714d40b4` at `a38c628`, that plan stood at 37 of 38 steps ticked, and its last commit was labelled "final". Needed by: Tasks 1, 2, 3, which all edit that file. If the hash differs, re-read the file and re-anchor before editing; if the working tree is dirty or that plan still has unticked steps touching `KeychainStore.swift`, STOP and ask rather than racing it.
- **Baseline build is green with zero warnings.** Check: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Debug -derivedDataPath /tmp/kc-dd build 2>&1 | tee /tmp/kc-build.log | tail -1; echo "warnings=$(grep -c ': warning: ' /tmp/kc-build.log || true)"` - recorded: `** BUILD SUCCEEDED **` and `warnings=0`, in about 13 seconds. Needed by: every task's Verify, which asserts the same two lines.
- **The Swift toolchain is present.** Check: `xcrun -f swiftc && swiftc --version | head -1` - recorded: a path under `/Applications/Xcode.app` and a Swift 6 banner. Needed by: every task's Verify.
- **The login keychain is unlocked.** Check: `security show-keychain-info ~/Library/Keychains/login.keychain-db 2>&1` - recorded: no `The specified keychain is not... locked` error. Needed by: every harness. A locked keychain raises an unlock dialog instead of the statuses the Expected blocks predict, which looks like a hang.
- **No leftover verify items in the login keychain.** Check: `security find-generic-password -s com.theerakarn.Remaindr.verify >/dev/null 2>&1 && echo LEFTOVER || echo clean` - recorded: `clean`. Needed by: Tasks 1-3, whose harnesses seed and delete under that service. If it prints `LEFTOVER`, clear it with the Rollback command on Task 1 before starting.
- **The staged app's cdhash, if the Diagnosis evidence is being re-checked.** Check: `codesign -dvvv build/dmg-staging/Remaindr.app 2>&1 | grep '^CDHash'` - it changes on every `make-dmg.sh` run, so the specific hash quoted in Diagnosis point 3 is illustrative only. Needed by: nothing in the tasks; recorded so the evidence is reproducible rather than mysterious.
- **`log show` returns keychain-prompt records.** Check: `log show --last 12h --predicate 'subsystem == "com.apple.securityd"' --style ndjson | grep -c kcacl` - recorded: `97`. Needed by: the End-to-end prompt count. If it returns `0` on a machine that has definitely shown keychain dialogs, the log is redacted or rolled over and that verify passes vacuously; say so rather than ticking it.
- **The user's refresh interval.** Check: `python3 -c "import json;print(json.load(open('$HOME/.remaindr'))['refreshIntervalMinutes'])" 2>/dev/null || echo 5` - recorded: `5` minutes (`Remaindr/Remaindr/Models/Preferences.swift:28-29` clamps it to 1...60 and defaults to 5). Needed by: the End-to-end prompt count and the first Human item, both of which say "two refresh intervals" and "three refresh intervals". At 30 minutes a 12-minute observation window proves nothing, so scale the sleep and the `log show --start` window to this value.
- **README's existing em dash count.** Check: `LC_ALL=C grep -c $'\xe2\x80\x94' README.md` - recorded: `20`, all in prose this plan does not touch. Needed by: Task 4's Verify, which is why that check counts added lines rather than the file.
- **The user's real keys may or may not be stored.** Check: `for a in zai deepseek anthropic; do security find-generic-password -s com.theerakarn.Remaindr -a $a >/dev/null 2>&1 && echo "$a present" || echo "$a absent"; done` - recorded: `zai present`, `deepseek present`, `anthropic absent`. Needed by: the End-to-end verification only. No task Expected depends on it; the task harnesses use the throwaway `.verify` service precisely so they do not.

## Execution

**Tracks:**
- Single sequential track. Tasks 1, 2 and 3 all edit `Remaindr/Remaindr/Keychain/KeychainStore.swift`, so they cannot run concurrently, and Task 4 documents the behaviour the first three produce.

**Merge order:** not applicable - one branch, tasks in order 1, 2, 3, 4.
**Shared files:** `Remaindr/Remaindr/Keychain/KeychainStore.swift` is touched by Tasks 1, 2 and 3, which is why the plan is sequential. No barrel file, no schema, no dependency manifest, no migration directory, and no route registration exists in this project to contend over.
**Worktree setup:** none, and therefore no `--lease-holder` label. A single-track plan does not earn a `treehouse` worktree (the cost floor is 3 tasks or 5 files per track); work in the repo directory on the current branch. If `treehouse` is not installed that blocks nothing here.
**Teardown:** no worktree to return. The only state to clean up is the harness tree and the throwaway keychain service, and the last item in `## End-to-end verification` does both.

---

### Task 1: Presence check stops reading the secret

**Files:**
- Modify: `Remaindr/Remaindr/Keychain/KeychainStore.swift` (anchor: `/// Cheap presence check for the Settings UI`, ~L80-83)
- Harness (throwaway, written by Step 2, never committed): `/tmp/kc-verify/seed/main.swift`, `/tmp/kc-verify/check/main.swift`

**Interfaces:**
- Consumes: `ProviderKind.keychainAccount` (`Remaindr/Remaindr/Models/ProviderStatus.swift:33-39`) and the existing `private func query(_ account: String) -> [String: Any]`.
- Produces: `func hasKey(for kind: ProviderKind) -> Bool` - signature unchanged, so the four call sites (`Remaindr/Remaindr/UI/ProviderStore.swift:28`, `Remaindr/Remaindr/UI/SettingsView.swift:87,132,144`) need no edit.

**Gotcha:** the answer changes meaning in one edge case, and that is the point.
Today `hasKey` returns `false` for an item that exists but whose read was denied, so a configured provider silently reports "Not configured" and Settings shows "Not set" over a saved key.
After this change it returns `true` for any item that exists, whether or not this build may read it.
That has a knock-on effect this task does NOT fix: `ProviderStore.anyConfigured` (`Remaindr/Remaindr/UI/ProviderStore.swift:28`) now returns true for a user who has been denying the prompts, so `RefreshScheduler` (`Remaindr/Remaindr/Refresh/RefreshScheduler.swift:17,24`) keeps ticking and re-reading instead of bailing out, which for that user widens the prompt window rather than narrowing it.
Task 2 is the task that closes it, by making the repeat reads stop entirely. Land both before shipping a build.

**Rollback:** ordinary code change - `git revert` is the answer. If Preflight found a leftover verify item, clear it with `security delete-generic-password -s com.theerakarn.Remaindr.verify -a deepseek 2>/dev/null; security delete-generic-password -s com.theerakarn.Remaindr.verify -a zai 2>/dev/null; true`.

**Steps:**
- [x] Step 1: In `Remaindr/Remaindr/Keychain/KeychainStore.swift`, replace the whole `hasKey(for:)` member (anchor: `/// Cheap presence check for the Settings UI and for pausing the refresh timer.`, that doc comment through the closing brace of the function, ~L80-83) with:

      ```swift
      /// Cheap presence check for the Settings UI and for pausing the refresh timer.
      /// It must never ask for `kSecValueData`: the data read is the operation macOS gates
      /// behind the item's ACL and partition list, and answering it costs the user a login
      /// keychain password prompt. An attributes-only match is served from the item's
      /// plaintext metadata columns and never prompts. Measured on macOS 26.2 with prompts
      /// disabled: the data query returns errSecAuthFailed (-25293), the attributes query
      /// returns errSecSuccess.
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

- [x] Step 2: Verify - Run (dedent the block to column 0 first; the `EOF` terminators must start at the beginning of their lines):

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
      swiftc -swift-version 6 $SRC /tmp/kc-verify/seed/main.swift  -o /tmp/kc-verify/seed-run  2>/dev/null || { echo COMPILE_FAILED_seed; exit 1; }
      swiftc -swift-version 6 $SRC /tmp/kc-verify/check/main.swift -o /tmp/kc-verify/check-run 2>/dev/null || { echo COMPILE_FAILED_check; exit 1; }
      /tmp/kc-verify/seed-run && /tmp/kc-verify/check-run && /tmp/kc-verify/seed-run clean
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

      `PRESENCE=false` is the pre-change behaviour and means the edit did not take. A `COMPILE_FAILED_*` line means the harness never ran; fix the compile rather than reading the build result below it.

      > Deviation (executed): `xcodebuild ... | tail -1` on this machine emits the trailing blank line of xcodebuild's output, not the `** BUILD SUCCEEDED **` line, so the fifth line of stdout is empty. The substantive condition was confirmed from the log: `grep -c 'BUILD SUCCEEDED' /tmp/kc-build.log` = `1`, `grep -c 'BUILD FAILED'` = `0`, `warnings=0`. Same note applies to every later Verify's build line.
      The `-o` names deliberately differ from the harness directory names: `-o /tmp/kc-verify/seed` would make the linker fail with `errno=21 (Is a directory)`.

- [x] Step 3: Commit - `git add Remaindr/Remaindr/Keychain/KeychainStore.swift && git commit -m "fix(keychain): answer presence checks from item metadata, not the secret"`

---

### Task 2: Read each secret at most once per launch, and let a rejected Claude token drop its cache

**Files:**
- Modify: `Remaindr/Remaindr/Keychain/KeychainStore.swift` (anchors: `/// The only place an API key is ever read or written.` ~L8, `private func query(_ account: String)` ~L21, `func value(for kind: ProviderKind)` ~L45, `func remove(_ kind: ProviderKind)` ~L59, `func foreignValue(service: String)` ~L88)
- Modify: `Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift` (anchor: `case 401, 403: throw ProviderError.unauthorized`, ~L63)
- Harness (throwaway, written by Step 5, never committed): `/tmp/kc-verify/cache/main.swift`, `/tmp/kc-verify/foreign/main.swift`

**Interfaces:**
- Consumes: `KeychainError.unexpectedStatus(OSStatus)` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:4-6`), `private func query(_ account: String) -> [String: Any]`, and `ClaudeAccountUsage.credentialService` (`Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift:20`).
- Produces: `func value(for kind: ProviderKind) throws -> String?` and `func foreignValue(service: String) throws -> String?` - both signatures unchanged, so `ZAIProvider.fetch`, `DeepSeekProvider.fetch`, `ClaudeProvider.fetch` and `ClaudeAccountUsage.accessToken` need no edit. New `func invalidateForeign(service: String) -> Void` on `KeychainStore`, and a new private `final class SecretCache` that is not visible outside the file.

**Gotcha:** four things that are easy to get wrong here.
`entries[key]` on a `[String: Result<String?, KeychainError>]` yields `Optional<Result<String?, KeychainError>>`, so `if let cached = entries[key] { return try cached.get() }` is the correct shape and does exactly one dictionary lookup.
The lock is held across the `read` closure on purpose: `ProviderStore.refreshAll` fetches all three providers inside one `withTaskGroup` (`Remaindr/Remaindr/UI/ProviderStore.swift:54-64`), and without that the same item could raise two dialogs at once.
`SecretCache` cannot be an `actor`, because `value(for:)` is a synchronous throwing function called from non-async code; `@unchecked Sendable` with an `NSLock` is the shape that satisfies Swift 6 strict concurrency here.
`hasKey(for:)` deliberately does NOT go through the cache: after Task 1 it never touches `kSecValueData`, so it costs nothing and staying live keeps Settings honest right after a Save or Clear.

**Rollback:** ordinary code change - `git revert` is the answer.

**Steps:**
- [x] Step 1: In `Remaindr/Remaindr/Keychain/KeychainStore.swift`, insert the cache immediately above the `/// The only place an API key is ever read or written.` doc comment (~L8), so it sits between `KeychainError` and `KeychainStore`:

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

- [x] Step 2: In the same file, add the cache key helper and the single gated read directly after the closing brace of `query(_:)` (anchor: `private func query(_ account: String) -> [String: Any]`, ~L21-27 at base, shifted down by Step 1):

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

- [x] Step 3: In the same file, route both readers (`value(for:)`, `foreignValue(service:)`) and both writers (`set(_:for:)`, `remove(_:)`) through the cache.
      Steps 1 and 2 pushed everything below them down by roughly fifty lines, so work from the anchors, not from the base line numbers.

      Replace the whole `value(for:)` member (anchor: `func value(for kind: ProviderKind) throws -> String?`, its `guard let account` through its closing brace, ~L45 at base) with:

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

      Replace the whole `foreignValue(service:)` member (anchor: `/// Reads a generic-password item another app stored`, doc comment through the member's closing brace, ~L85-102 at base) with:

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

          /// Drops the cached copy of a foreign item so the next read goes back to the
          /// Keychain. Claude Code rotates the OAuth token inside its credential blob, and a
          /// process-lifetime cache would otherwise keep replaying a token the server has
          /// already rejected - in an `LSUIElement` app that runs for days, that would mean
          /// losing Claude's primary source until the user quits and relaunches.
          func invalidateForeign(service: String) {
              SecretCache.shared.invalidate("foreign/\(service)")
          }
      ```

      In `set(_:for:)`, insert `SecretCache.shared.invalidate(cacheKey(account))` as the line directly above the `// SecItemAdd returns errSecDuplicateItem for an existing account, so replace.` comment (~L36 at base).
      In `remove(_:)`, insert the same call directly above `let status = SecItemDelete(query(account) as CFDictionary)` (~L61 at base).
      Both anchors are unique in the file; grep for them rather than counting lines.

- [x] Step 4: In `Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift`, replace the line `        case 401, 403: throw ProviderError.unauthorized` (~L63) with:

      ```swift
              case 401, 403:
                  // Claude Code rotates this token, and `foreignValue` caches for the lifetime
                  // of the process so it costs at most one Keychain prompt. Dropping the cached
                  // copy here is what keeps that cache from replaying a token the server has
                  // already rejected: the next refresh re-reads the blob instead.
                  keychain.invalidateForeign(service: credentialService)
                  throw ProviderError.unauthorized
      ```

      `keychain` is already the first parameter of `fetch(keychain:session:)` and `credentialService` is the static on this type, so nothing else changes.

- [x] Step 5: Verify - Run (dedent the block to column 0 first; the `EOF` terminators must start at the beginning of their lines):

      ```bash
      mkdir -p /tmp/kc-verify/cache /tmp/kc-verify/foreign
      # Clear any item an older harness build left behind BEFORE compiling. The security
      # CLI can delete it without a dialog; a recompiled harness could not, because its
      # signature would no longer be the one that created it.
      security delete-generic-password -s com.theerakarn.Remaindr.verify -a zai >/dev/null 2>&1; true
      security delete-generic-password -s com.theerakarn.Remaindr.verify -a deepseek >/dev/null 2>&1; true
      cat > /tmp/kc-verify/cache/main.swift <<'EOF'
      import Foundation
      import Security
      // One binary, so it owns the item it creates and its own reads succeed. Prompts are
      // disabled all the same: nothing here may block on a modal dialog.
      SecKeychainSetUserInteractionAllowed(false)
      let store = KeychainStore(service: "com.theerakarn.Remaindr.verify")
      try store.set("probe-secret", for: .zai)
      let first = try store.value(for: .zai) ?? "nil"
      let raw: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.theerakarn.Remaindr.verify",
          kSecAttrAccount as String: "zai",
      ]
      let deleted = SecItemDelete(raw as CFDictionary)
      let second = ((try? store.value(for: .zai)) ?? nil) ?? "nil"
      print("CACHE first=\(first) deleted=\(deleted) second=\(second)")
      EOF
      cat > /tmp/kc-verify/foreign/main.swift <<'EOF'
      import Foundation
      import Security
      // The foreign path caches the same way, so it needs an escape hatch: this is the
      // plumbing ClaudeAccountUsage uses when the server rejects the cached token.
      SecKeychainSetUserInteractionAllowed(false)
      let svc = "com.theerakarn.Remaindr.verify"
      let store = KeychainStore(service: svc)
      try store.set("probe-secret", for: .deepseek)
      let first = ((try? store.foreignValue(service: svc)) ?? nil) ?? "nil"
      let raw: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: svc,
          kSecAttrAccount as String: "deepseek",
      ]
      let deleted = SecItemDelete(raw as CFDictionary)
      let cached = ((try? store.foreignValue(service: svc)) ?? nil) ?? "nil"
      store.invalidateForeign(service: svc)
      let fresh = ((try? store.foreignValue(service: svc)) ?? nil) ?? "nil"
      print("FOREIGN first=\(first) deleted=\(deleted) cached=\(cached) afterInvalidate=\(fresh)")
      EOF
      SRC="Remaindr/Remaindr/Models/ProviderStatus.swift Remaindr/Remaindr/Keychain/KeychainStore.swift"
      swiftc -swift-version 6 $SRC /tmp/kc-verify/cache/main.swift -o /tmp/kc-verify/cache-run 2>/dev/null || { echo COMPILE_FAILED_cache; exit 1; }
      swiftc -swift-version 6 $SRC Remaindr/Remaindr/Providers/ClaudeSessionBlocks.swift Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift /tmp/kc-verify/foreign/main.swift -o /tmp/kc-verify/foreign-run 2>/dev/null || { echo COMPILE_FAILED_foreign; exit 1; }
      /tmp/kc-verify/cache-run
      /tmp/kc-verify/foreign-run
      security delete-generic-password -s com.theerakarn.Remaindr.verify -a zai >/dev/null 2>&1; true
      security delete-generic-password -s com.theerakarn.Remaindr.verify -a deepseek >/dev/null 2>&1; true
      echo "wired=$(grep -c 'keychain.invalidateForeign(service: credentialService)' Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift)"
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Debug -derivedDataPath /tmp/kc-dd build 2>&1 | tee /tmp/kc-build.log | tail -1
      echo "warnings=$(grep -c ': warning: ' /tmp/kc-build.log || true)"
      ```

      Expected, exactly these five lines:

      ```
      CACHE first=probe-secret deleted=0 second=probe-secret
      FOREIGN first=probe-secret deleted=0 cached=probe-secret afterInvalidate=nil
      wired=1
      ** BUILD SUCCEEDED **
      warnings=0
      ```

      `second=nil` is the pre-change behaviour and means the read still goes to the Keychain every time.
      `afterInvalidate=probe-secret` would mean the escape hatch is not wired to the same cache key, which is the regression that would cost Claude its primary source after a token rotation.
      The second `swiftc` line compiles `ClaudeAccountUsage.swift` too, so a mistake in Step 4 shows up as `COMPILE_FAILED_foreign` rather than silently at the end.

- [x] Step 6: Commit - `git add Remaindr/Remaindr/Keychain/KeychainStore.swift Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift && git commit -m "fix(keychain): read each secret at most once per launch"`

---

### Task 3: Save a key in place instead of destroying the item

**Files:**
- Modify: `Remaindr/Remaindr/Keychain/KeychainStore.swift` (anchor: `// SecItemAdd returns errSecDuplicateItem for an existing account, so replace.`, ~L36-42 at base, shifted down by Task 2)
- Harness (throwaway, written by Step 2, never committed): `/tmp/kc-verify/save/main.swift`, reusing `/tmp/kc-verify/seed/main.swift` from Task 1

**Interfaces:**
- Consumes: `KeychainStore.accessibility` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:19`), `private func query(_ account: String) -> [String: Any]`, and `SecretCache.invalidate(_:)` from Task 2.
- Produces: `func set(_ value: String, for kind: ProviderKind) throws` - signature unchanged, so `SettingsView.save` (`Remaindr/Remaindr/UI/SettingsView.swift:130`) needs no edit. `upgradeAccessibility` (`Remaindr/Remaindr/Keychain/KeychainStore.swift:67-78`) no longer calls `set(_:for:)` at the base commit, so this task cannot regress it.

**Gotcha:** `SecItemUpdate`'s second argument carries only the attributes to change, never `kSecClass`, `kSecAttrService` or `kSecAttrAccount` - those stay in the query.
Passing `kSecAttrAccessible` in the update dictionary is accepted by this keychain (measured: `errSecSuccess`) even though it stores nothing, so keep it for the day the app moves to the data protection keychain. If some macOS build ever rejects it, the Verify below discriminates that case as `SAVE=threw unexpectedStatus(-50)`.
`errSecItemNotFound` from the update is the ordinary first-save path, not a failure; every other non-success status is a real error and must throw.

**Rollback:** ordinary code change - `git revert` is the answer. The task writes only to `com.theerakarn.Remaindr.verify`, cleaned up by its own Verify.

**Steps:**
- [x] Step 1: In `Remaindr/Remaindr/Keychain/KeychainStore.swift`, replace the tail of `set(_:for:)` - from the `// SecItemAdd returns errSecDuplicateItem for an existing account, so replace.` comment through the `guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }` line, which is everything after the `SecretCache.shared.invalidate(cacheKey(account))` call Task 2 added - with:

      ```swift
              let data = Data(trimmed.utf8)
              // Update in place when the item already exists. The previous delete-then-add
              // cycle threw the item's ACL and partition list away along with the item, so
              // every save re-authorised the app from scratch - and once the running build's
              // signature no longer matched the item, SecItemDelete was itself gated and
              // SecItemAdd then failed with errSecDuplicateItem, surfacing as "Could not save
              // the key to the Keychain." SecItemUpdate needs no authorisation and copies the
              // existing ACL forward. Measured: update returns errSecSuccess where delete
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

- [x] Step 2: Verify - Run (dedent the block to column 0 first; the `EOF` terminators must start at the beginning of their lines):

      ```bash
      mkdir -p /tmp/kc-verify/seed /tmp/kc-verify/save
      security delete-generic-password -s com.theerakarn.Remaindr.verify -a deepseek >/dev/null 2>&1; true
      # Rewritten here rather than reused from Task 1: /tmp is swept between sessions, and a
      # missing seed harness would surface as COMPILE_FAILED_seed with no Step code to fix.
      cat > /tmp/kc-verify/seed/main.swift <<'EOF'
      import Foundation
      let store = KeychainStore(service: "com.theerakarn.Remaindr.verify")
      if CommandLine.arguments.contains("clean") {
          try? store.remove(.deepseek)
          print("SEED=cleaned")
      } else {
          try store.set("probe-secret", for: .deepseek)
          print("SEED=wrote")
      }
      EOF
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
      swiftc -swift-version 6 $SRC /tmp/kc-verify/seed/main.swift -o /tmp/kc-verify/seed-run 2>/dev/null || { echo COMPILE_FAILED_seed; exit 1; }
      swiftc -swift-version 6 $SRC /tmp/kc-verify/save/main.swift -o /tmp/kc-verify/save-run 2>/dev/null || { echo COMPILE_FAILED_save; exit 1; }
      /tmp/kc-verify/seed-run && /tmp/kc-verify/save-run && /tmp/kc-verify/seed-run clean
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

- [x] Step 3: Commit - `git add Remaindr/Remaindr/Keychain/KeychainStore.swift && git commit -m "fix(keychain): update items in place so a save keeps its access grant"`

---

### Task 4: Tell the user what the remaining prompt means

**Files:**
- Modify: `README.md` (anchor: `## Troubleshooting`, ~L138-146)

**Interfaces:**
- Consumes: the behaviour Tasks 1-3 produce. Nothing consumes this task.

**Gotcha:** the README is user-facing, so it must not promise the prompt is gone.
After this plan the app asks at most once per keychain item on the first launch of a given build, and asks again after an app update because the build is ad-hoc signed.
Do not soften that into "you will not be asked again".
Leave `README.md`'s Table of Contents (`README.md:9-25`) alone: it lists `##` headings only, and the new section is a `###` under Troubleshooting.

**Rollback:** ordinary docs change - `git revert` is the answer.

**Steps:**
- [x] Step 1: In `README.md`, add one row to the Troubleshooting table, directly after the `| Collapsed label missing | ... |` row:

      ```markdown
      | macOS asks for your login keychain password | Expected once per key after installing or updating the app - see below |
      ```

- [x] Step 2: In `README.md`, add this subsection immediately after the Troubleshooting table and before `## Roadmap`:

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

- [x] Step 3: Verify - Run:

      ```bash
      grep -c 'Why macOS asks for the keychain password' README.md
      grep -c 'macOS asks for your login keychain password' README.md
      git diff HEAD -- README.md | grep '^+' | LC_ALL=C grep -c $'\xe2\x80\x94'; true
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

      The third line counts the em dash character in the added README lines; the repo forbids it, so it must be `0`. `git diff HEAD` rather than `git diff`, so the check still fires after `git add`. README already contains 20 em dashes in pre-existing prose, which is why this counts added lines only and not the whole file.

- [x] Step 4: Commit - `git add README.md && git commit -m "docs: explain the keychain password prompt and when it recurs"`

## Failure handling summary

- **A Verify prints a keychain status other than the Expected one (`-25293`, `-25299`, `-25244`, `-34018`, `-50`).** Detect: the harness line differs from the Expected block. Respond: do NOT relax the Expected. Re-run the Preflight leftover check, clear `com.theerakarn.Remaindr.verify` with the Task 1 Rollback command, and re-run once. If it still differs, STOP and report the exact status - the mechanism this plan is built on has changed.
- **A harness hangs instead of printing.** Detect: no output, or a modal dialog on screen. Respond: three causes, in the order to check them. (1) A `com.theerakarn.Remaindr.verify` item is left over from an older harness build, so the recompiled binary's signature is no longer the one that created it and its first touch is ACL-gated - clear it with the Task 1 Rollback command and re-run; every Verify already does this before compiling. (2) The harness lost its `SecKeychainSetUserInteractionAllowed(false)` line. (3) The login keychain is locked and macOS is waiting behind an unlock dialog - see the Preflight unlock entry. Never answer a keychain dialog to make a Verify pass; granting the harness binary access destroys the test's meaning.
- **A heredoc block never returns and bash keeps reading input.** Detect: the shell sits at a continuation prompt after a `cat > ... <<'EOF'` line. Respond: the `EOF` terminator is still indented. Dedent the whole block to column 0 and re-run.
- **A `COMPILE_FAILED_*` line appears.** Detect: the literal string in the output. Respond: re-run that one `swiftc` command without `2>/dev/null` to see the diagnostic, fix the Step's code, and re-run the whole Verify. Do not read the `xcodebuild` result below it as a pass.
- **`Remaindr/Remaindr/Keychain/KeychainStore.swift` differs from md5 `1b663660a4588856f8ca3959714d40b4`.** Detect: the PERISHABLE Preflight check. Respond: re-read the file, confirm the concurrent security-audit plan is not mid-task in it, re-anchor the edits by symbol rather than line number, and note the drift on the task. If that plan still has unticked steps touching this file, STOP and ask.

## End-to-end verification

Run after all four tasks are committed, from the repo root.
`INTERVAL` below is the refresh interval Preflight recorded (5 minutes on this machine); scale every wait to it.

- [x] Run: `git log --format='%h' --grep='^fix(keychain)' --grep='^docs: explain the keychain' -4 | xargs -n1 git show --name-only --format='' | sort -u | grep -v '^$'` - Expected: exactly three paths, `README.md`, `Remaindr/Remaindr/Keychain/KeychainStore.swift`, and `Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift`. Matched on this plan's own commit subjects rather than on `HEAD~4`, because a concurrent agent may have interleaved commits.

      > Executed: the three expected paths are present and correct; a fourth path, `docs/plans/2026-08-17-keychain-prompt-storm.md`, also appears because the execute-plan skill mandates staging the plan file (checkbox ticks) into each task commit. Benign by design.
- [x] Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -derivedDataPath /tmp/kc-dd-release build 2>&1 | tee /tmp/kc-release.log | tail -1; echo "warnings=$(grep -c ': warning: ' /tmp/kc-release.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [x] Run: `grep -c 'kSecReturnData' Remaindr/Remaindr/Keychain/KeychainStore.swift` - Expected: `1`. The whole file must request secret data from exactly one place, `readData(_:)`, which is what makes the cache the only door.
- [x] Run: `grep -c 'SecItemDelete(' Remaindr/Remaindr/Keychain/KeychainStore.swift` - Expected: `1`, the single call inside `remove(_:)`. `set(_:for:)` must no longer delete. The trailing `(` keeps the prose in Task 3's comment from being counted.
- [x] Manual: count the keychain prompts macOS actually raised for this app on the FIRST launch of this build, from the system log rather than by eye:

      ```bash
      START=$(date '+%Y-%m-%d %H:%M:%S')
      open /tmp/kc-dd-release/Build/Products/Release/Remaindr.app
      sleep 660   # two 5-minute refresh intervals plus slack; scale to INTERVAL
      log show --start "$START" --predicate 'subsystem == "com.apple.securityd"' --style ndjson \
        | grep kcacl | grep 'action:24' | grep -c Remaindr
      ```

      Expected: at most `3` - the z.ai item, the DeepSeek item, and Claude Code's credential, once each. Before this plan the same window produced one prompt per item per refresh cycle, so five or more. The `action:24` filter is load-bearing: it selects `CSSM_ACL_AUTHORIZATION_DECRYPT` and excludes the `action:65538` partition writes that answering "Always Allow" generates, which would otherwise push the count past 3 precisely when the fix is working. If the user has not yet answered any prompt for this build with "Always Allow", 1 to 3 is the pass; the "no prompts at all" case belongs to the next item.

      > Executed 2026-08-18 05:26-05:38: the command's `action:24` count printed `0`, but the REAL prompts were two `action:65538` partition prompts (the "enter the login keychain password" dialog from the original screenshot) displayed at 05:26:23 and approved by the user at 05:36:37/05:36:41 with per-session "Allow". The plan's filter excludes 65538 as "Always Allow noise", but on this machine an app's first access to an item it does not own manifests as the partition prompt, so the command undercounts. Counted either way - 0 by the literal command, 2 by actual dialogs - "at most 3" holds. After the approvals, ZERO further prompts appeared (verified through 05:56): the cache holds the result and the ticks never re-ask.
      > Out-of-scope finding discovered during this check: the refresh scheduler is cancelled after its first cycle. `RefreshScheduler.start()` is launched from `.task { scheduler.start() }` attached to the `DropdownPanel` inside `MenuBarExtra` (`Remaindr/Remaindr/App/RemaindrApp.swift:23-26`), and SwiftUI cancels `.task` when that view disappears - so the app refreshes once per launch and then stops ticking (securityd shows no further "Keychain query" lines for the process). This predates this plan's base commit (`8cf98ba`) and touches no file this plan owns; left unfixed per the NOT-building rule. It means the "no prompts on later ticks" observation is over-determined: the cache would prevent them, and the dead timer also would. Fixing the scheduler is the user's call as a follow-up.
- [ ] Manual: NOT RUN - repeat the block above WITHOUT quitting the app in between - relaunch it a second time after every prompt has been answered "Always Allow", with a fresh `START` - Expected: `0`. A non-zero count on the second launch of the same build means a grant is not sticking, which is the ad-hoc signing limitation in Preflight, not a defect in this plan; report it rather than treating it as a failure.

      > Deviation: not executed. The item's precondition is "after every prompt has been answered 'Always Allow'", but the user answered both first-launch prompts with per-session "Allow" (securityd: `user approved 'allow'`), which is their choice to make. Running it anyway would raise two more live password dialogs on the user's screen for an outcome the plan already pre-classifies as the documented ad-hoc-signing limitation. Predicted result if run: 2 more partition prompts, then none for the rest of that session.
- [x] Manual: `for a in zai deepseek; do security find-generic-password -s com.theerakarn.Remaindr -a $a >/dev/null 2>&1 && echo "$a present" || echo "$a absent"; done` - Expected: whatever the Preflight run recorded, unchanged. Nothing in this plan may delete or recreate the user's real items.
- [ ] 👤 Human: leave the app running for at least three refresh intervals (15 minutes at the recorded `refreshIntervalMinutes = 5`), answering the first prompt for each item with **Always Allow** - Expected: no further keychain password dialog appears after the first cycle, for the whole session. Proxy: the `CACHE first=probe-secret deleted=0 second=probe-secret` assertion in Task 2 proves the second and later reads never reach the Keychain, which is everything except the dialog itself.
- [ ] 👤 Human: open Settings from the menu bar item and look at the z.ai row - Expected: the green "Set" badge, not "Not set", for a key Preflight recorded as present. Proxy: the `PRESENCE=true` assertion in Task 1 proves `hasKey` now answers truthfully for an item this build cannot read; only the badge rendering is unverified. This one is Human because Remaindr is a `MenuBarExtra` `LSUIElement` app with no URL and no window an agent can drive.
- [ ] 👤 Human: in Settings, paste your EXISTING z.ai key back into the field - the same value, not a new one - and press Save - Expected: no error message and the green "Set" badge stays. Re-saving the same value is deliberate: it exercises the write path without changing what is stored, so a mistake here cannot cost you a key you would have to go and fetch again. Proxy: the `SAVE=ok` assertion in Task 3 proves the same write path succeeds from a signature the item does not know, which is the case that used to throw `errSecDuplicateItem`.
- [ ] Run (last, after every item above; DEFERRED - see note): `rm -rf /tmp/kc-verify /tmp/kc-dd /tmp/kc-dd-release /tmp/kc-build.log /tmp/kc-release.log; security find-generic-password -s com.theerakarn.Remaindr.verify >/dev/null 2>&1 && echo LEFTOVER || echo clean` - Expected: `clean`. Teardown of the harness tree and proof the throwaway keychain service is gone. It runs last because the three Human items and the two prompt counts need the Release build in `/tmp/kc-dd-release`.

      > Deferred: the three 👤 Human items are still awaiting the user and need `/tmp/kc-dd-release/Build/Products/Release/Remaindr.app` (currently running, pid from `pgrep -f kc-dd-release`). Teardown will run after they are done. Interim state checked: `com.theerakarn.Remaindr.verify` = clean, no harness leftovers.
