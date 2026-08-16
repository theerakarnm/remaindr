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
Claude needs no key: it reads the plan-usage percentages Anthropic reports for the account signed in to Claude Code, authenticating with the OAuth credential Claude Code already stores in the login Keychain.
When that is unavailable (signed out, offline), it falls back to local session files under `~/.claude/projects/`.

## Note on rebuilds

This project is ad-hoc signed, so its code signature changes on every rebuild.
macOS may ask for permission to read the app's own Keychain items after a rebuild; choose Always Allow.
