import SwiftUI
import Supabase

// Pay first or order first (Testing Fixes G2) and closing once everyone has paid (H). `groups.state` keeps its eight
// values; pay first's phases come from `bill_final_at`, `ongkir_asked_at` and `ongkir_set_at`, and who owes what from
// `group_bill_v` (backend contract §6). Order first keeps its steps; pay first adds Ask Atas for ongkir (under
// Rp 200.000), Bills final and Everyone pays before Send, and the bottom bar carries the current step's action.

/// "How does everyone pay?" (G-1), on Create group and Edit delivery details.
enum PayRuleCopy {
    static let orderFirst = "Send the order to Atas first. Everyone pays once Atas confirms the ongkir."
    static let payFirst = "Everyone pays you before you send the order. Under Rp 200.000 you ask Atas for the ongkir first."
    static let footnote = "You can change this until the order locks. Members see it on the invite."
}

/// Pay first while the order is locked: asking Atas for the ongkir, then collecting payments before sending.
enum PayPhase {
    case asking, collecting
    var title: String { self == .asking ? "Asking Atas" : "Collecting" }
}

extension OrderGroup {
    var billFinal: Bool { bill_final_at != nil }

    var payPhase: PayPhase? {
        guard payFirst, state == .locked else { return nil }
        return billFinal ? .collecting : .asking
    }
}

extension BillRow {
    var isFinal: Bool { is_final ?? (bill_total != nil) }
    /// Still to pay: `owed` once final (a bill re-frozen higher owes only the difference), nothing before.
    var due: Int {
        guard isFinal else { return 0 }
        return owed ?? (paid_at == nil ? total : 0)
    }
}

extension GroupStore {
    /// Ongkir is free from Rp 200.000. A final bill that had ongkir entered (or a legacy one that charged it) isn't.
    var freeOngkir: Bool {
        guard let g = group, Ongkir.isFree(subtotal: subtotal) else { return false }
        return !g.billFinal || (g.ongkir_set_at == nil && (g.ongkir ?? 0) == 0)
    }

    /// Members other than the host with a final bill to pay, in join order.
    var payers: [BillRow] {
        bill.filter { $0.user_id != group?.host_id && $0.isFinal && $0.total > 0 }
            .sorted { colorIndex($0.user_id) < colorIndex($1.user_id) }
    }

    /// Payers who haven't been marked paid ("Says paid" still owes until the host marks it).
    var owing: [BillRow] { payers.filter { $0.due > 0 } }

    var allPaid: Bool { group?.billFinal == true && owing.isEmpty }

    /// "Kevin still owes Rp 89.500", "Kevin and Arief still owe Rp 116.000".
    var owingLine: String {
        let o = owing
        let names = joinedNames(o.map { name($0.user_id) })
        return "\(names) still \(o.count == 1 ? "owes" : "owe") \(Rupiah.format(o.reduce(0) { $0 + $1.due }))"
    }

    /// Atas's 15:00 WITA cutoff for this order's delivery is under 30 minutes away, or past.
    var nearCutoff: Bool {
        guard let g = group else { return false }
        return Date() >= Wita.atasDeadline(for: g.delivery_at).addingTimeInterval(-StepsMotion.cutoffWarning)
    }
}

// MARK: - Steps

