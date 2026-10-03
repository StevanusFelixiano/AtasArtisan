import SwiftUI
import PhotosUI
import Supabase

/// 4.13 Member bill (GoodMinton's two-column rule: proof_at = "I've paid", paid_at = host confirmed).
/// Board 5: 5-5 unpaid, 5-6 not final yet, 5-7 says paid, 5-8 paid (Mona Loafa on cocoa).
struct BillView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var toast: ToastNote?
    @State private var problem: Problem?
    @State private var receiptAt: Date?
    @State private var receiptURL: URL?
    @State private var viewing = false
    /// The JPEG of an upload that failed, kept for "Try again".
    @State private var failed: Data?
    /// The photo being uploaded, shown as the thumbnail until the receipt is up (Motion board 18).
    @State private var picked: UIImage?
    /// Bumped by each pick, so the new thumbnail scales in.
    @State private var picks = 0
    @State private var upload: UploadState?
    /// The upload still in flight after a timeout; a retry waits on it rather than sending another.
    @State private var pendingUpload: Task<Bool, Never>?
    @State private var uploadAttempt = 0
    @State private var uploads = 0
    @State private var uploadFails = 0
    @State private var retries = 0
    /// The bill on show is final. It starts as the bill is, so a bill that opens final is still (no replay); only a
    /// bill that turns final while open settles into its final numbers (Testing Fixes D): the card leads, the amount
    /// follows. The group screen under the sheet gives the success tap for order first's Confirmed move; pay first's
    /// bill turns final without a move, so this sheet gives it.
    @State private var final: Bool
    @State private var settles = 0
    /// The amount's line: 52 pt at the default text size, reserved from the first frame.
    @ScaledMetric(relativeTo: .title2) private var amountHeight: CGFloat = BillMotion.totalSize.to
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: GroupStore) {
        self.store = store
        _final = State(initialValue: store.myBill?.isFinal ?? false)
    }

    private enum Phase { case notFinal, unpaid, says, paid }

    private var phase: Phase {
        guard let b = store.myBill, b.isFinal else { return .notFinal }
        return b.due == 0 ? .paid : b.proof_at != nil ? .says : .unpaid
    }
    private var hostName: String { store.name(store.group?.host_id ?? UUID()) }

    var body: some View {
        Group {
            if phase == .paid, let bill = store.myBill {
                PaidView(host: hostName, total: bill.total)
            } else {
                bill
            }
        }
        .navigationTitle("Your bill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(phase == .paid ? .dark : nil, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
        .onChange(of: photo) { _, item in if let item { Task { await upload(item) } } }
        .onChange(of: phase != .notFinal) { old, now in
            guard now != final else { return }
            if now && !old {
                settles += 1
                final = true
            } else {
                // Pay first's bill stopped being final (unlocked, or edits requested): no settle to play backwards.
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { final = now }
            }
        }
        .task { await loadReceipt() }
        .sheet(isPresented: $viewing) {
            if let me = store.me { NavigationStack { ReceiptView(store: store, user: me) } }
        }
        .toast($toast, above: 84)
        .problemAlert($problem)
        .sensoryFeedback(Haptic.done, trigger: uploads)
        .sensoryFeedback(trigger: settles) { _, _ in store.group?.payFirst == true ? Haptic.done : nil }
        .sensoryFeedback(Haptic.fail, trigger: uploadFails)
        .sensoryFeedback(Haptic.tap, trigger: retries)
    }

    // MARK: Bill

    private var bill: some View {
        ScrollView {
            VStack(spacing: 14) {
                summary
                switch phase {
                case .notFinal, .unpaid:
                    if let p = store.payout, store.group?.payFirst == true || final {
                        transfer(p, amount: final ? store.myBill?.due : nil).transition(arriving)
                    }
                    if !final {
                        // The waiting card folds away 0.30 s into the settle.
                        BillBanner(text: store.group?.payFirst == true
                                   ? "\(hostName) is asking Atas for the ongkir. You can pay once your bill is final."
                                   : "You can pay once Atas confirms the order. We’ll tell you the final amount.",
                                   fill: Brand.liquorice100, circle: .white)
                            .transition(.asymmetric(insertion: .identity,
                                                    removal: .opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.fadeOut).delay(BillMotion.waitingDelay))))
                    } else {
                        receiptCard.transition(arriving)
                    }
                case .says:
                    receiptCard
                    VStack(spacing: Brand.s2) {
                        BillBanner(text: "Waiting for \(hostName) to check their account. You’ll get a ping when they confirm.",
                                   fill: Brand.choc100, circle: Brand.cream)
                        Button("Tell \(hostName) again") { Task { await claim() } }
                            .font(Type5.manrope(13, 600)).foregroundStyle(Brand.caramel).disabled(busy)
                            .frame(minHeight: 44)
                    }
                case .paid:
                    EmptyView()
                }
            }
            .animation(reduceMotion ? nil : final ? Motion.leave.delay(BillMotion.waitingDelay) : nil, value: final)
            .padding(.horizontal, Brand.s4)
            .padding(.top, 10)
            .padding(.bottom, Brand.s4)
        }
        .screen()
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    /// Cards that come with the final bill (the transfer details, the receipt) fade in as the waiting card goes.
    private var arriving: AnyTransition {
        .asymmetric(insertion: .opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(BillMotion.waitingDelay)),
                    removal: .opacity.animation(Motion.fadeOut))
    }

    @ViewBuilder private var bottomBar: some View {
        switch phase {
        case .notFinal, .unpaid:
            // One button from disabled to Caramel: it turns and bumps 0.40 s into the settle.
            if !final || (store.myBill?.due ?? 0) > 0 {
                GlassBar {
                    // Pay as soon as the bill is final: pay first before anything is sent, and after delivery until paid.
                    Button("I’ve paid") { Task { await claim() } }
                        .buttonStyle(.pill(.primary))
                        .disabled(!final || busy || store.group?.state == .cancelled,
                                  reason: final ? nil : store.group?.payFirst == true ? "Waiting for Atas’s ongkir" : "The bill isn’t final yet")
                        .animation((reduceMotion ? Motion.Reduced.fade : Motion.quick).delay(PaySheetMotion.payDelay), value: final)
                        .kick(reduceMotion ? 0 : settles, from: BillMotion.payBump, delay: PaySheetMotion.payDelay)
                        // The receipt is up: the next step bumps 0.20 s later.
                        .kick(reduceMotion ? 0 : uploads, from: AsyncMotion.successBump, delay: UploadMotion.doneDelay)
                }
            }
        case .says:
            if let phone = store.people[store.group?.host_id ?? UUID()]?.phone {
                GlassBar {
                    Button { openURL(Links.whatsApp(phone)) } label: {
                        Label { Text("Message \(hostName)") } icon: { WhatsAppGlyph(size: 19) }
                    }
                    .buttonStyle(.pill(.secondary))
                }
            }
        case .paid:
            EmptyView()
        }
    }

    /// The white card: state tags, the amount, who it goes to, and the lines that make it up. One card for both
    /// states, so a bill that turns final while open settles in place (Testing Fixes D). The amount's 52 pt line is
    /// reserved from the first frame and the number only scales inside it (46/52 → 1), so it never leaves the card. The
    /// card's height leads on `PaySheetMotion.card` and clips what opens inside it; the text follows: amount scale from
    /// 0.06 s, tags and count from 0.10 s, ongkir share 0.14 s, discount row 0.22 s, the Pay button 0.40 s.
    private var summary: some View {
        let b = store.myBill
        let f = final
        let total = f ? (b.map { $0.due > 0 ? $0.due : $0.total } ?? 0) : b?.items ?? itemLines.reduce(0) { $0 + $1.amount }
        let fade = reduceMotion ? Motion.Reduced.fade : Motion.fade
        return VStack(alignment: .leading, spacing: 12) {
            tags(f).frame(minHeight: 23, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // "≈ " narrows to nothing and fades with the tag swap.
                Text("≈ ").fixedSize()
                    .frame(width: f ? 0 : nil, alignment: .leading).clipped()
                    .opacity(f ? 0 : 1)
                    .animation((reduceMotion ? Motion.Reduced.fade : Motion.fadeOut).delay(PaySheetMotion.tagDelay), value: f)
                // Each counted frame is a new string: no per-frame text transition.
                CountUp(amount: total, delay: PaySheetMotion.countDelay) { Text(Rupiah.format($0)).contentTransition(reduceMotion ? .opacity : .identity) }
            }
            .font(Type5.roundo(BillMotion.totalSize.to)).monospacedDigit()
            .tracking(BillMotion.totalSize.to * -0.02)
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(f ? Brand.cocoa : Brand.ink3)
            .animation(fade.delay(PaySheetMotion.amountDelay), value: f)
            // Scale only, never the font size: the box is already final-sized.
            .scaleEffect(f ? 1 : PaySheetMotion.amountScaleFrom, anchor: .bottomLeading)
            .animation(reduceMotion ? nil : PaySheetMotion.amount.delay(PaySheetMotion.amountDelay), value: f)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .frame(height: amountHeight, alignment: .bottomLeading)
            OneSpot(active: f ? 1 : 0) {
                Text(store.freeOngkir ? "Your items so far. Ongkir is free: the order is over Rp 200.000."
                                      : "Your items so far. Ongkir and any discount get added when Atas confirms.")
                    .opacity(f ? 0 : 1).animation(reduceMotion ? Motion.Reduced.fade : Motion.fadeOut, value: f)
                Text(subtitle)
                    .opacity(f ? 1 : 0).animation(fade.delay(PaySheetMotion.tagDelay), value: f)
            }
            .font(Type5.manrope(13)).lineSpacing(1).foregroundStyle(Brand.ink2)
            if phase != .says {
                VStack(spacing: 8) {
                    ForEach(Array(itemLines.enumerated()), id: \.element.id) { i, l in lineRow(l, index: i) }
                    ongkirRow(index: itemLines.count)
                    if f, let d = deliveryLines.first(where: \.credit) {
                        lineRow(d, index: itemLines.count + 1).transition(arrivingRow)
                    }
                    if f, let b, let paid = b.paid_total, paid > 0, b.due > 0 {
                        lineRow(BillLine(id: "paid", label: "Already paid", meta: nil, amount: paid, credit: true), index: itemLines.count + 2)
                            .transition(arrivingRow)
                    }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { DashedRule(color: Brand.liquorice400) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        // The card's height leads: every row that opens inside it does so on the quicker spring, revealed by its edge.
        .animation(reduceMotion ? nil : PaySheetMotion.card, value: f)
    }

    /// Not final yet → Final and the pay chip: the old tag fades out, the new pair pops in from 0.92 after 0.10 s.
    private func tags(_ f: Bool) -> some View {
        ZStack(alignment: .leading) {
            if f {
                HStack {
                    finalTag(true)
                    Spacer()
                    PayTag(state: phase == .says ? .says : .unpaid)
                }
                .transition(.asymmetric(
                    insertion: reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade)
                        : AnyTransition.scale(scale: 0.92, anchor: .leading).combined(with: .opacity).animation(Motion.pop.delay(PaySheetMotion.tagDelay)),
                    removal: .opacity.animation(Motion.fadeOut)))
            } else {
                finalTag(false)
                    .transition(.asymmetric(insertion: .opacity.animation(Motion.fade),
                                            removal: .opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.fadeOut).delay(PaySheetMotion.tagDelay))))
            }
        }
    }

    /// The discount row (and an already-paid line) arriving inside the clip: fades in and rises 6 pt from 0.22 s.
    private var arrivingRow: AnyTransition {
        reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade)
            : .asymmetric(insertion: AnyTransition.opacity.animation(Motion.fade.delay(PaySheetMotion.discountRowDelay))
                            .combined(with: AnyTransition.offset(y: PaySheetMotion.rowOffset).animation(Motion.settle.delay(PaySheetMotion.discountRowDelay))),
                          removal: .opacity.animation(Motion.fadeOut))
    }

    private var subtitle: String {
        guard phase == .says, let at = store.myBill?.proof_at else { return "to \(hostName) · \(store.group?.name ?? "")" }
        let bank = store.payout.map { " · \($0.label)" } ?? ""
        return "to \(hostName)\(bank) · you marked it paid at \(Wita.string(at, "HH:mm"))"
    }

    /// A line's second line ("my items", "split with…", "Rp 10.000 ÷ 4") opens 0 → 16 pt with the card once the bill
    /// is final; its words fade in after, each line 0.04 s after the one above, from 0.10 s.
    private func lineDetail(_ meta: String?, index: Int) -> some View {
        Text(meta ?? "").font(Type5.manrope(12)).foregroundStyle(Brand.ink3)
            .opacity(final && meta != nil ? 1 : 0)
            .animation(reduceMotion ? Motion.Reduced.fade : final ? Motion.fade.delay(BillMotion.lineStart + BillMotion.lineStep * Double(index)) : nil, value: final)
            .frame(height: final && meta != nil ? 16 : 0, alignment: .top)
            .clipped()
            .animation(reduceMotion ? nil : final ? PaySheetMotion.card : nil, value: final)
    }

    private func lineRow(_ l: BillLine, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.label).font(Type5.manrope(14, 600)).foregroundStyle(Brand.cocoa)
                lineDetail(l.meta, index: index)
            }
            Spacer(minLength: 0)
            Text(l.credit ? "− \(Rupiah.format(l.amount))" : Rupiah.format(l.amount))
                .font(Type5.manrope(14, 600)).foregroundStyle(l.credit ? Brand.limeInk : Brand.cocoa).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// "Ongkir share · After Atas confirms" until the bill is final, then my share rolls in (0.14 s) and the ink deepens.
    @ViewBuilder private func ongkirRow(index: Int) -> some View {
        let line = deliveryLines.first { !$0.credit }
        if !final || line != nil {
            let ink = final ? Brand.cocoa : Brand.ink3
            let inkMotion = (reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(PaySheetMotion.ongkirDelay)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ongkir share").foregroundStyle(ink).animation(inkMotion, value: final)
                    lineDetail(line?.meta, index: index)
                }
                Spacer(minLength: 0)
                RollText(key: final ? "final" : "waiting", delay: PaySheetMotion.ongkirDelay) {
                    Text(final ? (line?.amount == 0 && store.freeOngkir ? "Free" : Rupiah.format(line?.amount ?? 0))
                         : store.freeOngkir ? "Free" : "After Atas confirms").fixedSize()
                }
                .foregroundStyle(ink).animation(inkMotion, value: final)
            }
            .font(Type5.manrope(14, 600))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Lines

    struct BillLine: Identifiable {
        var id: String
        var label: String
        var meta: String?
        var amount: Int
        var credit = false
    }

    /// My items and my pieces of shared items, in the amounts `group_bill_v` charges: a joiner pays
    /// ⌊price × n ÷ pieces⌋, the owner the rest.
    private var itemLines: [BillLine] {
        guard let me = store.me else { return [] }
        var out: [BillLine] = [], shared: [BillLine] = []
        for item in store.items {
            let claims = store.claims(item)
            let pieces = item.share_pieces ?? 0
            if item.owner_id == me {
                if claims.isEmpty {
                    out.append(BillLine(id: item.id.uuidString, label: "\(item.qty)× \(item.name)", meta: "my items", amount: item.total))
                } else {
                    out.append(BillLine(id: item.id.uuidString, label: "\(item.name) · \(store.ownerPieces(item)) of \(pieces) pieces",
                                        meta: "shared with \(joinedNames(claims.map { store.name($0.user_id) }))",
                                        amount: Pieces.ownerAmount(price: item.total, pieces: pieces, claims: claims.map(\.pieces))))
                }
            } else if let mine = claims.first(where: { $0.user_id == me }) {
                shared.append(BillLine(id: item.id.uuidString, label: "\(item.name) · \(mine.pieces) of \(pieces) pieces",
                                       meta: "under \(store.name(item.owner_id))",
                                       amount: Pieces.amount(price: item.total, pieces: pieces, n: mine.pieces)))
            }
        }
        return out + shared
    }

    /// Ongkir and discount, each split equally between everyone who ordered, each share truncated to Rp 100. The two
    /// lines add up to the view's `delivery_share` (the host's line carries the rounding). Free from Rp 200.000.
    private var deliveryLines: [BillLine] {
        guard let g = store.group, let b = store.myBill, b.items > 0, let ongkir = g.ongkir else { return [] }
        let payers = max(1, store.bill.filter { $0.items > 0 }.count)
        let discount = g.discount ?? 0
        if ongkir == 0 && discount == 0 && store.freeOngkir {
            return [BillLine(id: "ongkir", label: "Ongkir share", meta: "free from Rp 200.000", amount: 0)]
        }
        guard discount > 0 else {
            return [BillLine(id: "ongkir", label: "Ongkir share", meta: "\(Rupiah.format(ongkir)) ÷ \(payers)", amount: b.delivery_share)]
        }
        let ongkirShare = Ongkir.each(net: ongkir, payers: payers)
        return [BillLine(id: "ongkir", label: "Ongkir share", meta: "\(Rupiah.format(ongkir)) ÷ \(payers)", amount: ongkirShare),
                BillLine(id: "discount", label: "Discount share", meta: "\(Rupiah.format(discount)) ÷ \(payers)",
                         amount: ongkirShare - b.delivery_share, credit: true)]
    }

    // MARK: Transfer

    /// Cocoa card with the host's account and copy buttons.
    private func transfer(_ p: PayoutAccount, amount: Int?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Transfer to").font(Type5.manrope(12, 600)).tracking(12 * 0.03).textCase(.uppercase).foregroundStyle(Brand.liquorice400)
                Spacer()
                if !p.label.isEmpty {
                    Text(p.label).font(Type5.manrope(11, 600)).tracking(11 * 0.03).foregroundStyle(Brand.cocoa)
                        .padding(.vertical, 3).padding(.horizontal, 12).background(Capsule().fill(Brand.choc400))
                }
            }
            copyRow("Account name", p.account_name, font: Type5.manrope(17, 700), toastText: "Account name copied")
            copyRow("Account number", p.number, display: grouped(p.number), font: Type5.roundo(26), tracking: 26 * 0.04,
                    toastText: "Account number copied")
            if let amount {
                copyRow("Amount", String(amount), display: Rupiah.format(amount), font: Type5.manrope(17, 700), toastText: "Amount copied")
                    .padding(.top, 12)
                    .overlay(alignment: .top) { DashedRule(color: Brand.cream.opacity(0.2)) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.cocoa))
    }

    private func copyRow(_ caption: String, _ value: String, display: String? = nil, font: Font, tracking: CGFloat = 0, toastText: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption).font(Type5.manrope(12)).foregroundStyle(Brand.liquorice400)
                Text(display ?? value).font(font).tracking(tracking).foregroundStyle(Brand.cream)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            CopyButton(value: value, message: toastText, toast: $toast) { icon in
                icon.font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.cocoa)
                    .frame(width: 32, height: 32).background(Circle().fill(Brand.choc100))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .padding(.trailing, -6)
            .accessibilityLabel("Copy \(caption.lowercased())")
        }
    }

    /// "5271009934" → "5271 0099 34", as bank apps print it. Anything already spaced stays as written.
    private func grouped(_ number: String) -> String {
        guard !number.contains(" "), number.allSatisfy(\.isNumber), number.count > 6 else { return number }
        var out = ""
        for (i, c) in number.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(c)
        }
        return out
    }

    // MARK: Receipt

    /// Where my receipt stands: an upload this session, else what the server has.
    private var receiptState: UploadState? {
        upload ?? (failed != nil ? .failed : receiptAt != nil ? .done : nil)
    }

    /// The upload slot until there is a photo; then the photo's row, which carries the upload (Motion board 18): the
    /// picked photo scales in over the slot, a Cocoa layer and a ring creep while it uploads, and it ends with the
    /// check badge, or with "Tap to retry" and 6-9's Try again.
    @ViewBuilder private var receiptCard: some View {
        if let state = receiptState {
            receiptRow(state)
        } else {
            PhotosPicker(selection: $photo, matching: .images) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.liquorice100)
                        Image(systemName: "square.and.arrow.up").font(.system(size: 19, weight: .medium)).foregroundStyle(Brand.cocoa)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload transfer receipt").font(Type5.manrope(15, 700)).foregroundStyle(Brand.cocoa)
                        Text("Optional, helps \(hostName) check faster").font(Type5.manrope(12)).foregroundStyle(Brand.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Brand.card))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Brand.liquorice400, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
            .buttonStyle(DoughStyle(squash: Motion.pressCompact))
        }
    }

    private func receiptRow(_ state: UploadState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    switch state {
                    case .done: viewing = true
                    case .failed: retry()
                    case .uploading: break
                    }
                } label: {
                    HStack(spacing: 14) {
                        receiptThumb(state)
                        receiptText(state).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                // Not `.disabled`: that would grey the row while the photo uploads.
                .allowsHitTesting(state != .uploading)
                .accessibilityHint(state == .failed ? "Uploads the photo again" : state == .done ? "Shows the receipt" : "")
                if state == .done {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Text("Replace").font(Type5.manrope(13, 600)).foregroundStyle(Brand.caramel).frame(minHeight: 44)
                    }
                    .buttonStyle(DoughStyle(squash: Motion.pressCompact))
                }
            }
            if state == .failed, let failed {
                Button { Task { await send(failed) } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                    .buttonStyle(WidePill(fill: Brand.cocoa, ink: Brand.cream, size: 15, padding: 15))
                    .transition(.opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fade))
            }
        }
        .padding(14)
        .background(shape.fill(Brand.card))
        .overlay(shape.strokeBorder(Brand.destructive, lineWidth: 2).opacity(state == .failed ? 1 : 0))
        .animation(reduceMotion ? Motion.Reduced.fade : Motion.fade, value: state)
    }

    /// The photo, 64 × 84 with an inset 1.5 pt Liquorice 400 ring, under the upload's layer and ring. A new pick scales
    /// in from 0.9 as it fades in.
    private func receiptThumb(_ state: UploadState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            if let picked = picked ?? failed.flatMap(UIImage.init(data:)) {
                Image(uiImage: picked).resizable().scaledToFill()
            } else {
                HatchedPhoto(url: receiptURL, fill: Brand.liquorice100, ink: Brand.cocoa.opacity(0.07), band: 6)
            }
        }
        .frame(width: 64, height: 84)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Brand.liquorice400, lineWidth: 1.5))
        .modifier(UploadOverlay(state: state, radius: 12))
        .modifier(ThumbIn(active: picks > 0))
        .id(picks)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func receiptText(_ state: UploadState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            switch state {
            case .uploading:
                Text("Transfer receipt").font(Type5.manrope(15, 700)).foregroundStyle(Brand.cocoa)
                Text("Uploading…").font(Type5.manrope(12)).foregroundStyle(Brand.ink3)
            case .done:
                Text("Transfer receipt").font(Type5.manrope(15, 700)).foregroundStyle(Brand.cocoa)
                Text("Uploaded \(Wita.string(receiptAt ?? Date(), "HH:mm")) · tap to view").font(Type5.manrope(12)).foregroundStyle(Brand.ink3)
            case .failed:
                Label("Upload didn’t go through", systemImage: "exclamationmark.triangle")
                    .labelStyle(IconLabel(spacing: 6, size: 14))
                    .font(Type5.manrope(15, 700)).foregroundStyle(Brand.destructive)
                Text("The connection dropped. Your photo is still here.")
                    .font(Type5.manrope(13)).lineSpacing(1).foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(state)
        .transition(.opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fade))
    }

    private func loadReceipt() async {
        #if DEBUG
        // Screenshot hook for 6-9: show the failed-upload card with a stand-in photo.
        if DebugScreens.value("ATASTE_UPLOAD_FAILED") != nil { failed = UIImage(named: "paint-croissant")?.jpegData(compressionQuality: 0.5) }
        #endif
        guard let me = store.me, let at = await Receipts.list(store.id)[me] else { return }
        receiptAt = at
        receiptURL = await Receipts.url(store.id, me)
    }

    private func upload(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let jpeg = JPEG.compress(data) else {
            problem = Problem(title: "Upload failed", message: UploadError.unreadable.errorDescription ?? "")
            return
        }
        pendingUpload = nil
        picked = UIImage(data: jpeg)
        picks += 1
        await send(jpeg)
    }

    /// The failed thumbnail's tap: back to uploading the same JPEG.
    private func retry() {
        guard let failed else { return }
        retries += 1
        Task { await send(failed) }
    }

    /// Uploads (or replaces) my receipt. A failed upload, or one with no answer after 10 s, keeps the JPEG for "Try
    /// again" (6-9). The request is never cancelled: a late success still lands, and a retry waits on it.
    private func send(_ jpeg: Data) async {
        guard let me = store.me else { return }
        uploadAttempt += 1
        let mine = uploadAttempt
        upload = .uploading
        let work = pendingUpload ?? Task { () -> Bool in
            do {
                try await supabase.storage.from("receipts").upload(Receipts.path(store.id, me), data: jpeg,
                                                                    options: FileOptions(contentType: "image/jpeg", upsert: true))
                return true
            } catch {
                return false
            }
        }
        pendingUpload = work
        let timer = Task {
            try? await Task.sleep(for: .seconds(UploadMotion.timeout))
            if !Task.isCancelled, mine == uploadAttempt, upload == .uploading { failUpload(jpeg) }
        }
        let ok = await work.value
        timer.cancel()
        guard mine == uploadAttempt else { return }
        pendingUpload = nil
        if ok {
            failed = nil
            receiptAt = Date()
            upload = .done
            uploads += 1
            receiptURL = await Receipts.url(store.id, me)
        } else if upload == .uploading {
            failUpload(jpeg)
        }
    }

    private func failUpload(_ jpeg: Data) {
        failed = jpeg
        upload = .failed
        uploadFails += 1
    }

    private func claim() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't tell the host") {
            try await store.rpc("claim_paid", ["g": .string(store.id.uuidString)])
        }
    }
}

