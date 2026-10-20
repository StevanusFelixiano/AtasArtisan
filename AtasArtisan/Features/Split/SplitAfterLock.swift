import SwiftUI

// Shared items after lock (Claude Design "Ataste Screens 10 Split after lock"). From Sent to Closed everyone sees each
// shared item someone claimed from, its piece bar and who holds pieces (10-1), and a sheet per item (10-2). People in
// a split WhatsApp each other from it. While the order is Delivered, anyone in a split marks any holder's pieces of
// that item taken, or the whole item at once (10-3), and puts them back (10-5). The Pickup board's fridge card (10-4,
// PickupViews.swift) marks the same way.

// MARK: - Marking

/// Someone else's pieces of a shared item to put back in the fridge, asked first (10-5).
struct PutBack: Identifiable {
    var item: Item
    var holder: UUID
    var pieces: Int
    var id: String { "\(item.id)-\(holder)" }
}

/// Marking pieces of a shared item from any screen. Mark taken and the whole-item button apply at once with "2 slices
/// marked taken · Undo" for 4 s; the holders hear of it only after that (server cron), so an Undo notifies nobody.
/// Undo puts back exactly the holders that tap marked, without asking. Put back asks first, except on my own row.
struct SplitMarker {
    var store: GroupStore
    var problem: Binding<Problem?>
    var toast: Binding<ToastNote?>
    var ask: Binding<PutBack?>

    /// One holder's pieces, or (nil) every holder's still in the fridge.
    func mark(_ item: Item, _ holder: UUID?) async {
        let all = store.holders(item)
        let marked = all.filter { (holder == nil || $0.user == holder) && store.lineTaken(item, by: $0.user) == nil }
        guard !marked.isEmpty else { return }
        await attempt(problem, "Couldn't mark it taken") { try await store.markSplit(item, holder: holder, taken: true) }
        guard marked.contains(where: { store.lineTaken(item, by: $0.user) != nil }) else { return }
        let n = marked.reduce(0) { $0 + $1.pieces }
        toast.wrappedValue = ToastNote(text: "\(Pickup.count(n, of: item.name)) marked taken", action: ToastNote.Action(title: "Undo") {
            Task {
                await attempt(problem, "Couldn't undo") {
                    // Everyone was in the fridge before the tap: one call puts them all back.
                    if marked.count == all.count {
                        try await store.markSplit(item, holder: nil, taken: false)
                    } else {
                        for h in marked { try await store.markSplit(item, holder: h.user, taken: false) }
                    }
                }
            }
        }, hold: 4)
    }

    /// Put back: my own pieces at once, anyone else's after the 10-5 question.
    func putBack(_ item: Item, _ holder: UUID, pieces: Int) {
        if holder == store.me {
            Task { await put(item, holder) }
        } else {
            ask.wrappedValue = PutBack(item: item, holder: holder, pieces: pieces)
        }
    }

    func put(_ item: Item, _ holder: UUID) async {
        await attempt(problem, "Couldn't put it back") { try await store.markSplit(item, holder: holder, taken: false) }
    }

    /// "Kevin’s 2 slices", "your 3 slices": the controls' VoiceOver labels.
    static func whose(_ store: GroupStore, _ item: Item, _ user: UUID, _ n: Int) -> String {
        "\(user == store.me ? "your" : "\(store.name(user))’s") \(Pickup.count(n, of: item.name))"
    }
}

extension View {
    /// 10-5 as an alert (the repo's rule for questions): "Put Kevin’s 2 slices back in the fridge?", Keep as taken /
    /// Put back.
    func putBackAlert(_ ask: Binding<PutBack?>, store: GroupStore, put: @escaping (PutBack) -> Void) -> some View {
        let p = ask.wrappedValue
        let name = p.map { store.name($0.holder) } ?? ""
        return alert(p.map { "Put \(name)’s \(Pickup.count($0.pieces, of: $0.item.name)) back in the fridge?" } ?? "",
                     isPresented: Binding(get: { ask.wrappedValue != nil }, set: { if !$0 { ask.wrappedValue = nil } }),
                     presenting: p) { p in
            Button("Keep as taken", role: .cancel) {}
            Button("Put back") { put(p) }
        } message: { _ in
            Text("Use this if they’re still in the fridge. They show as not taken again, and \(name) gets a note that they’re back.")
        }
    }
}

/// "Mark taken" on another holder's row: the Chocolate 100 chip with the bag (10-3).
struct MarkTakenChip: View {
    var whose: String
    var action: () -> Void
    var body: some View {
        Button("Mark taken", systemImage: "bag", action: action)
            .buttonStyle(ChipStyle(fill: Brand.choc100))
            .fixedSize()
            .accessibilityLabel("Mark \(whose) taken")
    }
}

