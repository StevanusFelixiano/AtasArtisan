import SwiftUI
import Supabase

/// An item is shared in twelfths ("slices"); the server stores percentages with two decimals that must add up to
/// exactly 100, so every share but the owner's is rounded to 0.01% and the owner (first) takes the rest.
enum Slices {
    static let total = 12

    static func of(_ pct: Double) -> Int { Int((pct * Double(total) / 100).rounded()) }

    /// Hundredths of a percent per person, owner first.
    static func hundredths(_ slices: [Int]) -> [Int] {
        guard !slices.isEmpty else { return [] }
        var out = slices.map { Int((Double($0) * 10_000 / Double(total)).rounded()) }
        out[0] = 10_000 - out.dropFirst().reduce(0, +)
        return out
    }

    /// `n` people, owner first: equal slices, the owner keeps the remainder.
    static func even(_ n: Int) -> [Int] {
        guard n > 0 else { return [] }
        var out = Array(repeating: total / n, count: n)
        out[0] += total % n
        return out
    }

    /// "50%", "16.7%".
    static func pctText(_ pct: Double) -> String {
        let r = (pct * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r))%" : String(format: "%.1f%%", r)
    }

    static func label(_ n: Int) -> String { n == 1 ? "1 slice" : "\(n) slices" }

    /// Segment colours of the shares bar, by position.
    static let colors: [Color] = [Brand.choc400, Brand.lime, Brand.pink100, Brand.choc100, Brand.liquorice400, Brand.limeDeep]
}