/// 5-8: the host confirmed. Mona Loafa in a caramel frame on lime rays over cocoa.
private struct PaidView: View {
    var host: String
    var total: Int

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                Brand.cocoa
                Rays(color: Brand.lime, width: 9, period: 18).opacity(0.9)
                    .frame(width: 700, height: 700)
                    .position(x: geo.size.width / 2, y: top + 224)
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        PaintingFrame(art: "paint-monalisa", width: 200, height: 248, tilt: -2)
                        (Text("Mona Loafa").italic() + Text(" · oil on canvas"))
                            .font(Type5.manrope(12)).foregroundStyle(Brand.choc100)
                    }
                    .padding(.top, 44)
                    VStack(spacing: 10) {
                        Text("Paid up!").font(Brand.font(.accent, size: 54)).foregroundStyle(Brand.lime)
                        Text("\(host) confirmed your \(Rupiah.format(total)).\nNothing left to do but eat.")
                            .font(Type5.manrope(16, 600)).lineSpacing(2).multilineTextAlignment(.center).foregroundStyle(Brand.cream)
                        PayTag(state: .paid).padding(.top, 6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 44)
                }
                .padding(.top, top)
            }
            .ignoresSafeArea()
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

enum UploadError: LocalizedError {
    case unreadable
    var errorDescription: String? { "That photo couldn't be read. Try another one." }
}

