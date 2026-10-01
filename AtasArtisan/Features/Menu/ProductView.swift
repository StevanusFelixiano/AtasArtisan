import SwiftUI

/// 4.8 Product detail (3-13 to 3-16): the photo on a pastel hero, name and price, option groups as pills with the
/// price each choice leads to, a note for Atas and the quantity. Only combinations Atas actually sells are
/// offered (the server refuses anything else in price_item()). Option groups with a single choice are fixed,
/// so they are not shown.
struct ProductView: View {
    var store: GroupStore
    var product: Product
    /// Available products to suggest when this one is sold out.
    var alternatives: [String] = []
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
    private var shownGroups: [OptionGroup] { groups.filter { $0.choices.count > 1 } }
    private var hasOptions: Bool { !shownGroups.isEmpty }
    private var soldOut: Bool { !product.available }
    private var price: Int? {
        if product.variants.isEmpty { return product.base_price }
        return OptionMatch.variant(picked, groups: groups.map(\.name), variants: variants)?.price
    }
    private var priceText: String { price.map(Rupiah.format) ?? "\u{2014}" }
    private var totalText: String { price.map { Rupiah.format($0 * qty) } ?? "\u{2014}" }
    private var showSplitHint: Bool {
        !soldOut && store.group?.personal == false && store.activeMembers.count > 1 && (price ?? 0) >= 100_000
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                details.padding(.horizontal, 20).padding(.top, hasOptions ? 22 : 24).padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Brand.cream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { actionBar }
        .navigationTitle(product.name)
        .toolbar(removing: .title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.tint(Brand.cocoa) }
            ToolbarItem(placement: .primaryAction) {
                Button("Share", systemImage: "square.and.arrow.up") {
                    presentShare(["\(product.name) \u{00B7} \(priceText) from Atas Artisan\nhttps://www.atasartisan.com"])
                }
                .tint(Brand.cocoa)
            }
        }
        .onAppear { if picked.isEmpty { picked = OptionMatch.defaultPick(variants: variants) } }
        .problemAlert($problem)
    }

    // MARK: Hero

    private var hero: some View {
        let size: CGFloat = hasOptions ? 200 : 250
        let fill = soldOut ? Brand.liquorice100 : Brand.choc100
        return ProductPhoto(url: product.photo, size: size, fill: Brand.cream)
            .grayscale(soldOut ? 0.8 : 0)
            .opacity(soldOut ? 0.7 : 1)
            .overlay(alignment: .topLeading) {
                if soldOut { Tag(text: "Sold out", fill: fill).offset(x: -16, y: hasOptions ? 12 : 14) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, hasOptions ? 0 : 2)
            .padding(.bottom, hasOptions ? 14 : 16)
            .background(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: 48, bottomTrailingRadius: 48, style: .continuous)
                    .fill(fill)
                    .padding(.top, -600)
            }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: hasOptions ? 16 : 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(product.name).font(MenuFont.roundo(28)).foregroundStyle(Brand.cocoa)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text(priceText).font(MenuFont.roundo(22)).foregroundStyle(soldOut ? Brand.ink4 : Brand.cocoa)
                    .fixedSize().padding(.top, 2)
                    .contentTransition(.numericText())
            }
            if !product.description.isEmpty && product.description != "Click for more size" {
                Text(product.description).font(MenuFont.manrope(hasOptions ? 14 : 15)).foregroundStyle(Brand.ink2)
                    .lineSpacing(hasOptions ? 4 : 5)
            }
            if soldOut {
                soldOutNotice
            } else {
                ForEach(shownGroups, id: \.name) { g in optionGroup(g) }
                if hasOptions {
                    noteField
                } else {
                    HStack(spacing: 12) {
                        noteField
                        stepper(pad: 4)
                    }
                }
                if showSplitHint {
                    Label { Text("Sharing it? Propose a split from the group after adding.") } icon: { Image(systemName: "chart.pie") }
                        .labelStyle(HintLabel())
                        .font(MenuFont.manrope(13)).foregroundStyle(Brand.ink2)
                }
            }
        }
    }

    private func optionGroup(_ g: OptionGroup) -> some View {
        let allowed = OptionMatch.choices(g.name, all: g.choices, picked: picked, variants: variants)
        let prices = g.choices.map { choicePrice(g.name, $0) }
        let showPrices = Set(prices.compactMap { $0 }).count > 1
        return VStack(alignment: .leading, spacing: 8) {
            Text(optionGroupLabel(g.name)).brand(.label)
            FlowRow(spacing: 8) {
                ForEach(Array(g.choices.enumerated()), id: \.element) { i, c in
                    PricedOptionPill(text: optionLabel(c), price: showPrices ? prices[i].map(Rupiah.format) : nil,
                                     selected: picked[g.name] == c) { pick(g.name, c) }
                        .disabled(!allowed.contains(c))
                        .opacity(allowed.contains(c) ? 1 : 0.4)
                }
            }
        }
    }

    /// The price this choice leads to with the other picks kept (or the cheapest available variant with it).
    private func choicePrice(_ group: String, _ choice: String) -> Int? {
        var trial = picked
        trial[group] = choice
        if let v = OptionMatch.variant(trial, groups: groups.map(\.name), variants: variants) { return v.price }
        return variants.filter { $0.options[group] == choice && $0.available }.map(\.price).min()
    }

    /// Picks a choice; when the other picks no longer make a variant Atas sells, takes the first one that does.
    private func pick(_ group: String, _ choice: String) {
        var next = picked
        next[group] = choice
        if OptionMatch.variant(next, groups: groups.map(\.name), variants: variants)?.available != true,
           let v = variants.first(where: { $0.available && $0.options[group] == choice }) {
            next = v.options
        }
        withAnimation(.snappy) { picked = next }
    }

    private var noteField: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").font(.system(size: 16, weight: .medium)).foregroundStyle(Brand.caramel)
            TextField("Note for Atas", text: $note, prompt: Text("Note for Atas").foregroundStyle(Brand.ink4))
                .font(MenuFont.manrope(15)).foregroundStyle(Brand.cocoa).tint(Brand.caramel)
                .submitLabel(.done)
                .onChange(of: note) { _, n in if n.count > 140 { note = String(n.prefix(140)) } }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(RoundedRectangle(cornerRadius: Brand.rField, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: Brand.rField, style: .continuous).strokeBorder(Brand.liquorice100, lineWidth: 1.5))
    }

    private func stepper(pad: CGFloat) -> some View {
        PillStepper(value: "\(qty)", pad: pad, canMinus: qty > 1, canPlus: qty < 50,
                    minus: { qty = max(1, qty - 1) }, plus: { qty = min(50, qty + 1) })
            .accessibilityLabel("Quantity \(qty)")
    }

    private var soldOutNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 16, weight: .semibold)).padding(.top, 1)
            Text("Sold out on the Atas menu today." + (alternatives.isEmpty ? "" : " Try \(alternatives.joined(separator: " or "))."))
                .font(MenuFont.manrope(14, 600)).lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Brand.cocoa)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.liquorice100))
    }

    // MARK: Bottom bar (Liquid Glass)

    private var actionBar: some View {
        Group {
            if soldOut {
                Button("Sold out today") {}.buttonStyle(.pill(.primary)).disabled(true)
            } else if hasOptions {
                HStack(spacing: 10) {
                    stepper(pad: 6)
                    Button("Add \u{00B7} \(totalText)") { Task { await add() } }
                        .buttonStyle(.pill(.primary))
                        .disabled(price == nil || busy)
                }
            } else {
                Button("Add to my order \u{00B7} \(totalText)") { Task { await add() } }
                    .buttonStyle(.pill(.primary))
                    .disabled(price == nil || busy)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(Brand.cream.opacity(0.4)), in: .rect(cornerRadius: 36))
        .padding(.horizontal, 12)
    }

    private func add() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't add it") {
            try await store.add(product: product, options: product.variants.isEmpty ? [:] : picked, qty: qty,
                                note: note.trimmingCharacters(in: .whitespaces))
            dismiss()
        }
    }
}

/// Icon and text 6 pt apart, icon at 14 pt (the split hint).
private struct HintLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.system(size: 13, weight: .medium)); configuration.title }
    }
}
