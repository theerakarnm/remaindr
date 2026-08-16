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

    /// Short form used inside the 14-character collapsed menu bar label.
    var shortName: String {
        switch self {
        case .claude: return "CL"
        case .zai: return "GLM"
        case .deepseek: return "DS"
        }
    }

    /// Keychain account name. Claude has no entry: it reads local session files.
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
        }
    }
}

/// The two shapes a provider can report. A balance is never converted into a
/// fraction: DeepSeek sells credit, the other two meter a window.
enum ProviderReading: Equatable, Sendable {
    case fraction(used: Double, resetsAt: Date?)
    case balance(amount: Decimal, currency: String)
}

/// One successful reading from one provider at one moment.
struct ProviderStatus: Equatable, Sendable {
    let kind: ProviderKind
    let reading: ProviderReading
    /// Secondary line in the dropdown: a reset time, a plan name, or a currency note.
    let detail: String
    let fetchedAt: Date
}

/// What the collapsed menu bar label reports. `allConfigured` is the default because the
/// brief's example label shows more than one provider at once.
enum LabelSource: Equatable, Sendable, Hashable {
    case allConfigured
    case provider(ProviderKind)

    var storageValue: String {
        switch self {
        case .allConfigured: return "all"
        case .provider(let kind): return kind.rawValue
        }
    }

    /// Any unrecognised stored string falls back to `allConfigured`.
    init(storageValue: String) {
        if let kind = ProviderKind(rawValue: storageValue) {
            self = .provider(kind)
        } else {
            self = .allConfigured
        }
    }

    var displayName: String {
        switch self {
        case .allConfigured: return "All configured"
        case .provider(let kind): return kind.displayName
        }
    }

    static var allCases: [LabelSource] {
        [.allConfigured] + ProviderKind.allCases.map { .provider($0) }
    }
}