/// "Put back" in Caramel on a taken row, with a 44 pt hit area.
struct PutBackLink: View {
    var whose: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Put back").font(GFont.manrope(13, 600)).foregroundStyle(Brand.caramel)
                .fixedSize()
                .contentShape(Rectangle().inset(by: -12))
        }
        .buttonStyle(DoughStyle(squash: Motion.pressCompact))
        .accessibilityLabel("Put \(whose) back in the fridge")
    }
}

/// The lime WhatsApp circle on another holder with a verified number (the host's member-row button). None on my own
/// row, none for someone without a number.
struct HolderWhatsApp: View {
    var store: GroupStore
    var user: UUID
    @Environment(\.openURL) private var openURL

    var body: some View {
        if user != store.me, let phone = store.people[user]?.phone {
            Button { openURL(Links.whatsApp(phone)) } label: { RoundIcon(fill: Brand.lime) { WhatsAppGlyph(size: 15) } }
                .buttonStyle(DoughStyle())
                .accessibilityLabel("WhatsApp \(store.name(user))")
        }
    }
}

// MARK: - 10-1 / 10-3 on the group screen

extension GroupView {
    /// "SHARED ITEMS · 2 · Locked in at 13:00 Thu" (Sent, Confirmed, Closed) or "SHARED ITEMS IN THE FRIDGE · 2"
    /// (Delivered), for everyone, the host included. Shared items nobody claimed from aren't listed.
    @ViewBuilder func splitSection(_ g: OrderGroup) -> some View {
        let items = store.fridgeShared
        if !g.personal && !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(g.state == .delivered ? "Shared items in the fridge" : "Shared items · \(items.count)").brand(.label)
                    Spacer(minLength: 8)
                    if g.state == .delivered {
                        Text("\(items.count)").ui(GFont.manrope(12), Brand.ink3)
                    } else if let at = times?.locked_at {
                        Text("Locked in at \(Wita.string(at, "HH:mm EEE"))").ui(GFont.manrope(12), Brand.ink3)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)
                SplitCard(view: self, group: g, items: items)
            }
        }
    }
}

/// One block per shared item, three at most until "See all 4" (as the Up for sharing card).
private struct SplitCard: View {
    var view: GroupView
    var group: OrderGroup
    var items: [Item]
    @State private var all = false
    @State private var putBack: PutBack?

    var body: some View {
        let shown = all ? items : Array(items.prefix(3))
        let marker = SplitMarker(store: view.store, problem: view.$problem, toast: view.$toast, ask: $putBack)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                VStack(spacing: 0) {
                    if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1).padding(.vertical, 16) }
                    SplitBlock(store: view.store, group: group, item: item, marker: marker) { view.sheet = .splitItem(item) }
                }
                .transition(.itemRow)
            }
            if items.count > 3 && !all {
                Button("See all \(items.count)") { withAnimation(Motion.settle) { all = true } }
                    .ui(GFont.manrope(14, 600), Brand.caramel)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 8)
            }
        }
        .rowMotion(shown.map(\.id))
        .surface(32, padding: edges(18, 18))
        .putBackAlert($putBack, store: view.store) { p in Task { await marker.put(p.item, p.holder) } }
    }
}

/// One shared item. In the split: a row per holder with WhatsApp on the others, and while Delivered each row's taken
/// state with Mark taken / Put back, then the whole-item button. Not in it: the A-2 people chips until delivery, then
/// the rows without controls. The item and its bar open the sheet (10-2).
private struct SplitBlock: View {
    var store: GroupStore
    var group: OrderGroup
    var item: Item
    var marker: SplitMarker
    var open: () -> Void
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pieces: Int { item.share_pieces ?? 0 }
    private var inSplit: Bool { store.inSplit(item) }
    /// Delivered or Closed: the rows carry taken states, and anyone in the split can change them.
    private var pickup: Bool { [.delivered, .closed].contains(group.state) }
    private var canMark: Bool { pickup && inSplit }

