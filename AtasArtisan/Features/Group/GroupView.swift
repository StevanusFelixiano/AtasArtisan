import SwiftUI
import Supabase

/// Boards 3 to 6: the group order. One screen whose content follows the order's state and the viewer's role
/// (host or member): open (3-1/3-2/3-3/3-8), host review and edit rounds (4-5/4-7/4-8), the member's edit
/// request (4-9/4-10), waiting on the host (3-5), sent (5-2), confirmed (5-4), delivered (5-13), cancelled
/// (6-10). The bottom Liquid Glass bar carries the one next step. The sheets (menu, share, send, bill...)
/// are other screens; this view only presents them.
struct GroupView: View {
    let id: UUID
    @Binding var path: NavigationPath
    @State var store: GroupStore
    @State var sheet: GroupSheet?
    @State var confirm: Confirm?
    @State var problem: Problem?
    @State var toast: ToastNote?
    @State var times: GroupTimes?
    @State var itemTimes: [UUID: Date] = [:]
    /// A flagged item being replaced from the menu: the item, my item ids before, my subtotal before.
    @State var replacing: (item: Item, before: Set<UUID>, subtotal: Int)?
    /// This session's replacements in the current edit round, keyed by the new item (4-10).
    @State var replaced: [UUID: Replacement] = [:]
    @State var removedInRound = false
    @State var reporting: DeliveryProof?
    @State var proofURLs: [UUID: URL] = [:]
    /// The order as it was when an async button was tapped, shown until its result hands off (`AsyncPill`).
    @State var held: OrderGroup?
    @State var gate = SkeletonGate()
    /// People who joined while the screen was open: their avatar pops in (Motion board 11).
    @State var joined: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// The remove-item and leave-group questions, asked in the Ataste confirm sheet (other questions stay alerts).
    @State var asking: Confirm?
    @Environment(\.openURL) var openURL
    @Environment(\.scenePhase) var scenePhase
    /// The host handed the order to WhatsApp (5-1): 5-2's parts wait, hidden, and play in once the app is back, the
    /// send sheet has gone and the order is Sent (Motion board 17).
    @State var awaitingReturn = false
    @State var sentIn = true
    /// Taps that open the share sheet without a pill of their own (the toolbar, Invite, the menus) give a light tap.
    @State var shareTaps = 0

    init(id: UUID, path: Binding<NavigationPath>) {
        self.id = id
        _path = path
        _store = State(initialValue: GroupStore(id: id))
    }

    var body: some View {
        Group {
            if gate.revealed, let g = held ?? store.group {
                content(g).modifier(Arrival(animate: gate.animated))
            } else if let e = store.loadError, store.loaded {
                VStack { ErrorBanner(message: e) { Task { await store.refresh() } } }.padding().frame(maxHeight: .infinity).screen()
            } else if gate.skeleton {
                // 3-7, only for a slow load (Motion board 14); it fades out as the order arrives.
                GroupSkeleton().transition(.asymmetric(insertion: .identity, removal: .opacity.animation(Motion.fadeOut)))
            } else {
                Color.clear.screen()
            }
        }
        // Cream behind the skeleton and the arriving order while they crossfade.
        .background(Brand.cream.ignoresSafeArea())
        .navigationTitle(store.group?.name ?? "Order")
        .toolbar(removing: showsTitle ? nil : .title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await gate.load(store.refresh)
            debugHooks()
        }
        .marksScreen(group: id)
        .task { await store.watch() }
        .task(id: timesKey) { await loadTimes() }
        .sheet(item: Binding(get: { sheet?.ataste == false ? sheet : nil }, set: { sheet = $0 }), onDismiss: finishReplacing) { s in sheetView(s) }
        // The share sheets and Request an edit rise in the Ataste sheet (Motion board 07), the rest are system sheets.
        .doughSheet(item: shareSheet, titled: shareSheetTitle, content: shareSheetView)
        .doughSheet(item: Binding(get: { if case .requestEdit = sheet { sheet } else { nil } }, set: { if $0 == nil { sheet = nil } }),
                    title: "Request an edit") { s in if case .requestEdit(let seed) = s { RequestEditSheet(store: store, seed: seed) } }
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
        .doughSheet(item: $asking) { c in
            ConfirmSheet(confirm: c, delay: c.delay) { Task { await act("That didn't work", c.action) } }
        }
        .doughSheet(item: Binding(get: { if case .share = sheet { sheet } else { nil } }, set: { if $0 == nil { sheet = nil } }),
                    insets: ShareCard.insets) { _ in if let g = store.group { ShareCard(group: g) } }
        .sensoryFeedback(Haptic.tap, trigger: shareTaps)
        .onChange(of: backFromAtas) { _, back in
            guard back else { return }
            awaitingReturn = false
            sentIn = true
        }
        .problemAlert($problem)
        .toast($toast)
        // Someone else moved the order on: Confirmed, Delivered, Edits requested, Cancelled. Not on the first load,
        // and not for a change my own button made.
        .sensoryFeedback(trigger: (held ?? store.group)?.state) { old, new in
            guard let old, let new, old != new, !store.isOwnMove(from: old, to: new) else { return nil }
            return new.watcherHaptic
        }
        .sensoryFeedback(Haptic.done, trigger: store.myBill.map { $0.paid_at != nil }) { old, new in old == false && new == true }
        .onChange(of: store.activeMembers.map(\.user_id)) { old, new in
            if !old.isEmpty { joined.formUnion(Set(new).subtracting(old)) }
        }
    }

