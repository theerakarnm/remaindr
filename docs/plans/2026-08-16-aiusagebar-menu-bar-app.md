# AIUsageBar Implementation Plan

> **Run with:** `/execute-plan docs/plans/2026-08-16-aiusagebar-menu-bar-app.md` - the runner that ticks these
> checkboxes and honours the track layout below.
>
> **For the executing agent:** a single sequential track runs in place on the current branch.
> Steps use checkbox (`- [ ]`) syntax for tracking; tick them as you go.
> Run the `## Preflight` checks BEFORE task 1 and report anything down.

**Goal:** A macOS menu bar app that shows remaining usage/quota for Claude, z.ai (GLM), and DeepSeek at a glance, with per-provider detail in a dropdown.

**Architecture:** One SwiftUI `MenuBarExtra` scene with `.menuBarExtraStyle(.window)`, plus a `Settings` scene.
Every provider client conforms to `UsageProvider` (a `Sendable` protocol with one `async throws` method) and returns a common `ProviderStatus`; a `@MainActor @Observable ProviderStore` holds one independent `ProviderSlot` per provider so a failure in one never touches the others.
API keys are read from the Keychain at call time and are never held in `UserDefaults` or in the store.

**Tech Stack:** Swift 6 language mode, SwiftUI, Foundation, `URLSession` async/await, Security (Keychain), ServiceManagement (`SMAppService`). No third-party packages.

**Spec:** none - planned from the `/writing-plans` brief in this conversation.
The brief is reproduced verbatim where it constrains behaviour, in `## Global Constraints` and in each task.

**Base commit:** `7596ab0` (`agents: add agents.md and claude.md`).
The tree at that commit holds `AGENTS.md`, a one-line `CLAUDE.md` reading `@AGENTS.md`, and a root `README.md`.
It contains no Swift, no build system, and no `AIUsageBar/` directory.
`docs/plans/` is untracked at that commit and holds only this file.

**Assumptions:**
- z.ai auth header form (Task 5): two independent open-source clients disagree, so the client sends `Authorization: Bearer <key>` first and retries once with the bare token when the body reports `code: 1001`. Alternative not taken: pick one form and fail loudly. Unresolvable without a live GLM Coding Plan key.
- z.ai `unit` code semantics `3 = hours`, `5 = months`, `6 = weeks` (Task 5): read off a third-party mapper plus a captured live payload, not official docs. Alternative not taken: classify purely on `nextResetTime` distance.
- Claude in-block percentage denominator (Tasks 6-7): the largest historical 5-hour block, because no official "remaining subscription limit" number exists and the brief asks for ccusage-style blocks. Alternative not taken: show raw token counts with no percentage.

**Confidence:** 7/10 - the three assumption lines above are the whole gap; everything else in this plan was executed against the real toolchain, the real Claude session files, and live unauthenticated probes of all three provider endpoints.

**NOT building:**
- The Anthropic Admin usage endpoint fallback. The Rate Limits API docs state "The Admin API is unavailable for individual accounts", and the Admin API returns *configured* limits, not remaining headroom, so it cannot answer the question this app asks. The brief's third Claude source is dropped for that reason.
- An XCTest target. Verification uses `swiftc` harnesses on the pure-Foundation files instead, which is enough for every deterministic check this plan makes.
- z.ai `model-usage` and `tool-usage` endpoints. Only `quota/limit` is needed for the dropdown row.
- App Sandbox, notarization, an app icon asset catalog, and a Developer ID signing identity.
- Any git repository creation, CI config, or demo/example files.
- Any fourth provider, analytics, telemetry, onboarding flow, or update checker.

## Global Constraints

- Everything the app is made of lives under `AIUsageBar/`.
  The project root is `AIUsageBar/`, holding `AIUsageBar.xcodeproj` and the source folder `AIUsageBar/AIUsageBar/`.
  Two paths outside it are deliberate and are the only ones: this plan file under `docs/plans/`, and throwaway verification harnesses under `/tmp/aiub-verify/` which are never part of the app.
- Deployment target is `MACOSX_DEPLOYMENT_TARGET = 14.0`. Do not raise or lower it.
- `SWIFT_VERSION = 6.0` puts the target in **Swift 6 language mode**, and it is enforced.
  Verified: a bare `var globalCounter = 0` at file scope fails the build with `error: var 'globalCounter' is not concurrency-safe because it is nonisolated global shared mutable state`.
  Consequences that bite in this plan: no mutable global or static `var`; a `static let` of a non-`Sendable` class such as `ISO8601DateFormatter` is also an error, so use `Date.ISO8601FormatStyle` (a `Sendable` struct) instead.
- The build must finish with **zero warnings**. A task is not done until its build shows `warnings=0`.
- No third-party Swift packages. Stop and ask before adding one.
- API keys live in the macOS Keychain only. Never `UserDefaults`, never a plaintext file, never a log line, never a commit. Read them at call time and do not cache them in an observable object.
- No entitlement beyond outgoing network and Keychain access. This build requests neither explicitly (unsandboxed, hardened runtime on, ad-hoc signed); do not add an entitlements file.
- One provider failing must never blank or zero another. A failed refresh keeps the previous `ProviderStatus` and attaches an error; it never writes a zero.
- The collapsed menu bar label is **at most 14 characters**, always. This is a hard budget checked by a harness, not a guideline.
- Never use the em dash character in code, comments, commit messages, or the README. Use a plain `-`.
- In Markdown files, put each full sentence on its own line.
- Stage only the files a task names. Never `git add -A` or `git add .`: `CLAUDE.md` at the repo root is untracked and out of scope.

## Patterns to Mirror

The repository contains no Swift code, no build system, and no tests.
`ls` at the root returns `AGENTS.md`, `CLAUDE.md`, `README.md`, and `docs/`.
There is nothing to mirror, so every category below is a new convention this plan establishes.

### Naming

No existing pattern - establishing new convention: one type per file, file named for the type.
Providers are `<Vendor>Provider` (`DeepSeekProvider`, `ZAIProvider`, `ClaudeProvider`), each conforming to `UsageProvider`.
Error cases use full words, not abbreviations: `notConfigured`, `unauthorized`, `rateLimited`, `offline`, `malformedResponse`.

### Error handling

No existing pattern - establishing new convention: every provider throws `ProviderError`, a single enum defined once in `Models/ProviderStatus.swift`, and no provider defines its own error type.
Networking failures are classified at exactly one place per provider, in a `classify(status:body:)` step, so the five required visible states stay distinguishable.

### Tests

No existing pattern - establishing new convention: no XCTest target.
Deterministic checks compile the pure-Foundation files with `swiftc -swift-version 6` together with a throwaway `main.swift` harness under `/tmp/aiub-verify/`, then assert the harness's exact stdout.
A harness file must be named `main.swift`; Swift rejects top-level statements in any other filename with `error: expressions are not allowed at the top level`.

## Preflight

### DURABLE - true until the repo itself changes

- **Repository is empty of code.** Evidence: `ls` returns `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/`; `git log --oneline` shows two commits, neither adding source. Consequence: no baseline red exists, so every "zero warnings" Verify in this plan is falsifiable from Task 1 onward.
- **A hand-written `project.pbxproj` using `PBXFileSystemSynchronizedRootGroup` builds under this Xcode.** Evidence: the exact pbxproj in Task 1 was built in a scratch copy and printed `** BUILD SUCCEEDED **` with `warnings=0`. Consequence: **adding a new `.swift` file under the synchronized folder needs no pbxproj edit at all.** Verified by dropping a new file in mid-plan and rebuilding; it compiled without touching the project file. This is why the plan has no shared-file problem and no pbxproj task after Task 1.
- **Every Swift file in this plan was compiled together as a whole app before the plan shipped.** Evidence: all sixteen `swift` blocks below were extracted verbatim from this document into a scratch project carrying the Task 1 pbxproj, and `xcodebuild -configuration Release` printed `** BUILD SUCCEEDED **` with `warnings=0`. Consequence: the reference code is known to compile as a set, not just to read plausibly. Every harness Expected block below is pasted from an actual run of that same extracted code, not predicted.
- **Swift 6 language mode is on and enforced.** Evidence: probe file with a file-scope `var` failed with `error: var 'globalCounter' is not concurrency-safe`. Consequence: Global Constraints' concurrency rules are binding, not stylistic.
- **`Keychain`, `SMAppService`, `SettingsLink`, `@Observable`, and `MenuBarExtra(content:label:)` all compile clean at deployment target 14.0.** Evidence: a probe file exercising `SecItemAdd`/`SecItemCopyMatching`, `SMAppService.mainApp.register()`, `SettingsLink`, `@MainActor @Observable final class`, and a `MenuBarExtra { } label: { }` with an `HStack(Image, Text)` built with `warnings=0`. Consequence: none of these APIs needs an availability fallback.
- **A Keychain round trip works from an unsigned `swiftc` binary with no GUI prompt.** Evidence: harness printed `READBACK=sk-probe-123`, `MISSING=nil`, `AFTER_REMOVE=nil`. Consequence: Task 3's Verify is a real `Verify - Run`, not a Human check.
- **The Anthropic 401 response carries no `anthropic-ratelimit-*` headers.** Evidence: `curl -D- -X POST https://api.anthropic.com/v1/messages` with no key returned `HTTP/2 401` and a header set containing none of them. Consequence: Task 7's header fallback cannot be verified without a real key and a real billed request, so it is gated behind an explicit Human step.

### PERISHABLE - recapture before task 1

- **Xcode toolchain.** Check: `xcodebuild -version && swift --version | head -1 && xcrun --show-sdk-version --sdk macosx`. Recorded while planning: `Xcode 26.6 / Build 17F113`, `Apple Swift version 6.3.3`, macOS SDK `26.5`, host macOS `26.2`. Needed by: every task. If a different major Xcode is present, re-check Task 1's build before trusting the rest.
- **Code signing identities.** Check: `security find-identity -v -p codesigning`. Recorded: `0 valid identities found`, so the app is ad-hoc signed. Needed by: Task 3 and the end-to-end Keychain check. Consequence to expect: an ad-hoc signature changes on every rebuild, so macOS may prompt "AIUsageBar wants to access key ... in your keychain" after each rebuild. That prompt is normal here and is not a bug; click Always Allow.
- **DeepSeek endpoint reachable.** Check: `curl -s -m 15 -o /dev/null -w '%{http_code}\n' https://api.deepseek.com/user/balance`. Recorded: `401`, body `Authentication Fails (governor)` as **plain text, not JSON**. Needed by: Task 4. If it returns anything other than 401 with no key, stop and re-check the endpoint before writing the client.
- **z.ai endpoint reachable.** Check: `curl -s -m 15 -w '\nHTTP %{http_code}\n' -H 'Authorization: Bearer sk-invalid-probe' https://api.z.ai/api/monitor/usage/quota/limit`. Recorded: `HTTP 200` with body `{"code":401,"msg":"token expired or incorrect","success":false}`. With no header at all it returns `HTTP 200` and `{"code":1001,"msg":"Authentication parameter not received in Header, unable to authenticate","success":false}`. Needed by: Task 5. **z.ai signals auth failure inside a 200 body**, so HTTP status alone must not be trusted.
- **Claude session files present.** Check: `find ~/.claude/projects -name '*.jsonl' | wc -l`. Recorded: `1610` files, `28443` assistant records, of which `0` lacked `message.usage`, `0` lacked `timestamp`, `13` lacked `requestId`, and `18` carried `model: "<synthetic>"`. Needed by: Tasks 6 and 7. If the count is 0, Task 7's live check reports "Not configured" instead, which is a valid pass.
- **Provider API keys for the live checks.** Check: ask the user whether a DeepSeek key, a z.ai GLM Coding Plan key, and an Anthropic API key are available. Recorded while planning: not requested, none held. Needed by: the live Human checks in Tasks 4, 5, and 7, and two `## End-to-end verification` items. If absent, agree up front that those specific boxes stay unticked; every other box is reachable without a key.

## Execution

**Tracks:** single sequential track, Tasks 1-10, run in place on the current branch.

Tasks 4, 5, and 7 are logically independent providers, but each is a one-or-two file task, which is below this skill's cost floor for a worktree.
They run sequentially in the order the brief asked for: DeepSeek first because it is fully verifiable, then z.ai, then Claude last because it carries the fallback logic.

---

### Task 1: Xcode project skeleton that launches as a menu bar item

**Files:**
- Create: `AIUsageBar/AIUsageBar.xcodeproj/project.pbxproj`
- Create: `AIUsageBar/AIUsageBar.xcodeproj/xcshareddata/xcschemes/AIUsageBar.xcscheme`
- Create: `AIUsageBar/AIUsageBar/App/AIUsageBarApp.swift`
- Create: `AIUsageBar/README.md`
- Create: `AIUsageBar/.gitignore`

**Interfaces:**
- Produces: `struct AIUsageBarApp: App` at `AIUsageBar/AIUsageBar/App/AIUsageBarApp.swift`, the `@main` entry point. Tasks 9 and 10 replace its body.
- Produces: the source folder `AIUsageBar/AIUsageBar/` registered as a `PBXFileSystemSynchronizedRootGroup`. Every later task adds `.swift` files under it and **must not** edit `project.pbxproj`.

**Gotcha:** the object identifiers below are hand-assigned 24-character hex strings.
Xcode normally generates them, but any unique 24-hex-character value works and the ones given here are already proven to build.
Copy them exactly; a duplicate or short identifier makes `xcodebuild` reject the file.

**Steps:**

- [x] Step 1: Create `AIUsageBar/AIUsageBar/App/AIUsageBarApp.swift`.

      ```swift
      import SwiftUI

      @main
      struct AIUsageBarApp: App {
          var body: some Scene {
              MenuBarExtra {
                  Text("AIUsageBar")
                      .padding()
              } label: {
                  Image(systemName: "gauge.with.needle")
              }
              .menuBarExtraStyle(.window)
          }
      }
      ```

