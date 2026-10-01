import SwiftUI
import Supabase

// Lock and review (4-5), asking for edits (4-6), the host's edit round (4-7 / 4-8), and the member's edit
// request (4-9 / 4-10).

/// What the Request-an-edit sheet opens on.
struct RequestSeed {
    enum Reason: CaseIterable { case soldOut, size, note }
    var member: UUID?
    var item: UUID?
    var reason: Reason?
}

extension GroupView {

    // MARK: 4-5 Review (host, locked)

    /// One line of the review list: an item of the member's own, or their share of someone else's split.
    struct ReviewLine: Identifiable {
        var id: String
        var item: Item
        var qty: String
        var name: String
        var meta: String
        var metaInk: Color
        var amount: Int
        var flagged: Bool
    }

    func soldOut(_ item: Item) -> Bool { store.products[item.product_id]?.available == false }

    func reviewLines(_ user: UUID) -> [ReviewLine] {
        var lines: [ReviewLine] = []
        for item in store.items(of: user) {
            var meta = item.note.isEmpty ? "" : "“\(item.note)”"
            var ink = Brand.ink3
            var amount = item.total
            if let r = item.flag_reason, item.flagged_at != nil { meta = r.isEmpty ? "Change requested" : r; ink = Brand.editsInk }
            else if soldOut(item) { meta = "Sold out on the menu"; ink = Brand.editsInk }
            else if let sp = store.liveSplit(item), sp.state == "accepted" {
                let shares = store.shares(sp).sorted { a, _ in a.user_id == item.owner_id }
                let amounts = Shares.amounts(total: item.total, pcts: shares.map(\.pct))
                if let i = shares.firstIndex(where: { $0.user_id == user }) {
                    amount = amounts[i]
                    let whose = user == store.me ? "your" : "\(store.name(user))’s"
                    meta = "\(whose) \(Int(shares[i].pct.rounded()))% of \(Rupiah.format(item.total)) · split \(shares.count) ways"
                }
            }
            lines.append(ReviewLine(id: item.id.uuidString, item: item, qty: "\(item.qty)×", name: nameWithOptions(item), meta: meta, metaInk: ink,
                                    amount: amount, flagged: item.flagged_at != nil || soldOut(item)))
        }
        // Shares this member holds in someone else's split.
        for item in store.items where item.owner_id != user {
            guard let sp = store.liveSplit(item), sp.state == "accepted" else { continue }
            let shares = store.shares(sp).sorted { a, _ in a.user_id == item.owner_id }
            guard let i = shares.firstIndex(where: { $0.user_id == user }) else { continue }
            let amounts = Shares.amounts(total: item.total, pcts: shares.map(\.pct))
            lines.append(ReviewLine(id: "\(item.id)-\(user)", item: item, qty: shareGlyph(shares[i].pct), name: "\(item.name) share",
                                    meta: "under \(store.name(item.owner_id))", metaInk: Brand.ink3, amount: amounts[i], flagged: false))
        }
        return lines
    }

    @ViewBuilder func reviewSections(_ g: OrderGroup) -> some View {
        let people = store.activeMembers.filter { !reviewLines($0.user_id).isEmpty }
        reviewSummary(people: people.count)
        ForEach(store.items.filter { soldOut($0) && $0.flagged_at == nil }) { item in soldOutBanner(item) }
        ForEach(people, id: \.user_id) { m in reviewCard(m.user_id) }
    }

