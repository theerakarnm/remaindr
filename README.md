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
- 🔒 **Keychain-backed credentials** — API keys are never stored in plaintext or in `UserDefaults`
- ⚠️ **Graceful degradation** — if one provider fails or is unconfigured, the other two keep working; failures show a stale value plus an error indicator, never a fake zero
- 🚀 **Launch at login** — optional
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

> Not notarized/signed yet during early development — macOS Gatekeeper may warn on first launch. Right-click → Open to bypass, or build from source.

## Setup

1. Click the menu bar icon → **Settings**.
2. For each provider you want to track, paste the API key. Keys are written straight to the Keychain — nothing is saved until you do this.
3. Choose which provider drives the collapsed menu bar label (default: whichever is closest to its limit).
4. Set your refresh interval (default: 5 minutes).
5. Optionally enable **Launch at Login**.

Providers with no key configured simply show "Not configured" and are skipped on refresh — you don't need all three set up to use the app.

## Usage

- **Click the menu bar icon** to open the dropdown and see all three providers: current value, a progress bar or balance figure, and when each was last refreshed.
- **Collapsed label** shows a compact summary (icon + short string) so you can see your most-constrained provider without opening the dropdown.
- **Manual refresh** is available from the dropdown if you don't want to wait for the timer.
- **Errors** (expired key, rate limited, offline) show inline next to the affected provider — the other providers are unaffected.

## Privacy & security

- API keys are stored exclusively in the macOS Keychain, scoped to this app.
- No usage data, keys, or telemetry are sent anywhere except directly to each provider's own API, using your own key.
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
  Keychain/
    KeychainStore.swift   # read/write wrapper, no plaintext fallback
  UI/
    MenuBarLabel.swift     # collapsed label view
    DropdownPanel.swift    # per-provider rows
    SettingsView.swift     # keys, refresh interval, launch-at-login
  Refresh/
    RefreshScheduler.swift
```

See [`CLAUDE.md`](./CLAUDE.md) for the fuller architectural rules this project is built against (provider protocol boundaries, Keychain-only rule, etc.) — useful context whether you're a human contributor or an AI coding assistant.

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

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Claude shows "Not configured" | No `~/.claude/projects/` logs found and no API/admin key set |
| A provider shows a stale value with a warning icon | Last refresh failed (network, 401, 429) — check the key or your connection |
| Collapsed label missing | No provider is currently selected to drive it, or all providers are unconfigured |
| App doesn't appear in Dock | Expected — this is a menu-bar-only (`LSUIElement`) app by design |

## Roadmap

- [ ] Notarized, signed release build
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
