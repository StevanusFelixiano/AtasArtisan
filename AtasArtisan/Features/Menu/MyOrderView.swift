import SwiftUI

/// My order, from the menu's floating bar: my items in this group with their quantities, or the empty state
/// (3-12, The Son of Bun) with a way back to the menu.
struct MyOrderView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var removing: Item?
    @State private var problem: Problem?

    private var items: [Item] { store.myItems.sorted { $0.name < $1.name } }
    private var editable: Bool {
        guard let g = store.group else { return false }
        return g.state == .open || (g.state == .edits && store.hasFlagsForMe)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("My order").font(MenuFont.roundo(22)).foregroundStyle(Brand.cocoa).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(store.group?.name ?? "").font(MenuFont.manrope(13)).foregroundStyle(Brand.ink3).lineLimit(1)
            }
            if items.isEmpty { empty } else { list }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
        .doughSheet(item: $removing) { item in
            ConfirmSheet(confirm: Confirm(title: "Remove \(item.name)?",
                                          message: store.claims(item).isEmpty ? "It comes out of your order." : "The pieces others claimed come off their bills too.",
                                          button: "Remove", keep: "Keep") {}, delay: SheetMotion.rowAfterRemove) {
                Task { await attempt($problem, "Couldn't remove it") { try await store.remove(item) } }
            }
        }
        .problemAlert($problem)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                PaintingFrame(art: "paint-sonofbun", width: 150, height: 186, tilt: -1.5)
                (Text("The Son of Bun").italic() + Text(" \u{00B7} oil on canvas"))
                    .font(MenuFont.manrope(12)).foregroundStyle(Brand.ink3)
            }
            .padding(.top, 4)
            Text("Nothing in the oven\u{2026}yet!").font(MenuFont.roundo(26)).foregroundStyle(Brand.cocoa)
            Text("Add something from the menu. It joins the group order under your name.")
                .font(MenuFont.manrope(15)).foregroundStyle(Brand.ink2).lineSpacing(5)
                .frame(maxWidth: 290)
            Button("Browse the menu") { dismiss() }
                .buttonStyle(.pill(.primary, .medium))
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        VStack(spacing: 0) {
                            if i > 0 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                            row(item)
                        }
                        .transition(.itemRow)
                    }
                }
                .rowMotion(items.map(\.id))
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
                HStack {
                    Text("Your items").brand(.label)
                    Spacer()
                    CountUp(amount: items.reduce(0) { $0 + $1.total }) { Text(Rupiah.format($0)) }
                        .font(MenuFont.roundo(20)).foregroundStyle(Brand.cocoa)
                }
                .padding(.horizontal, 4)
                Text("Ongkir is shared once Atas confirms the order.").font(MenuFont.manrope(13)).foregroundStyle(Brand.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                Button("Add more") { dismiss() }.buttonStyle(.pill(.secondary, .medium)).padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ProductPhoto(url: store.products[item.product_id]?.photo, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(MenuFont.manrope(15, 700)).foregroundStyle(Brand.cocoa)
                let opts = store.optionText(item)
                if !opts.isEmpty { Text(optionLabel(opts)).font(MenuFont.manrope(12)).foregroundStyle(Brand.ink2) }
                if !item.note.isEmpty { Text("\u{201C}\(item.note)\u{201D}").font(MenuFont.manrope(12)).foregroundStyle(Brand.ink3) }
                Text(Rupiah.format(item.total)).font(MenuFont.roundo(15)).foregroundStyle(Brand.cocoa).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if editable {
                PillStepper(value: "\(item.qty)", fill: Brand.cream, gap: 10, pad: 3, countSize: 15,
                            minusSymbol: item.qty == 1 ? "trash" : "minus", canPlus: item.qty < 50 && item.share_pieces == nil,
                            minusLabel: item.qty == 1 ? "Remove \(item.name)" : "One less \(item.name)",
                            plusLabel: "One more \(item.name)",
                            minus: { change(item, item.qty - 1) }, plus: { change(item, item.qty + 1) })
            } else {
                Text("\(item.qty)\u{00D7}").font(MenuFont.roundo(15)).foregroundStyle(Brand.cocoa)
            }
        }
        .padding(.vertical, 12)
    }

    private func change(_ item: Item, _ qty: Int) {
        if qty < 1 { removing = item; return }
        Task { await attempt($problem, "Couldn't change the quantity") { try await store.setQty(item, qty) } }
    }
}
