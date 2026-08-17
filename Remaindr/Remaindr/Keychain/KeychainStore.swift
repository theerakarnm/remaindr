import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
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

    func set(_ value: String, for kind: ProviderKind) throws {
        guard let account = kind.keychainAccount else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try remove(kind)
            return
        }
        // SecItemAdd returns errSecDuplicateItem for an existing account, so replace.
        SecItemDelete(query(account) as CFDictionary)
        var attributes = query(account)
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = Self.accessibility
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func value(for kind: ProviderKind) throws -> String? {
        guard let account = kind.keychainAccount else { return nil }
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ kind: ProviderKind) throws {
        guard let account = kind.keychainAccount else { return }
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
    /// value never leaves memory except into a request header.
    func foreignValue(service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }
}