- [x] Step 2: Create `AIUsageBar/AIUsageBar.xcodeproj/project.pbxproj` with exactly this content.

      ```
      // !$*UTF8*$!
      {
      	archiveVersion = 1;
      	classes = {
      	};
      	objectVersion = 77;
      	objects = {

      /* Begin PBXFileSystemSynchronizedRootGroup section */
      		AA0000000000000000000010 /* AIUsageBar */ = {
      			isa = PBXFileSystemSynchronizedRootGroup;
      			path = AIUsageBar;
      			sourceTree = "<group>";
      		};
      /* End PBXFileSystemSynchronizedRootGroup section */

      /* Begin PBXFileReference section */
      		AA0000000000000000000020 /* AIUsageBar.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = AIUsageBar.app; sourceTree = BUILT_PRODUCTS_DIR; };
      /* End PBXFileReference section */

      /* Begin PBXFrameworksBuildPhase section */
      		AA0000000000000000000030 /* Frameworks */ = {
      			isa = PBXFrameworksBuildPhase;
      			buildActionMask = 2147483647;
      			files = (
      			);
      			runOnlyForDeploymentPostprocessing = 0;
      		};
      /* End PBXFrameworksBuildPhase section */

      /* Begin PBXGroup section */
      		AA0000000000000000000040 = {
      			isa = PBXGroup;
      			children = (
      				AA0000000000000000000010 /* AIUsageBar */,
      				AA0000000000000000000050 /* Products */,
      			);
      			sourceTree = "<group>";
      		};
      		AA0000000000000000000050 /* Products */ = {
      			isa = PBXGroup;
      			children = (
      				AA0000000000000000000020 /* AIUsageBar.app */,
      			);
      			name = Products;
      			sourceTree = "<group>";
      		};
      /* End PBXGroup section */

      /* Begin PBXNativeTarget section */
      		AA0000000000000000000060 /* AIUsageBar */ = {
      			isa = PBXNativeTarget;
      			buildConfigurationList = AA0000000000000000000070 /* Build configuration list for PBXNativeTarget "AIUsageBar" */;
      			buildPhases = (
      				AA0000000000000000000080 /* Sources */,
      				AA0000000000000000000030 /* Frameworks */,
      				AA0000000000000000000090 /* Resources */,
      			);
      			buildRules = (
      			);
      			dependencies = (
      			);
      			fileSystemSynchronizedGroups = (
      				AA0000000000000000000010 /* AIUsageBar */,
      			);
      			name = AIUsageBar;
      			productName = AIUsageBar;
      			productReference = AA0000000000000000000020 /* AIUsageBar.app */;
      			productType = "com.apple.product-type.application";
      		};
      /* End PBXNativeTarget section */

      /* Begin PBXProject section */
      		AA00000000000000000000A0 /* Project object */ = {
      			isa = PBXProject;
      			attributes = {
      				BuildIndependentTargetsInParallel = 1;
      				LastSwiftUpdateCheck = 2600;
      				LastUpgradeCheck = 2600;
      				TargetAttributes = {
      					AA0000000000000000000060 = {
      						CreatedOnToolsVersion = 26.0;
      					};
      				};
      			};
      			buildConfigurationList = AA00000000000000000000B0 /* Build configuration list for PBXProject "AIUsageBar" */;
      			developmentRegion = en;
      			hasScannedForEncodings = 0;
      			knownRegions = (
      				en,
      				Base,
      			);
      			mainGroup = AA0000000000000000000040;
      			minimizedProjectReferenceProxies = 1;
      			preferredProjectObjectVersion = 77;
      			productRefGroup = AA0000000000000000000050 /* Products */;
      			projectDirPath = "";
      			projectRoot = "";
      			targets = (
      				AA0000000000000000000060 /* AIUsageBar */,
      			);
      		};
      /* End PBXProject section */

      /* Begin PBXResourcesBuildPhase section */
      		AA0000000000000000000090 /* Resources */ = {
      			isa = PBXResourcesBuildPhase;
      			buildActionMask = 2147483647;
      			files = (
      			);
      			runOnlyForDeploymentPostprocessing = 0;
      		};
      /* End PBXResourcesBuildPhase section */

      /* Begin PBXSourcesBuildPhase section */
      		AA0000000000000000000080 /* Sources */ = {
      			isa = PBXSourcesBuildPhase;
      			buildActionMask = 2147483647;
      			files = (
      			);
      			runOnlyForDeploymentPostprocessing = 0;
      		};
      /* End PBXSourcesBuildPhase section */

      /* Begin XCBuildConfiguration section */
      		AA00000000000000000000C0 /* Debug */ = {
      			isa = XCBuildConfiguration;
      			buildSettings = {
      				ALWAYS_SEARCH_USER_PATHS = NO;
      				CLANG_ENABLE_OBJC_WEAK = YES;
      				COPY_PHASE_STRIP = NO;
      				DEBUG_INFORMATION_FORMAT = dwarf;
      				ENABLE_STRICT_OBJC_MSGSEND = YES;
      				ENABLE_TESTABILITY = YES;
      				GCC_OPTIMIZATION_LEVEL = 0;
      				MACOSX_DEPLOYMENT_TARGET = 14.0;
      				ONLY_ACTIVE_ARCH = YES;
      				SDKROOT = macosx;
      				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
      				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
      				SWIFT_VERSION = 6.0;
      			};
      			name = Debug;
      		};
      		AA00000000000000000000D0 /* Release */ = {
      			isa = XCBuildConfiguration;
      			buildSettings = {
      				ALWAYS_SEARCH_USER_PATHS = NO;
      				CLANG_ENABLE_OBJC_WEAK = YES;
      				COPY_PHASE_STRIP = NO;
      				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
      				ENABLE_NS_ASSERTIONS = NO;
      				ENABLE_STRICT_OBJC_MSGSEND = YES;
      				MACOSX_DEPLOYMENT_TARGET = 14.0;
      				SDKROOT = macosx;
      				SWIFT_COMPILATION_MODE = wholemodule;
      				SWIFT_VERSION = 6.0;
      			};
      			name = Release;
      		};
      		AA00000000000000000000E0 /* Debug */ = {
      			isa = XCBuildConfiguration;
      			buildSettings = {
      				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
      				CODE_SIGN_STYLE = Automatic;
      				COMBINE_HIDPI_IMAGES = YES;
      				CURRENT_PROJECT_VERSION = 1;
      				ENABLE_HARDENED_RUNTIME = YES;
      				GENERATE_INFOPLIST_FILE = YES;
      				INFOPLIST_KEY_LSUIElement = YES;
      				INFOPLIST_KEY_NSHumanReadableCopyright = "";
      				LD_RUNPATH_SEARCH_PATHS = (
      					"$(inherited)",
      					"@executable_path/../Frameworks",
      				);
      				MARKETING_VERSION = 1.0;
      				PRODUCT_BUNDLE_IDENTIFIER = com.theerakarn.AIUsageBar;
      				PRODUCT_NAME = "$(TARGET_NAME)";
      				SWIFT_EMIT_LOC_STRINGS = YES;
      			};
      			name = Debug;
      		};
      		AA00000000000000000000F0 /* Release */ = {
      			isa = XCBuildConfiguration;
      			buildSettings = {
      				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
      				CODE_SIGN_STYLE = Automatic;
      				COMBINE_HIDPI_IMAGES = YES;
      				CURRENT_PROJECT_VERSION = 1;
      				ENABLE_HARDENED_RUNTIME = YES;
      				GENERATE_INFOPLIST_FILE = YES;
      				INFOPLIST_KEY_LSUIElement = YES;
      				INFOPLIST_KEY_NSHumanReadableCopyright = "";
      				LD_RUNPATH_SEARCH_PATHS = (
      					"$(inherited)",
      					"@executable_path/../Frameworks",
      				);
      				MARKETING_VERSION = 1.0;
      				PRODUCT_BUNDLE_IDENTIFIER = com.theerakarn.AIUsageBar;
      				PRODUCT_NAME = "$(TARGET_NAME)";
      				SWIFT_EMIT_LOC_STRINGS = YES;
      			};
      			name = Release;
      		};
      /* End XCBuildConfiguration section */

      /* Begin XCConfigurationList section */
      		AA00000000000000000000B0 /* Build configuration list for PBXProject "AIUsageBar" */ = {
      			isa = XCConfigurationList;
      			buildConfigurations = (
      				AA00000000000000000000C0 /* Debug */,
      				AA00000000000000000000D0 /* Release */,
      			);
      			defaultConfigurationIsVisible = 0;
      			defaultConfigurationName = Release;
      		};
      		AA0000000000000000000070 /* Build configuration list for PBXNativeTarget "AIUsageBar" */ = {
      			isa = XCConfigurationList;
      			buildConfigurations = (
      				AA00000000000000000000E0 /* Debug */,
      				AA00000000000000000000F0 /* Release */,
      			);
      			defaultConfigurationIsVisible = 0;
      			defaultConfigurationName = Release;
      		};
      /* End XCConfigurationList section */
      	};
      	rootObject = AA00000000000000000000A0 /* Project object */;
      }
      ```

- [x] Step 3: Create `AIUsageBar/AIUsageBar.xcodeproj/xcshareddata/xcschemes/AIUsageBar.xcscheme`. A shared scheme is required; without it `xcodebuild -scheme AIUsageBar` cannot find one, because scheme auto-creation only happens when the project is opened in Xcode.

      ```xml
      <?xml version="1.0" encoding="UTF-8"?>
      <Scheme LastUpgradeVersion = "2600" version = "1.7">
         <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
            <BuildActionEntries>
               <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
                  <BuildableReference
                     BuildableIdentifier = "primary"
                     BlueprintIdentifier = "AA0000000000000000000060"
                     BuildableName = "AIUsageBar.app"
                     BlueprintName = "AIUsageBar"
                     ReferencedContainer = "container:AIUsageBar.xcodeproj">
                  </BuildableReference>
               </BuildActionEntry>
            </BuildActionEntries>
         </BuildAction>
         <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
            <Testables>
            </Testables>
         </TestAction>
         <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
            <BuildableProductRunnable runnableDebuggingMode = "0">
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "AA0000000000000000000060"
                  BuildableName = "AIUsageBar.app"
                  BlueprintName = "AIUsageBar"
                  ReferencedContainer = "container:AIUsageBar.xcodeproj">
               </BuildableReference>
            </BuildableProductRunnable>
         </LaunchAction>
         <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
            <BuildableProductRunnable runnableDebuggingMode = "0">
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "AA0000000000000000000060"
                  BuildableName = "AIUsageBar.app"
                  BlueprintName = "AIUsageBar"
                  ReferencedContainer = "container:AIUsageBar.xcodeproj">
               </BuildableReference>
            </BuildableProductRunnable>
         </ProfileAction>
         <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
         <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
      </Scheme>
      ```

- [x] Step 4: Create `AIUsageBar/README.md` as a short setup note only, one sentence per line. The outer fence below is four backticks because the file's own content contains a three-backtick block; write the file with the normal three-backtick form inside it.

      ````markdown
      # AIUsageBar

      A macOS menu bar utility showing remaining usage or quota for Claude, z.ai (GLM), and DeepSeek.

      ## Requirements

      macOS 14 or later, and Xcode 26 or later.

      ## Build and run

      ```bash
      cd AIUsageBar
      xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build
      open ./.build/Build/Products/Debug/AIUsageBar.app
      ```

      The app has no Dock icon; look for the gauge glyph in the menu bar.

      ## API keys

      Keys are entered in the app's Settings window and stored in the macOS Keychain under service `com.theerakarn.AIUsageBar`.
      They are never written to `UserDefaults` or to any file in this repository.
      Claude needs no key: it reads local session files under `~/.claude/projects/`.

      ## Note on rebuilds

      This project is ad-hoc signed, so its code signature changes on every rebuild.
      macOS may ask for permission to read the app's own Keychain items after a rebuild; choose Always Allow.
      ````

- [x] Step 5: Verify - Run: `cd AIUsageBar && xcodebuild -list -project AIUsageBar.xcodeproj` - Expected: output contains a `Schemes:` section listing `AIUsageBar`, and a `Targets:` section listing `AIUsageBar`.
- [x] Step 6: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [x] Step 7: Verify - Run: `/usr/libexec/PlistBuddy -c "Print :LSUIElement" AIUsageBar/.build/Build/Products/Debug/AIUsageBar.app/Contents/Info.plist && /usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" AIUsageBar/.build/Build/Products/Debug/AIUsageBar.app/Contents/Info.plist` - Expected: `true` then `14.0`.
- [x] Step 8: Create `AIUsageBar/.gitignore` containing the single line `.build/`, then Commit - `git add AIUsageBar/.gitignore AIUsageBar/README.md AIUsageBar/AIUsageBar.xcodeproj AIUsageBar/AIUsageBar && git commit -m "feat: add AIUsageBar Xcode project skeleton with menu bar scene"`

---

### Task 2: Shared status model and the UsageProvider protocol

**Files:**
- Create: `AIUsageBar/AIUsageBar/Models/ProviderStatus.swift`
- Create: `AIUsageBar/AIUsageBar/Providers/UsageProvider.swift`

**Interfaces:**
- Produces: `enum ProviderKind: String, CaseIterable, Sendable, Identifiable { case claude, zai, deepseek }`
- Produces: `enum ProviderError: Error, Equatable, Sendable { case notConfigured, unauthorized, rateLimited(retryAfter: TimeInterval?), offline, malformedResponse(String), serverError(status: Int), noActivePlan }`
- Produces: `enum ProviderReading: Equatable, Sendable { case fraction(used: Double, resetsAt: Date?), balance(amount: Decimal, currency: String) }`
- Produces: `struct ProviderStatus: Equatable, Sendable { let kind: ProviderKind; let reading: ProviderReading; let detail: String; let fetchedAt: Date }`
- Produces: `enum LabelSource: Equatable, Sendable, Hashable { case allConfigured; case provider(ProviderKind) }` with `var storageValue: String`, `init(storageValue: String)`, `var displayName: String`, `static var allCases: [LabelSource]`. It lives in the model file, not in Task 9's label file, so Task 8's `Preferences` compiles without a forward dependency.
- Produces: `protocol UsageProvider: Sendable { var kind: ProviderKind { get }; func fetch(now: Date) async throws -> ProviderStatus }`

**Gotcha:** `ProviderReading` must stay a two-case enum.
DeepSeek reports a currency balance, not a percentage, and the brief forbids normalising it into the same shape as the other two.
The UI branches on the case; it never converts a balance into a fraction.

**Steps:**

