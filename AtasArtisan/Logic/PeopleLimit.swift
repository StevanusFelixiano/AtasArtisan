import Foundation

// MARK: - People limit

/// How many people, the host included, can add items of their own. Past it, people join share-only: they claim
/// pieces, join splits and ask to share, until a spot frees up and they add an item of their own (the server's
/// `take_seat`).
nonisolated enum PeopleLimit {
    /// The server's check on `groups.people_limit`.
    static let range = 2...50

    /// The setting's note.
    static let note = "Includes you as the host. Anyone who joins after that can only join shared items."

    /// Spots left to add items: nil without a limit.
    static func free(limit: Int?, full: Int) -> Int? { limit.map { max(0, $0 - full) } }

    /// "4 of 6 can add items" for the group screen; nil without a limit.
    static func line(limit: Int?, full: Int) -> String? {
        guard let limit else { return nil }
        return full >= limit ? "Full · \(limit) of \(limit) adding items" : "\(full) of \(limit) adding items"
    }
}
