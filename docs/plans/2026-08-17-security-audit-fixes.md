# Security Audit Fixes Implementation Plan

> **Run with:** `/execute-plan <path-to-this-file>` - the runner that ticks these
> checkboxes and honours the track/merge layout below.
>
> **For the executing agent:** Implement this plan track-by-track. Parallel
> tracks each get their own `treehouse get --lease` worktree (see Execution).
> Steps use checkbox (`- [ ]`) syntax for tracking; tick them as you go.
> Run the `## Preflight` checks BEFORE task 1 and report anything down.

**Goal:** Fix the six High/Medium/Low findings from `SECURITY_AUDIT.md` (F-01 through F-06) so the shipped app carries no debug entitlement, distributes signed where credentials allow, stores keys under the strictest accessibility class, reads session files with size and overflow guards, and pins TLS certificates on all three provider endpoints.

**Architecture:** Entitlements are declared once in a new empty `.entitlements` file and enforced by a re-sign plus hard assertion inside `make-dmg.sh`, because Xcode's "Sign to Run Locally" fallback stamps `get-task-allow` into Release no matter what the project file says. Keychain writes move to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` with a one-time upgrade of items written by older builds. The Claude session scan gains a per-file size cap and overflow-checked token accumulation. A new `PinnedSession` URLSession delegate fails closed unless the server chain hashes to a pinned certificate, and all three providers are wired to it.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, Security framework, CryptoKit (first-party), URLSession, bash.

**Spec:** `SECURITY_AUDIT.md` (repo root).

**Base commit:** 80eb246. Every line reference below describes this tree.

**Confidence:** 8/10. Rubric deductions: -1 for the Developer ID signing and notarization branch, whose success path cannot be compiled or run on this machine because no signing identity exists (the failure path is fully verified); -1 for the Swift 6 strict-concurrency conformance of the new URLSession delegate, whose exact `Sendable` shape has not yet been compiler-checked. Neither blocks single-track execution.

**NOT building:**
- F-07 (App Sandbox) - a product decision, not a defect fix; sandboxing breaks the documented `~/.claude/projects` read (`Remaindr/Remaindr/Providers/ClaudeProvider.swift:22-26`) and the Claude Code credential read (`Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift:20`).
- F-08 (foreign keychain read) - intentional product behavior per `Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift:8-10`; removing it deletes a feature.
- A `.userPresence` `SecAccessControl` on keychain items - it would demand a biometric or password prompt on every scheduled refresh, which breaks the auto-refresh design (`Remaindr/Remaindr/Models/Preferences.swift:13-16`). The accessibility class change alone is the fix.
- Any test target. The repo has none (`git ls-files | grep -c Test` = 0) and verification uses the swiftc harness precedent from `docs/plans/2026-08-16-aiusagebar-menu-bar-app.md:758-771`.
- Any change to the `UsageProvider` protocol shape.
- F-02's README rewrite beyond the single Gatekeeper-bypass line at `README.md:70`.

## Global Constraints

- Build must succeed with zero warnings (`xcodebuild -scheme Remaindr build`; CLAUDE.md "Commands" section).
- No third-party Swift packages; CryptoKit is a first-party Apple framework and is allowed.
- API keys live in the macOS Keychain only: never `UserDefaults`, never plaintext, never logged, never committed.
- One provider failing must never blank or zero out the others; show a stale value plus a visible error indicator.
- Only make the change this plan describes; no extra features, abstractions, or files.
- Never use the em dash character; use plain hyphens in all written output.
- Long Markdown files put each full sentence on its own physical line.
- Swift 6 language mode is on and enforced, including region-based isolation.
- Deployment target is macOS 14.0; no API newer than macOS 14 without an availability fallback.
- Never auto-add an agent name as co-author to commit messages.

## Patterns to Mirror

### Naming and file layout
SOURCE: `Remaindr/Remaindr/Providers/DeepSeekProvider.swift:8-18`
```swift
struct DeepSeekProvider: UsageProvider {
    let kind: ProviderKind = .deepseek

    private let keychain: KeychainStore
    private let session: URLSession
```
One type per file, doc comment header, dependencies injected through `init` with defaults.

### Error handling
SOURCE: `Remaindr/Remaindr/Models/ProviderStatus.swift:43-63`
```swift
enum ProviderError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    ...
    /// Short text shown next to a stale value. Never contains a key or a token.
    var shortDescription: String {
        switch self {
        case .notConfigured: return "Not configured"
```
Transport failures map through `mapTransportFailure` (`Remaindr/Remaindr/Providers/UsageProvider.swift:16-26`).

### Verification harness (no test target exists)
SOURCE: `docs/plans/2026-08-16-aiusagebar-menu-bar-app.md:757-771`
```bash
mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/main.swift <<'EOF'
...
EOF
swiftc -swift-version 6 <source files> /tmp/.../main.swift -o /tmp/.../binary && /tmp/.../binary
```
Harness prints deterministic `KEY=value` lines; the Expected block lists them exactly.

## Preflight

**DURABLE:**
- treehouse is installed at `/Users/jametirakarn/.local/bin/treehouse` (`command -v treehouse`). This plan is a single track, so it runs sequentially in the main worktree anyway.
- No test target exists: `git ls-files | grep -c Test` prints `0`.
- No third-party dependencies: no `Package.swift` or `Package.resolved` anywhere in `git ls-files`.
- `dmg-resources/` does not exist, so `make-dmg.sh` always takes its no-background path and never runs `osascript`.

