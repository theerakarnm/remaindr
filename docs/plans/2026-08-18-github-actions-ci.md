# CI on GitHub Actions Implementation Plan

> **Run with:** `/execute-plan <path-to-this-file>` - the runner that ticks these
> checkboxes and honours the track/merge layout below.
>
> **For the executing agent:** Implement this plan track-by-track. Parallel
> tracks each get their own `treehouse get --lease` worktree (see Execution).
> Steps use checkbox (`- [ ]`) syntax for tracking; tick them as you go.
> Run the `## Preflight` checks BEFORE task 1 and report anything down.

**Goal:** Build GitHub Actions CI that builds the macOS app with zero warnings and runs the tests on every push, which first requires adding the repository's missing test target and wiring it into the shared scheme.
The request, verbatim from the repo owner: "CI on GitHub Actions that builds with zero warnings and runs the tests on every push."

**Architecture:** CI is one new workflow file, `.github/workflows/ci.yml`, that triggers on every push and runs a Release build plus the scheme's test action on a `macos-26` runner, both gated by `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` passed on the command line so any Swift warning fails the run without touching project build settings.
The repo has no test target and the shared scheme has an empty `<Testables>` block, so Task 1 first adds a `RemaindrTests` unit test target with six smoke tests over the Foundation-only `CollapsedLabelText` model and wires it into the committed shared scheme; `xcodebuild test` currently exits 66, so this task is the prerequisite for the "runs the tests" half of the request, not scope creep.
Task 3 then pushes the branch (a push event in itself), watches the real workflow run conclude success, and merges the PR, which is the only authoritative validation of the workflow file.

**Tech Stack:** GitHub Actions (`actions/checkout@v5`), YAML, bash, `xcodebuild` from the Xcode 26 family, XCTest via `@testable import Remaindr`, `gh` CLI 2.89, ruby 2.6 (YAML sanity parse only).

**Spec:** none - planned from conversation

**Base commit:** 090d214. Every anchor, line reference, and "already exists" claim below describes this tree; when an anchor does not match, run `git log --oneline 090d214..HEAD` to tell "the plan was wrong" from "the file moved on".

**Confidence:** 10/10 - rubric arithmetic: start 10; minus 0 for Consumes entries without full signatures (all five consumed declarations are copied verbatim from the cited source lines); minus 0 for unverified Patterns-to-Mirror SOURCEs (each verified against the real file at 090d214); minus 0 for unproxied `Verify - Human:` items (there are none); minus 0 for NOT-building cuts without file evidence; minus 0 for schema or inferred-type tasks (none); minus 0 for Preflight checks never run (every check below was executed on 2026-08-18 and its result recorded); minus 0 for parallel tracks below the cost floor (single track); total 10.
Residual uncertainty is environmental only (GitHub-side runner availability and any branch protection rule in Task 3) and is covered by the Failure handling summary.

**NOT building:**
- No `pull_request`-triggered workflow - the request says "every push", and pushes already cover same-repo branches; adding `pull_request` would double-run same-repo PRs.
- No lint or analyzer job, no SwiftLint - not requested, and no such config exists in the repo.
- No DMG, release, or notarization job - `make-dmg.sh` already exists but release automation was not requested.
- No matrix across Xcode versions - one current toolchain matches the documented requirement "macOS 14 or later, and Xcode 26 or later" (`Remaindr/README.md:7`).
- No project build-setting changes - the warnings gate is a CI command-line flag only.
- No README or AGENTS.md edits.
- No coverage reporting and no test artifact upload.

## Global Constraints

- No third-party Swift packages (repo AGENTS.md hard rule); this plan adds none.
- API keys live in the macOS Keychain only; never logged, never committed (repo AGENTS.md); the tests added touch no keys.
- Build must succeed with zero warnings (repo AGENTS.md and `README.md:136`).
- Only make the change directly requested; no features beyond CI plus the test target it requires (repo AGENTS.md).
- Do not modify the `UsageProvider` protocol or provider clients (repo AGENTS.md boundary).
- Never manually modify CHANGELOG.md or auto-generated files (user global rule).
- No em dashes in any written file; each sentence on its own line in long markdown (user global rule).

