import SwiftUI
import Supabase

/// 4.7 Menu (3-9 to 3-11), scraped from atasartisan.com by the VPS twice a day. Search and collection tabs stay
/// on top; every collection is a section of one scrolling grid, and the tab follows the scroll. A dark floating
/// bar shows what I have in the order and opens My order (3-12).
struct MenuView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var collections: [Collection] = []
    @State private var products: [Product] = []
    @State private var synced: Date?
    /// The section at the top of the scroll, read from the scroll offset (never written back to it).
    @State private var section: String?
    /// The tab just tapped, shown while the scroll animates to it.
    @State private var jump: String?
    /// Each section's top in the scroll content.
    @State private var tops: [String: CGFloat] = [:]
    @State private var query = ""
    @State private var picked: Product?
    @State private var loaded = false
    @State private var failed: String?
    @State private var showCart = false
    @State private var width: CGFloat = 402
    /// Basket changes while the bar shows (it bumps).
    @State private var cartBumps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !loaded {
                MenuSkeleton()
            } else if let failed, products.isEmpty {
                EmptyStateView(pose: "pose-confused", fill: Brand.pink100, title: "The oven didn't answer.", message: failed,
                               actionTitle: "Try again") { Task { await load() } }
                    .frame(maxHeight: .infinity)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Brand.cream.ignoresSafeArea())
        .toolbarBackground(Brand.cream, for: .navigationBar)
        .navigationTitle("Atas Artisan menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }.tint(Brand.cocoa)
            }
        }
        .task {
            if DebugScreens.value("ATASTE_MENU") == "skeleton" { return }
            await load()
            debugHooks()
        }
        .sheet(item: $picked) { p in
            NavigationStack { ProductView(store: store, product: p, alternatives: alternatives(to: p)) }
        }
        .sheet(isPresented: $showCart) { MyOrderView(store: store) }
    }

    // MARK: Content

    private var content: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    if let synced, isStale(synced) {
                        NoticeBanner(icon: "exclamationmark.triangle",
                                     text: "Menu last updated \(staleWhen(synced)). Prices or stock may have changed.",
                                     fill: Brand.choc100, actionTitle: "Refresh") { Task { await load() } }
                    }
                    searchField
                    if query.isEmpty { tabs(proxy) }
                }
                .padding(.horizontal, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if query.isEmpty {
                            if let synced, !isStale(synced) {
                                Label { Text("Menu updated \(ago(synced))") } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                                    .labelStyle(UpdatedLabel())
                                    .font(MenuFont.manrope(12)).foregroundStyle(Brand.ink3)
                                    .padding(.leading, 4)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(s.name).brand(.label).padding(.top, i == 0 ? 8 : 12).padding(.leading, 4)
                                            .accessibilityAddTraits(.isHeader)
                                        grid(s.products)
                                    }
                                    .id("section:" + s.id)
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("menu")).minY } action: { tops[s.id] = $0 }
                                    .onDisappear { tops[s.id] = nil }
                                }
                            }
                        } else if results.isEmpty {
                            EmptyStateView(pose: "pose-confused", fill: Brand.pink100, size: 120, title: "Nothing by that name",
                                           message: "Atas doesn't have \u{201C}\(query)\u{201D} on today's menu.")
                        } else {
                            grid(results)
                        }
                    }
                    .coordinateSpace(.named("menu"))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
                .onScrollGeometryChange(for: String?.self) { g in
                    // At the bottom the last section can be too short to reach the top; it is still the one being read.
                    if g.visibleRect.maxY >= g.contentSize.height - 1, let last = tops.max(by: { $0.value < $1.value }) { return last.key }
                    return tops.filter { $0.value <= g.visibleRect.minY + 8 }.max(by: { $0.value < $1.value })?.key
                } action: { _, id in withAnimation(.snappy) { section = id } }
                .onScrollPhaseChange { _, phase in if phase != .animating { withAnimation(.snappy) { jump = nil } } }
                .scrollDismissesKeyboard(.immediately)
            }
            .padding(.top, 4)
            .overlay(alignment: .bottom) { cartBar }
            .onChange(of: [cart.count, cart.total]) { old, new in if old[0] > 0 && new[0] > 0 { cartBumps += 1 } }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(Brand.ink3)
            TextField("Search the menu", text: $query,
                      prompt: Text("Search croissant, sourdough\u{2026}").foregroundStyle(Brand.ink4))
                .font(MenuFont.manrope(15)).foregroundStyle(Brand.cocoa).tint(Brand.caramel)
                .submitLabel(.search).autocorrectionDisabled()
            if !query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly).foregroundStyle(Brand.ink4)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Capsule().fill(.white))
        .overlay(Capsule().strokeBorder(Brand.liquorice100, lineWidth: 1.5))
    }

    /// `menu` scrolls the list. Section ids carry a prefix because each tab's ForEach id is the bare section id and
    /// `scrollTo` takes the first scroll view holding a match. The strip keeps its own reader to centre the tab.
    private func tabs(_ menu: ScrollViewProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sections) { s in
                        let on = (jump ?? section ?? sections.first?.id) == s.id
                        Button { withAnimation(.snappy) { jump = s.id; menu.scrollTo("section:" + s.id, anchor: .top) } } label: {
                            Text(s.name).font(MenuFont.manrope(14, 600)).lineLimit(1)
                                .foregroundStyle(on ? Brand.cream : Brand.cocoa)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(Capsule().fill(on ? Brand.cocoa : .white))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id("tab:" + s.id)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.trailing, 16)
            }
            .padding(.trailing, -16)
            .onChange(of: jump ?? section) { _, id in if let id { withAnimation(.snappy) { proxy.scrollTo("tab:" + id, anchor: .center) } } }
        }
    }

    private func grid(_ items: [Product]) -> some View {
        let photo = min(150, (width - 32 - 12) / 2 - 24)
        let counts = Dictionary(store.myItems.map { ($0.product_id, $0.qty) }, uniquingKeysWith: +)
        // ponytail: eager Grid, not LazyVGrid. Lazy grids nested in one scroll only estimate the rows not yet built,
        // so the content height shifted under the finger and threw the scroll back to the top. The menu is about 35
        // products and lays out in full cheaply; go back to lazy (with fixed card heights) if it grows to hundreds.
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                GridRow {
                    ForEach(items[i..<min(i + 2, items.count)]) { p in
                        Button { picked = p } label: { ProductCard(product: p, photo: photo, inOrder: counts[p.id] ?? 0) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Floating cart

    /// My item count and total.
    private var cart: (count: Int, total: Int) {
        (store.myItems.reduce(0) { $0 + $1.qty }, store.myItems.reduce(0) { $0 + $1.total })
    }

    /// Rises in with the first item (`Motion.arrive`) and drops away with the last (`Motion.leave`). Each change bumps
    /// it: the count rolls and the total counts to the new amount.
    @ViewBuilder private var cartBar: some View {
        let (count, total) = cart
        ZStack {
            if count > 0 {
                Button { showCart = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bag").font(.system(size: 18, weight: .medium))
                        Text(count == 1 ? "1 item" : "\(count) items").font(MenuFont.manrope(15, 600))
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
                            .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: count)
                        CountUp(amount: total) { Text(Rupiah.format($0)) }.font(MenuFont.roundo(15))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(Brand.caramel))
                    }
                    .foregroundStyle(Brand.cream)
                    .padding(.leading, 20).padding([.trailing, .vertical], 8)
                    .background(Capsule().fill(Brand.cocoa))
                    .shadow(color: Brand.cocoa.opacity(0.35), radius: 15, y: 12)
                    .contentShape(Capsule())
                }
                .buttonStyle(DoughStyle(squash: Motion.pressCompact))
                .kick(reduceMotion ? 0 : cartBumps, from: BasketMotion.bumpFrom)
                .padding(.bottom, 6)
                .accessibilityLabel("My order, \(count == 1 ? "1 item" : "\(count) items"), \(Rupiah.format(total))")
                .transition(reduceMotion ? .opacity.animation(Motion.Reduced.fade)
                            : .asymmetric(insertion: AnyTransition.offset(y: BasketMotion.hiddenOffset).combined(with: .opacity).animation(Motion.arrive),
                                          removal: AnyTransition.offset(y: BasketMotion.hiddenOffset).combined(with: .opacity).animation(Motion.leave)))
            }
        }
    }

    // MARK: Data

    private struct Section: Identifiable { var id: String; var name: String; var products: [Product] }

    private var sections: [Section] {
        var out = collections.map { c in Section(id: c.id, name: c.name, products: products.filter { $0.collection_id == c.id }) }
        let known = Set(collections.map(\.id))
        let loose = products.filter { $0.collection_id.map { !known.contains($0) } ?? true }
        if !loose.isEmpty { out.append(Section(id: "more", name: "More", products: loose)) }
        return out.filter { !$0.products.isEmpty }
    }

    private var results: [Product] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return products.filter { $0.name.lowercased().contains(q) }
    }

    private var mine: Set<String> { Set(store.myItems.map(\.product_id)) }

    /// "Try Pain Au Chocolate or Butter Croissant": two available products from the same collection.
    private func alternatives(to p: Product) -> [String] {
        guard !p.available else { return [] }
        return products.filter { $0.collection_id == p.collection_id && $0.available && $0.id != p.id }.prefix(2).map(\.name)
    }

    private func isStale(_ d: Date) -> Bool { Date().timeIntervalSince(d) > 26 * 3600 }

    private func ago(_ d: Date) -> String {
        if Date().timeIntervalSince(d) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = Locale(identifier: "en_GB")
        return f.localizedString(for: d, relativeTo: Date())
    }

    /// "yesterday, 12:10" or "Mon 29 Sep, 12:10", Bali time.
    private func staleWhen(_ d: Date) -> String {
        Wita.calendar.isDateInYesterday(d) ? "yesterday, " + Wita.string(d, "HH:mm") : Wita.string(d, "EEE d MMM, HH:mm")
    }

    private func load() async {
        do {
            async let c: [Collection] = supabase.from("collections").select().order("sort").execute().value
            async let p: [Product] = supabase.from("products").select().order("sort").execute().value
            nonisolated struct Meta: Decodable { var synced_at: Date }
            async let m: Meta? = try? supabase.from("menu_meta").select().single().execute().value
            (collections, products, synced) = try await (c, p, m?.synced_at)
            failed = nil
        } catch where isCancellation(error) {
            return
        } catch {
            failed = readable(error)
        }
        loaded = true
    }

    /// DEBUG screenshot hooks (compiled to nil in release): ATASTE_MENU = skeleton | stale | cart | soldout (marks ATASTE_PRODUCT sold out locally),
    /// ATASTE_PRODUCT = part of a product name.
    private func debugHooks() {
        switch DebugScreens.value("ATASTE_MENU") {
        case "stale": synced = Wita.calendar.date(bySettingHour: 12, minute: 10, second: 0, of: Date().addingTimeInterval(-86_400))
        case "cart": showCart = true
        default: break
        }
        if let name = DebugScreens.value("ATASTE_PRODUCT")?.lowercased(),
           let i = products.firstIndex(where: { $0.name.lowercased().contains(name) }) {
            if DebugScreens.value("ATASTE_MENU") == "soldout" { products[i].available = false }
            picked = products[i]
        }
    }
}

