import SwiftUI
import Supabase

// The group screen's content per state: open (3-1/3-2/3-3/3-8), waiting on the host (3-5), sent (5-2),
// confirmed (5-4), delivered and closed (5-13), cancelled (6-10).

extension GroupView {

    // MARK: Header

    /// `chipIn` false holds the state chip back until 5-2 plays in after the WhatsApp hand-off (it pops in then).
    func header(_ g: OrderGroup, subtitle: Bool = false, chipIn: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StateTag(group: g)
                    .entrance(chipIn, scale: 0.01, tilt: StepperMotion.iconTilt, Motion.pop, delay: HandOffMotion.chipDelay)
                if g.personal { Tag(text: "Just me", fill: .white, ink: Brand.ink3, dot: Brand.liquorice400) }
                Spacer(minLength: 8)
                headerTrailing(g)
            }
            Text(g.name).ui(GFont.roundo(32)).tracking(-0.32).fixedSize(horizontal: false, vertical: true)
            if subtitle { headerLine(g) }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private func headerTrailing(_ g: OrderGroup) -> some View {
        if g.state == .open, let c = g.cutoff_at {
            TimelineView(.periodic(from: .now, by: 30)) { t in
                HStack(spacing: 6) {
                    icon("clock", 15, Brand.caramel)
                    Text(locksIn(c, now: t.date)).ui(GFont.manrope(14, 700), Brand.caramel)
                }
            }
        } else if g.payPhase != nil {
            Text("Pay first").ui(GFont.manrope(13, 600), Brand.ink2)
        } else if [.locked, .edits].contains(g.state), let at = times?.locked_at {
            Text("Locked at \(Wita.string(at, "HH:mm"))").ui(GFont.manrope(13, 600), Brand.ink2)
        }
    }

    private func locksIn(_ cutoff: Date, now: Date) -> String {
        let mins = Int(cutoff.timeIntervalSince(now) / 60)
        if mins <= 0 { return "Locking now" }
        if mins >= 24 * 60 { return "Locks in \(mins / 1440)d \(mins % 1440 / 60)h" }
        if mins >= 60 { return "Locks in \(mins / 60)h \(mins % 60)m" }
        return "Locks in \(mins)m"
    }

    @ViewBuilder private func headerLine(_ g: OrderGroup) -> some View {
        let when = Wita.string(g.delivery_at, "EEE d MMM, HH:mm")
        if g.personal {
            let place = g.address_label.localizedCaseInsensitiveContains(g.area) ? g.address_label : "\(g.address_label), \(g.area)"
            Text("\(when) · \(place)").ui(GFont.manrope(13), Brand.ink2)
        } else {
            HStack(spacing: 8) {
                Avatar(name: hostName, index: store.colorIndex(g.host_id), size: 24, art: store.people[g.host_id]?.avatar, bg: store.people[g.host_id]?.avatar_bg)
                Text(store.isHost ? "You’re hosting · \(when) WITA · \(g.payFirst ? "Pay first" : "Order first")"
                                  : "Hosted by \(hostName) · \(when) WITA · \(g.address_label)")
                    .ui(GFont.manrope(13), Brand.ink2)
            }
        }
    }

    // MARK: Open (3-1 member, 3-2 host, 3-3 unlocked, 3-8 personal)

    /// 2-4d: a group the host just created, nobody has added anything yet.
    func isBorn(_ g: OrderGroup) -> Bool { !g.personal && store.isHost && store.items.isEmpty }

    @ViewBuilder func openSections(_ g: OrderGroup) -> some View {
        if isBorn(g) {
            header(g, subtitle: false)
            GroupBornState(group: g).padding(.top, Brand.s2)
        } else {
            openSectionsFull(g)
        }
    }