/// 4.9 Propose a split (4-1, 4-1e). Atas needs one name per item, so the item stays under its owner; the people
/// sharing it each take a number of slices out of 12, owner included.
struct SplitProposeView: View {
    var store: GroupStore
    var item: Item
    @Environment(\.closeSheet) private var close
    @State private var chosen: [UUID] = []
    @State private var slices: [UUID: Int] = [:]
    @State private var busy = false
    @State private var problem: Problem?
    /// Taps on the owner's chip (it shakes) and on a stepper that can't go further (the total line shakes).
    @State private var ownerTaps = 0
    @State private var stuck = 0
    @State private var evens = 0
    /// The rows' count before this change, so an added row opens and a removed one folds.
    @State private var rowCount: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Owner first, then me, then everyone else in join order.
    private var people: [UUID] {
        let rest = store.activeMembers.map(\.user_id).filter { $0 != item.owner_id && $0 != store.me }
        return [item.owner_id] + (store.me.map { $0 == item.owner_id ? [] : [$0] } ?? []) + rest
    }
    private var sharing: [UUID] { people.filter { chosen.contains($0) } }
    private var allocated: Int { sharing.reduce(0) { $0 + (slices[$1] ?? 0) } }
    private var valid: Bool { sharing.count >= 2 && allocated == Slices.total }
    private var mineToAsk: Bool { item.owner_id != store.me }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                itemCard
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who\u{2019}s sharing").brand(.label).padding(.leading, 4)
                    FlowRow(spacing: 8) { ForEach(people, id: \.self) { chip($0) } }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Shares \u{00B7} in slices of \(Slices.total)").brand(.label)
                        Spacer()
                        Button("Split evenly") { evens += 1; splitEvenly() }
                            .font(MenuFont.manrope(12, 600)).foregroundStyle(Brand.caramel)
                            .disabled(sharing.count < 2)
                    }
                    .padding(.horizontal, 4)
                    // Every candidate keeps a segment (0 wide when not sharing), so a new one grows from its place.
                    SharesBar(slices: people.map { chosen.contains($0) ? slices[$0] ?? 0 : 0 }, height: 16)
                    rows
                    status
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await propose() } } label: {
                Label(mineToAsk ? "Send to \(store.name(item.owner_id)) for approval" : "Invite to share", systemImage: "chart.pie")
            }
            .buttonStyle(.pill(.primary))
            .disabled(!valid || busy)
        }
        .onAppear {
            guard chosen.isEmpty else { return }
            chosen = [item.owner_id] + (mineToAsk ? store.me.map { [$0] } ?? [] : [])
            splitEvenly()
            // DEBUG screenshot hook (nil in release): ATASTE_SPLIT = three (4-1, 6/3/3) | short (4-1e, one slice missing).
            if let mode = DebugScreens.value("ATASTE_SPLIT"), mode == "three" || mode == "short" {
                if let third = people.first(where: { !chosen.contains($0) }) { chosen.append(third) }
                for (u, n) in zip(sharing, [6, 3, 3]) { slices[u] = n }
                if mode == "short", sharing.count > 1 { slices[sharing[1]] = 2 }
            }
        }
        .problemAlert($problem)
        .sensoryFeedback(.selection, trigger: chosen) { old, _ in !old.isEmpty }
        .sensoryFeedback(.selection, trigger: evens)
        .sensoryFeedback(Haptic.blocked, trigger: ownerTaps)
        .sensoryFeedback(Haptic.blocked, trigger: stuck)
    }

    private var itemCard: some View {
        HStack(spacing: 12) {
            ProductPhoto(url: store.products[item.product_id]?.photo, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.qty > 1 ? "\(item.qty)\u{00D7} \(item.name)" : item.name).font(MenuFont.manrope(16, 700)).foregroundStyle(Brand.cocoa)
                Text("\(Rupiah.format(item.total)) \u{00B7} under \(mineToAsk ? store.name(item.owner_id) + "\u{2019}s" : "your") name")
                    .font(MenuFont.manrope(13)).foregroundStyle(Brand.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }

    private func chip(_ u: UUID) -> some View {
        let on = chosen.contains(u)
        let locked = u == item.owner_id
        return Button {
            guard !locked else { ownerTaps += 1; return }
            if on { chosen.removeAll { $0 == u } } else { chosen.append(u) }
            splitEvenly()
        } label: {
            HStack(spacing: 6) {
                Avatar(name: store.name(u), index: store.colorIndex(u), size: 24, art: store.people[u]?.avatar, bg: store.people[u]?.avatar_bg)
                Text(u == store.me ? "You" : store.name(u)).font(MenuFont.manrope(14, 600)).lineLimit(1)
            }
            .foregroundStyle(on ? Brand.cream : Brand.cocoa)
            .padding(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 12))
            .background(Capsule().fill(on ? Brand.cocoa : .white))
            .overlay(Capsule().strokeBorder(Brand.liquorice400, lineWidth: on ? 0 : 1.5))
            .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick, value: on)
            .contentShape(Capsule())
            .shake(locked && !reduceMotion ? ownerTaps : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(u == store.me ? "You" : store.name(u))
        .accessibilityValue(locked ? "Owner, always sharing" : on ? "Sharing" : "Not sharing")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(sharing.enumerated()), id: \.element) { i, u in
                let n = slices[u] ?? 0
                let line = "\(Slices.pctText(Double(n) * 100 / Double(Slices.total))) \u{00B7} \(Rupiah.format(amount(i)))"
                VStack(spacing: 0) {
                    if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                    HStack(spacing: 10) {
                        Avatar(name: store.name(u), index: store.colorIndex(u), size: 32, art: store.people[u]?.avatar, bg: store.people[u]?.avatar_bg)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(u == store.me ? "You" : store.name(u)).font(MenuFont.manrope(15, 700)).foregroundStyle(Brand.cocoa)
                            Text(line)
                                .font(MenuFont.manrope(12)).foregroundStyle(Brand.ink2)
                                .contentTransition(reduceMotion ? .opacity : .numericText())
                                .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: line)
                        }
                        Spacer(minLength: 4)
                        PillStepper(value: Slices.label(n), fill: Brand.cream, gap: 10, pad: 3, minWidth: 52, countSize: 15,
                                    canMinus: n > 1, canPlus: allocated < Slices.total,
                                    minusLabel: "One slice less for \(store.name(u))", plusLabel: "One slice more for \(store.name(u))",
                                    minus: { slices[u] = max(1, n - 1) }, plus: { slices[u] = n + 1 }, blocked: { stuck += 1 })
                    }
                    .padding(.vertical, 11)
                }
                .transition(.itemRow)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
        .clipShape(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous))
        // An added row opens on Motion.settle after 0.04 s; a removed one folds on Motion.leave. Reduce Motion snaps.
        .animation(reduceMotion ? nil : sharing.count >= (rowCount ?? sharing.count) ? Motion.settle.delay(SplitMotion.rowDelay) : Motion.leave,
                   value: sharing)
        .onChange(of: sharing, initial: true) { rowCount = sharing.count }
    }

    /// The total line. It rolls to each new text, and shakes when a stepper can't go further.
    private var status: some View {
        let left = Slices.total - allocated
        let key = valid ? "done" : sharing.count < 2 ? "pick" : "left \(left)"
        return RollText(key: key) {
            if valid {
                Label { Text("\(Slices.total) of \(Slices.total) slices \u{00B7} 100%") } icon: { Image(systemName: "checkmark") }
                    .labelStyle(StatusLabel(icon: 12))
                    .font(MenuFont.manrope(13, 600)).foregroundStyle(Brand.limeInk)
                    .padding(.leading, 4)
            } else if sharing.count < 2 {
                Text("Pick who\u{2019}s sharing it with \(mineToAsk ? store.name(item.owner_id) : "you").")
                    .font(MenuFont.manrope(13, 600)).foregroundStyle(Brand.ink3)
                    .padding(.leading, 4)
            } else {
                let text = "\(allocated) of \(Slices.total) slices. Give the last \(left == 1 ? "slice" : "\(left) slices") to someone so the shares add up to 100%."
                Label { Text(text) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .labelStyle(StatusLabel(icon: 15))
                    .font(MenuFont.manrope(14, 600)).lineSpacing(3).foregroundStyle(Brand.destructive)
                    .padding(.horizontal, 4)
            }
        }
        .shake(reduceMotion ? 0 : stuck)
    }

    /// What one row costs: the server's rounding (owner absorbs it) once the shares are whole, plain thirds before.
    private func amount(_ i: Int) -> Int {
        let n = sharing.map { slices[$0] ?? 0 }
        if allocated == Slices.total {
            return Shares.amounts(total: item.total, pcts: Slices.hundredths(n).map { Double($0) / 100 })[i]
        }
        return Int((Double(item.total) * Double(n[i]) / Double(Slices.total)).rounded())
    }

    private func splitEvenly() {
        let even = Slices.even(sharing.count)
        for (i, u) in sharing.enumerated() { slices[u] = even[i] }
    }

    private func propose() async {
        busy = true
        defer { busy = false }
        let who = sharing
        let pcts = Slices.hundredths(who.map { slices[$0] ?? 0 })
        await attempt($problem, "Couldn't propose the split") {
            let shares: [AnyJSON] = zip(who, pcts).map { u, h in .object(["user": .string(u.uuidString), "pct": .double(Double(h) / 100)]) }
            try await store.rpc("propose_split", ["item": .string(item.id.uuidString), "shares": .array(shares)])
            close?()
        }
    }
}

