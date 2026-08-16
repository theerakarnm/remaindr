import Foundation

/// Builds the collapsed menu bar string. Foundation-only on purpose, so the width budget
/// is checkable without a running app.
enum CollapsedLabelText {
    /// Hard character budget for the text beside the provider glyph.
    static let budget = 14

    /// The label reports exactly one provider, and the glyph beside it says which one, so
    /// no short-name prefix is needed here.
    static func text(for slot: ProviderSlot?) -> String {
        clamp(single(slot))
    }

    private static func single(_ slot: ProviderSlot?) -> String {
        guard let slot else { return "--" }
        if let status = slot.status {
            let value = format(status.reading)
            return slot.error == nil ? value : "\(value)!"
        }
        // A bare "!" rather than the error text: spelling out "Offline" or "Server error 500"
        // would resize the status item on every failure kind. The dropdown carries the reason.
        if let error = slot.error, error != .notConfigured {
            return "--!"
        }
        return "--"
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
