import Foundation

/// The complete on-disk shape of ~/.remaindr/setting.json. Every field is optional so a
/// file written by an older build decodes with per-field fallbacks instead of throwing
/// and resetting everything, the same contract the previous dotfile always had.
/// The old dotfile (same path, a file not a directory) decodes as a subset: its
/// `keychainAccessibilityUpgraded` key is ignored as an unknown field.
struct SettingFile: Codable, Equatable {
    var refreshIntervalMinutes: Int?
    var menuBarProvider: String?
    var allowBilledClaudeProbe: Bool?
    var lastUpdateCheckAt: Double?
    /// API keys by provider credential key ("zai", "deepseek", "anthropic").
    /// Secrets: never logged, never surfaced in an error. Guarded by the
    /// directory's 0700 and the file's 0600.
    var apiKeys: [String: String]?
    /// The Claude Code OAuth token copied out by the Connect action, plus the
    /// lockout flag that ends automatic Keychain re-reads once it stops working.
    var claudeOAuth: ClaudeOAuthSetting?
}

/// Connection state for Claude's account usage source. `invalid == true` means the
/// token was rejected and re-begging the Keychain did not help: only the manual
/// Connect action reads the Keychain again.
struct ClaudeOAuthSetting: Codable, Equatable {
    var accessToken: String?
    var invalid: Bool?

    init(accessToken: String? = nil, invalid: Bool? = nil) {
        self.accessToken = accessToken
        self.invalid = invalid
    }
}

/// Owns ~/.remaindr/setting.json: the one file that holds both settings and secrets.
/// All writes are locked read-modify-write cycles so `Preferences` (settings) and the
/// providers (secrets) share the file without clobbering each other. App code must use
/// `SettingStore.shared` so every writer goes through the same lock; tests inject
/// their own instance pointed at a temporary home.
final class SettingStore: @unchecked Sendable {
    static let shared = SettingStore()

    private let lock = NSLock()
    private let home: URL
    private let directoryURL: URL
    private let settingURL: URL
    private let fileManager: FileManager

    init(directoryName: String = ".remaindr",
         fileName: String = "setting.json",
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         fileManager: FileManager = .default) {
        self.home = home
        self.directoryURL = home.appendingPathComponent(directoryName, isDirectory: true)
        self.settingURL = directoryURL.appendingPathComponent(fileName)
        self.fileManager = fileManager
        bootstrap()
    }

    func load() -> SettingFile {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked() ?? SettingFile()
    }

    /// Locked read-modify-write. The change sees the file's current contents and the
    /// result is persisted atomically with mode 0600 before the lock is released.
    func mutate(_ change: (inout SettingFile) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var value = readUnlocked() ?? SettingFile()
        change(&value)
        writeUnlocked(value)
    }

    // MARK: - Credentials

    func apiKey(for kind: ProviderKind) -> String? {
        guard let key = kind.keychainAccount else { return nil }
        guard let value = load().apiKeys?[key] else { return nil }
        return value.isEmpty ? nil : value
    }

    func hasApiKey(for kind: ProviderKind) -> Bool {
        apiKey(for: kind) != nil
    }

    /// A nil or empty value removes the entry, mirroring the old Keychain `set` rule
    /// where an empty paste cleared the item.
    func setApiKey(_ value: String?, for kind: ProviderKind) {
        guard let key = kind.keychainAccount else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        mutate { file in
            var keys = file.apiKeys ?? [:]
            if trimmed.isEmpty {
                keys.removeValue(forKey: key)
            } else {
                keys[key] = trimmed
            }
            file.apiKeys = keys.isEmpty ? nil : keys
        }
    }

    var claudeOAuth: ClaudeOAuthSetting {
        load().claudeOAuth ?? ClaudeOAuthSetting()
    }

    func setClaudeOAuth(_ value: ClaudeOAuthSetting) {
        mutate { $0.claudeOAuth = value }
    }

    // MARK: - File plumbing

    private func readUnlocked() -> SettingFile? {
        guard let data = try? Data(contentsOf: settingURL) else { return nil }
        return try? JSONDecoder().decode(SettingFile.self, from: data)
    }

    private func writeUnlocked(_ value: SettingFile) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: settingURL, options: .atomic)
        // `.atomic` does not carry attributes through the rename on every macOS
        // release, so the mode is forced here; the 0700 directory already bounds
        // who can reach the file between write and rename.
        try? fileManager.setAttributes([.posixPermissions: 0o600],
                                       ofItemAtPath: settingURL.path)
    }

    /// First-run bootstrap: create ~/.remaindr (0700) and an empty setting.json
    /// (0600) so the folder exists and is writable from the first launch, and clear
    /// the way when the name is still occupied by the pre-setting.json dotfile.
    private func bootstrap() {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            try? fileManager.setAttributes([.posixPermissions: 0o700],
                                           ofItemAtPath: directoryURL.path)
            if !fileManager.fileExists(atPath: settingURL.path) {
                writeUnlocked(SettingFile())
            }
            return
        }
        if exists {
            migrateDotfileAside()
            return
        }
        try? fileManager.createDirectory(at: directoryURL,
                                         withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        writeUnlocked(SettingFile())
    }

    /// The previous build stored settings in a `~/.remaindr` FILE; this build needs
    /// that name for the directory. The old file carries only non-secret settings
    /// (keys always lived in the Keychain), and its schema is a subset of
    /// `SettingFile`, so it is decoded, moved aside to `~/.remaindr.old`, and its
    /// fields become the first `setting.json` contents. The owner chose "start
    /// fresh" for keys only; settings survive.
    private func migrateDotfileAside() {
        // Decode BEFORE moving the file: `readUnlocked` reads the directory's
        // setting.json, a path that cannot exist yet, so it would hand back nil
        // here and every migrated setting would be lost.
        let legacy = (try? Data(contentsOf: directoryURL))
            .flatMap { try? JSONDecoder().decode(SettingFile.self, from: $0) }
        let aside = home.appendingPathComponent(".remaindr.old")
        try? fileManager.removeItem(at: aside)
        try? fileManager.moveItem(at: directoryURL, to: aside)
        try? fileManager.createDirectory(at: directoryURL,
                                         withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        writeUnlocked(legacy ?? SettingFile())
    }
}
