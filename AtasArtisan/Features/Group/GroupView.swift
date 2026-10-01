import SwiftUI
import Supabase

/// Boards 3 to 6: the group order. One screen whose content follows the order's state and the viewer's role
/// (host or member): open (3-1/3-2/3-3/3-8), host review and edit rounds (4-5/4-7/4-8), the member's edit
/// request (4-9/4-10), waiting on the host (3-5), sent (5-2), confirmed (5-4), delivered (5-13), cancelled
/// (6-10). The bottom Liquid Glass bar carries the one next step. The sheets (menu, split, send, bill...)
/// are other screens; this view only presents them.
struct GroupView: View {
    let id: UUID
    @Binding var path: NavigationPath
    @State var store: GroupStore
    @State var sheet: GroupSheet?
    @State var confirm: Confirm?
    @State var problem: Problem?
    @State var toast: String?
    @State var times: GroupTimes?
    @State var itemTimes: [UUID: Date] = [:]
    /// Member rows opened to show their splits.
    @State var expanded: Set<UUID> = []
    /// A flagged item being replaced from the menu: the item, my item ids before, my subtotal before.
    @State var replacing: (item: Item, before: Set<UUID>, subtotal: Int)?
    /// This session's replacements in the current edit round, keyed by the new item (4-10).
    @State var replaced: [UUID: Replacement] = [:]
    @State var removedInRound = false
    @State var reporting: DeliveryProof?
    @State var proofURLs: [UUID: URL] = [:]
    @Environment(\.openURL) var openURL

    init(id: UUID, path: Binding<NavigationPath>) {
        self.id = id
        _path = path
        _store = State(initialValue: GroupStore(id: id))
    }

