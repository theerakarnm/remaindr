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
            // First, because the collapsed label reports exactly one provider and this is
            // the only control that decides which. The window is a fixed 450pt tall and the
            // form is longer than that, so anything below "Refresh" needs scrolling to find.
            Section("Menu bar") {
                Picker("Shows", selection: Binding(
                    get: { preferences.menuBarProvider },
                    set: { preferences.menuBarProvider = $0 }
                )) {
                    ForEach(ProviderKind.allCases) { kind in
                        Label {
                            Text(kind.displayName)
                        } icon: {
                            if let glyph = ProviderGlyph.image(for: kind, size: 14) {
                                Image(nsImage: glyph)
                            }
                        }
                        .tag(kind)
                    }
                }
            }

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
    private func statusBadge(for kind: ProviderKind) -> some View {
        if savedKinds.contains(kind) {
            Label("Set", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
                .help("\(kind.displayName) key is saved in Keychain")
        } else {
            Label("Not set", systemImage: "circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .help("No \(kind.displayName) key saved")
        }
    }

    @ViewBuilder
    private func keyRow(_ kind: ProviderKind) -> some View {
        // The stored value is never read back into the field: presence only.
        LabeledContent {
            HStack {
                SecureField("Paste key", text: Binding(
                    get: { draftKeys[kind] ?? "" },
                    set: { draftKeys[kind] = $0 }
                ))
                Button("Save") { save(kind) }
                    .disabled((draftKeys[kind] ?? "").isEmpty)
                Button("Clear") { clear(kind) }
                    .disabled(!savedKinds.contains(kind))
            }
        } label: {
            HStack(spacing: 4) {
                Text(kind.displayName)
                statusBadge(for: kind)
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
