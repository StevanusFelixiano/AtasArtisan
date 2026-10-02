import SwiftUI
import Supabase

/// 4.15 Past orders (6-1), empty (6-3) and loading (6-4). Rows are grouped by delivery month; opening one shows
/// its detail (6-2).
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var groups: [OrderGroup] = []
    @State private var bills: [UUID: BillRow] = [:]
    @State private var hostNames: [UUID: String] = [:]
    @State private var people: [UUID: Int] = [:]
    @State private var loaded = false
    /// Skeleton rows only when the load is slow, then the rows arrive over them (Motion board 14).
    @State private var gate = SkeletonGate()
    /// The arrival has played; skeleton rows the list didn't fill are gone.
    @State private var arrived = false
    @State private var titleHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// DEBUG `ATASTE_HISTORY=<name part>` opens that order's detail (6-2); `ATASTE_HISTORY=skeleton` holds 6-4.
    @State private var debugPick: HistoryPick?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("History").obText(.display, 40)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .padding(.bottom, loaded && !groups.isEmpty ? 0 : 10)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height + 10 } action: { titleHeight = $0 }
                    .staysPutOnPull()
                    .accessibilityAddTraits(.isHeader)
                if !gate.revealed {
                    if gate.skeleton {
                        ForEach(Self.bones, id: \.self) { SkeletonRow(width: $0) }
                            .accessibilityHidden(true)
                    }
                } else if groups.isEmpty {
                    empty.modifier(Arrival(animate: arriving))
                } else {
                    rows
                    // Skeleton rows the list didn't fill fade out where they were.
                    if arriving, groups.count < Self.bones.count {
                        ForEach(groups.count..<Self.bones.count, id: \.self) { i in
                            SkeletonRow(width: Self.bones[i]).modifier(Leaving(index: i)).accessibilityHidden(true)
                        }
                    }
                }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, Brand.s5)
        }
        .pullToRefresh(below: titleHeight) { await load() }
        .scrollsToTopOnRetap()
        .screen()
        .navigationTitle("History")
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HistoryPick.self) { HistoryDetailView(id: $0.id) }
        .navigationDestination(item: $debugPick) { HistoryDetailView(id: $0.id) }
        .task(id: app.homeVersion) { await gate.load { _ = await load() } }
        .task(id: gate.revealed) {
            guard gate.revealed else { return }
            try? await Task.sleep(for: .seconds(SkeletonMotion.maxStagger + 0.3))
            arrived = true
        }
    }

    /// The first rows are arriving over the skeleton.
    private var arriving: Bool { gate.animated && !arrived }

    /// 6-4's skeleton rows: the width of each one's name line.
    private static let bones: [CGFloat] = [0.7, 0.55, 0.8, 0.6, 0.75, 0.5]

    // 6-1
    @ViewBuilder private var rows: some View {
        let fills = chipFills
        ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
            if i == 0 || Wita.string(groups[i - 1].delivery_at, "MMMM yyyy") != Wita.string(g.delivery_at, "MMMM yyyy") {
                MonthLabel(text: Wita.string(g.delivery_at, "MMMM"), index: i, animate: arriving)
            }
            NavigationLink(value: HistoryPick(id: g.id)) {
                HistoryRow(group: g, meta: meta(g), amount: amount(g), chip: fills[i], index: i,
                           bone: arriving && i < Self.bones.count ? Self.bones[i] : nil)
            }
            .buttonStyle(.plain)
        }
    }

    /// Date chips cycle choc-100, lime, pink-100 down the list; a cancelled order's chip is liquorice-100.
    private var chipFills: [Color] {
        let cycle = [Brand.choc100, Brand.lime, Brand.pink100]
        var n = 0
        return groups.map { g in
            if g.state == .cancelled { return Brand.liquorice100 }
            defer { n += 1 }
            return cycle[n % cycle.count]
        }
    }

    // 6-3. Its first view this session plays the empty-state entrance (Motion board 22); later views are still.
    private var empty: some View {
        VStack(spacing: 0) {
            PaintingFrame(art: "paint-creation", width: 292, height: 170)
                .emptyIntro(.painting, id: "history")
                .accessibilityElement().accessibilityLabel("The Creation of Ataste, a giraffe painting")
                .padding(.top, 30)
            ObCaption(title: "The Creation of Ataste").padding(.top, 32)
                .emptyIntro(.caption, id: "history")
            VStack(spacing: 10) {
                Text("No history…yet!").obText(.title2, 28)
                    .emptyIntro(.headline, id: "history")
                Text("Finished orders land here, ready to reorder in one tap.")
                    .obText(.body, 15, Brand.ink2).lineSpacing(4).frame(maxWidth: 290)
                    .emptyIntro(.body, id: "history")
            }
            .multilineTextAlignment(.center)
            .padding(.top, 30)
        }
        .frame(maxWidth: .infinity)
    }

    private func meta(_ g: OrderGroup) -> String {
        if g.personal { return "Just me" }
        let n = people[g.id] ?? 1
        let count = "\(n) \(n == 1 ? "person" : "people")"
        if g.host_id == app.userID { return "You hosted · \(count)" }
        return "\(hostNames[g.host_id] ?? "Someone") · \(count)"
    }

    private func amount(_ g: OrderGroup) -> String {
        guard g.state != .cancelled, let b = bills[g.id], b.total > 0 else { return "—" }
        return Rupiah.format(b.total)
    }

    /// Loads past orders; says whether it worked. A failed load keeps what is shown. After the first load, new rows
    /// open on `Motion.settle` as a pull to refresh returns (0.2 s after the reply).
    private func load() async -> Bool {
        // Holds the skeleton (6-4) for screenshots.
        if DebugScreens.value("ATASTE_HISTORY") == "skeleton" { try? await Task.sleep(for: .seconds(3600)); return true }
        defer {
            if let part = DebugScreens.value("ATASTE_HISTORY"), debugPick == nil,
               let g = groups.first(where: { $0.name.localizedCaseInsensitiveContains(part) }) { debugPick = HistoryPick(id: g.id) }
        }
        let fetched: [OrderGroup]
        do {
            fetched = try await supabase.from("groups").select()
                .in("state", values: ["delivered", "closed", "cancelled"]).order("delivery_at", ascending: false).execute().value
        } catch {
            loaded = true
            return isCancellation(error)
        }
        if let me = app.userID {
            let rows: [BillRow] = (try? await supabase.from("group_bill_v").select().eq("user_id", value: me).execute().value) ?? []
            bills = Dictionary(uniqueKeysWithValues: rows.map { ($0.group_id, $0) })
        }
        if !fetched.isEmpty {
            struct M: Decodable { var group_id: UUID; var removed_at: Date? }
            struct P: Decodable { var id: UUID; var name: String }
            let members: [M] = (try? await supabase.from("members").select("group_id,removed_at")
                .in("group_id", values: fetched.map(\.id)).execute().value) ?? []
            people = members.filter { $0.removed_at == nil }.reduce(into: [:]) { $0[$1.group_id, default: 0] += 1 }
            let hosts: [P] = (try? await supabase.from("profiles").select("id,name")
                .in("id", values: Array(Set(fetched.map(\.host_id)))).execute().value) ?? []
            hostNames = Dictionary(hosts.map { ($0.id, $0.name) }) { a, _ in a }
        }
        if loaded {
            withAnimation((reduceMotion ? Motion.Reduced.fade : Motion.settle).delay(RefreshMotion.returnDelay)) { groups = fetched }
        } else {
            groups = fetched
        }
        loaded = true
        return true
    }
}

