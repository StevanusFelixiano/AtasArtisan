import SwiftUI
import Supabase

// A2 sheets, in the Ataste sheet (SheetMotion): Claim pieces (A-3), Your claim (A-4), the owner's share settings
// (A-1's rows for an item already added, and A-7's request answered), Ask to share (A-7). Steppers here are the
// 32 pt PillStepper. Every write is one RPC; the screen refetches after it.

extension GroupSheet {
    /// The sheet's title, read from the item as it was when the sheet opened.
    func shareTitle(_ store: GroupStore) -> String {
        switch self {
        case .claim: "Claim pieces"
        case .editClaim: "Your claim"
        case .shareItem(let item, _): item.share_pieces == nil ? "Share this item" : "Sharing"
        case .ask(let user): "Ask \(store.name(user)) to share"
        default: ""
        }
    }

    var isShareSheet: Bool {
        switch self { case .claim, .editClaim, .shareItem, .ask: true; default: false }
    }
}

/// Which share sheet to show.
struct ShareSheetView: View {
    var store: GroupStore
    var sheet: GroupSheet
    var withdrawn: (Item, Int) -> Void
    var stop: (Item) -> Void
    var asked: (String) -> Void

    var body: some View {
        switch sheet {
        case .claim(let item), .editClaim(let item): ClaimSheet(store: store, itemID: item.id, withdrawn: withdrawn)
        case .shareItem(let item, let request): ShareSettingsSheet(store: store, itemID: item.id, request: request, stop: stop)
        case .ask(let user): AskShareSheet(store: store, owner: user, asked: asked)
        default: EmptyView()
        }
    }
}

// MARK: Rows

/// A-1's pieces and minimum rows (product sheet and share settings): "Pieces · Rp 21.667 a piece" with a 2…24
/// stepper, "Cancel if fewer people join" with its toggle, and "Fewer than 4 people, you included" when on.
/// `floor` is what others have claimed: the stepper stops there, shakes, and says who holds them.
struct ShareRows: View {
    @Binding var pieces: Int
    @Binding var hasMin: Bool
    @Binding var minPeople: Int
    var price: Int
    var minUpper: Int
    var stepper: CGFloat = 28
    var floor = PieceMotion.range.lowerBound
    var floorReason: String? = nil
    @State private var stuck = 0
    @State private var reason = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            divider
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pieces").ui(GFont.manrope(15, 700))
                    Text("\(Rupiah.format(Pieces.each(price: price, pieces: pieces))) a piece").ui(GFont.manrope(13), Brand.ink2)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: pieces)
                    if reason, let floorReason {
                        Text(floorReason).ui(GFont.manrope(12, 600), Brand.destructive)
                            .transition(.opacity.combined(with: .offset(y: ButtonMotion.reasonOffset)))
                    }
                }
            } control: {
                PillStepper(value: "\(pieces)", fill: Brand.cream, gap: 10, pad: 3, minWidth: 20, countSize: 16, button: stepper,
                            canMinus: pieces > max(floor, PieceMotion.range.lowerBound), canPlus: pieces < PieceMotion.range.upperBound,
                            minusLabel: "One piece less", plusLabel: "One piece more",
                            minus: { pieces -= 1 }, plus: { pieces += 1 }, blocked: { if pieces <= floor { stuck += 1 } })
                    .shake(reduceMotion ? 0 : stuck)
            }
            divider
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cancel if fewer people join").ui(GFont.manrope(15, 700))
                    Text("Checked when the order locks.").ui(GFont.manrope(13), Brand.ink2)
                }
            } control: {
                Toggle("Cancel if fewer people join", isOn: $hasMin.animation(reduceMotion ? Motion.Reduced.fade : PieceMotion.shareRows))
                    .labelsHidden().tint(Brand.caramel)
            }
            if hasMin {
                divider
                row {
                    Text("Fewer than \(Text("\(minPeople)").font(GFont.manrope(14, 800))) people, you included")
                        .ui(GFont.manrope(14, 600))
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: minPeople)
                } control: {
                    let upper = max(minUpper, minPeople)
                    PillStepper(value: "\(minPeople)", fill: Brand.cream, gap: 10, pad: 3, minWidth: 20, countSize: 16, button: stepper,
                                canMinus: minPeople > PieceMotion.minPeopleFloor, canPlus: minPeople < upper,
                                minusLabel: "One person fewer", plusLabel: "One person more",
                                minus: { minPeople -= 1 }, plus: { minPeople += 1 })
                }
                .transition(.opacity)
            }
        }
        .sensoryFeedback(Haptic.blocked, trigger: stuck)
        .task(id: stuck) {
            guard stuck > 0, floorReason != nil else { return }
            withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.settle) { reason = true }
            do { try await Task.sleep(for: .seconds(ButtonMotion.reasonHold)) } catch { return }
            withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.fadeOut) { reason = false }
        }
    }

    private var divider: some View { Rectangle().fill(Brand.liquorice100).frame(height: 1) }

    private func row<Label: View, Control: View>(@ViewBuilder _ label: () -> Label, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            label().frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }
}

