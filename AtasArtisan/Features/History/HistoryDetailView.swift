import SwiftUI
import Supabase

/// 6-2 History detail: state and payment tags, the delivery photo, my items with my ongkir and discount share,
/// what I paid, and "Reorder my items" (a new order for myself with my own items; splits aren't copied).
struct HistoryDetailView: View {
    let id: UUID
    @Environment(AppModel.self) private var app
    @State private var store: GroupStore
    @State private var photo: URL?
    @State private var reordering = false
    @State private var problem: Problem?

    init(id: UUID) {
        self.id = id
        _store = State(initialValue: GroupStore(id: id))
    }

    var body: some View {
        ScrollView {
            if let g = store.group {
                VStack(alignment: .leading, spacing: 14) {
                    header(g)
                    if let proof = store.proofs.filter({ !$0.hidden }).sorted(by: { $0.created_at < $1.created_at }).first {
                        deliveryPhoto(proof)
                    }
                    bill(g)
                    NavigationLink { GroupView(id: id, path: .constant(NavigationPath())) } label: {
                        Text("See the whole order").obText(.callout, 14, weight: 600, Brand.caramel).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(.horizontal, Brand.s4)
                .padding(.top, Brand.s1)
                .padding(.bottom, Brand.s5)
            } else if let error = store.loadError {
                ErrorBanner(message: error) { Task { await store.refresh() } }.padding(Brand.s4)
            } else {
                ProgressView().tint(Brand.caramel).frame(maxWidth: .infinity).padding(.top, 120)
            }
        }
        .screen()
        .navigationTitle(store.group?.name ?? "Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { presentShare([summary]) } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share this order")
                    .disabled(store.group == nil)
            }
        }
        .safeAreaInset(edge: .bottom) { if !store.myItems.isEmpty { reorderBar } }
        .task { await store.refresh(); await loadPhoto() }
        .sheet(isPresented: $reordering) {
            NavigationStack { CreateGroupView(personal: true) { newID in Task { await reorder(into: newID) } } }
        }
        .problemAlert($problem)
    }

    // MARK: Parts

