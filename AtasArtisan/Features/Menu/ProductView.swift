import SwiftUI

/// 4.8 Product detail (3-13 to 3-16): the photo on a pastel hero, name and price, option groups as pills with the
/// price each choice leads to, a note for Atas and the quantity. Only combinations Atas actually sells are
/// offered (the server refuses anything else in price_item()). Option groups with a single choice are fixed,
/// so they are not shown. A flavour group (I-2) starts unpicked and swaps the hero to the flavour's photo when
/// it has one. In an open group, a single item can be shared in pieces as it is added (A-1).
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
    /// The price on show, so a change rolls up or down.
    @State private var shownPrice = 0
    /// A-1: share it as it is added, in `pieces`, optionally cancelled at lock below `minPeople`.
    @State private var sharing = false
    @State private var pieces = PieceMotion.defaultPieces
    @State private var hasMin = false
    @State private var minPeople = PieceMotion.minPeopleDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var variants: [VariantChoice] {
        product.variants.map { VariantChoice(options: $0.options, price: $0.price, available: $0.available ?? true) }
    }
    private var groups: [OptionGroup] { product.variants.isEmpty ? [] : product.option_groups }
    private var shownGroups: [OptionGroup] { product.choiceGroups }
    /// Groups the member picks themselves (I-2: nothing preselected).
    private var flavourGroups: [String] { shownGroups.map(\.name).filter { optionGroupLabel($0) == "Flavour" } }
    private var needsFlavour: Bool { flavourGroups.contains { picked[$0] == nil } }
    /// The chosen flavour, and its own photo when iSeller has one.
    private var flavour: String? { flavourGroups.first.flatMap { picked[$0] } }
    private var flavourPhoto: URL? {
        guard let g = flavourGroups.first, let f = picked[g] else { return nil }
        let withIt = product.variants.filter { $0.options[g] == f && $0.image != nil }
        let exact = withIt.first { v in picked.allSatisfy { v.options[$0.key] == $0.value } }
        return (exact ?? withIt.first)?.image.flatMap(URL.init(string:))
    }
    private var flavourPhotos: [URL] {
        guard let g = flavourGroups.first else { return [] }
        return Array(Set(product.variants.filter { $0.options[g] != nil }.compactMap { $0.image.flatMap(URL.init(string:)) }))
    }
    private var hasOptions: Bool { !shownGroups.isEmpty }
    private var soldOut: Bool { !product.available }
    private var price: Int? {
        if product.variants.isEmpty { return product.base_price }
        return OptionMatch.variant(picked, groups: groups.map(\.name), variants: variants)?.price
    }
    /// Until a flavour is picked the title shows the price it starts from.
    private var priceText: String {
        if let price { return Rupiah.format(price) }
        guard needsFlavour else { return "\u{2014}" }
        return (Set(product.variants.map(\.price)).count > 1 ? "from " : "") + Rupiah.format(product.fromPrice)
    }
    private var totalText: String { price.map { Rupiah.format($0 * qty) } ?? "\u{2014}" }
    /// A-1: an open group order, one of it.
    private var canShare: Bool {
        !soldOut && store.group?.personal == false && store.group?.state == .open && qty == 1
    }
    /// The minimum's stepper runs to the group's size (at most 24).
    private var minUpper: Int { max(PieceMotion.minPeopleFloor, min(PieceMotion.range.upperBound, store.activeMembers.count)) }

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
        .onAppear {
            // The first pick shows still; only a change of choice rolls the price.
            var still = Transaction()
            still.disablesAnimations = true
            if picked.isEmpty {
                withTransaction(still) {
                    picked = OptionMatch.defaultPick(variants: variants).filter { !flavourGroups.contains($0.key) }
                    pieces = Pieces.defaultCount(product.name)
                    minPeople = min(PieceMotion.minPeopleDefault, minUpper)
                }
            }
        }
        .problemAlert($problem)
    }

    // MARK: Hero

    private var hero: some View {
        let size: CGFloat = hasOptions ? 200 : 250
        let fill = soldOut ? Brand.liquorice100 : Brand.choc100
        let url = flavourPhoto ?? product.photo
        return ZStack {
            // Every flavour photo loads with the sheet (hidden), so a pick crossfades at once (I-2).
            ForEach(flavourPhotos, id: \.self) { u in ProductPhoto(url: u, size: size, fill: Brand.cream).opacity(0) }
            ProductPhoto(url: url, size: size, fill: Brand.cream)
                .id(url)
                .transition(reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade)
                            : .asymmetric(insertion: AnyTransition.opacity.animation(FlavourMotion.photoIn)
                                            .combined(with: AnyTransition.scale(scale: FlavourMotion.photoScaleFrom).animation(FlavourMotion.photoScale)),
                                          removal: AnyTransition.opacity.animation(FlavourMotion.photoOut)))
        }
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
            .overlay(alignment: .bottom) {
                // A flavour without a photo of its own keeps the product's, and says so under the hero.
                if let flavour, flavourPhoto == nil {
                    Text("No \(flavour) photo yet, showing the \(product.name.lowercased().contains("cake") ? "cake" : "main photo")")
                        .font(MenuFont.manrope(12)).foregroundStyle(Brand.ink3)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 20)
                        .offset(y: 24)
                        .id(flavour)
                        .transition(AnyTransition.opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fade))
                }
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
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: (price ?? 0) < shownPrice))
                    .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: priceText)
                    .onChange(of: price, initial: true) { _, p in shownPrice = p ?? 0 }
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
                if canShare { shareCard.transition(.opacity) }
            }
        }
        .animation(reduceMotion ? Motion.Reduced.fade : PieceMotion.shareRows, value: canShare)
        .padding(.top, flavour != nil && flavourPhoto == nil ? 14 : 0)
    }

    /// A-1 "Share this item": the toggle, then the pieces and the optional minimum.
    private var shareCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label { Text("Share this item") } icon: { Image(systemName: "chart.pie") }
                        .labelStyle(HintLabel())
                        .font(MenuFont.manrope(16, 700)).foregroundStyle(Brand.cocoa)
                    Text("Anyone in the group can claim pieces until the order locks. You keep the rest.")
                        .font(MenuFont.manrope(13)).foregroundStyle(Brand.ink2).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Share this item", isOn: $sharing.animation(reduceMotion ? Motion.Reduced.fade : PieceMotion.shareRows))
                    .labelsHidden().tint(Brand.caramel)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            if sharing {
                ShareRows(pieces: $pieces, hasMin: $hasMin, minPeople: $minPeople, price: price ?? product.fromPrice, minUpper: minUpper)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(.white))
        .clipShape(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous))
        .sensoryFeedback(.selection, trigger: sharing) { _, on in on }
    }

    private func optionGroup(_ g: OptionGroup) -> some View {
        let allowed = OptionMatch.choices(g.name, all: g.choices, picked: picked, variants: variants)
        let prices = g.choices.map { choicePrice(g.name, $0) }
        let showPrices = Set(prices.compactMap { $0 }).count > 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(optionGroupLabel(g.name)).brand(.label)
                Spacer(minLength: 8)
                // "Pick one", then the flavour picked.
                if flavourGroups.contains(g.name) {
                    Text(picked[g.name] ?? "Pick one").font(MenuFont.manrope(12, 600)).foregroundStyle(Brand.caramel)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: picked[g.name])
                }
            }
            OptionChips(choices: g.choices.enumerated().map { i, c in
                            OptionChips.Choice(id: c, text: optionLabel(c), price: showPrices ? prices[i].map(Rupiah.format) : nil, allowed: allowed.contains(c))
                        },
                        selected: picked[g.name]) { pick(g.name, $0) }
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
        // A flavour not picked yet stays unpicked: only the member chooses it.
        let open = flavourGroups.filter { picked[$0] == nil && $0 != group }
        let sells = open.isEmpty ? OptionMatch.variant(next, groups: groups.map(\.name), variants: variants)?.available == true
                                 : variants.contains { v in v.available && next.allSatisfy { v.options[$0.key] == $0.value } }
        if !sells, let v = variants.first(where: { $0.available && $0.options[group] == choice }) {
            next = v.options.filter { !open.contains($0.key) }
        }
        picked = next
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
        PillStepper(value: "\(qty)", pad: pad, canMinus: qty > 1, canPlus: qty < 50 && !sharing,
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
                Button("Sold out today") {}.buttonStyle(.pill(.primary)).disabled(true, reason: nil)
            } else if hasOptions {
                HStack(spacing: 10) {
                    stepper(pad: 6)
                    if needsFlavour {
                        Button("Pick a flavour") {}.buttonStyle(.pill(.primary)).disabled(true, reason: "Pick a flavour first")
                    } else {
                        addButton("Add")
                    }
                }
            } else {
                addButton("Add to my order")
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(Brand.cream.opacity(0.4)), in: .rect(cornerRadius: 36))
        .padding(.horizontal, 12)
    }

    /// "Add to my order · Rp 260.000", or "Add & share" with the pie while sharing.
    private func addButton(_ title: String) -> some View {
        Button { Task { await add() } } label: {
            if sharing && canShare { Label("Add & share \u{00B7} \(totalText)", systemImage: "chart.pie") } else { Text("\(title) \u{00B7} \(totalText)") }
        }
        .buttonStyle(.pill(.primary))
        .disabled(price == nil || busy)
    }

    private func add() async {
        busy = true
        defer { busy = false }
        let share = sharing && canShare ? (pieces: pieces, min: hasMin ? Optional(minPeople) : nil) : nil
        await attempt($problem, "Couldn't add it") {
            try await store.add(product: product, options: product.variants.isEmpty ? [:] : picked, qty: qty,
                                note: note.trimmingCharacters(in: .whitespaces), share: share)
            dismiss()
        }
    }
}

/// Icon and text 6 pt apart, icon at 14 pt (the share card's title).
private struct HintLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.system(size: 13, weight: .medium)); configuration.title }
    }
}
