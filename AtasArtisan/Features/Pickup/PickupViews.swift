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
    /// Pickup runs while a group order is Delivered.
    var pickupOpen: Bool { group?.state == .delivered && group?.personal == false }

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

    /// Who holds pieces of a shared item: the owner (what nobody claimed), then each claim.
    func holders(_ item: Item) -> [(user: UUID, pieces: Int)] {
        [(item.owner_id, ownerPieces(item))] + claims(item).map { ($0.user_id, $0.pieces) }
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
}

// MARK: - Group screen

extension GroupView {
    /// I can say I've taken mine: the order is Delivered and I have food in it, not yet taken.
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

    /// 7-1 / 7-2: my food card, then the Pickup card. Members only; the host marks theirs on the board.
    @ViewBuilder func memberPickupSections() -> some View {
        if store.pickupOpen, let me = store.me {
            if store.hasFood(me) {
                PickupFoodCard(store: store, undo: { Task { await markTaken(false) } },
                               mark: { item, taken in Task { await markTaken(item, taken) } })
            }
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
                        if l.shared, let pieces = l.item.share_pieces {
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
/// Members see the same board without Nudge. Everyone marks their own food from their own row (the host's only way).
struct PickupBoardView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?

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
                    Text(store.isHost ? "Each person marks their own food. This doesn’t change anyone’s bill, and you can close the order at any time."
                                      : "Each person marks their own food. This doesn’t change anyone’s bill.")
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
    }

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

    /// Shared items in the fridge: pieces left, one cell per piece (taken ones grey), and each holder.
    private var fridgeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shared items in the fridge").brand(.label)
            ForEach(store.fridgeShared) { item in
                let pieces = item.share_pieces ?? 0
                let left = store.fridgeLeft(item)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        ProductPhoto(url: store.products[item.product_id]?.photo, size: 56, fill: Brand.pink100)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(Type5.manrope(15, 600)).foregroundStyle(Brand.cocoa)
                            Text("\(left) of \(pieces) \(Pickup.word(item.name, pieces)) left").font(Type5.roundo(17)).foregroundStyle(Brand.cocoa)
                                .contentTransition(.numericText(value: Double(left)))
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<pieces, id: \.self) { k in
                            let inFridge = k >= pieces - left
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(inFridge ? Brand.choc400 : Brand.liquorice100)
                                .overlay { if inFridge { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Brand.caramel, lineWidth: 1.5) } }
                                .frame(height: 14)
                        }
                    }
                    .animation(Motion.quick, value: left)
                    .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        ForEach(store.holders(item), id: \.user) { h in
                            HStack {
                                Text("\(store.name(h.user)) · \(Pickup.count(h.pieces, of: item.name))").font(Type5.manrope(13)).foregroundStyle(Brand.ink2)
                                Spacer()
                                if let at = store.takenAt(h.user) {
                                    Text("Taken \(Wita.string(at, "HH:mm"))").font(Type5.manrope(13, 600)).foregroundStyle(Brand.cocoa)
                                } else {
                                    Text("In the fridge").font(Type5.manrope(13, 600)).foregroundStyle(Brand.caramel)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
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
                    Text(part).font(Type5.manrope(12, 600)).foregroundStyle(Brand.limeDeep)
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
        } else if store.isHost && !taken {
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