- [x] Step 1: Create `AIUsageBar/AIUsageBar/Models/ProviderStatus.swift`.

      ```swift
      import Foundation

      /// The three providers this app reports on. Adding a fourth means adding a case
      /// here and one `UsageProvider` conformance; no UI file changes.
      enum ProviderKind: String, CaseIterable, Sendable, Identifiable {
          case claude
          case zai
          case deepseek

          var id: String { rawValue }

          var displayName: String {
              switch self {
              case .claude: return "Claude"
              case .zai: return "z.ai (GLM)"
              case .deepseek: return "DeepSeek"
              }
          }

          /// Short form used inside the 14-character collapsed menu bar label.
          var shortName: String {
              switch self {
              case .claude: return "CL"
              case .zai: return "GLM"
              case .deepseek: return "DS"
              }
          }

          /// Keychain account name. Claude has no entry: it reads local session files.
          var keychainAccount: String? {
              switch self {
              case .claude: return "anthropic"
              case .zai: return "zai"
              case .deepseek: return "deepseek"
              }
          }
      }

      /// Every distinct failure the UI must be able to show differently.
      enum ProviderError: Error, Equatable, Sendable {
          case notConfigured
          case unauthorized
          case rateLimited(retryAfter: TimeInterval?)
          case offline
          case malformedResponse(String)
          case serverError(status: Int)
          case noActivePlan

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
              }
          }
      }

      /// The two shapes a provider can report. A balance is never converted into a
      /// fraction: DeepSeek sells credit, the other two meter a window.
      enum ProviderReading: Equatable, Sendable {
          case fraction(used: Double, resetsAt: Date?)
          case balance(amount: Decimal, currency: String)
      }

      /// One successful reading from one provider at one moment.
      struct ProviderStatus: Equatable, Sendable {
          let kind: ProviderKind
          let reading: ProviderReading
          /// Secondary line in the dropdown: a reset time, a plan name, or a currency note.
          let detail: String
          let fetchedAt: Date
      }

      /// What the collapsed menu bar label reports. `allConfigured` is the default because the
      /// brief's example label shows more than one provider at once.
      enum LabelSource: Equatable, Sendable, Hashable {
          case allConfigured
          case provider(ProviderKind)

          var storageValue: String {
              switch self {
              case .allConfigured: return "all"
              case .provider(let kind): return kind.rawValue
              }
          }

          /// Any unrecognised stored string falls back to `allConfigured`.
          init(storageValue: String) {
              if let kind = ProviderKind(rawValue: storageValue) {
                  self = .provider(kind)
              } else {
                  self = .allConfigured
              }
          }

          var displayName: String {
              switch self {
              case .allConfigured: return "All configured"
              case .provider(let kind): return kind.displayName
              }
          }

          static var allCases: [LabelSource] {
              [.allConfigured] + ProviderKind.allCases.map { .provider($0) }
          }
      }
      ```

- [x] Step 2: Create `AIUsageBar/AIUsageBar/Providers/UsageProvider.swift`.

      ```swift
      import Foundation

      /// The only surface the UI layer knows about. A provider is a value type with no
      /// stored credentials: it reads its key from the Keychain inside `fetch`, at call time.
      protocol UsageProvider: Sendable {
          var kind: ProviderKind { get }

          /// Returns a status or throws a `ProviderError`.
          /// `now` is injected so aggregation over local files is deterministic in a harness.
          func fetch(now: Date) async throws -> ProviderStatus
      }

      extension UsageProvider {
          /// Maps `URLSession` transport failures onto the one offline state the UI shows.
          /// Anything that is not a recognised connectivity failure is rethrown untouched.
          func mapTransportFailure(_ error: Error) -> Error {
              guard let urlError = error as? URLError else { return error }
              switch urlError.code {
              case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                   .cannotConnectToHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff,
                   .dataNotAllowed, .secureConnectionFailed:
                  return ProviderError.offline
              default:
                  return error
              }
          }
      }
      ```

- [x] Step 3: Verify - Run:

      ```bash
      mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/main.swift <<'EOF'
      import Foundation
      let s = ProviderStatus(kind: .deepseek, reading: .balance(amount: Decimal(string: "4.10")!, currency: "USD"), detail: "USD", fetchedAt: Date(timeIntervalSince1970: 0))
      print("kinds=\(ProviderKind.allCases.count) short=\(ProviderKind.claude.shortName) err=\(ProviderError.rateLimited(retryAfter: 30).shortDescription) reading=\(s.reading)")
      print("sources=\(LabelSource.allCases.map(\.storageValue).joined(separator: ",")) default=\(LabelSource(storageValue: "bogus").storageValue)")
      EOF
      swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Providers/UsageProvider.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/models && /tmp/aiub-verify/models
      ```

      Expected, exactly these two lines:

      ```
      kinds=3 short=CL err=Rate limited reading=balance(amount: 4.1, currency: "USD")
      sources=all,claude,zai,deepseek default=all
      ```
- [x] Step 4: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [x] Step 5: Commit - `git add AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Providers/UsageProvider.swift && git commit -m "feat: add ProviderStatus model and UsageProvider protocol"`

---

### Task 3: Keychain-only credential storage

**Files:**
- Create: `AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift`

**Interfaces:**
- Consumes: `enum ProviderKind` from Task 2, specifically `ProviderKind.keychainAccount -> String?`.
- Produces: `struct KeychainStore: Sendable` with `init(service: String = "com.theerakarn.AIUsageBar")`, `func set(_ value: String, for kind: ProviderKind) throws`, `func value(for kind: ProviderKind) throws -> String?`, `func remove(_ kind: ProviderKind) throws`, `func hasKey(for kind: ProviderKind) -> Bool`.
- Produces: `enum KeychainError: Error, Equatable { case unexpectedStatus(OSStatus) }`

**Gotcha:** `SecItemAdd` fails with `errSecDuplicateItem` when an item already exists, so `set` deletes first and then adds.
Use `kSecAttrAccessibleAfterFirstUnlock` so a background refresh works while the screen is locked.
Never log the value, and never include it in a thrown error.

**Rollback:** the Step 2 harness writes to the login keychain, which `git revert` cannot undo. It deletes its own item on the way out, but if it dies partway, clear the leftover with `security delete-generic-password -s com.theerakarn.AIUsageBar.verify -a deepseek 2>/dev/null; true`. It never touches the real `com.theerakarn.AIUsageBar` service.

**Steps:**

- [x] Step 1: Create `AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift`.

      ```swift
      import Foundation
      import Security

      enum KeychainError: Error, Equatable {
          case unexpectedStatus(OSStatus)
      }

      /// The only place an API key is ever read or written. Values never reach
      /// `UserDefaults`, a log, or a thrown error's message.
      struct KeychainStore: Sendable {
          let service: String

          init(service: String = "com.theerakarn.AIUsageBar") {
              self.service = service
          }

          private func query(_ account: String) -> [String: Any] {
              [
                  kSecClass as String: kSecClassGenericPassword,
                  kSecAttrService as String: service,
                  kSecAttrAccount as String: account,
              ]
          }

          func set(_ value: String, for kind: ProviderKind) throws {
              guard let account = kind.keychainAccount else { return }
              let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !trimmed.isEmpty else {
                  try remove(kind)
                  return
              }
              // SecItemAdd returns errSecDuplicateItem for an existing account, so replace.
              SecItemDelete(query(account) as CFDictionary)
              var attributes = query(account)
              attributes[kSecValueData as String] = Data(trimmed.utf8)
              attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
              let status = SecItemAdd(attributes as CFDictionary, nil)
              guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
          }

          func value(for kind: ProviderKind) throws -> String? {
              guard let account = kind.keychainAccount else { return nil }
              var attributes = query(account)
              attributes[kSecReturnData as String] = true
              attributes[kSecMatchLimit as String] = kSecMatchLimitOne
              var result: CFTypeRef?
              let status = SecItemCopyMatching(attributes as CFDictionary, &result)
              if status == errSecItemNotFound { return nil }
              guard status == errSecSuccess, let data = result as? Data else {
                  throw KeychainError.unexpectedStatus(status)
              }
              return String(data: data, encoding: .utf8)
          }

          func remove(_ kind: ProviderKind) throws {
              guard let account = kind.keychainAccount else { return }
              let status = SecItemDelete(query(account) as CFDictionary)
              guard status == errSecSuccess || status == errSecItemNotFound else {
                  throw KeychainError.unexpectedStatus(status)
              }
          }

          /// Cheap presence check for the Settings UI and for pausing the refresh timer.
          func hasKey(for kind: ProviderKind) -> Bool {
              ((try? value(for: kind)) ?? nil) != nil
          }
      }
      ```

- [x] Step 2: Verify - Run:

      ```bash
      mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/main.swift <<'EOF'
      import Foundation
      let store = KeychainStore(service: "com.theerakarn.AIUsageBar.verify")
      try store.set("sk-verify-123", for: .deepseek)
      print("READBACK=\(try store.value(for: .deepseek) ?? "nil")")
      print("ABSENT=\(try store.value(for: .zai) ?? "nil")")
      print("HAS=\(store.hasKey(for: .deepseek)) \(store.hasKey(for: .zai))")
      try store.set("   ", for: .deepseek)
      print("BLANK_CLEARS=\(try store.value(for: .deepseek) ?? "nil")")
      try store.remove(.deepseek)
      print("AFTER_REMOVE=\(try store.value(for: .deepseek) ?? "nil")")
      EOF
      swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/keychain && /tmp/aiub-verify/keychain
      ```

      Expected, exactly these five lines:

      ```
      READBACK=sk-verify-123
      ABSENT=nil
      HAS=true false
      BLANK_CLEARS=nil
      AFTER_REMOVE=nil
      ```

- [x] Step 3: Verify - Run: `defaults read com.theerakarn.AIUsageBar 2>&1 | grep -ci 'sk-verify-123' || true` - Expected: `0`, proving the value never reached `UserDefaults`. A `Domain ... does not exist` message on stderr is also a pass.
- [x] Step 4: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [x] Step 5: Commit - `git add AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift && git commit -m "feat: add Keychain-only credential store"`

---

### Task 4: DeepSeek balance provider

**Files:**
- Create: `AIUsageBar/AIUsageBar/Providers/DeepSeekProvider.swift`

**Interfaces:**
- Consumes: `protocol UsageProvider`, `ProviderStatus`, `ProviderReading`, `ProviderError`, `ProviderKind`, and `KeychainStore.value(for:) throws -> String?`.
- Produces: `struct DeepSeekProvider: UsageProvider` with `init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared)` and `static func parse(_ data: Data, now: Date) throws -> ProviderStatus`.

**Gotcha:** three verified facts about this endpoint.
The balance fields are **JSON strings**, not numbers: `"total_balance": "110.00"`.
Decode them into `String` and convert with `Decimal(string:)`; decoding into `Double` fails outright.
The 401 body is **plain text** (`Authentication Fails (governor)`), not JSON, so classify on the HTTP status before attempting to decode.
`balance_infos` can hold more than one currency; take the first entry and put its currency in `detail`.

**Steps:**

- [x] Step 1: Create `AIUsageBar/AIUsageBar/Providers/DeepSeekProvider.swift`.

      ```swift
      import Foundation

      /// GET https://api.deepseek.com/user/balance with `Authorization: Bearer <key>`.
      /// Documented response:
      ///   {"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"110.00",
      ///     "granted_balance":"10.00","topped_up_balance":"100.00"}]}
      /// Reports remaining balance, never a usage percentage.
      struct DeepSeekProvider: UsageProvider {
          let kind: ProviderKind = .deepseek

          private let keychain: KeychainStore
          private let session: URLSession
          private static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

          init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared) {
              self.keychain = keychain
              self.session = session
          }

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

          func fetch(now: Date) async throws -> ProviderStatus {
              guard let key = try keychain.value(for: kind), !key.isEmpty else {
                  throw ProviderError.notConfigured
              }

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

          /// Pure so a harness can exercise it without a key or a network.
          static func parse(_ data: Data, now: Date) throws -> ProviderStatus {
              let payload: Payload
              do {
                  payload = try JSONDecoder().decode(Payload.self, from: data)
              } catch {
                  throw ProviderError.malformedResponse("balance payload not decodable")
              }
              guard let info = payload.balance_infos.first else {
                  throw ProviderError.malformedResponse("balance_infos empty")
              }
              guard let amount = Decimal(string: info.total_balance) else {
                  throw ProviderError.malformedResponse("total_balance not numeric")
              }
              return ProviderStatus(
                  kind: .deepseek,
                  reading: .balance(amount: amount, currency: info.currency),
                  detail: "Remaining balance in \(info.currency)",
                  fetchedAt: now
              )
          }
      }
      ```

- [x] Step 2: Verify - Run:

      ```bash
      mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/main.swift <<'EOF'
      import Foundation
      let now = Date(timeIntervalSince1970: 0)
      let good = #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"4.10","granted_balance":"0.00","topped_up_balance":"4.10"}]}"#
      let status = try DeepSeekProvider.parse(Data(good.utf8), now: now)
      print("OK reading=\(status.reading) detail=\(status.detail)")
      for (name, body) in [("empty", #"{"balance_infos":[]}"#), ("garbage", "not json"), ("nonnumeric", #"{"balance_infos":[{"currency":"USD","total_balance":"abc"}]}"#)] {
          do { _ = try DeepSeekProvider.parse(Data(body.utf8), now: now); print("\(name)=NO_THROW") }
          catch let error as ProviderError { print("\(name)=\(error.shortDescription)") }
      }
      EOF
      swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Providers/UsageProvider.swift AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift AIUsageBar/AIUsageBar/Providers/DeepSeekProvider.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/deepseek && /tmp/aiub-verify/deepseek
      ```

      Expected, exactly these four lines:

      ```
      OK reading=balance(amount: 4.1, currency: "USD") detail=Remaining balance in USD
      empty=Bad response
      garbage=Bad response
      nonnumeric=Bad response
      ```

- [x] Step 3: Verify - Manual: `curl -s -m 15 -o /dev/null -w '%{http_code}\n' https://api.deepseek.com/user/balance` - Expected: `401`, confirming the endpoint is live and that the unauthorized branch is reachable. This call carries no key and consumes no credits.
- [x] Step 4: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [ ] 👤 Step 5: Verify - Human: with a real DeepSeek key in Settings, click Refresh and read the DeepSeek row - Expected: the row shows the same figure as the DeepSeek console's balance page, in the same currency - Proxy: Step 2 asserts the exact `total_balance` to `Decimal` mapping off a fixture with the documented shape, and Step 3 proves the live endpoint and its 401 branch. **This is the only reason a real key is needed; `/user/balance` is not billed, but it does require the user's own credential, which no agent may supply.**
      > Awaiting human: no DeepSeek API key was supplied during this run. Paste one into Settings > API keys > DeepSeek, click Refresh, and compare the row's figure to the DeepSeek console's balance page.