**PERISHABLE (re-run each before task 1):**
- `git status --porcelain` prints nothing. Recorded while planning: clean.
- Baseline Release build is green with zero warnings. Re-run:
  `cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr && xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -derivedDataPath build/DerivedData build 2>&1 | grep -c ': warning: '`
  Recorded: `0`, and the build printed `** BUILD SUCCEEDED **`.
- No Developer ID signing identity exists. Re-run: `security find-identity -v -p codesigning`.
  Recorded: `0 valid identities found`.
  Consequence: Task 2's ad-hoc re-sign branch is fully verifiable; the Developer ID and notarization branch is syntax-checked only and is a `Verify - Human` step.
- All three pinned hosts are reachable over TLS and their certificate chains were captured on 2026-08-17. Re-run shape: `echo | openssl s_client -connect api.anthropic.com:443 -servername api.anthropic.com 2>/dev/null | grep -c BEGIN`.
  Recorded: chains captured for `api.anthropic.com`, `api.z.ai`, `api.deepseek.com`.

## Execution

Single sequential track; no treehouse lease needed.
Branch: `security-audit-fixes` off `80eb246`.
Merge order: not applicable (one track).

---

### Task 1: Declare the app's entitlements

Fixes the project half of F-01: an explicit entitlements file, wired into both target configurations, so the app's real entitlement set is declared in one place. Xcode will still inject `get-task-allow` under ad-hoc signing; Task 2's re-sign removes it from the shipped artifact.

**Files:**
- `Remaindr/Remaindr/Remaindr.entitlements` (new)
- `Remaindr/Remaindr.xcodeproj/project.pbxproj` ~164,~185 (the two `CODE_SIGN_STYLE = Automatic;` lines)

**Interfaces:**
      Consumes: nothing new.
      Produces: `Remaindr/Remaindr/Remaindr.entitlements`, a valid empty entitlements plist, referenced by `CODE_SIGN_ENTITLEMENTS` in both target configurations; consumed by Task 2's re-sign step.

**Gotcha:** the project file sits at `Remaindr/Remaindr.xcodeproj`, so build-setting paths are relative to `Remaindr/`: the file is stored at `Remaindr/Remaindr/Remaindr.entitlements` and referenced as `Remaindr/Remaindr.entitlements`. This was probed in a scratch worktree during planning and the build succeeded.

- [x] Step 1: Create `Remaindr/Remaindr/Remaindr.entitlements` with exactly:

      ```xml
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict/>
      </plist>
      ```

- [x] Step 2: In `Remaindr/Remaindr.xcodeproj/project.pbxproj`, in BOTH target configurations (the Debug block `AA00000000000000000000E0` and the Release block `AA00000000000000000000F0`), insert one line directly after `CODE_SIGN_STYLE = Automatic;` (lines 164 and 185 at base commit):

      ```
      				CODE_SIGN_ENTITLEMENTS = Remaindr/Remaindr.entitlements;
      ```

      The indentation is four tabs, matching the surrounding lines. The string `CODE_SIGN_STYLE = Automatic;` appears exactly twice in the file, once per target configuration.

- [x] Step 3: Verify - Run:

      ```bash
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      plutil -lint Remaindr/Remaindr/Remaindr.entitlements
      grep -c 'CODE_SIGN_ENTITLEMENTS = Remaindr/Remaindr.entitlements;' Remaindr/Remaindr.xcodeproj/project.pbxproj
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -derivedDataPath build/DerivedData build 2>&1 | tee /tmp/fix-build.log | tail -2
      grep -c ': warning: ' /tmp/fix-build.log || true
      ```

      Expected: `Remaindr/Remaindr/Remaindr.entitlements: OK`, then `2`, then `** BUILD SUCCEEDED **`, then `0`.

- [x] Step 4: Commit - `git add Remaindr/Remaindr/Remaindr.entitlements Remaindr/Remaindr.xcodeproj/project.pbxproj docs/plans/2026-08-17-security-audit-fixes.md && git commit -m "fix(security): declare explicit app entitlements"`
      > Deviation: the machine's auto-commit daemon committed these files as `0ceacbe` with its own message; content identical to the plan's step.

---

### Task 2: Enforce entitlements and signing in the DMG pipeline

Fixes the shipping half of F-01, all of F-02, and all of F-04.

**Files:**
- `make-dmg.sh` ~28,~41,~72
- `README.md` ~70

**Interfaces:**
      Consumes: `Remaindr/Remaindr/Remaindr.entitlements` from Task 1, referenced from the script's working directory as `Remaindr/Remaindr.entitlements`.
      Produces: nothing other code consumes; produces a shipped `.app` and `.dmg` whose entitlements contain no `get-task-allow`.

**Gotcha:** verified during planning - with no signing identity, Xcode stamps `com.apple.security.get-task-allow` into Release builds even when `CODE_SIGN_ENTITLEMENTS` is set, and only a re-sign removes it:
`codesign --force --sign - --options runtime --entitlements Remaindr/Remaindr/Remaindr.entitlements <app>` leaves `Signature=adhoc`, `flags=0x10002(adhoc,runtime)`, empty entitlements, and passes `codesign --verify --strict`.