struct HistoryPick: Hashable { var id: UUID }

/// "MAY": 30 pt with its 12 pt top padding. After a skeleton it opens 0 → 30 on `Motion.settle` with its row; Reduce
/// Motion snaps it open.
private struct MonthLabel: View {
    var text: String
    var index: Int
    var animate: Bool
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text).brand(.label).padding(.horizontal, 4).padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .frame(height: open || !animate ? SkeletonMotion.monthLabelHeight : 0, alignment: .bottom)
            .clipped()
            .animation(reduceMotion ? nil : Motion.settle.delay(SkeletonGate.delay(index)), value: open)
            .accessibilityAddTraits(.isHeader)
            .onAppear { if animate { open = true } }
    }
}

/// A skeleton row with no row to turn into: it fades out in place, on its row's stagger.
private struct Leaving: ViewModifier {
    var index: Int
    @State private var gone = false
    func body(content: Content) -> some View {
        content.opacity(gone ? 0 : 1)
            .animation(Motion.fadeOut.delay(SkeletonGate.delay(index)), value: gone)
            .onAppear { gone = true }
    }
}

/// One past order: date chip, name, host · people, my total and the state tag. After a skeleton the row arrives in
/// the skeleton's card: the placeholders fade out as the content rises 6 pt into place.
private struct HistoryRow: View {
    var group: OrderGroup
    var meta: String
    var amount: String
    var chip: Color
    var index = 0
    /// The skeleton row this one replaces (its name line's width), while the rows arrive.
    var bone: CGFloat?
    @State private var boneGone = false

    var body: some View {
        ZStack {
            if let bone {
                SkeletonLines(width: bone)
                    .opacity(boneGone ? 0 : 1)
                    .animation(Motion.fadeOut.delay(SkeletonGate.delay(index)), value: boneGone)
                    .onAppear { boneGone = true }
            }
            content.modifier(Arrival(index: index, animate: bone != nil))
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
        .opacity(group.state == .cancelled ? 0.65 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the order")
    }

    private var content: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(Wita.string(group.delivery_at, "dd")).obText(.display, 17)
                Text(Wita.string(group.delivery_at, "MMM").uppercased()).obText(.label, 9, weight: 600, tracking: 0.04)
            }
            .frame(width: 46, height: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(chip))
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).obText(.headline, 15).lineLimit(1)
                Text(meta).obText(.footnote, 12, Brand.ink3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(amount).obText(.display, 15)
                StateTag(state: group.state, size: .small)
            }
        }
    }
}

/// 6-4: a row-shaped placeholder while History loads.
private struct SkeletonRow: View {
    var width: CGFloat
    var body: some View {
        SkeletonLines(width: width)
            .padding(.horizontal, Brand.s4)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }
}

/// The skeleton's placeholders (#EDE2E4, still): a 46 pt tile, a 14 pt line, a 12 pt line at 40 %, a 64 × 16 block.
private struct SkeletonLines: View {
    var width: CGFloat
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.liquorice100).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: Brand.s2) {
                GeometryReader { g in
                    VStack(alignment: .leading, spacing: Brand.s2) {
                        Capsule().fill(Brand.liquorice100).frame(width: g.size.width * width, height: 14)
                        Capsule().fill(Brand.liquorice100).frame(width: g.size.width * 0.4, height: 12)
                    }
                }
                .frame(height: 34)
            }
            Capsule().fill(Brand.liquorice100).frame(width: 64, height: 16)
        }
    }
}
