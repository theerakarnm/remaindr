# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

**AIUsageBar** — a macOS menu bar utility (SwiftUI `MenuBarExtra`) that shows remaining usage/quota for three AI providers at a glance: Claude, z.ai (GLM), and DeepSeek. Lives permanently in the menu bar (`LSUIElement`, no Dock icon). Rename freely if a different app name is chosen later — search for `AIUsageBar` across the project when renaming.

## Stack

- Swift 6, SwiftUI, macOS 14+ (Sonoma)
- `MenuBarExtra` with `.menuBarExtraStyle(.window)`
- `URLSession` + `async/await` for networking — no third-party packages
- Keychain Services (via `Security` framework) for credential storage
- No backend, no analytics, no telemetry

## Architecture

```
AIUsageBar/
  App/                  # App entry point, MenuBarExtra scene
  Providers/
    UsageProvider.swift  # protocol all providers conform to
    ClaudeProvider.swift
    ZAIProvider.swift
    DeepSeekProvider.swift
  Models/
    ProviderStatus.swift # shared status struct returned by every provider
  Keychain/
    KeychainStore.swift  # read/write wrapper, no plaintext fallback
  UI/
    MenuBarLabel.swift    # collapsed label view
    DropdownPanel.swift   # per-provider rows
    SettingsView.swift    # keys, refresh interval, launch-at-login
  Refresh/
    RefreshScheduler.swift
```

Every provider client sits behind the `UsageProvider` protocol and returns a common `ProviderStatus`. The UI layer never talks to a provider directly — only through the protocol. This is what lets a fourth provider be added later without touching UI code. Do not weaken this boundary.

## Provider data — do not treat these as symmetric

- **Claude** — no stable public "remaining subscription limit" endpoint.
  1. Primary: parse local session files at `~/.claude/projects/**/*.jsonl`, aggregate token usage into rolling 5-hour blocks (ccusage-style).
  2. Fallback: if an API key is present, read `anthropic-ratelimit-*` response headers from a cheap request, or the Admin usage endpoint if an admin key is configured.
  3. If neither is available: render "Not configured." Never fabricate a number.
- **z.ai (GLM)** — has a quota/usage endpoint, but verify the exact path and response shape against current z.ai docs before writing or editing this client. Do not carry over an endpoint from memory or from a prior session without re-checking.
- **DeepSeek** — `GET https://api.deepseek.com/user/balance`, Bearer auth, returns `balance_infos[]` with `currency`, `total_balance`, `granted_balance`, `topped_up_balance`. Displays remaining balance, not a usage percent — don't try to normalize it into the same shape as the other two.

## Hard rules

- API keys live in the macOS Keychain only. Never `UserDefaults`, never plaintext, never logged, never committed.
- No third-party Swift packages. If one seems genuinely needed, stop and ask before adding it.
- One provider failing must never blank or zero out the others. Show a stale value plus a visible error indicator instead.
- Never invent an endpoint path, field name, or response shape you haven't verified. If you can't verify something, implement it against a clearly marked assumption and flag it rather than guessing silently.
- Collapsed menu bar label stays compact (~14 characters) regardless of how many providers are active — it must never push other menu bar items off screen.
- Only make the change directly requested in a given task. Do not add features, abstractions, onboarding flows, or files beyond what was asked.

## Stop and ask before

- Adding any dependency or Swift package
- Requesting any entitlement beyond outgoing network + Keychain access
- Making a live API call that consumes real tokens/credits during testing
- Changing the `UsageProvider` protocol shape (affects all three clients at once)
- Touching files outside this project directory

## Commands

```bash
xcodebuild -scheme AIUsageBar build      # build
xcodebuild -scheme AIUsageBar test       # run tests, if/when added
```

Build must succeed with zero warnings before a task is considered done.

## Session hygiene

- New unrelated task → new session, don't carry stale context forward.
- Prefer `/compact` around 50% context usage, not near the limit.
- For multi-file or multi-step work, front-load scope and acceptance criteria in the first message rather than correcting mid-session.
