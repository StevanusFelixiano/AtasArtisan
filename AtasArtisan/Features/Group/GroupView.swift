import SwiftUI
import Supabase

/// Board 3. The group order: header, Rp 200k bar, members and their items, splits, edit requests,
/// delivery photos, and a bottom action bar that depends on the role and the order's state.
struct GroupView: View {
    let id: UUID
    @Binding var path: NavigationPath
    @State private var store: GroupStore
    @State private var sheet: GroupSheet?
    @State private var confirm: Confirm?
    @State private var editRequest: Item?
    @State private var editReason = ""
    @State private var problem: Problem?
    @Environment(\.openURL) private var openURL

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
                LoaderView(line: "Asking the oven…")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(store.group?.name ?? "Order")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refresh()
            switch DebugScreens.value("ATASTE_SHEET") {
            case "menu": sheet = .menu
            case "send": sheet = .send
            case "confirm": sheet = .confirmAtas
            case "bill": sheet = .bill
            case "board": sheet = .board
            case "delivery": sheet = .delivery
            case "share": sheet = .share
            case "split": if let i = store.items.first(where: { $0.owner_id == store.me && store.liveSplit($0) == nil }) { sheet = .split(i) }
            default: break
            }
        }
        .task { await store.watch() }
        .sheet(item: $sheet) { s in sheetView(s) }
        .alert(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            if let c = confirm {
                Button(c.button, role: .destructive) { Task { await run(c.action) } }
                Button("Keep", role: .cancel) {}
            }
        } message: { Text(confirm?.message ?? "") }
        .alert("Ask to change this item", isPresented: Binding(get: { editRequest != nil }, set: { if !$0 { editRequest = nil } })) {
            TextField("Reason, e.g. sold out today", text: $editReason)
            Button("Send") {
                if let item = editRequest { Task { await act("Couldn't send the request") { try await store.rpc("request_edit", ["item": .string(item.id.uuidString), "reason": .string(editReason)]) } } }
                editReason = ""
            }
            Button("Cancel", role: .cancel) { editReason = "" }
        } message: { Text("\(store.name(editRequest?.owner_id ?? UUID())) gets a notification with your reason.") }
        .problemAlert($problem)
    }

    // MARK: Content

    @ViewBuilder private func content(_ g: OrderGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s4) {
                header(g)
                if !g.personal && g.state.isLive && g.state != .cancelled {
                    DiscountBar(subtotal: store.subtotal).card()
                }
                if g.state == .edits && store.hasFlagsForMe { editBanner }
                if g.state == .confirmed || g.state == .delivered, let bill = store.myBill, !store.isHost, bill.total > 0 { myBillCard(bill) }
                Timeline(group: g)
                ForEach(store.activeMembers, id: \.user_id) { m in memberCard(g, m) }
                if !store.proofs.filter({ !$0.hidden }).isEmpty { DeliveryPhotos(store: store) }
                if g.state == .open && !store.isHost {
                    Button("Leave group", role: .destructive) {
                        confirm = Confirm(title: "Leave \(g.name)?", message: "Your items come out of the order and the host gets a heads-up. You can rejoin with the link while the group is open.",
                                          button: "Leave group") { try await store.rpc("leave_group", ["g": .string(id.uuidString)]); path.removeLast() }
                    }
                    .brand(.callout, Brand.destructive).frame(maxWidth: .infinity)
                }
            }
            .padding(Brand.s4)
            .padding(.bottom, 90)
        }
        .screen()
        .refreshable { await store.refresh() }
        .safeAreaInset(edge: .bottom) { actionBar(g) }
        .toolbar {
            if store.isHost && g.state.isLive { ToolbarItem(placement: .topBarTrailing) { hostMenu(g) } }
            if !g.personal && g.state == .open {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .share } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Invite people")
                }
            }
        }
    }

    private func header(_ g: OrderGroup) -> some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack {
                StateTag(state: g.state)
                Spacer()
                if g.state == .open, let c = g.cutoff_at {
                    Label { Text("Locks \(c, style: .relative)") } icon: { Image(systemName: "clock") }.brand(.footnote, Brand.caramel)
                }
            }
            Text(g.name).brand(.title1)
            Text("Hosted by \(store.name(g.host_id)) · \(Wita.string(g.delivery_at, "EEE d MMM, HH:mm")) WITA · \(g.address_label)")
                .brand(.callout, Brand.ink2)
        }
    }

    private var editBanner: some View {
        HStack(alignment: .top, spacing: Brand.s3) {
            Mascot(pose: "pose-confused", size: 56, fill: Brand.pink100)
            VStack(alignment: .leading, spacing: Brand.s2) {
                Text("The host asked you to change an item").brand(.headline)
                ForEach(store.myItems.filter { $0.flagged_at != nil }) { i in
                    Text("\(i.name): \(i.flag_reason ?? "")").brand(.callout, Brand.ink2)
                }
                Text("Replace or remove it, then tap Done editing.").brand(.footnote, Brand.ink3)
            }
        }
        .card(Brand.rCard).overlay(RoundedRectangle(cornerRadius: Brand.rCard).stroke(Brand.pink100, lineWidth: 3))
    }

    private func myBillCard(_ bill: BillRow) -> some View {
        Button { sheet = .bill } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You owe \(store.name(store.group?.host_id ?? UUID()))").brand(.label, Brand.ink3)
                    Text(Rupiah.format(bill.total)).brand(.title1)
                }
                Spacer()
                PayTag(state: PayState(bill))
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private func memberCard(_ g: OrderGroup, _ m: Member) -> some View {
        let mine = m.user_id == store.me
        let items = store.items(of: m.user_id)
        let bill = store.bill.first { $0.user_id == m.user_id }
        return VStack(alignment: .leading, spacing: Brand.s3) {
            HStack(spacing: Brand.s3) {
                Avatar(name: store.name(m.user_id), index: store.colorIndex(m.user_id), host: m.user_id == g.host_id)
                VStack(alignment: .leading, spacing: 0) {
                    Text(mine ? "\(store.name(m.user_id)) (you)" : store.name(m.user_id)).brand(.headline)
                    Text(Rupiah.format(bill?.total ?? items.reduce(0) { $0 + $1.total })).brand(.callout, Brand.ink2)
                }
                Spacer()
                if let bill, [.confirmed, .delivered, .closed].contains(g.state), bill.total > 0, m.user_id != g.host_id { PayTag(state: PayState(bill)) }
                if store.isHost && !mine, let phone = store.people[m.user_id]?.phone {
                    IconCircle(symbol: "message.fill", fill: Brand.lime) { openURL(Links.whatsApp(phone)) }
                        .accessibilityLabel("WhatsApp \(store.name(m.user_id))")
                }
                if store.isHost && !mine && [.open, .locked, .edits].contains(g.state) {
                    Menu {
                        Button("Remove from group", role: .destructive) {
                            confirm = Confirm(title: "Remove \(store.name(m.user_id))?", message: "Their items come out of the order and they get a notification.",
                                              button: "Remove") { try await store.rpc("remove_member", ["g": .string(id.uuidString), "u": .string(m.user_id.uuidString)]) }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("More for \(store.name(m.user_id))")
                }
            }
            if items.isEmpty {
                Text(mine ? "Nothing in the oven...yet!" : "No items yet").brand(.callout, Brand.ink3)
            }
            ForEach(items) { item in itemRow(g, item, mine: mine) }
        }
        .card()
    }

    private func itemRow(_ g: OrderGroup, _ item: Item, mine: Bool) -> some View {
        let editable = mine && (g.state == .open || (g.state == .edits && store.hasFlagsForMe))
        let split = store.liveSplit(item)
        return VStack(alignment: .leading, spacing: Brand.s2) {
            HStack(alignment: .top, spacing: Brand.s3) {
                ProductPhoto(url: store.products[item.product_id]?.photo, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.qty)× \(item.name)").brand(.headline)
                    let opts = store.optionText(item)
                    if !opts.isEmpty { Text(opts).brand(.callout, Brand.ink2) }
                    if !item.note.isEmpty { Text("Note: \(item.note)").brand(.footnote, Brand.ink3) }
                    if let reason = item.flag_reason, item.flagged_at != nil {
                        Tag(text: "Change: \(reason)", fill: Brand.pink100)
                    }
                }
                Spacer()
                Text(Rupiah.format(item.total)).brand(.callout)
            }
            if let split { SplitSummary(store: store, item: item, split: split) }
            HStack(spacing: Brand.s2) {
                if editable {
                    QtyStepper(qty: item.qty) { q in
                        if q == 0 {
                            confirm = Confirm(title: "Remove \(item.name)?", message: split == nil ? "It comes out of your order." : "The split on it is cancelled too.",
                                              button: "Remove") { try await store.remove(item) }
                        } else { Task { await act("Couldn't change the quantity") { try await store.update(item, qty: q) } } }
                    }
                }
                Spacer()
                if g.state == .open && split == nil && store.activeMembers.count > 1 {
                    Button("Split") { sheet = .split(item) }.buttonStyle(.pill(.secondary, .small))
                }
                if store.isHost && [.locked, .edits].contains(g.state) && item.flagged_at == nil {
                    Button("Ask to change") { editRequest = item }.buttonStyle(.pill(.secondary, .small))
                }
            }
        }
        .padding(.top, Brand.s2)
    }

    private func hostMenu(_ g: OrderGroup) -> some View {
        Menu {
            if g.state == .open {
                Button { Task { await act("Couldn't lock") { try await store.rpc("lock_group", ["g": .string(id.uuidString)]) } } } label: { Label("Lock order", systemImage: "lock") }
            }
            if g.state == .locked {
                Button { Task { await act("Couldn't unlock") { try await store.rpc("unlock_group", ["g": .string(id.uuidString), "new_cutoff": .null]) } } } label: { Label("Unlock", systemImage: "lock.open") }
            }
            if [.open, .locked, .edits, .sent].contains(g.state) {
                Button(role: .destructive) {
                    confirm = Confirm(title: "Cancel \(g.name)?", message: "Everyone is told the group was cancelled. This can't be undone.",
                                      button: "Cancel group") { try await store.rpc("cancel_group", ["g": .string(id.uuidString)]) }
                } label: { Label("Cancel group", systemImage: "xmark.circle") }
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel("Host actions")
    }

    // MARK: Bottom bar (Liquid Glass)

    @ViewBuilder private func actionBar(_ g: OrderGroup) -> some View {
        let host = store.isHost
        HStack(spacing: Brand.s3) {
            switch g.state {
            case .open:
                Button("Add items") { sheet = .menu }.buttonStyle(.pill(host && !g.personal ? .secondary : .primary))
                if host {
                    Button(g.personal ? "Send to Atas" : "Lock order") {
                        Task { await act("Couldn't lock") {
                            try await store.rpc("lock_group", ["g": .string(id.uuidString)])
                            if g.personal { sheet = .send }
                        } }
                    }
                    .buttonStyle(.pill(.primary)).disabled(store.items.isEmpty)
                }
            case .edits:
                if store.hasFlagsForMe {
                    Button("Add items") { sheet = .menu }.buttonStyle(.pill(.secondary))
                    Button("Done editing") { Task { await act("Couldn't finish") { try await store.rpc("done_editing", ["g": .string(id.uuidString)]) } } }.buttonStyle(.pill(.primary))
                } else if host {
                    Button("Lock again") { Task { await act("Couldn't lock") { try await store.rpc("lock_group", ["g": .string(id.uuidString)]) } } }
                        .buttonStyle(.pill(.primary)).disabled(store.items.contains { $0.flagged_at != nil })
                } else { waiting("Waiting for edits") }
            case .locked:
                if host { Button("Send to Atas · \(Rupiah.format(store.subtotal))") { sheet = .send }.buttonStyle(.pill(.primary)) }
                else { waiting("\(store.name(g.host_id)) is checking the order") }
            case .sent:
                if host { Button("Atas replied · enter final bill") { sheet = .confirmAtas }.buttonStyle(.pill(.primary)) }
                else { waiting("Waiting for Atas to confirm") }
            case .confirmed:
                if host && !g.personal { Button("Payments") { sheet = .board }.buttonStyle(.pill(.secondary)) }
                else if !host, let b = store.myBill, b.total > 0, b.paid_at == nil { Button("Pay \(Rupiah.format(b.total))") { sheet = .bill }.buttonStyle(.pill(.secondary)) }
                Button("Confirm delivery") { sheet = .delivery }.buttonStyle(.pill(.primary))
            case .delivered:
                if host {
                    if !g.personal { Button("Payments") { sheet = .board }.buttonStyle(.pill(.secondary)) }
                    Button("Close order") { Task { await act("Couldn't close") { try await store.rpc("close_group", ["g": .string(id.uuidString)]) } } }.buttonStyle(.pill(.primary))
                } else if let b = store.myBill, b.total > 0, b.paid_at == nil {
                    Button("Pay \(Rupiah.format(b.total))") { sheet = .bill }.buttonStyle(.pill(.primary))
                }
            case .closed, .cancelled:
                EmptyView()
            }
        }
        .padding(.horizontal, Brand.s4).padding(.vertical, Brand.s3)
        .glassEffect(.regular.tint(Brand.cream.opacity(0.4)), in: .rect(cornerRadius: Brand.rHero))
        .padding(.horizontal, Brand.s3)
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: Brand.s2) {
            ProgressView().tint(Brand.caramel)
            Text(text).brand(.callout, Brand.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
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
        }
    }

    private func run(_ action: @escaping () async throws -> Void) async {
        await act("That didn't work", action)
    }

    private func act(_ title: String, _ work: @escaping () async throws -> Void) async {
        await attempt($problem, title, work)
    }
}

enum GroupSheet: Identifiable {
    case menu, share, split(Item), send, confirmAtas, bill, board, delivery
    var id: String {
        switch self {
        case .menu: "menu"; case .share: "share"; case .split(let i): "split-\(i.id)"; case .send: "send"
        case .confirmAtas: "confirm"; case .bill: "bill"; case .board: "board"; case .delivery: "delivery"
        }
    }
}

struct Confirm {
    var title: String
    var message: String
    var button: String
    var action: () async throws -> Void
}

struct QtyStepper: View {
    var qty: Int
    var change: (Int) -> Void
    var body: some View {
        HStack(spacing: 0) {
            IconCircle(symbol: qty == 1 ? "trash" : "minus") { change(qty - 1) }
                .accessibilityLabel(qty == 1 ? "Remove" : "One less")
            Text("\(qty)").brand(.headline).frame(minWidth: 24)
            IconCircle(symbol: "plus") { change(min(qty + 1, 50)) }.accessibilityLabel("One more")
        }
    }
}

/// The order's states, done and to come (design system timeline).
struct Timeline: View {
    var group: OrderGroup
    private let steps: [GroupState] = [.open, .locked, .sent, .confirmed, .delivered, .closed]

    var body: some View {
        let current = group.state == .edits ? GroupState.locked : group.state
        let at = steps.firstIndex(of: current) ?? 0
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: Brand.s3) {
                    ZStack {
                        Circle().fill(i < at ? Brand.lime : i == at ? Brand.caramel : .white)
                            .overlay(Circle().stroke(i <= at ? Brand.limeDeep : Brand.liquorice400, lineWidth: 1.5))
                        if i < at { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.cocoa) }
                    }
                    .frame(width: 22, height: 22)
                    Text(s == .locked && group.state == .edits ? "Edits requested" : s.title)
                        .brand(i == at ? .headline : .callout, i > at ? Brand.ink4 : Brand.cocoa)
                    Spacer()
                    if let d = date(s) { Text(Wita.string(d, "EEE HH:mm")).brand(.footnote, Brand.ink3) }
                }
                if i < steps.count - 1 {
                    Rectangle().fill(i < at ? Brand.limeDeep : Brand.liquorice100).frame(width: 2, height: 14).padding(.leading, 10)
                }
            }
        }
        .card()
        .opacity(group.state == .cancelled ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private func date(_ s: GroupState) -> Date? {
        switch s {
        case .open: group.created_at
        case .sent: group.sent_at
        case .confirmed: group.confirmed_at
        case .delivered: group.delivered_at ?? group.delivery_at
        case .closed: group.closed_at
        default: nil
        }
    }
}
