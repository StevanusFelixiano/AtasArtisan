import Foundation

// Rows as PostgREST returns them. Property names are the column names (no CodingKeys, no decoder strategy
// to keep in step with the schema); dates decode from timestamptz.

nonisolated struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var phone: String
    var name: String
    var msg_lang: String
    var notify_mute: [String]
    var avatar: String?
    /// Picture background, a key of `Art.backgrounds`; nil = the pastel from join order.
    var avatar_bg: String?
}

nonisolated struct PayoutAccount: Codable, Identifiable, Hashable {
    var id = UUID()
    var user_id: UUID?
    var label = ""
    var account_name = ""
    var number = ""
}

nonisolated struct Address: Codable, Identifiable, Hashable {
    var id = UUID()
    var user_id: UUID?
    var label = ""
    var area = "Kuta"
    var detail = ""
    var maps_url = ""
}

nonisolated enum GroupState: String, Codable, CaseIterable {
    case open, locked, edits, sent, confirmed, delivered, closed, cancelled

    var title: String {
        switch self {
        case .open: "Open"
        case .locked: "Locked"
        case .edits: "Edits requested"
        case .sent: "Sent to Atas"
        case .confirmed: "Confirmed by Atas"
        case .delivered: "Delivered"
        case .closed: "Closed"
        case .cancelled: "Cancelled"
        }
    }
    var isLive: Bool { ![.closed, .cancelled].contains(self) }
}

nonisolated struct OrderGroup: Codable, Identifiable, Hashable {
    var id: UUID
    var code: String
    var host_id: UUID
    var name: String
    var personal: Bool
    var area: String
    var address_label: String
    var address_detail: String
    var maps_url: String
    var delivery_at: Date
    var cutoff_at: Date?
    var pay_rule: String
    var msg_lang: String
    var payout_account_id: UUID?
    var state: GroupState
    var ongkir: Int?
    var discount: Int?
    var created_at: Date
    var sent_at: Date?
    var confirmed_at: Date?
    var delivered_at: Date?
    var closed_at: Date?
    /// Bills are final and frozen; members may pay (pay first from lock or the entered ongkir, order first at confirm).
    var bill_final_at: Date?
    /// Pay first: when the host asked Atas for the ongkir.
    var ongkir_asked_at: Date?
    /// When the host entered Atas's ongkir; nil while not entered, and when ongkir is free from Rp 200.000.
    var ongkir_set_at: Date?

    var payFirst: Bool { pay_rule == "pay_first" }
}

/// What a host fills in to create a group. Only the columns clients may insert.
nonisolated struct NewGroup: Encodable {
    var name: String
    var personal: Bool
    var area: String
    var address_label: String
    var address_detail: String
    var maps_url: String
    var delivery_at: Date
    var cutoff_at: Date?
    var pay_rule: String
    var msg_lang: String
    var payout_account_id: UUID?
}

nonisolated struct Member: Codable, Hashable {
    var group_id: UUID
    var user_id: UUID
    var joined_at: Date
    var removed_at: Date?
    var done_editing_at: Date?
    var proof_at: Date?
    var paid_at: Date?
    var bill_total: Int?
    /// The host's last payment reminder (the payment board shows "✓ Nudged" for the rest of that WITA day).
    var nudged_at: Date?
    /// The frozen items part of `bill_total`, and what the host has confirmed so far.
    var bill_items: Int?
    var paid_total: Int?
}

nonisolated struct OptionGroup: Codable, Hashable {
    var name: String
    var choices: [String]
}

nonisolated struct Variant: Codable, Hashable {
    var options: [String: String]
    var price: Int
    var available: Bool?
}

nonisolated struct Product: Codable, Identifiable, Hashable {
    var id: String
    var collection_id: String?
    var name: String
    var description: String
    var photo_url: String
    var base_price: Int
    var option_groups: [OptionGroup]
    var variants: [Variant]
    var available: Bool
    var sort: Int

    var fromPrice: Int { variants.map(\.price).min() ?? base_price }
    var photo: URL? { URL(string: photo_url) }
}

nonisolated struct Collection: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var sort: Int
}

nonisolated struct Item: Codable, Identifiable, Hashable {
    var id: UUID
    var group_id: UUID
    var owner_id: UUID
    var product_id: String
    var name: String
    var options: [String: String]
    var unit_price: Int
    var qty: Int
    var note: String
    var flag_reason: String?
    var flagged_at: Date?

    var total: Int { unit_price * qty }
}

nonisolated struct NewItem: Encodable {
    var group_id: UUID
    var product_id: String
    var options: [String: String]
    var qty: Int
    var note: String
}

nonisolated struct Split: Codable, Identifiable, Hashable {
    var id: UUID
    var item_id: UUID
    var proposer_id: UUID
    var state: String          // pending | accepted | declined | cancelled
}

nonisolated struct SplitShare: Codable, Hashable {
    var split_id: UUID
    var user_id: UUID
    var pct: Double
    var accepted_at: Date?
}

/// A row of `group_bill_v`: what one member owes.
nonisolated struct BillRow: Codable, Hashable {
    var group_id: UUID
    var user_id: UUID
    var items: Int
    var delivery_share: Int
    var bill_total: Int?
    var proof_at: Date?
    var paid_at: Date?
    /// This bill is final and frozen.
    var is_final: Bool?
    /// What the host has confirmed so far, and what is still to pay (nil before final; 0 for the host and the paid).
    var paid_total: Int?
    var owed: Int?

    var total: Int { bill_total ?? (items + delivery_share) }
}

nonisolated struct DeliveryProof: Codable, Identifiable, Hashable {
    var id: UUID
    var group_id: UUID
    var path: String
    var by_user: UUID
    var hidden: Bool
    var created_at: Date
}

nonisolated struct GroupPreview: Codable, Hashable {
    var id: UUID
    var name: String
    var host_name: String
    var area: String
    var delivery_at: Date
    var cutoff_at: Date?
    var state: GroupState
    var members: Int
    var already_member: Bool
}