    var body: some View {
        Group {
            if let g = store.group {
                content(g)
            } else if let e = store.loadError, store.loaded {
                VStack { ErrorBanner(message: e) { Task { await store.refresh() } } }.padding().frame(maxHeight: .infinity).screen()
            } else {
                GroupSkeleton()
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(store.group?.name ?? "Order")
        .toolbar(removing: showsTitle ? nil : .title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refresh()
            debugHooks()
        }
        .task { await store.watch() }
        .task(id: timesKey) { await loadTimes() }
        .sheet(item: $sheet, onDismiss: finishReplacing) { s in sheetView(s) }
        .alert(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            if let c = confirm {
                Button(c.keep, role: .cancel) {}
                Button(c.button, role: .destructive) { Task { await act("That didn't work", c.action) } }
            }
        } message: { Text(confirm?.message ?? "") }
        .alert("Report this photo?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Report and hide", role: .destructive) {
                if let p = reporting { Task { await act("Couldn't report") { try await store.rpc("report_photo", ["proof": .string(p.id.uuidString)]) } } }
            }
        } message: { Text("It's hidden for everyone in the group, and we review it.") }
        .problemAlert($problem)
        .toast($toast)
    }

    // MARK: Who sees what

    enum Mode { case open, review, editsHost, fixing, waiting, sent, confirmed, delivered, closed, cancelled }

    var me: Member? { store.members.first { $0.user_id == store.me } }
    /// I pressed Done editing after the latest lock, so this round is finished for me.
    var doneThisRound: Bool {
        guard let d = me?.done_editing_at else { return false }
        return d > (times?.locked_at ?? .distantPast)
    }

    func mode(_ g: OrderGroup) -> Mode {
        switch g.state {
        case .open: .open
        case .locked: store.isHost ? .review : .waiting
        case .edits:
            if store.hasFlagsForMe || ((!replaced.isEmpty || removedInRound) && !doneThisRound) { .fixing }
            else { store.isHost ? .editsHost : .waiting }
        case .sent: .sent
        case .confirmed: .confirmed
        case .delivered: .delivered
        case .closed: .closed
        case .cancelled: .cancelled
        }
    }

    /// Screens that draw their own heading hide the bar title (it stays set for the back menu).
    var showsTitle: Bool {
        guard let g = store.group else { return false }
        return [.review, .editsHost, .fixing].contains(mode(g))
    }

    /// 6-8: no network. The last loaded order stays readable; changes wait for the connection.
    var offline: Bool { groupOffline }

    var hostName: String { store.name(store.group?.host_id ?? UUID()) }
    var hostFirst: String { String(hostName.split(separator: " ").first ?? Substring(hostName)) }

    // MARK: Content

    @ViewBuilder func content(_ g: OrderGroup) -> some View {
        let m = mode(g)
        if m == .cancelled {
            cancelledPage(g)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if offline {
                        NoticeBanner(icon: "wifi.slash", text: "You’re offline. Showing the order as of \(Wita.string(store.loadedAt ?? Date(), "HH:mm")).",
                                     fill: Brand.liquorice100, actionTitle: "Retry") { Task { await store.refresh() } }
                    }
                    VStack(alignment: .leading, spacing: 14) { sections(g, m) }
                        .opacity(offline ? 0.7 : 1)
                        .disabled(offline)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .screen()
            .refreshable { await store.refresh() }
            .safeAreaInset(edge: .bottom) { actionBar(g, m) }
            .toolbar { toolbar(g, m) }
            .navigationTitle(m == .fixing ? g.name : "Review order")
        }
    }

    @ViewBuilder private func sections(_ g: OrderGroup, _ m: Mode) -> some View {
        switch m {
        case .open: openSections(g)
        case .review: reviewSections(g)
        case .editsHost: editsHostSections(g)
        case .fixing: fixingSections(g)
        case .waiting: waitingSections(g)
        case .sent: sentSections(g)
        case .confirmed: confirmedSections(g)
        case .delivered, .closed: deliveredSections(g)
        case .cancelled: EmptyView()
        }
    }

    // MARK: Toolbar (Liquid Glass capsule: share + more)

    @ToolbarContentBuilder private func toolbar(_ g: OrderGroup, _ m: Mode) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if g.state == .open && !g.personal {
                Button { sheet = .share } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share invite")
            }
            if hasMoreMenu(g) {
                Menu { moreMenu(g) } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel(store.isHost ? "Host actions" : "More")
            }
        }
    }

    private func hasMoreMenu(_ g: OrderGroup) -> Bool {
        if store.isHost { return g.state != .cancelled }
        return true
    }

    /// 3-4 Host menu, and the member's equivalent.
    @ViewBuilder private func moreMenu(_ g: OrderGroup) -> some View {
        let s = g.state
        if store.isHost {
            if s == .open && !g.personal {
                Button { lock(g) } label: { Label("Lock order", systemImage: "lock") }.disabled(store.items.isEmpty)
            }
            if s == .locked {
                Button { Task { await act("Couldn't unlock") { try await store.rpc("unlock_group", ["g": .string(id.uuidString), "new_cutoff": .null]) } } }
                    label: { Label("Unlock order", systemImage: "lock.open") }
            }
            if [.locked, .edits].contains(s) && !g.personal {
                Button { sheet = .requestEdit(RequestSeed()) } label: { Label("Request edits", systemImage: "pencil") }
            }
            if [.open, .locked, .edits].contains(s) {
                Button { sheet = .editDelivery } label: { Label("Edit delivery details", systemImage: "mappin.and.ellipse") }
            }
            if s == .open && !g.personal {
                Button { sheet = .share } label: { Label("Share invite", systemImage: "square.and.arrow.up") }
            }
            if [.confirmed, .delivered, .closed].contains(s) {
                Button { sheet = g.personal ? .bill : .board } label: { Label(g.personal ? "My bill" : "Payments", systemImage: "receipt") }
            }
            Divider()
            let others = store.activeMembers.filter { $0.user_id != g.host_id }
            if [.open, .locked, .edits].contains(s) && !others.isEmpty {
                Menu {
                    ForEach(others, id: \.user_id) { m in
                        Button(store.name(m.user_id)) { askRemove(m.user_id) }
                    }
                } label: { Label("Remove a member", systemImage: "person") }
            }
            if [.open, .locked, .edits, .sent].contains(s) {
                Button(role: .destructive) {
                    confirm = Confirm(title: "Cancel \(g.name)?", message: "Everyone is told the group was cancelled. This can't be undone.",
                                      button: "Cancel group") { try await store.rpc("cancel_group", ["g": .string(id.uuidString)]) }
                } label: { Label("Cancel group", systemImage: "trash") }
            }
        } else {
            if s == .open {
                Button { sheet = .share } label: { Label("Share invite", systemImage: "square.and.arrow.up") }
            }
            if let phone = store.people[g.host_id]?.phone {
                Button { openURL(Links.whatsApp(phone)) } label: { Label("Message \(hostFirst)", systemImage: "message") }
            }
            if s == .confirmed, unpaid != nil {
                Button { sheet = .delivery } label: { Label("Confirm delivery", systemImage: "shippingbox") }
            }
            if [.confirmed, .delivered, .closed].contains(s), let b = store.myBill, b.total > 0 {
                Button { sheet = .bill } label: { Label("My bill", systemImage: "receipt") }
            }
            if s == .open {
                Divider()
                Button(role: .destructive) { askLeave(g) } label: { Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right") }
            }
        }
    }

    // MARK: Bottom bar (Liquid Glass)

    /// My bill while it is still to pay.
    var unpaid: BillRow? {
        guard !store.isHost, let b = store.myBill, b.total > 0, b.paid_at == nil else { return nil }
        return b
    }

    @ViewBuilder private func actionBar(_ g: OrderGroup, _ m: Mode) -> some View {
        switch m {
        case .open:
            if g.personal || store.isHost {
                GlassBar {
                    addCircle
                    Button { lock(g) } label: {
                        Label(g.personal ? "Send to Atas" : "Lock order", systemImage: g.personal ? "paperplane" : "lock")
                    }
                    .buttonStyle(.pill(.primary)).disabled(store.items.isEmpty)
                }
            } else {
                GlassBar { Button { sheet = .menu } label: { Label("Add items", systemImage: "plus") }.buttonStyle(.pill(.primary)) }
            }
        case .review:
            GlassBar {
                if !g.personal {
                    Button { sheet = .requestEdit(RequestSeed()) } label: { Label("Request edits", systemImage: "pencil") }
                        .buttonStyle(BarPillStyle(kind: .secondary))
                        .layoutPriority(1)
                }
                Button { sheet = .send } label: { Label("Send to Atas", systemImage: "paperplane") }
                    .buttonStyle(BarPillStyle(kind: .primary))
                    .layoutPriority(1.2)
            }
        case .editsHost:
            GlassBar {
                Button { lock(g) } label: { Label("Lock again", systemImage: "lock") }
                    .buttonStyle(.pill(.primary)).disabled(store.items.contains { $0.flagged_at != nil })
            }
        case .fixing:
            GlassBar {
                Button { Task { await doneEditing() } } label: {
                    if store.hasFlagsForMe { Text("Done editing") } else { Label("Done editing", systemImage: "checkmark") }
                }
                .buttonStyle(.pill(.primary)).disabled(store.hasFlagsForMe)
            }
        case .sent:
            if store.isHost {
                GlassBar { Button("Atas replied · enter final bill") { sheet = .confirmAtas }.buttonStyle(.pill(.primary)) }
            }
        case .confirmed:
            GlassBar {
                if let b = unpaid {
                    Button { sheet = .bill } label: { Label("Pay \(hostFirst) · \(Rupiah.format(b.total))", systemImage: "receipt") }
                        .buttonStyle(.pill(.primary))
                } else {
                    Button { sheet = .delivery } label: { Label("Confirm delivery", systemImage: "shippingbox") }.buttonStyle(.pill(.primary))
                }
            }
        case .delivered:
            if store.isHost {
                GlassBar {
                    Button("Close order") { Task { await act("Couldn't close") { try await store.rpc("close_group", ["g": .string(id.uuidString)]) } } }
                        .buttonStyle(.pill(.dark))
                }
            } else if let b = unpaid {
                GlassBar {
                    Button { sheet = .bill } label: { Label("Pay \(hostFirst) · \(Rupiah.format(b.total))", systemImage: "receipt") }
                        .buttonStyle(.pill(.primary))
                }
            }
        case .waiting, .closed, .cancelled:
            EmptyView()
        }
    }

    /// The 60pt "+" beside the main action (3-2, 3-8).
    private var addCircle: some View {
        Button { sheet = .menu } label: { Image(systemName: "plus").font(.system(size: 20, weight: .semibold)) }
            .buttonStyle(BarPillStyle(kind: .secondary, width: 60))
            .accessibilityLabel("Add items")
    }

    // MARK: Actions

    func lock(_ g: OrderGroup) {
        Task { await act("Couldn't lock") {
            try await store.rpc("lock_group", ["g": .string(id.uuidString)])
            if g.personal { sheet = .send }
        } }
    }

    func askLeave(_ g: OrderGroup) {
        let mine = itemPhrase(store.myItems)
        let what = mine.isEmpty ? "You leave the order" : "Your \(mine) come out of the order"
        confirm = Confirm(title: "Leave \(g.name)?",
                          message: "\(what) and \(hostFirst) gets a heads-up. You can rejoin with the link while the group is open.",
                          button: "Leave group", keep: "Stay") {
            try await store.rpc("leave_group", ["g": .string(id.uuidString)])
            path.removeLast()
        }
    }

    func askRemove(_ user: UUID) {
        confirm = Confirm(title: "Remove \(store.name(user))?", message: "Their items come out of the order and they get a notification.",
                          button: "Remove") { try await store.rpc("remove_member", ["g": .string(id.uuidString), "u": .string(user.uuidString)]) }
    }

    func doneEditing() async {
        await act("Couldn't finish") {
            try await store.rpc("done_editing", ["g": .string(id.uuidString)])
            await loadTimes()
        }
    }

    func act(_ title: String, _ work: @escaping () async throws -> Void) async {
        await attempt($problem, title, work)
    }

    /// `locked_at` and item times, which the shared models don't carry.
    private var timesKey: String {
        "\(store.group?.state.rawValue ?? "")|\(store.items.map(\.id.uuidString).joined())|\(store.members.compactMap(\.done_editing_at).count)"
    }

    func loadTimes() async {
        guard store.group != nil else { return }
        times = try? await supabase.from("groups").select("locked_at,cancelled_at").eq("id", value: id).single().execute().value
        let rows: [ItemTime] = (try? await supabase.from("items").select("id,created_at").eq("group_id", value: id).execute().value) ?? []
        itemTimes = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.created_at) })
    }

    // MARK: Sheets

    @ViewBuilder private func sheetView(_ s: GroupSheet) -> some View {
        switch s {
        case .menu: NavigationStack { MenuView(store: store) }
        case .share: if let g = store.group { NavigationStack { ShareCard(group: g) } }
        case .split(let item): NavigationStack { SplitProposeView(store: store, item: item) }
        case .send: NavigationStack { SendToAtasView(store: store) }
        case .confirmAtas: NavigationStack { ConfirmAtasView(store: store) }
        case .bill: NavigationStack { BillView(store: store) }
        case .board: NavigationStack { PaymentBoardView(store: store) }
        case .delivery: NavigationStack { DeliveryView(store: store) }
        case .requestEdit(let seed): NavigationStack { RequestEditSheet(store: store, seed: seed) }
        case .editDelivery: NavigationStack { EditDeliverySheet(store: store) }
        }
    }

    /// DEBUG screenshot hooks: ATASTE_SHEET opens a sheet (or the leave / request-edit confirmations);
    /// ATASTE_REPLACED="Old name:old price:subtotal before" fakes a replacement on my first item (4-10).
    private func debugHooks() {
        switch DebugScreens.value("ATASTE_SHEET") {
        case "menu": sheet = .menu
        case "send": sheet = .send
        case "confirm": sheet = .confirmAtas
        case "bill": sheet = .bill
        case "board": sheet = .board
        case "delivery": sheet = .delivery
        case "share": sheet = .share
        case "split": if let i = store.items.first(where: { $0.owner_id == store.me && store.liveSplit($0) == nil }) { sheet = .split(i) }
        case "request": sheet = .requestEdit(RequestSeed(member: store.items.first { $0.owner_id != store.me }?.owner_id,
                                                         item: store.items.first { $0.owner_id != store.me }?.id, reason: .soldOut))
        case "delivery-details": sheet = .editDelivery
        case "leave": if let g = store.group { askLeave(g) }
        default: break
        }
        if let fake = DebugScreens.value("ATASTE_REPLACED"), let item = store.myItems.last {
            let parts = fake.split(separator: ":").map(String.init)
            if parts.count == 3, let old = Int(parts[1]), let before = Int(parts[2]) {
                replaced[item.id] = Replacement(oldName: parts[0], oldQty: 1, oldTotal: old, subtotalBefore: before)
            }
        }
    }
}