    private func header(_ g: OrderGroup) -> some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack(spacing: Brand.s2) {
                StateTag(state: g.state)
                if g.state != .cancelled, let b = store.myBill, b.total > 0, !isHost { PayTag(state: PayState(b)) }
            }
            Text(g.name).obText(.display, 30).lineSpacing(-2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(meta(g)).obText(.callout, 13, Brand.ink2)
        }
        .padding(.horizontal, 4)
    }

    private func deliveryPhoto(_ proof: DeliveryProof) -> some View {
        ZStack(alignment: .bottomLeading) {
            Brand.liquorice100
            CachedPhoto(url: photo, key: proof.path, side: 400, fill: Brand.liquorice100)
            Text("\(store.name(proof.by_user)) · \(Wita.string(proof.created_at, "EEE HH:mm"))")
                .obText(.footnote, 12, weight: 600, Brand.cream)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Brand.cocoa.opacity(0.75)))
                .padding(12)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Delivery photo by \(store.name(proof.by_user))")
    }

    private func bill(_ g: OrderGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My items").brand(.label)
            let lines = itemLines
            if lines.isEmpty {
                Text("You didn't order anything in this group.").obText(.callout, 14, Brand.ink2)
            }
            ForEach(lines.indices, id: \.self) { i in
                let l = lines[i]
                HStack(spacing: 12) {
                    ProductPhoto(url: store.products[l.product]?.photo, size: 48, fill: [Brand.choc100, Brand.pink100, Brand.lime][i % 3])
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.title).obText(.headline, 14, weight: 600)
                        if let sub = l.subtitle { Text(sub).obText(.footnote, 12, Brand.ink3) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Rupiah.format(l.amount)).obText(.headline, 14, weight: 600)
                }
                .accessibilityElement(children: .combine)
            }
            if let b = store.myBill, b.total > 0, g.state != .cancelled {
                VStack(spacing: 6) {
                    let (ongkir, discount) = shares(g, b)
                    if ongkir > 0 { totalLine("Ongkir share", Rupiah.format(ongkir), Brand.ink2) }
                    if discount > 0 { totalLine("Discount share", "− " + Rupiah.format(discount), Brand.limeInk) }
                    HStack(alignment: .firstTextBaseline) {
                        Text(totalTitle(b)).obText(.headline, 15)
                        Spacer()
                        Text(Rupiah.format(b.total)).obText(.display, 22)
                    }
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                }
                .padding(.top, 10)
                .overlay(alignment: .top) {
                    Line().stroke(Brand.liquorice400, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
                }
            } else if g.state == .cancelled {
                Text("This order was cancelled. Nobody paid anything.").obText(.callout, 13, Brand.ink2)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        Line().stroke(Brand.liquorice400, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
                    }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.card))
    }

    private func totalLine(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack { Text(label); Spacer(); Text(value) }.obText(.callout, 13, color)
    }

    private var reorderBar: some View {
        VStack(spacing: 0) {
            Button { reordering = true } label: { Label("Reorder my items", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(.pill(.primary))
            Text(reorderNote).obText(.footnote, 12, Brand.ink2).multilineTextAlignment(.center)
                .padding(.top, Brand.s2).padding(.bottom, 2)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .padding(.horizontal, 12)
    }

    // MARK: Data

    private struct ItemLine { var product: String; var title: String; var subtitle: String?; var amount: Int }

    /// My own items (my part when shared), then my pieces of other people's shared items.
    private var itemLines: [ItemLine] {
        var out: [ItemLine] = []
        for item in store.items.sorted(by: { $0.name < $1.name }) {
            let claims = store.claims(item)
            let pieces = item.share_pieces ?? 0
            if item.owner_id == store.me {
                if claims.isEmpty {
                    out.append(ItemLine(product: item.product_id, title: "\(item.qty)× \(item.name)", subtitle: nil, amount: item.total))
                } else {
                    out.append(ItemLine(product: item.product_id, title: "\(item.name) · \(store.piecesLeft(item)) of \(pieces) pieces",
                                        subtitle: "shared \(claims.count + 1) ways",
                                        amount: Pieces.ownerAmount(price: item.total, pieces: pieces, claims: claims.map(\.pieces))))
                }
            } else if let mine = claims.first(where: { $0.user_id == store.me }) {
                out.append(ItemLine(product: item.product_id, title: "\(item.name) · \(mine.pieces) of \(pieces) pieces",
                                    subtitle: "under \(store.name(item.owner_id)) · shared \(claims.count + 1) ways",
                                    amount: Pieces.amount(price: item.total, pieces: pieces, n: mine.pieces)))
            }
        }
        return out
    }

    private var isHost: Bool { store.group?.host_id == store.me }

    private func meta(_ g: OrderGroup) -> String {
        let date = Wita.string(g.delivery_at, "EEE d MMM yyyy")
        if g.personal { return "\(date) · just me" }
        let n = store.activeMembers.count
        let host = isHost ? "hosted by you" : "hosted by \(store.name(g.host_id))"
        return "\(date) · \(host) · \(n) \(n == 1 ? "person" : "people")"
    }

    /// Splits my `delivery_share` (ongkir − discount, divided equally among payers by `group_bill_v`) back into
    /// its two halves. The ongkir half is ongkir ÷ payers (the host also takes the remainder, as the view does);
    /// the discount half is whatever makes them add up to the server's figure exactly.
    private func shares(_ g: OrderGroup, _ b: BillRow) -> (ongkir: Int, discount: Int) {
        let payers = store.bill.filter { $0.items > 0 }.count
        let ongkir = g.ongkir ?? 0
        guard payers > 0, ongkir > 0, b.items > 0 else { return (b.delivery_share, 0) }
        let each = ongkir / payers
        let mine = isHost ? ongkir - (payers - 1) * each : each
        return (mine, max(0, mine - b.delivery_share))
    }

    private func totalTitle(_ b: BillRow) -> String {
        if isHost || store.group?.personal == true { return "Your total" }
        let host = store.name(store.group?.host_id ?? UUID())
        return b.paid_at != nil ? "Paid to \(host)" : "Owed to \(host)"
    }

    private var reorderNote: String {
        let mine = store.myItems
        let list = mine.map { "\($0.name) ×\($0.qty)" }.joined(separator: ", ")
        let shared = store.items.contains { $0.share_pieces != nil }
        return "Adds \(list) to a new order." + (shared ? " Sharing isn’t copied." : "")
    }

    private var summary: String {
        guard let g = store.group else { return "" }
        var lines = ["\(g.name) · \(Wita.string(g.delivery_at, "EEE d MMM yyyy"))"]
        lines += itemLines.map { "\($0.title): \(Rupiah.format($0.amount))" }
        if let b = store.myBill, b.total > 0, g.state != .cancelled { lines.append("\(totalTitle(b)): \(Rupiah.format(b.total))") }
        return lines.joined(separator: "\n")
    }

    private func loadPhoto() async {
        guard let p = store.proofs.filter({ !$0.hidden }).sorted(by: { $0.created_at < $1.created_at }).first else { return }
        photo = try? await supabase.storage.from("delivery").createSignedURL(path: p.path, expiresIn: 3600)
    }

    /// Copies my own items (not splits) into the order just created, then opens it on Home.
    private func reorder(into newID: UUID) async {
        var missing: [String] = []
        for item in store.myItems {
            do {
                try await supabase.from("items").insert(NewItem(group_id: newID, product_id: item.product_id, options: item.options,
                                                                qty: item.qty, note: item.note)).execute()
            } catch {
                missing.append(item.name)
            }
        }
        reordering = false
        app.homeVersion += 1
        app.openGroup = newID
        if !missing.isEmpty {
            problem = Problem(title: "Some items weren't added",
                              message: "\(missing.joined(separator: ", ")) couldn't be added. They may be sold out or off the menu today.")
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
