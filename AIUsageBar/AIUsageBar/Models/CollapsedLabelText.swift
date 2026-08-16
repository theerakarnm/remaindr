import Foundation

/// Builds the collapsed menu bar string. Foundation-only on purpose, so the width budget
/// is checkable without a running app.
enum CollapsedLabelText {
    /// Hard character budget for the text beside the SF Symbol.
    static let budget = 14

    /// Joined with a bare middot: " · " with spaces overflows the budget at three providers.
    private static let separator = "\u{00B7}"

    static func text(for slots: [ProviderKind: ProviderSlot], source: LabelSource) -> String {
        switch source {
        case .provider(let kind):
            return clamp(single(slots[kind], kind: kind))
        case .allConfigured:
            let parts = ProviderKind.allCases.compactMap { kind -> String? in
                guard let slot = slots[kind] else { return nil }
                if slot.status == nil, slot.error == .notConfigured || slot.error == nil { return nil }
                return single(slot, kind: kind)
            }
            return clamp(parts.isEmpty ? "Not set up" : parts.joined(separator: separator))
        }
    }

    /// A warning glyph only when something actually failed. "Not configured" is not a failure.
    static func symbolName(for slots: [ProviderKind: ProviderSlot], source: LabelSource) -> String {
        let relevant: [ProviderSlot]
        switch source {
        case .provider(let kind): relevant = [slots[kind]].compactMap { $0 }
        case .allConfigured: relevant = Array(slots.values)
        }
        let failing = relevant.contains { slot in
            guard let error = slot.error else { return false }
            return error != .notConfigured
        }
        return failing ? "exclamationmark.triangle" : "gauge.with.needle"
    }

    private static func single(_ slot: ProviderSlot?, kind: ProviderKind) -> String {
        guard let slot else { return "\(kind.shortName) --" }
        if let status = slot.status {
            let value = format(status.reading)
            return slot.error == nil ? value : "\(value)!"
        }
        if let error = slot.error, error != .notConfigured {
            return "\(kind.shortName)!"
        }
        return "\(kind.shortName) --"
    }

    private static func format(_ reading: ProviderReading) -> String {
        switch reading {
        case .fraction(let used, _):
            return "\(Int((used * 100).rounded()))%"
        case .balance(let amount, let currency):
            return "\(symbol(for: currency))\(compact(amount))"
        }
    }

    private static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "CNY": return "\u{00A5}"
        case "EUR": return "\u{20AC}"
        default: return "\(currency.uppercased()) "
        }
    }

    /// Keeps big balances short: 1234.5 becomes 1.2k, 1234567 becomes 1.2M.
    private static func compact(_ amount: Decimal) -> String {
        let value = (amount as NSDecimalNumber).doubleValue
        let magnitude = abs(value)
        if magnitude >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if magnitude >= 1_000 { return String(format: "%.1fk", value / 1_000) }
        return String(format: "%.2f", value)
    }

    private static func clamp(_ value: String) -> String {
        value.count <= budget ? value : String(value.prefix(budget - 1)) + "\u{2026}"
    }
}
