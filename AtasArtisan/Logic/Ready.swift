import Foundation

// MARK: - Ready (open orders)

/// While an order is open, each member with a stake taps Ready; the host locks when everyone is. A stake is an item of
/// their own or pieces claimed of someone's shared item (the server's `has_stake`). The host is never counted, and
/// members with no stake are taken off the list at lock.
nonisolated enum Ready {
    struct Person {
        var id: UUID
        var stake: Bool
        var ready: Bool
    }

    /// "N of M ready": the non-host members with a stake, and how many of them are ready.
    static func count(_ people: [Person], host: UUID) -> (ready: Int, of: Int) {
        let counted = people.filter { $0.id != host && $0.stake }
        return (counted.filter(\.ready).count, counted.count)
    }

    /// Non-host members with nothing in the order: the lock removes them.
    static func empty(_ people: [Person], host: UUID) -> Int {
        people.filter { $0.id != host && !$0.stake }.count
    }

    /// The host's line over the member list; nil when nobody has a stake yet.
    static func line(_ c: (ready: Int, of: Int)) -> String? {
        guard c.of > 0 else { return nil }
        return c.ready == c.of ? (c.of == 1 ? "1 of 1 ready" : "All \(c.of) ready") : "\(c.ready) of \(c.of) ready"
    }

    /// What the lock question adds: who isn't ready yet, and who will be removed. Empty when there is nothing to warn.
    static func lockWarning(_ c: (ready: Int, of: Int), empty: Int) -> String {
        var parts: [String] = []
        let waiting = c.of - c.ready
        if waiting > 0 { parts.append(waiting == 1 ? "1 person isn’t ready yet." : "\(waiting) people aren’t ready yet.") }
        if empty > 0 {
            parts.append(empty == 1 ? "1 person has nothing in the order and will be taken off the list."
                                    : "\(empty) people have nothing in the order and will be taken off the list.")
        }
        return parts.joined(separator: " ")
    }
}
