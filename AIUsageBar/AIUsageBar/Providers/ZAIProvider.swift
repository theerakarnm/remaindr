import Foundation

/// GET https://api.z.ai/api/monitor/usage/quota/limit
///
/// This endpoint is not in z.ai's public API reference. The shape below is taken from a
/// captured live GLM Coding Plan response:
///   {"code":200,"msg":"Operation successful","data":{"limits":[
///     {"type":"CREDIT_LIMIT","unit":3,"number":5,"percentage":0},
///     {"type":"CREDIT_LIMIT","unit":6,"number":1,"percentage":98,"nextResetTime":1786685679998}
///   ],"level":"lite"},"success":true}
///
/// `unit` encodes the window: 3 = hours, 4 = days, 5 = months, 6 = weeks, multiplied by
/// `number`. A sub-daily window is the rolling 5-hour session meter, which is the one
/// this app shows. `TOKENS_LIMIT` is the older name for `CREDIT_LIMIT`; both are accepted.
struct ZAIProvider: UsageProvider {
    let kind: ProviderKind = .zai

    private let keychain: KeychainStore
    private let session: URLSession
    private static let endpoint = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

    init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func fetch(now: Date) async throws -> ProviderStatus {
        guard let key = try keychain.value(for: kind), !key.isEmpty else {
            throw ProviderError.notConfigured
        }

        // Two open-source clients disagree on the header form, so try the standard
        // Bearer shape first and fall back to the bare token only when z.ai says the
        // auth parameter was not received (code 1001).
        var data = try await send(key: key, bearer: true)
        if Self.bodyCode(data) == 1001 {
            data = try await send(key: key, bearer: false)
        }
        return try Self.parse(data, now: now)
    }

    private func send(key: String, bearer: Bool) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(bearer ? "Bearer \(key)" : key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

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
        // z.ai returns 200 for auth failures, so a non-2xx here is a genuine transport
        // or server fault; the body-level classification happens in `parse`.
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw ProviderError.unauthorized
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
                throw ProviderError.rateLimited(retryAfter: retryAfter)
            default: throw ProviderError.serverError(status: http.statusCode)
            }
        }
        return data
    }

    private static func bodyCode(_ data: Data) -> Int? {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return root?["code"] as? Int
    }

    /// Pure so a harness can exercise every branch without a key or a network.
    static func parse(_ data: Data, now: Date) throws -> ProviderStatus {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderError.malformedResponse("quota payload not JSON")
        }

        if (root["success"] as? Bool) == false {
            let message = (root["msg"] as? String ?? "").lowercased()
            let code = root["code"] as? Int
            if code == 401 || code == 1001 || code == 403 { throw ProviderError.unauthorized }
            if code == 429 { throw ProviderError.rateLimited(retryAfter: nil) }
            // A valid key with no GLM Coding Plan answers success:false and says so.
            if message.contains("coding plan") { throw ProviderError.noActivePlan }
            throw ProviderError.serverError(status: code ?? -1)
        }

        // The limits array normally lives under `data`; tolerate it at the root too.
        let container = (root["data"] as? [String: Any]) ?? root
        guard let limits = container["limits"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("no limits array")
        }

        // The rolling session meter is the percentage entry with a sub-daily window.
        let session = limits.first { entry in
            let type = (entry["type"] as? String) ?? ""
            guard type == "CREDIT_LIMIT" || type == "TOKENS_LIMIT" else { return false }
            guard let windowMs = windowMilliseconds(entry) else { return false }
            return windowMs < 24 * 60 * 60 * 1000
        }
        guard let session, let percentage = session["percentage"] as? Double ?? (session["percentage"] as? Int).map(Double.init) else {
            throw ProviderError.malformedResponse("no session percentage")
        }

        let resetsAt = (session["nextResetTime"] as? Double ?? (session["nextResetTime"] as? Int).map(Double.init))
            .map { Date(timeIntervalSince1970: $0 / 1000) }
        let plan = (container["level"] as? String)?.capitalized

        var detail = "5-hour window"
        if let plan { detail = "\(plan) plan, 5-hour window" }

        return ProviderStatus(
            kind: .zai,
            reading: .fraction(used: min(max(percentage / 100, 0), 1), resetsAt: resetsAt),
            detail: detail,
            fetchedAt: now
        )
    }

    /// `(unit, number)` to a window length in milliseconds. Unknown units return nil so a
    /// future z.ai window cannot hide the meters this app already understands.
    private static func windowMilliseconds(_ entry: [String: Any]) -> Double? {
        let unit = (entry["unit"] as? Double) ?? (entry["unit"] as? Int).map(Double.init)
        let number = (entry["number"] as? Double) ?? (entry["number"] as? Int).map(Double.init)
        guard let unit, let number, number > 0 else { return nil }
        let unitMs: Double
        switch Int(unit) {
        case 3: unitMs = 60 * 60 * 1000
        case 4: unitMs = 24 * 60 * 60 * 1000
        case 5: unitMs = 30 * 24 * 60 * 60 * 1000
        case 6: unitMs = 7 * 24 * 60 * 60 * 1000
        default: return nil
        }
        return unitMs * number
    }
}
