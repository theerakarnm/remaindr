# Remaindr

A macOS menu bar utility that shows your remaining usage and balance across three AI providers at a glance — **Claude**, **z.ai (GLM)**, and **DeepSeek** — without opening a browser or a dashboard.

<!-- ![Menu bar screenshot](docs/screenshot.png) -->

---

## Table of Contents

- [Why](#why)
- [Features](#features)
- [How each provider is measured](#how-each-provider-is-measured)
- [Requirements](#requirements)
- [Installation](#installation)
- [Setup](#setup)
- [Usage](#usage)
- [Privacy & security](#privacy--security)
- [Project structure](#project-structure)
- [Building from source](#building-from-source)
- [Releasing](#releasing)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [Renaming](#renaming)
- [Contributing](#contributing)
- [License](#license)

---

## Why

If you're paying for or metering usage across multiple AI providers, checking "how much do I have left" usually means three different tabs, three different logins, and three different mental models of what "usage" even means. Remaindr puts all three in one menu bar dropdown, refreshed on a timer, with no dashboard required.

## Features

- 🖥️ **Native menu bar app** — SwiftUI `MenuBarExtra`, no Dock icon, no separate window unless you open Settings
- 📊 **One row per provider** — Claude, z.ai (GLM), DeepSeek — each rendered according to what that provider actually reports
- 🔁 **Auto-refresh** — configurable interval (1–60 min), plus manual refresh
- 🔒 **Config-file credentials** - API keys live in `~/.remaindr/setting.json` (0700 directory, 0600 file), never in `UserDefaults`
- ⚠️ **Graceful degradation** — if one provider fails or is unconfigured, the other two keep working; failures show a stale value plus an error indicator, never a fake zero
- 🚀 **Launch at login** — optional
- 🆕 **Update check** — compares the running version against the latest GitHub release once a day and links to the release page; it never downloads or installs anything
- 🪶 **Zero third-party dependencies**

## How each provider is measured

The three providers don't expose usage the same way, so Remaindr doesn't force them into one shape:

| Provider | What's shown | Source |
|---|---|---|
| **Claude** | Usage within the current rolling 5-hour block | Local `~/.claude/projects/**/*.jsonl` session logs (primary). Falls back to `anthropic-ratelimit-*` response headers or the Admin usage endpoint if an API/admin key is configured. Shows "Not configured" if neither is available — never a fabricated number. |
| **z.ai (GLM)** | Quota remaining | z.ai's usage/quota endpoint (requires API key) |
| **DeepSeek** | Account balance | `GET /user/balance` — shows `total_balance` per currency (requires API key) |

Claude has no public "remaining subscription quota" API, so its number is an estimate derived from local logs unless you supply an API/admin key for a more authoritative header-based reading. This is a known limitation, not a bug.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+ (to build from source)
- Optional, per provider you want live data from:
  - Anthropic API key or Admin key (Claude fallback/verification)
  - z.ai API key
  - DeepSeek API key

## Installation

1. Download the latest release from the [Releases](../../releases) page, **or** build from source (see below).
2. Move `Remaindr.app` to `/Applications`.
3. Launch it — a new icon appears in your menu bar.

> The release pipeline signs the DMG with a Developer ID certificate, has Apple notarize it,
> and staples the ticket, so a release built through it opens with an ordinary double-click.
> There is no Gatekeeper workaround to perform and none is supported: if macOS refuses to
> open such a download, the artifact is wrong, not the warning. Verify it (below), then open
> an issue.
>
> No release has gone through that pipeline yet, because it needs a Developer ID certificate
> that does not exist yet (see the Roadmap).
>
> A release that ships a `.sha256` sidecar came from this pipeline. The older `v1.0.0`
> asset predates it and is neither notarized nor checksummed - build from source rather
> than using it.

### Opening an un-notarized build

Every release published so far is an un-notarized pre-release (no `.sha256` sidecar, see
below) because the Developer ID certificate the signing pipeline needs does not exist yet.
Gatekeeper will refuse to open one on first launch, and on macOS Sequoia and later that
dialog has no inline "Open Anyway" button - only a path through **System Settings → Privacy
& Security**.

An equally valid alternative, and the one many free/open-source Mac apps document for
exactly this situation, is to strip the quarantine flag Gatekeeper is reacting to before the
first launch:

```bash
xattr -cr /Applications/Remaindr.app
```

Run it once, from Terminal, after moving the app to `/Applications` and before opening it.
This does not disable Gatekeeper system-wide and does not touch any other app - it removes
the `com.apple.quarantine` attribute macOS attached to this one download, so Gatekeeper has
nothing to flag on that binary and no dialog appears at all.

This instruction applies only to un-notarized pre-releases. Once a release goes through the
notarized pipeline (ships a `.sha256` sidecar), it opens with an ordinary double-click and
this step is unnecessary - see "Verifying your download" below.

### Verifying your download

Every notarized release publishes `Remaindr-<version>.dmg` together with `Remaindr-<version>.dmg.sha256`.
A release without the sidecar is an un-notarized pre-release: expect Gatekeeper to block its first open - see "Opening an un-notarized build" above for how to run it anyway, or build from source instead.
For a notarized release, download both into the same folder, then:

```bash
shasum -a 256 -c Remaindr-<version>.dmg.sha256
spctl --assess --type open --context context:primary-signature -vv Remaindr-<version>.dmg
```

The first command must print `Remaindr-<version>.dmg: OK`.
The second must print `accepted` together with `source=Notarized Developer ID`.
Anything else - a checksum mismatch, `rejected`, or a missing signature - means the file is
not the one that was published.
Delete it and download again rather than opening it.

## Setup

1. Click the menu bar icon → **Settings**.
2. For each provider you want to track, paste the API key.
   Keys are written to `~/.remaindr/setting.json` (mode 0600, inside a 0700 directory) - nothing is saved until you do this.
3. For Claude's exact plan-limit numbers, click **Connect** once.
   macOS may ask for the login keychain password (at most twice); after that the app uses the saved token.
4. Choose which provider drives the collapsed menu bar label (default: whichever is closest to its limit).
5. Set your refresh interval (default: 5 minutes).
6. Optionally enable **Launch at Login**.

Providers with no key configured simply show "Not configured" and are skipped on refresh — you don't need all three set up to use the app.

## Usage

- **Click the menu bar icon** to open the dropdown and see all three providers: current value, a progress bar or balance figure, and when each was last refreshed.
- **Collapsed label** shows a compact summary (icon + short string) so you can see your most-constrained provider without opening the dropdown.
- **Manual refresh** is available from the dropdown if you don't want to wait for the timer.
- **Errors** (expired key, rate limited, offline) show inline next to the affected provider — the other providers are unaffected.

## Privacy & security

- API keys and the Claude OAuth token are stored in `~/.remaindr/setting.json` only: directory mode 0700, file mode 0600.
  The trade is explicit: a process running as your user can read that file, where the keychain ACL previously gated reads behind a prompt - accepted in exchange for zero periodic keychain prompts.
- No usage data, keys, or telemetry are sent anywhere except directly to each provider's own API, using your own key.
- The update check is a single unauthenticated `GET` to `api.github.com` that sends no key, no account identifier, and no usage data (only the default `URLSession` user agent, which carries the app and OS version); the download link it shows is a fixed URL compiled into the app, never one read out of the response.
- Claude's local-log reading only parses token counts and timestamps from `~/.claude/projects/` — it does not read prompt or response content.
- No analytics, no crash reporting, no third-party SDKs.

## Project structure

```
Remaindr/
  App/                   # App entry point, MenuBarExtra scene
  Providers/
    UsageProvider.swift   # shared protocol every provider implements
    ClaudeProvider.swift
    ZAIProvider.swift
    DeepSeekProvider.swift
  Models/
    ProviderStatus.swift  # common status struct returned by every provider
    SettingStore.swift    # owns ~/.remaindr/setting.json
  Keychain/
    ClaudeCodeCredential.swift  # the one Keychain read (Claude Connect)
  Update/
    AppVersion.swift      # dotted version parse + compare
    UpdateChecker.swift   # latest GitHub release lookup
    UpdateStore.swift     # observable state + once-a-day throttle
    UpdateStatusText.swift # the exact strings the UI renders
  UI/
    MenuBarLabel.swift     # collapsed label view
    DropdownPanel.swift    # per-provider rows
    SettingsView.swift     # keys, refresh interval, launch-at-login
  Refresh/
    RefreshScheduler.swift
```

See [`CLAUDE.md`](./CLAUDE.md) for the fuller architectural rules this project is built against (provider protocol boundaries, the setting.json credential rule, etc.) - useful context whether you're a human contributor or an AI coding assistant.

## Building from source

```bash
git clone https://github.com/<your-org>/Remaindr.git
cd Remaindr
open Remaindr.xcodeproj   # or .xcworkspace, depending on setup
```

Build and run from Xcode (⌘R), or from the command line:

```bash
xcodebuild -scheme Remaindr build
```

Build must complete with zero warnings — this is enforced project convention, not just a suggestion.

## Releasing

Releases are cut by pushing a version tag; GitHub Actions does everything else.
The workflow (`.github/workflows/release.yml`) first builds and tests with warnings as errors, the same gate as CI.
It then runs `make-dmg.sh`, and what gets published depends on whether the signing secrets below are configured.

With signing configured, the DMG is Developer ID signed, notarized, stapled, and checksummed before anything is published, and the release carries `Remaindr-<version>.dmg` together with its `.sha256` sidecar.
Without signing secrets, the same tag push still publishes the DMG, but as a **pre-release** whose notes say it is un-notarized, and without the sidecar.
A `.sha256` sidecar therefore stays the marker of a release that went through the full pipeline.
Marking un-notarized builds as pre-releases also keeps the in-app update check pointing only at notarized releases, because it skips pre-releases just like GitHub's `releases/latest` does.

```bash
# Bump MARKETING_VERSION in the Xcode project first; tag and version must match.
git tag v1.2.3
git push origin v1.2.3
```

The workflow refuses a tag that does not match `MARKETING_VERSION`.
With signing configured it also refuses to finish on any build that is not notarized.

### One-time setup: repository secrets

Configure five secrets under *Settings → Secrets and variables → Actions* to switch tag pushes from un-notarized pre-releases to fully notarized releases.
Until they exist, the workflow publishes the ad-hoc signed DMG as a pre-release and skips the signing steps entirely.

| Secret | Value |
| --- | --- |
| `MACOS_SIGNING_P12_BASE64` | Your Developer ID Application identity exported as `.p12`, then base64: `base64 -i identity.p12 \| pbcopy` |
| `MACOS_SIGNING_P12_PASSWORD` | The password you set on that `.p12` export |
| `ASC_NOTARY_KEY_P8_BASE64` | An App Store Connect API key (Developer role or higher) `.p8`, then base64: `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` |
| `ASC_NOTARY_KEY_ID` | That key's 10-character ID |
| `ASC_NOTARY_ISSUER_ID` | The issuer UUID shown on the same page |

Export the `.p12` from Keychain Access by selecting the identity under *My Certificates*.
Make sure the `Developer ID Certification Authority` intermediate is present in the keychain so the exported chain is complete; an incomplete chain makes notarization reject the build.

The signing identity and the notary profile live only in a temporary keychain on an ephemeral runner and are deleted when the job ends.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Claude shows "Not configured" | No `~/.claude/projects/` logs found and no API/admin key set |
| A provider shows a stale value with a warning icon | Last refresh failed (network, 401, 429) — check the key or your connection |
| Collapsed label missing | No provider is currently selected to drive it, or all providers are unconfigured |
| Claude shows Reconnect Claude in Settings | The saved token expired and re-reading it did not help - see below |
| App doesn't appear in Dock | Expected — this is a menu-bar-only (`LSUIElement`) app by design |
| "Remaindr" Not Opened / Apple could not verify | Un-notarized pre-release - run `xattr -cr /Applications/Remaindr.app` once, see [Opening an un-notarized build](#opening-an-un-notarized-build) |

### Reconnecting Claude

Remaindr shows **Reconnect Claude in Settings** when the saved OAuth token was
rejected and the single automatic retry after Connect did not help.
To fix it: open Claude Code (run `claude` and sign in) so it writes a fresh
credential, then click **Connect** again in Remaindr's Settings.
At most one login-keychain password prompt appears per Connect, twice at most
in the failure case.

Versions before the setting.json change stored keys in the login keychain; open
Keychain Access to delete the old items (service `com.theerakarn.Remaindr`).
Those items are no longer read by this app.

## Roadmap

- [x] Notarized, stapled, checksummed release pipeline in `make-dmg.sh` - the first notarized *release* still needs a Developer ID certificate
- [ ] Additional providers (OpenAI, Gemini, etc.) via the existing `UsageProvider` protocol
- [ ] Historical usage graph
- [ ] Optional notifications when a provider crosses a usage threshold

## Renaming

The app name is `Remaindr`. To rename:

1. Update the Xcode project/target name and bundle identifier.
2. Search the codebase for `Remaindr` and replace with the new name.
3. Update this README and `CLAUDE.md`.

## Contributing

Issues and PRs are welcome. Please keep provider clients behind the `UsageProvider` protocol and avoid adding third-party dependencies — see `CLAUDE.md` for the full constraints this project follows.

## License

MIT — see [`LICENSE`](./LICENSE).
