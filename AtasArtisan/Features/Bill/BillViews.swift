import SwiftUI
import PhotosUI
import Supabase

/// 4.13 Member bill (GoodMinton's two-column rule: proof_at = "I've paid", paid_at = host confirmed).
struct BillView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var uploaded = false
    @State private var busy = false
    @State private var copied: String?
    @State private var toast: String?
    @State private var problem: Problem?

    var body: some View {
        let bill = store.myBill
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s4) {
                VStack(alignment: .leading, spacing: Brand.s2) {
                    Text("You owe \(store.name(store.group?.host_id ?? UUID()))").brand(.label, Brand.ink3)
                    Text(Rupiah.format(bill?.total ?? 0)).brand(.hero)
                    if let bill { PayTag(state: PayState(bill)) }
                }
                VStack(alignment: .leading, spacing: Brand.s2) {
                    ForEach(store.myItems) { i in line("\(i.qty)× \(i.name)", i.total) }
                    ForEach(splitLines, id: \.0) { line($0.0, $0.1) }
                    line("Ongkir − discount, your share", bill?.delivery_share ?? 0)
                    Divider()
                    line("Total", bill?.total ?? 0).bold()
                }
                .card()
                if store.group?.state == .sent || store.group?.state == .locked {
                    Text("The bill isn't final until Atas confirms the ongkir.").brand(.callout, Brand.ink2)
                }
                if let p = store.payout {
                    VStack(alignment: .leading, spacing: Brand.s3) {
                        Text("Pay to").brand(.label)
                        copyRow(p.label, nil)
                        copyRow(p.account_name, "Account name")
                        copyRow(p.number, "Account number")
                    }
                    .card()
                }
                VStack(alignment: .leading, spacing: Brand.s3) {
                    Text("Transfer receipt").brand(.label)
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(uploaded || bill?.proof_at != nil ? "Replace receipt" : "Upload transfer receipt", systemImage: "photo")
                    }
                    .buttonStyle(.pill(.secondary, .medium))
                    if uploaded || bill?.proof_at != nil { Label("Receipt uploaded", systemImage: "checkmark.circle.fill").brand(.callout, Color(rgb: 0x5E7A00)) }
                }
                .card()
            }
            .padding(Brand.s4)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            if let bill, bill.paid_at == nil, bill.total > 0 {
                Button(bill.proof_at == nil ? "I've paid" : "Tell the host again") { Task { await claim() } }
                    .buttonStyle(.pill(.primary)).disabled(busy || !(["confirmed", "delivered"].contains(store.group?.state.rawValue ?? "")))
                    .padding(Brand.s4)
            }
        }
        .navigationTitle("Your bill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onChange(of: photo) { _, item in if let item { Task { await upload(item) } } }
        .toast($toast, above: 84)
        .problemAlert($problem)
    }

    /// My shares of other people's split items.
    private var splitLines: [(String, Int)] {
        store.items.compactMap { item in
            guard item.owner_id != store.me, let s = store.liveSplit(item), s.state == "accepted" else { return nil }
            let shares = store.shares(s).sorted { a, _ in a.user_id == item.owner_id }
            guard shares.allSatisfy({ $0.accepted_at != nil }), let idx = shares.firstIndex(where: { $0.user_id == store.me }) else { return nil }
            return ("Share of \(item.name) (\(Int(shares[idx].pct))%)", Shares.amounts(total: item.total, pcts: shares.map(\.pct))[idx])
        }
    }

    private func line(_ label: String, _ n: Int) -> some View {
        HStack { Text(label).brand(.callout); Spacer(); Text(Rupiah.format(n)).brand(.callout) }
    }

    private func copyRow(_ value: String, _ caption: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if let caption { Text(caption).brand(.footnote, Brand.ink3) }
                Text(value).brand(.headline)
            }
            Spacer()
            IconCircle(symbol: copied == value ? "checkmark" : "doc.on.doc") {
                copy(value, caption == "Account number" ? "Account number copied" : "Copied", $toast)
                copied = value
            }
            .accessibilityLabel("Copy \(caption ?? value)")
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Upload failed") {
            guard let data = try await item.loadTransferable(type: Data.self), let jpeg = JPEG.compress(data) else { throw UploadError.unreadable }
            guard let me = store.me else { return }
            try await supabase.storage.from("receipts").upload("\(store.id.uuidString.lowercased())/\(me.uuidString.lowercased()).jpg", data: jpeg,
                                                                options: FileOptions(contentType: "image/jpeg", upsert: true))
            uploaded = true
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