    private func reviewSummary(people: Int) -> some View {
        let total = store.subtotal
        let goal = DiscountBar.goal
        let reached = total >= goal
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                StateTag(state: .locked)
                Spacer()
                Text("\(people) \(people == 1 ? "person" : "people") · \(store.items.reduce(0) { $0 + $1.qty }) items")
                    .ui(GFont.manrope(13), Brand.liquorice400)
            }
            Text(Rupiah.format(total)).ui(GFont.roundo(44), Brand.cream)
            Capsule().fill(Brand.ink2).frame(height: 12)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(reached ? Brand.lime : Brand.choc400).frame(width: geo.size.width * min(1, CGFloat(total) / CGFloat(goal)))
                    }
                }
                .clipShape(Capsule())
            HStack(alignment: .top, spacing: 6) {
                if reached { icon("checkmark", 15, Brand.lime, weight: .heavy) }
                Text(reached ? "\(Rupiah.format(total - goal)) past the \(Rupiah.format(goal)) ongkir discount"
                             : "\(Rupiah.format(goal - total)) short of the \(Rupiah.format(goal)) ongkir discount")
                    .ui(GFont.manrope(14, 600), reached ? Brand.lime : Brand.choc100)
            }
        }
        .surface(32, padding: edges(20, 20), fill: Brand.cocoa)
        .accessibilityElement(children: .combine)
    }

    private func soldOutBanner(_ item: Item) -> some View {
        HStack(spacing: 10) {
            icon("exclamationmark.triangle", 18)
            Text("\(item.name) is now sold out on the menu.").ui(GFont.manrope(13, 600)).frame(maxWidth: .infinity, alignment: .leading)
            Button("Ask \(store.name(item.owner_id))") {
                sheet = .requestEdit(RequestSeed(member: item.owner_id, item: item.id, reason: .soldOut))
            }
            .ui(GFont.manrope(13, 700), Brand.caramel)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.choc100))
    }

    private func reviewCard(_ user: UUID) -> some View {
        let lines = reviewLines(user)
        let sub = store.bill.first { $0.user_id == user }?.items ?? lines.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Avatar(name: store.name(user), index: store.colorIndex(user), size: 30, art: store.people[user]?.avatar, bg: store.people[user]?.avatar_bg)
                Text(store.name(user)).ui(GFont.manrope(16, 700)).frame(maxWidth: .infinity, alignment: .leading)
                Text(Rupiah.format(sub)).ui(GFont.roundo(16))
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
            ForEach(lines) { line in
                HStack(spacing: 10) {
                    Text(line.qty).ui(GFont.roundo(14), Brand.caramel).frame(width: 22, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(line.name).ui(GFont.manrope(14, 600))
                        if !line.meta.isEmpty { Text(line.meta).ui(GFont.manrope(12), line.metaInk) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(bareRupiah(line.amount)).ui(GFont.manrope(13, 600))
                    Button {
                        sheet = .requestEdit(RequestSeed(member: line.item.owner_id, item: line.item.id, reason: soldOut(line.item) ? .soldOut : nil))
                    } label: {
                        RoundIcon(fill: Brand.liquorice100) { icon("pencil", 13) }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Ask \(store.name(line.item.owner_id)) to change \(line.item.name)")
                }
                .padding(.vertical, 5)
                .padding(.horizontal, line.flagged ? 6 : 0)
                .background(RoundedRectangle(cornerRadius: 10).fill(line.flagged ? Brand.splitFill : .clear))
                .padding(.horizontal, line.flagged ? -6 : 0)
            }
        }
        .surface(28, padding: edges(14, 16))
    }

    // MARK: 4-7 / 4-8 Edit round (host)

    @ViewBuilder func editsHostSections(_ g: OrderGroup) -> some View {
        let flagged = store.items.filter { $0.flagged_at != nil }
        let editors = store.activeMembers.map(\.user_id).filter { u in flagged.contains { $0.owner_id == u } }
        let allDone = editors.isEmpty
        let lockedAt = times?.locked_at ?? .distantPast
        let edited = store.activeMembers.filter { ($0.done_editing_at ?? .distantPast) > lockedAt }.map(\.user_id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StateTag(state: .edits)
                Spacer()
                Text(Rupiah.format(store.subtotal)).ui(GFont.roundo(18))
            }
            Text(allDone ? "Every edit is done" : "Waiting on \(flagged.count) edit\(flagged.count == 1 ? "" : "s")").ui(GFont.roundo(20))
            Text(allDone ? "Lock the order again, then send it to Atas."
                         : "Everyone else is locked in. When \(names(editors)) \(editors.count == 1 ? "is" : "are") done, lock the order again to continue.")
                .ui(GFont.manrope(13), allDone ? Brand.cocoa : Brand.ink2).lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(allDone ? Brand.lime : Brand.card))
        .overlay { if allDone { RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Brand.limeDeep, lineWidth: 2) } }
        if allDone {
            ForEach(edited, id: \.self) { u in editedCard(u) }
        } else {
            ForEach(editors, id: \.self) { u in editingCard(u) }
            VStack(spacing: 8) {
                ForEach(store.activeMembers.map(\.user_id).filter { u in !editors.contains(u) && !store.items(of: u).isEmpty }, id: \.self) { u in
                    lockedRow(u)
                }
            }
            .opacity(0.6)
        }
    }

    private func names(_ users: [UUID]) -> String {
        let n = users.map { store.name($0) }
        return n.count <= 1 ? (n.first ?? "") : n.dropLast().joined(separator: ", ") + " and " + n.last!
    }

    private func editingCard(_ user: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(name: store.name(user), index: store.colorIndex(user), size: 30, art: store.people[user]?.avatar, bg: store.people[user]?.avatar_bg)
                Text(store.name(user)).ui(GFont.manrope(16, 700)).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) { icon("clock", 13, Brand.editsInk); Text("Editing") }.ui(GFont.manrope(12, 600), Brand.editsInk)
            }
            ForEach(store.items(of: user)) { item in
                if item.flagged_at != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(item.qty)× \(nameWithOptions(item))").ui(GFont.manrope(14, 700))
                            Spacer()
                            Text(Rupiah.format(item.total)).ui(GFont.manrope(13, 600))
                        }
                        if let r = item.flag_reason, !r.isEmpty { Text("“\(r)”").ui(GFont.manrope(13), Brand.ink2) }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.splitFill))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.pink100, lineWidth: 1.5))
                } else {
                    plainLine(item)
                }
            }
            if let phone = store.people[user]?.phone {
                Button { openURL(Links.whatsApp(phone)) } label: {
                    HStack(spacing: 6) { WhatsAppGlyph(size: 14); Text("Message \(store.name(user))") }
                        .ui(GFont.manrope(13, 600))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Brand.lime))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .surface(28, padding: edges(14, 16))
    }

    private func plainLine(_ item: Item) -> some View {
        HStack {
            Text("\(item.qty)× \(nameWithOptions(item))").ui(GFont.manrope(14, 600))
            Spacer()
            Text(Rupiah.format(item.total)).ui(GFont.manrope(13, 600))
        }
        .padding(.vertical, 4)
    }

    private func editedCard(_ user: UUID) -> some View {
        let items = store.items(of: user)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(name: store.name(user), index: store.colorIndex(user), size: 30, art: store.people[user]?.avatar, bg: store.people[user]?.avatar_bg)
                Text(store.name(user)).ui(GFont.manrope(16, 700)).frame(maxWidth: .infinity, alignment: .leading)
                Text(Rupiah.format(items.reduce(0) { $0 + $1.total })).ui(GFont.roundo(16))
            }
            ForEach(items) { plainLine($0) }
        }
        .surface(28, padding: edges(14, 16))
    }

    private func lockedRow(_ user: UUID) -> some View {
        HStack(spacing: 10) {
            Avatar(name: store.name(user), index: store.colorIndex(user), size: 30, art: store.people[user]?.avatar, bg: store.people[user]?.avatar_bg)
            Text(store.name(user)).ui(GFont.manrope(15, 700)).frame(maxWidth: .infinity, alignment: .leading)
            Text(Rupiah.format(store.bill.first { $0.user_id == user }?.items ?? store.items(of: user).reduce(0) { $0 + $1.total }))
                .ui(GFont.roundo(14))
            icon("lock", 14)
        }
        .surface(24, padding: edges(14, 16))
        .accessibilityElement(children: .combine)
    }

    // MARK: 4-9 / 4-10 Edit request (member)

    @ViewBuilder func fixingSections(_ g: OrderGroup) -> some View {
        let mine = store.myItems
        let flagged = mine.filter { $0.flagged_at != nil }
        let swapped = mine.filter { replaced[$0.id] != nil }
        let rest = mine.filter { $0.flagged_at == nil && replaced[$0.id] == nil }
        let n = flagged.count + swapped.count
        VStack(alignment: .leading, spacing: 8) {
            StateTag(state: .edits)
            Text("\(hostFirst) asked you to change \(n <= 1 ? "an item" : "\(n) items")").ui(GFont.roundo(30))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        ForEach(flagged) { flaggedCard(g, $0) }
        ForEach(swapped) { replacedCard($0) }
        ForEach(rest) { item in
            HStack {
                Text("\(item.qty)× \(nameWithOptions(item))").ui(GFont.manrope(14, 600))
                Spacer()
                HStack(spacing: 6) { icon("lock", 13); Text(Rupiah.format(item.total)) }.ui(GFont.manrope(13, 600))
            }
            .surface(24, padding: edges(14, 16))
            .opacity(0.7)
        }
    }

    private func flaggedCard(_ g: OrderGroup, _ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProductPhoto(url: store.products[item.product_id]?.photo, size: 64, fill: soldOut(item) ? Brand.liquorice100 : Brand.choc100)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.qty)× \(nameWithOptions(item))").ui(GFont.manrope(16, 700))
                    Text(Rupiah.format(item.total)).ui(GFont.manrope(13), Brand.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if soldOut(item) { Tag(text: "Sold out", fill: Brand.liquorice100, size: .small) }
            }
            HStack(alignment: .top, spacing: 10) {
                Avatar(name: hostName, index: store.colorIndex(g.host_id), size: 28, art: store.people[g.host_id]?.avatar, bg: store.people[g.host_id]?.avatar_bg)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hostFirst) · \(Wita.string(item.flagged_at ?? Date(), "HH:mm"))").ui(GFont.manrope(12, 600), Brand.ink3)
                    Text(item.flag_reason?.isEmpty == false ? item.flag_reason! : "Please change this item.").ui(GFont.manrope(15, 600))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.splitFill))
            HStack(spacing: 10) {
                Button {
                    replacing = (item, Set(store.myItems.map(\.id)), store.myItems.reduce(0) { $0 + $1.total })
                    sheet = .menu
                } label: { Label("Replace", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(BarPillStyle(kind: .dark, height: 52))
                .layoutPriority(1.3)
                Button {
                    confirm = Confirm(title: "Remove \(item.name)?", message: "It comes out of your order.", button: "Remove") {
                        try await store.remove(item)
                        removedInRound = true
                    }
                } label: { Label("Remove", systemImage: "trash") }
                .buttonStyle(BarPillStyle(kind: .destructive, height: 52))
                .layoutPriority(1)
            }
        }
        .surface(32, padding: edges(18, 18))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Brand.pink100, lineWidth: 2))
    }

    private func replacedCard(_ item: Item) -> some View {
        let r = replaced[item.id]!
        let now = store.myItems.reduce(0) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProductPhoto(url: store.products[item.product_id]?.photo, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.qty)× \(nameWithOptions(item))").ui(GFont.manrope(16, 700))
                    Text("\(Rupiah.format(item.total)) · replaces \(r.oldName)").ui(GFont.manrope(13), Brand.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                icon("checkmark", 15, Brand.cocoa, weight: .heavy).frame(width: 28, height: 28).background(Circle().fill(Brand.lime))
            }
            if r.subtotalBefore != now {
                Text("Your subtotal goes from \(Rupiah.format(r.subtotalBefore)) to \(Rupiah.format(now)).").ui(GFont.manrope(13), Brand.ink2)
            }
        }
        .surface(32, padding: edges(18, 18))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Brand.limeDeep, lineWidth: 2))
    }

    /// After the menu closes on a Replace: the new item takes the flagged one's place (add first, then remove,
    /// because adding needs the flag that lets a member edit during the round).
    func finishReplacing() {
        guard let r = replacing else { return }
        replacing = nil
        Task {
            await store.refresh()
            let added = store.myItems.filter { !r.before.contains($0.id) }
            guard !added.isEmpty else { return }
            let before = replaced.values.first?.subtotalBefore ?? r.subtotal
            await act("Couldn't replace it") {
                try await store.remove(r.item)
                for n in added { replaced[n.id] = Replacement(oldName: r.item.name, oldQty: r.item.qty, oldTotal: r.item.total, subtotalBefore: before) }
            }
        }
    }
}

