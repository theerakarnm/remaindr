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

/// A linear meter that layers the weekly window behind the rolling one when the provider
/// reports both. The solid front fill is the rolling window the row's first caption
/// describes; the lighter fill behind it is the weekly allowance, which spans a longer
/// window and so reads as the stack's back layer.
private struct StackedUsageBar: View {
    /// 0...1 of the rolling window, drawn as the solid front fill.
    let sessionUsed: Double
    /// 0...1 of the weekly window, drawn as the lighter back fill. Nil draws a plain bar.
    let weeklyUsed: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let weeklyUsed {
                    Capsule()
                        .fill(.tint.opacity(0.35))
                        .frame(width: proxy.size.width * Self.clamped(weeklyUsed))
                }
                Capsule()
                    .fill(.tint)
                    .frame(width: proxy.size.width * Self.clamped(sessionUsed))
            }
        }
        .frame(height: 6)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
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
                    StackedUsageBar(sessionUsed: used, weeklyUsed: status.weekly?.used)
                    HStack {
                        Text("\(Int((used * 100).rounded()))% used")
                        if let resetsAt {
                            Text("resets \(resetsAt, style: .relative)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let weekly = status.weekly {
                        HStack {
                            Text("Weekly \(Int((weekly.used * 100).rounded()))% used")
                            if let resetsAt = weekly.resetsAt {
                                Text("resets \(resetsAt, style: .relative)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
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
