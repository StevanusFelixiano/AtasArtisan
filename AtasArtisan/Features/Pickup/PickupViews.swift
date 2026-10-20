import SwiftUI
import Supabase

// Pickup (Claude Design "Ataste Screens 7 Pickup"): once the order is Delivered, each person with food in it says when
// they've taken it out of the office fridge. A self-report, never confirmed by the host; it doesn't change the bill and
// never blocks Close order. 7-1/7-2 the member's food card and I've taken mine, 7-3 the Pickup card, 7-4 the board.

// MARK: - Data

/// One line of someone's food in the fridge: a whole item ("2× Pain Au Chocolate") or their pieces of a shared one
/// ("3 slices Burnt Cheesecake").
struct FoodLine: Identifiable {
    var item: Item
    var text: String
    /// Set for pieces of a shared item that others hold pieces of too.
    var shared: Bool
    var id: UUID { item.id }
}

extension GroupStore {
    /// Pickup runs once a group order is Delivered, and stays open after it's Closed (food can still be in the fridge).
    var pickupOpen: Bool { [.delivered, .closed].contains(group?.state) && group?.personal == false }

    func member(_ user: UUID) -> Member? { members.first { $0.user_id == user } }
    func takenAt(_ user: UUID) -> Date? { member(user)?.taken_at }

    /// They own an item or hold claimed pieces (the server's `has_food`).
    func hasFood(_ user: UUID) -> Bool {
        items.contains { $0.owner_id == user && $0.qty > 0 } || claims.contains { $0.user_id == user && $0.pieces > 0 }
    }

    /// Everyone counted, host included: taken first, in the order they took it, then who is left in join order.
    var pickupPeople: [Member] {
        let counted = activeMembers.filter { hasFood($0.user_id) }
        let taken = counted.filter { $0.taken_at != nil }.sorted { $0.taken_at! < $1.taken_at! }
        return taken + counted.filter { $0.taken_at == nil }
    }

    /// Someone's food: whole items, then pieces of shared ones (an owner's as the pieces nobody claimed), each by name.
    func food(of user: UUID) -> [FoodLine] {
        var out: [FoodLine] = []
        for item in items.sorted(by: { $0.name < $1.name }) {
            if item.owner_id == user, item.qty > 0 {
                if item.share_pieces != nil, claimed(item) > 0 {
                    out.append(FoodLine(item: item, text: "\(Pickup.count(ownerPieces(item), of: item.name)) \(item.name)", shared: true))
                } else {
                    out.append(FoodLine(item: item, text: Pickup.whole(item.name, qty: item.qty), shared: false))
                }
            } else if let c = claims(item).first(where: { $0.user_id == user }) {
                out.append(FoodLine(item: item, text: "\(Pickup.count(c.pieces, of: item.name)) \(item.name)", shared: true))
            }
        }
        return out.filter { !$0.shared } + out.filter(\.shared)
    }

    /// Who holds pieces of a shared item, in the order board 10 lists them: the owner (what nobody claimed), then me,
    /// then the others in claim order. Nobody without pieces.
    func holders(_ item: Item) -> [(user: UUID, pieces: Int)] {
        let claims = claims(item)
        return Pickup.order(owner: item.owner_id, me: me, claimers: claims.map(\.user_id)).compactMap { u in
            let n = u == item.owner_id ? ownerPieces(item) : claims.first { $0.user_id == u }?.pieces ?? 0
            return n > 0 ? (user: u, pieces: n) : nil
        }
    }

    /// I hold pieces of this shared item, so I may mark anyone's pieces of it taken and WhatsApp the others (board 10).
    func inSplit(_ item: Item) -> Bool { holders(item).contains { $0.user == me } }

    /// Who marked `user`'s pieces of `item` taken when it wasn't them (`item_pickups.marked_by`).
    func takenBy(_ item: Item, _ user: UUID) -> UUID? {
        pickups.first { $0.item_id == item.id && $0.user_id == user }?.marked_by.flatMap { $0 == user ? nil : $0 }
    }

    /// "Taken 12:40", "Taken by you · 12:40", "Taken by Kevin · 12:15"; nil while in the fridge. `short` is the sheet's
    /// line beside the TAKEN tag ("by you · 12:40").
    func takenLine(_ item: Item, _ user: UUID, short: Bool = false) -> String? {
        guard let at = lineTaken(item, by: user) else { return nil }
        let by = takenBy(item, user).map { $0 == me ? "you" : name($0) }
        let time = Wita.string(at, "HH:mm")
        return short ? Pickup.takenBy(by, at: time) : Pickup.takenLine(by, at: time)
    }

