import SwiftUI
import Supabase

/// 4.7 Menu, scraped from atasartisan.com by the VPS (twice a day). Collections as tabs, search, product grid.
struct MenuView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var collections: [Collection] = []
    @State private var products: [Product] = []
    @State private var synced: Date?
    @State private var tab: String?
    @State private var query = ""
    @State private var picked: Product?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s4) {
                if let synced, Date().timeIntervalSince(synced) > 26 * 3600 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.caramel)
                        Text("Menu last updated \(synced, style: .relative) ago. Prices or stock may have changed.").brand(.footnote)
                    }
                    .card(Brand.rSmall, padding: Brand.s3).background(RoundedRectangle(cornerRadius: Brand.rSmall).fill(Brand.choc100))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Brand.s2) {
                        ForEach(collections) { c in
                            Button(c.name) { tab = c.id }
                                .buttonStyle(.pill(tab == c.id ? .dark : .secondary, .small))
                        }
                    }
                }
                if let synced { Text("Menu updated \(synced, style: .relative) ago").brand(.footnote, Brand.ink3) }
                if !loaded {
                    ProgressView().tint(Brand.caramel).frame(maxWidth: .infinity)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Brand.s3), GridItem(.flexible(), spacing: Brand.s3)], spacing: Brand.s3) {
                    ForEach(shown) { p in
                        Button { picked = p } label: { ProductCard(product: p) }.buttonStyle(.plain).disabled(!p.available)
                    }
                }
            }
            .padding(Brand.s4)
        }
        .screen()
        .searchable(text: $query, prompt: "Search croissant, sourdough…")
        .navigationTitle("Atas Artisan menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await load() }
        .sheet(item: $picked) { p in NavigationStack { ProductView(store: store, product: p) } }
    }

    private var shown: [Product] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { return products.filter { $0.name.lowercased().contains(q) } }
        return products.filter { $0.collection_id == tab }
    }

    private func load() async {
        collections = (try? await supabase.from("collections").select().order("sort").execute().value) ?? []
        products = (try? await supabase.from("products").select().order("sort").execute().value) ?? []
        nonisolated struct Meta: Decodable { var synced_at: Date }
        synced = (try? await supabase.from("menu_meta").select().single().execute().value as Meta)?.synced_at
        tab = tab ?? collections.first?.id
        loaded = true
    }
}

struct ProductCard: View {
    var product: Product
    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            ZStack(alignment: .topLeading) {
                ProductPhoto(url: product.photo, size: 120, fill: product.available ? Brand.choc100 : Brand.liquorice100)
                    .frame(maxWidth: .infinity)
                if !product.available { Tag(text: "Sold out", fill: Brand.liquorice100) }
            }
            Text(product.name).brand(.headline).lineLimit(2).frame(minHeight: 44, alignment: .topLeading)
            HStack {
                Text((product.variants.count > 1 ? "from " : "") + Rupiah.format(product.fromPrice)).brand(.callout)
                Spacer()
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.cocoa)
                    .frame(width: 28, height: 28).background(Circle().fill(Brand.choc100))
            }
        }
        .card(Brand.rCard, padding: Brand.s3)
        .opacity(product.available ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

/// 4.8 Product detail: option groups as pill rows; price follows the pick. Only combinations Atas
/// actually sells are offered (the server refuses anything else in price_item()).
struct ProductView: View {
    var store: GroupStore
    var product: Product
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String: String] = [:]
    @State private var qty = 1
    @State private var note = ""
    @State private var busy = false
    @State private var problem: Problem?

    private var variants: [VariantChoice] {
        product.variants.map { VariantChoice(options: $0.options, price: $0.price, available: $0.available ?? true) }
    }
    private var groups: [OptionGroup] { product.variants.isEmpty ? [] : product.option_groups }
    private var price: Int? {
        if product.variants.isEmpty { return product.base_price }
        return OptionMatch.variant(picked, groups: groups.map(\.name), variants: variants)?.price
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s4) {
                ProductPhoto(url: product.photo, size: 230).frame(maxWidth: .infinity).padding(.vertical, Brand.s3)
                HStack(alignment: .firstTextBaseline) {
                    Text(product.name).brand(.title1)
                    Spacer()
                    Text(price.map(Rupiah.format) ?? "—").brand(.title2)
                }
                if !product.description.isEmpty && product.description != "Click for more size" {
                    Text(product.description).brand(.body, Brand.ink2)
                }
                ForEach(groups, id: \.name) { g in
                    VStack(alignment: .leading, spacing: Brand.s2) {
                        Text(g.name == "Berat" ? "Weight" : g.name == "Rasa" ? "Flavour" : g.name).brand(.label)
                        let allowed = OptionMatch.choices(g.name, all: g.choices, picked: picked, variants: variants)
                        FlowRow {
                            ForEach(g.choices, id: \.self) { c in
                                Button(c) { picked[g.name] = c }
                                    .buttonStyle(.pill(picked[g.name] == c ? .dark : .secondary, .small))
                                    .disabled(!allowed.contains(c))
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Brand.s2) {
                    Text("Note for Atas").brand(.label)
                    TextField("e.g. warm it up if you can", text: $note)
                        .padding(Brand.s3).background(RoundedRectangle(cornerRadius: Brand.rField).fill(.white))
                }
                HStack {
                    Text("Quantity").brand(.headline)
                    Spacer()
                    QtyStepper(qty: qty) { qty = max(1, $0) }
                }
            }
            .padding(Brand.s4)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            Button("Add to my order\(price.map { " · " + Rupiah.format($0 * qty) } ?? "")") { Task { await add() } }
                .buttonStyle(.pill(.primary))
                .disabled(price == nil || busy || !product.available)
                .padding(Brand.s4)
                .glassEffect(.regular.tint(Brand.cream.opacity(0.4)), in: .rect(cornerRadius: Brand.rHero))
                .padding(.horizontal, Brand.s3)
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onAppear { if picked.isEmpty { picked = OptionMatch.defaultPick(variants: variants) } }
        .problemAlert($problem)
    }

    private func add() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't add it") {
            try await store.add(product: product, options: product.variants.isEmpty ? [:] : picked, qty: qty, note: note.trimmingCharacters(in: .whitespaces))
            dismiss()
        }
    }
}

/// Wrapping row of pills.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing
            row = max(row, sz.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            row = max(row, sz.height)
        }
    }
}