extension GroupView {
    /// Pay first's steps (G2) and the current one. Under Rp 200.000: Open, Locked, Ask Atas for ongkir, Bills final,
    /// Everyone pays, Send, Confirmed, Delivered, Closed; from Rp 200.000 the bills are final at lock, so there is no
    /// asking. Members read the same steps worded about the host; only the host's current step carries a reason.
    func payFlow(_ g: OrderGroup, _ layout: Timeline.Layout) -> (steps: [TimelineStep], current: Int) {
        let host = store.isHost
        let free = store.freeOngkir
        let shown = Timeline(group: g, lockedAt: times?.locked_at, editsAt: store.items.compactMap(\.flagged_at).min(), layout: layout)
        let when = { (s: GroupState) in shown.date(s).map { shown.meta(s, $0) } }
        let sent = [.sent, .confirmed, .delivered, .closed].contains(g.state)
        let payers = store.payers
        let paid = payers.count - store.owing.count
        let collecting = g.state == .locked && g.billFinal
        let warn = collecting && !store.allPaid && store.nearCutoff

        var steps = [TimelineStep(id: "open", title: GroupState.open.title, symbol: "clock", meta: when(.open)),
                     TimelineStep(id: "locked", title: GroupState.locked.title, symbol: "lock", meta: when(.locked))]
        if store.members.contains(where: { $0.done_editing_at != nil }) || g.state == .edits {
            steps.append(TimelineStep(id: "edits", title: GroupState.edits.title, symbol: "pencil", meta: when(.edits)))
        }
        if !free {
            steps.append(TimelineStep(id: "ask", title: host ? "Ask Atas for ongkir" : "\(hostFirst) asks Atas for ongkir", symbol: "message",
                                      meta: g.ongkir_asked_at.map { "Asked \(Wita.string($0, "HH:mm"))" },
                                      reason: host ? "Under Rp 200.000 Atas charges ongkir. Ask first so everyone pays the right amount." : nil))
        }
        steps.append(TimelineStep(id: "final", title: free ? "Bills final · free ongkir" : host ? "Bills final" : "Atas quoted the ongkir",
                                  symbol: "receipt", meta: g.bill_final_at.map { layout == .inline ? Wita.string($0, "EEE HH:mm") : Wita.string($0, "EEE d MMM, HH:mm") }))
        let payReason = warn ? "Atas’s cutoff is 15:00. Send now and collect the rest after."
            : free ? "\(Rupiah.format(store.subtotal)) is over Rp 200.000, so there’s no ongkir to ask about. Send the order once everyone has paid."
            : "Bills are final. Send the order once everyone has paid."
        steps.append(TimelineStep(id: "pay", title: !host ? "You pay \(hostFirst)" : g.billFinal ? "Everyone pays · \(paid) of \(payers.count) paid" : "Everyone pays", symbol: "banknote",
                                  meta: nil, reason: host ? payReason : nil, warn: warn,
                                  // Sent before everyone paid: payments stay open after the order has gone.
                                  phase: sent && g.billFinal && !store.allPaid ? .now : nil))
        steps.append(TimelineStep(id: "send", title: sent ? GroupState.sent.title : host ? "Send the order to Atas · before 15:00" : "\(hostFirst) sends the order · after everyone pays",
                                  symbol: "paperplane", meta: when(.sent),
                                  reason: host && collecting ? "Everyone has paid. Send the order to Atas before 15:00." : nil))
        for s in [GroupState.confirmed, .delivered, .closed] {
            steps.append(TimelineStep(id: s.rawValue, title: s.title, symbol: "checkmark", meta: when(s), todoMeta: shown.todoMeta(s)))
        }
        let index = { (id: String) in steps.firstIndex { $0.id == id } ?? 0 }
        let current: Int = switch g.state {
        case .open, .cancelled: 0
        case .locked: !g.billFinal ? index(free ? "final" : "ask") : store.allPaid ? index("send") : index("pay")
        case .edits: index("edits")
        case .sent: index("send")
        case .confirmed, .delivered, .closed: index(g.state.rawValue)
        }
        return (steps, current)
    }
}

// MARK: - Group screen: pay first while locked

extension GroupView {
    /// G-2 / G-3: the host's locked pay-first order. The steps with the current one's reason, then the review.
    @ViewBuilder func payFirstHostSections(_ g: OrderGroup) -> some View {
        header(g)
        timeline(g, .inline)
        reviewSections(g)
    }

    /// G-4: a member's locked pay-first order. Once the bill is final: pay now so the host can order; before, the host
    /// is asking Atas for the ongkir.
    @ViewBuilder func payFirstMemberSections(_ g: OrderGroup) -> some View {
        header(g)
        if let b = store.myBill, b.isFinal {
            if b.total > 0 {
                BillBanner(text: b.due == 0 ? "You’ve paid. \(hostFirst) sends the order to Atas once everyone has paid."
                                 : b.proof_at != nil ? "Waiting for \(hostFirst) to check your payment. They’ll send the order once everyone has paid."
                                 : "Pay now so \(hostFirst) can order. They’ll send it to Atas once everyone has paid.",
                           fill: Brand.choc100, circle: Brand.cream)
                oweCard(b)
            }
        } else {
            HStack(spacing: 14) {
                Mascot(pose: "pose-waiting", size: 72, fill: Brand.liquorice100)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(hostFirst) is asking Atas for the ongkir").ui(GFont.roundo(17))
                    Text("You can pay once your bill is final. If something needs fixing, they’ll ask you.").ui(GFont.manrope(13), Brand.ink2).lineSpacing(3)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .surface(32, padding: edges(16, 16))
        }
        timeline(g, .stacked)
        myItemsCompact
    }

    /// "You owe Rani · Rp 39.500 · Rp 32.000 items + Rp 7.500 ongkir" with Final and the pay chip; opens the bill.
    func oweCard(_ b: BillRow) -> some View {
        let ongkir = b.delivery_share
        let breakdown = b.due > 0 && b.due < b.total ? "\(Rupiah.format(b.total)) bill · \(Rupiah.format(b.total - b.due)) already paid"
            : ongkir > 0 ? "\(Rupiah.format(b.items)) items + \(Rupiah.format(ongkir)) ongkir"
            : ongkir < 0 ? "\(Rupiah.format(b.items)) items − \(Rupiah.format(-ongkir)) discount"
            : store.freeOngkir ? "\(Rupiah.format(b.items)) items · free ongkir" : "\(Rupiah.format(b.items)) items"
        return Button { sheet = .bill } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(b.due > 0 ? "You owe \(hostFirst)" : "Your bill").brand(.label)
                    Text(Rupiah.format(b.due > 0 ? b.due : b.total)).ui(GFont.roundo(34)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(breakdown).ui(GFont.manrope(12), Brand.ink2)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    finalTag(true)
                    PayTag(state: b.due == 0 ? .paid : PayState(b))
                }
            }
            .surface(32, padding: edges(18, 18))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your bill")
    }

