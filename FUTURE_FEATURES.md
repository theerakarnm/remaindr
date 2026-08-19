# Future Feature Checklist

Candidate features and improvements for Remaindr, in checklist form.
Items fold in the four Roadmap entries from `README.md` plus the work the security audit deferred as product decisions.
Nothing here is scheduled; pick an item, check it off when shipped, and move its verification notes into the PR.

Ground rules that still apply to every item below (see `AGENTS.md`):

- Credentials live in `~/.remaindr/setting.json` only (0700 directory, 0600 file), never in `UserDefaults`, logs, or commits. The Keychain is read only by the Claude Connect flow.
- The UI talks to providers only through the `UsageProvider` protocol; a new provider must not require UI changes.
- The collapsed menu bar label stays within roughly 14 characters no matter how many providers are active.
- No third-party Swift packages; if one seems needed for an item, stop and ask first.

## Distribution & trust

- [ ] Developer ID signed Release builds so the Connect flow's keychain grant survives updates and `get-task-allow` never ships (audit F-01; blocked on obtaining a signing identity).
- [x] Notarize and staple the DMG in `make-dmg.sh`, then remove the Gatekeeper-bypass wording from the README (audit F-02).
- [x] Publish SHA-256 checksums alongside each release download.
- [ ] Design and ship a real app icon asset catalog (menu bar glyph plus Settings window icon).
- [x] First-party update checker (version check against the latest GitHub release; must not grow into a third-party framework).

## Providers

- [ ] OpenAI provider (usage via the API usage / billing endpoints) behind `UsageProvider`.
- [ ] Google Gemini provider behind `UsageProvider`.
- [ ] OpenRouter provider behind `UsageProvider` (credits remaining maps naturally onto the DeepSeek-style balance row).
- [ ] Per-provider show/hide toggle so an unused provider can be hidden from the dropdown without deleting its key.
- [ ] Re-verify the z.ai endpoint path and response shape against current docs before any ZAI provider change (project rule; do not trust the shape from memory).
- [ ] Decision item: switch the Claude percentage denominator from "largest historical block" to a user-configured limit.

## Menu bar & dropdown UI

- [ ] "Auto" option for the collapsed label: show whichever provider is closest to its limit instead of one fixed pick.
- [ ] Two-provider collapsed label variant (for example `C42 Z88`) that still respects the character budget.
- [ ] Color state on the collapsed label when the shown provider crosses a warning threshold.
- [ ] Per-row context menu: refresh this provider only, copy the raw reading, open the provider's usage web page.
- [ ] Keyboard shortcuts inside the dropdown panel (R for refresh, comma for Settings), matching standard macOS menu bar apps.
- [ ] Sortable or reorderable rows in the dropdown.

## Data & history

- [ ] Persist readings locally (timestamps plus values, no secrets) so history survives relaunches.
- [ ] Historical usage graph in the dropdown or a popover (the README Roadmap item; depends on the persistence item above).
- [ ] Per-provider history detail view: last 24 hours and last 7 days.
- [ ] Export history to CSV or JSON from Settings.
- [ ] Claude 5-hour block history strip showing previous blocks next to the current one.

## Notifications & alerts

- [ ] Optional notification when a provider crosses a usage threshold (the README Roadmap item).
- [ ] Configurable per-provider thresholds in Settings (percent for Claude and z.ai, absolute currency for DeepSeek).
- [ ] Notification shortly before the Claude 5-hour window resets.
- [ ] Low DeepSeek balance warning below a user-set amount.

## Refresh behavior & networking

- [ ] Refresh immediately on wake from sleep (currently the interval timer can leave data stale across a sleep).
- [ ] Refresh when the network path comes back up, via `NWPathMonitor`.
- [ ] Backoff and retry for transient provider failures before surfacing an error state.
- [ ] Optional faster refresh cadence when a provider is near its limit or a window reset is minutes away.

## Security hardening (deferred audit items)

- [ ] Decision item: enable App Sandbox, which requires a user-granted folder bookmark or similar access to `~/.claude/projects` (audit F-07; deliberately not built because it breaks the local session read).
- [x] Decision item: stop reading Claude Code's foreign keychain credential in favor of an explicit user-pasted token (audit F-08; deliberately kept because removing it deletes a feature); resolved 2026-08-19: the credential is still read, but only by the manual Connect action and one expiry retry, at most twice per connection cycle.

## Accessibility & localization

- [ ] Full VoiceOver pass over the dropdown, Settings, and the collapsed label.
- [ ] Dynamic Type support in the dropdown and Settings windows.
- [ ] Reduce Motion variant for any animated meter transitions.
- [ ] Localization, starting with Thai, with strings moved out of code.

## Quality & engineering

- [ ] XCTest target covering the pure-Foundation logic (block aggregation, collapsed-label text, preference clamping).
- [ ] CI on GitHub Actions that builds with zero warnings and runs the tests on every push.
- [ ] UI smoke test that pins the dropdown layout so regressions in the character budget surface in review.
- [ ] Instruments pass on a long-running build to confirm no memory growth across days of scheduled refreshes.