- [x] Step 6: Commit - `git add AIUsageBar/AIUsageBar/Providers/DeepSeekProvider.swift && git commit -m "feat: add DeepSeek balance provider"`

---

### Task 5: z.ai (GLM) quota provider

**Files:**
- Create: `AIUsageBar/AIUsageBar/Providers/ZAIProvider.swift`

**Interfaces:**
- Consumes: `protocol UsageProvider`, `ProviderStatus`, `ProviderReading`, `ProviderError`, `ProviderKind`, and `KeychainStore.value(for:) throws -> String?`.
- Produces: `struct ZAIProvider: UsageProvider` with `init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared)` and `static func parse(_ data: Data, now: Date) throws -> ProviderStatus`.

**Gotcha:** the single most important fact about this endpoint, verified live.
**z.ai answers auth failures with HTTP 200.**
A missing header returns `200` and `{"code":1001,"msg":"Authentication parameter not received in Header, unable to authenticate","success":false}`; a bad token returns `200` and `{"code":401,"msg":"token expired or incorrect","success":false}`.
Classification therefore reads `success` and `code` from the body, and the HTTP status is only a secondary signal.
The endpoint is undocumented; the response shape below comes from a captured live payload, so treat any unrecognised entry as ignorable rather than fatal.

**Steps:**

- [ ] Step 1: Create `AIUsageBar/AIUsageBar/Providers/ZAIProvider.swift`.

      ```swift
      import Foundation

      /// GET https://api.z.ai/api/monitor/usage/quota/limit
      ///
      /// This endpoint is not in z.ai's public API reference. The shape below is taken from a
      /// captured live GLM Coding Plan response:
      ///   {"code":200,"msg":"Operation successful","data":{"limits":[
      ///     {"type":"CREDIT_LIMIT","unit":3,"number":5,"percentage":0},
      ///     {"type":"CREDIT_LIMIT","unit":6,"number":1,"percentage":98,"nextResetTime":1786685679998}
      ///   ],"level":"lite"},"success":true}
      ///
      /// `unit` encodes the window: 3 = hours, 4 = days, 5 = months, 6 = weeks, multiplied by
      /// `number`. A sub-daily window is the rolling 5-hour session meter, which is the one
      /// this app shows. `TOKENS_LIMIT` is the older name for `CREDIT_LIMIT`; both are accepted.
      struct ZAIProvider: UsageProvider {
          let kind: ProviderKind = .zai

          private let keychain: KeychainStore
          private let session: URLSession
          private static let endpoint = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

          init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared) {
              self.keychain = keychain
              self.session = session
          }

          func fetch(now: Date) async throws -> ProviderStatus {
              guard let key = try keychain.value(for: kind), !key.isEmpty else {
                  throw ProviderError.notConfigured
              }

              // Two open-source clients disagree on the header form, so try the standard
              // Bearer shape first and fall back to the bare token only when z.ai says the
              // auth parameter was not received (code 1001).
              var data = try await send(key: key, bearer: true)
              if Self.bodyCode(data) == 1001 {
                  data = try await send(key: key, bearer: false)
              }
              return try Self.parse(data, now: now)
          }

          private func send(key: String, bearer: Bool) async throws -> Data {
              var request = URLRequest(url: Self.endpoint)
              request.httpMethod = "GET"
              request.timeoutInterval = 15
              request.setValue(bearer ? "Bearer \(key)" : key, forHTTPHeaderField: "Authorization")
              request.setValue("application/json", forHTTPHeaderField: "Accept")
              request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

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
              // z.ai returns 200 for auth failures, so a non-2xx here is a genuine transport
              // or server fault; the body-level classification happens in `parse`.
              guard (200..<300).contains(http.statusCode) else {
                  switch http.statusCode {
                  case 401, 403: throw ProviderError.unauthorized
                  case 429:
                      let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
                      throw ProviderError.rateLimited(retryAfter: retryAfter)
                  default: throw ProviderError.serverError(status: http.statusCode)
                  }
              }
              return data
          }

          private static func bodyCode(_ data: Data) -> Int? {
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
              return root?["code"] as? Int
          }

          /// Pure so a harness can exercise every branch without a key or a network.
          static func parse(_ data: Data, now: Date) throws -> ProviderStatus {
              guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                  throw ProviderError.malformedResponse("quota payload not JSON")
              }

              if (root["success"] as? Bool) == false {
                  let message = (root["msg"] as? String ?? "").lowercased()
                  let code = root["code"] as? Int
                  if code == 401 || code == 1001 || code == 403 { throw ProviderError.unauthorized }
                  if code == 429 { throw ProviderError.rateLimited(retryAfter: nil) }
                  // A valid key with no GLM Coding Plan answers success:false and says so.
                  if message.contains("coding plan") { throw ProviderError.noActivePlan }
                  throw ProviderError.serverError(status: code ?? -1)
              }

              // The limits array normally lives under `data`; tolerate it at the root too.
              let container = (root["data"] as? [String: Any]) ?? root
              guard let limits = container["limits"] as? [[String: Any]] else {
                  throw ProviderError.malformedResponse("no limits array")
              }

              // The rolling session meter is the percentage entry with a sub-daily window.
              let session = limits.first { entry in
                  let type = (entry["type"] as? String) ?? ""
                  guard type == "CREDIT_LIMIT" || type == "TOKENS_LIMIT" else { return false }
                  guard let windowMs = windowMilliseconds(entry) else { return false }
                  return windowMs < 24 * 60 * 60 * 1000
              }
              guard let session, let percentage = session["percentage"] as? Double ?? (session["percentage"] as? Int).map(Double.init) else {
                  throw ProviderError.malformedResponse("no session percentage")
              }

              let resetsAt = (session["nextResetTime"] as? Double ?? (session["nextResetTime"] as? Int).map(Double.init))
                  .map { Date(timeIntervalSince1970: $0 / 1000) }
              let plan = (container["level"] as? String)?.capitalized

              var detail = "5-hour window"
              if let plan { detail = "\(plan) plan, 5-hour window" }

              return ProviderStatus(
                  kind: .zai,
                  reading: .fraction(used: min(max(percentage / 100, 0), 1), resetsAt: resetsAt),
                  detail: detail,
                  fetchedAt: now
              )
          }

          /// `(unit, number)` to a window length in milliseconds. Unknown units return nil so a
          /// future z.ai window cannot hide the meters this app already understands.
          private static func windowMilliseconds(_ entry: [String: Any]) -> Double? {
              let unit = (entry["unit"] as? Double) ?? (entry["unit"] as? Int).map(Double.init)
              let number = (entry["number"] as? Double) ?? (entry["number"] as? Int).map(Double.init)
              guard let unit, let number, number > 0 else { return nil }
              let unitMs: Double
              switch Int(unit) {
              case 3: unitMs = 60 * 60 * 1000
              case 4: unitMs = 24 * 60 * 60 * 1000
              case 5: unitMs = 30 * 24 * 60 * 60 * 1000
              case 6: unitMs = 7 * 24 * 60 * 60 * 1000
              default: return nil
              }
              return unitMs * number
          }
      }
      ```

- [ ] Step 2: Verify - Run:

      ```bash
      mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/main.swift <<'EOF'
      import Foundation
      let now = Date(timeIntervalSince1970: 0)
      let live = #"{"code":200,"msg":"Operation successful","data":{"limits":[{"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,"currentValue":620,"remaining":1380,"percentage":31},{"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,"currentValue":9855,"remaining":145,"percentage":98,"nextResetTime":1786685679998}],"level":"lite"},"success":true}"#
      let status = try ZAIProvider.parse(Data(live.utf8), now: now)
      print("OK reading=\(status.reading) detail=\(status.detail)")
      let cases: [(String, String)] = [
        ("badtoken", #"{"code":401,"msg":"token expired or incorrect","success":false}"#),
        ("noheader", #"{"code":1001,"msg":"Authentication parameter not received in Header, unable to authenticate","success":false}"#),
        ("noplan", #"{"code":500,"msg":"user has no coding plan","success":false}"#),
        ("garbage", "not json"),
        ("nolimits", #"{"code":200,"success":true,"data":{}}"#),
      ]
      for (name, body) in cases {
          do { _ = try ZAIProvider.parse(Data(body.utf8), now: now); print("\(name)=NO_THROW") }
          catch let error as ProviderError { print("\(name)=\(error.shortDescription)") }
      }
      EOF
      swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Providers/UsageProvider.swift AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift AIUsageBar/AIUsageBar/Providers/ZAIProvider.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/zai && /tmp/aiub-verify/zai
      ```

      Expected, exactly these six lines. The first asserts that the **5-hour** entry is selected and the weekly one at 98 percent is ignored:

      ```
      OK reading=fraction(used: 0.31, resetsAt: nil) detail=Lite plan, 5-hour window
      badtoken=Key rejected
      noheader=Key rejected
      noplan=No active plan
      garbage=Bad response
      nolimits=Bad response
      ```

- [ ] Step 3: Verify - Manual: `curl -s -m 15 -w '\nHTTP %{http_code}\n' -H 'Authorization: Bearer sk-invalid-probe' https://api.z.ai/api/monitor/usage/quota/limit` - Expected: body `{"code":401,"msg":"token expired or incorrect","success":false}` then `HTTP 200`, confirming the endpoint is live and that auth failure really does arrive inside a 200. This call carries no real key and consumes nothing.
- [ ] Step 4: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [ ] Step 5: 👤 Verify - Human: with a real z.ai GLM Coding Plan key in Settings, click Refresh and compare the z.ai row against the usage figure on the z.ai subscription page - Expected: the two percentages agree, and the header-form fallback did not fire (the row is not "Key rejected") - Proxy: Step 2 asserts the exact window-selection and every error branch off the captured live payload, and Step 3 proves the live endpoint's 200-with-`success:false` behaviour.
- [ ] Step 6: Commit - `git add AIUsageBar/AIUsageBar/Providers/ZAIProvider.swift && git commit -m "feat: add z.ai GLM quota provider"`

---

### Task 6: Claude rolling 5-hour block aggregation

**Files:**
- Create: `AIUsageBar/AIUsageBar/Providers/ClaudeSessionBlocks.swift`

**Interfaces:**
- Produces: `struct ClaudeUsageEntry: Sendable, Equatable` with `timestamp: Date`, `dedupeKey: String?`, `inputTokens: Int`, `cacheCreationTokens: Int`, `cacheReadTokens: Int`, `outputTokens: Int`, and `var totalTokens: Int`.
- Produces: `struct ClaudeUsageBlock: Sendable, Equatable` with `startedAt: Date`, `endsAt: Date`, `totalTokens: Int`.
- Produces: `enum ClaudeSessionBlocks` with `static let blockDuration: TimeInterval`, `static func entry(fromLine line: String) -> ClaudeUsageEntry?`, `static func blocks(from entries: [ClaudeUsageEntry]) -> [ClaudeUsageBlock]`, `static func activeBlock(in blocks: [ClaudeUsageBlock], now: Date) -> ClaudeUsageBlock?`, `static func parseTimestamp(_ value: String) -> Date?`.

**Gotcha:** two facts verified against the real session files, and one Swift 6 trap.
Across 1610 files and 28443 assistant records, every record had `message.usage` and `timestamp`, 13 had no `requestId`, and 18 carried `model: "<synthetic>"`; synthetic records must be excluded and a record with no `requestId` must still count rather than being dropped.
The Swift 6 trap: a `static let` of `ISO8601DateFormatter` fails to compile with `error: static property 'iso8601' is not concurrency-safe because non-'Sendable' type 'ISO8601DateFormatter' may have shared mutable state`.
Use `Date.ISO8601FormatStyle`, which is a `Sendable` struct.

**Steps:**

- [ ] Step 1: Create `AIUsageBar/AIUsageBar/Providers/ClaudeSessionBlocks.swift`.

      ```swift
      import Foundation

      /// One assistant turn read out of a Claude Code session `.jsonl` file.
      struct ClaudeUsageEntry: Sendable, Equatable {
          let timestamp: Date
          let dedupeKey: String?
          let inputTokens: Int
          let cacheCreationTokens: Int
          let cacheReadTokens: Int
          let outputTokens: Int

          var totalTokens: Int {
              inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens
          }
      }

      /// A rolling 5-hour usage block, ccusage-style.
      struct ClaudeUsageBlock: Sendable, Equatable {
          let startedAt: Date
          let endsAt: Date
          let totalTokens: Int
      }

      /// Pure aggregation over Claude Code session files. No I/O lives here, so a harness can
      /// drive it with a fixture and a fixed `now`.
      enum ClaudeSessionBlocks {
          static let blockDuration: TimeInterval = 5 * 60 * 60

          /// Decodes one JSONL line. Returns nil for every line that is not a usable assistant
          /// turn: malformed JSON, a non-assistant record, or a synthetic model.
          static func entry(fromLine line: String) -> ClaudeUsageEntry? {
              guard let data = line.data(using: .utf8),
                    let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                    root["type"] as? String == "assistant",
                    let message = root["message"] as? [String: Any],
                    (message["model"] as? String) != "<synthetic>",
                    let usage = message["usage"] as? [String: Any],
                    let stamp = root["timestamp"] as? String,
                    let timestamp = parseTimestamp(stamp)
              else { return nil }

              // 13 of 28443 real records carry no requestId. Those still count; they just
              // cannot be deduplicated, which is the safe direction.
              let messageID = message["id"] as? String
              let requestID = root["requestId"] as? String
              let dedupeKey = messageID.flatMap { id in requestID.map { "\(id):\($0)" } }

              return ClaudeUsageEntry(
                  timestamp: timestamp,
                  dedupeKey: dedupeKey,
                  inputTokens: usage["input_tokens"] as? Int ?? 0,
                  cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                  cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                  outputTokens: usage["output_tokens"] as? Int ?? 0
              )
          }

          /// Groups entries into rolling 5-hour blocks. A block starts at the UTC hour floor of
          /// its first entry and closes when an entry is 5h past the block start or 5h past the
          /// previous entry.
          static func blocks(from entries: [ClaudeUsageEntry]) -> [ClaudeUsageBlock] {
              var seen = Set<String>()
              let ordered = entries
                  .filter { entry in
                      guard let key = entry.dedupeKey else { return true }
                      return seen.insert(key).inserted
                  }
                  .sorted { $0.timestamp < $1.timestamp }

              var result: [ClaudeUsageBlock] = []
              var start: Date?
              var previous: Date?
              var total = 0

              for entry in ordered {
                  if let blockStart = start, let last = previous,
                     entry.timestamp.timeIntervalSince(blockStart) < blockDuration,
                     entry.timestamp.timeIntervalSince(last) < blockDuration {
                      total += entry.totalTokens
                      previous = entry.timestamp
                      continue
                  }
                  if let blockStart = start {
                      result.append(ClaudeUsageBlock(startedAt: blockStart,
                                                     endsAt: blockStart.addingTimeInterval(blockDuration),
                                                     totalTokens: total))
                  }
                  start = hourFloor(entry.timestamp)
                  previous = entry.timestamp
                  total = entry.totalTokens
              }
              if let blockStart = start {
                  result.append(ClaudeUsageBlock(startedAt: blockStart,
                                                 endsAt: blockStart.addingTimeInterval(blockDuration),
                                                 totalTokens: total))
              }
              return result
          }

          /// The block containing `now`, if any.
          static func activeBlock(in blocks: [ClaudeUsageBlock], now: Date) -> ClaudeUsageBlock? {
              blocks.first { $0.startedAt <= now && now < $0.endsAt }
          }

          /// `Date.ISO8601FormatStyle` is a Sendable struct; an `ISO8601DateFormatter` static is
          /// a Swift 6 error. Session files carry fractional seconds, but fall back to the plain
          /// form rather than dropping a turn.
          private static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
          private static let iso8601NoFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

          static func parseTimestamp(_ value: String) -> Date? {
              (try? iso8601.parse(value)) ?? (try? iso8601NoFraction.parse(value))
          }

          private static func hourFloor(_ date: Date) -> Date {
              Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
          }
      }
      ```