// MARK: 4-6 Request an edit

/// The host picks a member, one or more of their items and a reason; each item is flagged with `request_edit`
/// and the member gets one notification per item.
struct RequestEditSheet: View {
    var store: GroupStore
    var seed: RequestSeed
    @Environment(\.dismiss) private var dismiss
    @State private var member: UUID?
    @State private var picked: Set<UUID> = []
    @State private var reason: RequestSeed.Reason?
    @State private var text = ""
    @State private var busy = false
    @State private var problem: Problem?
    @FocusState private var typing: Bool

    private var people: [UUID] {
        store.activeMembers.map(\.user_id).filter { $0 != store.group?.host_id && !store.items(of: $0).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Member") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) { ForEach(people, id: \.self) { chip($0) } }
                    }
                    .scrollIndicators(.hidden)
                }
                if let member {
                    section("Item") { itemList(member) }
                }
                section("Reason") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { ForEach(RequestSeed.Reason.allCases, id: \.self) { reasonChip($0) } }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) { reasonChip(.soldOut); reasonChip(.size) }
                            reasonChip(.note)
                        }
                    }
                    TextField("What should they change?", text: $text, axis: .vertical)
                        .focused($typing)
                        .ui(GFont.manrope(16))
                        .lineLimit(2...5)
                        .frame(minHeight: 48, alignment: .topLeading)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.caramel, lineWidth: 2))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .safeAreaInset(edge: .bottom) {
            Button { Task { await send() } } label: {
                Label("Send to \(member.map { store.name($0) } ?? "them")", systemImage: "paperplane")
            }
            .buttonStyle(.pill(.primary))
            .disabled(picked.isEmpty || busy)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .navigationTitle("Request an edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            member = seed.member.flatMap { people.contains($0) ? $0 : nil } ?? people.first
            if let i = seed.item { picked = [i] }
            if let r = seed.reason { choose(r) }
        }
        .problemAlert($problem)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).brand(.label).padding(.leading, 4)
            content()
        }
    }

    private func chip(_ user: UUID) -> some View {
        let on = member == user
        return Button {
            if member != user { member = user; picked = [] }
        } label: {
            HStack(spacing: 6) {
                Avatar(name: store.name(user), index: store.colorIndex(user), size: 24, art: store.people[user]?.avatar, bg: store.people[user]?.avatar_bg)
                Text(store.name(user)).ui(GFont.manrope(14, 600), on ? Brand.cream : Brand.cocoa)
            }
            .padding(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 12))
            .background(Capsule().fill(on ? Brand.cocoa : .white))
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func itemList(_ user: UUID) -> some View {
        let items = store.items(of: user)
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                let asked = item.flagged_at != nil
                let on = picked.contains(item.id)
                Button {
                    if on { picked.remove(item.id) } else { picked.insert(item.id) }
                    if let reason { choose(reason) }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            if on { Circle().fill(Brand.caramel); icon("checkmark", 13, .white, weight: .heavy) }
                            else { Circle().strokeBorder(Brand.liquorice400, lineWidth: 2) }
                        }
                        .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(item.qty)× \(item.name)").ui(GFont.manrope(15, 700))
                            if asked { Text("Already asked").ui(GFont.manrope(12, 600), Brand.ink3) }
                            else if store.products[item.product_id]?.available == false { Text("Sold out on the menu").ui(GFont.manrope(12, 600), Brand.caramel) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Rupiah.format(item.total)).ui(GFont.manrope(13, 600))
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(asked)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
    }

    private func reasonChip(_ r: RequestSeed.Reason) -> some View {
        Button { choose(r) } label: {
            Text(title(r)).ui(GFont.manrope(13, 600))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(reason == r ? Brand.choc100 : .white))
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(reason == r ? .isSelected : [])
    }

    private func title(_ r: RequestSeed.Reason) -> String {
        switch r { case .soldOut: "Sold out today"; case .size: "Pick a size"; case .note: "Check the note" }
    }

    /// A reason chip writes a starting sentence the host can edit.
    private func choose(_ r: RequestSeed.Reason) {
        reason = r
        let names = store.items.filter { picked.contains($0.id) }.map(\.name)
        let what = names.isEmpty ? "it" : names.joined(separator: " and ")
        text = switch r {
        case .soldOut: "\(what) is sold out today, can you swap it?"
        case .size: "Can you pick a size for \(what)?"
        case .note: "Can you check the note on \(what)?"
        }
        text = text.prefix(1).uppercased() + text.dropFirst()
    }

    private func send() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't send the request") {
            for id in picked {
                try await store.rpc("request_edit", ["item": .string(id.uuidString), "reason": .string(text.trimmingCharacters(in: .whitespacesAndNewlines))])
            }
            dismiss()
        }
    }
}