    /// Back in the app from the WhatsApp hand-off, the send sheet gone and the order Sent: 5-2 plays in.
    private var backFromAtas: Bool {
        awaitingReturn && scenePhase == .active && sheet == nil && store.group?.state == .sent
    }

    /// Open WhatsApp on 5-1 was tapped: hide 5-2's parts until the app comes back.
    func handedOff() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            awaitingReturn = true
            sentIn = false
        }
    }

    func openShare() {
        shareTaps += 1
        sheet = .share
    }

    /// `AsyncPill`'s hold on the order shown while its result plays.
    var holding: Binding<Bool> {
        Binding(get: { held != nil }, set: { held = $0 ? store.group : nil })
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
        return [.review, .editsHost, .fixing].contains(mode(g)) && g.payPhase == nil
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
            .pullToRefresh {
                await store.refresh()
                return store.loadError == nil
            }
            .screen()
            .safeAreaInset(edge: .bottom) { actionBar(g, m) }
            .toolbar { toolbar(g, m) }
            .navigationTitle([.review, .editsHost].contains(m) && g.payPhase == nil ? "Review order" : g.name)
        }
    }

    @ViewBuilder private func sections(_ g: OrderGroup, _ m: Mode) -> some View {
        switch m {
        case .open: openSections(g)
        case .review: if g.payPhase != nil { payFirstHostSections(g) } else { reviewSections(g) }
        case .editsHost: editsHostSections(g)
        case .fixing: fixingSections(g)
        case .waiting: if g.payPhase != nil { payFirstMemberSections(g) } else { waitingSections(g) }
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
                Button { openShare() } label: { Image(systemName: "square.and.arrow.up") }
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
            if g.payPhase == .asking && g.ongkir_asked_at != nil {
                Button { sheet = .send } label: { Label("Ask Atas again", systemImage: "message") }
            }
            if g.payPhase == .collecting && !store.freeOngkir {
                Button { sheet = .confirmAtas } label: { Label("Change the ongkir", systemImage: "pencil") }
            }
            if s == .open && !g.personal {
                Button { openShare() } label: { Label("Share invite", systemImage: "square.and.arrow.up") }
            }
            if [.confirmed, .delivered, .closed].contains(s) || (g.billFinal && [.locked, .sent].contains(s)) {
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
                    let n = store.activeMembers.count
                    confirm = Confirm(title: "Cancel \(g.name)?",
                                      message: "Everyone’s items are dropped and all \(n) members are told. "
                                          + (s == .sent ? "Atas already has the order, so let them know too. " : "Nothing has been sent to Atas yet. ")
                                          + "This can’t be undone.",
                                      button: "Cancel group", keep: "Keep group") { try await store.rpc("cancel_group", ["g": .string(id.uuidString)]) }
                } label: { Label("Cancel group", systemImage: "trash") }
            }
        } else {
            if s == .open {
                Button { openShare() } label: { Label("Share invite", systemImage: "square.and.arrow.up") }
            }
            if let phone = store.people[g.host_id]?.phone {
                Button { openURL(Links.whatsApp(phone)) } label: { Label("Message \(hostFirst)", systemImage: "message") }
            }
            if s == .confirmed, unpaid != nil {
                Button { sheet = .delivery } label: { Label("Confirm delivery", systemImage: "shippingbox") }
            }
            if let b = store.myBill, b.isFinal, b.total > 0 {
                Button { sheet = .bill } label: { Label("My bill", systemImage: "receipt") }
            }
            if s == .open {
                Divider()
                Button(role: .destructive) { askLeave(g) } label: { Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right") }
            }
        }
    }

    // MARK: Bottom bar (Liquid Glass)

    /// My bill while it is still to pay: final, and not yet marked paid (pay first: before the order is sent too).
    var unpaid: BillRow? {
        guard !store.isHost, let b = store.myBill, b.due > 0 else { return nil }
        return b
    }

    @ViewBuilder private func actionBar(_ g: OrderGroup, _ m: Mode) -> some View {
        switch m {
        case .open:
            if isBorn(g) {
                GroupBar {
                    FlexRow(weights: [1, 1.3]) {
                        Button { sheet = .menu } label: { Label("My items", systemImage: "plus") }.buttonStyle(BarPillStyle(kind: .secondary))
                        Button { sheet = .share } label: { Label("Invite people", systemImage: "square.and.arrow.up") }.buttonStyle(BarPillStyle(kind: .primary))
                    }
                }
            } else if (g.personal || store.isHost) && !store.items.isEmpty {
                // B-bar: a labelled Add items beside the main action, 1 : 1.25.
                GroupBar {
                    AddLockBar {
                        Button { sheet = .menu } label: { Label("Add items", systemImage: "plus") }
                            .buttonStyle(BarPillStyle(kind: .secondary))
                            .accessibilityLabel(g.personal ? "Add items" : "Add items for yourself")
                    } lock: {
                        lockPill(g, title: g.personal ? "Send to Atas" : "Lock order", icon: g.personal ? "paperplane" : "lock")
                    }
                }
            } else {
                GroupBar { Button { sheet = .menu } label: { Label("Add items", systemImage: "plus") }.buttonStyle(.pill(.primary)) }
            }
        case .review where g.payPhase != nil:
            payFirstHostBar(g)
        case .review:
            GroupBar {
                FlexRow(weights: g.personal ? [1] : [1, 1.2]) {
                    if !g.personal {
                        Button { sheet = .requestEdit(RequestSeed()) } label: { Label("Request edits", systemImage: "pencil") }
                            .buttonStyle(BarPillStyle(kind: .secondary))
                    }
                    Button { sheet = .send } label: { Label("Send to Atas", systemImage: "paperplane") }
                        .buttonStyle(BarPillStyle(kind: .primary))
                }
            }
        case .editsHost:
            GroupBar {
                lockPill(g, title: "Lock again", icon: "lock")
                    .disabled(store.items.contains { $0.flagged_at != nil }, reason: "Every flagged item needs fixing first")
            }
        case .fixing:
            GroupBar {
                Button { Task { await doneEditing() } } label: {
                    if store.hasFlagsForMe { Text("Done editing") } else { Label("Done editing", systemImage: "checkmark") }
                }
                .buttonStyle(.pill(.primary)).disabled(store.hasFlagsForMe, reason: "Replace or remove your flagged items first")
            }
        case .sent:
            if store.isHost {
                GroupBar {
                    Group {
                        if g.payFirst && g.billFinal {
                            confirmSentPill()
                        } else {
                            Button("Atas replied · enter final bill") { sheet = .confirmAtas }.buttonStyle(.pill(.primary))
                        }
                    }
                    .entrance(sentIn, offset: HandOffMotion.buttonOffset, Motion.arrive, fade: nil, delay: HandOffMotion.buttonDelay)
                }
            } else {
                memberPayBar(g)
            }
        case .confirmed:
            GroupBar {
                if let b = unpaid {
                    Button { sheet = .bill } label: { Label("Pay \(hostFirst) · \(Rupiah.format(b.due))", systemImage: "receipt") }
                        .buttonStyle(.pill(.primary))
                } else {
                    Button { sheet = .delivery } label: { Label("Confirm delivery", systemImage: "shippingbox") }.buttonStyle(.pill(.primary))
                }
            }
        case .delivered:
            if store.isHost {
                CloseOrderBar(store: store) {
                    Task { await act("Couldn't close") { try await store.rpc("close_group", ["g": .string(id.uuidString)]) } }
                }
            } else {
                memberPayBar(g)
            }
        case .waiting where g.payPhase != nil, .closed:
            memberPayBar(g)
        case .waiting, .cancelled:
            EmptyView()
        }
    }

    // MARK: Actions

    /// Lock order, Lock again, and a personal order's Send to Atas (which locks, then opens the message).
    private func lockPill(_ g: OrderGroup, title: String, icon: String) -> some View {
        AsyncPill(title: title, icon: icon, busyTitle: "Locking…", doneTitle: "Locked", failTitle: "Couldn’t lock",
                  tight: true, holding: holding, refresh: store.refresh, reached: { store.group?.state == .locked }) {
            try await store.rpc("lock_group", ["g": .string(id.uuidString)])
        } then: {
            if g.personal { sheet = .send }
        }
    }

    func lock(_ g: OrderGroup) {
        Task { await act("Couldn't lock") {
            try await store.rpc("lock_group", ["g": .string(id.uuidString)])
            if g.personal { sheet = .send }
        } }
    }

    func askLeave(_ g: OrderGroup) {
        let mine = itemPhrase(store.myItems)
        let what = mine.isEmpty ? "You leave the order" : "Your \(mine) come out of the order"
        asking = Confirm(title: "Leave \(g.name)?",
                          message: "\(what) and \(hostFirst) gets a heads-up. You can rejoin with the link while the group is open.",
                          button: "Leave group", keep: "Stay") {
            try await store.rpc("leave_group", ["g": .string(id.uuidString)])
            path.removeLast()
        }
    }

    func askRemove(_ user: UUID) {
        let theirs = itemPhrase(store.items.filter { $0.owner_id == user })
        confirm = Confirm(title: "Remove \(store.name(user)) from the group?",
                          message: (theirs.isEmpty ? "They" : "Their \(theirs) come out of the order and they") + " get a notification. "
                              + "They can rejoin with the invite link while the group is open.",
                          button: "Remove", keep: "Keep \(store.name(user))") { try await store.rpc("remove_member", ["g": .string(id.uuidString), "u": .string(user.uuidString)]) }
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
        case .share, .requestEdit, .claim, .editClaim, .shareItem, .ask: EmptyView()
        case .send: NavigationStack { SendToAtasView(store: store, handedOff: handedOff) }
        case .confirmAtas: NavigationStack { ConfirmAtasView(store: store) }
        case .bill: NavigationStack { BillView(store: store) }
        case .board: NavigationStack { PaymentBoardView(store: store) { sheet = .send } }
        case .delivery: NavigationStack { DeliveryView(store: store) }
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
        case "claim": if let i = store.sharedItems.first(where: { $0.owner_id != store.me }) { sheet = store.myClaim(i) > 0 ? .editClaim(i) : .claim(i) }
        case "shareitem": if let i = store.myItems.first(where: { $0.share_pieces != nil }) ?? store.myItems.first { sheet = .shareItem(i, nil) }
        case "ask": if let u = store.activeMembers.map(\.user_id).first(where: { u in u != store.me && store.items(of: u).contains { $0.share_pieces == nil } }) { sheet = .ask(u) }
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
    case menu, share, send, confirmAtas, bill, board, delivery, requestEdit(RequestSeed), editDelivery
    /// A2: claim or edit my claim on a shared item, the owner's share settings (answering a request), ask to share.
    case claim(Item), editClaim(Item), shareItem(Item, ShareRequest?), ask(UUID)
    var id: String {
        switch self {
        case .menu: "menu"; case .share: "share"; case .send: "send"
        case .claim(let i): "claim-\(i.id)"; case .editClaim(let i): "edit-claim-\(i.id)"
        case .shareItem(let i, _): "share-item-\(i.id)"; case .ask(let u): "ask-\(u)"
        case .confirmAtas: "confirm"; case .bill: "bill"; case .board: "board"; case .delivery: "delivery"
        case .requestEdit: "request"; case .editDelivery: "edit-delivery"
        }
    }

    /// Shown in the Ataste sheet rather than a system sheet.
    var ataste: Bool {
        switch self { case .requestEdit, .share, .claim, .editClaim, .shareItem, .ask: true; default: false }
    }
}

