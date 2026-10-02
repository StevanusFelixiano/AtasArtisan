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
    var splits: [Split] = []
    var shares: [SplitShare] = []
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
    var isHost: Bool { group?.host_id == me }
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
    func liveSplit(_ item: Item) -> Split? { splits.first { $0.item_id == item.id && ["pending", "accepted"].contains($0.state) } }
    func shares(_ split: Split) -> [SplitShare] { shares.filter { $0.split_id == split.id } }

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
            let itemIDs = items.map(\.id)
            let splits: [Split] = itemIDs.isEmpty ? [] :
                try await supabase.from("splits").select().in("item_id", values: itemIDs).execute().value
            let shares: [SplitShare] = splits.isEmpty ? [] :
                try await supabase.from("split_shares").select().in("split_id", values: splits.map(\.id)).execute().value
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
            self.splits = splits
            self.shares = shares
            self.people = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
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
        let streams = [("groups", "id"), ("members", "group_id"), ("items", "group_id"), ("delivery_proofs", "group_id")].map {
            channel.postgresChange(AnyAction.self, table: $0.0, filter: .eq($0.1, value: id))
        } + [channel.postgresChange(AnyAction.self, table: "splits"), channel.postgresChange(AnyAction.self, table: "split_shares")]
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

    func add(product: Product, options: [String: String], qty: Int, note: String) async throws {
        try await supabase.from("items").insert(NewItem(group_id: id, product_id: product.id, options: options, qty: qty, note: note)).execute()
        products[product.id] = product
        epoch += 1
        await refresh()
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