- [x] Step 1: In `make-dmg.sh`, insert this block after the `DMG="build/$APP_NAME-$VERSION.dmg"` line (line 28 at base) and before the `# 2. Stage a clean folder` comment:

      ```bash
      # 1b. Re-sign with the app's real entitlements.
      #     Xcode's "Sign to Run Locally" fallback stamps the debug entitlement
      #     com.apple.security.get-task-allow into Release builds, which leaves the
      #     shipped binary attachable by a debugger. Re-signing with the explicit
      #     entitlements file removes it. With a Developer ID identity present the
      #     same re-sign produces a distributable signature.
      ENTITLEMENTS="$APP_NAME/$APP_NAME/Remaindr.entitlements"
      IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')
      if [ -n "$IDENTITY" ]; then
        codesign --force --deep --options runtime --timestamp \
                 --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"
      else
        echo "WARNING: no Developer ID identity found; re-signing ad-hoc (not notarized)." >&2
        codesign --force --sign - --options runtime \
                 --entitlements "$ENTITLEMENTS" "$APP_PATH"
      fi

      # 1c. Refuse to ship any build that still carries the debug entitlement.
      if codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q get-task-allow; then
        echo "ERROR: $APP_PATH still carries com.apple.security.get-task-allow; not shipping." >&2
        exit 1
      fi
      ```

- [x] Step 2: In `make-dmg.sh`, replace the fixed `/tmp/dmg-applescript.txt` path with a private temp directory. Directly after the `CONFIG="Release"` / `DERIVED=` / `DIST=` assignments (line 17 at base), add:

      ```bash
      LAYOUT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/remaindr-dmg.XXXXXX")
      trap 'rm -rf "$LAYOUT_DIR"' EXIT
      LAYOUT_SCRIPT="$LAYOUT_DIR/layout.applescript"
      ```

      Then change the two references: `cat > /tmp/dmg-applescript.txt <<'EOS'` becomes `cat > "$LAYOUT_SCRIPT" <<'EOS'` (line 41 at base), and the step 5 block (lines 72-75 at base) becomes:

      ```bash
      # 5. Apply the saved Finder layout to the final DMG
      if [ -f "$LAYOUT_SCRIPT" ]; then
        osascript "$LAYOUT_SCRIPT"
      fi
      ```

      The standalone `rm -f /tmp/dmg-applescript.txt` line is deleted; the `trap` owns cleanup.

- [x] Step 3: In `make-dmg.sh`, after the `hdiutil create` block (line 69 at base) and before the step 5 comment, insert:

      ```bash
      # 4b. Notarize and staple when both a Developer ID identity and a stored
      #     notary profile exist. Store the profile once with:
      #       xcrun notarytool store-credentials NOTARY_PROFILE --apple-id <id> --team-id <team>
      if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
      fi
      ```

- [x] Step 4: Replace the single README line 70:

      ```
      > Not notarized/signed yet during early development — macOS Gatekeeper may warn on first launch. Right-click → Open to bypass, or build from source.
      ```

      with these three lines:

      ```
      > Early-development builds are not notarized.
      > Prefer building from source (below).
      > If you use a downloaded build, verify its SHA-256 against the checksum published with the release before opening it.
      ```

- [x] Step 5: Verify - Run:

      ```bash
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      bash -n make-dmg.sh && echo SYNTAX_OK
      grep -c 'Right-click' README.md || true
      grep -c 'mktemp -d' make-dmg.sh
      grep -c 'get-task-allow' make-dmg.sh
      ```

      Expected: `SYNTAX_OK`, then `0`, then `1`, then `2`.
      > Deviation: Expected `2` for the last count was a plan miscount; the file correctly contains 3 occurrences (explanatory comment, the `grep -q` assertion, and the error message). All three verified by reading the file.

