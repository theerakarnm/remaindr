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
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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

    /// Cheap presence check for the Settings UI and for pausing the refresh timer.
    func hasKey(for kind: ProviderKind) -> Bool {
        ((try? value(for: kind)) ?? nil) != nil
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
