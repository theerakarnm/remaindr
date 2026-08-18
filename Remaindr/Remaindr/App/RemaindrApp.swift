import SwiftUI

@main
struct RemaindrApp: App {
    @State private var preferences: Preferences
    @State private var store: ProviderStore
    @State private var scheduler: RefreshScheduler
    @State private var updateStore: UpdateStore

    init() {
        let preferences = Preferences()
        if !preferences.keychainAccessibilityUpgraded {
            KeychainStore().upgradeAccessibility()
            preferences.keychainAccessibilityUpgraded = true
        }
        let store = ProviderStore(preferences: preferences)
        let scheduler = RefreshScheduler(store: store, preferences: preferences)
        let updateStore = UpdateStore(preferences: preferences)
        _preferences = State(initialValue: preferences)
        _store = State(initialValue: store)
        _scheduler = State(initialValue: scheduler)
        _updateStore = State(initialValue: updateStore)
    }

    var body: some Scene {
        MenuBarExtra {
            DropdownPanel(store: store, updateStore: updateStore)
                .task {
                    scheduler.start()
                    await updateStore.checkIfDue()
                }
        } label: {
            MenuBarLabel(store: store, preferences: preferences)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences, scheduler: scheduler, updateStore: updateStore)
        }
    }
}
