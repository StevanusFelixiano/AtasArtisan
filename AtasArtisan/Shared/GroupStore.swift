import Foundation
import Supabase

/// One group's live state for the group screen and its sheets. Realtime events mean "refetch"; a 30 s poll
/// stands behind the channel (iOS guide). Writes go through RLS-checked inserts or the security-definer RPCs.
@MainActor @Observable
final class GroupStore {
    let id: UUID
    var group: OrderGroup?
    var members: [Member] = []
    var people: [UUID: Profile] = [:]
    var items: [Item] = []
    /// Pieces claimed of shared items, and the ask-to-share requests I made or got.
    var claims: [ItemClaim] = []
    var shareRequests: [ShareRequest] = []
    /// Lines of food people have taken out of the fridge (Pickup, per item); fetched once the order is Delivered.
    var pickups: [ItemPickup] = []
    /// My notices about shared items that came off at lock (A-8); fetched once the order has left Open.
    var shareNotices: [GroupNotice] = []
    var bill: [BillRow] = []
    var proofs: [DeliveryProof] = []
    var payout: PayoutAccount?
    var products: [String: Product] = [:]
    var loadError: String?
    var loaded = false
    /// When the data on screen was last fetched ("Showing the order as of 11:31" while offline).
    var loadedAt: Date?
    /// RPCs of mine in flight, and the state change the last one made: watchers feel a change, its author doesn't.
    private var writing = 0
    private var ownMove: (from: GroupState, to: GroupState)?
    /// Bumped when one of my writes lands. A refresh that started before it may carry the old row, so it is
    /// dropped; the write's own refresh follows.
    private var epoch = 0
    /// Quantities shown but not saved yet (see `setQty`), the tap count that owns each item's save, and each
    /// item's last save so the next one waits for it.
    private var pendingQty: [UUID: Int] = [:]
    private var qtyTaps: [UUID: Int] = [:]
    private var qtySaves: [UUID: Task<Error?, Never>] = [:]

    init(id: UUID) { self.id = id }

    var me: UUID? { AppModel.shared.userID }
    var isHost: Bool {
        #if DEBUG
        if let role = DebugScreens.value("ATASTE_ROLE") { return role == "host" }
        #endif
        return group?.host_id == me
    }
    var activeMembers: [Member] { members.filter { $0.removed_at == nil }.sorted { $0.joined_at < $1.joined_at } }
    var subtotal: Int { items.reduce(0) { $0 + $1.total } }
    var myItems: [Item] { items.filter { $0.owner_id == me } }
    var myBill: BillRow? { bill.first { $0.user_id == me } }
    var hasFlagsForMe: Bool { myItems.contains { $0.flagged_at != nil } }

    func name(_ user: UUID) -> String {
        let n = people[user]?.name ?? ""
        return n.isEmpty ? "Someone" : n
    }
    func colorIndex(_ user: UUID) -> Int { activeMembers.firstIndex { $0.user_id == user } ?? 0 }
    func items(of user: UUID) -> [Item] { items.filter { $0.owner_id == user }.sorted { $0.name < $1.name } }

    // MARK: Ready (open orders)

    /// An item of their own or claimed pieces (the server's `has_stake`; split shares aren't loaded here).
    func hasStake(_ user: UUID) -> Bool {
        items.contains { $0.owner_id == user } || claims.contains { $0.user_id == user && $0.pieces > 0 }
    }
    func isReady(_ user: UUID) -> Bool { activeMembers.first { $0.user_id == user }?.ready_at != nil }
    var readyPeople: [Ready.Person] {
        activeMembers.map { Ready.Person(id: $0.user_id, stake: hasStake($0.user_id), ready: $0.ready_at != nil) }
    }
    var readyCount: (ready: Int, of: Int) { Ready.count(readyPeople, host: group?.host_id ?? UUID()) }

    // MARK: People limit

    /// Joined past the people limit: shared items only until a spot frees up and they add an item of their own.
    func isShareOnly(_ user: UUID) -> Bool { activeMembers.first { $0.user_id == user }?.share_only == true }
    /// People who can add items of their own, the host included.
    var fullCount: Int { activeMembers.filter { $0.share_only != true }.count }
    /// Spots still free under the limit; nil when there's no limit.
    var spotsFree: Int? { PeopleLimit.free(limit: group?.people_limit, full: fullCount) }
    /// I can add items of my own: I'm a full member, or a spot is free for me to take.
    var canAddOwn: Bool {
        guard let me, isShareOnly(me) else { return true }
        return (spotsFree ?? 1) > 0
    }

    // MARK: Shared items (A2)

