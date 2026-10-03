import SwiftUI
import Supabase

// A2 "Up for sharing" on the group screen (Testing Fixes board): the shared-items card (A-2 member, A-5 owner,
// A-8 locked), the owner's ask-to-share card (A-7), the came-off-at-lock notice (A-8), the rows' Share pills and
// pie buttons, and B1's Add items / Lock order bar. The sheets they open are in ShareSheets.swift.

extension GroupStore {
    /// A claimer's piece colour (part 2's split colours): me Lime, everyone else by join order.
    func pieceColor(_ user: UUID) -> Color {
        if user == me { return Brand.lime }
        let others = activeMembers.map(\.user_id).filter { $0 != me }
        return PieceColors.others[(others.firstIndex(of: user) ?? 0) % PieceColors.others.count]
    }

    /// One fill per piece: the claims in the order they were made, the pieces still up for claiming (hatched until
    /// the order locks, the owner's colour after), then the pieces the owner keeps, in their colour from the start.
    /// `mine` previews my claim at that count, in Lime after the others' (the claim sheet).
    func pieceFills(_ item: Item, mine: Int? = nil) -> [Color?] {
        let pieces = item.share_pieces ?? 0
        let owner = pieceColor(item.owner_id)
        var out: [Color?] = []
        for c in claims(item) where mine == nil || c.user_id != me { out += Array(repeating: pieceColor(c.user_id), count: c.pieces) }
        if let mine { out += Array(repeating: Brand.lime, count: mine) }
        out += Array(repeating: group?.state != .open ? owner : nil, count: max(0, claimable(item) - out.count))
        out += Array(repeating: owner, count: max(0, pieces - out.count))
        return Array(out.prefix(pieces))
    }

    /// "Rani’s", or "Your" for my own.
    func whose(_ user: UUID) -> String { user == me ? "Your" : "\(name(user))’s" }
}

enum PieceColors {
    /// Part 2's split colours without Lime, which is always mine: Rani Chocolate 400, Kevin Pink 100, Dimas
    /// Chocolate 100, Nadia Liquorice 400, Arief Lime Deep.
    static let others: [Color] = [Brand.choc400, Brand.pink100, Brand.choc100, Brand.liquorice400, Brand.limeDeep]
}

/// The piece bar: one 18 pt segment per piece, 2 pt apart, 4 pt corners and capsule ends. Claimed and kept pieces in
/// their holder's colour, the rest a Liquorice 100 hatch. A claimed piece grows from its leading edge on `Motion.pop`,
/// each claimer's run 0.025 s per piece; a released one shrinks on `Motion.leave`. Reduce Motion fades them.
struct PieceBar: View {
    var fills: [Color?]
    var height = PieceMotion.barHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: PieceMotion.segmentGap) {
            ForEach(fills.indices, id: \.self) { i in
                let fill = fills[i]
                let end = height / 2, r = PieceMotion.segmentRadius
                let shape = UnevenRoundedRectangle(topLeadingRadius: i == 0 ? end : r, bottomLeadingRadius: i == 0 ? end : r,
                                                   bottomTrailingRadius: i == fills.count - 1 ? end : r,
                                                   topTrailingRadius: i == fills.count - 1 ? end : r, style: .continuous)
                ZStack {
                    Hatch()
                    Rectangle().fill(fill ?? .clear)
                        .scaleEffect(x: fill == nil && !reduceMotion ? 0.001 : 1, anchor: .leading)
                        .opacity(fill == nil && reduceMotion ? 0 : 1)
                        .animation(animation(i, filled: fill != nil), value: fill)
                }
                .clipShape(shape)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func animation(_ i: Int, filled: Bool) -> Animation {
        if reduceMotion { return Motion.Reduced.fade }
        guard filled else { return PieceMotion.release }
        let start = fills[..<i].lastIndex { $0 != fills[i] }.map { $0 + 1 } ?? 0
        return PieceMotion.claim.delay(Double(i - start) * PieceMotion.remoteStagger)
    }

    /// 135° Liquorice 100 stripes on white, 5 pt each.
    private struct Hatch: View {
        var body: some View {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    ctx.stroke(p, with: .color(Brand.liquorice100), lineWidth: 5)
                    x += 10 / 0.7071
                }
            }
        }
    }
}

