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
