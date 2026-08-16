import AppKit
import SwiftUI

/// A provider's monochrome glyph, sized and marked as a template before SwiftUI sees it.
///
/// `Image(name).resizable().frame(...)` renders nothing inside a `MenuBarExtra` label:
/// AppKit measures that label itself, and a resizable image has no intrinsic size left to
/// fall back on, so it collapses. Baking the size into the `NSImage` avoids the problem.
/// The asset keeps its vector representation, so it stays crisp at any size.
@MainActor
enum ProviderGlyph {
    /// Conventional menu bar glyph size inside the 22pt bar.
    static let menuBarSize: CGFloat = 16

    private static var cache: [String: NSImage] = [:]

    /// Nil only if the asset is missing, which callers should treat as "fall back to a symbol"
    /// rather than as a reason to show no icon at all.
    static func image(for kind: ProviderKind, size: CGFloat) -> NSImage? {
        let key = "\(kind.rawValue)@\(size)"
        if let cached = cache[key] { return cached }
        guard let glyph = NSImage(named: kind.iconAssetName)?.copy() as? NSImage else { return nil }
        // The three glyphs are drawn on a shared square grid, scaled so they carry the same
        // optical weight, so one square size fits all of them.
        glyph.size = NSSize(width: size, height: size)
        glyph.isTemplate = true
        cache[key] = glyph
        return glyph
    }
}