/// White 24 pt card: photo, name, a line under it.
private func itemCard(_ store: GroupStore, _ item: Item, _ line: String, @ViewBuilder below: () -> some View = { EmptyView() }) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 12) {
            ProductPhoto(url: store.products[item.product_id]?.photo, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).ui(GFont.manrope(16, 700))
                Text(line).ui(GFont.manrope(13), Brand.ink2)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        below()
    }
    .surface(24, padding: edges(14, 16))
}

/// Explainers under the cards: Manrope 500 13, Ink 2.
private func explainer(_ text: String) -> some View {
    Text(text).ui(GFont.manrope(13), Brand.ink2).lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
}

// MARK: Claim (A-3) and Your claim (A-4)

struct ClaimSheet: View {
    var store: GroupStore
    var itemID: UUID
    var withdrawn: (Item, Int) -> Void
    @Environment(\.closeSheet) private var close
    @State private var n: Int?
    @State private var busy = false
    @State private var problem: Problem?
    /// The minimum reached with my claim: success on this device only (the one that made it happen).
    @State private var reached = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: Item? { store.items.first { $0.id == itemID } }

    var body: some View {
        if let item, let pieces = item.share_pieces {
            let was = store.myClaim(item)
            let editing = was > 0
            let room = store.piecesLeft(item) + was
            let count = n ?? (editing ? was : 1)
            let amount = Pieces.amount(price: item.unit_price, pieces: pieces, n: count)
            let owner = store.name(item.owner_id)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        itemCard(store, item, "\(owner)’s · \(store.piecesLeft(item)) of \(pieces) pieces left") {
                            PieceBar(fills: preview(item, count: count))
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Pieces.label(count)).ui(GFont.manrope(16, 700))
                                Text(editing ? "\(Rupiah.format(amount)) · was \(Pieces.label(was))" : "\(Rupiah.format(amount)) on your bill")
                                    .ui(GFont.manrope(13), Brand.ink2)
                            }
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: count)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            PillStepper(value: "\(count)", fill: Brand.cream, gap: 10, pad: 3, minWidth: 20, countSize: 16, button: 32,
                                        minusSymbol: editing && count == 1 ? "trash" : "minus",
                                        canMinus: count > (editing ? 0 : 1), canPlus: count < room,
                                        minusLabel: "One piece less", plusLabel: "One piece more",
                                        minus: { n = count - 1 }, plus: { n = count + 1 })
                        }
                        .surface(24, padding: edges(14, 16))
                        explainer(explanation(item, editing: editing))
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                VStack(spacing: 6) {
                    if editing && count == 0 {
                        Button("Withdraw my claim") { Task { await save(item, 0, was: was) } }
                            .buttonStyle(.pill(.destructive)).disabled(busy)
                    } else {
                        Button { Task { await save(item, count, was: was) } } label: {
                            Text(editing ? "Save · \(Pieces.label(count))" : "Claim \(Pieces.label(count)) · \(Rupiah.format(amount))")
                        }
                        .buttonStyle(.pill(.primary))
                        .disabled(busy || (editing && count == was))
                    }
                    if editing && count > 0 {
                        Button("Withdraw my claim") { Task { await save(item, 0, was: was) } }
                            .ui(GFont.manrope(15, 600), Brand.destructive)
                            .frame(minHeight: 44)
                            .buttonStyle(.plain)
                    }
                }
            }
            .problemAlert($problem)
            .sensoryFeedback(Haptic.done, trigger: reached)
        }
    }

    /// Others' claims as they are, then my pieces in Lime, then the rest hatched.
    private func preview(_ item: Item, count: Int) -> [Color?] {
        var out: [Color?] = []
        for c in store.claims(item) where c.user_id != store.me { out += Array(repeating: store.pieceColor(c.user_id), count: c.pieces) }
        out += Array(repeating: Brand.lime, count: count)
        return Array((out + Array(repeating: nil, count: max(0, (item.share_pieces ?? 0) - out.count))).prefix(item.share_pieces ?? 0))
    }

    private func explanation(_ item: Item, editing: Bool) -> String {
        let owner = store.name(item.owner_id)
        let until = store.group?.cutoff_at.map { " at \(Wita.string($0, "HH:mm"))" } ?? ""
        let rest = "\(owner) keeps the pieces nobody claims."
        guard let min = item.share_min else { return "You can change or withdraw until the order locks\(until). \(rest)" }
        let by = store.group?.cutoff_at.map { "by \(Wita.string($0, "HH:mm"))" } ?? "before the order locks"
        let you = editing ? "" : "You’d be the \(Pieces.ordinal(store.sharePeople(item) + 1)) person; "
        return "\(you)\(owner) needs \(min) \(by) or the \(item.name) comes off the order. You can change or withdraw until then. \(rest)"
    }

    private func save(_ item: Item, _ count: Int, was: Int) async {
        busy = true
        defer { busy = false }
        let before = store.sharePeople(item)
        await attempt($problem, count == 0 ? "Couldn't withdraw" : "Couldn't claim") {
            try await store.claim(item, pieces: count)
            if let min = item.share_min, before < min, store.sharePeople(item) >= min { reached += 1 }
            close?()
            if count == 0 { withdrawn(item, was) }
        }
    }
}

