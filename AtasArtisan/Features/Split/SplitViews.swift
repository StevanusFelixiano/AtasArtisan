import SwiftUI
import Supabase

/// 4.9 Propose a split. Atas needs one name per item, so the item stays under its owner; shares are custom
/// percentages that must add up to 100%, owner included.
struct SplitProposeView: View {
    var store: GroupStore
    var item: Item
    @Environment(\.dismiss) private var dismiss
    @State private var pcts: [UUID: Double] = [:]
    @State private var busy = false
    @State private var problem: Problem?

    private var people: [UUID] {
        [item.owner_id] + store.activeMembers.map(\.user_id).filter { $0 != item.owner_id }
    }
    private var chosen: [UUID] { people.filter { (pcts[$0] ?? 0) > 0 } }
    private var total: Double { pcts.values.reduce(0, +) }
    private var valid: Bool { (pcts[item.owner_id] ?? 0) > 0 && Shares.isValid(chosen.map { pcts[$0]! }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s4) {
                HStack(spacing: Brand.s3) {
                    Mascot(pose: "pose-splitting", size: 90, fill: Brand.pink100)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Split \(item.name)").brand(.title2)
                        Text("\(Rupiah.format(item.total)) · stays under \(store.name(item.owner_id))'s name for Atas").brand(.callout, Brand.ink2)
                    }
                }
                ForEach(people, id: \.self) { u in
                    let pct = pcts[u] ?? 0
                    VStack(alignment: .leading, spacing: Brand.s2) {
                        HStack {
                            Avatar(name: store.name(u), index: store.colorIndex(u), size: 30, art: store.people[u]?.avatar)
                            Text(store.name(u) + (u == item.owner_id ? " · owner" : "")).brand(.headline)
                            Spacer()
                            Text("\(Int(pct))% · \(Rupiah.format(Int((Double(item.total) * pct / 100).rounded())))").brand(.callout)
                        }
                        Slider(value: Binding(get: { pct }, set: { pcts[u] = ($0 / 5).rounded() * 5 }), in: 0...100, step: 5)
                            .tint(Brand.caramel)
                            .accessibilityLabel("\(store.name(u))'s share")
                    }
                    .card(Brand.rSmall, padding: Brand.s3)
                }
                HStack {
                    Text("Total").brand(.headline)
                    Spacer()
                    Text("\(Int(total))%").brand(.headline, abs(total - 100) < 0.01 ? Brand.cocoa : Brand.destructive)
                }
                if abs(total - 100) >= 0.01 && total > 0 {
                    Text("Shares need to add up to 100%.").brand(.callout, Brand.destructive)
                }
                Button("Split equally between chosen") {
                    let who = chosen.isEmpty ? [item.owner_id] : chosen
                    let each = (100.0 / Double(who.count) * 100).rounded() / 100
                    for u in people { pcts[u] = who.contains(u) ? each : 0 }
                    pcts[item.owner_id] = 100 - each * Double(who.count - 1)
                }
                .buttonStyle(.pill(.secondary, .small))
            }
            .padding(Brand.s4)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            Button(item.owner_id == store.me ? "Invite to share" : "Ask \(store.name(item.owner_id))") { Task { await propose() } }
                .buttonStyle(.pill(.primary)).disabled(!valid || busy)
                .padding(Brand.s4)
        }
        .navigationTitle("Split an item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            if pcts.isEmpty {
                pcts[item.owner_id] = item.owner_id == store.me ? 100 : 50
                if let me = store.me, me != item.owner_id { pcts[me] = 50 }
            }
        }
        .problemAlert($problem)
    }

    private func propose() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't propose the split") {
            let shares: [AnyJSON] = chosen.map { .object(["user": .string($0.uuidString), "pct": .double(pcts[$0]!)]) }
            try await store.rpc("propose_split", ["item": .string(item.id.uuidString), "shares": .array(shares)])
            dismiss()
        }
    }
}

/// "Burnt Cheesecake — under Rani · split 3 ways" with each person's amount, and the answer buttons.
struct SplitSummary: View {
    var store: GroupStore
    var item: Item
    var split: Split
    @State private var problem: Problem?

    var body: some View {
        let shares = store.shares(split).sorted { a, _ in a.user_id == item.owner_id }
        let amounts = Shares.amounts(total: item.total, pcts: shares.map(\.pct))
        let mine = shares.first { $0.user_id == store.me }
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack {
                Image(systemName: "chart.pie.fill").foregroundStyle(Brand.cocoa)
                Text(status(shares)).brand(.label)
            }
            ForEach(Array(shares.enumerated()), id: \.element.user_id) { i, s in
                HStack {
                    Text("\(store.name(s.user_id)) \(Int(s.pct))%").brand(.callout)
                    Spacer()
                    Text(Rupiah.format(amounts[i])).brand(.callout)
                    Image(systemName: s.accepted_at == nil ? "clock" : "checkmark.circle.fill")
                        .foregroundStyle(s.accepted_at == nil ? Brand.ink3 : Color(rgb: 0x5E7A00))
                        .accessibilityLabel(s.accepted_at == nil ? "waiting" : "accepted")
                }
            }
            if split.state == "pending" && item.owner_id == store.me {
                HStack {
                    Button("Accept split") { answer("respond_split", true) }.buttonStyle(.pill(.success, .small))
                    Button("Decline") { answer("respond_split", false) }.buttonStyle(.pill(.secondary, .small))
                }
            } else if split.state == "accepted", let mine, mine.accepted_at == nil {
                HStack {
                    Button("Accept my share") { answer("answer_share", true) }.buttonStyle(.pill(.success, .small))
                    Button("Decline") { answer("answer_share", false) }.buttonStyle(.pill(.secondary, .small))
                }
            }
        }
        .padding(Brand.s3)
        .background(RoundedRectangle(cornerRadius: Brand.rSmall).fill(Brand.pink100.opacity(0.35)))
        .problemAlert($problem)
    }

    private func status(_ shares: [SplitShare]) -> String {
        if split.state == "pending" { return "Split proposed · waiting for \(store.name(item.owner_id))" }
        let waiting = shares.filter { $0.accepted_at == nil }.count
        return waiting == 0 ? "Split \(shares.count) ways" : "Split \(shares.count) ways · \(waiting) to accept"
    }

    private func answer(_ fn: String, _ accept: Bool) {
        Task {
            await attempt($problem, "Couldn't answer") {
                try await store.rpc(fn, ["split": .string(split.id.uuidString), "accept": .bool(accept)])
            }
        }
    }
}