    var body: some View {
        let holders = store.holders(item)
        VStack(alignment: .leading, spacing: 14) {
            Button(action: open) { summary(holders) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens who has pieces")
            if inSplit || pickup {
                VStack(spacing: 0) {
                    ForEach(holders, id: \.user) { h in row(h.user, h.pieces) }
                }
            }
            if canMark, let label = Pickup.bulk(item.name, left: store.fridgeLeft(item), of: pieces) {
                Button { run { await marker.mark(item, nil) } } label: { Label(label, systemImage: "bag") }
                    .buttonStyle(SharePillStyle(fill: Brand.cream, border: Brand.choc100))
                    .disabled(busy)
            }
        }
    }

    /// The item row (the delivered caption in place of the subtitle once it's in the fridge), the bar, then the count
    /// line with Locked in (in the split) or the people chips (not in it).
    private func summary(_ holders: [(user: UUID, pieces: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProductPhoto(url: store.products[item.product_id]?.photo, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.owner_id == store.me ? "Your \(item.name)" : item.name).ui(GFont.manrope(16, 700))
                    if pickup && inSplit {
                        let caption = Pickup.inFridge(left: store.fridgeLeft(item), of: pieces, name: item.name,
                                                      at: store.lastTaken(item).map { Wita.string($0, "HH:mm") })
                        Text(caption).ui(GFont.roundo(15))
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: caption)
                    } else {
                        Text(subtitle).ui(GFont.manrope(13), Brand.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                icon("chevron.right", 18, Brand.ink4)
            }
            PieceBar(fills: store.splitFills(item))
            if inSplit && !pickup {
                HStack(spacing: 8) {
                    Text("\(holders.count) people · all \(pieces) handed out").ui(GFont.manrope(15, 700))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Tag(text: "Locked in", fill: Brand.cocoa, ink: Brand.cream)
                }
            }
            if !inSplit && !pickup {
                FlowRow(spacing: 6) {
                    ForEach(holders, id: \.user) { h in
                        PieceChip(color: store.pieceColor(h.user),
                                  text: "\(store.name(h.user)) · \(Pickup.holding(h.pieces, of: item.name, owner: h.user == item.owner_id, you: false))")
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// "Rani’s · 12 slices · you have 3", "12 slices · you keep 5" on my own, "Kevin’s · you’re not in this one".
    private var subtitle: String {
        let all = Pickup.count(pieces, of: item.name)
        if item.owner_id == store.me { return "\(all) · you keep \(store.ownerPieces(item))" }
        let owner = "\(store.name(item.owner_id))’s"
        let mine = store.myClaim(item)
        return mine > 0 ? "\(owner) · \(all) · you have \(mine)" : "\(owner) · you’re not in this one"
    }

    /// Colour dot, "Kevin · 2 slices", and from delivery "In the fridge" / "Taken by you · 12:40", with the controls.
    private func row(_ user: UUID, _ n: Int) -> some View {
        let you = user == store.me
        let line = store.takenLine(item, user)
        let whose = SplitMarker.whose(store, item, user, n)
        return HStack(spacing: 10) {
            Circle().fill(store.pieceColor(user)).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Text(you ? "You" : store.name(user)).font(GFont.manrope(14, 700)).foregroundStyle(Brand.cocoa)) · \(Pickup.holding(n, of: item.name, owner: user == item.owner_id, you: you))")
                    .ui(GFont.manrope(14), Brand.ink2)
                if pickup {
                    if let line { Text(line).ui(GFont.manrope(12, 600)) } else { Text("In the fridge").ui(GFont.manrope(12), Brand.ink3) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if canMark {
                if line != nil {
                    PutBackLink(whose: whose) { marker.putBack(item, user, pieces: n) }.disabled(busy)
                } else if !you {
                    MarkTakenChip(whose: whose) { run { await marker.mark(item, user) } }.disabled(busy)
                }
            }
            if inSplit { HolderWhatsApp(store: store, user: user) }
        }
        .frame(minHeight: pickup ? 48 : 44)
        .overlay(alignment: .top) { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
        .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick, value: line)
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task { await work(); busy = false }
    }
}

// MARK: - 10-2 Shared item sheet

/// One shared item, opened from its block: the item with its price a piece, the bar, and every holder with their
/// pieces and share of the price, WhatsApp on the others (for people in the split). From delivery each row shows
/// TAKEN and who marked it, with Put back / Mark taken for people in the split. Not in it: the same sheet, no buttons.
struct SplitItemSheet: View {
    var store: GroupStore
    var itemID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?
    @State private var toast: ToastNote?
    @State private var putBack: PutBack?
    @State private var busy = false

    private var marker: SplitMarker { SplitMarker(store: store, problem: $problem, toast: $toast, ask: $putBack) }
    private var pickup: Bool { [.delivered, .closed].contains(store.group?.state) }

    var body: some View {
        ScrollView {
            if let item = store.items.first(where: { $0.id == itemID }) {
                content(item)
                    .padding(.horizontal, Brand.s4)
                    .padding(.top, 10)
                    .padding(.bottom, Brand.s5)
            }
        }
        .screen()
        .navigationTitle("Shared item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .problemAlert($problem)
        .putBackAlert($putBack, store: store) { p in Task { await marker.put(p.item, p.holder) } }
        .toast($toast)
    }

    private func content(_ item: Item) -> some View {
        let pieces = item.share_pieces ?? 0
        let holders = store.holders(item)
        let inSplit = store.inSplit(item)
        let canMark = store.pickupOpen && inSplit
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProductPhoto(url: store.products[item.product_id]?.photo, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).ui(GFont.manrope(16, 700))
                    if pickup {
                        Text(Pickup.inFridge(left: store.fridgeLeft(item), of: pieces, name: item.name,
                                             at: store.lastTaken(item).map { Wita.string($0, "HH:mm") }))
                            .ui(GFont.roundo(15))
                    } else {
                        let owner = item.owner_id == store.me ? "Yours" : "\(store.name(item.owner_id))’s"
                        Text("\(owner) · \(Rupiah.format(item.total)) · \(Rupiah.format(Pieces.each(price: item.unit_price, pieces: pieces))) a \(Pickup.word(item.name, 1))")
                            .ui(GFont.manrope(13), Brand.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .surface(24, padding: edges(12, 12))
            PieceBar(fills: store.splitFills(item))
            if !pickup {
                HStack(spacing: 8) {
                    Text("\(holders.count) people · all \(pieces) handed out").ui(GFont.manrope(15, 700))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Tag(text: "Locked in", fill: Brand.cocoa, ink: Brand.cream)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(holders.enumerated()), id: \.element.user) { i, h in
                    if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                    row(item, h.user, h.pieces, inSplit: inSplit, canMark: canMark)
                }
            }
            .surface(24, padding: edges(4, 16))
            if canMark, let label = Pickup.bulk(item.name, left: store.fridgeLeft(item), of: pieces) {
                Button { run { await marker.mark(item, nil) } } label: { Label(label, systemImage: "bag") }
                    .buttonStyle(SharePillStyle(fill: Brand.cream, border: Brand.choc100))
                    .disabled(busy)
            }
            if !pickup && inSplit {
                Text(footnote(item)).ui(GFont.manrope(13), Brand.ink2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Before delivery: avatar, name (owner tag), "keeps 5 · Rp 108.334". From delivery: name, dot and pieces, then
    /// TAKEN with who and when, or In the fridge, and the controls.
    private func row(_ item: Item, _ user: UUID, _ n: Int, inSplit: Bool, canMark: Bool) -> some View {
        let you = user == store.me
        let owner = user == item.owner_id
        let name = you ? "You" : store.name(user)
        let holding = Pickup.holding(n, of: item.name, owner: owner, you: you)
        let line = store.takenLine(item, user, short: true)
        let whose = SplitMarker.whose(store, item, user, n)
        return HStack(spacing: 12) {
            Avatar(name: store.name(user), index: store.colorIndex(user), size: 40, art: store.people[user]?.avatar, bg: store.people[user]?.avatar_bg)
            VStack(alignment: .leading, spacing: pickup ? 5 : 3) {
                if pickup {
                    HStack(spacing: 6) {
                        Text(name).ui(GFont.manrope(15, 700))
                        Circle().fill(store.pieceColor(user)).frame(width: 10, height: 10)
                        Text(holding).ui(GFont.manrope(13), Brand.ink2)
                    }
                    HStack(spacing: 8) {
                        if let line {
                            TakenTag(size: .small)
                            Text(line).ui(GFont.manrope(12, 600))
                        } else {
                            Text("In the fridge").ui(GFont.manrope(12), Brand.ink3)
                        }
                        if canMark {
                            if line != nil {
                                PutBackLink(whose: whose) { marker.putBack(item, user, pieces: n) }.disabled(busy)
                            } else if !you {
                                MarkTakenChip(whose: whose) { run { await marker.mark(item, user) } }.disabled(busy)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(name).ui(GFont.manrope(15, 700))
                        if owner { Text("· owner").ui(GFont.manrope(12), Brand.ink3) }
                    }
                    HStack(spacing: 6) {
                        Circle().fill(store.pieceColor(user)).frame(width: 10, height: 10)
                        Text("\(holding) · \(Rupiah.format(share(item, user, n)))").ui(GFont.manrope(13), Brand.ink2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if inSplit { HolderWhatsApp(store: store, user: user) }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    /// What a holder pays for their pieces, as the bill does: a joiner ⌊price × n ÷ pieces⌋, the owner the rest.
    private func share(_ item: Item, _ user: UUID, _ n: Int) -> Int {
        let pieces = item.share_pieces ?? 0
        return user == item.owner_id ? Pieces.ownerAmount(price: item.unit_price, pieces: pieces, claims: store.claims(item).map(\.pieces))
                                     : Pieces.amount(price: item.unit_price, pieces: pieces, n: n)
    }

    /// "It arrives as one cake. Whoever takes it out of the fridge on Friday can mark everyone’s slices taken from here."
    private func footnote(_ item: Item) -> String {
        let unit = Pickup.word(item.name, 2)
        let day = store.group.map { Wita.string($0.delivery_at, "EEEE") } ?? "delivery day"
        return "\(unit == "slices" ? "It arrives as one cake." : "It arrives whole.") Whoever takes it out of the fridge on \(day) "
            + "can mark everyone’s \(unit) taken from here."
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task { await work(); busy = false }
    }
}
