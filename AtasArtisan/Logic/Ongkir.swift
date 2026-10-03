import Foundation

// MARK: - Ongkir and discount (E)

/// The delivery part of each bill, as the server computes it (`group_bill_live_v`, migration 20261002232926).
nonisolated enum Ongkir {
    /// From Rp 200.000 Atas delivers free: the server stores ongkir 0 and discount 0, whatever the host types.
    static let freeFrom = 200_000
    /// Each member's share is truncated to this many rupiah; the host's bill takes the remainder.
    static let roundTo = 100
    static let maxAmount = 9_999_999

    static func isFree(subtotal: Int) -> Bool { subtotal >= freeFrom }

    /// The discount as applied: never more than items + ongkir, so the total can't go below Rp 0.
    static func cappedDiscount(_ discount: Int, subtotal: Int, ongkir: Int) -> Int { min(discount, subtotal + ongkir) }

    /// One member's share of `net` (ongkir − discount) among `payers`, truncated to Rp 100 towards zero.
    static func each(net: Int, payers: Int) -> Int {
        guard payers > 0 else { return 0 }
        return net / payers / roundTo * roundTo
    }

    /// Every bill's share of `net`, in the order given. Members whose items come to Rp 0 pay nothing; the others pay
    /// `each`, a negative share stopping at −items; the host takes the remainder (also with no items), likewise never
    /// below −items. Nobody has items: nobody pays anything.
    static func shares(net: Int, bills: [(items: Int, host: Bool)]) -> [Int] {
        let payers = bills.filter { $0.items > 0 }.count
        guard payers > 0 else { return bills.map { _ in 0 } }
        let one = each(net: net, payers: payers)
        var out = bills.map { b in b.host || b.items == 0 ? 0 : max(one, -b.items) }
        if let h = bills.firstIndex(where: \.host) {
            out[h] = max(net - out.reduce(0, +), -bills[h].items)
        }
        return out
    }
}