enum GroupSheet: Identifiable {
    case menu, share, split(Item), send, confirmAtas, bill, board, delivery, requestEdit(RequestSeed), editDelivery
    var id: String {
        switch self {
        case .menu: "menu"; case .share: "share"; case .split(let i): "split-\(i.id)"; case .send: "send"
        case .confirmAtas: "confirm"; case .bill: "bill"; case .board: "board"; case .delivery: "delivery"
        case .requestEdit: "request"; case .editDelivery: "edit-delivery"
        }
    }
}

struct Confirm {
    var title: String
    var message: String
    var button: String
    var keep = "Keep"
    var action: () async throws -> Void

    init(title: String, message: String, button: String, keep: String = "Keep", action: @escaping () async throws -> Void) {
        self.title = title; self.message = message; self.button = button; self.keep = keep; self.action = action
    }
}

/// A flagged item the member swapped for another this session (4-10 "replaces Almond Croissant").
struct Replacement: Hashable {
    var oldName: String
    var oldQty: Int
    var oldTotal: Int
    var subtotalBefore: Int
}

/// The quantity control in item rows (3-1): two 28pt choc-100 circles on a cream capsule, Roundo 16 count.
struct QtyStepper: View {
    var qty: Int
    var change: (Int) -> Void
    var body: some View {
        HStack(spacing: 10) {
            step(qty == 1 ? "trash" : "minus", qty == 1 ? Brand.trashFill : Brand.choc100) { change(qty - 1) }
                .accessibilityLabel(qty == 1 ? "Remove" : "One less")
            Text("\(qty)").ui(GFont.roundo(16)).frame(minWidth: 12)
            step("plus", Brand.choc100) { change(min(qty + 1, 50)) }.accessibilityLabel("One more")
        }
        .padding(3)
        .background(Capsule().fill(Brand.cream))
    }

