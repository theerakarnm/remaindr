import Foundation

/// The only surface the UI layer knows about. A provider is a value type with no
/// stored credentials: it reads its key from the Keychain inside `fetch`, at call time.
protocol UsageProvider: Sendable {
    var kind: ProviderKind { get }

    /// Returns a status or throws a `ProviderError`.
    /// `now` is injected so aggregation over local files is deterministic in a harness.
    func fetch(now: Date) async throws -> ProviderStatus
}

extension UsageProvider {
    /// Maps `URLSession` transport failures onto the one offline state the UI shows.
    /// Anything that is not a recognised connectivity failure is rethrown untouched.
    func mapTransportFailure(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff,
             .dataNotAllowed, .secureConnectionFailed:
            return ProviderError.offline
        default:
            return error
        }
    }
}