    /// When the last of a shared item's pieces left the fridge.
    func lastTaken(_ item: Item) -> Date? { holders(item).compactMap { lineTaken(item, by: $0.user) }.max() }

    /// The piece bar after lock: each holder's pieces in their colour while in the fridge, Liquorice 100 once taken.
    func splitFills(_ item: Item) -> [Color?] {
        holders(item).flatMap { h in
            Array(repeating: lineTaken(item, by: h.user) == nil ? pieceColor(h.user) : Brand.liquorice100, count: h.pieces)
        }
    }

    /// When `user` took their line of `item`: its own pickup row, or every line once they said I've taken mine (a
    /// server without per-item pickup only has that).
    func lineTaken(_ item: Item, by user: UUID) -> Date? {
        pickups.first { $0.item_id == item.id && $0.user_id == user }?.taken_at ?? takenAt(user)
    }

    /// "1 of 3 taken" while someone has taken some of their food but not all; nil otherwise.
    func partlyTaken(_ user: UUID) -> String? {
        let lines = food(of: user)
        let n = lines.filter { lineTaken($0.item, by: user) != nil }.count
        return n > 0 && n < lines.count ? "\(n) of \(lines.count) taken" : nil
    }

    /// Pieces of a shared item still in the fridge.
    func fridgeLeft(_ item: Item) -> Int {
        Pickup.left(holders(item).map { (pieces: $0.pieces, taken: lineTaken(item, by: $0.user) != nil) })
    }

    /// Shared items that others hold pieces of (board 7-4's fridge card).
    var fridgeShared: [Item] { sharedItems.filter { !claims($0).isEmpty } }

    /// The Pickup card's line; the viewer is "you" and leads the taken names.
    var pickupLine: String {
        let people = pickupPeople
        let taken = people.filter { $0.taken_at != nil }.map(\.user_id)
        let names = (taken.contains { $0 == me } ? ["you"] : []) + taken.filter { $0 != me }.map(name)
        return Pickup.line(taken: isHost ? taken.map(name) : names,
                           left: people.filter { $0.taken_at == nil }.map { name($0.user_id) }, host: isHost)
    }

    /// I've taken mine (true) or Undo (false).
    func markTaken(_ taken: Bool) async throws {
        try await rpc("mark_taken", ["g": .string(id.uuidString), "taken": .bool(taken)])
    }

    /// One line of my food taken (true) or back in the fridge (false).
    func markTaken(_ item: Item, _ taken: Bool) async throws {
        try await rpc("mark_item_taken", ["item": .string(item.id.uuidString), "taken": .bool(taken)])
    }

    /// Someone's pieces of a shared item I'm in taken (true) or back in the fridge (false); `holder` nil is every
    /// holder at once ("I took the whole …"). The holder hears of it only once the 4 s Undo is over (server cron).
    func markSplit(_ item: Item, holder: UUID?, taken: Bool) async throws {
        try await rpc("mark_split_taken", ["item": .string(item.id.uuidString),
                                           "holder": holder.map { .string($0.uuidString) } ?? .null, "taken": .bool(taken)])
    }
}

// MARK: - Group screen

extension GroupView {
    /// I can say I've taken mine: pickup is open and I have food in it, not yet taken.
    var canTake: Bool {
        guard store.pickupOpen, let me = store.me else { return false }
        return store.hasFood(me) && store.takenAt(me) == nil
    }

    /// Marks my food taken or not. Taking it shows "Marked as taken · Undo"; undoing is silent.
    func markTaken(_ taken: Bool) async {
        await act(taken ? "Couldn't mark it taken" : "Couldn't undo") { try await store.markTaken(taken) }
        guard taken, let me = store.me, store.takenAt(me) != nil else { return }
        toast = ToastNote(text: "Marked as taken", action: ToastNote.Action(title: "Undo") {
            Task { await markTaken(false) }
        }, hold: 4)
    }

    /// One line of my food taken or put back. Taking the last one shows "Marked as taken · Undo" like the whole.
    func markTaken(_ item: Item, _ taken: Bool) async {
        await act(taken ? "Couldn't mark it taken" : "Couldn't undo") { try await store.markTaken(item, taken) }
        guard taken, let me = store.me, store.takenAt(me) != nil else { return }
        toast = ToastNote(text: "Marked as taken", action: ToastNote.Action(title: "Undo") {
            Task { await markTaken(item, false) }
        }, hold: 4)
    }

