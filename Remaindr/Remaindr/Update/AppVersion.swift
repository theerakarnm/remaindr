import Foundation

/// A dotted numeric version, compared component by component. Foundation-only on
/// purpose so the comparison is checkable without a running app, the same reason
/// `CollapsedLabelText` exists.
///
/// Accepts an optional leading `v` because GitHub release tags carry one (`v1.0.0`)
/// while `CFBundleShortVersionString` does not (`1.0`). Anything that is not purely
/// numeric components - `1.0-beta`, `2026.08.19-rc1`, an empty string - fails to
/// parse rather than silently comparing as some fallback.
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    /// One to four non-negative components, in order of significance.
    let components: [Int]

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var parsed: [Int] = []
        for part in parts {
            // `isNumber` alone is true for non-ASCII digits such as "½".
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part) else { return nil }
            parsed.append(value)
        }
        self.components = parsed
    }

    /// The running app's version. Falls back to `0` so a bundle with no version
    /// string can never read as newer than a published release.
    static var current: AppVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw.flatMap(AppVersion.init) ?? AppVersion("0")!
    }

    /// Zero-pads the shorter side, so `1.0` and `1.0.0` are equal rather than `1.0`
    /// reading as older. The app ships MARKETING_VERSION 1.0 while the matching
    /// release is tagged v1.0.0; without this padding every user would be told an
    /// update exists.
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    /// Defined explicitly rather than synthesised, so `1.0` equals `1.0.0`.
    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    /// Rendered without the leading `v`, so UI text reads `1.1.0`, not `v1.1.0`.
    var description: String {
        components.map(String.init).joined(separator: ".")
    }
}
