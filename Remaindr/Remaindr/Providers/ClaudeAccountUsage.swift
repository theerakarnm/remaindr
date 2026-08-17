import Foundation

/// Plan-limit usage for the Claude account signed in to Claude Code, straight from
/// Anthropic's usage endpoint. These are the same numbers Claude Code itself shows in
/// `/usage`, which is the whole point: a locally synthesized percentage can never match
/// the server's rolling 5-hour window, and every local approximation drifts.
///
/// Authentication reuses the OAuth credential Claude Code already stores in the login
/// Keychain, so the user configures nothing. The token is read, used for one GET, and
/// never stored, logged, or surfaced anywhere else.
struct ClaudeAccountUsage: Sendable, Equatable {
    /// 0...1 of the account's 5-hour session limit already spent.
    let fiveHourUsedFraction: Double
    let fiveHourResetsAt: Date?
    /// The weekly limit, when the account reports one. Enterprise usage-based accounts
    /// have none, which is nil rather than an invented number.
    let weekly: ProviderWeeklyUsage?

    /// The Keychain service Claude Code stores its credential blob under.
    static let credentialService = "Claude Code-credentials"

    enum AccountUsageError: Error {
        /// No signed-in Claude Code credential (or the blob has no access token yet).
        case noCredential
    }

    /// Reads the OAuth access token out of the credential blob Claude Code maintains.
    /// Any failure simply means "no account source available" and the caller falls back.
    static func accessToken(keychain: KeychainStore) -> String? {
        guard let blob = (try? keychain.foreignValue(service: credentialService)) ?? nil,
              let data = blob.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }

    /// One read-only GET. The endpoint answers with percentages for the rolling
    /// 5-hour session limit and the weekly limit; it does not consume plan usage.
    static func fetch(keychain: KeychainStore, session: URLSession) async throws -> ClaudeAccountUsage {
        guard let token = accessToken(keychain: keychain) else {
            throw AccountUsageError.noCredential
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        // The token is placed straight into the request; it must never appear in an
        // error, a log line, or a status string.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("no HTTP response")
        }
        switch http.statusCode {
        case 200: break
        case 401, 403:
            // Claude Code rotates this token, and `foreignValue` caches for the lifetime
            // of the process so it costs at most one Keychain prompt. Dropping the cached
            // copy here is what keeps that cache from replaying a token the server has
            // already rejected: the next refresh re-reads the blob instead.
            keychain.invalidateForeign(service: credentialService)
            throw ProviderError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        default: throw ProviderError.serverError(status: http.statusCode)
        }
        guard let usage = decode(data) else {
            throw ProviderError.malformedResponse("no five_hour bucket")
        }
        return usage
    }

    /// Pulls the 5-hour and weekly percentages out of the response. Older accounts carry
    /// flat `five_hour` / `seven_day` buckets; newer ones report the same windows inside
    /// `limits[]` as kind `session` / `weekly_all`. Both shapes are accepted, flat first.
    static func decode(_ data: Data) -> ClaudeAccountUsage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let flatSession = root["five_hour"] as? [String: Any]
        let flatWeekly = root["seven_day"] as? [String: Any]
        let limitEntries = root["limits"] as? [[String: Any]]

        func bucket(kind: String) -> [String: Any]? {
            limitEntries?.first { ($0["kind"] as? String) == kind }
        }

        let sessionBucket = (flatSession?.keys.contains("utilization") == true)
            ? flatSession
            : bucket(kind: "session")
        guard let sessionPercent = sessionBucket?["utilization"] as? Double else { return nil }

        let weeklyBucket = (flatWeekly?.keys.contains("utilization") == true)
            ? flatWeekly
            : bucket(kind: "weekly_all")
        let weekly = weeklyBucket?["utilization"] as? Double

        return ClaudeAccountUsage(
            fiveHourUsedFraction: Self.clampedFraction(sessionPercent),
            fiveHourResetsAt: (sessionBucket?["resets_at"] as? String).flatMap(ClaudeSessionBlocks.parseTimestamp),
            weekly: weekly.map {
                ProviderWeeklyUsage(used: Self.clampedFraction($0),
                                    resetsAt: (weeklyBucket?["resets_at"] as? String).flatMap(ClaudeSessionBlocks.parseTimestamp))
            }
        )
    }

    private static func clampedFraction(_ percent: Double) -> Double {
        min(max(percent / 100, 0), 1)
    }
}