- [x] Step 6: Verify - Run (the script's re-sign and assertion steps, executed directly against the Task 1 build):

      ```bash
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      codesign --force --sign - --options runtime \
        --entitlements Remaindr/Remaindr/Remaindr.entitlements \
        build/DerivedData/Build/Products/Release/Remaindr.app
      codesign -d --entitlements - build/DerivedData/Build/Products/Release/Remaindr.app 2>/dev/null
      codesign -d --entitlements - build/DerivedData/Build/Products/Release/Remaindr.app 2>/dev/null | grep -c get-task-allow || true
      codesign --verify --strict build/DerivedData/Build/Products/Release/Remaindr.app && echo STRICT_OK
      ```

      Expected: re-sign reports `replacing existing signature`; the entitlements dump prints only `[Dict]` with no keys; the grep prints `0`; `STRICT_OK`.

- [x] Step 7: Commit - `git add make-dmg.sh README.md docs/plans/2026-08-17-security-audit-fixes.md && git commit -m "fix(security): re-sign release without debug entitlement, gate notarization, stop teaching Gatekeeper bypass"`

---

### Task 3: Strictest keychain accessibility plus a one-time upgrade

Fixes F-03. The accessibility class moves to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and items written by older builds under `kSecAttrAccessibleAfterFirstUnlock` are rewritten once at launch.

**Interfaces:**
      Consumes: `ProviderKind.keychainAccount` (`Remaindr/Remaindr/Models/ProviderStatus.swift:33-39`) and the existing `set(_:for:)` / `value(for:)` / `remove(_:)`.
      Produces: `static let accessibility: String` and `func upgradeAccessibility() -> Void` on `KeychainStore`; called once from `RemaindrApp.init()`.

**Files:**
- `Remaindr/Remaindr/Keychain/KeychainStore.swift` ~11,~36,~61
- `Remaindr/Remaindr/App/RemaindrApp.swift` ~10

- [x] Step 1: In `KeychainStore.swift`, add a static accessibility constant below the `service` property (line 11 at base):

      ```swift
      /// The strictest class that still allows unattended refresh: the item never
      /// migrates to another device and is unavailable until the keychain unlocks.
      static let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      ```

      Then change line 36 from `attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock` to `attributes[kSecAttrAccessible as String] = Self.accessibility`.

- [x] Step 2: In `KeychainStore.swift`, add this method after `remove(_:)` (line 61 at base):

      ```swift
      /// Rewrites this app's own items so items written by an older build pick up
      /// the current accessibility class. Absent, empty, or already-current items
      /// are left alone, and no other app's item is ever touched.
      func upgradeAccessibility() {
          for kind in ProviderKind.allCases {
              guard let account = kind.keychainAccount else { continue }
              guard let stored = try? value(for: kind), let stored, !stored.isEmpty else { continue }
              var attributes = query(account)
              attributes[kSecReturnAttributes as String] = true
              var result: CFTypeRef?
              guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
                    let item = result as? [String: Any],
                    (item[kSecAttrAccessible as String] as? String) != Self.accessibility
              else { continue }
              try? set(stored, for: kind)
          }
      }
      ```

- [x] Step 3: In `RemaindrApp.swift`, make `init()` upgrade once before the store is built. Insert as the first line of `init()` (line 10 at base):

      ```swift
      KeychainStore().upgradeAccessibility()
      ```

- [x] Step 4: Verify - Run:

      ```bash
      mkdir -p /tmp/fix-kc && cat > /tmp/fix-kc/main.swift <<'EOF'
      import Foundation
      import Security

      let store = KeychainStore(service: "com.theerakarn.Remaindr.verify")
      let account = "deepseek"

      func attributes() -> String? {
          var query: [String: Any] = [
              kSecClass as String: kSecClassGenericPassword,
              kSecAttrService as String: "com.theerakarn.Remaindr.verify",
              kSecAttrAccount as String: account,
              kSecReturnAttributes as String: true,
          ]
          var result: CFTypeRef?
          guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                let item = result as? [String: Any] else { return nil }
          return item[kSecAttrAccessible as String] as? String
      }

      // Fresh write must use the strict class.
      SecItemDelete([
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.theerakarn.Remaindr.verify",
          kSecAttrAccount as String: account,
      ] as CFDictionary)
      try store.set("probe-value", for: .deepseek)
      print("FRESH=\(attributes() == KeychainStore.accessibility)")

      // Simulate a legacy item written by an older build.
      SecItemDelete([
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.theerakarn.Remaindr.verify",
          kSecAttrAccount as String: account,
      ] as CFDictionary)
      var legacy: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.theerakarn.Remaindr.verify",
          kSecAttrAccount as String: account,
          kSecValueData as String: Data("probe-value".utf8),
          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      ]
      print("LEGACY_ADD=\(SecItemAdd(legacy as CFDictionary, nil) == errSecSuccess)")
      store.upgradeAccessibility()
      print("UPGRADED=\(attributes() == KeychainStore.accessibility)")

      try store.remove(.deepseek)
      print("CLEANED=\(attributes() == nil)")
      EOF
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      swiftc -swift-version 6 \
        Remaindr/Remaindr/Models/ProviderStatus.swift \
        Remaindr/Remaindr/Keychain/KeychainStore.swift \
        /tmp/fix-kc/main.swift -o /tmp/fix-kc/kc && /tmp/fix-kc/kc
      ```

      Expected, exactly these four lines:

      ```
      FRESH=true
      LEGACY_ADD=true
      UPGRADED=true
      CLEANED=true
      ```

- [x] Step 5: Verify - Run:

      ```bash
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -derivedDataPath build/DerivedData build 2>&1 | tee /tmp/fix-build.log | tail -1
      grep -c ': warning: ' /tmp/fix-build.log || true
      ```

      Expected: `** BUILD SUCCEEDED **`, then `0`.

- [x] Step 6: Commit - `git add Remaindr/Remaindr/Keychain/KeychainStore.swift Remaindr/Remaindr/App/RemaindrApp.swift docs/plans/2026-08-17-security-audit-fixes.md && git commit -m "fix(security): store keys WhenUnlockedThisDeviceOnly and upgrade existing items"`

---

> Deviation: broken plan assumption. macOS 26 never reports `kSecAttrAccessible` back from `SecItemCopyMatching` and treats it as a non-discriminating query constraint, verified empirically against the live keychain, so the read-back guard in the planned `upgradeAccessibility` can never work and the planned harness Expected (`FRESH=true`/`UPGRADED=true`) is unsatisfiable on this OS.
      Corrections applied: (1) `static let accessibility: String = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String` - Swift 6 rejects a stored `CFString` static and the cast needs to be explicit; (2) `guard let stored = try? value(for: kind), !stored.isEmpty` - `try?` already flattens the optional so the second `let stored` did not compile; (3) `upgradeAccessibility()` rewrites unconditionally and the once-only gate lives in `RemaindrApp.init()` behind a new `Preferences.keychainAccessibilityUpgraded` flag; (4) Step 4's harness was replaced with one asserting what is observable on this OS (`ROUNDTRIP`, `MIGRATION_PRESERVES`, `IDEMPOTENT`, `ABSENT_STAYS_ABSENT`, `CLEANED`, all `true`), with the strict class itself verified by code inspection at `KeychainStore.swift:19,40`; (5) Preferences.swift and ConfigFileStore.swift joined the task's Files block to carry the flag.
      (6) Follow-up refinement: `upgradeAccessibility` now applies `SecItemUpdate` with only `kSecAttrAccessible` in place of the planned delete-and-re-add, because recreating an item discards its ACL and partition list and re-prompts for keychain access on this ad-hoc-signed app; the in-place update also never reads the secret. Verified by harness (`VALUE_PRESERVED`, `IDEMPOTENT`, `CLEANED`, all true).
### Task 4: Size cap and overflow-safe aggregation on the session scan

Fixes F-05.

**Files:**
- `Remaindr/Remaindr/Providers/ClaudeSessionBlocks.swift` ~12,~79
- `Remaindr/Remaindr/Providers/ClaudeProvider.swift` ~20,~88,~94

- [x] Step 1: In `ClaudeSessionBlocks.swift`, replace the `totalTokens` property of `ClaudeUsageEntry` (lines 12-14 at base):

      ```swift
      var totalTokens: Int {
          inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens
      }
      ```

      with an overflow-checked version that saturates instead of trapping:

      ```swift
      /// Saturates rather than trapping: session files are local input this app
      /// does not control, and a crashing menu bar app helps nobody.
      var totalTokens: Int {
          var total = 0
          for count in [inputTokens, cacheCreationTokens, cacheReadTokens, outputTokens] {
              let (sum, overflow) = total.addingReportingOverflow(count)
              if overflow { return Int.max }
              total = sum
          }
          return total
      }
      ```

- [x] Step 2: In `ClaudeSessionBlocks.swift`, inside `blocks(from:)` (line 79 at base), replace:

      ```swift
      total += entry.totalTokens
      previous = entry.timestamp
      continue
      ```

      with:

      ```swift
      let (sum, overflow) = total.addingReportingOverflow(entry.totalTokens)
      guard !overflow else {
          // A total that cannot grow means the entries so far are corrupt or
          // hostile; keep the block, skip the entry, never trap.
          previous = entry.timestamp
          continue
      }
      total = sum
      previous = entry.timestamp
      continue
      ```

- [x] Step 3: In `ClaudeProvider.swift`, add the cap constant inside `struct ClaudeProvider` below the `allowBilledProbe` property (line 20 at base):

      ```swift
      /// Session files larger than this are skipped: the scan reads whole files
      /// into memory, and a planted huge file must not be able to jetsam the app.
      static let maxSessionFileBytes = 16 * 1024 * 1024
      ```

      Then in `scanBlocks(in:)`, change the enumerator's key array to `[.isRegularFileKey, .fileSizeKey]` (line 88 at base), and gate the read (line 94 at base):

      ```swift
      for case let url as URL in walker where url.pathExtension == "jsonl" {
          let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
          guard size <= Self.maxSessionFileBytes else { continue }
          guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      ```

- [x] Step 4: Verify - Run:

      ```bash
      mkdir -p /tmp/fix-ov && cat > /tmp/fix-ov/main.swift <<'EOF'
      import Foundation

      func assistantLine(id: String, input: Int) -> String {
          """
          {"type":"assistant","requestId":"req-\(id)","timestamp":"2026-08-17T01:00:00Z","message":{"id":"msg-\(id)","model":"claude-x","usage":{"input_tokens":\(input),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
          """
      }

      // Overflow saturates instead of trapping.
      let huge = ClaudeUsageEntry(timestamp: Date(), dedupeKey: "a", inputTokens: Int.max / 2,
                                  cacheCreationTokens: Int.max / 2, cacheReadTokens: 0, outputTokens: 0)
      print("ENTRY_SATURATED=\(huge.totalTokens == Int.max)")

      // Aggregating saturating entries never traps.
      let entries = [
          ClaudeUsageEntry(timestamp: Date(timeIntervalSince1970: 0), dedupeKey: "a", inputTokens: Int.max / 2,
                           cacheCreationTokens: Int.max / 2, cacheReadTokens: 0, outputTokens: 0),
          ClaudeUsageEntry(timestamp: Date(timeIntervalSince1970: 60), dedupeKey: "b", inputTokens: Int.max / 2,
                           cacheCreationTokens: Int.max / 2, cacheReadTokens: 0, outputTokens: 0),
      ]
      let blocks = ClaudeSessionBlocks.blocks(from: entries)
      print("BLOCKS_NO_TRAP=\(blocks.count == 1)")
      print("BLOCK_SATURATED=\(blocks.first?.totalTokens == Int.max)")

      // A file over the cap is skipped; a normal file beside it still counts.
      let dir = FileManager.default.temporaryDirectory
          .appendingPathComponent("fix-ov-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let big = dir.appendingPathComponent("big.jsonl")
      let small = dir.appendingPathComponent("small.jsonl")
      try String(repeating: "x", count: 17 * 1024 * 1024).write(to: big, atomically: true, encoding: .utf8)
      try assistantLine(id: "1", input: 42).write(to: small, atomically: true, encoding: .utf8)
      let scanned = ClaudeProvider.scanBlocks(in: dir)
      print("CAP_SKIPS_BIG=\(scanned.count == 1 && scanned[0].totalTokens == 42)")
      try? FileManager.default.removeItem(at: dir)
      EOF
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      swiftc -swift-version 6 \
        Remaindr/Remaindr/Models/ProviderStatus.swift \
        Remaindr/Remaindr/Providers/UsageProvider.swift \
        Remaindr/Remaindr/Keychain/KeychainStore.swift \
        Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift \
        Remaindr/Remaindr/Providers/ClaudeSessionBlocks.swift \
        Remaindr/Remaindr/Providers/ClaudeProvider.swift \
        /tmp/fix-ov/main.swift -o /tmp/fix-ov/ov && /tmp/fix-ov/ov
      ```

      Expected, exactly these four lines:

      ```
      ENTRY_SATURATED=true
      BLOCKS_NO_TRAP=true
      BLOCK_SATURATED=true
      CAP_SKIPS_BIG=true
      ```

- [x] Step 5: Verify - Run:

      ```bash
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -derivedDataPath build/DerivedData build 2>&1 | tee /tmp/fix-build.log | tail -1
      grep -c ': warning: ' /tmp/fix-build.log || true
      ```

      Expected: `** BUILD SUCCEEDED **`, then `0`.

- [x] Step 6: Commit - `git add Remaindr/Remaindr/Providers/ClaudeSessionBlocks.swift Remaindr/Remaindr/Providers/ClaudeProvider.swift docs/plans/2026-08-17-security-audit-fixes.md && git commit -m "fix(security): cap session file size and saturate token totals instead of trapping"`

---

> Deviation: two plan defects surfaced and were corrected. (1) The reference code for Step 2 carried wrong indentation for the two continuation lines inside `blocks(from:)` (the real file indents them three spaces); the edit was re-anchored on the actual text. (2) The Step 4 harness miscounted its own arithmetic: `Int.max / 2 + Int.max / 2` is `Int.max - 1` without overflow, so `ENTRY_SATURATED` needed a third addend (`cacheReadTokens: 8`) to force saturation and `BLOCK_SATURATED` must expect `Int.max - 1` (the first entry saturates the block total; the second is skipped). Both corrected assertions pass; the code's own behavior never changed.
### Task 5: Pin TLS certificates on the three provider endpoints

Fixes F-06. Four files, one atomic change: the delegate, its error surface, and the wiring, committed together because every intermediate split would leave a half-connected pinning layer.

**Files:**
- `Remaindr/Remaindr/Providers/PinnedSession.swift` (new)
- `Remaindr/Remaindr/Models/ProviderStatus.swift` ~50,~61
- `Remaindr/Remaindr/Providers/UsageProvider.swift` ~16
- `Remaindr/Remaindr/UI/ProviderStore.swift` ~32

**Interfaces:**
      Consumes: `ClaudeProvider.init(keychain:session:projectsDirectory:allowBilledProbe:)`, `ZAIProvider.init(keychain:session:)`, and `DeepSeekProvider.init(keychain:session:)`, which already accept a `URLSession`; also `ProviderError` and `mapTransportFailure`.
      Produces: `enum PinnedSession` with `static let shared: URLSession`, `static let pins: [String: [String]]`, `static func certificateHash(_ certificate: SecCertificate) -> String`, and `final class Delegate` with `init(pins: [String: [String]] = PinnedSession.pins)`; plus `ProviderError.untrustedServer`.

**Gotcha:** pins are SHA-256 over the whole DER certificate, not over the SPKI, because `SecKeyCopyExternalRepresentation` returns the raw key without the SubjectPublicKeyInfo wrapper and no first-party API reconstructs it. Certificate pinning over the leaf plus issuing CA is the TrustKit `SSLPinMode.certificate` shape: a leaf renewal is covered by the CA pin, a CA change is a visible failure until the pins are refreshed.

- [x] Step 1: Create `Remaindr/Remaindr/Providers/PinnedSession.swift` with exactly:

      ```swift
      import CryptoKit
      import Foundation

      /// A URLSession whose server trust must match a pinned certificate hash.
      ///
      /// Fail-closed certificate pinning for the three hosts this app sends
      /// credentials to. A host with no pins, or whose chain contains neither a
      /// pinned leaf nor a pinned issuing CA, cancels the challenge rather than
      /// falling back to system trust, so a rogue or intercepted CA cannot harvest
      /// a key. Pins are base64 SHA-256 over the whole DER certificate.
      ///
      /// Refreshing the pins: capture the new chains with
      ///   echo | openssl s_client -connect <host>:443 -servername <host> -showcerts
      /// save each PEM block to its own file, then hash it with
      ///   openssl x509 -outform DER -in cert.pem | openssl dgst -sha256 -binary | base64
      /// and replace the leaf entry; keep the CA entry when the CA is unchanged.
      enum PinnedSession {
          /// Base64 SHA-256 of each host's leaf and issuing CA certificates,
          /// captured 2026-08-17.
          static let pins: [String: [String]] = [
              "api.anthropic.com": [
                  "oKzenjNbvk+BU+TLrWMnzeW09tkHzoj5mUZzgYrlPjg=", // leaf CN=api.anthropic.com
                  "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=", // CA Google Trust Services WE1
              ],
              "api.z.ai": [
                  "vCXiRElVzr29slyOBUtRUb0N3KrSPNNjWEEgfEHoUHA=", // leaf CN=*.z.ai
                  "jFTDNLZrpOQmdyr0o/kTbBmhrscp/bKMU1wHpaTvIuA=", // CA Sectigo Public Server Authentication CA DV
              ],
              "api.deepseek.com": [
                  "CxEkdgkFfa14FpGFLwGuLqUsnEfNYykPMvhculJbR10=", // leaf CN=*.deepseek.com
                  "Uzjr7I+yrGCZYSbT52qjT9DzMYrHjrt6yPbxNh9ISzM=", // CA Amazon RSA 2048 M01
              ],
          ]

          /// The one session every provider client uses.
          static let shared: URLSession = {
              let configuration = URLSessionConfiguration.default
              return URLSession(configuration: configuration, delegate: Delegate(), delegateQueue: nil)
          }()

          /// Base64 SHA-256 over a certificate's DER encoding.
          static func certificateHash(_ certificate: SecCertificate) -> String {
              let der = SecCertificateCopyData(certificate) as Data
              return Data(SHA256.hash(data: der)).base64EncodedString()
          }

          /// The delegate that enforces the pins. Injectable pins exist so a
          /// harness can prove the fail-closed path without touching production.
          final class Delegate: NSObject, URLSessionDelegate, @unchecked Sendable {
              private let pins: [String: [String]]

              init(pins: [String: [String]] = PinnedSession.pins) {
                  self.pins = pins
              }

              func urlSession(_ session: URLSession,
                              didReceive challenge: URLAuthenticationChallenge) async
                  -> (URLSession.AuthChallengeDisposition, URLCredential?) {
                  guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                        let trust = challenge.protectionSpace.serverTrust else {
                      return (.performDefaultHandling, nil)
                  }
                  let host = challenge.protectionSpace.host
                  guard let hostPins = pins[host], !hostPins.isEmpty,
                        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
                      return (.cancelAuthenticationChallenge, nil)
                  }
                  let hashes = Set(chain.map(PinnedSession.certificateHash))
                  guard !hostPins.isDisjoint(with: hashes) else {
                      return (.cancelAuthenticationChallenge, nil)
                  }
                  var error: CFError?
                  guard SecTrustEvaluateWithError(trust, &error) else {
                      return (.cancelAuthenticationChallenge, nil)
                  }
                  return (.useCredential, URLCredential(trust: trust))
              }
          }
      }
      ```

      If Swift 6 strict concurrency rejects `@unchecked Sendable` on the delegate or the async challenge handler signature, apply the smallest correction the compiler asks for (for example dropping `@unchecked Sendable`, or switching to the completion-handler form) and record a `> Deviation:` line; the fail-closed semantics must survive any such correction.

- [x] Step 2: In `ProviderStatus.swift`, add a case to `ProviderError` after `noActivePlan` (line 50 at base):

      ```swift
      /// The server's certificate chain did not match a pinned certificate.
      case untrustedServer
      ```

      and a branch in `shortDescription` (after line 61):

      ```swift
      case .untrustedServer: return "Connection untrusted"
      ```

- [x] Step 3: In `UsageProvider.swift`, inside `mapTransportFailure`'s `switch` (line 18 at base), add `.cancelled` to the mapped set with its own return, and extend the doc comment above the method by one line:

      ```swift
      case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
           .cannotConnectToHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff,
           .dataNotAllowed, .secureConnectionFailed:
          return ProviderError.offline
      case .cancelled:
          // The pinning delegate is the only code path that cancels a challenge;
          // no provider cancels its own requests.
          return ProviderError.untrustedServer
      ```

- [x] Step 4: In `ProviderStore.swift`, wire the pinned session into all three providers inside `provider(for:)` (lines 32-42 at base):

      ```swift
      case .claude:
          return ClaudeProvider(keychain: keychain,
                                session: PinnedSession.shared,
                                allowBilledProbe: preferences.allowBilledClaudeProbe)
      case .zai:
          return ZAIProvider(keychain: keychain, session: PinnedSession.shared)
      case .deepseek:
          return DeepSeekProvider(keychain: keychain, session: PinnedSession.shared)
      ```

- [x] Step 5: Verify - Run (live pin check; three bare TLS handshakes and GETs to the host roots, no credentials, no API call, nothing billed):

      ```bash
      mkdir -p /tmp/fix-pin && cat > /tmp/fix-pin/main.swift <<'EOF'
      import Foundation

      func check(host: String, pins: [String: [String]]) async -> String {
          let config = URLSessionConfiguration.default
          config.timeoutIntervalForRequest = 15
          let session = URLSession(configuration: config,
                                   delegate: PinnedSession.Delegate(pins: pins),
                                   delegateQueue: nil)
          do {
              let (_, response) = try await session.data(from: URL(string: "https://\(host)")!)
              await session.finishTasksAndInvalidate()
              return "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
          } catch let error as URLError where error.code == .cancelled {
              await session.finishTasksAndInvalidate()
              return "CANCELLED"
          } catch {
              await session.finishTasksAndInvalidate()
              return "ERROR \(error.localizedDescription.prefix(30))"
          }
      }

      let hosts = ["api.anthropic.com", "api.z.ai", "api.deepseek.com"]
      for host in hosts {
          print("PIN_OK_\(host)=\(await check(host: host, pins: PinnedSession.pins) != "CANCELLED")")
      }
      print("GARBAGE_PINS_CANCEL=\(await check(host: hosts[0], pins: [:]) == "CANCELLED")")
      EOF
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      swiftc -swift-version 6 \
        Remaindr/Remaindr/Models/ProviderStatus.swift \
        Remaindr/Remaindr/Providers/UsageProvider.swift \
        Remaindr/Remaindr/Keychain/KeychainStore.swift \
        Remaindr/Remaindr/Providers/PinnedSession.swift \
        /tmp/fix-pin/main.swift -o /tmp/fix-pin/pin && /tmp/fix-pin/pin
      ```

      Expected, exactly these four lines:

      ```
      PIN_OK_api.anthropic.com=true
      PIN_OK_api.z.ai=true
      PIN_OK_api.deepseek.com=true
      GARBAGE_PINS_CANCEL=true
      ```

- [x] Step 6: Verify - Run:

      ```bash
      cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr
      xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -derivedDataPath build/DerivedData build 2>&1 | tee /tmp/fix-build.log | tail -1
      grep -c ': warning: ' /tmp/fix-build.log || true
      ```

      Expected: `** BUILD SUCCEEDED **`, then `0`.

- [x] Step 7: Commit - `git add Remaindr/Remaindr/Providers/PinnedSession.swift Remaindr/Remaindr/Models/ProviderStatus.swift Remaindr/Remaindr/Providers/UsageProvider.swift Remaindr/Remaindr/UI/ProviderStore.swift docs/plans/2026-08-17-security-audit-fixes.md && git commit -m "fix(security): pin TLS certificates on all three provider endpoints, fail closed"`

---

## End-to-end verification

- [x] Run: `cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr && bash -n make-dmg.sh && echo SYNTAX_OK` - Expected: `SYNTAX_OK`.
- [x] Run: `cd /Users/jametirakarn/Desktop/Theerakarnm/remaindr && ./make-dmg.sh > /tmp/make-dmg.log 2>&1; echo rc=$?; tail -2 /tmp/make-dmg.log` - Expected: `rc=0` and `Created: build/Remaindr-1.0.dmg`.
  The script takes its no-background path (`dmg-resources/` does not exist), so no `osascript` runs and no Finder window appears.
- [x] Run: `codesign -d --entitlements - build/dmg-staging/Remaindr.app 2>/dev/null | grep -c get-task-allow || true` - Expected: `0`.
- [x] Run: `hdiutil verify build/Remaindr-1.0.dmg | tail -1` - Expected: a line ending `devrdisk image is valid` or equivalent `...verified`.
- [x] Run: `grep -c 'kSecAttrAccessibleAfterFirstUnlock' Remaindr/Remaindr/Keychain/KeychainStore.swift || true` - Expected: `1` (only inside `upgradeAccessibility`, never in `set`).
  > Deviation: actual count `0`. The Task 3 follow-up refinement (in-place `SecItemUpdate`) removed the last reference to the legacy class, so the strict class is now the only one in the file - a strictly stronger outcome than the plan's expectation.
- [x] Run: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Debug -derivedDataPath build/DerivedData build 2>&1 | tail -1` - Expected: `** BUILD SUCCEEDED **` (Debug still builds with the entitlements wired).
- [x] Run: `git status --porcelain` - Expected: empty, or only untracked build artifacts.
- [ ] 👤 Verify - Human: with a Developer ID Application certificate in the keychain and `NOTARY_PROFILE` stored via `xcrun notarytool store-credentials`, run `NOTARY_PROFILE=<profile> ./make-dmg.sh` and confirm the printed log shows the identity re-sign, a notarytool submission accepted, and `stapler staple` succeeding, then check `spctl -a -vv build/Remaindr-1.0.dmg` reports accepted.
  Proxy: Task 2 Step 6 proves the re-sign plus assertion path end to end on the ad-hoc branch, `bash -n` proves the identity branch parses, and the branch is selected by the same `IDENTITY` test the human run exercises.
  > Awaiting human: no Developer ID certificate or notary profile exists on this machine (`security find-identity -v -p codesigning` prints `0 valid identities found`).

## Failure handling summary

- If Task 5's delegate fails Swift 6 strict concurrency in a way the noted corrections cannot satisfy, STOP and report rather than weakening the isolation model (for example by making `pins` mutable shared state).
- If Task 2 Step 6 still shows `get-task-allow` after the re-sign, STOP: the entitlements file path or the signature operation is wrong, and shipping would fail the assertion in a real run.
- If any live pin check in Task 5 Step 5 returns `CANCELLED` for a pinned host, do not delete the pin to make the check pass; re-capture the chain, and if the CA genuinely changed, record it as a deviation with both old and new pins.

> Deviation: three corrections, none changing the fail-closed semantics. (1) `hostPins.isDisjoint(with:)` does not exist on `Array`; the code now reads `Set(hostPins).isDisjoint(with: hashes)`. (2) The Step 5 harness probed `https://<host>/`, and `api.z.ai/` 301-redirects to `z.ai`, an unpinned host, so the delegate correctly fail-closed on the redirect; the harness now probes each host's real unauthenticated API path (`/api/oauth/usage`, `/api/monitor/usage/quota/limit`, `/user/balance`), all of which stay on-host. Observed results: `HTTP 429`, `HTTP 200`, `HTTP 401`, plus `GARBAGE_PINS_CANCEL=true`. No credentials were sent by any probe. (3) The earlier scratch typecheck of this file had silently covered only a truncated extraction, so the `isDisjoint` defect was caught here rather than during planning.
