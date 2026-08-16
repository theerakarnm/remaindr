import SwiftUI

/// One row per provider: name, a progress bar or a balance figure, a secondary line, and
/// the per-provider last-refreshed time.
struct DropdownPanel: View {
    let store: ProviderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ProviderKind.allCases) { kind in
                ProviderRow(kind: kind, slot: store.slots[kind] ?? ProviderSlot())
            }
            Divider()
            HStack {
                Button("Refresh") { Task { await store.refreshAll() } }
                Spacer()
                SettingsLink { Text("Settings…") }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct ProviderRow: View {
    let kind: ProviderKind
    let slot: ProviderSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(kind.displayName).font(.headline)
                if slot.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let error = slot.error {
                    Label(error.shortDescription, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let status = slot.status {
                switch status.reading {
                case .fraction(let used, let resetsAt):
                    ProgressView(value: used)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("\(Int((used * 100).rounded()))% used")
                        if let resetsAt {
                            Text("resets \(resetsAt, style: .relative)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .balance(let amount, let currency):
                    Text(amount.formatted(.currency(code: currency)))
                        .font(.title3)
                        .monospacedDigit()
                }
                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Updated \(status.fetchedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(slot.error?.shortDescription ?? "Not configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
