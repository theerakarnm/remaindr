# SECURITY_AUDIT.md - Security Audit Report

**Project:** Remaindr (macOS SwiftUI menu bar usage monitor for Claude, z.ai/GLM, DeepSeek)
**Repo root:** `/Users/jametirakarn/Desktop/Theerakarnm/remaindr`
**Audit type:** read-only static audit of all 19 Swift sources, `project.pbxproj`, `make-dmg.sh`, generated entitlements/Info.plists, and the built Release artifacts under `build/` (signature and strings inspection only; nothing was built, run, or executed).
**Threat model:** (1) local unprivileged process/malicious app on the same Mac, (2) network attacker on hostile Wi-Fi, (3) malicious server/API response, (4) attacker with read access to disk/backups.
**Method:** full read of every source file in `Remaindr/Remaindr/`, `Remaindr/Remaindr.xcodeproj/project.pbxproj`, `make-dmg.sh`, `.gitignore`, both READMEs, the tracked plan doc, generated `Entitlements.plist` and shipped `Info.plist`; marker grep sweep across the tree; `codesign -dv`/`codesign -d --entitlements` on the two built `.app` copies; `strings` sweep of the Release Mach-O.

Findings are ranked by severity, then by exploitability.

---

### [F-01] Release build ships ad-hoc signed with `com.apple.security.get-task-allow`, enabling silent in-memory credential theft by any same-user process

**Severity:** High

**Category:** 3. Sandbox, entitlements & hardened runtime

**Location:** `Remaindr/Remaindr.xcodeproj/project.pbxproj:182-201` (Release target config; `CODE_SIGN_STYLE = Automatic` at line 185, no `DEVELOPMENT_TEAM`, no `CODE_SIGN_IDENTITY` anywhere in the file). Verified in the built artifact `build/DerivedData/Build/Intermediates.noindex/Remaindr.build/Release/Remaindr.build/DerivedSources/Entitlements.plist:5-6` and identical in `build/dmg-staging/Remaindr.app`.

