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

    // MARK: Shared items after lock (board 10)

    /// Who holds pieces of a shared item once the order is locked, in the order every row and the piece bar list them
    /// (board 10, Open question 5): the owner, then me, then the others in the order they claimed.
    static func order<ID: Equatable>(owner: ID, me: ID?, claimers: [ID]) -> [ID] {
        [owner] + claimers.filter { $0 == me && $0 != owner } + claimers.filter { $0 != me && $0 != owner }
    }

    /// What a holder has: "keeps 5" for the owner ("keep 5" when that's me), "3 slices" for anyone else.
    static func holding(_ n: Int, of name: String, owner: Bool, you: Bool) -> String {
        owner ? "\(you ? "keep" : "keeps") \(n)" : count(n, of: name)
    }

    /// The whole-item button (10-3): "I took the whole Burnt Cheesecake 20 cm" while nothing is taken, "I took the rest ·
    /// 10 slices" once some are; nil once every piece is.
    static func bulk(_ name: String, left: Int, of pieces: Int) -> String? {
        guard left > 0 else { return nil }
        return left >= pieces ? "I took the whole \(name)" : "I took the rest · \(count(left, of: name))"
    }

    /// Beside the TAKEN tag (10-2b): "12:40" when the holder marked it themselves, "by you · 12:40" or "by Kevin · 12:15"
    /// when someone else did (`by` nil, "you" or their name).
    static func takenBy(_ by: String?, at time: String) -> String { by.map { "by \($0) · \(time)" } ?? time }

    /// A holder's row (10-3, 10-4): "Taken 12:40", "Taken by you · 12:40", "Taken by Kevin · 12:15".
    static func takenLine(_ by: String?, at time: String) -> String { "Taken \(takenBy(by, at: time))" }

    /// A shared item's line while it's delivered: "12 of 12 slices in the fridge"; none left, "All 12 slices taken ·
    /// 12:40" (`at` the last one taken, nil leaves it out).
    static func inFridge(left: Int, of pieces: Int, name: String, at: String?) -> String {
        if left > 0 { return "\(left) of \(count(pieces, of: name)) in the fridge" }
        return "All \(count(pieces, of: name)) taken" + (at.map { " · \($0)" } ?? "")
    }
}