- [ ] Step 2: Verify - Run:

      ```bash
      mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/fixture.jsonl <<'EOF'
      {"type":"assistant","timestamp":"2026-01-15T09:12:00.000Z","requestId":"req_1","message":{"id":"msg_a","model":"claude-opus-5","usage":{"input_tokens":100,"cache_creation_input_tokens":200,"cache_read_input_tokens":1000,"output_tokens":50}}}
      {"type":"assistant","timestamp":"2026-01-15T10:30:00.000Z","requestId":"req_2","message":{"id":"msg_b","model":"claude-sonnet-5","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":500,"output_tokens":5}}}
      {"type":"assistant","timestamp":"2026-01-15T10:30:00.000Z","requestId":"req_2","message":{"id":"msg_b","model":"claude-sonnet-5","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":500,"output_tokens":5}}}
      {"type":"user","timestamp":"2026-01-15T10:31:00.000Z","message":{"role":"user","content":"hi"}}
      {"type":"assistant","timestamp":"2026-01-15T11:00:00.000Z","requestId":"req_s","message":{"id":"msg_s","model":"<synthetic>","usage":{"input_tokens":9999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":9999}}}
      {not json
      {"type":"assistant","timestamp":"2026-01-15T16:00:00.000Z","requestId":"req_3","message":{"id":"msg_c","model":"claude-opus-5","usage":{"input_tokens":500,"cache_creation_input_tokens":200,"cache_read_input_tokens":200,"output_tokens":32}}}
      EOF
      cat > /tmp/aiub-verify/main.swift <<'EOF'
      import Foundation
      let style = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
      let now = try style.parse("2026-01-15T17:00:00Z")
      let text = try String(contentsOfFile: "/tmp/aiub-verify/fixture.jsonl", encoding: .utf8)
      let entries = text.split(separator: "\n").compactMap { ClaudeSessionBlocks.entry(fromLine: String($0)) }
      let blocks = ClaudeSessionBlocks.blocks(from: entries)
      let active = ClaudeSessionBlocks.activeBlock(in: blocks, now: now)
      let peak = blocks.map(\.totalTokens).max() ?? 0
      let percent = peak > 0 ? Int((Double(active?.totalTokens ?? 0) / Double(peak) * 100).rounded()) : 0
      print("entries=\(entries.count) blocks=\(blocks.count)")
      for b in blocks { print("block start=\(style.format(b.startedAt)) end=\(style.format(b.endsAt)) tokens=\(b.totalTokens)") }
      print("ACTIVE tokens=\(active?.totalTokens ?? 0) peak=\(peak) percent=\(percent) resetsAt=\(active.map { style.format($0.endsAt) } ?? "-")")
      EOF
      swiftc -swift-version 6 AIUsageBar/AIUsageBar/Providers/ClaudeSessionBlocks.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/blocks && /tmp/aiub-verify/blocks
      ```

      Expected, exactly these four lines. `entries=4` proves the synthetic record, the user record, and the malformed line were all skipped; `blocks=2` proves the duplicate `msg_b:req_2` was collapsed:

      ```
      entries=4 blocks=2
      block start=2026-01-15T09:00:00Z end=2026-01-15T14:00:00Z tokens=1865
      block start=2026-01-15T16:00:00Z end=2026-01-15T21:00:00Z tokens=932
      ACTIVE tokens=932 peak=1865 percent=50 resetsAt=2026-01-15T21:00:00Z
      ```

- [ ] Step 3: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [ ] Step 4: Commit - `git add AIUsageBar/AIUsageBar/Providers/ClaudeSessionBlocks.swift && git commit -m "feat: add Claude rolling 5-hour block aggregation"`

---

### Task 7: Claude provider with local-session primary and rate-limit-header fallback

**Files:**
- Create: `AIUsageBar/AIUsageBar/Providers/ClaudeProvider.swift`

**Interfaces:**
- Consumes: `ClaudeSessionBlocks.entry(fromLine:)`, `ClaudeSessionBlocks.blocks(from:)`, `ClaudeSessionBlocks.activeBlock(in:now:)`, `ClaudeUsageBlock`, `protocol UsageProvider`, `ProviderStatus`, `ProviderReading`, `ProviderError`, `KeychainStore.value(for:) throws -> String?`.
- Produces: `struct ClaudeProvider: UsageProvider` with `init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared, projectsDirectory: URL = ClaudeProvider.defaultProjectsDirectory)`, `static var defaultProjectsDirectory: URL`, `static func status(from blocks: [ClaudeUsageBlock], now: Date) -> ProviderStatus?`, `static func statusFromHeaders(_ http: HTTPURLResponse, now: Date) -> ProviderStatus?`.

**Gotcha:** three constraints.
The denominator for the in-block percentage is the largest historical block, because no official remaining-limit number exists; the dropdown's secondary line must say so in words, so the number is never mistaken for an official quota.
Reading 1610 files takes real time, so the scan runs off the main actor and streams each file rather than loading all of them into memory at once.
The header fallback needs a **billed** `POST /v1/messages` call; a 401 response carries no `anthropic-ratelimit-*` headers at all, verified live. Gate it behind an explicit user opt-in, never fire it automatically.

**Steps:**

- [ ] Step 1: Create `AIUsageBar/AIUsageBar/Providers/ClaudeProvider.swift`.

      ```swift
      import Foundation

      /// Claude has no public "remaining subscription limit" endpoint, so this provider has two
      /// sources, in order:
      ///  1. local session files under `~/.claude/projects/**/*.jsonl`, aggregated into rolling
      ///     5-hour blocks;
      ///  2. `anthropic-ratelimit-*` response headers, but only when the user has explicitly
      ///     opted into a billed probe request, because the headers exist only on a successful
      ///     Messages API call.
      /// When neither is available it throws `.notConfigured`. It never invents a number.
      struct ClaudeProvider: UsageProvider {
          let kind: ProviderKind = .claude

          private let keychain: KeychainStore
          private let session: URLSession
          private let projectsDirectory: URL
          /// Off unless the user turns it on in Settings. A probe request is billed.
          private let allowBilledProbe: Bool

          static var defaultProjectsDirectory: URL {
              FileManager.default.homeDirectoryForCurrentUser
                  .appendingPathComponent(".claude", isDirectory: true)
                  .appendingPathComponent("projects", isDirectory: true)
          }

          init(keychain: KeychainStore = KeychainStore(),
               session: URLSession = .shared,
               projectsDirectory: URL = ClaudeProvider.defaultProjectsDirectory,
               allowBilledProbe: Bool = false) {
              self.keychain = keychain
              self.session = session
              self.projectsDirectory = projectsDirectory
              self.allowBilledProbe = allowBilledProbe
          }

          func fetch(now: Date) async throws -> ProviderStatus {
              let directory = projectsDirectory
              // The scan touches ~1600 files, so keep it off the main actor.
              let blocks = await Task.detached(priority: .utility) {
                  Self.scanBlocks(in: directory)
              }.value

              if let status = Self.status(from: blocks, now: now) {
                  return status
              }

              guard allowBilledProbe, let key = try keychain.value(for: kind), !key.isEmpty else {
                  throw ProviderError.notConfigured
              }
              return try await probeHeaders(key: key, now: now)
          }

          // MARK: - Local session files

          /// Streams every `.jsonl` under the projects directory and aggregates the blocks.
          /// A missing directory, an unreadable file, or a malformed line is skipped, never fatal.
          static func scanBlocks(in directory: URL) -> [ClaudeUsageBlock] {
              guard let walker = FileManager.default.enumerator(
                  at: directory,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

              var entries: [ClaudeUsageEntry] = []
              for case let url as URL in walker where url.pathExtension == "jsonl" {
                  guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                  for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                      if let entry = ClaudeSessionBlocks.entry(fromLine: String(line)) {
                          entries.append(entry)
                      }
                  }
              }
              return ClaudeSessionBlocks.blocks(from: entries)
          }

          /// Returns nil when there are no blocks at all, which is the "nothing to report" case
          /// the caller turns into `.notConfigured` or a header probe.
          static func status(from blocks: [ClaudeUsageBlock], now: Date) -> ProviderStatus? {
              guard !blocks.isEmpty else { return nil }
              let peak = blocks.map(\.totalTokens).max() ?? 0
              let active = ClaudeSessionBlocks.activeBlock(in: blocks, now: now)
              let used = active?.totalTokens ?? 0
              let fraction = peak > 0 ? min(max(Double(used) / Double(peak), 0), 1) : 0

              let detail: String
              if active != nil {
                  detail = "\(used.formatted()) tokens this 5-hour block, against your busiest block of \(peak.formatted())"
              } else {
                  detail = "No activity in the current 5-hour block"
              }

              return ProviderStatus(
                  kind: .claude,
                  reading: .fraction(used: fraction, resetsAt: active?.endsAt),
                  detail: detail,
                  fetchedAt: now
              )
          }

          // MARK: - Rate limit header fallback

          /// Sends the smallest possible Messages request purely to read the rate limit headers.
          /// This IS billed, which is why it only runs when the user opted in.
          private func probeHeaders(key: String, now: Date) async throws -> ProviderStatus {
              var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
              request.httpMethod = "POST"
              request.timeoutInterval = 15
              request.setValue(key, forHTTPHeaderField: "x-api-key")
              request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
              request.setValue("application/json", forHTTPHeaderField: "content-type")
              request.httpBody = try JSONSerialization.data(withJSONObject: [
                  "model": "claude-haiku-4-5-20251001",
                  "max_tokens": 1,
                  "messages": [["role": "user", "content": "."]],
              ])

              let response: URLResponse
              do {
                  (_, response) = try await session.data(for: request)
              } catch {
                  throw mapTransportFailure(error)
              }
              guard let http = response as? HTTPURLResponse else {
                  throw ProviderError.malformedResponse("no HTTP response")
              }
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
              guard let status = Self.statusFromHeaders(http, now: now) else {
                  throw ProviderError.malformedResponse("no anthropic-ratelimit headers")
              }
              return status
          }

          /// Reads the documented input-token headers. A 401 response carries none of these, so
          /// a nil return means the fallback has nothing to say.
          static func statusFromHeaders(_ http: HTTPURLResponse, now: Date) -> ProviderStatus? {
              func number(_ name: String) -> Double? {
                  http.value(forHTTPHeaderField: name).flatMap(Double.init)
              }
              guard let limit = number("anthropic-ratelimit-input-tokens-limit"),
                    let remaining = number("anthropic-ratelimit-input-tokens-remaining"),
                    limit > 0 else { return nil }

              let resetsAt = http.value(forHTTPHeaderField: "anthropic-ratelimit-input-tokens-reset")
                  .flatMap { ClaudeSessionBlocks.parseTimestamp($0) }
              let fraction = min(max((limit - remaining) / limit, 0), 1)

              return ProviderStatus(
                  kind: .claude,
                  reading: .fraction(used: fraction, resetsAt: resetsAt),
                  detail: "API input tokens per minute, from response headers",
                  fetchedAt: now
              )
          }
      }
      ```

