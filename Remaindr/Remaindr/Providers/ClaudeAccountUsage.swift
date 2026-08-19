import Foundation

/// Plan-limit usage for the Claude account signed in to Claude Code, straight from
/// Anthropic's usage endpoint. These are the same numbers Claude Code itself shows in
/// `/usage`, which is the whole point: a locally synthesized percentage can never match
/// the server's rolling 5-hour window, and every local approximation drifts.
///
/// Authentication uses the OAuth token the manual Connect action copied out of Claude
/// Code's Keychain item into setting.json. The token is used for one GET and is never
/// logged or surfaced anywhere else; `ClaudeCodeCredential` is the only Keychain reader.
struct ClaudeAccountUsage: Sendable, Equatable {
    /// 0...1 of the account's 5-hour session limit already spent.
    let fiveHourUsedFraction: Double
    let fiveHourResetsAt: Date?
    /// The weekly limit, when the account reports one. Enterprise usage-based accounts
    /// have none, which is nil rather than an invented number.
    let weekly: ProviderWeeklyUsage?

    /// One read-only GET. The endpoint answers with percentages for the rolling
    /// 5-hour session limit and the weekly limit; it does not consume plan usage.
    static func fetch(token: String, session: URLSession) async throws -> ClaudeAccountUsage {
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

    /// The manual Connect action. Keychain read #1; if the server rejects that
    /// token, Keychain read #2; if that still cannot call the API, the stored token
    /// is marked invalid and the user is told to sign in to Claude Code and click
    /// Connect again. Returns true when the account source is usable right now.
    static func connect(settings: SettingStore,
                        readCredential: () -> String? = ClaudeCodeCredential.readAccessToken,
                        verify: @Sendable (String) async -> Bool) async -> Bool {
        guard let first = readCredential() else {
            markConnectionInvalid(in: settings)
            return false
        }
        settings.setClaudeOAuth(ClaudeOAuthSetting(accessToken: first, invalid: false))
        if await verify(first) { return true }
        guard let second = readCredential() else {
            markConnectionInvalid(in: settings)
            return false
        }
        settings.setClaudeOAuth(ClaudeOAuthSetting(accessToken: second, invalid: false))
        if await verify(second) { return true }
        markConnectionInvalid(in: settings)
        return false
    }

    /// The one automatic Keychain re-read, run only after the server rejected the
    /// saved token. A nil return means "give up": no credential, the connection is
    /// already locked out, or the Keychain still holds the same token Claude Code
    /// has not rotated yet - retrying that would burn a Keychain prompt every
    /// refresh interval, the exact storm this project fixed once already. Every
    /// give-up path marks the connection invalid here, so no caller has to remember to.
    static func recoverExpiredToken(settings: SettingStore,
                                    readCredential: () -> String? = ClaudeCodeCredential.readAccessToken) -> String? {
        let stored = settings.claudeOAuth
        guard let oldToken = stored.accessToken, !(stored.invalid ?? false) else { return nil }
        guard let fresh = readCredential(), fresh != oldToken else {
            markConnectionInvalid(in: settings)
            return nil
        }
        settings.setClaudeOAuth(ClaudeOAuthSetting(accessToken: fresh, invalid: false))
        return fresh
    }

    /// Internal rather than private: `ClaudeProvider` calls it after a recovered
    /// token is itself rejected by the server - the second failed beg that ends
    /// the cycle.
    static func markConnectionInvalid(in settings: SettingStore) {
        let stored = settings.claudeOAuth
        settings.setClaudeOAuth(ClaudeOAuthSetting(accessToken: stored.accessToken, invalid: true))
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