**Evidence:**

    // project.pbxproj, Release target configuration (AA00000000000000000000F0)
    184| isa = XCBuildConfiguration;
    185| buildSettings = {
    185|     CODE_SIGN_STYLE = Automatic;      // no DEVELOPMENT_TEAM, no CODE_SIGN_IDENTITY
    188|     ENABLE_HARDENED_RUNTIME = YES;

    // build/.../Release/Remaindr.build/DerivedSources/Entitlements.plist
    5|  <key>com.apple.security.get-task-allow</key>
    6|  <true/>

    // verified via codesign -d --entitlements on both built .app copies:
    //   CodeDirectory flags=0x10002(adhoc,runtime)  Signature=adhoc  TeamIdentifier=not set
    //   [Key] com.apple.security.get-task-allow  [Value] true

**Attack path:** A malicious local app running as the same user (threat 1) ad-hoc signs itself with the `get-task-allow` entitlement, which requires no Apple approval. Remaindr runs permanently in the menu bar and, on every 1-60 minute refresh, loads the z.ai and DeepSeek API keys from its Keychain and the Claude Code OAuth access token (read from the `Claude Code-credentials` keychain item) into memory to build `Authorization` headers (`ClaudeAccountUsage.swift:51`, `ZAIProvider.swift:48`, `DeepSeekProvider.swift:39`). Because the shipped Remaindr binary itself carries `get-task-allow` while SIP is otherwise on, the malware can call `task_for_pid` on the running Remaindr process, attach a debugger, and dump its memory to recover the raw keys and `Bearer` token strings. No Keychain ACL prompt appears and the user sees nothing. Impact: silent theft of every configured provider credential, including the Claude Code OAuth token, which grants account-level access.

**Why it is wrong:** `get-task-allow` in a release/distributed build disables the debugger-attachment protection that hardened runtime is meant to provide; it is normally a Debug-only convenience. The root cause is that `CODE_SIGN_STYLE = Automatic` with no team or identity makes Xcode fall back to ad-hoc signing, which adds `get-task-allow` and produces a new, untrusted signature on every rebuild.

**Remediation:** Configure a real signing identity for Release and assert the entitlement is absent.

    // project.pbxproj, Release target config
    CODE_SIGN_STYLE = Manual;
    CODE_SIGN_IDENTITY = "Developer ID Application";
    DEVELOPMENT_TEAM = <TEAMID>;

    // CI assertion (fails the release if get-task-allow sneaks back in):
    codesign -d --entitlements - "$APP" | grep -q get-task-allow && exit 1
    codesign verify --deep --strict --verbose=2 "$APP"

---

### [F-02] Distribution DMG is unsigned and un-notarized, and the README trains users to bypass Gatekeeper

**Severity:** Medium

**Category:** 3. Sandbox, entitlements & hardened runtime / 11. Update & distribution channel

**Location:** `make-dmg.sh:64-79` (DMG creation with no signing or notarization step anywhere in the file); corroborated by `README.md:70`.

**Evidence:**

    // make-dmg.sh - the entire post-build pipeline; no codesign/notarytool/stapler
    64| # 4. Create the DMG (UDZO = zlib-compressed, the standard distributable format)
    65| hdiutil create -volname "$APP_NAME" \
    66|                -srcfolder "$DIST" \
    67|                -ov \
    68|                -format UDZO \
    69|                "$DMG"
    ...
    77| echo ""
    78| echo "Created: $DMG"

    // README.md:70
    70| > Not notarized/signed yet during early development ... Right-click -> Open to bypass, or build from source.

**Attack path:** The distributed artifact has no Developer ID signature and no notarization ticket. A network attacker (threat 2) who can interfere with the download path (untrusted mirror, hostile proxy for an http fetch of the DMG, substituted GitHub release asset) or a disk/backup attacker (threat 4) who replaces the `.dmg` delivers a trojaned build. Users have been instructed to dismiss Gatekeeper warnings with right-click, Open, so the modified app installs and runs; it then holds the same keychain-reading capabilities as the real app plus arbitrary attacker code. There is also no update channel (see category 11), so every version bump repeats this exposure.

**Why it is wrong:** Notarization plus a stable Developer ID signature is the only client-side mechanism that lets macOS detect a tampered or substituted app before first run. Documenting the Gatekeeper bypass institutionalizes the weakness.

**Remediation:** Sign, notarize, and staple in `make-dmg.sh` after step 4:

    codesign --force --deep --options runtime --timestamp \
      --sign "Developer ID Application: <NAME> (<TEAMID>)" "$DIST/$APP_NAME.app"
    xcrun notarytool submit "build/$APP_NAME-$VERSION.dmg" --keychain-profile AC_NOTARY --wait
    xcrun stapler staple "build/$APP_NAME-$VERSION.dmg"

    And update README.md:70 to remove the right-click bypass instruction once notarized.

---

### [F-03] API keys stored with `kSecAttrAccessibleAfterFirstUnlock` and no `SecAccessControl`

**Severity:** Low

**Category:** 1. Secrets & credential storage

**Location:** `Remaindr/Remaindr/Keychain/KeychainStore.swift:36`

**Evidence:**

    34| var attributes = query(account)
    35| attributes[kSecValueData as String] = Data(trimmed.utf8)
    36| attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    37| let status = SecItemAdd(attributes as CFDictionary, nil)

**Attack path:** The stored z.ai/DeepSeek/Claude-probe keys remain readable by any process running as the user after the Mac has been unlocked once, including malware that starts while the screen is merely locked again (threat 1 variant), and they are eligible for migration in backup/restore flows that honor the non-`ThisDeviceOnly` accessibility class (threat 4). No `SecAccessControl` is attached, so the items are not bound to user presence. Exploitation still requires same-user code execution or a device state where the login keychain is already unlocked-after-first-unlock, which is why this is rated Low rather than higher.

**Why it is wrong:** For secrets that are only ever used while the user is actively at the machine, `WhenUnlockedThisDeviceOnly` is the correct accessibility class, and a `SecAccessControl` with `.userPresence` binds decryption to the user, not just the account.

**Remediation:**

    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    var error: Unmanaged<CFError>?
    if let acl = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                 .userPresence, &error) {
        attributes[kSecAttrAccessControl as String] = acl
    }

---

### [F-04] Build script writes a predictable temp file in shared `/tmp` and then executes it

**Severity:** Low

**Category:** 8. Local data at rest / 4. Process execution & command injection

**Location:** `make-dmg.sh:41` (write), `make-dmg.sh:72-74` (execute + remove)

**Evidence:**

    41|   cat > /tmp/dmg-applescript.txt <<'EOS'
    ...
    72| if [ -f /tmp/dmg-applescript.txt ]; then
    73|   osascript /tmp/dmg-applescript.txt
    74|   rm -f /tmp/dmg-applescript.txt