// MARK: Share settings (the owner's A-1 rows for an added item; A-7 answered)

struct ShareSettingsSheet: View {
    var store: GroupStore
    var itemID: UUID
    /// The ask-to-share request being answered: its pieces prefill the stepper.
    var request: ShareRequest?
    var stop: (Item) -> Void
    @Environment(\.closeSheet) private var close
    @State private var pieces = PieceMotion.defaultPieces
    @State private var hasMin = false
    @State private var minPeople = PieceMotion.minPeopleDefault
    @State private var ready = false
    @State private var busy = false
    @State private var problem: Problem?

    private var item: Item? { store.items.first { $0.id == itemID } }
    private var minUpper: Int { max(PieceMotion.minPeopleFloor, min(PieceMotion.range.upperBound, store.activeMembers.count)) }

    var body: some View {
        if let item {
            let shared = item.share_pieces != nil
            let claims = store.claims(item)
            let floor = store.claimed(item)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        itemCard(store, item, "\(Rupiah.format(item.unit_price)) · under your name")
                        if let request {
                            explainer("\(store.name(request.requester_id)) asked for \(request.mine) of \(request.pieces) pieces. They get theirs as soon as you share it.")
                        }
                        ShareRows(pieces: $pieces, hasMin: $hasMin, minPeople: $minPeople, price: item.unit_price, minUpper: minUpper,
                                  stepper: 32, floor: floor,
                                  floorReason: claims.isEmpty ? nil : "\(joinedNames(claims.map { store.name($0.user_id) })) \(claims.count == 1 ? "has" : "have") \(floor) claimed")
                            .padding(.horizontal, 16)
                            .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(.white))
                        explainer(item.qty > 1 ? "Sharing keeps 1 of your \(item.qty) on the order. Anyone in the group can claim pieces until it locks; you keep the rest."
                                               : "Anyone in the group can claim pieces until the order locks. You keep the rest.")
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                VStack(spacing: 6) {
                    Button { Task { await save(item) } } label: {
                        if shared { Text("Save") } else { Label("Share in \(pieces) pieces", systemImage: "chart.pie") }
                    }
                    .buttonStyle(.pill(.primary))
                    .disabled(busy)
                    if shared {
                        Button("Stop sharing") {
                            close?()
                            stop(item)
                        }
                        .ui(GFont.manrope(15, 600), Brand.destructive)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                    }
                }
            }
            .problemAlert($problem)
            .onAppear {
                guard !ready else { return }
                ready = true
                pieces = item.share_pieces ?? request?.pieces ?? Pieces.defaultCount(item.name)
                hasMin = item.share_min != nil
                minPeople = item.share_min ?? min(PieceMotion.minPeopleDefault, minUpper)
            }
        }
    }

    private func save(_ item: Item) async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't share it") {
            try await store.share(item, pieces: pieces, min: hasMin ? minPeople : nil)
            close?()
        }
    }
}

