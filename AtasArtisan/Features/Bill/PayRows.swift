import SwiftUI
import Supabase

// One member's payment row, shared by the payment board (5-9, G-5) and the delivered order's Still owes card (H-1),
// and that card.

/// Avatar, name, what they still owe, their chip, and the host's actions. Unpaid: Nudge and Mark paid, which asks
/// first because there is no receipt (H-2). Says paid: the receipt and Mark paid, which opens the receipt (5-10) when
/// there is one. Paid: nothing. WhatsApp sits at the end on the board.
struct PayRow: View {
    var store: GroupStore
    var row: BillRow
    var receiptURL: URL?
    var whatsApp = true
    var openReceipt: () -> Void
    /// confirm_paid for this member.
    var markPaid: () async -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var asking = false
    @State private var nudging = false
    @State private var nudgeBumps = 0
    @State private var nudgeShakes = 0
    @State private var problem: Problem?

    private var name: String { store.name(row.user_id) }
    private var state: PayState { row.due == 0 ? .paid : PayState(row) }

    var body: some View {
        let state = state
        HStack(spacing: 12) {
            Avatar(name: name, index: store.colorIndex(row.user_id), size: 40, art: store.people[row.user_id]?.avatar,
                   bg: store.people[row.user_id]?.avatar_bg)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    // 9-10e: the badge after the name; unverified people have no WhatsApp button here, so the host
                    // sees why.
                    let person = store.people[row.user_id].flatMap { $0.verified ? VerifiedPerson($0, index: store.colorIndex(row.user_id)) : nil }
                    BadgedName(name: name, font: Type5.manrope(16, 700), person: person) {
                        if person == nil { NotVerifiedNote() }
                    }
                    Spacer()
                    Text(Rupiah.format(row.due > 0 ? row.due : row.total)).font(Type5.roundo(16)).foregroundStyle(Brand.cocoa)
                }
                HStack(spacing: 8) {
                    PayTag(state: state, size: .small)
                    Spacer(minLength: 0)
                    if let receiptURL {
                        Button(action: openReceipt) {
                            HatchedPhoto(url: receiptURL, fill: Brand.liquorice100, ink: Brand.cocoa.opacity(0.1), band: 3)
                                .frame(width: 28, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Brand.liquorice400, lineWidth: 1.5))
                                .contentShape(Rectangle().inset(by: -4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(name)’s receipt")
                    }
                    // Nudge goes once they say they paid; Mark paid folds away once paid.
                    if state == .unpaid { nudge.transition(fold) }
                    if state != .paid { markPaidChip.transition(fold) }
                    if whatsApp, let phone = store.people[row.user_id]?.phone {
                        Button { openURL(Links.whatsApp(phone)) } label: {
                            WhatsAppGlyph(size: 14).foregroundStyle(Brand.cocoa)
                                .frame(width: 28, height: 28).background(Circle().fill(Brand.lime))
                                .contentShape(Rectangle().inset(by: -8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("WhatsApp \(name)")
                    }
                }
                .frame(minHeight: 36)
                .animation(reduceMotion ? nil : Motion.leave.delay(BoardMotion.buttonCollapseDelay), value: state)
            }
        }
        .padding(.vertical, 14)
        .alert("Mark \(name) as paid?", isPresented: $asking) {
            Button("Cancel", role: .cancel) {}
            Button("Mark paid") { Task { await markPaid() } }
        } message: {
            Text("Use this if \(name) paid you another way, like cash. They’ll see “\(store.name(store.group?.host_id ?? UUID())) marked your \(Rupiah.format(row.due)) as paid.”")
        }
        .problemAlert($problem)
    }

    /// Folds from the trailing edge as it goes, opens to its width as it comes.
    private var fold: AnyTransition {
        .asymmetric(insertion: AnyTransition(Fold(reduceMotion: reduceMotion)).animation(reduceMotion ? Motion.Reduced.fade : Motion.settle),
                    removal: AnyTransition(Fold(reduceMotion: reduceMotion)).animation(reduceMotion ? Motion.Reduced.fade : Motion.leave.delay(BoardMotion.buttonCollapseDelay)))
    }

    /// Lime with a Lime Deep ring. Unpaid asks first; a claim with a receipt opens the receipt, where the host marks it.
    private var markPaidChip: some View {
        Button("Mark paid", systemImage: "checkmark") {
            if state == .unpaid { asking = true } else if receiptURL != nil { openReceipt() } else { Task { await markPaid() } }
        }
        .buttonStyle(ChipStyle(fill: Brand.lime, ring: Brand.limeDeep, haptic: nil))
    }

    /// Nudge (peach) rolls to "✓ Nudged" on Liquorice 100 and bumps from 1.15. The server allows one reminder every
    /// 4 hours; until then the chip stays Nudged and a tap only shakes it.
    private var nudge: some View {
        let at = store.members.first { $0.user_id == row.user_id }?.nudged_at
        let nudged = nudging || at.map { Date().timeIntervalSince($0) < CloseMotion.nudgeCooldown } == true
        return Button {
            if nudged {
                nudgeShakes += 1
            } else {
                nudging = true
                nudgeBumps += 1
                Task {
                    await attempt($problem, "Couldn't nudge") {
                        do { try await store.rpc("nudge", ["g": .string(store.id.uuidString), "u": .string(row.user_id.uuidString)]) } catch {
                            nudging = false
                            throw error
                        }
                    }
                }
            }
        } label: {
            ZStack {
                Group { if nudged { Label("Nudged", systemImage: "checkmark") } else { Label("Nudge", systemImage: "bell") } }
                    .id(nudged)
                    .transition(AnyTransition.roll(reduceMotion).animation(reduceMotion ? Motion.Reduced.fade : Motion.digits))
            }
        }
        .buttonStyle(ChipStyle(fill: nudged ? Brand.liquorice100 : Brand.choc100, haptic: nudged ? Haptic.blocked : Haptic.tap))
        .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick, value: nudged)
        .kick(reduceMotion ? 0 : nudgeBumps, from: BoardMotion.nudgeBump)
        .shake(reduceMotion ? 0 : nudgeShakes)
        .accessibilityLabel(nudged ? "Nudged" : "Nudge \(name)")
    }
}

/// H-1 / H-4: a delivered order, for the host. While anyone owes: STILL OWES with the total, a row per person who
/// owes, and who has paid. A marked row folds away 0.6 s after its chip turns Paid. Once nobody owes, the card turns
/// into the lime "Everyone has paid" notice.
struct StillOwesCard: View {
    var store: GroupStore
    @State private var receipts: [UUID: URL] = [:]
    @State private var receipt: ReceiptRef?
    @State private var problem: Problem?
    @State private var marked = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let owing = store.owing
        let payers = store.payers
        ZStack {
            if owing.isEmpty {
                Label {
                    Text("Everyone has paid. \(Rupiah.format(payers.reduce(0) { $0 + $1.total })) collected, so you can close the order.")
                } icon: { icon("checkmark", 20, Brand.cocoa, weight: .heavy) }
                .labelStyle(IconLabel(spacing: 10, size: 20))
                .font(GFont.manrope(14, 600)).foregroundStyle(Brand.cocoa)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Brand.lime))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Brand.limeDeep, lineWidth: 2))
                .transition(.opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.settle).delay(CloseMotion.doneDelay)))
            } else {
                owes(owing, paid: payers.filter { $0.due == 0 })
                    .transition(.opacity.animation(reduceMotion ? Motion.Reduced.fade : CloseMotion.rowCollapse.delay(CloseMotion.rowCollapseDelay)))
            }
        }
        .sheet(item: $receipt) { r in NavigationStack { ReceiptView(store: store, user: r.user) } }
        .task(id: store.bill.map(\.proof_at)) { await loadReceipts() }
        .problemAlert($problem)
        .sensoryFeedback(Haptic.done, trigger: marked)
    }

    private func owes(_ owing: [BillRow], paid: [BillRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Still owes").brand(.label)
                Spacer()
                Text(Rupiah.format(owing.reduce(0) { $0 + $1.due })).ui(GFont.roundo(15))
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(owing.reduce(0) { $0 + $1.due })))
                    .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: owing.map(\.due))
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(owing.enumerated()), id: \.element.user_id) { i, r in
                    VStack(spacing: 0) {
                        if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                        PayRow(store: store, row: r, receiptURL: receipts[r.user_id], whatsApp: false,
                               openReceipt: { receipt = ReceiptRef(user: r.user_id) }, markPaid: { await confirmPaid(r.user_id) })
                    }
                    .transition(.itemRow)
                }
            }
            .animation(reduceMotion ? nil : CloseMotion.rowCollapse.delay(CloseMotion.rowCollapseDelay), value: owing.map(\.user_id))
            .padding(.vertical, 4).padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
            Text(paid.isEmpty ? "Your own share isn’t counted."
                              : "\(joinedNames(paid.map { store.name($0.user_id) })) \(paid.count == 1 ? "has" : "have") paid. Your own share isn’t counted.")
                .font(Type5.manrope(12)).lineSpacing(1).foregroundStyle(Brand.ink3).padding(.horizontal, 4)
        }
    }

    private func confirmPaid(_ user: UUID) async {
        await attempt($problem, "Couldn't mark paid") {
            try await store.rpc("confirm_paid", ["g": .string(store.id.uuidString), "u": .string(user.uuidString)])
            marked += 1
        }
    }

    private func loadReceipts() async {
        let found = await Receipts.list(store.id)
        var urls: [UUID: URL] = [:]
        for user in found.keys where store.owing.contains(where: { $0.user_id == user }) {
            urls[user] = await Receipts.url(store.id, user)
        }
        receipts = urls
    }
}