    /// Items shared in pieces, oldest first.
    var sharedItems: [Item] { items.filter { $0.share_pieces != nil } }
    /// Claims on `item`, first claimed first.
    func claims(_ item: Item) -> [ItemClaim] {
        claims.filter { $0.item_id == item.id && $0.pieces > 0 }.sorted { $0.created_at < $1.created_at }
    }
    func claimed(_ item: Item) -> Int { claims(item).reduce(0) { $0 + $1.pieces } }
    /// Pieces the owner keeps for themselves (`share_keep`, at least 1); nobody else can claim them.
    func kept(_ item: Item) -> Int { item.share_pieces == nil ? 0 : max(1, item.share_keep ?? 1) }
    /// Pieces others can claim in all: every piece but the owner's kept ones.
    func claimable(_ item: Item) -> Int { max(0, (item.share_pieces ?? 0) - kept(item)) }
    /// Pieces others can still claim.
    func piecesLeft(_ item: Item) -> Int { Pieces.left(pieces: item.share_pieces ?? 0, keep: kept(item), claimed: claimed(item)) }
    /// The owner's pieces: the kept ones and every one nobody claimed.
    func ownerPieces(_ item: Item) -> Int { max(0, (item.share_pieces ?? 0) - claimed(item)) }
    /// The owner and everyone with a claim.
    func sharePeople(_ item: Item) -> Int { 1 + claims(item).count }
    func minMet(_ item: Item) -> Bool { Pieces.minMet(min: item.share_min, people: sharePeople(item), left: piecesLeft(item)) }
    func myClaim(_ item: Item) -> Int { claims(item).first { $0.user_id == me }?.pieces ?? 0 }
    /// Requests waiting on my answer, as the item's owner.
    var asksForMe: [ShareRequest] {
        shareRequests.filter { r in r.owner_id == me && r.state == "pending" && items.contains { $0.id == r.item_id && $0.share_pieces == nil } }
    }
    func myAsk(_ item: Item) -> ShareRequest? {
        shareRequests.first { $0.item_id == item.id && $0.requester_id == me && $0.state == "pending" }
    }

    /// "1000gr · Sliced 15mm" in the product's option order.
    func optionText(_ item: Item) -> String {
        let order = products[item.product_id]?.option_groups.map(\.name) ?? item.options.keys.sorted()
        return order.compactMap { item.options[$0] }.joined(separator: " · ")
    }

    func refresh() async {
        let started = epoch
        do {
            let g: OrderGroup = try await supabase.from("groups").select().eq("id", value: id).single().execute().value
            async let m: [Member] = supabase.from("members").select().eq("group_id", value: id).execute().value
            async let i: [Item] = supabase.from("items").select().eq("group_id", value: id).order("created_at").execute().value
            async let b: [BillRow] = supabase.from("group_bill_v").select().eq("group_id", value: id).execute().value
            async let d: [DeliveryProof] = supabase.from("delivery_proofs").select().eq("group_id", value: id).execute().value
            let (members, items, bill, proofs) = try await (m, i, b, d)
            async let c: [ItemClaim] = supabase.from("item_claims").select().eq("group_id", value: id).execute().value
            async let r: [ShareRequest] = supabase.from("share_requests").select().eq("group_id", value: id).execute().value
            let (claims, requests) = try await (c, r)
            // Optional: a server without per-item pickup has no table, and Pickup falls back to members.taken_at.
            let pickups: [ItemPickup] = [.delivered, .closed].contains(g.state)
                ? ((try? await supabase.from("item_pickups").select().eq("group_id", value: id).execute().value) ?? []) : []
            let notices: [GroupNotice] = g.state == .open ? [] :
                try await supabase.from("notifications").select("id,kind,title,body,created_at").eq("group_id", value: id)
                    .eq("kind", value: "share_min_not_met").order("created_at").execute().value
            let profiles: [Profile] = try await supabase.from("profiles").select()
                .in("id", values: members.map(\.user_id)).execute().value
            let productIDs = Array(Set(items.map(\.product_id)))
            let prods: [Product] = productIDs.isEmpty ? [] :
                try await supabase.from("products").select().in("id", values: productIDs).execute().value
            var payout: PayoutAccount?
            if let pid = g.payout_account_id {
                payout = try? await supabase.from("payout_accounts").select().eq("id", value: pid).single().execute().value
            }
            guard started == epoch else { return }
            self.group = g
            self.members = members
            self.items = items.map { var i = $0; i.qty = pendingQty[i.id] ?? i.qty; return i }
            self.bill = bill
            self.proofs = proofs
            self.claims = claims
            self.shareRequests = requests
            self.pickups = pickups
            self.shareNotices = notices
            self.people = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            #if DEBUG
            for (id, p) in people where DebugScreens.unverified(p.name) { people[id]?.phone = nil }
            #endif
            self.products.merge(prods.map { ($0.id, $0) }) { _, new in new }
            self.payout = payout
            self.loadError = nil
            self.loadedAt = Date()

        } catch where isCancellation(error) {
            return
        } catch {
            loadError = readable(error)
        }
        loaded = true
    }