struct Confirm: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var button: String
    var keep = "Keep"
    /// Seconds between the confirm closing and `action` (a removed row collapses 0.12 s into the sheet's exit).
    var delay: Double = 0
    var action: () async throws -> Void

    init(title: String, message: String, button: String, keep: String = "Keep", delay: Double = 0, action: @escaping () async throws -> Void) {
        self.title = title; self.message = message; self.button = button; self.keep = keep; self.delay = delay; self.action = action
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
        PillStepper(value: "\(qty)", fill: Brand.cream, gap: 10, pad: 3, minWidth: 12, countSize: 16,
                    minusSymbol: qty == 1 ? "trash" : "minus", canPlus: qty < 50,
                    minusLabel: qty == 1 ? "Remove" : "One less", plusLabel: "One more",
                    minus: { change(qty - 1) }, plus: { change(qty + 1) })
    }
}

/// Pills that share the glass bar or sit in cards (4-5 "Request edits" + "Send to Atas", the 60pt "+", 4-9
/// "Replace" / "Remove"): the large pill's colours at 15pt with tight side padding so two fit side by side.
/// `.destructive` is the outlined Remove (white, soft red ring, red text).
struct BarPillStyle: PrimitiveButtonStyle {
    var kind: PillKind
    var width: CGFloat? = nil
    var height: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        CommitButton(configuration: configuration, face: Face(kind: kind, width: width, height: height),
                     haptic: kind == .destructive ? Haptic.heavy : Haptic.tap)
    }

    private struct Face: ButtonStyle {
        var kind: PillKind
        var width: CGFloat?
        var height: CGFloat
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
                .background(Capsule().fill(fill).pressTone(p))
                .overlay(Capsule().strokeBorder(border, lineWidth: 4).pressTone(p))
                .contentShape(Capsule())
                .doughPress(p, squash: width == nil ? Motion.pressWide : Motion.pressIcon)
        }
    }

    private struct BarLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) { configuration.icon.font(.system(size: 16, weight: .semibold)); configuration.title }
        }
    }
}