/// A 44 pt (or 32 pt) pill in the card's own colours: Claim pieces, Your 2 pieces · Edit, Invite more, Stop sharing,
/// and the rows' Share / Shared. The shared press and a light tap.
struct SharePillStyle: PrimitiveButtonStyle {
    var fill: Color
    var border: Color
    var ink: Color = Brand.cocoa
    var height: CGFloat = 44
    var borderWidth: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        CommitButton(configuration: configuration, face: Face(style: self), haptic: Haptic.tap)
    }

    private struct Face: ButtonStyle {
        var style: SharePillStyle
        @Environment(\.isEnabled) private var enabled
        func makeBody(configuration: Configuration) -> some View {
            let p = configuration.isPressed
            configuration.label
                .labelStyle(IconLabel(spacing: 6, size: style.height < 40 ? 14 : 16))
                .font(GFont.manrope(style.height < 40 ? 13 : 15, 600))
                .lineLimit(1).minimumScaleFactor(0.85)
                .foregroundStyle(enabled ? style.ink : Brand.liquorice400)
                .padding(.horizontal, style.height < 40 ? 12 : 16)
                .frame(maxWidth: style.height < 40 ? nil : .infinity, minHeight: style.height)
                .background(Capsule().fill(enabled ? style.fill : Brand.cream).pressTone(p))
                .overlay(Capsule().strokeBorder(enabled ? style.border : Brand.liquorice100, lineWidth: style.borderWidth))
                .contentShape(Capsule())
                .doughPress(p, squash: Motion.pressCompact)
        }
    }
}

extension GroupView {

    // MARK: The share sheets (ShareSheets.swift), in the Ataste sheet

    var shareSheet: Binding<GroupSheet?> {
        Binding(get: { sheet?.isShareSheet == true ? sheet : nil }, set: { if $0 == nil { sheet = nil } })
    }

    func shareSheetTitle(_ s: GroupSheet) -> String { s.shareTitle(store) }

    func shareSheetView(_ s: GroupSheet) -> ShareSheetView {
        ShareSheetView(store: store, sheet: s, withdrawn: claimWithdrawn, stop: stopSharing) { toast = ToastNote(text: $0) }
    }

    // MARK: Up for sharing (A-2, A-5, A-8)

