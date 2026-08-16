import Foundation

/// One assistant turn read out of a Claude Code session `.jsonl` file.
struct ClaudeUsageEntry: Sendable, Equatable {
    let timestamp: Date
    let dedupeKey: String?
    let inputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int

    var totalTokens: Int {
        inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens
    }
}

/// A rolling 5-hour usage block, ccusage-style.
struct ClaudeUsageBlock: Sendable, Equatable {
    let startedAt: Date
    let endsAt: Date
    let totalTokens: Int
}

/// Pure aggregation over Claude Code session files. No I/O lives here, so a harness can
/// drive it with a fixture and a fixed `now`.
enum ClaudeSessionBlocks {
    static let blockDuration: TimeInterval = 5 * 60 * 60

    /// Decodes one JSONL line. Returns nil for every line that is not a usable assistant
    /// turn: malformed JSON, a non-assistant record, or a synthetic model.
    static func entry(fromLine line: String) -> ClaudeUsageEntry? {
        guard let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["type"] as? String == "assistant",
              let message = root["message"] as? [String: Any],
              (message["model"] as? String) != "<synthetic>",
              let usage = message["usage"] as? [String: Any],
              let stamp = root["timestamp"] as? String,
              let timestamp = parseTimestamp(stamp)
        else { return nil }

        // 13 of 28443 real records carry no requestId. Those still count; they just
        // cannot be deduplicated, which is the safe direction.
        let messageID = message["id"] as? String
        let requestID = root["requestId"] as? String
        let dedupeKey = messageID.flatMap { id in requestID.map { "\(id):\($0)" } }

        return ClaudeUsageEntry(
            timestamp: timestamp,
            dedupeKey: dedupeKey,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0
        )
    }

    /// Groups entries into rolling 5-hour blocks. A block starts at the UTC hour floor of
    /// its first entry and closes when an entry is 5h past the block start or 5h past the
    /// previous entry.
    static func blocks(from entries: [ClaudeUsageEntry]) -> [ClaudeUsageBlock] {
        var seen = Set<String>()
        let ordered = entries
            .filter { entry in
                guard let key = entry.dedupeKey else { return true }
                return seen.insert(key).inserted
            }
            .sorted { $0.timestamp < $1.timestamp }

        var result: [ClaudeUsageBlock] = []
        var start: Date?
        var previous: Date?
        var total = 0

        for entry in ordered {
            if let blockStart = start, let last = previous,
               entry.timestamp.timeIntervalSince(blockStart) < blockDuration,
               entry.timestamp.timeIntervalSince(last) < blockDuration {
                total += entry.totalTokens
                previous = entry.timestamp
                continue
            }
            if let blockStart = start {
                result.append(ClaudeUsageBlock(startedAt: blockStart,
                                               endsAt: blockStart.addingTimeInterval(blockDuration),
                                               totalTokens: total))
            }
            start = hourFloor(entry.timestamp)
            previous = entry.timestamp
            total = entry.totalTokens
        }
        if let blockStart = start {
            result.append(ClaudeUsageBlock(startedAt: blockStart,
                                           endsAt: blockStart.addingTimeInterval(blockDuration),
                                           totalTokens: total))
        }
        return result
    }

    /// The block containing `now`, if any.
    static func activeBlock(in blocks: [ClaudeUsageBlock], now: Date) -> ClaudeUsageBlock? {
        blocks.first { $0.startedAt <= now && now < $0.endsAt }
    }

    /// `Date.ISO8601FormatStyle` is a Sendable struct; an `ISO8601DateFormatter` static is
    /// a Swift 6 error. Session files carry fractional seconds, but fall back to the plain
    /// form rather than dropping a turn.
    private static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let iso8601NoFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func parseTimestamp(_ value: String) -> Date? {
        (try? iso8601.parse(value)) ?? (try? iso8601NoFraction.parse(value))
    }

    private static func hourFloor(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }
}