/// Icon at the first line, 6–8 pt before the text.
private struct StatusLabel: LabelStyle {
    var icon: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: icon > 13 ? 8 : 6) {
            configuration.icon.font(.system(size: icon, weight: .bold))
            configuration.title
        }
    }
}

/// The shares bar: one segment per person in slice proportion (each its width minus a 2 pt gap on its trailing side),
/// in member order; slices nobody has yet are striped. A share that changes moves its segment's edges on
/// `Motion.doughTrail` and its neighbours give way on the same spring (Reduce Motion: `Motion.Reduced.fill`). A 0
/// entry keeps its place at zero width, so a person joining the split grows from there.
struct SharesBar: View {
    var slices: [Int]
    var height: CGFloat = 16
    /// Grey everyone but this index and outline it (the invitee's view).
    var highlight: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let used = slices.reduce(0, +)
            let unit = g.size.width / CGFloat(Slices.total)
            let last = slices.lastIndex { $0 > 0 }
            ZStack(alignment: .leading) {
                if used < Slices.total { Stripes() }
                ForEach(slices.indices, id: \.self) { i in
                    let n = slices[i]
                    let before = slices[..<i].reduce(0, +)
                    // Colours by position among the people sharing (the app's split palette).
                    let place = slices[..<i].filter { $0 > 0 }.count
                    let mine = highlight == i
                    let gap = i == last && used == Slices.total ? 0 : SplitMotion.segmentGap
                    Rectangle()
                        .fill(highlight == nil ? Slices.colors[place % Slices.colors.count] : mine ? Brand.pink100 : Brand.liquorice100)
                        .overlay { if mine { UnevenRoundedRectangle(topLeadingRadius: before == 0 ? height : 0, bottomLeadingRadius: before == 0 ? height : 0,
                                                                     bottomTrailingRadius: i == last ? height : 0, topTrailingRadius: i == last ? height : 0)
                            .strokeBorder(Brand.cocoa, lineWidth: 2) } }
                        .frame(width: max(0, unit * CGFloat(n) - gap))
                        .offset(x: unit * CGFloat(before))
                }
            }
            .frame(width: g.size.width, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(height: height)
        .animation(reduceMotion ? Motion.Reduced.fill : Motion.doughTrail, value: slices)
        .accessibilityHidden(true)
    }
}

