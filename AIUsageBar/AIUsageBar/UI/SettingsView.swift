import SwiftUI

struct SettingsView: View {
    let preferences: Preferences
    let scheduler: RefreshScheduler

    private let keychain = KeychainStore()

    @State private var draftKeys: [ProviderKind: String] = [:]
    @State private var savedKinds: Set<ProviderKind> = []
    @State private var launchAtLogin = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("API keys") {
                ForEach(ProviderKind.allCases.filter { $0 != .claude }) { kind in
                    keyRow(kind)
                }
                LabeledContent("Claude") {
                    Text("Reads ~/.claude/projects. No key needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Allow a billed API request when no local sessions exist", isOn: Binding(
                    get: { preferences.allowBilledClaudeProbe },
                    set: { preferences.allowBilledClaudeProbe = $0 }
                ))
                .help("Sends one minimal POST /v1/messages to read anthropic-ratelimit headers. This is billed.")
                if preferences.allowBilledClaudeProbe {
                    keyRow(.claude)
                }
            }

            Section("Refresh") {
                Stepper(value: Binding(
                    get: { preferences.refreshIntervalMinutes },
                    set: { preferences.refreshIntervalMinutes = $0; scheduler.reschedule() }
                ), in: 1...60) {
                    Text("Every \(preferences.refreshIntervalMinutes) min")
                }
                Picker("Menu bar shows", selection: Binding(
                    get: { preferences.labelSource },
                    set: { preferences.labelSource = $0 }
                )) {
                    ForEach(LabelSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            try LoginItem.set(newValue)
                            message = nil
                        } catch {
                            message = "Could not change the login item: \(error.localizedDescription)"
                        }
                        launchAtLogin = LoginItem.isEnabled
                    }
                ))
                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            savedKinds = Set(ProviderKind.allCases.filter { keychain.hasKey(for: $0) })
        }
    }

    @ViewBuilder
    private func keyRow(_ kind: ProviderKind) -> some View {
        // The stored value is never read back into the field: presence only.
        LabeledContent(kind.displayName) {
            HStack {
                SecureField(savedKinds.contains(kind) ? "Key saved" : "Paste key",
                            text: Binding(
                                get: { draftKeys[kind] ?? "" },
                                set: { draftKeys[kind] = $0 }
                            ))
                Button("Save") { save(kind) }
                    .disabled((draftKeys[kind] ?? "").isEmpty)
                Button("Clear") { clear(kind) }
                    .disabled(!savedKinds.contains(kind))
            }
        }
    }

    private func save(_ kind: ProviderKind) {
        do {
            try keychain.set(draftKeys[kind] ?? "", for: kind)
            draftKeys[kind] = ""
            savedKinds = Set(ProviderKind.allCases.filter { keychain.hasKey(for: $0) })
            scheduler.reschedule()
            message = nil
        } catch {
            message = "Could not save the key to the Keychain."
        }
    }

    private func clear(_ kind: ProviderKind) {
        do {
            try keychain.remove(kind)
            draftKeys[kind] = ""
            savedKinds = Set(ProviderKind.allCases.filter { keychain.hasKey(for: $0) })
            scheduler.reschedule()
            message = nil
        } catch {
            message = "Could not clear the key from the Keychain."
        }
    }
}