    /// 7-1 / 7-2: my food card, the shared items in the fridge (10-3), then the Pickup card. Members only; the host
    /// marks theirs on the board.
    @ViewBuilder func memberPickupSections(_ g: OrderGroup) -> some View {
        if store.pickupOpen, let me = store.me {
            if store.hasFood(me) {
                PickupFoodCard(store: store, undo: { Task { await markTaken(false) } },
                               mark: { item, taken in Task { await markTaken(item, taken) } })
            }
            splitSection(g)
            pickupCard
        }
    }

    /// "Pickup · 4 of 6 taken · Kevin, Nadia left" (7-1, 7-3), opens the board.
    @ViewBuilder var pickupCard: some View {
        if store.pickupOpen && !store.pickupPeople.isEmpty {
            Button { sheet = .pickup } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pickup").brand(.label)
                        Text(store.pickupLine).ui(GFont.manrope(14, 600))
                    }
                    Spacer()
                    icon("chevron.right", 18, Brand.ink4)
                }
                .surface(24, padding: edges(16, 16))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens who has taken their food")
        }
    }

    /// 7-1: a member's bar while their food is in the fridge. With a bill still to pay, Pay keeps the primary place.
    @ViewBuilder func memberDeliveredBar(_ g: OrderGroup) -> some View {
        if canTake, let b = unpaid {
            GroupBar {
                FlexRow(weights: [1, 1]) {
                    Button { Task { await markTaken(true) } } label: { Label("I’ve taken mine", systemImage: "bag") }
                        .buttonStyle(BarPillStyle(kind: .secondary))
                    Button { sheet = .bill } label: { Label("Pay \(hostFirst) · \(Rupiah.format(b.due))", systemImage: "receipt") }
                        .buttonStyle(BarPillStyle(kind: .primary))
                }
            }
        } else if canTake {
            GroupBar {
                VStack(spacing: 8) {
                    Button { Task { await markTaken(true) } } label: { Label("I’ve taken mine", systemImage: "bag") }
                        .buttonStyle(.pill(.primary))
                    Text("Lets the group know your food is out of the fridge.").ui(GFont.manrope(12), Brand.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 2)
                }
            }
        } else {
            memberPayBar(g)
        }
    }
}

// MARK: - 7-1 / 7-2 Yours in the fridge

/// My food: each line, a shared item's slices still in the fridge, and once taken the TAKEN tag, the time and Undo.
/// With more than one line, each one is marked on its own ("Taken" / its time and Undo).
struct PickupFoodCard: View {
    var store: GroupStore
    var undo: () -> Void
    var mark: (Item, Bool) -> Void = { _, _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let me = store.me ?? UUID()
        let at = store.takenAt(me)
        let lines = store.food(of: me)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(at == nil ? "Yours in the fridge" : "Your food").brand(.label)
                Spacer()
                if at != nil { TakenTag().transition(.scale.combined(with: .opacity)) }
            }
            .frame(minHeight: 24)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                HStack(spacing: 12) {
                    ProductPhoto(url: store.products[l.item.product_id]?.photo, size: 44, fill: [Brand.choc100, Brand.pink100, Brand.lime][i % 3])
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.text).ui(GFont.manrope(15, 600))
                        if l.shared, store.takenBy(l.item, me) != nil, let line = store.takenLine(l.item, me) {
                            // Someone in the split took mine out with theirs (board 10): "Taken by Putri · 12:40".
                            Text(line).ui(GFont.manrope(12, 600))
                        } else if l.shared, let pieces = l.item.share_pieces {
                            Text("\(store.fridgeLeft(l.item)) of \(pieces) \(Pickup.word(l.item.name, pieces)) left in the fridge")
                                .ui(GFont.manrope(12), Brand.ink3)
                                .contentTransition(.numericText())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if lines.count > 1 && at == nil {
                        Spacer(minLength: 8)
                        PickupLineToggle(name: l.item.name, taken: store.lineTaken(l.item, by: me)) { mark(l.item, $0) }
                    }
                }
            }
            if let at {
                DashedRule(color: Brand.liquorice400)
                HStack {
                    Text("You took yours at \(Wita.string(at, "HH:mm"))").ui(GFont.manrope(13), Brand.ink2)
                    Spacer()
                    Button("Undo", action: undo)
                        .font(GFont.manrope(13, 700)).foregroundStyle(Brand.caramel)
                        .buttonStyle(DoughStyle(squash: Motion.pressCompact))
                        .accessibilityLabel("Undo taken")
                }
            }
        }
        .surface(24, padding: edges(18, 18))
        .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick, value: at)
    }
}

