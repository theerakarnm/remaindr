import Foundation

/// Drives auto-refresh. Pauses entirely when no provider is configured, as the brief requires.
@MainActor
final class RefreshScheduler {
    private let store: ProviderStore
    private let preferences: Preferences
    private var task: Task<Void, Never>?

    init(store: ProviderStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
    }

    func start() {
        stop()
        guard store.anyConfigured else { return }
        let interval = UInt64(preferences.refreshIntervalMinutes) * 60 * 1_000_000_000
        task = Task { [store] in
            await store.refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                guard store.anyConfigured else { return }
                await store.refreshAll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Call after the interval changes or a key is added or removed.
    func reschedule() { start() }
}