- [ ] Step 2: Verify - Run:

      ```bash
      mkdir -p /tmp/aiub-verify/empty && cat > /tmp/aiub-verify/main.swift <<'EOF'
      import Foundation
      let style = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
      let now = try style.parse("2026-01-15T17:00:00Z")

      // Empty projects directory: no fabricated number, just nil.
      print("EMPTY_DIR_BLOCKS=\(ClaudeProvider.scanBlocks(in: URL(fileURLWithPath: "/tmp/aiub-verify/empty")).count)")
      print("MISSING_DIR_BLOCKS=\(ClaudeProvider.scanBlocks(in: URL(fileURLWithPath: "/tmp/aiub-verify/does-not-exist")).count)")
      print("NO_BLOCKS_STATUS=\(ClaudeProvider.status(from: [], now: now).map { _ in "present" } ?? "nil")")

      let blocks = [
          ClaudeUsageBlock(startedAt: try style.parse("2026-01-15T09:00:00Z"), endsAt: try style.parse("2026-01-15T14:00:00Z"), totalTokens: 1865),
          ClaudeUsageBlock(startedAt: try style.parse("2026-01-15T16:00:00Z"), endsAt: try style.parse("2026-01-15T21:00:00Z"), totalTokens: 932),
      ]
      let status = ClaudeProvider.status(from: blocks, now: now)!
      print("STATUS reading=\(status.reading) detail=\(status.detail)")

      let headers = [
          "anthropic-ratelimit-input-tokens-limit": "2000000",
          "anthropic-ratelimit-input-tokens-remaining": "1500000",
          "anthropic-ratelimit-input-tokens-reset": "2026-01-15T17:05:00Z",
      ]
      let http = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!, statusCode: 200, httpVersion: nil, headerFields: headers)!
      print("HEADERS=\(ClaudeProvider.statusFromHeaders(http, now: now)!.reading)")
      let bare = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!, statusCode: 401, httpVersion: nil, headerFields: [:])!
      print("NO_HEADERS=\(ClaudeProvider.statusFromHeaders(bare, now: now).map { _ in "present" } ?? "nil")")
      EOF
      swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Providers/UsageProvider.swift AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift AIUsageBar/AIUsageBar/Providers/ClaudeSessionBlocks.swift AIUsageBar/AIUsageBar/Providers/ClaudeProvider.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/claude && /tmp/aiub-verify/claude
      ```

      Expected, exactly these six lines. The `STATUS` line is one physical line; it is shown wrapped here only because this document wraps.

      ```
      EMPTY_DIR_BLOCKS=0
      MISSING_DIR_BLOCKS=0
      NO_BLOCKS_STATUS=nil
      STATUS reading=fraction(used: 0.4997319034852547, resetsAt: Optional(2026-01-15 21:00:00 +0000)) detail=932 tokens this 5-hour block, against your busiest block of 1,865
      HEADERS=fraction(used: 0.25, resetsAt: Optional(2026-01-15 17:05:00 +0000))
      NO_HEADERS=nil
      ```

- [ ] Step 3: Verify - Run: `/tmp/aiub-verify/claude` is unchanged, then scan the real directory: `mkdir -p /tmp/aiub-verify && printf 'import Foundation\nlet b = ClaudeProvider.scanBlocks(in: ClaudeProvider.defaultProjectsDirectory)\nprint("real_blocks=\\(b.count) nonzero=\\(b.allSatisfy { $0.totalTokens >= 0 })")\n' > /tmp/aiub-verify/real.swift && mv /tmp/aiub-verify/real.swift /tmp/aiub-verify/main.swift && swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Providers/UsageProvider.swift AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift AIUsageBar/AIUsageBar/Providers/ClaudeSessionBlocks.swift AIUsageBar/AIUsageBar/Providers/ClaudeProvider.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/claudereal && time /tmp/aiub-verify/claudereal` - Expected: `real_blocks=` followed by a number greater than 0 and `nonzero=true`, completing in under 30 seconds. If the machine has no `~/.claude/projects`, `real_blocks=0` is also a pass and the Claude row will read "Not configured".
- [ ] Step 4: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [ ] Step 5: 👤 Verify - Human: **only if the user explicitly consents to a billed API call**, enable the header fallback in Settings with a real Anthropic API key and refresh - Expected: the Claude row switches to "API input tokens per minute, from response headers" with a percentage - Proxy: Step 2 asserts `statusFromHeaders` against a synthesised `HTTPURLResponse` carrying the exact documented header names, and asserts nil for a 401 with no headers. **Do not run this without asking; it sends a real `POST /v1/messages` and is billed.**
- [ ] Step 6: Commit - `git add AIUsageBar/AIUsageBar/Providers/ClaudeProvider.swift && git commit -m "feat: add Claude provider with session-file primary and header fallback"`

---

### Task 8: Preferences, provider store, and refresh scheduler

**Files:**
- Create: `AIUsageBar/AIUsageBar/Models/Preferences.swift`
- Create: `AIUsageBar/AIUsageBar/UI/ProviderStore.swift`
- Create: `AIUsageBar/AIUsageBar/Refresh/RefreshScheduler.swift`

**Interfaces:**
- Consumes: `ProviderKind`, `ProviderStatus`, `ProviderError`, `protocol UsageProvider`, `KeychainStore.hasKey(for:) -> Bool`, `DeepSeekProvider.init(keychain:session:)`, `ZAIProvider.init(keychain:session:)`, `ClaudeProvider.init(keychain:session:projectsDirectory:allowBilledProbe:)`.
- Consumes: `LabelSource` from Task 2, specifically `LabelSource.init(storageValue: String)` and `LabelSource.storageValue -> String`.
- Produces: `@MainActor @Observable final class Preferences` with `init(defaults: UserDefaults = .standard)`, `var refreshIntervalMinutes: Int` (clamped 1...60), `var labelSource: LabelSource`, `var allowBilledClaudeProbe: Bool`.
- Produces: `struct ProviderSlot: Equatable, Sendable { var status: ProviderStatus?; var error: ProviderError?; var isRefreshing: Bool }`.
- Produces: `@MainActor @Observable final class ProviderStore` with `init(keychain: KeychainStore = KeychainStore(), preferences: Preferences)`, `private(set) var slots: [ProviderKind: ProviderSlot]`, `var anyConfigured: Bool`, `func refreshAll(now: Date = Date()) async`, `func refresh(_ kind: ProviderKind, now: Date = Date()) async`.
- Produces: `@MainActor final class RefreshScheduler` with `init(store: ProviderStore, preferences: Preferences)`, `func start()`, `func stop()`, `func reschedule()`.

**Gotcha:** three things, one of which is a compiler error waiting to happen.
The "one provider failing must not blank the others" rule lives in `ProviderStore.apply`: write `slot.error` and leave `slot.status` untouched on failure, never assigning `nil` or a zeroed status.
**Do not write `group.addTask { @MainActor in await self.refresh(...) }`.** That exact shape was tried and fails with `error: pattern that the region-based isolation checker does not understand how to check. Please file a bug`. The working shape below keeps `self` out of the task group entirely: the group returns `(ProviderKind, Result<...>)` values, and the store applies them afterwards on the main actor.
`Preferences` stores only non-secret values in `UserDefaults`, and the scheduler must not fire when `anyConfigured` is false, per the brief.

**Steps:**

- [ ] Step 1: Create `AIUsageBar/AIUsageBar/Models/Preferences.swift`.

      ```swift
      import Foundation

      /// Non-secret settings only. API keys live in the Keychain and never appear here.
      @MainActor
      @Observable
      final class Preferences {
          private enum Key {
              static let refreshIntervalMinutes = "refreshIntervalMinutes"
              static let labelSource = "labelSource"
              static let allowBilledClaudeProbe = "allowBilledClaudeProbe"
          }

          private let defaults: UserDefaults

          init(defaults: UserDefaults = .standard) {
              self.defaults = defaults
              let stored = defaults.integer(forKey: Key.refreshIntervalMinutes)
              self.refreshIntervalMinutes = stored == 0 ? 5 : min(max(stored, 1), 60)
              self.labelSource = LabelSource(storageValue: defaults.string(forKey: Key.labelSource) ?? "all")
              self.allowBilledClaudeProbe = defaults.bool(forKey: Key.allowBilledClaudeProbe)
          }

          /// Clamped to the 1...60 range the brief specifies.
          var refreshIntervalMinutes: Int {
              didSet {
                  let clamped = min(max(refreshIntervalMinutes, 1), 60)
                  if clamped != refreshIntervalMinutes {
                      refreshIntervalMinutes = clamped
                      return
                  }
                  defaults.set(clamped, forKey: Key.refreshIntervalMinutes)
              }
          }

          /// Which provider or providers drive the collapsed menu bar label.
          var labelSource: LabelSource {
              didSet { defaults.set(labelSource.storageValue, forKey: Key.labelSource) }
          }

          /// Off by default. Turning it on permits a billed Messages request for the Claude
          /// header fallback.
          var allowBilledClaudeProbe: Bool {
              didSet { defaults.set(allowBilledClaudeProbe, forKey: Key.allowBilledClaudeProbe) }
          }
      }
      ```