/// 135° liquorice and white stripes, 5 pt each (the unallocated part of the bar).
private struct Stripes: View {
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

/// How a live split reads under its item in the group, and the way into answering it: the owner reviews a
/// proposal (4-2), an invitee accepts their share (4-3).
struct SplitSummary: View {
    var store: GroupStore
    var item: Item
    var split: Split
    @State private var answering = false

    var body: some View {
        let shares = ordered
        let amounts = Shares.amounts(total: item.total, pcts: shares.map(\.pct))
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.cocoa)
                Text(status(shares)).font(MenuFont.manrope(13)).foregroundStyle(Brand.ink2)
            }
            ForEach(Array(shares.enumerated()), id: \.element.user_id) { i, s in
                HStack {
                    Text("\(s.user_id == store.me ? "You" : store.name(s.user_id)) \u{00B7} \(Slices.label(Slices.of(s.pct)))").font(MenuFont.manrope(13, 600))
                    Spacer()
                    Text(Rupiah.format(amounts[i])).font(MenuFont.manrope(13, 600))
                    Image(systemName: s.accepted_at == nil ? "clock" : "checkmark.circle.fill")
                        .foregroundStyle(s.accepted_at == nil ? Brand.ink3 : Brand.limeInk)
                        .accessibilityLabel(s.accepted_at == nil ? "waiting" : "accepted")
                }
                .foregroundStyle(Brand.cocoa)
            }
            if let action = actionTitle {
                Button(action) { answering = true }.buttonStyle(.pill(.primary, .small))
            }
        }
        .padding(Brand.s3)
        .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.splitFill))
        .sheet(isPresented: $answering) {
            NavigationStack {
                if split.state == "pending" { SplitReviewView(store: store, item: item, split: split) }
                else { SplitInviteView(store: store, item: item, split: split) }
            }
        }
        .task {
            // DEBUG screenshot hook (nil in release): ATASTE_SPLIT=review opens the answer screen when one is due.
            if DebugScreens.value("ATASTE_SPLIT") == "review", actionTitle != nil { answering = true }
        }
    }

    private var ordered: [SplitShare] {
        store.shares(split).sorted { a, b in a.user_id == item.owner_id && b.user_id != item.owner_id }
    }

    private var actionTitle: String? {
        if split.state == "pending" && item.owner_id == store.me { return "Review split" }
        if split.state == "accepted", let mine = ordered.first(where: { $0.user_id == store.me }), mine.accepted_at == nil { return "See your share" }
        return nil
    }

    private func status(_ shares: [SplitShare]) -> String {
        if split.state == "pending" { return "\(store.name(split.proposer_id)) proposed \u{00B7} waiting for \(store.name(item.owner_id))" }
        let waiting = shares.filter { $0.accepted_at == nil }.count
        return "Under \(store.name(item.owner_id)) \u{00B7} split \(shares.count) ways" + (waiting == 0 ? "" : " \u{00B7} \(waiting) to go")
    }
}
