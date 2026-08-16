import Foundation

/// Claude has no public "remaining subscription limit" endpoint, so this provider has two
/// sources, in order:
///  1. local session files under `~/.claude/projects/**/*.jsonl`, aggregated into rolling
///     5-hour blocks;
///  2. `anthropic-ratelimit-*` response headers, but only when the user has explicitly
///     opted into a billed probe request, because the headers exist only on a successful
///     Messages API call.
/// When neither is available it throws `.notConfigured`. It never invents a number.
struct ClaudeProvider: UsageProvider {
    let kind: ProviderKind = .claude

    private let keychain: KeychainStore
    private let session: URLSession
    private let projectsDirectory: URL
    /// Off unless the user turns it on in Settings. A probe request is billed.
    private let allowBilledProbe: Bool

    static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    init(keychain: KeychainStore = KeychainStore(),
         session: URLSession = .shared,
         projectsDirectory: URL = ClaudeProvider.defaultProjectsDirectory,
         allowBilledProbe: Bool = false) {
        self.keychain = keychain
        self.session = session
        self.projectsDirectory = projectsDirectory
        self.allowBilledProbe = allowBilledProbe
    }

    func fetch(now: Date) async throws -> ProviderStatus {
        let directory = projectsDirectory
        // The scan touches ~1600 files, so keep it off the main actor.
        let blocks = await Task.detached(priority: .utility) {
            Self.scanBlocks(in: directory)
        }.value

        if let status = Self.status(from: blocks, now: now) {
            return status
        }

        guard allowBilledProbe, let key = try keychain.value(for: kind), !key.isEmpty else {
            throw ProviderError.notConfigured
        }
        return try await probeHeaders(key: key, now: now)
    }

    // MARK: - Local session files

    /// Streams every `.jsonl` under the projects directory and aggregates the blocks.
    /// A missing directory, an unreadable file, or a malformed line is skipped, never fatal.
    static func scanBlocks(in directory: URL) -> [ClaudeUsageBlock] {
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [ClaudeUsageEntry] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
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