// MARK: Ask to share (A-7)

struct AskShareSheet: View {
    var store: GroupStore
    var owner: UUID
    var asked: (String) -> Void
    @Environment(\.closeSheet) private var close
    @State private var chosen: UUID?
    @State private var pieces = 2
    @State private var mine = 1
    @State private var busy = false
    @State private var problem: Problem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: [Item] { store.items(of: owner).filter { $0.share_pieces == nil } }
    private var name: String { store.name(owner) }

    var body: some View {
        let item = items.first { $0.id == chosen }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                            if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                            radioRow(it)
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(.white))
                    if let item {
                        VStack(spacing: 0) {
                            stepperRow(title: "Pieces", line: "\(Rupiah.format(Pieces.each(price: item.unit_price, pieces: pieces))) a piece",
                                       value: pieces, canMinus: pieces > PieceMotion.range.lowerBound, canPlus: pieces < PieceMotion.range.upperBound) {
                                pieces -= 1
                                mine = min(mine, pieces - 1)
                            } plus: { pieces += 1 }
                            Rectangle().fill(Brand.liquorice100).frame(height: 1)
                            stepperRow(title: "\(mine) of \(pieces) pieces for me",
                                       line: Rupiah.format(Pieces.amount(price: item.unit_price, pieces: pieces, n: mine)),
                                       value: mine, canMinus: mine > 1, canPlus: mine < pieces - 1) { mine -= 1 } plus: { mine += 1 }
                        }
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(.white))
                        explainer("\(name) gets the request in the app. If \(name) shares it, your \(mine == 1 ? "piece is" : "pieces are") claimed for you and the rest of the group can join.")
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            Button { Task { await ask() } } label: { Label("Ask \(name)", systemImage: "chart.pie") }
                .buttonStyle(.pill(.primary))
                .disabled(item == nil || busy)
        }
        .problemAlert($problem)
        .onAppear { if chosen == nil, let first = items.first { choose(first) } }
        .sensoryFeedback(.selection, trigger: chosen) { old, _ in old != nil }
    }

    /// 22 pt radio (Cocoa when chosen), photo, name and price.
    private func radioRow(_ it: Item) -> some View {
        let on = chosen == it.id
        return Button { choose(it) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(on ? Brand.cocoa : Brand.liquorice400, lineWidth: on ? 7 : 1.5)
                }
                .frame(width: 22, height: 22)
                .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick, value: on)
                ProductPhoto(url: store.products[it.product_id]?.photo, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.name).ui(GFont.manrope(15, 700))
                    Text("\(it.qty)× · \(Rupiah.format(it.unit_price)) each").ui(GFont.manrope(13), Brand.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func stepperRow(title: String, line: String, value: Int, canMinus: Bool, canPlus: Bool,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ui(GFont.manrope(15, 700))
                Text(line).ui(GFont.manrope(13), Brand.ink2)
            }
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: line)
            .frame(maxWidth: .infinity, alignment: .leading)
            PillStepper(value: "\(value)", fill: Brand.cream, gap: 10, pad: 3, minWidth: 20, countSize: 16, button: 32,
                        canMinus: canMinus, canPlus: canPlus, minus: minus, plus: plus)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }

    /// A pending request of mine prefills its numbers; otherwise the item's default pieces and one for me.
    private func choose(_ it: Item) {
        chosen = it.id
        let pending = store.myAsk(it)
        pieces = pending?.pieces ?? Pieces.defaultCount(it.name)
        mine = min(pending?.mine ?? 1, pieces - 1)
    }

    private func ask() async {
        guard let item = items.first(where: { $0.id == chosen }) else { return }
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't ask") {
            try await store.rpc("ask_to_share", ["item": .string(item.id.uuidString), "pieces": .integer(pieces), "mine": .integer(mine)])
            close?()
            asked("Asked \(name)")
        }
    }
}