enum JPEG {
    /// Longest side 1600 px, JPEG under the buckets' 2 MB limit.
    static func compress(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        for q in [0.7, 0.5, 0.35] {
            if let out = resized.jpegData(compressionQuality: q), out.count < 2_000_000 { return out }
        }
        return nil
    }
}

/// 4.13 Host payment board (5-9): who paid, who says they paid, who still owes. In pay first before sending (G-5) it
/// also carries Atas's cutoff and Send to Atas.
struct PaymentBoardView: View {
    var store: GroupStore
    /// Opens the order message (pay first, before sending).
    var send: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var receipt: ReceiptRef?
    @State private var receipts: [UUID: URL] = [:]
    @State private var problem: Problem?
    /// My Mark paid is in flight: the bar and totals move 0.10 s after the chip (a member's own "I've paid" moves them
    /// at once).
    @State private var marking = false
    @State private var marked = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [BillRow] { store.payers }
    private var collecting: Bool { store.group?.payPhase == .collecting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if rows.isEmpty {
                    EmptyStateView(pose: "pose-waiting", title: "Nobody owes you", message: "Bills appear once they’re final.")
                } else {
                    totals
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.user_id) { i, r in
                            PayRow(store: store, row: r, receiptURL: receipts[r.user_id],
                                   openReceipt: { receipt = ReceiptRef(user: r.user_id) }, markPaid: { await confirmPaid(r.user_id) })
                            if i < rows.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                        }
                    }
                    .padding(.vertical, 4).padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
                    if collecting { cutoffNote }
                    if !footnote.isEmpty {
                        Text(footnote).font(Type5.manrope(12)).lineSpacing(1).foregroundStyle(Brand.ink3).padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.top, 10)
            .padding(.bottom, Brand.s5)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            if collecting, let send {
                GlassBar { SendToAtasPill(store: store, send: send) }
            }
        }
        .navigationTitle("Payments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
        .sheet(item: $receipt) { r in NavigationStack { ReceiptView(store: store, user: r.user) } }
        .task(id: store.bill.map(\.proof_at)) { await loadReceipts() }
        .problemAlert($problem)
        .sensoryFeedback(Haptic.done, trigger: marked)
    }

    private var footnote: String {
        let host = store.bill.first { $0.user_id == store.group?.host_id }
        var parts: [String] = []
        if let h = host, h.total > 0 { parts.append("Your own share (\(Rupiah.format(h.total))) isn’t counted.") }
        let shares = Set(rows.map(\.delivery_share)).filter { $0 > 0 }
        if shares.count == 1, let s = shares.first { parts.append("Totals include the \(Rupiah.format(s)) ongkir share on each bill.") }
        return parts.joined(separator: " ")
    }

    /// G-5: send once everyone has paid, and how long until Atas's 15:00 WITA cutoff.
    private var cutoffNote: some View {
        TimelineView(.periodic(from: .now, by: 60)) { t in
            let deadline = Wita.atasDeadline(for: store.group?.delivery_at ?? t.date)
            let mins = Int(deadline.timeIntervalSince(t.date) / 60)
            let left = mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
            Label {
                Text(mins > 0 ? "Send the order once everyone has paid. Atas’s cutoff is 15:00 WITA, \(left) from now."
                              : "Atas’s 15:00 WITA cutoff has passed, so delivery can take up to 2 days. Send now and collect the rest after.")
            } icon: { icon("clock", 16, Brand.ink2) }
            .labelStyle(IconLabel(spacing: 10, size: 16))
            .font(Type5.manrope(13)).lineSpacing(1).foregroundStyle(Brand.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.card))
        }
    }

    // MARK: Totals

    /// The owed bar's segments take their share of the total on `Motion.doughTrail` and the three amounts count to
    /// their new values on `Motion.glide` (Motion board 19). Reduce Motion: the bar eases, the amounts crossfade.
    private var totals: some View {
        let delay = marking ? BoardMotion.barDelay : 0
        let paid = rows.reduce(0) { $0 + $1.total - $1.due }
        let says = rows.filter { $0.due > 0 && $0.proof_at != nil }.reduce(0) { $0 + $1.due }
        let owed = rows.filter { $0.due > 0 && $0.proof_at == nil }.reduce(0) { $0 + $1.due }
        let paidCount = rows.filter { $0.due == 0 }.count
        let parts: [(String, Int, Color, Color)] = [("Collected · \(paidCount) of \(rows.count)", paid, Brand.limeDeep, Brand.limeDeep),
                                                    ("To check", says, Brand.choc400, Brand.choc400),
                                                    ("Outstanding", owed, Brand.liquorice100, Brand.liquorice400)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Owed to you").font(Type5.manrope(12, 600)).tracking(12 * 0.03).textCase(.uppercase).foregroundStyle(Brand.cocoa)
                Spacer()
                Text(Rupiah.format(paid + says + owed)).font(Type5.roundo(18)).foregroundStyle(Brand.cocoa)
            }
            GeometryReader { g in
                let amounts = parts.map(\.1)
                let gaps = CGFloat(max(0, amounts.filter { $0 > 0 }.count - 1)) * SplitMotion.segmentGap
                // Every segment stays in the row so it can grow from or shrink to nothing; a 2 pt gap follows each
                // one that has a filled segment after it.
                HStack(spacing: 0) {
                    ForEach(parts.indices, id: \.self) { i in
                        Rectangle().fill(parts[i].2)
                            .frame(width: (g.size.width - gaps) * CGFloat(amounts[i]) / CGFloat(max(1, paid + says + owed)))
                            .padding(.trailing, amounts[i] > 0 && amounts[(i + 1)...].contains { $0 > 0 } ? SplitMotion.segmentGap : 0)
                    }
                }
                .animation((reduceMotion ? Motion.Reduced.fill : Motion.doughTrail).delay(delay), value: amounts)
            }
            .frame(height: 16)
            .background(Brand.liquorice100)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 8) {
                ForEach(parts.indices, id: \.self) { i in
                    let p = parts[i]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(p.3).frame(width: 8, height: 8)
                            Text(p.0).font(Type5.manrope(11, 600)).foregroundStyle(Brand.ink2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        CountUp(amount: p.1, delay: delay) { Text(Rupiah.format($0)) }
                            .font(Type5.roundo(17)).foregroundStyle(Brand.cocoa).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
    }

    private func confirmPaid(_ user: UUID) async {
        marking = true
        defer { marking = false }
        await attempt($problem, "Couldn't mark paid") {
            try await store.rpc("confirm_paid", ["g": .string(store.id.uuidString), "u": .string(user.uuidString)])
            marked += 1
        }
    }

    private func loadReceipts() async {
        let found = await Receipts.list(store.id)
        var urls: [UUID: URL] = [:]
        for user in found.keys where rows.contains(where: { $0.user_id == user }) {
            urls[user] = await Receipts.url(store.id, user)
        }
        receipts = urls
        #if DEBUG
        if receipt == nil, let who = DebugScreens.value("ATASTE_RECEIPT"),
           let r = rows.first(where: { store.name($0.user_id).localizedCaseInsensitiveContains(who) }) {
            receipt = ReceiptRef(user: r.user_id)
        }
        #endif
    }

}

struct ReceiptRef: Identifiable { var user: UUID; var id: UUID { user } }

/// 5-10: one member's transfer receipt, full screen on cocoa. The host marks it paid from here.
struct ReceiptView: View {
    var store: GroupStore
    var user: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var uploadedAt: Date?
    @State private var loaded = false
    @State private var busy = false
    @State private var problem: Problem?

    private var row: BillRow? { store.bill.first { $0.user_id == user } }
    private var name: String { store.name(user) }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                HatchedPhoto(url: nil, fill: Brand.cream.opacity(0.1), ink: Brand.cream.opacity(0.05), band: 8)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if loaded {
                    Text("No receipt uploaded").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Brand.liquorice400)
                } else {
                    ProgressView().tint(Brand.cream)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 480)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 40)
            .accessibilityLabel("\(name)’s transfer receipt")
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info).font(Type5.manrope(13, 600)).foregroundStyle(Brand.liquorice400)
                    Text(Rupiah.format(row.map { $0.due > 0 ? $0.due : $0.total } ?? 0)).font(Type5.roundo(30)).foregroundStyle(Brand.cream)
                }
                Spacer()
                if let row { PayTag(state: row.due == 0 && row.isFinal ? .paid : PayState(row)) }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.cocoa.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if store.isHost, let row, row.due > 0 {
                HStack(alignment: .bottom, spacing: 10) {
                    Button("Not received") { Task { await act("reject_paid", "Couldn't tell them") } }
                        .buttonStyle(WidePill(fill: Brand.cream.opacity(0.12), ink: Brand.cream, size: 17, padding: 18))
                        .disabled(busy)
                    AsyncPill(title: "Mark paid", icon: "checkmark", busyTitle: "Marking…", doneTitle: "Paid", failTitle: "Couldn’t mark paid",
                              kind: .success, refresh: store.refresh,
                              reached: { store.bill.first { $0.user_id == user }?.paid_at != nil }) {
                        try await store.rpc("confirm_paid", ["g": .string(store.id.uuidString), "u": .string(user.uuidString)])
                    } then: {
                        dismiss()
                    }
                    .disabled(busy)
                    .containerRelativeFrame(.horizontal) { w, _ in (w - 42) * 1.3 / 2.3 }
                }
                .padding(.horizontal, Brand.s4)
                .padding(.bottom, 10)
            }
        }
        .navigationTitle("\(name)’s receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Brand.cocoa, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            if let image {
                ToolbarItem(placement: .primaryAction) {
                    Button { presentShare([image]) } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share receipt")
                }
            }
        }
        .task { await load() }
        .problemAlert($problem)
    }

    private var info: String {
        var parts = [name]
        if let label = store.payout?.label, !label.isEmpty { parts.append(label) }
        if let at = row?.proof_at ?? uploadedAt { parts.append(Wita.string(at, "HH:mm")) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        defer { loaded = true }
        uploadedAt = await Receipts.list(store.id)[user]
        guard uploadedAt != nil, let url = await Receipts.url(store.id, user),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        image = UIImage(data: data)
    }

    private func act(_ fn: String, _ title: String) async {
        busy = true
        defer { busy = false }
        await attempt($problem, title) {
            try await store.rpc(fn, ["g": .string(store.id.uuidString), "u": .string(user.uuidString)])
            dismiss()
        }
    }
}
