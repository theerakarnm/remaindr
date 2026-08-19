import Foundation

/// Independent per-provider state. A failure writes `error` and leaves `status` alone,
/// so a stale reading stays on screen next to an error indicator. It is never zeroed.
struct ProviderSlot: Equatable, Sendable {
    var status: ProviderStatus?
    var error: ProviderError?
    var isRefreshing: Bool = false
}

@MainActor
@Observable
final class ProviderStore {
    private(set) var slots: [ProviderKind: ProviderSlot]

    private let settings: SettingStore
    private let preferences: Preferences

    init(settings: SettingStore = .shared, preferences: Preferences) {
        self.settings = settings
        self.preferences = preferences
        self.slots = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, ProviderSlot()) })
    }

    /// True when at least one provider can produce a reading: any stored key, or a
    /// readable Claude projects directory.
    var anyConfigured: Bool {
        if settings.hasApiKey(for: .zai) || settings.hasApiKey(for: .deepseek) { return true }
        return FileManager.default.fileExists(atPath: ClaudeProvider.defaultProjectsDirectory.path)
    }

    private func provider(for kind: ProviderKind) -> any UsageProvider {
        switch kind {
        case .claude:
            return ClaudeProvider(settings: settings,
                                  session: PinnedSession.shared,
                                  allowBilledProbe: preferences.allowBilledClaudeProbe)
        case .zai:
            return ZAIProvider(settings: settings, session: PinnedSession.shared)
        case .deepseek:
            return DeepSeekProvider(settings: settings, session: PinnedSession.shared)
        }
    }

    /// Fetches every provider concurrently off the main actor, then applies the results here.
    /// The task group must not capture `self`: a `@MainActor` closure inside `addTask` is
    /// rejected by the region-based isolation checker.
    func refreshAll(now: Date = Date()) async {
        for kind in ProviderKind.allCases {
            slots[kind, default: ProviderSlot()].isRefreshing = true
        }
        let work = ProviderKind.allCases.map { ($0, provider(for: $0)) }
        var results: [(ProviderKind, Result<ProviderStatus, any Error>)] = []
        await withTaskGroup(of: (ProviderKind, Result<ProviderStatus, any Error>).self) { group in
            for (kind, provider) in work {
                group.addTask {
                    do { return (kind, .success(try await provider.fetch(now: now))) }
                    catch { return (kind, .failure(error)) }
                }
            }
            for await result in group { results.append(result) }
        }
        for (kind, result) in results { apply(result, to: kind) }
        for kind in ProviderKind.allCases {
            slots[kind, default: ProviderSlot()].isRefreshing = false
        }
    }

    func refresh(_ kind: ProviderKind, now: Date = Date()) async {
        slots[kind, default: ProviderSlot()].isRefreshing = true
        let provider = provider(for: kind)
        let result: Result<ProviderStatus, any Error>
        do { result = .success(try await provider.fetch(now: now)) }
        catch { result = .failure(error) }
        apply(result, to: kind)
        slots[kind, default: ProviderSlot()].isRefreshing = false
    }

    /// Keeps the previous status on failure. Never writes nil, never writes a zero.
    private func apply(_ result: Result<ProviderStatus, any Error>, to kind: ProviderKind) {
        switch result {
        case .success(let status):
            slots[kind] = ProviderSlot(status: status, error: nil, isRefreshing: slots[kind]?.isRefreshing ?? false)
        case .failure(let error as ProviderError):
            slots[kind, default: ProviderSlot()].error = error
        case .failure:
            slots[kind, default: ProviderSlot()].error = .malformedResponse("unexpected failure")
        }
    }
}