    /// "UP FOR SHARING · Claim until 13:00" and the card: one block per shared item, three at most until "See all".
    @ViewBuilder func sharedSection(_ g: OrderGroup) -> some View {
        let shared = store.sharedItems
        if !shared.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Up for sharing").brand(.label)
                    Spacer(minLength: 8)
                    if g.state == .open {
                        Text(g.cutoff_at.map { "Claim until \(Wita.string($0, "HH:mm"))" } ?? "Claim before it locks")
                            .ui(GFont.manrope(12), Brand.ink3)
                    }
                }
                .padding(.horizontal, 4)
                SharedCard(view: self, group: g, items: shared)
            }
            .transition(reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade)
                        : AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(PieceMotion.cardIn))
        }
    }

    /// A-7 owner side: "Putri asked you to share Almond Croissant · 1 of 2 pieces", Share / Not this time.
    @ViewBuilder var askCards: some View {
        ForEach(store.asksForMe) { r in
            if let item = store.items.first(where: { $0.id == r.item_id }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        icon("chart.pie", 16).frame(width: 36, height: 36).background(Circle().fill(Brand.pink100))
                        Text("\(Text(store.name(r.requester_id)).font(GFont.manrope(14, 700))) asked you to share \(item.name) · \(r.mine) of \(r.pieces) pieces")
                            .ui(GFont.manrope(14), Brand.cocoa)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        Button("Not this time") {
                            Task { await act("Couldn't answer") { try await store.rpc("decline_share_request", ["request": .string(r.id.uuidString)]) } }
                        }
                        .buttonStyle(SharePillStyle(fill: Brand.cream, border: Brand.choc100))
                        Button { sheet = .shareItem(item, r) } label: { Label("Share", systemImage: "chart.pie") }
                            .buttonStyle(SharePillStyle(fill: Brand.caramel, border: Brand.caramel, ink: Brand.cream))
                    }
                }
                .surface(24, padding: edges(16, 16))
                .transition(.opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fade))
            }
        }
    }

    /// A-8: a shared item came off at lock because too few joined (owner's or joiner's copy, from their notice).
    @ViewBuilder var shareNotices: some View {
        VStack(spacing: 14) {
            ForEach(store.shareNotices, id: \.id) { n in
                HStack(alignment: .top, spacing: 10) {
                    icon("exclamationmark.triangle", 18)
                    Text("\(Text(n.title + ".").font(GFont.manrope(14, 800))) \(n.body)")
                        .ui(GFont.manrope(14, 600), Brand.cocoa)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .surface(24, padding: edges(14, 16), fill: Brand.choc100)
                .transition(reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade)
                            : AnyTransition.opacity.animation(Motion.fade.delay(PieceMotion.noticeFadeDelay))
                                .combined(with: AnyTransition.offset(y: 8).animation(PieceMotion.noticeIn.delay(PieceMotion.noticeDelay))))
            }
        }
        .sensoryFeedback(Haptic.warn, trigger: store.shareNotices.count) { old, new in new > old }
    }

    /// A-6: Stop sharing asks first when someone has claimed; with no claims it applies at once.
    func stopSharing(_ item: Item) {
        let claims = store.claims(item)
        let stop = { try await store.rpc("unshare_item", ["item": .string(item.id.uuidString)]) }
        guard !claims.isEmpty else {
            Task { await act("Couldn't stop sharing", stop) }
            return
        }
        let parts = claims.enumerated().map { i, c in "\(store.name(c.user_id))’s \(i == 0 ? Pieces.label(c.pieces) : "\(c.pieces)")" }
        confirm = Confirm(title: "Stop sharing \(item.name)?",
                          message: "\(joinedNames(parts)) come off \(claims.count == 1 ? "their bill" : "their bills") and they get a heads-up. "
                              + "The whole \(item.name) stays on the order under your name, \(Rupiah.format(item.total)).",
                          button: "Stop sharing", keep: "Keep sharing", action: stop)
    }

    /// A-4: the claim is gone; Undo puts the old count back.
    func claimWithdrawn(_ item: Item, was: Int) {
        toast = ToastNote(text: "Claim withdrawn", action: ToastNote.Action(title: "Undo") {
            Task { await act("Couldn't undo") { try await store.claim(item, pieces: was) } }
        }, hold: 4)
    }

    // MARK: Row controls (A-2, A-5)

    /// My item's Share pill (Pink 100, 32 pt) or, once shared, the Lime "Shared" pill; both open the share settings.
    func sharePill(_ item: Item) -> some View {
        let shared = item.share_pieces != nil
        return Button { sheet = .shareItem(item, nil) } label: {
            Label(shared ? "Shared" : "Share", systemImage: shared ? "checkmark" : "chart.pie")
        }
        .buttonStyle(SharePillStyle(fill: shared ? Brand.lime : Brand.pink100, border: shared ? Brand.limeDeep : Brand.pink100,
                                    height: 32, borderWidth: shared ? 1.5 : 0))
        .fixedSize()
        .accessibilityLabel(shared ? "Sharing settings for \(item.name)" : "Share \(item.name)")
    }

    /// The pie on someone else's row: Ask to share (A-7). Faded to 35 % when they have nothing to ask for.
    func askPie(_ g: OrderGroup, _ user: UUID) -> some View {
        let askable = g.state == .open && store.items(of: user).contains { $0.share_pieces == nil }
        return Button { sheet = .ask(user) } label: { RoundIcon(fill: Brand.pink100) { icon("chart.pie", 14) } }
            .buttonStyle(DoughStyle())
            .disabled(!askable)
            .opacity(askable ? 1 : 0.35)
            .accessibilityLabel("Ask \(store.name(user)) to share")
    }

    /// "Nothing for you yet": the host's empty My items row (B-1).
    var hostEmptyRow: some View {
        HStack(spacing: 12) {
            Circle().strokeBorder(Brand.liquorice400, style: StrokeStyle(lineWidth: 1.5, dash: [4.5, 3]))
                .frame(width: 56, height: 56)
                .overlay { icon("bag", 20, Brand.ink3) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing for you yet").ui(GFont.manrope(15, 700))
                Text("Hosting doesn’t add anything. Pick your own treats too.").ui(GFont.manrope(13), Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 76)
        .accessibilityElement(children: .combine)
    }
}

/// The Up for sharing card: blocks for up to three shared items, then "See all 4".
private struct SharedCard: View {
    var view: GroupView
    var group: OrderGroup
    var items: [Item]
    @State private var all = false

    var body: some View {
        let shown = all ? items : Array(items.prefix(3))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                VStack(spacing: 0) {
                    if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1).padding(.vertical, 16) }
                    SharedBlock(view: view, group: group, item: item)
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
    }
}