    private func step(_ symbol: String, _ fill: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(symbol == "trash" ? Brand.destructive : Brand.cocoa)
                .frame(width: 28, height: 28).background(Circle().fill(fill))
                .padding(8).contentShape(Rectangle()).padding(-8)
        }
        .buttonStyle(.plain)
    }
}

/// Pills that share the glass bar or sit in cards (4-5 "Request edits" + "Send to Atas", the 60pt "+", 4-9
/// "Replace" / "Remove"): the large pill's colours at 15pt with tight side padding so two fit side by side.
/// `.destructive` is the outlined Remove (white, soft red ring, red text).
struct BarPillStyle: ButtonStyle {
    var kind: PillKind
    var width: CGFloat? = nil
    var height: CGFloat = 60
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let p = configuration.isPressed
        let (fill, border, ink): (Color, Color, Color) = switch (kind, enabled) {
        case (_, false): kind == .secondary ? (Brand.cream, Brand.liquorice100, Brand.liquorice400) : (Brand.liquorice400, Brand.liquorice400, Brand.cream)
        case (.secondary, true): (p ? Brand.creamPressed : Brand.cream, p ? Brand.choc100Pressed : Brand.choc100, Brand.cocoa)
        case (.dark, true): (p ? Brand.cocoaPressed : Brand.cocoa, p ? Brand.cocoaPressed : Brand.cocoa, Brand.cream)
        case (.destructive, true): (p ? Brand.trashFill : .white, Brand.destructiveSoft, Brand.destructive)
        case (.success, true): (p ? Brand.limePressed : Brand.lime, p ? Brand.limeDeepPressed : Brand.limeDeep, Brand.cocoa)
        case (.primary, true): (p ? Brand.caramelPressed : Brand.caramel, p ? Brand.caramelPressed : Brand.caramel, Brand.cream)
        }
        configuration.label
            .labelStyle(BarLabel())
            .font(GFont.manrope(15, 600))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: height)
            .foregroundStyle(ink)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border, lineWidth: 4))
            .contentShape(Capsule())
    }

    private struct BarLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) { configuration.icon.font(.system(size: 16, weight: .semibold)); configuration.title }
        }
    }
}
