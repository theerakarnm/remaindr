import Foundation

/// What a completed update check concluded.
enum UpdateStatus: Equatable, Sendable {
    case upToDate(current: AppVersion)
    case updateAvailable(latest: AppVersion)
}

/// Every distinct failure the Settings row must be able to show differently.
/// Deliberately separate from `ProviderError`: an update check is not a provider
/// reading and must not widen the `UsageProvider` surface.
enum UpdateCheckError: Error, Equatable, Sendable {
    case offline
    case rateLimited
    case noRelease
    case malformedResponse(String)
    case serverError(status: Int)

    /// Short text shown in Settings. Never contains a URL or a response body.
    var shortDescription: String {
        switch self {
        case .offline: return "Offline"
        case .rateLimited: return "Rate limited"
        case .noRelease: return "No release found"
        case .malformedResponse: return "Bad response"
        case .serverError(let status): return "Server error \(status)"
        }
    }
}

/// Reads the newest published release from GitHub and compares its tag with the
/// running bundle's version. It downloads nothing, installs nothing, and sends no
/// credential: the whole feature is one unauthenticated GET plus a link.
struct UpdateChecker: Sendable {
    /// The page the UI links to. A constant, never a URL taken from the response:
    /// this endpoint is unauthenticated and unpinned, so a tampered `html_url`
    /// would otherwise become an attacker-chosen link the user is invited to click.
    static let releasesPageURL = URL(string: "https://github.com/theerakarnm/remaindr/releases/latest")!

    private static let endpoint = URL(string: "https://api.github.com/repos/theerakarnm/remaindr/releases/latest")!

    private let session: URLSession
    private let currentVersion: AppVersion

    /// `URLSession.shared`, not `PinnedSession.shared`. The pinning delegate is
    /// fail-closed for any host with no pins, so routing this call through it would
    /// cancel every check; and pinning github.com would break silently the next time
    /// GitHub rotates a certificate. System trust is the right level here because no
    /// key or token is sent.
    init(session: URLSession = .shared, currentVersion: AppVersion = AppVersion.current) {
        self.session = session
        self.currentVersion = currentVersion
    }

    private struct Payload: Decodable {
        let tag_name: String
        let draft: Bool?
        let prerelease: Bool?
    }

    func check() async throws -> UpdateStatus {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // A cancelled task is the caller going away, not a connectivity failure.
            if error.code == .cancelled { throw error }
            throw UpdateCheckError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.malformedResponse("no HTTP response")
        }
        // The 403 body is a rate-limit message, so status is classified before decoding.
        switch http.statusCode {
        case 200:
            break
        case 403, 429:
            // Unauthenticated callers get 60 requests an hour per IP, and GitHub
            // answers 403 rather than 429 once that budget is gone.
            throw UpdateCheckError.rateLimited
        case 404:
            throw UpdateCheckError.noRelease
        default:
            throw UpdateCheckError.serverError(status: http.statusCode)
        }

        return try Self.parse(data, currentVersion: currentVersion)
    }

    /// Pure so a harness can exercise it without a network.
    static func parse(_ data: Data, currentVersion: AppVersion) throws -> UpdateStatus {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UpdateCheckError.malformedResponse("release payload not decodable")
        }
        // A draft or a pre-release is not something to point a user at.
        guard payload.draft != true, payload.prerelease != true else {
            throw UpdateCheckError.noRelease
        }
        guard let latest = AppVersion(payload.tag_name) else {
            throw UpdateCheckError.malformedResponse("tag_name is not a version")
        }
        return latest > currentVersion
            ? .updateAvailable(latest: latest)
            : .upToDate(current: currentVersion)
    }
}