/// One shared item: its row, the piece bar, the count line with its chip, who has pieces, and the action.
private struct SharedBlock: View {
    var view: GroupView
    var group: OrderGroup
    var item: Item
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: GroupStore { view.store }
    private var mine: Bool { item.owner_id == store.me }
    private var open: Bool { group.state == .open }
    private var pieces: Int { item.share_pieces ?? 0 }
    private var people: Int { store.sharePeople(item) }
    private var left: Int { store.piecesLeft(item) }
    private var keeps: Int { store.ownerPieces(item) }
    private var owner: String { store.name(item.owner_id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProductPhoto(url: store.products[item.product_id]?.photo, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mine ? "Your \(item.name)" : item.name).ui(GFont.manrope(16, 700))
                    Text(subtitle).ui(GFont.manrope(13), Brand.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if mine && open {
                    Button("Edit") { view.sheet = .shareItem(item, nil) }
                        .ui(GFont.manrope(14, 600), Brand.caramel)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.plain)
                }
            }
            PieceBar(fills: store.pieceFills(item))
            HStack(alignment: .center, spacing: 8) {
                Text(caption).ui(GFont.manrope(15, 700)).monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: caption)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                chip
            }
            peopleChips
            if open { actions }
        }
    }

    private var subtitle: String {
        if mine {
            return "\(pieces) pieces · " + (item.share_min.map { "min \($0) people" } ?? "\(Rupiah.format(Pieces.each(price: item.unit_price, pieces: pieces))) each")
        }
        return "\(owner)’s · \(pieces) pieces · \(Rupiah.format(Pieces.each(price: item.unit_price, pieces: pieces))) each"
    }

    /// "2 people · min 4 · 9 left", "3 people · min 4 · you keep 7", "Only Rani so far · min 4", "All 11 claimed"
    /// (every piece Rani doesn't keep), "4 people · Rani keeps 5" once locked.
    private var caption: String {
        let min = item.share_min.map { " · min \($0)" } ?? ""
        let them = people == 1 ? "1 person" : "\(people) people"
        if !open { return "\(them) · \(mine ? "you keep" : "\(owner) keeps") \(keeps)" }
        if people == 1 { return "Only \(mine ? "you" : owner) so far\(min)" }
        if mine { return "\(them)\(min) · you keep \(keeps)" }
        if left == 0 { return "All \(store.claimable(item)) claimed" }
        return "\(them)\(min) · \(left) left"
    }

    /// Locked in; under the minimum "2 more needed"; at it "Minimum reached". No minimum, no chip.
    @ViewBuilder private var chip: some View {
        let met = item.share_min.map { people >= $0 } ?? true
        ZStack {
            if !open {
                Tag(text: "Locked in", fill: Brand.cocoa, ink: Brand.cream)
            } else if let min = item.share_min {
                Group {
                    if met { Tag(text: "Minimum reached", fill: Brand.lime, border: Brand.limeDeep, check: true) }
                    else { Tag(text: "\(min - people) more needed", fill: Brand.choc100) }
                }
                .id(met)
                .transition(reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade)
                            : .asymmetric(insertion: AnyTransition.opacity.combined(with: .scale(scale: PieceMotion.chipFrom))
                                            .animation(PieceMotion.claim.delay(PieceMotion.chipDelay)),
                                          removal: AnyTransition.opacity.animation(Motion.fadeOut)))
            }
        }
    }

    /// 18 pt colour dot, name, count. Members see the owner first ("keeps the rest"); the owner sees claimers only.
    private var peopleChips: some View {
        let claims = store.claims(item)
        let owners: [(UUID, String)] = mine || claims.isEmpty ? [] : [(item.owner_id, "\(owner) · keeps the rest")]
        let rows = owners + claims.map { c in
            let who = c.user_id == store.me ? "You" : store.name(c.user_id)
            return (c.user_id, mine ? "\(who) · \(c.pieces)" : "\(who) · \(Pieces.label(c.pieces))")
        }
        return FlowRow(spacing: 6) {
            ForEach(rows, id: \.0) { user, text in
                HStack(spacing: 6) {
                    Circle().fill(store.pieceColor(user)).frame(width: 18, height: 18)
                    Text(text).ui(GFont.manrope(13, 600)).lineLimit(1)
                }
                .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 10))
                .background(Capsule().fill(Brand.cream))
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if mine {
            HStack(spacing: 10) {
                Button { view.openShare() } label: { Label("Invite more", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SharePillStyle(fill: Brand.cream, border: Brand.choc100))
                Button("Stop sharing") { view.stopSharing(item) }
                    .buttonStyle(SharePillStyle(fill: Brand.cream, border: Brand.liquorice100, ink: Brand.destructive))
            }
        } else if store.myClaim(item) > 0 {
            Button { view.sheet = .editClaim(item) } label: {
                Label("Your \(Pieces.label(store.myClaim(item))) · Edit", systemImage: "checkmark")
            }
            .buttonStyle(SharePillStyle(fill: Brand.lime, border: Brand.limeDeep))
        } else {
            Button { view.sheet = .claim(item) } label: { Label("Claim pieces", systemImage: "chart.pie") }
                .buttonStyle(SharePillStyle(fill: Brand.cream, border: Brand.choc100))
                .disabled(left == 0, reason: "Every piece is claimed. Ask \(owner) to add more.")
                .padding(.bottom, left == 0 ? 2 : 0)
        }
    }
}

/// B-bar: Add items (secondary) and the main action (primary) side by side at 1 : 1.25; from Dynamic Type
/// .xLarge they stack, Add items on top, both full width.
struct AddLockBar<Add: View, Lock: View>: View {
    @ViewBuilder var add: Add
    @ViewBuilder var lock: Lock
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize >= HostItemsMotion.stackFrom {
            VStack(spacing: 10) { add; lock }
        } else {
            FlexRow(weights: [HostItemsMotion.barWidths.add, HostItemsMotion.barWidths.lock]) { add; lock }
        }
    }
}
