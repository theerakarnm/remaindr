import Foundation

/// GET https://api.deepseek.com/user/balance with `Authorization: Bearer <key>`.
/// Documented response:
///   {"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"110.00",
///     "granted_balance":"10.00","topped_up_balance":"100.00"}]}
/// Reports remaining balance, never a usage percentage.
struct DeepSeekProvider: UsageProvider {
    let kind: ProviderKind = .deepseek

    private let keychain: KeychainStore
    private let session: URLSession
    private static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

    init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    private struct Payload: Decodable {
        struct BalanceInfo: Decodable {
            let currency: String
            let total_balance: String
            let granted_balance: String?
            let topped_up_balance: String?
        }
        let is_available: Bool?
        let balance_infos: [BalanceInfo]
    }

    func fetch(now: Date) async throws -> ProviderStatus {
        guard let key = try keychain.value(for: kind), !key.isEmpty else {
            throw ProviderError.notConfigured
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportFailure(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("no HTTP response")
        }
        // The 401 body is plain text, so status is classified before decoding.
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw ProviderError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ProviderError.serverError(status: http.statusCode)
        }

        return try Self.parse(data, now: now)
    }

    /// Pure so a harness can exercise it without a key or a network.
    static func parse(_ data: Data, now: Date) throws -> ProviderStatus {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ProviderError.malformedResponse("balance payload not decodable")
        }
        guard let info = payload.balance_infos.first else {
            throw ProviderError.malformedResponse("balance_infos empty")
        }
        guard let amount = Decimal(string: info.total_balance) else {
            throw ProviderError.malformedResponse("total_balance not numeric")
        }
        return ProviderStatus(
            kind: .deepseek,
            reading: .balance(amount: amount, currency: info.currency),
            detail: "Remaining balance in \(info.currency)",
            fetchedAt: now
        )
    }
}