    /// The bottom bar while a pay-first order is locked (host): the current step's action. Ask Atas for ongkir (Cocoa,
    /// WhatsApp) → Atas replied · enter ongkir (Caramel) → Payments + Send to Atas.
    @ViewBuilder func payFirstHostBar(_ g: OrderGroup) -> some View {
        GroupBar {
            ZStack {
                switch g.payPhase {
                case .asking where g.ongkir_asked_at == nil:
                    Button { sheet = .send } label: { Label { Text("Ask Atas for ongkir") } icon: { WhatsAppGlyph(size: 20) } }
                        .buttonStyle(.pill(.dark))
                        .transition(.opacity)
                case .asking:
                    Button("Atas replied · enter ongkir") { sheet = .confirmAtas }
                        .buttonStyle(.pill(.primary))
                        .transition(.opacity)
                default:
                    FlexRow(weights: [1, 1.4]) {
                        Button { sheet = .board } label: { Label("Payments", systemImage: "receipt") }
                            .buttonStyle(BarPillStyle(kind: .secondary))
                        SendToAtasPill(store: store, short: true) { sheet = .send }
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? Motion.Reduced.fade : StepsMotion.barSwap, value: "\(String(describing: g.payPhase))\(g.ongkir_asked_at != nil)")
        }
    }

    /// The member's Pay button while the order is locked or sent: enabled once the bill is final, before anything is
    /// sent; before the ongkir is in it explains why it waits.
    @ViewBuilder func memberPayBar(_ g: OrderGroup) -> some View {
        if let b = unpaid {
            GroupBar {
                Button { sheet = .bill } label: { Label("Pay \(hostFirst) · \(Rupiah.format(b.due))", systemImage: "receipt") }
                    .buttonStyle(.pill(.primary))
            }
        } else if g.payPhase == .asking, (store.myBill?.items ?? 0) > 0 {
            GroupBar {
                Button {} label: { Label("Pay \(hostFirst)", systemImage: "receipt") }
                    .buttonStyle(.pill(.primary))
                    .disabled(true, reason: "Waiting for Atas’s ongkir")
            }
        }
    }

    /// After a pay-first send with final bills, Atas confirmed is one tap: there's nothing to enter.
    func confirmSentPill() -> some View {
        AsyncPill(title: "Atas confirmed", icon: "checkmark", busyTitle: "Confirming…", doneTitle: "Confirmed", failTitle: "Couldn’t confirm",
                  holding: holding, refresh: store.refresh, reached: { store.group?.state == .confirmed }) {
            try await store.rpc("confirm_atas", ["g": .string(id.uuidString), "ongkir": .null, "discount": .null])
        }
    }
}

// MARK: - Send to Atas while someone hasn't paid (G-3, G-5, G-6)

/// Send to Atas in pay first. While anyone owes it is the quiet pill, "Send · 2 unpaid", and asks first (G-6): the
/// host can still send, because of Atas's 15:00 cutoff, and pays Atas for the unpaid shares until they pay. When the
/// last payment is marked it turns Cocoa and bumps, with the success tap.
struct SendToAtasPill: View {
    var store: GroupStore
    /// "Send · 2 unpaid" beside Payments; "Send to Atas · 2 unpaid" on its own.
    var short = false
    var send: () -> Void
    @State private var asking = false
    @State private var ready = 0
    @State private var problem: Problem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let owing = store.owing
        let n = owing.count
        Group {
            if owing.isEmpty {
                Button(action: send) { Label { Text("Send to Atas") } icon: { WhatsAppGlyph(size: 18) } }
                    .buttonStyle(BarPillStyle(kind: .dark))
            } else {
                Button { asking = true } label: {
                    Label { Text(short ? "Send · \(n) unpaid" : "Send to Atas · \(n) unpaid") } icon: { WhatsAppGlyph(size: 18) }
                }
                .buttonStyle(QuietPillStyle())
            }
        }
        .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick.delay(StepsMotion.sendReadyDelay), value: owing.isEmpty)
        .kick(reduceMotion ? 0 : ready, from: StepsMotion.sendReadyBump, delay: StepsMotion.sendReadyDelay)
        .onChange(of: owing.isEmpty) { was, now in if !was && now { ready += 1 } }
        .sensoryFeedback(Haptic.done, trigger: ready)
        .sensoryFeedback(Haptic.warn, trigger: asking) { !$0 && $1 }
        .alert(title(owing), isPresented: $asking) {
            Button(n == 1 ? "Nudge \(store.name(owing[0].user_id))" : "Nudge them") { Task { await nudge(owing) } }
            Button("Send anyway") { send() }
        } message: {
            Text(message(owing))
        }
        .problemAlert($problem)
    }

