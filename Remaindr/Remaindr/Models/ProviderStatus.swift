import Foundation

/// The three providers this app reports on. Adding a fourth means adding a case
/// here and one `UsageProvider` conformance; no UI file changes.
enum ProviderKind: String, CaseIterable, Sendable, Identifiable {
    case claude
    case zai
    case deepseek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .zai: return "z.ai (GLM)"
        case .deepseek: return "DeepSeek"
        }
    }

    /// Asset catalog name of the monochrome template glyph. The collapsed label uses it
    /// instead of a text prefix, so the bar is identifiable without reading it.
    var iconAssetName: String {
        switch self {
        case .claude: return "ProviderIconClaude"
        case .zai: return "ProviderIconZAI"
        case .deepseek: return "ProviderIconDeepSeek"
        }
    }

    /// Credential key in setting.json (a historical name: these strings were the
    /// Keychain account names before credentials moved to the config file).
    /// Claude's entry is the billed-header-probe API key; its primary source is
    /// the OAuth token stored by the Connect action.
    var keychainAccount: String? {
        switch self {
        case .claude: return "anthropic"
        case .zai: return "zai"
        case .deepseek: return "deepseek"
        }
    }
}

/// Every distinct failure the UI must be able to show differently.
enum ProviderError: Error, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case offline
    case malformedResponse(String)
    case serverError(status: Int)
    case noActivePlan
    /// The server's certificate chain did not match a pinned certificate.
    case untrustedServer
    /// The saved Claude OAuth token was rejected and re-reading the Keychain did not
    /// help. The user must sign in to Claude Code and click Connect again in Settings.
    case reconnectRequired

    /// Short text shown next to a stale value. Never contains a key or a token.
    var shortDescription: String {
        switch self {
        case .notConfigured: return "Not configured"
        case .unauthorized: return "Key rejected"
        case .rateLimited: return "Rate limited"
        case .offline: return "Offline"
        case .malformedResponse: return "Bad response"
        case .serverError(let status): return "Server error \(status)"
        case .noActivePlan: return "No active plan"
        case .untrustedServer: return "Connection untrusted"
        case .reconnectRequired: return "Reconnect Claude in Settings"
        }
    }
}

/// The two shapes a provider can report. A balance is never converted into a
/// fraction: DeepSeek sells credit, the other two meter a window.
enum ProviderReading: Equatable, Sendable {
    case fraction(used: Double, resetsAt: Date?)
    case balance(amount: Decimal, currency: String)
}

/// A weekly-window meter, present only when the provider actually reports one. z.ai
/// answers with a weekly quota entry; Claude's local session files carry no weekly
/// ceiling to divide by, and DeepSeek meters credit, so those two leave it nil rather
/// than invent a number.
struct ProviderWeeklyUsage: Equatable, Sendable {
    /// 0...1 of the weekly allowance spent, same convention as `ProviderReading.fraction`.
    let used: Double
    let resetsAt: Date?
}

/// One successful reading from one provider at one moment.
struct ProviderStatus: Equatable, Sendable {
    let kind: ProviderKind
    let reading: ProviderReading
    /// Secondary line in the dropdown: a reset time, a plan name, or a currency note.
    let detail: String
    let fetchedAt: Date
    /// The weekly meter, when the provider reports one. The dropdown draws it stacked
    /// behind the primary reading.
    var weekly: ProviderWeeklyUsage?

    /// `weekly` defaults to nil so providers with no weekly meter read unchanged.
    init(kind: ProviderKind,
         reading: ProviderReading,
         detail: String,
         fetchedAt: Date,
         weekly: ProviderWeeklyUsage? = nil) {
        self.kind = kind
        self.reading = reading
        self.detail = detail
        self.fetchedAt = fetchedAt
        self.weekly = weekly
    }
}
