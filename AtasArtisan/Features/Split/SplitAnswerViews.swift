import SwiftUI
import Supabase

/// 4-2 Owner review: someone proposed splitting my item. The Creation of Ataste, who takes how many slices,
/// and Decline / Accept split.
struct SplitReviewView: View {
    var store: GroupStore
    var item: Item
    var split: Split
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var problem: Problem?

    var body: some View {
        let shares = SplitAnswer.ordered(store, item, split)
        ScrollView {
            VStack(spacing: 0) {
                PaintingFrame(art: "paint-creation", width: 288, height: 166, tilt: 1.5)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(store.name(split.proposer_id)) proposed a split").brand(.label, Brand.caramel)
                        Text("Share your \(item.name)?").font(MenuFont.roundo(28)).foregroundStyle(Brand.cocoa)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.horizontal, 4)
                    SplitAnswer.rows(store, item, shares)
                    Text("It stays under your name on the Atas order. Each person pays their share on their own bill.")
                        .font(MenuFont.manrope(13)).lineSpacing(3).foregroundStyle(Brand.ink2)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 36)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            SplitAnswer.buttons(no: "Decline", yes: "Accept split", yesIcon: "checkmark", busy: busy) {
                answer(false)
            } yes: { answer(true) }
        }
        .navigationTitle("Split request")
        .toolbar(removing: .title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.tint(Brand.cocoa) } }
        .problemAlert($problem)
    }

    private func answer(_ accept: Bool) {
        Task {
            busy = true
            defer { busy = false }
            await attempt($problem, "Couldn't answer") {
                try await store.rpc("respond_split", ["split": .string(split.id.uuidString), "accept": .bool(accept)])
                dismiss()
            }
        }
    }
}

/// 4-3 Invitee accept: the owner agreed to a split and I'm asked to take my share.
struct SplitInviteView: View {
    var store: GroupStore
    var item: Item
    var split: Split
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var confirmNo = false
    @State private var problem: Problem?

    var body: some View {
        let shares = SplitAnswer.ordered(store, item, split)
        let amounts = Shares.amounts(total: item.total, pcts: shares.map(\.pct))
        let me = shares.firstIndex { $0.user_id == store.me }
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Mascot(pose: "pose-splitting", size: 170, fill: Brand.pink100)
                    Text("\(store.name(split.proposer_id)) invited you to share").brand(.label, Brand.caramel)
                    Text(item.name).font(MenuFont.roundo(28)).foregroundStyle(Brand.cocoa).accessibilityAddTraits(.isHeader)
                    Text("Under \(store.name(item.owner_id)) \u{00B7} split \(shares.count) ways").font(MenuFont.manrope(14)).foregroundStyle(Brand.ink2)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 24)
                if let me {
                    let n = Slices.of(shares[me].pct)
                    VStack(spacing: 12) {
                        Text("Your share").brand(.label)
                        Text(Rupiah.format(amounts[me])).font(MenuFont.roundo(48)).foregroundStyle(Brand.cocoa)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text("\(n) of \(Slices.total) slices \u{00B7} \(Slices.pctText(shares[me].pct))")
                            .font(MenuFont.manrope(14, 600)).foregroundStyle(Brand.ink2)
                        SharesBar(slices: shares.map { Slices.of($0.pct) }, height: 12, highlight: me)
                        HStack(spacing: 0) {
                            ForEach(Array(shares.enumerated()), id: \.element.user_id) { i, s in
                                if i > 0 { Spacer(minLength: 6) }
                                let mine = s.user_id == store.me
                                Text(mine ? "You \(Slices.of(s.pct))"
                                          : "\(store.name(s.user_id)) \(Slices.of(s.pct)) \u{00B7} \(s.accepted_at == nil ? "waiting" : "accepted")")
                                    .font(MenuFont.manrope(12, mine ? 700 : 500))
                                    .foregroundStyle(mine ? Brand.cocoa : Brand.ink3)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
                    .padding(.top, 48)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            SplitAnswer.buttons(no: "No thanks", yes: "I\u{2019}m in", yesIcon: nil, busy: busy) {
                confirmNo = true
            } yes: { answer(true) }
        }
        .navigationTitle("Share an item")
        .toolbar(removing: .title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.tint(Brand.cocoa) } }
        .alert("Say no to this share?", isPresented: $confirmNo) {
            Button("No thanks", role: .destructive) { answer(false) }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The split is called off and \(item.name) stays whole on \(store.name(item.owner_id))\u{2019}s bill.")
        }
        .problemAlert($problem)
    }

    private func answer(_ accept: Bool) {
        Task {
            busy = true
            defer { busy = false }
            await attempt($problem, "Couldn't answer") {
                try await store.rpc("answer_share", ["split": .string(split.id.uuidString), "accept": .bool(accept)])
                dismiss()
            }
        }
    }
}

/// What the two answer screens share.
enum SplitAnswer {
    /// Owner first, then the shares as stored.
    static func ordered(_ store: GroupStore, _ item: Item, _ split: Split) -> [SplitShare] {
        store.shares(split).sorted { a, b in a.user_id == item.owner_id && b.user_id != item.owner_id }
    }

    /// White card: avatar, name ("You"), "6 of 12 slices · 50%", amount.
    @MainActor static func rows(_ store: GroupStore, _ item: Item, _ shares: [SplitShare]) -> some View {
        let amounts = Shares.amounts(total: item.total, pcts: shares.map(\.pct))
        return VStack(spacing: 0) {
            ForEach(Array(shares.enumerated()), id: \.element.user_id) { i, s in
                HStack(spacing: 10) {
                    Avatar(name: store.name(s.user_id), index: store.colorIndex(s.user_id), size: 34, art: store.people[s.user_id]?.avatar, bg: store.people[s.user_id]?.avatar_bg)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.user_id == store.me ? "You" : store.name(s.user_id)).font(MenuFont.manrope(15, 700))
                        Text("\(Slices.of(s.pct)) of \(Slices.total) slices \u{00B7} \(Slices.pctText(s.pct))")
                            .font(MenuFont.manrope(12)).foregroundStyle(Brand.ink2)
                    }
                    Spacer(minLength: 4)
                    Text(Rupiah.format(amounts[i])).font(MenuFont.roundo(16))
                }
                .foregroundStyle(Brand.cocoa)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                if i < shares.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
    }

    /// Cream "no" pill and caramel "yes" pill, 1 : 1.4.
    @MainActor static func buttons(no: String, yes: String, yesIcon: String?, busy: Bool,
                                   no noAction: @escaping () -> Void, yes yesAction: @escaping () -> Void) -> some View {
        GeometryReader { g in
            HStack(spacing: 10) {
                Button(no, action: noAction).buttonStyle(.pill(.secondary)).frame(width: (g.size.width - 10) / 2.4)
                Button(action: yesAction) {
                    if let yesIcon { Label(yes, systemImage: yesIcon) } else { Text(yes) }
                }
                .buttonStyle(.pill(.primary))
            }
            .disabled(busy)
        }
        .frame(height: 60)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
