import SwiftUI

/// The collapsed menu bar item: one SF Symbol plus one short string, driven by whichever
/// source the user picked in Settings.
struct MenuBarLabel: View {
    let store: ProviderStore
    let preferences: Preferences

    var body: some View {
        let source = preferences.labelSource
        HStack(spacing: 3) {
            Image(systemName: CollapsedLabelText.symbolName(for: store.slots, source: source))
            Text(CollapsedLabelText.text(for: store.slots, source: source))
        }
        .accessibilityLabel("\(source.displayName) usage")
    }
}