// MARK: - 7-4 Pickup board

/// Who has taken their food and who hasn't, with the host's Nudge, and each shared item's pieces still in the fridge.
/// Members see the same board without Nudge. Everyone marks their own food from their own row (the host's only way);
/// someone in a split also marks the others' pieces of it in the fridge card (10-4).
struct PickupBoardView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?
    @State private var toast: ToastNote?
    @State private var putBack: PutBack?

    private var hostFirst: String {
        let n = store.name(store.group?.host_id ?? UUID())
        return String(n.split(separator: " ").first ?? Substring(n))
    }

    var body: some View {
        let people = store.pickupPeople
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if people.isEmpty {
                    EmptyStateView(pose: "pose-waiting", title: "Nothing in the fridge", message: "Nobody has food in this order.")
                } else {
                    summary(people)
                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.element.user_id) { i, m in
                            PickupPersonRow(store: store, member: m, problem: $problem)
                            if i < people.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                        }
                    }
                    .padding(.vertical, 4).padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
                    if !store.fridgeShared.isEmpty { fridgeCard }
                    Text("Each person, or anyone in their split, marks food as taken. It doesn’t change anyone’s bill"
                         + (store.group?.state == .closed ? "."
                            : ", and " + (store.isHost ? "you" : hostFirst) + " can close the order at any time."))
                        .font(Type5.manrope(12)).lineSpacing(1).foregroundStyle(Brand.ink3).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.top, 10)
            .padding(.bottom, Brand.s5)
        }
        .screen()
        .navigationTitle("Pickup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
        .problemAlert($problem)
        .putBackAlert($putBack, store: store) { p in Task { await marker.put(p.item, p.holder) } }
        .toast($toast)
    }

    private var marker: SplitMarker { SplitMarker(store: store, problem: $problem, toast: $toast, ask: $putBack) }

    /// TAKEN · 4 of 6, the bar, and the two name lists.
    private func summary(_ people: [Member]) -> some View {
        let taken = people.filter { $0.taken_at != nil }
        let left = people.filter { $0.taken_at == nil }
        let names = { (list: [Member]) in list.map { store.name($0.user_id) }.joined(separator: ", ") }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Taken").font(Type5.manrope(12, 600)).tracking(12 * 0.03).textCase(.uppercase).foregroundStyle(Brand.cocoa)
                Spacer()
                Text("\(taken.count) of \(people.count)").font(Type5.roundo(18)).foregroundStyle(Brand.cocoa)
                    .contentTransition(.numericText(value: Double(taken.count)))
            }
            GeometryReader { g in
                Rectangle().fill(Brand.limeDeep)
                    .frame(width: g.size.width * CGFloat(taken.count) / CGFloat(max(1, people.count)))
                    .animation(Motion.doughTrail, value: taken.count)
            }
            .frame(height: 16)
            .background(Brand.liquorice100)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 8) {
                column("Taken", Brand.limeDeep, taken.isEmpty ? "Nobody yet" : names(taken))
                column("Still in the fridge", Brand.liquorice400, left.isEmpty ? "Nobody" : names(left))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
    }

    private func column(_ title: String, _ dot: Color, _ names: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(title).font(Type5.manrope(11, 600)).foregroundStyle(Brand.ink2)
            }
            Text(names).font(Type5.roundo(17)).foregroundStyle(Brand.cocoa).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Shared items in the fridge (10-4): pieces left, the bar in each holder's colour (Liquorice 100 once taken), and
    /// each holder's pieces with who took them. Someone in the split marks any holder's pieces or puts them back;
    /// anyone else reads it.
    private var fridgeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shared items in the fridge").brand(.label)
            ForEach(Array(store.fridgeShared.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1).padding(.vertical, 2) }
                FridgeSharedItem(store: store, item: item, marker: marker)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
    }
}