/// Icon and text 6 pt apart (the "Menu updated" line).
private struct UpdatedLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.system(size: 11, weight: .semibold)); configuration.title }
    }
}

/// One product in the grid: photo in its dashed ring, name, price, and a round button that reads the state
/// (plus; lime check when it's already in my order; x when sold out).
/// Adding it turns the button lime with a check that pops in; adding more of it bumps the check.
struct ProductCard: View {
    var product: Product
    var photo: CGFloat = 150
    /// How many of it are in my order.
    var inOrder = 0
    @State private var again = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let soldOut = !product.available
        VStack(alignment: .leading, spacing: 10) {
            ProductPhoto(url: product.photo, size: photo, fill: soldOut ? Brand.liquorice100 : Brand.choc100)
                .grayscale(soldOut ? 0.8 : 0)
                .overlay(alignment: .topLeading) {
                    if soldOut { Tag(text: "Sold out", fill: Brand.liquorice100, size: .small).offset(x: -2, y: -2) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let badge = product.choiceBadge { ChoiceBadge(text: badge).offset(x: 4, y: -6) }
                }
                .frame(maxWidth: .infinity)
            Text(product.name).font(MenuFont.manrope(15, 700)).foregroundStyle(Brand.cocoa)
                .lineSpacing(1).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            HStack(alignment: .bottom) {
                Text(priceText).font(MenuFont.roundo(16)).foregroundStyle(Brand.cocoa).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                PopSymbol(name: soldOut ? "xmark" : inOrder > 0 ? "checkmark" : "plus", animation: Motion.pop.delay(StepperMotion.addCheckDelay))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.cocoa)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle().fill(soldOut ? Brand.liquorice100 : inOrder > 0 ? Brand.lime : Brand.choc100)
                            .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick, value: inOrder > 0)
                            .geometryGroup()
                    }
                    .kick(reduceMotion ? 0 : again, from: StepperMotion.againBump)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 14, trailing: 12))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
        .opacity(soldOut ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([product.name, product.choiceBadge, priceText, soldOut ? "Sold out" : inOrder > 0 ? "In your order" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .onChange(of: inOrder) { old, new in if old > 0 && new > old { again += 1 } }
    }

    /// "from Rp 21.000" only when the variants really differ in price.
    private var priceText: String {
        let prices = Set(product.variants.map(\.price))
        return (prices.count > 1 ? "from " : "") + Rupiah.format(product.fromPrice)
    }
}

/// I-1: "4 flavours" on a product with a choice. White pill, 1.5 pt liquorice ring, soft cocoa shadow, Manrope 600 10
/// uppercase.
private struct ChoiceBadge: View {
    var text: String
    var body: some View {
        Text(text).font(MenuFont.manrope(10, 600)).tracking(0.3).textCase(.uppercase).foregroundStyle(Brand.cocoa)
            .lineLimit(1).fixedSize()
            .padding(.vertical, 3).padding(.horizontal, 10)
            .background(Capsule().fill(.white))
            .overlay(Capsule().strokeBorder(Brand.liquorice400, lineWidth: 1.5))
            .shadow(color: Brand.cocoa.opacity(0.12), radius: 3, y: 2)
    }
}

/// 3-11: the menu's shape in liquorice while it loads, and "Asking the oven…".
struct MenuSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(.white).frame(height: 46)
                HStack(spacing: 8) {
                    ForEach([110, 70, 120], id: \.self) { w in Capsule().fill(Brand.liquorice100).frame(width: CGFloat(w), height: 36) }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach([0.6, 0.4, 0.7, 0.5], id: \.self) { w in card(w) }
                }
                .padding(.top, 20)
                Text("Asking the oven\u{2026}").font(MenuFont.roundo(17)).foregroundStyle(Brand.ink3)
                    .frame(maxWidth: .infinity).padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the menu")
    }

    private func card(_ w: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Circle().fill(Brand.liquorice100).padding(8)
                .overlay(Circle().strokeBorder(Brand.liquorice400, style: StrokeStyle(lineWidth: 1.5, dash: [4.5, 3])))
                .frame(width: 150, height: 150)
                .frame(maxWidth: .infinity)
            Capsule().fill(Brand.liquorice100).frame(height: 14)
            GeometryReader { g in Capsule().fill(Brand.liquorice100).frame(width: g.size.width * w) }.frame(height: 14)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }
}