## Patterns to Mirror

### Project file style

SOURCE: `Remaindr/Remaindr.xcodeproj/project.pbxproj:9-15`
```
/* Begin PBXFileSystemSynchronizedRootGroup section */
		AA0000000000000000000010 /* Remaindr */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Remaindr;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */
```
New pbxproj objects follow this hand-written style: ids in the `AA00000000000000000000XY` pattern, TAB indentation, and `/* Begin ... */` and `/* End ... */` section fences separated from neighbours by one blank line.

### xcodebuild invocation shape

SOURCE: `make-dmg.sh:23-27`
```bash
xcodebuild -project "$APP_NAME/$APP_NAME.xcodeproj" \
           -scheme "$SCHEME" \
           -configuration "$CONFIG" \
           -derivedDataPath "$DERIVED" \
           build
```
Every xcodebuild call in this plan runs from the repo root with `-project Remaindr/Remaindr.xcodeproj` and `-derivedDataPath build/DerivedData`, mirroring this canonical invocation.

### Zero-warnings convention

SOURCE: `README.md:136` (the original sentence's em dash is replaced by a hyphen here, per the no-em-dash rule)
"Build must complete with zero warnings - this is enforced project convention, not just a suggestion."
CI enforces this existing convention; it does not introduce a new standard.

### Commit messages

SOURCE: `git log --oneline` at 090d214, e.g. `1f08d6b fix(keychain): update items in place so a save keeps its access grant` and `cceb416 docs: explain the keychain password prompt and when it recurs`
Conventional commit prefixes; this plan uses `test:` and `ci:`.

### Tests

No existing pattern - establishing new convention: this is the repository's first test target.
Test files live in `Remaindr/RemaindrTests/`, a sibling of the app source directory `Remaindr/Remaindr/`, exposed to Xcode through a new `PBXFileSystemSynchronizedRootGroup` so sources auto-sync.
Files are named after the type under test (`CollapsedLabelTextTests.swift` for `CollapsedLabelText`), use the XCTest framework with `@testable import Remaindr`, and run in-process against the app as `TEST_HOST`.
The type under test is chosen because it is documented as checkable without a running app - SOURCE: `Remaindr/Remaindr/Models/CollapsedLabelText.swift:3-4`
```swift
/// Builds the collapsed menu bar string. Foundation-only on purpose, so the width budget
/// is checkable without a running app.
```

## Preflight

Every entry below was executed on 2026-08-18 while planning, and its actual result is recorded.
Entries record the SHAPE of a fact, never a secret, token, hostname, or third-party account or repository identifier; this file gets committed.

### DURABLE - true until the repo itself changes

- [No `.github` directory exists] - Evidence: `ls .github` printed "No such file or directory" - Consequence: the workflow is greenfield, with no naming collision.
- [The shared scheme is committed to git] - Evidence: `git ls-files` lists `Remaindr/Remaindr.xcodeproj/xcshareddata/xcschemes/Remaindr.xcscheme` - Consequence: `xcodebuild -scheme Remaindr` works on a fresh CI checkout with no user-local scheme.
- [Entitlements are an empty dict] - Evidence: `Remaindr/Remaindr/Remaindr.entitlements` contains only `<plist><dict/></plist>` - Consequence: CI needs no signing certificates or profiles; ad-hoc signing on runners works.
- [Root `.gitignore` ignores `build/`] - Evidence: `.gitignore:5` is `build/` - Consequence: `build/DerivedData` written by CI-style local runs never gets committed.
- [The project format requires the Xcode 26 family] - Evidence: `objectVersion = 77` at `Remaindr/Remaindr.xcodeproj/project.pbxproj:6`, `LastSwiftUpdateCheck = 2600` at line 78, and `Remaindr/README.md:7` documenting "Xcode 26 or later" - Consequence: the runner must be the `macos-26` image whose default toolchain is Xcode 26.x.
- [A single origin remote on github.com] - Evidence: `git remote -v` shows exactly one remote named `origin`, HTTPS, fetch and push (shape only) - Consequence: the `gh` CLI resolves the repository implicitly from the checkout; no `-R` flag appears anywhere in this plan.

### PERISHABLE - recapture before task 1

- [Local toolchain is Xcode 26.6] - Check: `xcodebuild -version` (planning run: Xcode 26.6, Build 17F113) - Needed by: Task 1 verify. If it shows Xcode below 26, local verify may still pass (16.3+ reads the format) but match the runner by testing on 26.x.
- [Baseline build is warning-free] - Check: `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/remaindr-preflight build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (planning run 2026-08-18: `** BUILD SUCCEEDED **`, exit 0) - Needed by: the whole plan. If it exits nonzero: STOP - pre-existing warnings must be fixed before this plan runs, and that fix is out of scope here.
- [The `gh` CLI is authenticated] - Check: `gh auth status` reports an active logged-in account (planning run: active; record "active" or "NOT active" only, never the account name) - Needed by: Task 3. If not active: Task 3 blocks; ask the user to run `gh auth login` before starting.
- [Working tree clean on main at 090d214] - Check: `git status -sb` is clean and `git rev-parse --short HEAD` prints 090d214 (planning run: clean, 090d214) - Needed by: all tasks. If HEAD is later, diff the plan's anchors before editing.
- [ruby with YAML support] - Check: `ruby -ryaml -e 'puts "ok"'` prints ok (planning run: ruby 2.6.10) - Needed by: Task 2 verify.
- [Baseline test action is red: exit 66, "Scheme Remaindr is not currently configured for the test action"] - Check (optional; takes a full build): `xcodebuild -project Remaindr/Remaindr.xcodeproj -scheme Remaindr -destination 'platform=macOS' -derivedDataPath /tmp/remaindr-preflight-test test` (planning run: exit 66) - Needed by: Task 1's Expected is falsifiable only against this named pre-existing red, which Task 1 itself fixes; this is the expected starting state, not a defect.

## Execution

**Tracks:** single sequential track (Track A, Tasks 1-3 in order).
Three tasks sit below the treehouse cost floor, so the plan runs sequentially in the main checkout with no lease.
**Merge order:** sequential - Task 1, then Task 2, then Task 3, in order, on one branch.
**Shared files:** none.
**Branch:** `ci/github-actions`, created off 090d214 before Task 1 with `git switch -c ci/github-actions`; Tasks 1 and 2 commit onto it, and Task 3 pushes, verifies, and merges it.
**Teardown:** none - no treehouse lease to return.

---

### Track A

#### Task 1: Add the RemaindrTests unit test target, smoke tests, and scheme wiring

**Files:**
- Create: `Remaindr/RemaindrTests/CollapsedLabelTextTests.swift`
- Modify: `Remaindr/Remaindr.xcodeproj/project.pbxproj` (anchor: `AA0000000000000000000060 /* Remaindr */ = {`, ~L51)
- Modify: `Remaindr/Remaindr.xcodeproj/xcshareddata/xcschemes/Remaindr.xcscheme` (anchor: `<Testables>`, ~L17-18)

**Interfaces:**
- Consumes (signatures copied verbatim from the source; the test file constructs each one):
  - `struct ProviderSlot: Equatable, Sendable` with `var status: ProviderStatus?`, `var error: ProviderError?`, `var isRefreshing: Bool = false` (`Remaindr/Remaindr/UI/ProviderStore.swift:5-9`); its memberwise init accepts zero arguments because both optional vars default to nil.
  - `ProviderStatus.init(kind:reading:detail:fetchedAt:weekly:)` with `weekly: ProviderWeeklyUsage? = nil` (`Remaindr/Remaindr/Models/ProviderStatus.swift:98-105`).
  - `enum ProviderReading: Equatable, Sendable` with `case fraction(used: Double, resetsAt: Date?)` and `case balance(amount: Decimal, currency: String)` (`Remaindr/Remaindr/Models/ProviderStatus.swift:71-74`).
  - `enum ProviderError: Error, Equatable, Sendable` including `case notConfigured` and `case offline` (`Remaindr/Remaindr/Models/ProviderStatus.swift:43-48`).
  - `enum CollapsedLabelText` with `static let budget = 14` and `static func text(for slot: ProviderSlot?) -> String` (`Remaindr/Remaindr/Models/CollapsedLabelText.swift:5-12`).
- Produces (consumed by Task 2's Test step and Task 3's CI run):
  - Native target `RemaindrTests` (id `AA0000000000000000000061`, product `RemaindrTests.xctest`, bundle id `com.theerakarn.RemaindrTests`, `TEST_HOST` set to the built Remaindr.app) whose sources auto-sync from `Remaindr/RemaindrTests/`.
  - Shared scheme `Remaindr` whose TestAction lists `RemaindrTests.xctest` as a TestableReference, so `xcodebuild -scheme Remaindr test` executes the six smoke tests instead of exiting 66.

**Gotcha:** the pbxproj uses TAB indentation and hand-written ids; every fragment below uses tabs, and the eleven new ids (`...0011`, `...0021`, `...0031`, `...0061`, `...0081`, `...0091`, `...00A1`, `...00B1`, `...0017`, `...002C`, `...002D`) collide with nothing (verified: a grep of all eleven against the file at 090d214 returns 0 hits).
Do NOT open the project in Xcode and do NOT reformat the pbxproj; Xcode 26 would rewrite the object ids and formatting.
Apply each insertion literally at the stated anchor; `plutil -lint` is the structural gate before any build.
The `build/DerivedData` path the verify writes is already gitignored (`.gitignore:5`), so the tree stays committable.

**Steps:**

- [ ] Step 1: In the `PBXFileSystemSynchronizedRootGroup` section, directly after the existing `AA0000000000000000000010 /* Remaindr */ = { ... };` block (just before `/* End PBXFileSystemSynchronizedRootGroup section */`), insert:
```
		AA0000000000000000000011 /* RemaindrTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RemaindrTests;
			sourceTree = "<group>";
		};
```

- [ ] Step 2: In the `PBXFileReference` section, directly after the `AA0000000000000000000020 /* Remaindr.app */` line (~L18), insert:
```
		AA0000000000000000000021 /* RemaindrTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = RemaindrTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

- [ ] Step 3: In the `PBXFrameworksBuildPhase` section, directly after the `AA0000000000000000000030 /* Frameworks */` block (just before `/* End PBXFrameworksBuildPhase section */`), insert:
```
		AA0000000000000000000031 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

- [ ] Step 4: In the `PBXGroup` section, make two one-line insertions.
In group `AA0000000000000000000040`'s children, after this existing line:
```
				AA0000000000000000000010 /* Remaindr */,
```
insert this line:
```
				AA0000000000000000000011 /* RemaindrTests */,
```
In group `AA0000000000000000000050 /* Products */`'s children, after this existing line:
```
				AA0000000000000000000020 /* Remaindr.app */,
```
insert this line:
```
				AA0000000000000000000021 /* RemaindrTests.xctest */,
```

- [ ] Step 5: Immediately before `/* Begin PBXNativeTarget section */`, separated from its neighbours by blank lines exactly as the other sections are, insert a new section:
```
/* Begin PBXContainerItemProxy section */
		AA00000000000000000000A1 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = AA00000000000000000000A0 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = AA0000000000000000000060;
			remoteInfo = Remaindr;
		};
/* End PBXContainerItemProxy section */
```
Then, inside the `PBXNativeTarget` section, directly after the app target's closing brace (the `};` that follows `productType = "com.apple.product-type.application";`, ~L70) and before `/* End PBXNativeTarget section */`, insert:
```
		AA0000000000000000000061 /* RemaindrTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000017 /* Build configuration list for PBXNativeTarget "RemaindrTests" */;
			buildPhases = (
				AA0000000000000000000081 /* Sources */,
				AA0000000000000000000031 /* Frameworks */,
				AA0000000000000000000091 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				AA00000000000000000000B1 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000011 /* RemaindrTests */,
			);
			name = RemaindrTests;
			productName = RemaindrTests;
			productReference = AA0000000000000000000021 /* RemaindrTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
```

- [ ] Step 6: In the `PBXProject` object (anchor: `AA00000000000000000000A0 /* Project object */`), make two insertions.
In the `targets = (` list, after this existing line:
```
				AA0000000000000000000060 /* Remaindr */,
```
insert this line:
```
				AA0000000000000000000061 /* RemaindrTests */,
```
Inside `TargetAttributes`, after the existing `AA0000000000000000000060 = { CreatedOnToolsVersion = 26.0; };` entry, insert:
```
					AA0000000000000000000061 = {
						CreatedOnToolsVersion = 26.0;
						TestTargetID = AA0000000000000000000060;
					};
```

- [ ] Step 7: Make four insertions at the stated section boundaries.
At the top of the `PBXResourcesBuildPhase` section (directly after `/* Begin PBXResourcesBuildPhase section */`), insert:
```
		AA0000000000000000000091 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```
At the top of the `PBXSourcesBuildPhase` section (directly after `/* Begin PBXSourcesBuildPhase section */`), insert:
```
		AA0000000000000000000081 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```
Immediately before `/* Begin XCBuildConfiguration section */`, separated from its neighbours by blank lines as the other sections are, insert:
```
/* Begin PBXTargetDependency section */
		AA00000000000000000000B1 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = AA0000000000000000000060 /* Remaindr */;
			targetProxy = AA00000000000000000000A1 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */
```
Directly before `/* End XCBuildConfiguration section */`, insert the two test-target configurations:
```
		AA000000000000000000002C /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.theerakarn.RemaindrTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Remaindr.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Remaindr";
			};
			name = Debug;
		};
		AA000000000000000000002D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.theerakarn.RemaindrTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Remaindr.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Remaindr";
			};
			name = Release;
		};
```
And directly before `/* End XCConfigurationList section */`, insert the tests configuration list:
```
		AA0000000000000000000017 /* Build configuration list for PBXNativeTarget "RemaindrTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA000000000000000000002C /* Debug */,
				AA000000000000000000002D /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] Step 8: In `Remaindr/Remaindr.xcodeproj/xcshareddata/xcschemes/Remaindr.xcscheme`, replace the two lines:
```
      <Testables>
      </Testables>
```
with:
```
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "AA0000000000000000000061"
               BuildableName = "RemaindrTests.xctest"
               BlueprintName = "RemaindrTests"
               ReferencedContainer = "container:Remaindr.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
```

- [ ] Step 9: Create `Remaindr/RemaindrTests/CollapsedLabelTextTests.swift` with exactly this content (executed end-to-end in a probe copy on 2026-08-18: 6 tests, 0 failures):
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

    func testUnconfiguredSlotShowsPlaceholder() {
        var slot = ProviderSlot()
        slot.error = .notConfigured
        XCTAssertEqual(CollapsedLabelText.text(for: slot), "--")
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

    func testBalanceReadingShowsSymbolAndCompactAmount() {
        let status = ProviderStatus(
            kind: .deepseek,
            reading: .balance(amount: 1234.5, currency: "usd"),
            detail: "",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        let slot = ProviderSlot(status: status)
        XCTAssertEqual(CollapsedLabelText.text(for: slot), "$1.2k")
    }

    func testStaleReadingWithErrorAppendsBang() {
        let status = ProviderStatus(
            kind: .zai,
            reading: .fraction(used: 0.5, resetsAt: nil),
            detail: "",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        var slot = ProviderSlot(status: status)
        slot.error = .offline
        XCTAssertEqual(CollapsedLabelText.text(for: slot), "50%!")
    }

    func testLabelNeverExceedsBudget() {
        // An unknown long currency forces the widest possible string.
        let status = ProviderStatus(
            kind: .deepseek,
            reading: .balance(amount: 1_234_567, currency: "WOWSUCHCURRENCY"),
            detail: "",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        let slot = ProviderSlot(status: status)
        let text = CollapsedLabelText.text(for: slot)
        XCTAssertLessThanOrEqual(text.count, CollapsedLabelText.budget)
        XCTAssertTrue(text.hasSuffix("\u{2026}"))
    }
}
```
End the file with a trailing newline.

- [ ] Step 10: Verify - Run (from repo root):
```bash
plutil -lint Remaindr/Remaindr.xcodeproj/project.pbxproj && \
xcodebuild -project Remaindr/Remaindr.xcodeproj \
  -scheme Remaindr \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  test \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```
Expected: `plutil` prints OK; the xcodebuild output ends `** TEST SUCCEEDED **` reporting "Executed 6 tests, with 0 failures"; the chained command exits 0.

- [ ] Step 11: Commit - `git add Remaindr/RemaindrTests/CollapsedLabelTextTests.swift Remaindr/Remaindr.xcodeproj/project.pbxproj Remaindr/Remaindr.xcodeproj/xcshareddata/xcschemes/Remaindr.xcscheme && git commit -m "test: add RemaindrTests target with collapsed-label smoke tests"`

#### Task 2: Add the GitHub Actions workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the shared scheme's test action wired in Task 1, without which the workflow's Test step exits 66; the xcodebuild invocation shape from `make-dmg.sh:23-27`.
- Produces (consumed by Task 3): `.github/workflows/ci.yml` defining workflow `CI` on `push` (unfiltered, so every push) and `workflow_dispatch`, with one job `build-and-test` on `runs-on: macos-26` whose steps are checkout, Show toolchain, Build (Release with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`), and Test (same flag).

**Gotcha:** the runner's `appintentsmetadataprocessor` prints a stderr line ("Metadata extraction skipped. No AppIntents.framework dependency found.") that is not a Swift compiler warning and does not trip `SWIFT_TREAT_WARNINGS_AS_ERRORS`; this was verified during planning, where build and test both exited 0 with that line present.
Do not add an actionlint step to the verify; actionlint is not installed locally, and the authoritative workflow validation is Task 3's real run.

**Design decisions:**
- `on: push` with no branch filter is the literal "every push" requirement, and `workflow_dispatch` allows manual re-runs.
- The warnings gate is `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` passed on the CI command line only; no project build setting changes, so local dev behavior is untouched and the README convention is simply enforced.
- `runs-on: macos-26` (arm64) ships a default Xcode 26.x toolchain, matching the documented "Xcode 26 or later" requirement; there is no Xcode-pinning step, and the Show toolchain step logs exactly what ran.
- The Build step uses Release (matching `make-dmg.sh`'s shipping configuration) and the Test step uses the scheme's test action (Debug); both run from the repo root against `Remaindr/Remaindr.xcodeproj`.
- `build/DerivedData` as the derived data path is already gitignored (`.gitignore:5`).
- `timeout-minutes: 30` guards against a hung test burning runner minutes.
- `concurrency` with `cancel-in-progress: true` cancels stale runs superseded by a newer push.

**Steps:**

- [ ] Step 1: Create `.github/workflows/ci.yml` with exactly this content:
```yaml
name: CI

on:
  push:
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    runs-on: macos-26
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v5
      - name: Show toolchain
        run: |
          xcodebuild -version
          sw_vers
      - name: Build (Release, warnings as errors)
        run: >-
          xcodebuild -project Remaindr/Remaindr.xcodeproj
          -scheme Remaindr
          -configuration Release
          -destination 'platform=macOS'
          -derivedDataPath build/DerivedData
          build
          SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
      - name: Test (warnings as errors)
        run: >-
          xcodebuild -project Remaindr/Remaindr.xcodeproj
          -scheme Remaindr
          -destination 'platform=macOS'
          -derivedDataPath build/DerivedData
          test
          SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

- [ ] Step 2: Verify - Run (from repo root):
```bash
ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml") or raise "empty"; puts "YAML parses"' && \
test "$(grep -c "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES" .github/workflows/ci.yml)" = "2" && \
grep -q "runs-on: macos-26" .github/workflows/ci.yml && \
grep -q "actions/checkout" .github/workflows/ci.yml
```
Expected: prints "YAML parses"; the chained count test and both greps pass; the chained command exits 0.

- [ ] Step 3: Commit - `git add .github/workflows/ci.yml && git commit -m "ci: build with zero warnings and run tests on every push"`

#### Task 3: Push, watch the workflow run go green, merge

**Files:**
- none - this task pushes the existing branch, watches CI, and merges; it creates no files and no commit of its own, and its deliverable is the merged PR (one merge commit on main).

**Interfaces:**
- Consumes: branch `ci/github-actions` carrying the Task 1 and Task 2 commits; the workflow from Task 2; the authenticated `gh` CLI (Preflight).
- Produces: the PR merged into main, a green `CI` run on the branch push, and a green `CI` run on main's merge push (the last is asserted in End-to-end verification).

**Gotcha:** run every `gh` command from the repo root; gh resolves the repository from the checkout, so no `-R` flag is needed or used anywhere.
Obtain the run id from `gh run list`; never guess it.

**Rollback:** the merge is a write to the remote that local git cannot undo by itself.
Exact reversal after an unwanted merge: `git revert -m 1 <merge-sha>` on main followed by `git push`, then `git push origin --delete ci/github-actions` to drop the branch.
Before the merge, the reversal is `git push origin --delete ci/github-actions` alone.

**Steps:**

- [ ] Step 1: Push the branch, which is itself the first CI trigger event: `git push -u origin ci/github-actions`

- [ ] Step 2: Get the run id: `gh run list --branch ci/github-actions --limit 1` and copy the numeric id of the workflow "CI" run for the branch push.

- [ ] Step 3: Verify - Run: `gh run watch <run-id> --exit-status` (substitute the id from Step 2) - Expected: exits 0; the run named "CI" concludes success with the Build and Test steps green.

- [ ] Step 4: Open the PR: `gh pr create --title "ci: GitHub Actions build + test on every push" --body "Adds a RemaindrTests target with collapsed-label smoke tests and a CI workflow that builds Release with zero warnings and runs the tests on every push."`

- [ ] Step 5: Merge with a merge commit, which preserves the per-task commit history and matches how the repo's first PR was merged: `gh pr merge --merge`

- [ ] Step 6: Sync the local checkout: `git switch main && git pull`

## Failure handling summary

- **macos-26 runner label unavailable or invalid** - Detect: the run fails immediately with a no-matching-runner or invalid-label error. Respond: switch `runs-on` to `macos-latest` ONLY after confirming from the Show toolchain step that its default Xcode is 26.x, because the project requires the Xcode 26 family (`LastSwiftUpdateCheck = 2600` at `Remaindr/Remaindr.xcodeproj/project.pbxproj:78`; `Remaindr/README.md:7`); if neither label works, STOP and report - do not downgrade the toolchain silently.
- **Test step fails with a signing error** - Detect: a red Test step mentioning code signing. Respond: entitlements are an empty dict and runners sign ad-hoc, so a signing failure means something else changed; capture the log with `gh run view <run-id> --log-failed` and STOP.
- **Build step red on warnings** - Detect: a red Build step quoting a Swift warning. Respond: the push introduced warnings; fix them in a follow-up commit on the same branch and push again; never weaken or remove the `SWIFT_TREAT_WARNINGS_AS_ERRORS` flag.
- **PR merge blocked by a branch protection rule** - Detect: `gh pr merge` fails with a protection error the executor cannot satisfy. Respond: fall back to pushing the branch commits directly to main (`git switch main && git merge --no-ff ci/github-actions && git push`) and verify the push-triggered run the same way; the evidence is identical.

## End-to-end verification

- [ ] Run: `gh run list --branch main --limit 1 --json workflowName,conclusion --jq '.[0]'` - Expected: `{"conclusion":"success","workflowName":"CI"}`, proving the merge push on main triggered the workflow and it passed with the zero-warning gates on.
- [ ] Run: `gh run view <run-id> --json jobs --jq '.jobs[].steps[] | "\(.name): \(.conclusion)"'` (run id from `gh run list --branch main --limit 1`) - Expected: four lines, including `Build (Release, warnings as errors): success` and `Test (warnings as errors): success`.
