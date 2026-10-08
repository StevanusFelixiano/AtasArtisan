import Foundation

// MARK: - Pickup (board 7)

/// Once an order is delivered, each person with food in it says when they've taken it out of the office fridge.
/// Counted: active members who own an item or hold claimed pieces, the host included (the server's `has_food`).
nonisolated enum Pickup {
    /// The unit a shared item is cut into: cakes in slices, anything else in pieces (the server's `unit_count`).
    static func word(_ name: String, _ n: Int) -> String {
        name.lowercased().contains("cake") ? (n == 1 ? "slice" : "slices") : (n == 1 ? "piece" : "pieces")
    }

    /// "3 slices", "1 piece".
    static func count(_ n: Int, of name: String) -> String { "\(n) \(word(name, n))" }

    /// A whole item as the fridge lists it: "2× Pain Au Chocolate", "Brioche Bun".
    static func whole(_ name: String, qty: Int) -> String { qty > 1 ? "\(qty)× \(name)" : name }

    /// Pieces of a shared item still in the fridge: every holder's pieces until they've taken theirs.
    static func left(_ holders: [(pieces: Int, taken: Bool)]) -> Int {
        holders.filter { !$0.taken }.reduce(0) { $0 + $1.pieces }
    }

    /// The Pickup card's line (7-1, 7-2, 7-3). The host reads who is left ("4 of 6 taken · Kevin, Nadia left"), a member
    /// who has taken theirs ("3 of 6 taken · you, Rani, Dimas"). Nobody yet: "0 of 6 taken"; everyone: "Fridge is clear ·
    /// all 6 taken".
    static func line(taken: [String], left: [String], host: Bool) -> String {
        let n = taken.count + left.count
        if n > 0 && left.isEmpty { return "Fridge is clear · all \(n) taken" }
        let head = "\(taken.count) of \(n) taken"
        if taken.isEmpty { return head }
        return host ? "\(head) · \(names(left)) left" : "\(head) · \(names(taken))"
    }

    /// "Kevin, Nadia"; past three names, "Kevin, Nadia and 2 more".
    static func names(_ list: [String]) -> String {
        list.count <= 3 ? list.joined(separator: ", ") : list.prefix(2).joined(separator: ", ") + " and \(list.count - 2) more"
    }
}