    private func title(_ owing: [BillRow]) -> String {
        owing.count == 1 ? "\(store.name(owing[0].user_id)) hasn’t paid yet" : "\(owing.count) people haven’t paid yet"
    }

    private func message(_ owing: [BillRow]) -> String {
        let who = owing.map { "\(store.name($0.user_id)) owes \(Rupiah.format($0.due))." }.joined(separator: " ")
        let share = owing.count == 1 ? "\(store.name(owing[0].user_id))’s share until they pay" : "their shares until they pay"
        return "\(who) If you send now, you pay Atas for \(share) you. Atas’s cutoff is 15:00 WITA."
    }

    /// The payment reminder to each of them not nudged in the last 4 hours.
    private func nudge(_ owing: [BillRow]) async {
        let due = owing.filter { r in
            let at = store.members.first { $0.user_id == r.user_id }?.nudged_at
            return at.map { Date().timeIntervalSince($0) >= CloseMotion.nudgeCooldown } ?? true
        }
        guard !due.isEmpty else {
            problem = Problem(title: "Already nudged", message: "You nudged them less than 4 hours ago.")
            return
        }
        await attempt($problem, "Couldn't nudge") {
            for r in due {
                try await store.rpc("nudge", ["g": .string(store.id.uuidString), "u": .string(r.user_id.uuidString)])
            }
        }
    }
}

/// The send pill while someone hasn't paid: Cream with a Liquorice 100 ring and Cocoa ink, the bar pill's size.
struct QuietPillStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CommitButton(configuration: configuration, face: Face(), haptic: Haptic.tap)
    }

    private struct Face: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            let p = configuration.isPressed
            configuration.label
                .labelStyle(IconLabel(spacing: 6, size: 16))
                .font(GFont.manrope(15, 600))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 60)
                .foregroundStyle(Brand.cocoa)
                .background(Capsule().fill(p ? Brand.creamPressed : Brand.cream).pressTone(p))
                .overlay(Capsule().strokeBorder(Brand.liquorice100, lineWidth: 4))
                .contentShape(Capsule())
                .doughPress(p, squash: Motion.pressWide)
        }
    }
}

// MARK: - Closing (H)

/// Close order for the host of a delivered order. Disabled (Liquorice 400) while anyone owes, with who owes what under
/// it; a tap shakes. Once the last payment is marked it turns Cocoa and bumps 0.7 s later.
struct CloseOrderBar: View {
    var store: GroupStore
    var close: () -> Void
    @State private var ready = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let blocked = !store.owing.isEmpty
        GroupBar {
            VStack(spacing: 8) {
                Button(action: close) {
                    if blocked { Label("Close order", systemImage: "lock") } else { Text("Close order") }
                }
                .buttonStyle(.pill(.dark))
                .disabled(blocked, reason: nil)
                .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick.delay(CloseMotion.doneDelay), value: blocked)
                .kick(reduceMotion ? 0 : ready, from: StepsMotion.sendReadyBump, delay: CloseMotion.doneDelay)
                if blocked {
                    Label { Text(store.owingLine) } icon: { icon("exclamationmark.circle", 14, Brand.ink2) }
                        .labelStyle(IconLabel(spacing: 6, size: 14))
                        .font(GFont.manrope(13, 600)).foregroundStyle(Brand.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 2)
                        .transition(.opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fadeOut))
                }
            }
        }
        .onChange(of: blocked) { was, now in if was && !now { ready += 1 } }
    }
}
