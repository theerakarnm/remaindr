import Foundation

/// Claude has three sources, in order:
///  1. the account usage endpoint (`/api/oauth/usage`), which reports the exact
///     percentages Claude Code itself shows in `/usage`, authenticated with the OAuth
///     token the Connect action copied out of Claude Code's Keychain item into
///     setting.json;
///  2. local session files under `~/.claude/projects/**/*.jsonl`, aggregated into rolling
///     5-hour blocks, used whenever the account source is unavailable;
///  3. `anthropic-ratelimit-*` response headers, but only when the user has explicitly
///     opted into a billed probe request, because the headers exist only on a successful
///     Messages API call.
/// When none is available it throws `.notConfigured`. It never invents a number.
struct ClaudeProvider: UsageProvider {
    let kind: ProviderKind = .claude

    private let settings: SettingStore
    private let session: URLSession
    private let projectsDirectory: URL
    /// Off unless the user turns it on in Settings. A probe request is billed.
    private let allowBilledProbe: Bool

    /// Session files larger than this are skipped: the scan reads whole files
    /// into memory, and a planted huge file must not be able to jetsam the app.
    static let maxSessionFileBytes = 16 * 1024 * 1024

    static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    init(settings: SettingStore = .shared,
         session: URLSession = .shared,
         projectsDirectory: URL = ClaudeProvider.defaultProjectsDirectory,
         allowBilledProbe: Bool = false) {
        self.settings = settings
        self.session = session
        self.projectsDirectory = projectsDirectory
        self.allowBilledProbe = allowBilledProbe
    }

    func fetch(now: Date) async throws -> ProviderStatus {
        // Door 1: the account endpoint, authenticated with the token the Connect
        // action saved. Unavailable (never connected, or locked out as invalid)
        // simply means "fall through", exactly like every other account failure.
        // An untrusted server is the exception: surfacing it is the only way a pin
        // failure becomes visible instead of silently downgrading.
        do {
            return try await accountUsageStatus(now: now)
        } catch ProviderError.untrustedServer {
            throw ProviderError.untrustedServer
        } catch ProviderError.unauthorized {
            // The saved token was rejected. One Keychain re-read, one retry; if
            // either fails the connection is marked invalid and automatic
            // Keychain reads stop until the user clicks Connect again.
            if let fresh = ClaudeAccountUsage.recoverExpiredToken(settings: settings) {
                if let status = try? await accountUsage(withToken: fresh, now: now) {
                    return status
                }
                // The rotated token was rejected too: the second failed beg.
                ClaudeAccountUsage.markConnectionInvalid(in: settings)
            }
        } catch {
        }

        let directory = projectsDirectory
        // The scan touches ~1600 files, so keep it off the main actor.
        let blocks = await Task.detached(priority: .utility) {
            Self.scanBlocks(in: directory)
        }.value

        if let status = Self.status(from: blocks, now: now) {
            return status
        }

        guard allowBilledProbe, let key = settings.apiKey(for: kind), !key.isEmpty else {
            let oauth = settings.claudeOAuth
            if let invalid = oauth.invalid, invalid, oauth.accessToken != nil {
                throw ProviderError.reconnectRequired
            }
            throw ProviderError.notConfigured
        }
        return try await probeHeaders(key: key, now: now)
    }

    /// Reads the token saved by Connect. Absent or flagged invalid both throw, which
    /// the caller treats as "account source unavailable, fall through" - never as an
    /// error for the user (the reconnect-required signal is raised only at the very
    /// end of fetch, after every source has failed).
    private func accountUsageStatus(now: Date) async throws -> ProviderStatus {
        let oauth = settings.claudeOAuth
        guard let token = oauth.accessToken, !(oauth.invalid ?? false) else {
            throw ProviderError.notConfigured
        }
        return try await accountUsage(withToken: token, now: now)
    }

    /// Turns the account usage payload into the status the UI draws. The 5-hour percent
    /// drives the primary meter and reset countdown; the weekly limit, when the account
    /// reports one, rides along as the stacked back layer.
    private func accountUsage(withToken token: String, now: Date) async throws -> ProviderStatus {
        let usage: ClaudeAccountUsage
        do {
            usage = try await ClaudeAccountUsage.fetch(token: token, session: session)
        } catch {
            throw mapTransportFailure(error)
        }
        return ProviderStatus(
            kind: .claude,
            reading: .fraction(used: usage.fiveHourUsedFraction, resetsAt: usage.fiveHourResetsAt),
            detail: "Plan limits reported by claude.ai (same source as Claude Code /usage)",
            fetchedAt: now,
            weekly: usage.weekly
        )
    }

    // MARK: - Local session files

    /// Streams every `.jsonl` under the projects directory and aggregates the blocks.
    /// A missing directory, an unreadable file, or a malformed line is skipped, never fatal.
    static func scanBlocks(in directory: URL) -> [ClaudeUsageBlock] {
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [ClaudeUsageEntry] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= Self.maxSessionFileBytes else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let entry = ClaudeSessionBlocks.entry(fromLine: String(line)) {
                    entries.append(entry)
                }
            }
        }
        return ClaudeSessionBlocks.blocks(from: entries)
    }

    /// Returns nil when there are no blocks at all, which is the "nothing to report" case
    /// the caller turns into `.notConfigured` or a header probe.
    static func status(from blocks: [ClaudeUsageBlock], now: Date) -> ProviderStatus? {
        guard !blocks.isEmpty else { return nil }
        let peak = blocks.map(\.totalTokens).max() ?? 0
        let active = ClaudeSessionBlocks.activeBlock(in: blocks, now: now)
        let used = active?.totalTokens ?? 0
        let fraction = peak > 0 ? min(max(Double(used) / Double(peak), 0), 1) : 0

        let detail: String
        if active != nil {
            detail = "\(used.formatted()) tokens this 5-hour block, against your busiest block of \(peak.formatted())"
        } else {
            detail = "No activity in the current 5-hour block"
        }

        return ProviderStatus(
            kind: .claude,
            reading: .fraction(used: fraction, resetsAt: active?.endsAt),
            detail: detail,
            fetchedAt: now
        )
    }

    // MARK: - Rate limit header fallback

    /// Sends the smallest possible Messages request purely to read the rate limit headers.
    /// This IS billed, which is why it only runs when the user opted in.
    private func probeHeaders(key: String, now: Date) async throws -> ProviderStatus {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]],
        ])

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw mapTransportFailure(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("no HTTP response")
        }
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
        guard let status = Self.statusFromHeaders(http, now: now) else {
            throw ProviderError.malformedResponse("no anthropic-ratelimit headers")
        }
        return status
    }

    /// Reads the documented input-token headers. A 401 response carries none of these, so
    /// a nil return means the fallback has nothing to say.
    static func statusFromHeaders(_ http: HTTPURLResponse, now: Date) -> ProviderStatus? {
        func number(_ name: String) -> Double? {
            http.value(forHTTPHeaderField: name).flatMap(Double.init)
        }
        guard let limit = number("anthropic-ratelimit-input-tokens-limit"),
              let remaining = number("anthropic-ratelimit-input-tokens-remaining"),
              limit > 0 else { return nil }

        let resetsAt = http.value(forHTTPHeaderField: "anthropic-ratelimit-input-tokens-reset")
            .flatMap { ClaudeSessionBlocks.parseTimestamp($0) }
        let fraction = min(max((limit - remaining) / limit, 0), 1)

        return ProviderStatus(
            kind: .claude,
            reading: .fraction(used: fraction, resetsAt: resetsAt),
            detail: "API input tokens per minute, from response headers",
            fetchedAt: now
        )
    }
}
