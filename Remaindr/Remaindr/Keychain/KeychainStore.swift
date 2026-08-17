import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Process-wide cache of the secret material already read out of the Keychain.
///
/// Reading `kSecValueData` is the operation macOS gates behind the item's ACL and
/// partition list, so an uncached read is a possible "enter the login keychain
/// password" dialog. The refresh timer fires every `refreshIntervalMinutes` and each
/// cycle re-read the z.ai key, the DeepSeek key and Claude Code's credential blob, so
/// a user who answered "Allow" rather than "Always Allow" was asked again on every
/// tick, forever. Caching makes any one item cost at most one prompt per app launch.
///
/// Failures are cached too, deliberately: a denied read retried every five minutes
/// re-prompts every five minutes. A cached `.success(nil)` means "asked, nothing
/// there". Values live in memory only - nothing here is written to disk or logged.
private final class SecretCache: @unchecked Sendable {
    static let shared = SecretCache()

    private let lock = NSLock()
    private var entries: [String: Result<String?, KeychainError>] = [:]

    /// `read` runs at most once per key for the lifetime of the process. The lock is
    /// held across it on purpose: two providers refreshing concurrently must not
    /// stack two dialogs for the same item.
    func value(forKey key: String, read: () -> Result<String?, KeychainError>) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = entries[key] { return try cached.get() }
        let fresh = read()
        entries[key] = fresh
        return try fresh.get()
    }

    func invalidate(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }
}

/// The only place an API key is ever read or written. Values never reach
/// `UserDefaults`, a log, or a thrown error's message.
struct KeychainStore: Sendable {
    let service: String

    init(service: String = "com.theerakarn.Remaindr") {
        self.service = service
    }

    /// The strictest class that still allows unattended refresh: the item never
    /// migrates to another device and is unavailable until the keychain unlocks.
    static let accessibility: String = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
    private func cacheKey(_ account: String) -> String { "\(service)/\(account)" }

    /// The one place `kSecValueData` is requested. Every call is a possible Keychain
    /// prompt, which is why `SecretCache` wraps it.
    private static func readData(_ base: [String: Any]) -> Result<String?, KeychainError> {
        var attributes = base
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return .success(nil) }
        guard status == errSecSuccess, let data = result as? Data else {
            return .failure(.unexpectedStatus(status))
        }
        return .success(String(data: data, encoding: .utf8))
    }

    func set(_ value: String, for kind: ProviderKind) throws {
        guard let account = kind.keychainAccount else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try remove(kind)
            return
        }
        SecretCache.shared.invalidate(cacheKey(account))
        // SecItemAdd returns errSecDuplicateItem for an existing account, so replace.
        SecItemDelete(query(account) as CFDictionary)
        var attributes = query(account)
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = Self.accessibility
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Reads the stored key, at most once per process. See `SecretCache`.
    func value(for kind: ProviderKind) throws -> String? {
        guard let account = kind.keychainAccount else { return nil }
        let base = query(account)
        return try SecretCache.shared.value(forKey: cacheKey(account)) {
            Self.readData(base)
        }
    }
    func remove(_ kind: ProviderKind) throws {
        guard let account = kind.keychainAccount else { return }
        SecretCache.shared.invalidate(cacheKey(account))
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Raises this app's own items to the current accessibility class. macOS never
    /// reports a generic password's `kSecAttrAccessible` back, so the caller gates
    /// this to run exactly once. `SecItemUpdate` changes the attribute in place:
    /// the secret is never read, and the item keeps its existing ACL and partition
    /// list instead of being destroyed and recreated (which would re-prompt).
    func upgradeAccessibility() {
        for kind in ProviderKind.allCases {
            guard let account = kind.keychainAccount else { continue }
            let updates: [String: Any] = [kSecAttrAccessible as String: Self.accessibility]
            _ = SecItemUpdate(query(account) as CFDictionary, updates as CFDictionary)
        }
    }

    /// Cheap presence check for the Settings UI and for pausing the refresh timer.
    /// It must never ask for `kSecValueData`: the data read is the operation macOS gates
    /// behind the item's ACL and partition list, and answering it costs the user a login
    /// keychain password prompt. An attributes-only match is served from the item's
    /// plaintext metadata columns and never prompts. Measured on macOS 26.2 with prompts
    /// disabled: the data query returns errSecAuthFailed (-25293), the attributes query
    /// returns errSecSuccess.
    /// The trade is deliberate - this now answers "does the item exist", not "can this
    /// build read it", so a saved key stops reading as "Not set" after an app update.
    func hasKey(for kind: ProviderKind) -> Bool {
        guard let account = kind.keychainAccount else { return false }
        var attributes = query(account)
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess
    }

    /// Reads a generic-password item another app stored, such as Claude Code's OAuth
    /// credential. Read-only: this app never writes or deletes a foreign item, and the
    /// value never leaves memory except into a request header. Read at most once per
    /// process: the item belongs to another app, so its ACL cannot list this one until
    /// the user grants access by hand, and re-reading it every refresh means re-asking
    /// every refresh.
    func foreignValue(service: String) throws -> String? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        return try SecretCache.shared.value(forKey: "foreign/\(service)") {
            Self.readData(base)
        }
    }

    /// Drops the cached copy of a foreign item so the next read goes back to the
    /// Keychain. Claude Code rotates the OAuth token inside its credential blob, and a
    /// process-lifetime cache would otherwise keep replaying a token the server has
    /// already rejected - in an `LSUIElement` app that runs for days, that would mean
    /// losing Claude's primary source until the user quits and relaunches.
    func invalidateForeign(service: String) {
        SecretCache.shared.invalidate("foreign/\(service)")
    }

}
