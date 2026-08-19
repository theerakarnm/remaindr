import Foundation

/// Non-secret settings only. Secrets (API keys, the Claude OAuth token) live in the
/// same setting.json but are accessed through SettingStore's credential accessors,
/// never through this type.
@MainActor
@Observable
final class Preferences {
    private let store: SettingStore

    convenience init() {
        self.init(store: .shared)
    }

    init(store: SettingStore) {
        self.store = store
        let loaded = store.load()
        let stored = loaded.refreshIntervalMinutes ?? 5
        self.refreshIntervalMinutes = min(max(stored, 1), 60)
        self.menuBarProvider = loaded.menuBarProvider.flatMap(ProviderKind.init(rawValue:)) ?? .claude
        self.allowBilledClaudeProbe = loaded.allowBilledClaudeProbe ?? false
        self.lastUpdateCheck = loaded.lastUpdateCheckAt.map(Date.init(timeIntervalSince1970:))
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

    /// When the update check last completed a network round trip, successful or not.
    /// Non-secret, like every other field here. Stored as epoch seconds so the file
    /// stays readable and independent of any date-encoding strategy.
    var lastUpdateCheck: Date? {
        didSet { persist() }
    }

    private func persist() {
        store.mutate { file in
            file.refreshIntervalMinutes = refreshIntervalMinutes
            file.menuBarProvider = menuBarProvider.rawValue
            file.allowBilledClaudeProbe = allowBilledClaudeProbe
            file.lastUpdateCheckAt = lastUpdateCheck?.timeIntervalSince1970
        }
    }
}