- [ ] Step 2: Create `AIUsageBar/AIUsageBar/UI/ProviderStore.swift`.

      ```swift
      import Foundation

      /// Independent per-provider state. A failure writes `error` and leaves `status` alone,
      /// so a stale reading stays on screen next to an error indicator. It is never zeroed.
      struct ProviderSlot: Equatable, Sendable {
          var status: ProviderStatus?
          var error: ProviderError?
          var isRefreshing: Bool = false
      }

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

          /// True when at least one provider can produce a reading: any stored key, or a
          /// readable Claude projects directory.
          var anyConfigured: Bool {
              if keychain.hasKey(for: .zai) || keychain.hasKey(for: .deepseek) { return true }
              return FileManager.default.fileExists(atPath: ClaudeProvider.defaultProjectsDirectory.path)
          }

          private func provider(for kind: ProviderKind) -> any UsageProvider {
              switch kind {
              case .claude:
                  return ClaudeProvider(keychain: keychain,
                                        allowBilledProbe: preferences.allowBilledClaudeProbe)
              case .zai:
                  return ZAIProvider(keychain: keychain)
              case .deepseek:
                  return DeepSeekProvider(keychain: keychain)
              }
          }

          /// Fetches every provider concurrently off the main actor, then applies the results here.
          /// The task group must not capture `self`: a `@MainActor` closure inside `addTask` is
          /// rejected by the region-based isolation checker.
          func refreshAll(now: Date = Date()) async {
              for kind in ProviderKind.allCases {
                  slots[kind, default: ProviderSlot()].isRefreshing = true
              }
              let work = ProviderKind.allCases.map { ($0, provider(for: $0)) }
              var results: [(ProviderKind, Result<ProviderStatus, any Error>)] = []
              await withTaskGroup(of: (ProviderKind, Result<ProviderStatus, any Error>).self) { group in
                  for (kind, provider) in work {
                      group.addTask {
                          do { return (kind, .success(try await provider.fetch(now: now))) }
                          catch { return (kind, .failure(error)) }
                      }
                  }
                  for await result in group { results.append(result) }
              }
              for (kind, result) in results { apply(result, to: kind) }
              for kind in ProviderKind.allCases {
                  slots[kind, default: ProviderSlot()].isRefreshing = false
              }
          }

          func refresh(_ kind: ProviderKind, now: Date = Date()) async {
              slots[kind, default: ProviderSlot()].isRefreshing = true
              let provider = provider(for: kind)
              let result: Result<ProviderStatus, any Error>
              do { result = .success(try await provider.fetch(now: now)) }
              catch { result = .failure(error) }
              apply(result, to: kind)
              slots[kind, default: ProviderSlot()].isRefreshing = false
          }

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

- [ ] Step 3: Create `AIUsageBar/AIUsageBar/Refresh/RefreshScheduler.swift`.

      ```swift
      import Foundation

      /// Drives auto-refresh. Pauses entirely when no provider is configured, as the brief requires.
      @MainActor
      final class RefreshScheduler {
          private let store: ProviderStore
          private let preferences: Preferences
          private var task: Task<Void, Never>?

          init(store: ProviderStore, preferences: Preferences) {
              self.store = store
              self.preferences = preferences
          }

          func start() {
              stop()
              guard store.anyConfigured else { return }
              let interval = UInt64(preferences.refreshIntervalMinutes) * 60 * 1_000_000_000
              task = Task { [store] in
                  await store.refreshAll()
                  while !Task.isCancelled {
                      try? await Task.sleep(nanoseconds: interval)
                      if Task.isCancelled { return }
                      guard store.anyConfigured else { return }
                      await store.refreshAll()
                  }
              }
          }

          func stop() {
              task?.cancel()
              task = nil
          }

          /// Call after the interval changes or a key is added or removed.
          func reschedule() { start() }
      }
      ```

- [ ] Step 4: Verify - Run:

      ```bash
      mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/main.swift <<'EOF'
      import Foundation

      @MainActor
      func run() async {
          let suite = UserDefaults(suiteName: "com.theerakarn.AIUsageBar.verify")!
          suite.removePersistentDomain(forName: "com.theerakarn.AIUsageBar.verify")
          let prefs = Preferences(defaults: suite)
          print("DEFAULT_INTERVAL=\(prefs.refreshIntervalMinutes) SOURCE=\(prefs.labelSource.storageValue) PROBE=\(prefs.allowBilledClaudeProbe)")
          prefs.refreshIntervalMinutes = 999
          print("CLAMP_HIGH=\(prefs.refreshIntervalMinutes)")
          prefs.refreshIntervalMinutes = 0
          print("CLAMP_LOW=\(prefs.refreshIntervalMinutes)")

          // A failure must keep the previous status and add an error, never blank it.
          var slot = ProviderSlot(status: ProviderStatus(kind: .deepseek, reading: .balance(amount: Decimal(string: "4.10")!, currency: "USD"), detail: "USD", fetchedAt: Date(timeIntervalSince1970: 0)), error: nil, isRefreshing: false)
          slot.error = .offline
          print("STALE_KEPT=\(slot.status != nil) ERROR=\(slot.error!.shortDescription)")

          let store = ProviderStore(keychain: KeychainStore(service: "com.theerakarn.AIUsageBar.verify-empty"), preferences: prefs)
          print("SLOTS=\(store.slots.count) ALL_EMPTY=\(store.slots.values.allSatisfy { $0.status == nil && $0.error == nil })")
          await store.refresh(.deepseek, now: Date(timeIntervalSince1970: 0))
          print("UNCONFIGURED=\(store.slots[.deepseek]!.error!.shortDescription) STILL_NIL=\(store.slots[.deepseek]!.status == nil)")
          suite.removePersistentDomain(forName: "com.theerakarn.AIUsageBar.verify")
      }

      await run()
      EOF
      swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Models/CollapsedLabelText.swift AIUsageBar/AIUsageBar/Models/Preferences.swift AIUsageBar/AIUsageBar/Providers/UsageProvider.swift AIUsageBar/AIUsageBar/Providers/ClaudeSessionBlocks.swift AIUsageBar/AIUsageBar/Providers/ClaudeProvider.swift AIUsageBar/AIUsageBar/Providers/ZAIProvider.swift AIUsageBar/AIUsageBar/Providers/DeepSeekProvider.swift AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift AIUsageBar/AIUsageBar/UI/ProviderStore.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/store && /tmp/aiub-verify/store
      ```

      Expected, exactly these six lines:

      ```
      DEFAULT_INTERVAL=5 SOURCE=all PROBE=false
      CLAMP_HIGH=60
      CLAMP_LOW=1
      STALE_KEPT=true ERROR=Offline
      SLOTS=3 ALL_EMPTY=true
      UNCONFIGURED=Not configured STILL_NIL=true
      ```

- [ ] Step 5: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [ ] Step 6: Commit - `git add AIUsageBar/AIUsageBar/Models/Preferences.swift AIUsageBar/AIUsageBar/UI/ProviderStore.swift AIUsageBar/AIUsageBar/Refresh/RefreshScheduler.swift && git commit -m "feat: add preferences, per-provider store, and refresh scheduler"`

---

### Task 9: Collapsed label text, menu bar label, and dropdown panel

**Files:**
- Create: `AIUsageBar/AIUsageBar/Models/CollapsedLabelText.swift`
- Create: `AIUsageBar/AIUsageBar/UI/MenuBarLabel.swift`
- Create: `AIUsageBar/AIUsageBar/UI/DropdownPanel.swift`

**Interfaces:**
- Consumes: `ProviderKind`, `ProviderStatus`, `ProviderReading`, `ProviderError`, `ProviderSlot`, `ProviderStore.slots`, `ProviderStore.refreshAll(now:)`, `Preferences.labelSource`.
- Consumes: `LabelSource` from Task 2, all four members.
- Produces: `enum CollapsedLabelText` with `static let budget = 14`, `static func text(for slots: [ProviderKind: ProviderSlot], source: LabelSource) -> String`, `static func symbolName(for slots: [ProviderKind: ProviderSlot], source: LabelSource) -> String`.
- Produces: `struct MenuBarLabel: View` with `init(store: ProviderStore, preferences: Preferences)`.
- Produces: `struct DropdownPanel: View` with `init(store: ProviderStore)`. It takes no `Preferences`: the panel shows every provider regardless of which one drives the collapsed label.

**Gotcha:** four constraints, all load-bearing.
`CollapsedLabelText.swift` must stay **Foundation-only**, with no `import SwiftUI`, so the width budget is checkable by a standalone harness.
The budget is 14 characters for the text alone; the SF Symbol sits beside it and is not counted, matching the brief's `◐ 62% · $4.10` example.
The brief's example shows two providers at once and AGENTS.md requires the budget to hold "regardless of how many providers are active", so Task 2's `LabelSource` has an `allConfigured` case that joins every configured provider; it is the default. The separator is a **bare** middot `·` with no surrounding spaces, because `" · "` pushes three providers to 17 characters and blows the budget.
`.notConfigured` is not a failure: it must render the plain gauge glyph, never the warning triangle, or an app with no keys looks broken on first launch.

**Steps:**

- [ ] Step 1: Create `AIUsageBar/AIUsageBar/Models/CollapsedLabelText.swift`. Foundation only.

      ```swift
      import Foundation

      /// Builds the collapsed menu bar string. Foundation-only on purpose, so the width budget
      /// is checkable without a running app.
      enum CollapsedLabelText {
          /// Hard character budget for the text beside the SF Symbol.
          static let budget = 14

          /// Joined with a bare middot: " · " with spaces overflows the budget at three providers.
          private static let separator = "\u{00B7}"

          static func text(for slots: [ProviderKind: ProviderSlot], source: LabelSource) -> String {
              switch source {
              case .provider(let kind):
                  return clamp(single(slots[kind], kind: kind))
              case .allConfigured:
                  let parts = ProviderKind.allCases.compactMap { kind -> String? in
                      guard let slot = slots[kind] else { return nil }
                      if slot.status == nil, slot.error == .notConfigured || slot.error == nil { return nil }
                      return single(slot, kind: kind)
                  }
                  return clamp(parts.isEmpty ? "Not set up" : parts.joined(separator: separator))
              }
          }

          /// A warning glyph only when something actually failed. "Not configured" is not a failure.
          static func symbolName(for slots: [ProviderKind: ProviderSlot], source: LabelSource) -> String {
              let relevant: [ProviderSlot]
              switch source {
              case .provider(let kind): relevant = [slots[kind]].compactMap { $0 }
              case .allConfigured: relevant = Array(slots.values)
              }
              let failing = relevant.contains { slot in
                  guard let error = slot.error else { return false }
                  return error != .notConfigured
              }
              return failing ? "exclamationmark.triangle" : "gauge.with.needle"
          }

          private static func single(_ slot: ProviderSlot?, kind: ProviderKind) -> String {
              guard let slot else { return "\(kind.shortName) --" }
              if let status = slot.status {
                  let value = format(status.reading)
                  return slot.error == nil ? value : "\(value)!"
              }
              if let error = slot.error, error != .notConfigured {
                  return "\(kind.shortName)!"
              }
              return "\(kind.shortName) --"
          }

          private static func format(_ reading: ProviderReading) -> String {
              switch reading {
              case .fraction(let used, _):
                  return "\(Int((used * 100).rounded()))%"
              case .balance(let amount, let currency):
                  return "\(symbol(for: currency))\(compact(amount))"
              }
          }

          private static func symbol(for currency: String) -> String {
              switch currency.uppercased() {
              case "USD": return "$"
              case "CNY": return "\u{00A5}"
              case "EUR": return "\u{20AC}"
              default: return "\(currency.uppercased()) "
              }
          }

          /// Keeps big balances short: 1234.5 becomes 1.2k, 1234567 becomes 1.2M.
          private static func compact(_ amount: Decimal) -> String {
              let value = (amount as NSDecimalNumber).doubleValue
              let magnitude = abs(value)
              if magnitude >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
              if magnitude >= 1_000 { return String(format: "%.1fk", value / 1_000) }
              return String(format: "%.2f", value)
          }

          private static func clamp(_ value: String) -> String {
              value.count <= budget ? value : String(value.prefix(budget - 1)) + "\u{2026}"
          }
      }
      ```

- [ ] Step 2: Create `AIUsageBar/AIUsageBar/UI/MenuBarLabel.swift`.

      ```swift
      import SwiftUI

      /// The collapsed menu bar item: one SF Symbol plus one short string, driven by whichever
      /// source the user picked in Settings.
      struct MenuBarLabel: View {
          let store: ProviderStore
          let preferences: Preferences

          var body: some View {
              let source = preferences.labelSource
              HStack(spacing: 3) {
                  Image(systemName: CollapsedLabelText.symbolName(for: store.slots, source: source))
                  Text(CollapsedLabelText.text(for: store.slots, source: source))
              }
              .accessibilityLabel("\(source.displayName) usage")
          }
      }
      ```

- [ ] Step 3: Create `AIUsageBar/AIUsageBar/UI/DropdownPanel.swift`.

      ```swift
      import SwiftUI

      /// One row per provider: name, a progress bar or a balance figure, a secondary line, and
      /// the per-provider last-refreshed time.
      struct DropdownPanel: View {
          let store: ProviderStore

          var body: some View {
              VStack(alignment: .leading, spacing: 12) {
                  ForEach(ProviderKind.allCases) { kind in
                      ProviderRow(kind: kind, slot: store.slots[kind] ?? ProviderSlot())
                  }
                  Divider()
                  HStack {
                      Button("Refresh") { Task { await store.refreshAll() } }
                      Spacer()
                      SettingsLink { Text("Settings…") }
                      Button("Quit") { NSApplication.shared.terminate(nil) }
                  }
              }
              .padding(14)
              .frame(width: 300)
          }
      }

      private struct ProviderRow: View {
          let kind: ProviderKind
          let slot: ProviderSlot

          var body: some View {
              VStack(alignment: .leading, spacing: 3) {
                  HStack {
                      Text(kind.displayName).font(.headline)
                      if slot.isRefreshing {
                          ProgressView().controlSize(.small)
                      }
                      Spacer()
                      if let error = slot.error {
                          Label(error.shortDescription, systemImage: "exclamationmark.triangle.fill")
                              .labelStyle(.titleAndIcon)
                              .font(.caption)
                              .foregroundStyle(.orange)
                      }
                  }

                  if let status = slot.status {
                      switch status.reading {
                      case .fraction(let used, let resetsAt):
                          ProgressView(value: used)
                              .progressViewStyle(.linear)
                          HStack {
                              Text("\(Int((used * 100).rounded()))% used")
                              if let resetsAt {
                                  Text("resets \(resetsAt, style: .relative)")
                              }
                          }
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      case .balance(let amount, let currency):
                          Text(amount.formatted(.currency(code: currency)))
                              .font(.title3)
                              .monospacedDigit()
                      }
                      Text(status.detail)
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                      Text("Updated \(status.fetchedAt, style: .relative) ago")
                          .font(.caption2)
                          .foregroundStyle(.tertiary)
                  } else {
                      Text(slot.error?.shortDescription ?? "Not configured")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                  }
              }
          }
      }
      ```

- [ ] Step 4: Verify - Run:

      ```bash
      mkdir -p /tmp/aiub-verify && cat > /tmp/aiub-verify/main.swift <<'EOF'
      import Foundation
      let now = Date(timeIntervalSince1970: 0)
      func slot(_ kind: ProviderKind, _ reading: ProviderReading?, _ error: ProviderError?) -> ProviderSlot {
          ProviderSlot(status: reading.map { ProviderStatus(kind: kind, reading: $0, detail: "", fetchedAt: now) }, error: error)
      }
      let claude = slot(.claude, .fraction(used: 0.62, resetsAt: nil), nil)
      let glm = slot(.zai, .fraction(used: 1.0, resetsAt: nil), nil)
      let ds = slot(.deepseek, .balance(amount: Decimal(string: "4.10")!, currency: "USD"), nil)
      let dsBig = slot(.deepseek, .balance(amount: Decimal(string: "1234567.89")!, currency: "USD"), nil)
      let dsOdd = slot(.deepseek, .balance(amount: Decimal(string: "12.34")!, currency: "XYZ"), nil)
      let unset = ProviderSlot(status: nil, error: .notConfigured)
      let broken = ProviderSlot(status: nil, error: .unauthorized)
      let stale = slot(.deepseek, .balance(amount: Decimal(string: "4.10")!, currency: "USD"), .offline)

      let cases: [(String, [ProviderKind: ProviderSlot], LabelSource)] = [
          ("one_pct", [.claude: claude], .provider(.claude)),
          ("one_bal", [.deepseek: ds], .provider(.deepseek)),
          ("one_unset", [.zai: unset], .provider(.zai)),
          ("one_broken", [.zai: broken], .provider(.zai)),
          ("one_stale", [.deepseek: stale], .provider(.deepseek)),
          ("all_three", [.claude: claude, .zai: glm, .deepseek: ds], .allConfigured),
          ("all_worst", [.claude: claude, .zai: glm, .deepseek: dsOdd], .allConfigured),
          ("all_big", [.claude: claude, .zai: glm, .deepseek: dsBig], .allConfigured),
          ("all_none", [.claude: unset, .zai: unset, .deepseek: unset], .allConfigured),
          ("all_partial", [.claude: claude, .zai: unset, .deepseek: broken], .allConfigured),
      ]
      var worst = 0
      for (name, slots, source) in cases {
          let text = CollapsedLabelText.text(for: slots, source: source)
          worst = max(worst, text.count)
          print("\(name)=\"\(text)\" len=\(text.count) symbol=\(CollapsedLabelText.symbolName(for: slots, source: source))")
      }
      print("MAX_LEN=\(worst) BUDGET=\(CollapsedLabelText.budget) WITHIN=\(worst <= CollapsedLabelText.budget)")
      EOF
      swiftc -swift-version 6 AIUsageBar/AIUsageBar/Models/ProviderStatus.swift AIUsageBar/AIUsageBar/Models/CollapsedLabelText.swift AIUsageBar/AIUsageBar/Models/Preferences.swift AIUsageBar/AIUsageBar/Providers/UsageProvider.swift AIUsageBar/AIUsageBar/Providers/ClaudeSessionBlocks.swift AIUsageBar/AIUsageBar/Providers/ClaudeProvider.swift AIUsageBar/AIUsageBar/Providers/ZAIProvider.swift AIUsageBar/AIUsageBar/Providers/DeepSeekProvider.swift AIUsageBar/AIUsageBar/Keychain/KeychainStore.swift AIUsageBar/AIUsageBar/UI/ProviderStore.swift /tmp/aiub-verify/main.swift -o /tmp/aiub-verify/label && /tmp/aiub-verify/label
      ```

      `ProviderSlot` is declared in Task 8's `ProviderStore.swift`, so the harness compiles the same file list Task 8 used rather than a shim that could silently drift.

      Expected, exactly these eleven lines. `all_three` at exactly 14 is the budget's worst realistic case, and `all_worst` proves the clamp fires rather than overflowing:

      ```
      one_pct="62%" len=3 symbol=gauge.with.needle
      one_bal="$4.10" len=5 symbol=gauge.with.needle
      one_unset="GLM --" len=6 symbol=gauge.with.needle
      one_broken="GLM!" len=4 symbol=exclamationmark.triangle
      one_stale="$4.10!" len=6 symbol=exclamationmark.triangle
      all_three="62%·100%·$4.10" len=14 symbol=gauge.with.needle
      all_worst="62%·100%·XYZ …" len=14 symbol=gauge.with.needle
      all_big="62%·100%·$1.2M" len=14 symbol=gauge.with.needle
      all_none="Not set up" len=10 symbol=gauge.with.needle
      all_partial="62%·DS!" len=7 symbol=exclamationmark.triangle
      MAX_LEN=14 BUDGET=14 WITHIN=true
      ```

- [ ] Step 5: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [ ] Step 6: Commit - `git add AIUsageBar/AIUsageBar/Models/CollapsedLabelText.swift AIUsageBar/AIUsageBar/UI/MenuBarLabel.swift AIUsageBar/AIUsageBar/UI/DropdownPanel.swift && git commit -m "feat: add collapsed label text budget, menu bar label, and dropdown panel"`

---

### Task 10: Settings window, launch at login, and app wiring

**Files:**
- Create: `AIUsageBar/AIUsageBar/UI/SettingsView.swift`
- Create: `AIUsageBar/AIUsageBar/App/LoginItem.swift`
- Modify: `AIUsageBar/AIUsageBar/App/AIUsageBarApp.swift` (anchor: `struct AIUsageBarApp: App`)

**Interfaces:**
- Consumes: `Preferences`, `ProviderStore`, `RefreshScheduler`, `KeychainStore`, `MenuBarLabel.init(store:preferences:)`, `DropdownPanel.init(store:preferences:)`, `ProviderKind`.
- Produces: `struct SettingsView: View` with `init(preferences: Preferences, scheduler: RefreshScheduler)`. It takes no `ProviderStore`: saving a key reschedules the timer, which re-reads the Keychain, so the view never touches the store.
- Produces: `@MainActor enum LoginItem` with `static var isEnabled: Bool` and `static func set(_ enabled: Bool) throws`.

**Gotcha:** `SMAppService.mainApp.register()` throws when the app is not in a location macOS trusts, which includes a DerivedData build directory.
Surface the thrown error in the UI rather than silently leaving the toggle in the wrong position, and re-read `status` after every attempt.
The key fields must be `SecureField` and must never be seeded from the Keychain; show a "Key saved" indicator instead of the value.

**Rollback:** the launch-at-login toggle and any key saved during the Step 5 checks live outside git. Undo them with `security delete-generic-password -s com.theerakarn.AIUsageBar -a deepseek 2>/dev/null; true` per account, and by turning the toggle off in the app or removing AIUsageBar under System Settings, General, Login Items. Reverting the commit alone leaves both in place.

**Steps:**

- [ ] Step 1: Create `AIUsageBar/AIUsageBar/App/LoginItem.swift`.

      ```swift
      import Foundation
      import ServiceManagement

      /// Launch at login via SMAppService. Registration can legitimately fail when the app runs
      /// from a build directory, so the caller shows the error rather than assuming success.
      @MainActor
      enum LoginItem {
          static var isEnabled: Bool {
              SMAppService.mainApp.status == .enabled
          }

          static func set(_ enabled: Bool) throws {
              if enabled {
                  try SMAppService.mainApp.register()
              } else {
                  try SMAppService.mainApp.unregister()
              }
          }
      }
      ```

- [ ] Step 2: Create `AIUsageBar/AIUsageBar/UI/SettingsView.swift`.

      ```swift
      import SwiftUI

      struct SettingsView: View {
          let preferences: Preferences
          let scheduler: RefreshScheduler

          private let keychain = KeychainStore()

          @State private var draftKeys: [ProviderKind: String] = [:]
          @State private var savedKinds: Set<ProviderKind> = []
          @State private var launchAtLogin = false
          @State private var message: String?

          var body: some View {
              Form {
                  Section("API keys") {
                      ForEach(ProviderKind.allCases.filter { $0 != .claude }) { kind in
                          keyRow(kind)
                      }
                      LabeledContent("Claude") {
                          Text("Reads ~/.claude/projects. No key needed.")
                              .font(.caption)
                              .foregroundStyle(.secondary)
                      }
                      Toggle("Allow a billed API request when no local sessions exist", isOn: Binding(
                          get: { preferences.allowBilledClaudeProbe },
                          set: { preferences.allowBilledClaudeProbe = $0 }
                      ))
                      .help("Sends one minimal POST /v1/messages to read anthropic-ratelimit headers. This is billed.")
                      if preferences.allowBilledClaudeProbe {
                          keyRow(.claude)
                      }
                  }

                  Section("Refresh") {
                      Stepper(value: Binding(
                          get: { preferences.refreshIntervalMinutes },
                          set: { preferences.refreshIntervalMinutes = $0; scheduler.reschedule() }
                      ), in: 1...60) {
                          Text("Every \(preferences.refreshIntervalMinutes) min")
                      }
                      Picker("Menu bar shows", selection: Binding(
                          get: { preferences.labelSource },
                          set: { preferences.labelSource = $0 }
                      )) {
                          ForEach(LabelSource.allCases, id: \.self) { source in
                              Text(source.displayName).tag(source)
                          }
                      }
                  }

                  Section("General") {
                      Toggle("Launch at login", isOn: Binding(
                          get: { launchAtLogin },
                          set: { newValue in
                              do {
                                  try LoginItem.set(newValue)
                                  message = nil
                              } catch {
                                  message = "Could not change the login item: \(error.localizedDescription)"
                              }
                              launchAtLogin = LoginItem.isEnabled
                          }
                      ))
                      if let message {
                          Text(message).font(.caption).foregroundStyle(.orange)
                      }
                  }
              }
              .formStyle(.grouped)
              .frame(width: 460)
              .onAppear {
                  launchAtLogin = LoginItem.isEnabled
                  savedKinds = Set(ProviderKind.allCases.filter { keychain.hasKey(for: $0) })
              }
          }

          @ViewBuilder
          private func keyRow(_ kind: ProviderKind) -> some View {
              // The stored value is never read back into the field: presence only.
              LabeledContent(kind.displayName) {
                  HStack {
                      SecureField(savedKinds.contains(kind) ? "Key saved" : "Paste key",
                                  text: Binding(
                                      get: { draftKeys[kind] ?? "" },
                                      set: { draftKeys[kind] = $0 }
                                  ))
                      Button("Save") { save(kind) }
                          .disabled((draftKeys[kind] ?? "").isEmpty)
                      Button("Clear") { clear(kind) }
                          .disabled(!savedKinds.contains(kind))
                  }
              }
          }

          private func save(_ kind: ProviderKind) {
              do {
                  try keychain.set(draftKeys[kind] ?? "", for: kind)
                  draftKeys[kind] = ""
                  savedKinds = Set(ProviderKind.allCases.filter { keychain.hasKey(for: $0) })
                  scheduler.reschedule()
                  message = nil
              } catch {
                  message = "Could not save the key to the Keychain."
              }
          }

          private func clear(_ kind: ProviderKind) {
              do {
                  try keychain.remove(kind)
                  draftKeys[kind] = ""
                  savedKinds = Set(ProviderKind.allCases.filter { keychain.hasKey(for: $0) })
                  scheduler.reschedule()
                  message = nil
              } catch {
                  message = "Could not clear the key from the Keychain."
              }
          }
      }
      ```

- [ ] Step 3: Replace the whole body of `AIUsageBar/AIUsageBar/App/AIUsageBarApp.swift` (anchor: `struct AIUsageBarApp: App`).

      ```swift
      import SwiftUI

      @main
      struct AIUsageBarApp: App {
          @State private var preferences: Preferences
          @State private var store: ProviderStore
          @State private var scheduler: RefreshScheduler

          init() {
              let preferences = Preferences()
              let store = ProviderStore(preferences: preferences)
              let scheduler = RefreshScheduler(store: store, preferences: preferences)
              _preferences = State(initialValue: preferences)
              _store = State(initialValue: store)
              _scheduler = State(initialValue: scheduler)
          }

          var body: some Scene {
              MenuBarExtra {
                  DropdownPanel(store: store)
                      .task { scheduler.start() }
              } label: {
                  MenuBarLabel(store: store, preferences: preferences)
              }
              .menuBarExtraStyle(.window)

              Settings {
                  SettingsView(preferences: preferences, scheduler: scheduler)
              }
          }
      }
      ```

- [ ] Step 4: Verify - Run: `cd AIUsageBar && xcodebuild -scheme AIUsageBar -configuration Debug -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-build.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-build.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`.
- [ ] Step 5: Verify - Manual: `open AIUsageBar/.build/Build/Products/Debug/AIUsageBar.app && sleep 3 && osascript -e 'tell application "System Events" to return (name of every process whose bundle identifier is "com.theerakarn.AIUsageBar")' && osascript -e 'tell application "System Events" to return (background only of every process whose bundle identifier is "com.theerakarn.AIUsageBar")'` - Expected: the first call prints `AIUsageBar`, proving it launched; the second prints `true`, proving it is an agent process with no Dock icon.
- [ ] Step 6: Verify - Manual: `defaults read com.theerakarn.AIUsageBar` - Expected: at most the three non-secret keys `refreshIntervalMinutes`, `labelSource`, `allowBilledClaudeProbe`, and no value resembling an API key. A `Domain ... does not exist` message before any setting is changed is also a pass.
- [ ] Step 7: Verify - Manual: `osascript -e 'tell application "AIUsageBar" to quit' 2>/dev/null; pkill -x AIUsageBar; sleep 1; pgrep -x AIUsageBar || echo "stopped"` - Expected: `stopped`.
- [ ] Step 8: Commit - `git add AIUsageBar/AIUsageBar/UI/SettingsView.swift AIUsageBar/AIUsageBar/App/LoginItem.swift AIUsageBar/AIUsageBar/App/AIUsageBarApp.swift && git commit -m "feat: add settings window, launch at login, and app wiring"`

---

## Failure handling summary

- **`SMAppService.mainApp.register()` throws while the app runs from `.build/`.** Detect: the Settings toggle snaps back and the orange message appears. Respond: this is expected for an unsigned build outside `/Applications`; do NOT work around it by changing signing or by copying the app elsewhere. Record it against the launch-at-login end-to-end item and move on.
- **macOS prompts for Keychain access after a rebuild.** Detect: a system dialog naming AIUsageBar and the item under `com.theerakarn.AIUsageBar`. Respond: this follows from ad-hoc signing changing on each build, which Preflight records. Choose Always Allow. It is not a defect and needs no code change.
- **z.ai returns `success:false` with an unfamiliar `code`.** Detect: the z.ai row shows `Server error <n>`. Respond: do NOT broaden the unauthorized branch to swallow it. Record the exact `code` and `msg` in the run report; the classification stays narrow on purpose.
- **A provider verify needs a key the user does not have.** Detect: a 👤 step in Task 4, 5, or 7. Respond: leave the box unticked and report it as "awaiting human", never as passed or failed.

## End-to-end verification

Run after Task 10 is committed.

- [ ] Run: `cd AIUsageBar && rm -rf .build && xcodebuild -scheme AIUsageBar -configuration Release -derivedDataPath ./.build build 2>&1 | tee /tmp/aiub-release.log | tail -2; echo "warnings=$(grep -c ': warning: ' /tmp/aiub-release.log || true)"` - Expected: `** BUILD SUCCEEDED **` then `warnings=0`, from a clean derived-data directory in the Release configuration.
- [ ] Run: `/usr/libexec/PlistBuddy -c "Print :LSUIElement" AIUsageBar/.build/Build/Products/Release/AIUsageBar.app/Contents/Info.plist` - Expected: `true`.
- [ ] Run: `git status --porcelain AIUsageBar | head` - Expected: no output, meaning every file the plan created is committed and `.build/` is ignored.
- [ ] Run: `grep -rn 'sk-' AIUsageBar --include='*.swift' || echo "no key literals"` - Expected: `no key literals`. This is a negative control: the string `sk-` appears nowhere in committed Swift source.
- [ ] Manual: with **no keys saved at all**, launch the Release build and open the dropdown - Expected: all three rows render, the z.ai and DeepSeek rows read `Not configured`, the Claude row shows a real percentage if `~/.claude/projects` has sessions and `Not configured` otherwise. No crash, no zero passed off as data.
- [ ] Manual: `defaults read com.theerakarn.AIUsageBar` after saving and clearing a dummy key in Settings - Expected: only `refreshIntervalMinutes`, `labelSource`, `allowBilledClaudeProbe`; no key material anywhere in the output.
- [ ] Manual: `security find-generic-password -s com.theerakarn.AIUsageBar -a deepseek -g 2>&1 | head -3` after saving a dummy DeepSeek key - Expected: the item is found under that service and account, proving the key landed in the Keychain and not in a file.
- [ ] Manual: quit the app, relaunch it, and reopen Settings - Expected: the DeepSeek field shows the `Key saved` placeholder, proving the Keychain value survived a restart. Then clear it.
- [ ] 👤 Human: with all three providers configured, look at the collapsed menu bar item beside the battery and clock - Expected: the label stays narrow enough that no existing menu bar item is pushed off screen, at every value the label can take - Proxy: Task 9 Step 4 asserts `MAX_LEN=14 BUDGET=14 WITHIN=true` across ten label states, including all three providers at once, a seven-figure balance, and an unknown currency code that forces the clamp.
- [ ] 👤 Human: turn Wi-Fi off, click Refresh, and watch a previously-populated provider row - Expected: the row keeps its previous figure and gains an `Offline` indicator; it does not blank and does not show 0 - Proxy: Task 8 Step 4 asserts `STALE_KEPT=true ERROR=Offline` on the same code path, and Task 4 Step 2 asserts the parse layer throws rather than returning a zeroed status.
- [ ] 👤 Human: copy the Release build to `/Applications`, launch it, and toggle Launch at login - Expected: the toggle sticks and the app appears under System Settings, General, Login Items - Proxy: Task 10 Step 4 proves `LoginItem` compiles against `SMAppService` at the 14.0 deployment target; the toggle cannot be exercised from a build directory, which the Failure handling section records.

## Unverified assumptions

The brief asked for these to be listed explicitly.

1. **z.ai `Authorization` header form.** `robinebers/openusage` (Swift, with a live capture dated 2026-08-13) sends `Bearer <key>`; `guyinwonder168/opencode-glm-quota` states the opposite, that the token is passed with no `Bearer` prefix. Both cannot be right for the same account type. Task 5 sends `Bearer` first and retries once with the bare token when the body reports `code: 1001`. Resolvable only with a live GLM Coding Plan key.
2. **z.ai `unit` code semantics.** `3 = hours`, `4 = days`, `5 = months`, `6 = weeks`, multiplied by `number`. Taken from `openusage`'s `ZAIUsageMapper` plus a captured payload in which `unit:3, number:5` is the 5-hour window and `unit:6, number:1` is the weekly one. The endpoint is absent from z.ai's public API reference, so there is no official statement to check this against.
3. **z.ai quota response shape generally.** `data.limits[]` with `type`, `unit`, `number`, `percentage`, and `nextResetTime`, and the `TOKENS_LIMIT` to `CREDIT_LIMIT` rename. Same source, same caveat. Task 5 therefore ignores unrecognised entries instead of failing on them.
4. **Claude in-block percentage denominator.** The largest historical 5-hour block. No official remaining-subscription-limit number exists, and the brief specified ccusage-style blocks without naming a denominator. The dropdown's secondary line states the comparison in words so the figure is not mistaken for an official quota.
5. **DeepSeek `is_available` semantics.** Documented as "whether the user has sufficient balance", but not used by this app, which reports `total_balance` directly. The field is decoded and ignored.
6. **`anthropic-ratelimit-input-tokens-*` as the Claude fallback meter.** The header names and their RFC 3339 reset format are documented and quoted exactly. What is unverified is whether an unattended minimal request reliably returns them for every account tier, because a 401 response carries none of them and testing a 200 requires a billed call.