/// 4.13 Host payment board.
struct PaymentBoardView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var receipt: ReceiptRef?
    @State private var problem: Problem?

    private var rows: [BillRow] {
        store.bill.filter { $0.user_id != store.group?.host_id && $0.total > 0 }
            .sorted { store.colorIndex($0.user_id) < store.colorIndex($1.user_id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s4) {
                let collected = rows.filter { $0.paid_at != nil }.reduce(0) { $0 + $1.total }
                let outstanding = rows.filter { $0.paid_at == nil }.reduce(0) { $0 + $1.total }
                HStack {
                    VStack(alignment: .leading) { Text("Collected").brand(.label, Brand.ink3); Text(Rupiah.format(collected)).brand(.title2) }
                    Spacer()
                    VStack(alignment: .trailing) { Text("Outstanding").brand(.label, Brand.ink3); Text(Rupiah.format(outstanding)).brand(.title2, Brand.caramel) }
                }
                .card()
                ForEach(rows, id: \.user_id) { r in
                    VStack(alignment: .leading, spacing: Brand.s3) {
                        HStack(spacing: Brand.s3) {
                            Avatar(name: store.name(r.user_id), index: store.colorIndex(r.user_id), art: store.people[r.user_id]?.avatar)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(store.name(r.user_id)).brand(.headline)
                                Text(Rupiah.format(r.total)).brand(.callout, Brand.ink2)
                            }
                            Spacer()
                            PayTag(state: PayState(r))
                        }
                        HStack(spacing: Brand.s2) {
                            if r.proof_at != nil {
                                Button("Receipt") { receipt = ReceiptRef(user: r.user_id) }.buttonStyle(.pill(.secondary, .small))
                            }
                            if r.paid_at == nil {
                                Button("Mark paid") { Task { await act("confirm_paid", r.user_id) } }.buttonStyle(.pill(.success, .small))
                                Button("Nudge") { Task { await act("nudge", r.user_id) } }.buttonStyle(.pill(.secondary, .small))
                            }
                            Spacer()
                            if let phone = store.people[r.user_id]?.phone {
                                IconCircle(symbol: "message.fill", fill: Brand.lime) { openURL(Links.whatsApp(phone)) }
                                    .accessibilityLabel("WhatsApp \(store.name(r.user_id))")
                            }
                        }
                    }
                    .card()
                }
                if rows.isEmpty { EmptyStateView(pose: "pose-waiting", title: "Nobody owes you", message: "Bills appear once Atas confirms.") }
            }
            .padding(Brand.s4)
        }
        .screen()
        .navigationTitle("Payments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $receipt) { r in NavigationStack { ReceiptView(group: store.id, user: r.user, name: store.name(r.user)) } }
        .problemAlert($problem)
    }

    private func act(_ fn: String, _ user: UUID) async {
        await attempt($problem, fn == "nudge" ? "Couldn't nudge" : "Couldn't mark paid") {
            try await store.rpc(fn, ["g": .string(store.id.uuidString), "u": .string(user.uuidString)])
        }
    }
}

struct ReceiptRef: Identifiable { var user: UUID; var id: UUID { user } }

struct ReceiptView: View {
    var group: UUID
    var user: UUID
    var name: String
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
        }
        .navigationTitle("\(name)'s receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            url = try? await supabase.storage.from("receipts")
                .createSignedURL(path: "\(group.uuidString.lowercased())/\(user.uuidString.lowercased()).jpg", expiresIn: 300)
        }
    }
}