    @ViewBuilder private func openSectionsFull(_ g: OrderGroup) -> some View {
        header(g, subtitle: true)
        DiscountBar(subtotal: store.subtotal, host: hostFirst, personal: g.personal)
        if !g.personal && store.subtotal >= DiscountBar.goal { latestActivity }
        if !g.personal {
            askCards
            sharedSection(g)
        }
        if g.personal {
            personalItems(g)
        } else if store.isHost {
            // B1: the host's own My items above Members, the same card a member sees.
            myItemsCard(g)
            listHeader("Members", count: store.activeMembers.count) {
                Button { openShare() } label: {
                    HStack(spacing: 4) { icon("square.and.arrow.up", 14, Brand.caramel); Text("Invite") }
                        .ui(GFont.manrope(13, 600), Brand.caramel)
                }
                .buttonStyle(.plain)
            }
            memberList(g, store.activeMembers.filter { $0.user_id == g.host_id } + store.activeMembers.filter { $0.user_id != g.host_id })
        } else {
            myItemsCard(g)
            listHeader("Everyone", count: store.activeMembers.count) {
                HStack(spacing: 3) {
                    Text("Tap the")
                    Image(systemName: "chart.pie").font(.system(size: 11, weight: .semibold))
                    Text("to ask someone to share")
                }
                .ui(GFont.manrope(12), Brand.ink3)
                .accessibilityElement(children: .combine)
            }
            memberList(g, store.activeMembers.filter { $0.user_id != store.me })
            Button("Leave group") { askLeave(g) }
                .ui(GFont.manrope(14, 600), Brand.destructive)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
    }

    /// "MEMBERS · 4": the count rolls when someone joins or leaves (Motion board 11).
    private func listHeader<Trailing: View>(_ title: String, count: Int, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            (Text("\(title) · ") + Text("\(count)"))
                .brand(.label)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
                .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: count)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    /// 3-3: who just added what ("Nadia added Banana Cake · Rp 50.000 · now").
    @ViewBuilder private var latestActivity: some View {
        if let item = store.items.filter({ $0.owner_id != store.me }).max(by: { (itemTimes[$0.id] ?? .distantPast) < (itemTimes[$1.id] ?? .distantPast) }),
           let at = itemTimes[item.id] {
            HStack(spacing: 12) {
                Avatar(name: store.name(item.owner_id), index: store.colorIndex(item.owner_id), size: 36, art: store.people[item.owner_id]?.avatar, bg: store.people[item.owner_id]?.avatar_bg)
                (Text(store.name(item.owner_id)).fontWeight(.bold) + Text(" added \(item.name) · \(Rupiah.format(item.total))"))
                    .ui(GFont.manrope(14), Brand.cocoa)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TimelineView(.periodic(from: .now, by: 60)) { t in
                    Text(ago(at, now: t.date)).ui(GFont.manrope(12), Brand.ink3)
                }
            }
            .surface(24, padding: edges(14, 16))
            .accessibilityElement(children: .combine)
        }
    }

    private func ago(_ d: Date, now: Date) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        return m < 1 ? "now" : m < 60 ? "\(m)m" : m < 1440 ? "\(m / 60)h" : "\(m / 1440)d"
    }