**Attack path:** A second local user account on the developer machine (threat 1) pre-creates `/tmp/dmg-applescript.txt` as a symlink to any file the build user can write, before `make-dmg.sh` runs. The `cat >` redirect follows the symlink and clobbers the target with the fixed AppleScript text; `[ -f ... ]` also follows symlinks and `rm -f` deletes through it. If the attacker instead wins the race and replaces the file content between line 41 and line 73, `osascript` executes attacker-chosen AppleScript (which can `do shell script`) as the build user, i.e. arbitrary code execution at build time. The race window is small and the attacker needs a separate local account, hence Low.

**Why it is wrong:** Fixed paths in the world-writable, cross-user `/tmp` directory are the classic symlink-race primitive, and executing a file from that directory converts the clobber into potential code execution.

**Remediation:**

    WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/dmg-layout.XXXXXX")
    trap 'rm -rf "$WORKDIR"' EXIT
    cat > "$WORKDIR/layout.applescript" <<'EOS'
    ...
    EOS
    osascript "$WORKDIR/layout.applescript"

---

### [F-05] Local Claude session scan reads whole files without size limits and sums token counts with unchecked `Int` arithmetic

**Severity:** Low

**Category:** 12. Memory & language-level safety / 6. Untrusted input handling

**Location:** `Remaindr/Remaindr/Providers/ClaudeProvider.swift:94` (unbounded whole-file read); `Remaindr/Remaindr/Providers/ClaudeSessionBlocks.swift:79` with attacker-influenced operands from `ClaudeSessionBlocks.swift:51-54`

**Evidence:**

    // ClaudeProvider.swift
    94| guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

    // ClaudeSessionBlocks.swift
    51| inputTokens: usage["input_tokens"] as? Int ?? 0,
    ...
    79| total += entry.totalTokens

**Attack path:** Any process running as the user (threat 1) can write into `~/.claude/projects/`, which the app scans on every refresh. A planted multi-gigabyte `.jsonl` file is loaded fully into memory by `String(contentsOf:)` (inflated again as a Swift String), spiking memory and potentially jetsamming the menu bar app. Alternatively, three well-formed assistant lines each carrying `input_tokens` near `Int.max` make `total += entry.totalTokens` at line 79 trap on overflow and crash the app (remote/local DoS only; no memory corruption). Impact is limited to denial of service of a menu bar utility, hence Low.

**Why it is wrong:** File-derived and network-derived values flow into unbounded reads and unchecked arithmetic without caps. Swift traps (crashes) on integer overflow rather than wrapping.

**Remediation:**

    // size cap before reading
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size <= 16 * 1024 * 1024 else { continue }

    // overflow-safe accumulation
    let (sum, overflow) = total.addingReportingOverflow(entry.totalTokens)
    guard !overflow else { continue }
    total = sum

---

### [F-06] No certificate pinning on the three credential-bearing endpoints

**Severity:** Low

**Category:** 2. Transport security

**Location:** `Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift:46`, `Remaindr/Remaindr/Providers/ZAIProvider.swift:22`, `Remaindr/Remaindr/Providers/DeepSeekProvider.swift:13` (all requests use default `URLSession` trust evaluation)

**Evidence:**

    46| var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    51| request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    // ZAIProvider.swift:22 / DeepSeekProvider.swift:13: same pattern via URLSession.shared

**Attack path:** Default TLS validation is used, so any attacker (threat 2) who controls a CA-trusted certificate (corporate TLS-intercepting proxy with an installed root, a compromised/rogue CA, or malware that installed a root profile) can MITM `api.anthropic.com`, `api.z.ai`, or `api.deepseek.com` and capture the OAuth Bearer token and API keys sent on every refresh. No `URLSessionDelegate` challenge handler exists anywhere in the codebase to detect this. Rated Low because exploitation requires a trusted-root compromise, which is above the standard hostile-Wi-Fi capability.

**Why it is wrong:** The app transmits long-lived bearer credentials and an account OAuth token to fixed, known hosts; pinning those hosts' SPKI hashes is the standard defense-in-depth against CA-level interception.

**Remediation:** Add a `URLSessionDelegate` that evaluates the server trust and compares the leaf/intermediate SPKI hashes against pinned values for the three hosts, failing closed on mismatch, and provide an update path for rotation.

---

### [F-07] App Sandbox is not enabled

**Severity:** Informational

**Category:** 3. Sandbox, entitlements & hardened runtime

**Location:** `Remaindr/Remaindr.xcodeproj/project.pbxproj:182-201` (no `ENABLE_APP_SANDBOX`, no `CODE_SIGN_ENTITLEMENTS` in any configuration; confirmed: the only entitlement in the shipped binary is `get-task-allow`)

