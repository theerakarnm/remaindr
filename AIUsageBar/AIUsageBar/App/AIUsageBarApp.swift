import SwiftUI

@main
struct AIUsageBarApp: App {
    @State private var preferences: Preferences
    @State private var store: ProviderStore
    @State private var scheduler: RefreshScheduler

    init() {
        let preferences = Preferences()
        let store = ProviderStore(preferences: preferences)
        let scheduler = RefreshScheduler(store: store, preferences: preferences)
        _preferences = State(initialValue: preferences)
        _store = State(initialValue: store)
        _scheduler = State(initialValue: scheduler)
    }

    var body: some Scene {
        MenuBarExtra {
            DropdownPanel(store: store)
                .task { scheduler.start() }
        } label: {
            MenuBarLabel(store: store, preferences: preferences)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences, scheduler: scheduler)
        }
    }
}
