import SwiftUI

struct SettingsView: View {
    let preferences: Preferences
    let scheduler: RefreshScheduler
    let updateStore: UpdateStore

    private let settings = SettingStore.shared

    @State private var draftKeys: [ProviderKind: String] = [:]
    @State private var savedKinds: Set<ProviderKind> = []
    @State private var launchAtLogin = false
    @State private var message: String?
    @State private var claudeConnected = false
    @State private var claudeInvalid = false
    @State private var isConnectingClaude = false

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
                    HStack {
                        claudeBadge
                        Button(claudeConnected ? "Reconnect" : "Connect") {
                            Task { await connectClaude() }
                        }
                        .disabled(isConnectingClaude)
                    }
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
                LabeledContent("Updates") {
                    HStack {
                        Text(UpdateStatusText.settings(status: updateStore.status,
                                                       error: updateStore.error,
                                                       isChecking: updateStore.isChecking))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Check now") { Task { await updateStore.check() } }
                            .disabled(updateStore.isChecking)
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            savedKinds = Set(ProviderKind.allCases.filter { settings.hasApiKey(for: $0) })
            reloadClaudeState()
        }
    }

    @ViewBuilder
    private var claudeBadge: some View {
        if claudeInvalid {
            Label("Invalid token", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.orange)
                .help("Sign in to Claude Code, then click Connect again")
        } else if claudeConnected {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
                .help("Reading plan limits with the token saved in setting.json")
        } else {
            Label("Not connected", systemImage: "circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .help("Connect copies Claude Code's sign-in token into setting.json, once")
        }
    }

    /// The manual Connect action. Prompts for the login keychain password at most
    /// twice; on failure the badge turns to "Invalid token" and stays there until
    /// the user signs in to Claude Code and clicks Connect again.
    private func connectClaude() async {
        isConnectingClaude = true
        defer { isConnectingClaude = false }
        let ok = await ClaudeAccountUsage.connect(
            settings: settings,
            verify: { token in
                // PinnedSession, not .shared: this request carries the OAuth token,
                // and every credential-bearing request must fail closed on a pin
                // mismatch (PinnedSession.swift documents the invariant).
                (try? await ClaudeAccountUsage.fetch(token: token, session: PinnedSession.shared)) != nil
            })
        reloadClaudeState()
        if !ok {
            message = "Could not connect. Sign in to Claude Code, then click Connect again."
        } else {
            message = nil
            scheduler.reschedule()
        }
    }

    private func reloadClaudeState() {
        let oauth = settings.claudeOAuth
        claudeConnected = oauth.accessToken != nil && !(oauth.invalid ?? false)
        claudeInvalid = oauth.invalid == true && oauth.accessToken != nil
    }

    @ViewBuilder
    private func statusBadge(for kind: ProviderKind) -> some View {
        if savedKinds.contains(kind) {
            Label("Set", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
                .help("\(kind.displayName) key is saved in setting.json")
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
        settings.setApiKey(draftKeys[kind] ?? "", for: kind)
        draftKeys[kind] = ""
        savedKinds = Set(ProviderKind.allCases.filter { settings.hasApiKey(for: $0) })
        scheduler.reschedule()
        message = nil
    }

    private func clear(_ kind: ProviderKind) {
        settings.setApiKey(nil, for: kind)
        draftKeys[kind] = ""
        savedKinds = Set(ProviderKind.allCases.filter { settings.hasApiKey(for: $0) })
        scheduler.reschedule()
        message = nil
    }
}
