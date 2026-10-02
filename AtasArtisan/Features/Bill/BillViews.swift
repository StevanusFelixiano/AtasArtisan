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
    @State private var uploading = false
    @State private var copied: String?
    @State private var toast: String?
    @State private var problem: Problem?
    @State private var receiptAt: Date?
    @State private var receiptURL: URL?
    @State private var viewing = false
    /// The JPEG of an upload that failed, kept for "Try again".
    @State private var failed: Data?

    private enum Phase { case notFinal, unpaid, says, paid }

    private var phase: Phase {
        guard let g = store.group, [.confirmed, .delivered, .closed].contains(g.state), let b = store.myBill else { return .notFinal }
        return b.paid_at != nil ? .paid : b.proof_at != nil ? .says : .unpaid
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
        .task { await loadReceipt() }
        .sheet(isPresented: $viewing) {
            if let me = store.me { NavigationStack { ReceiptView(store: store, user: me) } }
        }
        .toast($toast, above: 84)
        .problemAlert($problem)
    }

    // MARK: Bill

    private var bill: some View {
        ScrollView {
            VStack(spacing: 14) {
                summary
                switch phase {
                case .notFinal:
                    if store.group?.payFirst == true, let p = store.payout { transfer(p, amount: nil) }
                    BillBanner(text: store.group?.payFirst == true
                               ? "Pay now so \(hostName) can order. They’ll send it to Atas once everyone has paid."
                               : "The order is in — pay when you can. We’ll tell you the final amount.",
                               fill: Brand.liquorice100, circle: .white)
                case .unpaid:
                    if let p = store.payout { transfer(p, amount: store.myBill?.total) }
                    receiptCard
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
            .padding(.horizontal, Brand.s4)
            .padding(.top, 10)
            .padding(.bottom, Brand.s4)
        }
        .screen()
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    @ViewBuilder private var bottomBar: some View {
        switch phase {
        case .notFinal:
            GlassBar { Button("I’ve paid") {}.buttonStyle(.pill(.primary)).disabled(true) }
        case .unpaid:
            if let b = store.myBill, b.total > 0 {
                GlassBar {
                    Button("I’ve paid") { Task { await claim() } }
                        .buttonStyle(.pill(.primary))
                        .disabled(busy || !["confirmed", "delivered"].contains(store.group?.state.rawValue ?? ""))
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

    /// The white card: state tags, the amount, who it goes to, and the lines that make it up.
    private var summary: some View {
        let b = store.myBill
        return VStack(alignment: .leading, spacing: 12) {
            if phase == .notFinal {
                finalTag(false)
                Text("≈ \(Rupiah.format(b?.items ?? itemLines.reduce(0) { $0 + $1.amount }))")
                    .font(Type5.roundo(46)).foregroundStyle(Brand.ink3).lineLimit(1).minimumScaleFactor(0.6)
                Text("Your items so far. Ongkir and any discount get added when Atas confirms.")
                    .font(Type5.manrope(13)).lineSpacing(1).foregroundStyle(Brand.ink2)
            } else {
                HStack {
                    finalTag(true)
                    Spacer()
                    PayTag(state: phase == .says ? .says : .unpaid)
                }
                Text(Rupiah.format(b?.total ?? 0))
                    .font(Type5.roundo(52)).tracking(52 * -0.02).foregroundStyle(Brand.cocoa).lineLimit(1).minimumScaleFactor(0.6)
                Text(subtitle).font(Type5.manrope(13)).foregroundStyle(Brand.ink2)
            }
            if phase != .says {
                VStack(spacing: 8) {
                    ForEach(itemLines) { lineRow($0, compact: phase == .notFinal) }
                    if phase == .notFinal {
                        HStack {
                            Text("Ongkir share")
                            Spacer()
                            Text("After Atas confirms")
                        }
                        .font(Type5.manrope(14, 600)).foregroundStyle(Brand.ink3)
                    } else {
                        ForEach(deliveryLines) { lineRow($0, compact: false) }
                    }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { DashedRule(color: Brand.liquorice400) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
    }

    private var subtitle: String {
        guard phase == .says, let at = store.myBill?.proof_at else { return "to \(hostName) · \(store.group?.name ?? "")" }
        let bank = store.payout.map { " · \($0.label)" } ?? ""
        return "to \(hostName)\(bank) · you marked it paid at \(Wita.string(at, "HH:mm"))"
    }

    private func lineRow(_ l: BillLine, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.label).font(Type5.manrope(14, 600)).foregroundStyle(Brand.cocoa)
                if !compact, let meta = l.meta { Text(meta).font(Type5.manrope(12)).foregroundStyle(Brand.ink3) }
            }
            Spacer(minLength: 0)
            Text(l.credit ? "− \(Rupiah.format(l.amount))" : Rupiah.format(l.amount))
                .font(Type5.manrope(14, 600)).foregroundStyle(l.credit ? Brand.limeInk : Brand.cocoa).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Lines

    struct BillLine: Identifiable {
        var id: String
        var label: String
        var meta: String?
        var amount: Int
        var credit = false
    }

    /// My items and my shares of split items, in the amounts `group_bill_v` charges: a split item's
    /// non-owners pay round(total × pct), the owner the rest.
    private var itemLines: [BillLine] {
        guard let me = store.me else { return [] }
        var out: [BillLine] = [], shared: [BillLine] = []
        for item in store.items {
            let split = store.liveSplit(item).flatMap { s -> [SplitShare]? in
                let shares = store.shares(s)
                return s.state == "accepted" && shares.allSatisfy({ $0.accepted_at != nil }) ? shares : nil
            }
            let others = (split ?? []).filter { $0.user_id != item.owner_id }
            let amount: (SplitShare) -> Int = { Int((Double(item.total) * $0.pct / 100).rounded()) }
            if item.owner_id == me {
                if others.isEmpty {
                    out.append(BillLine(id: item.id.uuidString, label: "\(item.qty)× \(item.name)", meta: "my items", amount: item.total))
                } else {
                    let mine = item.total - others.reduce(0) { $0 + amount($1) }
                    let pct = split?.first { $0.user_id == me }?.pct ?? (100 - others.reduce(0) { $0 + $1.pct })
                    out.append(BillLine(id: item.id.uuidString, label: "\(item.qty)× \(item.name) · \(percent(pct))",
                                        meta: "split with \(joinedNames(others.map { store.name($0.user_id) }))", amount: mine))
                }
            } else if let share = others.first(where: { $0.user_id == me }) {
                let rest = (split ?? []).filter { $0.user_id != me }
                let with = (rest.filter { $0.user_id == item.owner_id } + rest.filter { $0.user_id != item.owner_id }).map { store.name($0.user_id) }
                shared.append(BillLine(id: item.id.uuidString, label: "\(item.name) · \(percent(share.pct))",
                                       meta: "split with \(joinedNames(with)) · under \(store.name(item.owner_id))", amount: amount(share)))
            }
        }
        return out + shared
    }

    /// Ongkir and discount, each split equally between everyone who ordered. The two lines add up to the
    /// view's `delivery_share` (the host's line carries the rounding).
    private var deliveryLines: [BillLine] {
        guard let g = store.group, let b = store.myBill, b.items > 0, let ongkir = g.ongkir else { return [] }
        let payers = max(1, store.bill.filter { $0.items > 0 }.count)
        let discount = g.discount ?? 0
        guard discount > 0 else {
            return [BillLine(id: "ongkir", label: "Ongkir share", meta: "\(Rupiah.format(ongkir)) ÷ \(payers)", amount: b.delivery_share)]
        }
        let ongkirShare = ongkir / payers
        return [BillLine(id: "ongkir", label: "Ongkir share", meta: "\(Rupiah.format(ongkir)) ÷ \(payers)", amount: ongkirShare),
                BillLine(id: "discount", label: "Discount share", meta: "\(Rupiah.format(discount)) ÷ \(payers)",
                         amount: ongkirShare - b.delivery_share, credit: true)]
    }

    private func percent(_ p: Double) -> String { p == p.rounded() ? "\(Int(p))%" : String(format: "%g%%", p) }

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
            Button {
                copy(value, toastText, $toast)
                copied = value
            } label: {
                Image(systemName: copied == value ? "checkmark" : "square.on.square")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.cocoa)
                    .frame(width: 32, height: 32).background(Circle().fill(Brand.choc100))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    @ViewBuilder private var receiptCard: some View {
        if let failed {
            UploadFailedCard(image: UIImage(data: failed)) { Task { await send(failed) } }
                .disabled(uploading)
        } else if let at = receiptAt {
            HStack(spacing: 14) {
                Button { viewing = true } label: {
                    HStack(spacing: 14) {
                        HatchedPhoto(url: receiptURL, fill: Brand.liquorice100, ink: Brand.cocoa.opacity(0.07), band: 6)
                            .frame(width: 64, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transfer receipt").font(Type5.manrope(15, 700)).foregroundStyle(Brand.cocoa)
                            Text("Uploaded \(Wita.string(at, "HH:mm")) · tap to view").font(Type5.manrope(12)).foregroundStyle(Brand.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                PhotosPicker(selection: $photo, matching: .images) {
                    Text("Replace").font(Type5.manrope(13, 600)).foregroundStyle(Brand.caramel).frame(minHeight: 44)
                }
                .disabled(uploading)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Brand.card))
        } else {
            PhotosPicker(selection: $photo, matching: .images) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.liquorice100)
                        if uploading { ProgressView().tint(Brand.caramel) } else {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 19, weight: .medium)).foregroundStyle(Brand.cocoa)
                        }
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
            .buttonStyle(.plain)
            .disabled(uploading)
        }
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
        await send(jpeg)
    }

    /// Uploads (or replaces) my receipt. A failed upload keeps the JPEG for "Try again" (6-9).
    private func send(_ jpeg: Data) async {
        guard let me = store.me else { return }
        uploading = true
        defer { uploading = false }
        do {
            try await supabase.storage.from("receipts").upload(Receipts.path(store.id, me), data: jpeg,
                                                                options: FileOptions(contentType: "image/jpeg", upsert: true))
            failed = nil
            receiptAt = Date()
            receiptURL = await Receipts.url(store.id, me)
        } catch where isCancellation(error) {
        } catch {
            failed = jpeg
        }
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

/// 4.13 Host payment board (5-9): who paid, who says they paid, who still owes.
struct PaymentBoardView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var receipt: ReceiptRef?
    @State private var receipts: [UUID: URL] = [:]
    @State private var problem: Problem?

    private var rows: [BillRow] {
        store.bill.filter { $0.user_id != store.group?.host_id && $0.total > 0 }
            .sorted { store.colorIndex($0.user_id) < store.colorIndex($1.user_id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if rows.isEmpty {
                    EmptyStateView(pose: "pose-waiting", title: "Nobody owes you", message: "Bills appear once Atas confirms.")
                } else {
                    totals
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.user_id) { i, r in
                            row(r)
                            if i < rows.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                        }
                    }
                    .padding(.vertical, 4).padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
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
        .navigationTitle("Payments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
        .sheet(item: $receipt) { r in NavigationStack { ReceiptView(store: store, user: r.user) } }
        .task(id: store.bill.map(\.proof_at)) { await loadReceipts() }
        .problemAlert($problem)
    }

    private var footnote: String {
        let host = store.bill.first { $0.user_id == store.group?.host_id }
        var parts: [String] = []
        if let h = host, h.total > 0 { parts.append("Your own share (\(Rupiah.format(h.total))) isn’t counted.") }
        let shares = Set(rows.map(\.delivery_share)).filter { $0 > 0 }
        if shares.count == 1, let s = shares.first { parts.append("Totals include the \(Rupiah.format(s)) ongkir share on each bill.") }
        return parts.joined(separator: " ")
    }

    // MARK: Totals

    private var totals: some View {
        let paid = rows.filter { $0.paid_at != nil }.reduce(0) { $0 + $1.total }
        let says = rows.filter { $0.paid_at == nil && $0.proof_at != nil }.reduce(0) { $0 + $1.total }
        let owed = rows.filter { $0.paid_at == nil && $0.proof_at == nil }.reduce(0) { $0 + $1.total }
        let parts: [(String, Int, Color, Color)] = [("Collected", paid, Brand.limeDeep, Brand.limeDeep),
                                                    ("To check", says, Brand.choc400, Brand.choc400),
                                                    ("Outstanding", owed, Brand.liquorice100, Brand.liquorice400)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Owed to you").font(Type5.manrope(12, 600)).tracking(12 * 0.03).textCase(.uppercase).foregroundStyle(Brand.cocoa)
                Spacer()
                Text(Rupiah.format(paid + says + owed)).font(Type5.roundo(18)).foregroundStyle(Brand.cocoa)
            }
            GeometryReader { g in
                let shown = parts.filter { $0.1 > 0 }
                let width = g.size.width - CGFloat(max(0, shown.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(shown, id: \.0) { p in
                        Rectangle().fill(p.2).frame(width: width * CGFloat(p.1) / CGFloat(max(1, paid + says + owed)))
                    }
                }
            }
            .frame(height: 16)
            .background(Brand.liquorice100)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 8) {
                ForEach(parts, id: \.0) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(p.3).frame(width: 8, height: 8)
                            Text(p.0).font(Type5.manrope(11, 600)).foregroundStyle(Brand.ink2)
                        }
                        Text(Rupiah.format(p.1)).font(Type5.roundo(17)).foregroundStyle(Brand.cocoa).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Brand.card))
    }

    // MARK: Rows

    private func row(_ r: BillRow) -> some View {
        let state = PayState(r)
        return HStack(spacing: 12) {
            Avatar(name: store.name(r.user_id), index: store.colorIndex(r.user_id), size: 40, art: store.people[r.user_id]?.avatar,
                   bg: store.people[r.user_id]?.avatar_bg)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.name(r.user_id)).font(Type5.manrope(16, 700)).foregroundStyle(Brand.cocoa)
                    Spacer()
                    Text(Rupiah.format(r.total)).font(Type5.roundo(16)).foregroundStyle(Brand.cocoa)
                }
                HStack(spacing: 8) {
                    PayTag(state: state, size: .small)
                    Spacer(minLength: 0)
                    if let url = receipts[r.user_id] {
                        Button { receipt = ReceiptRef(user: r.user_id) } label: {
                            HatchedPhoto(url: url, fill: Brand.liquorice100, ink: Brand.cocoa.opacity(0.1), band: 3)
                                .frame(width: 28, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Brand.liquorice400, lineWidth: 1.5))
                                .contentShape(Rectangle().inset(by: -4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(store.name(r.user_id))’s receipt")
                    }
                    switch state {
                    case .unpaid:
                        Button("Nudge", systemImage: "bell") { Task { await act("nudge", r.user_id) } }
                            .buttonStyle(ChipStyle(fill: Brand.choc100))
                    case .says:
                        markPaid(r.user_id)
                    case .paid:
                        EmptyView()
                    }
                    if let phone = store.people[r.user_id]?.phone {
                        Button { openURL(Links.whatsApp(phone)) } label: {
                            WhatsAppGlyph(size: 14).foregroundStyle(Brand.cocoa)
                                .frame(width: 28, height: 28).background(Circle().fill(Brand.lime))
                                .contentShape(Rectangle().inset(by: -8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("WhatsApp \(store.name(r.user_id))")
                    }
                }
                .frame(minHeight: 36)
            }
        }
        .padding(.vertical, 14)
        // Cash and other off-app payments: the host can still mark an unpaid bill paid.
        .contextMenu {
            if state == .unpaid { Button("Mark paid", systemImage: "checkmark") { Task { await act("confirm_paid", r.user_id) } } }
        }
    }

    private func markPaid(_ user: UUID) -> some View {
        Button("Mark paid", systemImage: "checkmark") { Task { await act("confirm_paid", user) } }
            .buttonStyle(ChipStyle(fill: Brand.lime, ring: Brand.limeDeep))
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

    private func act(_ fn: String, _ user: UUID) async {
        await attempt($problem, fn == "nudge" ? "Couldn't nudge" : "Couldn't mark paid") {
            try await store.rpc(fn, ["g": .string(store.id.uuidString), "u": .string(user.uuidString)])
        }
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
                    Text(Rupiah.format(row?.total ?? 0)).font(Type5.roundo(30)).foregroundStyle(Brand.cream)
                }
                Spacer()
                if let row { PayTag(state: PayState(row)) }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.cocoa.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if store.isHost, let row, row.paid_at == nil {
                HStack(spacing: 10) {
                    Button("Not received") { Task { await act("reject_paid", "Couldn't tell them") } }
                        .buttonStyle(WidePill(fill: Brand.cream.opacity(0.12), ink: Brand.cream, size: 17, padding: 18))
                    Button("Mark paid", systemImage: "checkmark") { Task { await act("confirm_paid", "Couldn't mark paid") } }
                        .buttonStyle(.pill(.success))
                    .containerRelativeFrame(.horizontal) { w, _ in (w - 42) * 1.3 / 2.3 }
                }
                .disabled(busy)
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
