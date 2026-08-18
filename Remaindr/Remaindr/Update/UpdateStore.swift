import Foundation

/// Update state for the UI, mirroring `ProviderStore`: a failure writes `error` and
/// leaves the last `status` alone, so a known result stays on screen instead of
/// blanking.
@MainActor
@Observable
final class UpdateStore {
    /// At most one automatic check a day. GitHub allows 60 unauthenticated requests
    /// an hour per IP, and a menu bar app that stays running for weeks must not
    /// spend that budget on version strings.
    static let minimumInterval: TimeInterval = 24 * 60 * 60

    private(set) var status: UpdateStatus?
    private(set) var error: UpdateCheckError?
    private(set) var isChecking = false

    private let checker: UpdateChecker
    private let preferences: Preferences

    init(checker: UpdateChecker = UpdateChecker(), preferences: Preferences) {
        self.checker = checker
        self.preferences = preferences
    }

    /// The version to offer, or nil when up to date or not yet checked.
    var availableVersion: AppVersion? {
        guard case .updateAvailable(let latest) = status else { return nil }
        return latest
    }

    /// Called the first time the dropdown is built. Skips the network entirely when
    /// the last check is recent. Note this is NOT app launch: `MenuBarExtra(.window)`
    /// builds its content lazily, so the first check happens on first dropdown open.
    func checkIfDue(now: Date = Date()) async {
        if let last = preferences.lastUpdateCheck,
           now.timeIntervalSince(last) < Self.minimumInterval {
            return
        }
        await check(now: now)
    }

    /// The "Check now" button. Always makes the request.
    func check(now: Date = Date()) async {
        isChecking = true
        defer { isChecking = false }
        do {
            status = try await checker.check()
            error = nil
        } catch let failure as UpdateCheckError {
            error = failure
        } catch let urlError as URLError where urlError.code == .cancelled {
            // The caller went away; leave the timestamp alone so the next launch retries.
            return
        } catch {
            self.error = .malformedResponse("unexpected failure")
        }
        // Stamped even on failure, so a persistently offline machine does not retry
        // on every launch. "Check now" is the override.
        preferences.lastUpdateCheck = now
    }
}