    /// 3-1 "My items": photo, name, price each and note, the Share pill and the stepper (a shared item has the Lime
    /// "Shared" pill instead of both). The host has the same card (B1), with an empty row until they add something.
    private func myItemsCard(_ g: OrderGroup) -> some View {
        let mine = store.items(of: store.me ?? UUID())
        let total = mine.reduce(0) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("My items").brand(.label)
                Spacer()
                CountUp(amount: total) { Text(Rupiah.format($0)) }.ui(GFont.roundo(18), total == 0 ? Brand.ink4 : Brand.cocoa)
            }
            .padding(.bottom, 10)
            if mine.isEmpty {
                if store.isHost {
                    hostEmptyRow.padding(.bottom, 10).transition(.itemRow)
                } else {
                    Text("Nothing in the oven…yet!").ui(GFont.manrope(13), Brand.ink4).padding(.vertical, 10)
                }
            }
            ForEach(Array(mine.enumerated()), id: \.element.id) { i, item in
                VStack(spacing: 0) {
                    if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                    myItemRow(g, item)
                }
                .transition(.itemRow)
            }
        }
        .rowMotion(mine.map(\.id))
        .surface(32, padding: EdgeInsets(top: 18, leading: 18, bottom: 8, trailing: 18))
    }

    private func myItemRow(_ g: OrderGroup, _ item: Item) -> some View {
        let shared = item.share_pieces.map { "Sharing · you keep \(store.ownerPieces(item)) of \($0)" }
        return HStack(spacing: 10) {
            ProductPhoto(url: store.products[item.product_id]?.photo, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(nameWithOptions(item)).ui(GFont.manrope(15, 700))
                Text(shared ?? eachLine(item)).ui(GFont.manrope(13), Brand.ink2)
                // The Share pill sits under the price, so the name keeps the row's width beside the stepper.
                if g.state == .open && shared == nil { sharePill(item).padding(.top, 6) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if shared != nil { sharePill(item) } else { QtyStepper(qty: item.qty) { q in changeQty(item, to: q) } }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 76)
    }

    func changeQty(_ item: Item, to q: Int) {
        if q == 0 {
            asking = removeItemConfirm(store, item) { try await store.remove(item) }
        } else {
            Task { await act("Couldn't change the quantity") { try await store.setQty(item, q) } }
        }
    }

    /// "Classic Sourdough · 1000gr · Sliced 15mm".
    func nameWithOptions(_ item: Item) -> String {
        let o = store.optionText(item)
        return o.isEmpty ? item.name : "\(item.name) · \(o)"
    }

    /// "Rp 16.000 each · “warm if possible”".
    private func eachLine(_ item: Item) -> String {
        let price = "\(Rupiah.format(item.unit_price)) each"
        return item.note.isEmpty ? price : "\(price) · “\(item.note)”"
    }

    /// "2× Butter Croissant · 1× Burnt Cheesecake 20 cm (shared) · Banana Cake, 3 of 12": their items, then the
    /// pieces they claimed of others'.
    private func summary(_ user: UUID, _ items: [Item]) -> String {
        let own = items.map { "\($0.qty)× \(nameWithOptions($0))" + ($0.share_pieces == nil ? "" : " (shared)") }
        let claimed = store.items.compactMap { i -> String? in
            guard let pieces = i.share_pieces, let c = store.claims(i).first(where: { $0.user_id == user }) else { return nil }
            return "\(i.name), \(c.pieces) of \(pieces)"
        }
        return (own + claimed).joined(separator: " · ")
    }

    /// 3-1 / 3-2 member rows. Someone joining while the screen is open gets a row that opens at the end, its avatar
    /// popping in; someone leaving folds theirs (Motion board 11).
    private func memberList(_ g: OrderGroup, _ members: [Member]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.user_id) { i, m in
                VStack(spacing: 0) {
                    if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                    memberRow(g, m)
                }
                .transition(.itemRow)
            }
        }
        .rowMotion(members.map(\.user_id))
        .surface(32, padding: edges(4, 18))
    }

    private func memberRow(_ g: OrderGroup, _ m: Member) -> some View {
        let user = m.user_id
        let items = store.items(of: user)
        let claimed = store.claims.contains { $0.user_id == user }
        let amount = store.bill.first { $0.user_id == user }?.items ?? items.reduce(0) { $0 + $1.total }
        let role = user == store.me ? "· you" : user == g.host_id ? "· host" : ""
        // B1: the host's own row is a one-line summary pointing at My items.
        let line = user == store.me ? (items.isEmpty ? "Nothing yet · see My items" : "\(items.count) \(items.count == 1 ? "item" : "items") · in My items")
                 : items.isEmpty && !claimed ? "Nothing in the oven…yet!" : summary(user, items)
        let lineInk = user == store.me ? Brand.ink3 : items.isEmpty && !claimed ? Brand.ink4 : Brand.ink2
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Avatar(name: store.name(user), index: store.colorIndex(user), size: 40, art: store.people[user]?.avatar, bg: store.people[user]?.avatar_bg)
                    .modifier(PopOnAppear(active: joined.contains(user), delay: MembersMotion.rowDelay))
                    .frame(maxHeight: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        (Text(store.name(user)).font(GFont.manrope(16, 700))
                         + Text(role.isEmpty ? "" : " \(role)").font(GFont.manrope(12)).foregroundStyle(Brand.ink3))
                            .foregroundStyle(Brand.cocoa)
                        Spacer(minLength: 8)
                        Text(Rupiah.format(amount)).ui(GFont.roundo(16))
                    }
                    Text(line)
                        .ui(GFont.manrope(13), lineInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                rowAction(g, user)
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.vertical, 14)
    }

    /// Someone else's row: the pie (Ask to share); the host also gets WhatsApp beside it, the circles 8 pt apart. My
    /// own row has no controls.
    @ViewBuilder private func rowAction(_ g: OrderGroup, _ user: UUID) -> some View {
        if user != store.me {
            HStack(spacing: -8) {
                askPie(g, user)
                if store.isHost, let phone = store.people[user]?.phone {
                    Button { openURL(Links.whatsApp(phone)) } label: { RoundIcon(fill: Brand.lime) { WhatsAppGlyph(size: 15) } }
                        .buttonStyle(DoughStyle())
                        .accessibilityLabel("WhatsApp \(store.name(user))")
                }
            }
        }
    }

    /// 3-8: just me. Photo, name with options, price; the count opens a small menu.
    private func personalItems(_ g: OrderGroup) -> some View {
        let mine = store.items(of: store.me ?? UUID())
        return VStack(spacing: 0) {
            if mine.isEmpty {
                Text("Nothing in the oven…yet!").ui(GFont.manrope(13), Brand.ink4).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(mine.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                HStack(spacing: 12) {
                    ProductPhoto(url: store.products[item.product_id]?.photo, size: 52, fill: i % 2 == 0 ? Brand.choc100 : Brand.liquorice100)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nameWithOptions(item)).ui(GFont.manrope(15, 700))
                        Text(Rupiah.format(item.total)).ui(GFont.manrope(13), Brand.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Button { changeQty(item, to: item.qty + 1) } label: { Label("One more", systemImage: "plus") }
                        if item.qty > 1 { Button { changeQty(item, to: item.qty - 1) } label: { Label("One less", systemImage: "minus") } }
                        Button(role: .destructive) { changeQty(item, to: 0) } label: { Label("Remove", systemImage: "trash") }
                    } label: {
                        Text("\(item.qty)").ui(GFont.roundo(16)).frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    }
                    .accessibilityLabel("Quantity \(item.qty), change")
                }
                .padding(.vertical, 10)
            }
        }
        .surface(32, padding: edges(8, 18))
    }

    // MARK: Waiting on the host (3-5)

    @ViewBuilder func waitingSections(_ g: OrderGroup) -> some View {
        header(g)
        shareNotices
        HStack(spacing: 14) {
            Mascot(pose: "pose-waiting", size: 72, fill: Brand.liquorice100)
            VStack(alignment: .leading, spacing: 4) {
                Text(waitingTitle(g)).ui(GFont.roundo(17))
                Text(waitingBody(g)).ui(GFont.manrope(13), Brand.ink2).lineSpacing(3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .surface(32, padding: edges(16, 16))
        timeline(g, .stacked)
        sharedSection(g)
        myItemsCompact
    }

    private func waitingTitle(_ g: OrderGroup) -> String {
        g.state == .edits ? "\(hostFirst) asked for a few edits" : "\(hostFirst) is checking the order"
    }

    private func waitingBody(_ g: OrderGroup) -> String {
        if g.state == .edits {
            return doneThisRound ? "Thanks, your changes are in. \(hostFirst) locks the order again once everyone is done."
                                 : "Your items are fine. \(hostFirst) locks the order again once the edits are done."
        }
        return "You can’t change items now. If something needs fixing, they’ll ask you."
    }

    func timeline(_ g: OrderGroup, _ layout: Timeline.Layout) -> some View {
        Timeline(group: g, lockedAt: times?.locked_at, editsAt: store.items.compactMap(\.flagged_at).min(),
                 hadEdits: store.members.contains { $0.done_editing_at != nil }, layout: layout,
                 flow: g.payFirst && !g.personal ? payFlow(g, layout) : nil)
    }

    /// 3-3 "My items" line: "2× Pain Au Chocolate · Rp 32.000".
    @ViewBuilder var myItemsCompact: some View {
        let mine = store.myItems
        if !mine.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("My items").brand(.label)
                Spacer(minLength: 8)
                (Text(mine.map { "\($0.qty)× \($0.name)" }.joined(separator: ", ") + " · ")
                 + Text(Rupiah.format(mine.reduce(0) { $0 + $1.total })).font(GFont.roundo(14)))
                    .ui(GFont.manrope(14, 600))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
            }
            .surface(32, padding: edges(18, 18))
        }
    }

    // MARK: Sent to Atas (5-2)

    /// Back from the WhatsApp hand-off (`sentIn` turning true), 5-2 is laid out at once and its parts play in: the
    /// chip pops, the waiting card rises 16 pt as its giraffe drops in from 30 pt above, the totals follow, then the
    /// bar's button rises 40 pt. Reduce Motion fades them in.
    @ViewBuilder func sentSections(_ g: OrderGroup) -> some View {
        header(g, chipIn: sentIn)
        HStack(spacing: 14) {
            Mascot(pose: "pose-delivery", size: 110, fill: Brand.cream)
                .entrance(sentIn, offset: HandOffMotion.mascotOffset, Motion.bounce, fades: false, delay: HandOffMotion.mascotDelay)
            VStack(alignment: .leading, spacing: 6) {
                Text("Waiting for Atas to reply").ui(GFont.roundo(20))
                Text(sentBody(g)).ui(GFont.manrope(13), Brand.cocoa).lineSpacing(3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .surface(32, padding: edges(20, 20), fill: Brand.choc100)
        .entrance(sentIn, offset: HandOffMotion.cardOffset, Motion.settle, delay: HandOffMotion.cardDelay)
        VStack(spacing: 10) {
            HStack {
                Text("Items").ui(GFont.manrope(14, 600), Brand.ink2)
                Spacer()
                Text(Rupiah.format(store.subtotal)).ui(GFont.roundo(15))
            }
            HStack {
                Text("Ongkir").ui(GFont.manrope(14, 600), Brand.ink2)
                Spacer()
                // Pay first agreed it before sending.
                if g.billFinal {
                    Text(store.freeOngkir ? "Free" : Rupiah.format(g.ongkir ?? 0)).ui(GFont.roundo(15))
                } else {
                    Text("Waiting for Atas").ui(GFont.manrope(14, 600), Brand.ink3)
                }
            }
        }
        .surface(24, padding: edges(16, 16))
        .entrance(sentIn, offset: HandOffMotion.cardOffset, Motion.settle, delay: HandOffMotion.totalsDelay)
        if g.billFinal && !g.personal {
            // Pay first: payments go on while the order is with Atas.
            billOrPayments(g).entrance(sentIn, offset: HandOffMotion.cardOffset, Motion.settle, delay: HandOffMotion.totalsDelay)
        }
        if store.isHost {
            Button { openURL(Links.whatsApp(Links.atasNumber)) } label: {
                Label { Text("Open the Atas chat") } icon: { WhatsAppGlyph(size: 17) }
            }
            .buttonStyle(BarPillStyle(kind: .secondary, height: 52))
            .entrance(sentIn, offset: HandOffMotion.cardOffset, Motion.settle, delay: HandOffMotion.totalsDelay)
        } else {
            myItemsCompact
        }
    }

    private func sentBody(_ g: OrderGroup) -> String {
        let at = g.sent_at ?? Date()
        let t = Wita.string(at, "HH:mm")
        let beforeCutoff = Wita.calendar.component(.hour, from: at) < Wita.atasCutoffHour
        if !store.isHost {
            return "\(hostFirst) sent the order at \(t) WITA." + (g.billFinal ? "" : " Your bill is final once Atas confirms the ongkir.")
        }
        if g.billFinal {
            return "Sent \(t) WITA on WhatsApp, \(beforeCutoff ? "before" : "after") Atas’s 15:00 cutoff. The bills are already final, so tap Atas confirmed once they reply."
        }
        return beforeCutoff
            ? "Sent \(t) WITA on WhatsApp, before Atas’s 15:00 cutoff. When they confirm the ongkir, enter it here so everyone’s bill is final."
            : "Sent \(t) WITA on WhatsApp, after Atas’s 15:00 cutoff, so delivery can take up to 2 days. When they confirm the ongkir, enter it here so everyone’s bill is final."
    }

    // MARK: Confirmed (5-4)

    @ViewBuilder func confirmedSections(_ g: OrderGroup) -> some View {
        header(g)
        VStack(alignment: .leading, spacing: 10) {
            Text("It’s in the oven!").ui(GFont.shrikhand(30), Brand.choc100)
            Text("Atas confirmed the order. Delivery \(Wita.string(g.delivery_at, "EEE d MMM")) around \(Wita.string(g.delivery_at, "HH:mm")) WITA to \(g.address_label).")
                .ui(GFont.manrope(14), Brand.cream).lineSpacing(3)
        }
        .surface(32, padding: edges(20, 20), fill: Brand.caramel)
        billOrPayments(g)
        timeline(g, .inline)
    }

    @ViewBuilder private func billOrPayments(_ g: OrderGroup) -> some View {
        if store.isHost {
            if !g.personal { paymentsRow }
        } else if let b = store.myBill, b.isFinal, b.total > 0 {
            oweCard(b)
        }
    }

    /// "Payments · 4 of 5 paid · Kevin outstanding" (5-13), opens the payment board.
    private var paymentsRow: some View {
        let owing = store.payers
        let open = store.owing.map { store.name($0.user_id) }
        let line: String = switch open.count {
        case 0: "Everyone paid"
        case 1: "\(owing.count - 1) of \(owing.count) paid · \(open[0]) outstanding"
        case 2: "\(owing.count - 2) of \(owing.count) paid · \(open[0]) and \(open[1]) outstanding"
        default: "\(owing.count - open.count) of \(owing.count) paid · \(open.count) outstanding"
        }
        return Button { sheet = .board } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payments").brand(.label)
                    Text(line).ui(GFont.manrope(14, 600))
                }
                Spacer()
                icon("chevron.right", 18, Brand.ink4)
            }
            .surface(24, padding: edges(16, 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Delivered and closed (5-13)

    @ViewBuilder func deliveredSections(_ g: OrderGroup) -> some View {
        header(g)
        if let proof = store.proofs.filter({ !$0.hidden }).max(by: { $0.created_at < $1.created_at }) { deliveredCard(proof) }
        if g.state == .delivered && store.isHost && !g.personal {
            StillOwesCard(store: store)
        } else {
            if g.state == .delivered, unpaid != nil {
                BillBanner(text: "The treats have arrived. \(hostFirst) can close the order once you’ve paid.", fill: Brand.choc100, circle: Brand.cream)
            }
            billOrPayments(g)
        }
        if g.state == .closed { timeline(g, .inline) }
    }

    private func deliveredCard(_ p: DeliveryProof) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CachedPhoto(url: proofURLs[p.id], key: p.path, side: 400, fill: Brand.liquorice100)
                .frame(height: 200).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contextMenu { Button(role: .destructive) { reporting = p } label: { Label("Report photo", systemImage: "flag") } }
                .accessibilityLabel("Delivery photo by \(store.name(p.by_user))")
            HStack(spacing: 10) {
                Avatar(name: store.name(p.by_user), index: store.colorIndex(p.by_user), size: 30, art: store.people[p.by_user]?.avatar, bg: store.people[p.by_user]?.avatar_bg)
                Text("\(store.name(p.by_user)) confirmed · \(Wita.string(p.created_at, "EEE HH:mm"))").ui(GFont.manrope(14, 600))
            }
        }
        .padding(16)
        .overlay(alignment: .topTrailing) {
            Mascot(pose: "pose-celebrating", size: 96, fill: .clear).offset(x: -10, y: 150).allowsHitTesting(false)
        }
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.lime))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Brand.limeDeep, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .task(id: p.id) {
            proofURLs[p.id] = try? await supabase.storage.from("delivery").createSignedURL(path: p.path, expiresIn: 3600)
        }
    }

    // MARK: Cancelled (6-10)

    func cancelledPage(_ g: OrderGroup) -> some View {
        let mine = store.myItems
        let host = store.isHost ? "You" : hostFirst
        var body = g.sent_at == nil ? "Nothing was sent to Atas and nobody owes anything."
                                    : "Nobody owes anything in Ataste. \(store.isHost ? "Let" : hostFirst + " lets") Atas know."
        if !mine.isEmpty { body += " Your \(itemPhrase(mine)) are saved if you want to start your own order." }
        return ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    PaintingFrame(art: "paint-scream", width: 150, height: 186, tilt: 2)
                    (Text("The Scream of Dough").italic() + Text(" · oil on canvas")).ui(GFont.manrope(12), Brand.ink3)
                }
                StateTag(state: .cancelled)
                Text("\(host) cancelled this group").ui(GFont.roundo(28)).multilineTextAlignment(.center)
                Text(body).ui(GFont.manrope(15), Brand.ink2).lineSpacing(5).multilineTextAlignment(.center).frame(maxWidth: 320)
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if !mine.isEmpty {
                    Button("Start an order with my items") { Task { await startOrder(from: g, items: mine) } }
                        .buttonStyle(.pill(.primary))
                }
                Button("Back to Home") { path.removeLast(path.count) }
                    .ui(GFont.manrope(16, 600), Brand.ink2)
                    .padding(10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