/// One shared item on the board's fridge card: "4 of 16 pieces left", the bar, a row per holder ("Kevin · keeps 8 ·
/// Taken 12:15", "Dimas · 4 pieces · Taken by Kevin · 12:15"), and for someone in the split Mark taken, Put back and the
/// whole-item button. Not in it: "You’re not in the … split".
private struct FridgeSharedItem: View {
    var store: GroupStore
    var item: Item
    var marker: SplitMarker
    @State private var busy = false

    var body: some View {
        let pieces = item.share_pieces ?? 0
        let left = store.fridgeLeft(item)
        let inSplit = store.inSplit(item)
        let canMark = store.pickupOpen && inSplit
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ProductPhoto(url: store.products[item.product_id]?.photo, size: 56, fill: Brand.pink100)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(Type5.manrope(15, 600)).foregroundStyle(Brand.cocoa)
                    Text(left == 0 ? Pickup.inFridge(left: 0, of: pieces, name: item.name, at: nil)
                                   : "\(left) of \(pieces) \(Pickup.word(item.name, pieces)) left")
                        .font(Type5.roundo(17)).foregroundStyle(Brand.cocoa)
                        .contentTransition(.numericText(value: Double(left)))
                }
            }
            PieceBar(fills: store.splitFills(item), height: 14)
            VStack(spacing: 0) {
                ForEach(store.holders(item), id: \.user) { h in row(h.user, h.pieces, canMark: canMark) }
            }
            if canMark, let label = Pickup.bulk(item.name, left: left, of: pieces) {
                Button { run { await marker.mark(item, nil) } } label: { Label(label, systemImage: "bag") }
                    .buttonStyle(SharePillStyle(fill: Brand.cream, border: Brand.choc100))
                    .disabled(busy)
            }
            if !inSplit {
                Text("You’re not in the \(item.name) split, so you can see it but not change it.")
                    .font(Type5.manrope(12)).lineSpacing(1).foregroundStyle(Brand.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ user: UUID, _ n: Int, canMark: Bool) -> some View {
        let you = user == store.me
        let who = you ? "You" : store.name(user)
        let line = store.takenLine(item, user)
        return HStack(spacing: 8) {
            Text("\(who) · \(Pickup.holding(n, of: item.name, owner: user == item.owner_id, you: you))")
                .font(Type5.manrope(13)).foregroundStyle(Brand.ink2)
            Spacer(minLength: 8)
            Group {
                if let line {
                    Text(line).font(Type5.manrope(13, 600)).foregroundStyle(Brand.cocoa)
                } else {
                    Text("In the fridge").font(Type5.manrope(13, 600)).foregroundStyle(Brand.caramel)
                }
            }
            .lineLimit(1)
            if canMark {
                let whose = SplitMarker.whose(store, item, user, n)
                if line != nil {
                    PutBackLink(whose: whose) { marker.putBack(item, user, pieces: n) }.disabled(busy)
                } else if !you {
                    MarkTakenChip(whose: whose) { run { await marker.mark(item, user) } }.disabled(busy)
                }
            }
        }
        .frame(minHeight: canMark ? 44 : 36)
        .overlay(alignment: .top) { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task { await work(); busy = false }
    }
}

/// One person on the board: avatar, name, when they took it, what they have, TAKEN, and the actions. The host nudges
/// someone still to take theirs once ("✓ Nudged 10:40" after). My own row marks mine taken, or undoes it.
private struct PickupPersonRow: View {
    var store: GroupStore
    var member: Member
    @Binding var problem: Problem?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudging = false
    @State private var busy = false
    @State private var nudgeBumps = 0

    private var user: UUID { member.user_id }
    private var mine: Bool { user == store.me }
    private var name: String { store.name(user) }

    var body: some View {
        let at = member.taken_at
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: name, index: store.colorIndex(user), size: 40, art: store.people[user]?.avatar, bg: store.people[user]?.avatar_bg)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mine ? "\(name) · you" : name).font(Type5.manrope(16, 700)).foregroundStyle(Brand.cocoa)
                    Spacer()
                    if let at { Text("Taken \(Wita.string(at, "HH:mm"))").font(Type5.manrope(12)).foregroundStyle(Brand.ink3) }
                }
                let lines = store.food(of: user)
                if mine && store.pickupOpen && lines.count > 1 && at == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines) { l in
                            HStack(spacing: 8) {
                                Text(l.text).font(Type5.manrope(13)).foregroundStyle(Brand.ink2).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                PickupLineToggle(name: l.item.name, taken: store.lineTaken(l.item, by: user)) { markLine(l.item, $0) }
                                    .disabled(busy)
                            }
                        }
                    }
                } else {
                    Text(lines.map(\.text).joined(separator: " · "))
                        .font(Type5.manrope(13)).foregroundStyle(Brand.ink2).fixedSize(horizontal: false, vertical: true)
                }
                if at == nil, let part = store.partlyTaken(user) {
                    Label { Text(part).foregroundStyle(Brand.cocoa) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.limeDeep) }
                        .labelStyle(IconLabel(spacing: 5, size: 12))
                        .font(Type5.manrope(12, 600))
                }
                HStack(spacing: 8) {
                    if at != nil { TakenTag(size: .small) }
                    if store.pickupOpen { actions(taken: at != nil) }
                    Spacer(minLength: 0)
                    if !mine, let phone = store.people[user]?.phone {
                        Button { openURL(Links.whatsApp(phone)) } label: {
                            WhatsAppGlyph(size: 14).foregroundStyle(Brand.cocoa)
                                .frame(width: 28, height: 28).background(Circle().fill(Brand.lime))
                                .contentShape(Rectangle().inset(by: -8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("WhatsApp \(name)")
                    }
                }
                .frame(minHeight: 28)
                .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick, value: at)
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder private func actions(taken: Bool) -> some View {
        if mine {
            if taken {
                Button("Undo") { mark(false) }
                    .font(Type5.manrope(13, 700)).foregroundStyle(Brand.caramel)
                    .buttonStyle(DoughStyle(squash: Motion.pressCompact))
                    .disabled(busy)
                    .accessibilityLabel("Undo taken")
            } else {
                Button("I’ve taken mine", systemImage: "bag") { mark(true) }
                    .buttonStyle(ChipStyle(fill: Brand.lime, ring: Brand.limeDeep))
                    .disabled(busy)
            }
        } else if store.isHost && !taken && store.group?.state == .delivered {  // pickup_nudge stops at Close
            if let at = member.pickup_nudged_at {
                Label("Nudged \(Wita.string(at, "HH:mm"))", systemImage: "checkmark")
                    .labelStyle(IconLabel(spacing: 5, size: 12))
                    .font(Type5.manrope(12, 600)).foregroundStyle(Brand.ink2)
            } else {
                Button("Nudge", systemImage: "bell") { nudge() }
                    .buttonStyle(ChipStyle(fill: Brand.choc100))
                    .disabled(nudging)
                    .kick(reduceMotion ? 0 : nudgeBumps, from: BoardMotion.nudgeBump)
                    .accessibilityLabel("Nudge \(name)")
            }
        }
    }

    private func mark(_ taken: Bool) {
        busy = true
        Task {
            await attempt($problem, taken ? "Couldn't mark it taken" : "Couldn't undo") { try await store.markTaken(taken) }
            busy = false
        }
    }

    private func markLine(_ item: Item, _ taken: Bool) {
        busy = true
        Task {
            await attempt($problem, taken ? "Couldn't mark it taken" : "Couldn't undo") { try await store.markTaken(item, taken) }
            busy = false
        }
    }

    private func nudge() {
        nudging = true
        nudgeBumps += 1
        Task {
            await attempt($problem, "Couldn't nudge") {
                try await store.rpc("pickup_nudge", ["g": .string(store.id.uuidString), "u": .string(user.uuidString)])
            }
            nudging = false
        }
    }
}

/// One line of food on its own: "Taken" while it's in the fridge, its time and Undo once taken.
private struct PickupLineToggle: View {
    var name: String
    var taken: Date?
    var set: (Bool) -> Void

    var body: some View {
        if let taken {
            HStack(spacing: 8) {
                Label(Wita.string(taken, "HH:mm"), systemImage: "checkmark")
                    .labelStyle(IconLabel(spacing: 4, size: 11))
                    .font(Type5.manrope(12, 600)).foregroundStyle(Brand.ink2)
                Button("Undo") { set(false) }
                    .font(Type5.manrope(13, 700)).foregroundStyle(Brand.caramel)
                    .buttonStyle(DoughStyle(squash: Motion.pressCompact))
                    .accessibilityLabel("Undo taken \(name)")
            }
        } else {
            Button("Taken", systemImage: "bag") { set(true) }
                .buttonStyle(ChipStyle(fill: Brand.lime, ring: Brand.limeDeep))
                .accessibilityLabel("I’ve taken \(name)")
        }
    }
}