**Evidence:**

    184| isa = XCBuildConfiguration;
    185| buildSettings = {
    186|     CODE_SIGN_STYLE = Automatic;
    ...
    (no ENABLE_APP_SANDBOX, no CODE_SIGN_ENTITLEMENTS, no sandbox entitlements keys anywhere in the file)

**Attack path:** The app runs unsandboxed with full user-level file access. This is a deliberate design dependency, not an oversight: the Claude provider reads `~/.claude/projects/**/*.jsonl` (`ClaudeProvider.swift:22-26`) and reads the `Claude Code-credentials` Keychain item (`ClaudeAccountUsage.swift:20`), both of which are outside what a sandboxed app can reach without user grants. The practical risk is blast-radius: any future code-execution bug in the app executes with the user's full permissions. Recorded as Informational because the capability is required by the product's documented behavior, and the hardened runtime is enabled.

**Why it is wrong:** For defense in depth, sandboxing would contain compromise; here it is mutually exclusive with core features unless those features move behind user-selected folder access or a helper.

**Remediation:** If sandboxing is ever desired, enable `ENABLE_APP_SANDBOX` with `com.apple.security.files.user-selected.read-only` for the `~/.claude` directory and keep keychain access via the app's own items; otherwise document the unsandboxed posture explicitly in the README security section.

---

### [F-08] Reading Claude Code's foreign Keychain credential expands the blast radius, and the documented "Always Allow" guidance weakens the keychain ACL prompt

**Severity:** Informational

**Category:** 1. Secrets & credential storage / 10. Authentication & authorization logic

**Location:** `Remaindr/Remaindr/Keychain/KeychainStore.swift:71-85` (`foreignValue`), used by `Remaindr/Remaindr/Providers/ClaudeAccountUsage.swift:29-38`; guidance at `Remaindr/README.md:28-29`

**Evidence:**

    // KeychainStore.swift
    71| func foreignValue(service: String) throws -> String? {
    72|     let query: [String: Any] = [
    73|         kSecClass as String: kSecClassGenericPassword,
    74|         kSecAttrService as String: service,
    ...
    // Remaindr/README.md
    28| This project is ad-hoc signed, so its code signature changes on every rebuild.
    29| macOS may ask for permission to read the app's own Keychain items after a rebuild; choose Always Allow.

**Attack path:** The app reads another application's Keychain item (`Claude Code-credentials`, account-level OAuth token) and sends it to `api.anthropic.com`. Any compromise of the Remaindr process (see F-01, which enables exactly this without any prompt) therefore yields the Claude Code account token, not just this app's own data. Separately, because ad-hoc signatures change per rebuild, users are instructed to click "Always Allow" on keychain prompts, training them to grant future (possibly tampered, per F-02) binaries standing access to the credential.

**Why it is wrong:** The design is intentional per the project's own architecture notes and read-only, but it makes Remaindr a high-value target whose compromise equals Claude Code account compromise, and the Always-Allow habit erodes the one prompt that would otherwise gate a substituted binary.

**Remediation:** Once F-01/F-02 are fixed with a stable Developer ID signature, rebuild prompts disappear; keep the foreign read read-only and consider gating it behind an explicit Settings opt-in so users who do not use the Claude account source never expose the token to this process.

---

## Needs Manual Verification

- `[UNVERIFIED]` Whether published release artifacts (GitHub Releases referenced in `README.md:66`) match the local `build/` output. The audit made no network requests, so the actual distributed DMG could not be fetched and signature-checked.
- `[UNVERIFIED]` Whether the `Claude Code-credentials` Keychain item triggers an ACL prompt when Remaindr first reads it depends on how Claude Code created the item (trusted-application list), which is not observable from this repository.
- `[UNVERIFIED]` End-user permissions of the `~/.remaindr` preferences dotfile (`Remaindr/Remaindr/Models/ConfigFileStore.swift:20`) depend on each user's umask; the file does not exist on the audit machine. Its contents are non-secret (interval, provider name, probe flag), so at most it leaks the user's provider choices.

## Severity Count Table

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 4 |
| Informational | 2 |

## Clean / Not Applicable (by checklist category)

1. **Secrets & credential storage - clean apart from F-03/F-08.** No hardcoded keys in any tracked file (the only key-shaped strings in `docs/plans/2026-08-16-aiusagebar-menu-bar-app.md` are obvious placeholders such as `sk-ve****`/`sk-in****` probes). Secrets never touch `UserDefaults`, plists, or files (`KeychainStore.swift:8-9`, verified by grep: zero functional `UserDefaults` usage). No Keychain access groups are set. `strings` over the Release binary yields only endpoint URLs; no secret material.
2. **Transport security - clean apart from F-06.** No `NSAppTransportSecurity` keys anywhere (source or built Info.plists); no `URLSessionDelegate`/`serverTrust`/challenge handlers exist, so system default validation applies; all endpoints are `https://`; tokens travel in `Authorization`/`x-api-key` headers, never in URL query strings.
3. **Sandbox, entitlements & hardened runtime - findings F-01, F-02, F-07.** Hardened runtime is enabled (`project.pbxproj:167,188`). No `disable-library-validation`, `allow-unsigned-executable-memory`, `allow-dyld-environment-variables`, `allow-jit`, or Apple Events/automation entitlements.
4. **Process execution & command injection - not applicable for app code.** No `Process`, `NSTask`, `posix_spawn`, or `/bin/sh` usage in any Swift file. Script-side exposure is F-04.
5. **IPC, XPC & privileged helpers - not applicable.** No `NSXPCConnection`, `NSXPCListener`, `SMJobBless`, or `AuthorizationExecuteWithPrivileges` usage; no helper tools or XPC services are bundled.
6. **Untrusted input handling - clean apart from F-05.** No `NSKeyedUnarchiver`/`unarchiveObject`; only `JSONSerialization`/`JSONDecoder` with type-checked, clamped decoding; no custom URL scheme, no deep links, no `NSWorkspace.shared.open`; responses drive display values only, never privileged behavior; status codes and header values are parsed with `Double.init`/`TimeInterval.init` and clamped.
7. **WebView - not applicable.** No `WKWebView`, legacy `WebView`, `evaluateJavaScript`, or `loadHTMLString` anywhere.
8. **Local data at rest - clean apart from F-04.** No secrets written outside the Keychain; `~/.remaindr` holds non-secret preferences only; no temp-dir writes, no `NSPasteboard` usage, no logging of any kind in app sources (zero `print`, `NSLog`, `os_log`), no analytics or crash reporting.
9. **Cryptography - not applicable.** The app performs no cryptographic operations itself; no MD5/SHA1, no CommonCrypto, no ECB, no RNG usage, no hand-rolled crypto.
10. **Authentication & authorization logic - clean.** Keys are clearable (revocation) via Settings; expired/invalid credentials surface as `unauthorized` and stale values persist per the provider-failure rule (`ProviderStore.swift:78-88`); no client-side-only authorization gates, no `LAContext`.
11. **Update & distribution channel - no updater exists (not applicable for auto-update); distribution integrity is F-02.** No Sparkle, no `SUFeedURL`, no self-update code.
12. **Memory & language-level safety - clean apart from F-05.** No `Unsafe*Pointer`, `unsafeBitCast`, `withUnsafeBytes`, or C interop. The four force-unwraps of constant URL strings (`ClaudeProvider.swift:133`, `ClaudeAccountUsage.swift:46`, `ZAIProvider.swift:22`, `DeepSeekProvider.swift:13`) are compile-time constants, not attacker-reachable. Shared mutable state is `@MainActor`-confined under Swift 6 strict concurrency (`ProviderStore.swift:11-13`, `RefreshScheduler.swift:4`).
13. **Supply chain - clean.** Zero third-party dependencies (no `Package.swift`, no `Package.resolved`, empty frameworks phase), no CI workflows, no build-time network fetches, no `curl | sh` patterns; `make-dmg.sh` only invokes local `xcodebuild`/`hdiutil`/`osascript`; no secrets in CI or scripts.
14. **Local network listeners - not applicable.** The app opens no sockets and runs no local server.

## Top 5 Fix First

1. **F-01** - Configure a real Developer ID signing identity for Release so the shipped binary stops carrying `get-task-allow`; this closes the silent memory-dump credential-theft path (also prerequisite to F-02).
2. **F-02** - Add sign/notarize/staple steps to `make-dmg.sh` and remove the Gatekeeper-bypass instruction from the README.
3. **F-03** - Switch Keychain items to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` with a `.userPresence` `SecAccessControl`.
4. **F-04** - Replace the fixed `/tmp/dmg-applescript.txt` path with `mktemp` plus trap cleanup.
5. **F-05** - Cap per-file size in the session scan and use overflow-checked accumulation.

---

*Audit performed without modifying any file other than this report; `git status` was verified clean before the audit and shows only this new file after it.*
