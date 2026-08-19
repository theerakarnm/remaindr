import Foundation
import Security

/// The single remaining Keychain touchpoint. Claude Code stores its OAuth
/// credential as a JSON blob in the login Keychain under this service name; the
/// manual Connect action copies the token out once into setting.json, and after
/// that only the expiry retry ever comes back here.
enum ClaudeCodeCredential {
    static let service = "Claude Code-credentials"

    /// One call can surface one login-keychain password prompt. Callers must be
    /// the manual Connect action or the single automatic retry after an auth
    /// rejection - never a periodic refresh.
    /// Returns nil for every failure: missing item, denied read, or a blob with
    /// no access token. The token is never logged and never persisted anywhere
    /// except setting.json.
    static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }
}
