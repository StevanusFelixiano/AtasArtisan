import Foundation

// MARK: - Shared items in pieces (A2)

/// An item shared in pieces: the owner sets 2–24 pieces, anyone else in the group claims some until the order
/// locks, and the owner keeps the rest. Amounts match `group_bill_v`: a joiner pays ⌊price × n ÷ pieces⌋ rupiah and
/// the owner pays what is left, so the shares add up to the price.
nonisolated enum Pieces {
    /// What a joiner with `n` of `pieces` pays.
    static func amount(price: Int, pieces: Int, n: Int) -> Int {
        guard pieces > 0, n > 0 else { return 0 }
        return price * n / pieces
    }

    /// What the owner pays: the price less every joiner's amount.
    static func ownerAmount(price: Int, pieces: Int, claims: [Int]) -> Int {
        price - claims.reduce(0) { $0 + amount(price: price, pieces: pieces, n: $1) }
    }

    /// "Rp 21.667 a piece": the price per piece, rounded.
    static func each(price: Int, pieces: Int) -> Int {
        pieces > 0 ? Int((Double(price) / Double(pieces)).rounded()) : price
    }

    /// The piece count a product starts at. By name first (the owner's call, 2026-10-03): cheesecakes and brownies 8,
    /// banana cake and sourdough 2. Otherwise by size: 20×20 trays 16, 20 cm cakes 12, anything else 8.
    static func defaultCount(_ name: String) -> Int {
        let lower = name.lowercased()
        for (word, count) in [("cheesecake", 8), ("brownie", 8), ("banana cake", 2), ("sourdough", 2)] where lower.contains(word) {
            return count
        }
        let n = lower.replacingOccurrences(of: " ", with: "")
        if n.contains("20x20") || n.contains("20×20") { return 16 }
        if n.contains("20cm") { return 12 }
        return 8
    }

    /// "1 piece", "3 pieces".
    static func label(_ n: Int) -> String { n == 1 ? "1 piece" : "\(n) pieces" }

    /// "1st", "2nd", "3rd", "4th", "11th".
    static func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(suffix)"
    }
}

