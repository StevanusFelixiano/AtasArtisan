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
    /// DEBUG `ATASTE_HISTORY=<name part>` opens that order's detail (6-2); `ATASTE_HISTORY=skeleton` holds 6-4.
    @State private var debugPick: HistoryPick?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("History").obText(.display, 40)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .padding(.bottom, loaded && !groups.isEmpty ? 0 : 10)
                    .accessibilityAddTraits(.isHeader)
                if !loaded {
                    ForEach([0.7, 0.55, 0.8, 0.6, 0.75, 0.5], id: \.self) { SkeletonRow(width: $0) }
                        .accessibilityHidden(true)
                } else if groups.isEmpty {
                    empty
                } else {
                    rows
                }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, Brand.s5)
        }
        .screen()
        .navigationTitle("History")
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HistoryPick.self) { HistoryDetailView(id: $0.id) }
        .navigationDestination(item: $debugPick) { HistoryDetailView(id: $0.id) }
        .refreshable { await load() }
        .task(id: app.homeVersion) { await load() }
    }

    // 6-1
    @ViewBuilder private var rows: some View {
        let fills = chipFills
        ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
            if i == 0 || Wita.string(groups[i - 1].delivery_at, "MMMM yyyy") != Wita.string(g.delivery_at, "MMMM yyyy") {
                Text(Wita.string(g.delivery_at, "MMMM")).brand(.label).padding(.horizontal, 4).padding(.top, 10).padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            NavigationLink(value: HistoryPick(id: g.id)) {
                HistoryRow(group: g, meta: meta(g), amount: amount(g), chip: fills[i])
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

    // 6-3
    private var empty: some View {
        VStack(spacing: 0) {
            PaintingFrame(art: "paint-creation", width: 292, height: 170, tilt: -2)
                .accessibilityElement().accessibilityLabel("The Creation of Ataste, a giraffe painting")
                .padding(.top, 30)
            ObCaption(title: "The Creation of Ataste").padding(.top, 32)
            VStack(spacing: 10) {
                Text("No history…yet!").obText(.title2, 28)
                Text("Finished orders land here, ready to reorder in one tap.")
                    .obText(.body, 15, Brand.ink2).lineSpacing(4).frame(maxWidth: 290)
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

    private func load() async {
        if DebugScreens.value("ATASTE_HISTORY") == "skeleton" { return }
        defer {
            if let part = DebugScreens.value("ATASTE_HISTORY"), debugPick == nil,
               let g = groups.first(where: { $0.name.localizedCaseInsensitiveContains(part) }) { debugPick = HistoryPick(id: g.id) }
        }
        groups = (try? await supabase.from("groups").select()
            .in("state", values: ["delivered", "closed", "cancelled"]).order("delivery_at", ascending: false).execute().value) ?? []
        if let me = app.userID {
            let rows: [BillRow] = (try? await supabase.from("group_bill_v").select().eq("user_id", value: me).execute().value) ?? []
            bills = Dictionary(uniqueKeysWithValues: rows.map { ($0.group_id, $0) })
        }
        if !groups.isEmpty {
            struct M: Decodable { var group_id: UUID; var removed_at: Date? }
            struct P: Decodable { var id: UUID; var name: String }
            let members: [M] = (try? await supabase.from("members").select("group_id,removed_at")
                .in("group_id", values: groups.map(\.id)).execute().value) ?? []
            people = members.filter { $0.removed_at == nil }.reduce(into: [:]) { $0[$1.group_id, default: 0] += 1 }
            let hosts: [P] = (try? await supabase.from("profiles").select("id,name")
                .in("id", values: Array(Set(groups.map(\.host_id)))).execute().value) ?? []
            hostNames = Dictionary(hosts.map { ($0.id, $0.name) }) { a, _ in a }
        }
        loaded = true
    }
}

struct HistoryPick: Hashable { var id: UUID }

/// One past order: date chip, name, host · people, my total and the state tag.
private struct HistoryRow: View {
    var group: OrderGroup
    var meta: String
    var amount: String
    var chip: Color

    var body: some View {
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
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
        .opacity(group.state == .cancelled ? 0.65 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the order")
    }
}

/// 6-4: a row-shaped placeholder while History loads.
private struct SkeletonRow: View {
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
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }
}