    func watch() async {
        // A fresh topic per watcher: two watchers sharing one silently unsubscribe each other.
        let channel = supabase.channel("group:\(id):\(UUID().uuidString)")
        let streams = [("groups", "id"), ("members", "group_id"), ("items", "group_id"), ("delivery_proofs", "group_id"),
                       ("item_claims", "group_id"), ("share_requests", "group_id"),
                       ("item_pickups", "group_id")].map {
            channel.postgresChange(AnyAction.self, table: $0.0, filter: .eq($0.1, value: id))
        }
        defer { Task { await supabase.removeChannel(channel) } }
        try? await channel.subscribeWithError()
        await withTaskGroup(of: Void.self) { tasks in
            for stream in streams {
                tasks.addTask { for await _ in stream { await self.refresh() } }
            }
            tasks.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    await self.refresh()
                }
            }
        }
    }

    // MARK: Writes

    func rpc(_ fn: String, _ params: [String: AnyJSON]) async throws {
        let before = group?.state
        writing += 1
        defer { writing -= 1 }
        try await supabase.rpc(fn, params: params).execute()
        epoch += 1
        await refresh()
        if let before, let after = group?.state, after != before { ownMove = (before, after) }
        AppModel.shared.homeVersion += 1
    }

    /// The order moving `from` → `to` is my own doing (or may be: one of my RPCs is still in flight).
    func isOwnMove(from: GroupState, to: GroupState) -> Bool {
        writing > 0 || (ownMove?.from == from && ownMove?.to == to)
    }

    /// Adds an item; `share` opens it to the group in that many pieces, `keep` of them mine, with an optional minimum
    /// of people.
    func add(product: Product, options: [String: String], qty: Int, note: String, share: (pieces: Int, keep: Int, min: Int?)? = nil) async throws {
        nonisolated struct Added: Decodable { var id: UUID }
        let added: Added = try await supabase.from("items")
            .insert(NewItem(group_id: id, product_id: product.id, options: options, qty: qty, note: note))
            .select("id").single().execute().value
        products[product.id] = product
        epoch += 1
        if let share {
            try await rpc("share_item", ["item": .string(added.id.uuidString), "pieces": .integer(share.pieces),
                                         "min_people": share.min.map { .integer($0) } ?? .null, "keep": .integer(share.keep)])
        } else {
            await refresh()
        }
    }

    /// Shares my item, or changes its pieces, the ones I keep and the minimum (`share_item`).
    func share(_ item: Item, pieces: Int, keep: Int, min: Int?) async throws {
        try await rpc("share_item", ["item": .string(item.id.uuidString), "pieces": .integer(pieces), "keep": .integer(keep),
                                     "min_people": min.map { .integer($0) } ?? .null])
    }

    /// Sets my claim on someone's shared item; 0 withdraws it.
    func claim(_ item: Item, pieces: Int) async throws {
        try await rpc("claim_pieces", ["item": .string(item.id.uuidString), "pieces": .integer(pieces)])
    }

    func update(_ item: Item, qty: Int? = nil, note: String? = nil, options: [String: String]? = nil, product: String? = nil) async throws {
        struct Patch: Encodable { var qty: Int?; var note: String?; var options: [String: String]?; var product_id: String? }
        try await supabase.from("items").update(Patch(qty: qty, note: note, options: options, product_id: product)).eq("id", value: item.id).execute()
        epoch += 1
        await refresh()
    }

    /// The stepper: the new quantity shows at once and is saved 0.6 s after the last tap, so a run of taps is one
    /// write of the final number. Saves of one item run one after another and each sends the latest number, so an
    /// older value never lands last. Until saved, refreshes keep showing my number. Throws only for the save this
    /// tap ended up making; a failed save puts the server's number back.
    func setQty(_ item: Item, _ qty: Int) async throws {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].qty = qty
        pendingQty[item.id] = qty
        let tap = qtyTaps[item.id, default: 0] + 1
        qtyTaps[item.id] = tap
        try? await Task.sleep(for: .milliseconds(600))
        guard qtyTaps[item.id] == tap else { return }  // a later tap owns the save
        let prior = qtySaves[item.id]
        let save = Task { _ = await prior?.value; return await self.saveQty(item.id) }
        qtySaves[item.id] = save
        if let error = await save.value { throw error }
    }

    private func saveQty(_ id: UUID) async -> Error? {
        guard let qty = pendingQty[id] else { return nil }
        var failure: Error?
        do {
            try await supabase.from("items").update(["qty": qty]).eq("id", value: id).execute()
        } catch {
            failure = error
        }
        if pendingQty[id] == qty { pendingQty[id] = nil }  // a newer number stays pending for its own save
        epoch += 1
        await refresh()
        return failure
    }

    /// The row goes at once (it collapses as the remove confirm leaves); a failed delete's refresh brings it back.
    func remove(_ item: Item) async throws {
        pendingQty[item.id] = nil
        qtyTaps[item.id, default: 0] += 1  // drops a quantity save still waiting
        items.removeAll { $0.id == item.id }
        do {
            try await supabase.from("items").delete().eq("id", value: item.id).execute()
        } catch {
            await refresh()
            throw error
        }
        epoch += 1
        await refresh()
    }
}
