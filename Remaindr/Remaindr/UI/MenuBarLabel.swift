import SwiftUI

/// The collapsed menu bar item: the chosen provider's monochrome glyph plus one short
/// string. Exactly one provider, picked in Settings.
struct MenuBarLabel: View {
    let store: ProviderStore
    let preferences: Preferences

    var body: some View {
        let kind = preferences.menuBarProvider
        HStack(spacing: 3) {
            if let glyph = ProviderGlyph.image(for: kind, size: ProviderGlyph.menuBarSize) {
                Image(nsImage: glyph)
            } else {
                Image(systemName: "gauge.with.needle")
            }
            Text(CollapsedLabelText.text(for: store.slots[kind]))
        }
        .accessibilityLabel("\(kind.displayName) usage")
    }
}
