import Foundation

/// Builds the two update strings the UI shows. Foundation-only on purpose, so the
/// wording is checkable without a running app - the same reason `CollapsedLabelText`
/// exists. No update string is written anywhere else.
enum UpdateStatusText {
    /// The Settings row. Reports the in-flight state first, then a failure, then the
    /// result, then "never checked".
    static func settings(status: UpdateStatus?,
                         error: UpdateCheckError?,
                         isChecking: Bool) -> String {
        if isChecking { return "Checking\u{2026}" }
        if let error { return "Check failed: \(error.shortDescription)" }
        switch status {
        case .updateAvailable(let latest): return "Update available: \(latest)"
        case .upToDate(let current): return "Up to date (\(current))"
        case nil: return "Not checked yet"
        }
    }

    /// The dropdown line. Nil when there is nothing to offer, so the panel stays as
    /// compact as it is today for the overwhelmingly common case.
    static func dropdown(available: AppVersion?) -> String? {
        guard let available else { return nil }
        return "Update available: \(available)"
    }
}
