import Foundation

/// Non-secret settings only. API keys live in the Keychain and never appear here.
/// Backed by a dotfile so settings persist across an app uninstall, same as the
/// Keychain already does for keys.
@MainActor
@Observable
final class Preferences {
    /// Every field is optional on purpose. `ConfigFileStore.load` decodes with `try?`, so a
    /// single non-optional field missing from an older file would throw and silently reset
    /// *all* settings to their defaults. Optional fields let each key fall back on its own.
    private struct ConfigFile: Codable {
        var refreshIntervalMinutes: Int?
        var menuBarProvider: String?
        var allowBilledClaudeProbe: Bool?
        var keychainAccessibilityUpgraded: Bool?
    }

    private let store: ConfigFileStore<ConfigFile>

    convenience init() {
        self.init(store: ConfigFileStore(fileName: ".remaindr"))
    }

    private init(store: ConfigFileStore<ConfigFile>) {
        self.store = store
        let loaded = store.load()
        let stored = loaded?.refreshIntervalMinutes ?? 5
        self.refreshIntervalMinutes = min(max(stored, 1), 60)
        self.menuBarProvider = loaded?.menuBarProvider.flatMap(ProviderKind.init(rawValue:)) ?? .claude
        self.allowBilledClaudeProbe = loaded?.allowBilledClaudeProbe ?? false
        self.keychainAccessibilityUpgraded = loaded?.keychainAccessibilityUpgraded ?? false
    }

    /// Clamped to the 1...60 range the brief specifies.
    var refreshIntervalMinutes: Int {
        didSet {
            let clamped = min(max(refreshIntervalMinutes, 1), 60)
            if clamped != refreshIntervalMinutes {
                refreshIntervalMinutes = clamped
                return
            }
            persist()
        }
    }

    /// The single provider the collapsed menu bar label reports on. Exactly one, always:
    /// the bar has to stay narrow, and its icon has to mean one thing.
    var menuBarProvider: ProviderKind {
        didSet { persist() }
    }

    /// Off by default. Turning it on permits a billed Messages request for the Claude
    /// header fallback.
    var allowBilledClaudeProbe: Bool {
        didSet { persist() }
    }

    /// True once the one-time Keychain accessibility rewrite has run. macOS does
    /// not report a stored item's accessibility class, so the rewrite cannot
    /// detect "already done" and must be gated here instead.
    var keychainAccessibilityUpgraded: Bool {
        didSet { persist() }
    }

    private func persist() {
        store.save(ConfigFile(refreshIntervalMinutes: refreshIntervalMinutes,
                               menuBarProvider: menuBarProvider.rawValue,
                               allowBilledClaudeProbe: allowBilledClaudeProbe,
                               keychainAccessibilityUpgraded: keychainAccessibilityUpgraded))
    }
}
