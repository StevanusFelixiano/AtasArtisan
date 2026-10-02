import SwiftUI
import Supabase

/// 4.12 Send to Atas (5-1, 5-1b). The message in the hosts' own format (Indonesian by default, English
/// selectable), editable, sent from the host's own WhatsApp to Atas (0821-3145-473).
struct SendToAtasView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app
    @State private var language = 0
    @State private var text = ""
    @State private var busy = false
    @State private var problem: Problem?
    @FocusState private var editing: Bool

    private var indonesian: Bool { language == 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Mascot(pose: "pose-phone", size: 64, fill: Brand.lime)
                    Text("This is the message Atas will get. Tap to edit anything before you open WhatsApp.")
                        .font(Type5.manrope(14)).lineSpacing(1).foregroundStyle(Brand.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
                Segmented(options: ["Bahasa Indonesia", "English"], selection: $language)
                    .accessibilityLabel("Message language")
                TextField("Message", text: $text, axis: .vertical)
                    .font(Type5.manrope(14))
                    .lineSpacing(2)
                    .foregroundStyle(Brand.cocoa)
                    .tint(Brand.caramel)
                    .focused($editing)
                    .padding(.trailing, 24)
                    .padding(.vertical, 16).padding(.horizontal, 18)
                    .background(bubble.fill(Brand.card))
                    .overlay(bubble.strokeBorder(Brand.liquorice100, lineWidth: 1.5))
                    .overlay(alignment: .topTrailing) {
                        Button { editing = true } label: {
                            Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.cocoa)
                                .frame(width: 28, height: 28).background(Circle().fill(Brand.liquorice100))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel("Edit the message")
                    }
                HStack {
                    Text("To Atas Artisan").font(Type5.manrope(13, 600)).foregroundStyle(Brand.ink2)
                    Spacer()
                    Text("+62 821 3145 473").font(Type5.manrope(14, 700)).foregroundStyle(Brand.cocoa)
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.card))
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, Brand.s4)
            .padding(.top, 10)
            .padding(.bottom, Brand.s4)
        }
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .safeAreaInset(edge: .bottom) {
            GlassBar {
                Button { Task { await send() } } label: {
                    Label { Text("Open WhatsApp") } icon: { WhatsAppGlyph(size: 20) }
                }
                .buttonStyle(.pill(.dark))
                .disabled(busy || text.isEmpty)
                cutoff
            }
        }
        .navigationTitle("Send to Atas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
        }
        .onAppear {
            language = (store.group?.msg_lang ?? app.profile?.msg_lang ?? "id") == "id" ? 0 : 1
            text = message()
        }
        .onChange(of: language) { _, _ in text = message() }
        .problemAlert($problem)
    }

    /// The message bubble: radius 24 with a 6 pt corner at the bottom right.
    private var bubble: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24, bottomTrailingRadius: 6, topTrailingRadius: 24, style: .continuous)
    }

    @ViewBuilder private var cutoff: some View {
        if Wita.isPastTodaysCutoff() {
            Label("It’s past Atas’s 15:00 WITA cutoff. Delivery can take up to 2 days.", systemImage: "exclamationmark.triangle")
                .labelStyle(IconLabel(spacing: 10, size: 16))
                .font(Type5.manrope(14, 600)).lineSpacing(1)
                .foregroundStyle(Brand.cocoa)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.choc100))
                .padding(.top, 8)
        } else {
            Label("Send before 15:00 WITA for delivery tomorrow morning", systemImage: "clock")
                .labelStyle(IconLabel(spacing: 6, size: 12))
                .font(Type5.manrope(12))
                .foregroundStyle(Brand.ink2)
                .padding(.top, 8).padding(.bottom, 2)
        }
    }

    private func message() -> String {
        guard let g = store.group else { return "" }
        let people = store.activeMembers.map { m in
            (name: store.name(m.user_id), lines: store.items(of: m.user_id).map { i in
                let order = store.products[i.product_id]?.option_groups.map(\.name) ?? i.options.keys.sorted()
                return AtasLine(name: i.name, options: order.compactMap { i.options[$0] }, qty: i.qty, unitPrice: i.unit_price, note: i.note)
            })
        }
        let host = store.people[g.host_id]
        return AtasMessage.text(AtasOrder(hostName: host?.name ?? "", hostPhone: host?.phone ?? "",
                                          place: g.address_label, address: g.address_detail == g.address_label ? "" : g.address_detail,
                                          mapsURL: g.maps_url, delivery: g.delivery_at, people: people), indonesian: indonesian)
    }

    private func send() async {
        busy = true
        defer { busy = false }
        openURL(Links.whatsApp(Links.atasNumber, text: text))
        await attempt($problem, "Couldn't mark it sent") {
            try await store.rpc("mark_sent", ["g": .string(store.id.uuidString)])
            dismiss()
        }
    }
}

/// 4.12 Confirm with Atas (5-3): copy the ongkir and discount from Atas's reply. Split equally between everyone
/// who ordered; the bill freezes and everyone is told what they owe.
struct ConfirmAtasView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var ongkir = ""
    @State private var discount = ""
    @State private var busy = false
    @State private var problem: Problem?
    @FocusState private var field: Field?

    private enum Field { case ongkir, discount }

    private var o: Int { Int(ongkir) ?? 0 }
    private var d: Int { Int(discount) ?? 0 }
    private var net: Int { max(0, o - d) }
    /// Everyone who owes something, as `group_bill_v` counts them (split shares included).
    private var orderers: [BillRow] {
        store.bill.filter { $0.items > 0 }.sorted { store.colorIndex($0.user_id) < store.colorIndex($1.user_id) }
    }
    private var payers: Int { max(1, orderers.count) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Copy the numbers from Atas’s reply. Ongkir and discount are split equally between the \(payers) members.")
                    .font(Type5.manrope(14)).lineSpacing(1).foregroundStyle(Brand.ink2)
                    .padding(.horizontal, 4)
                amountField("Ongkir from Atas", prefix: "Rp", text: $ongkir, .ongkir)
                amountField("Discount Atas applied", prefix: "− Rp", text: $discount, .discount)
                totals
                if !orderers.isEmpty { people }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.top, 10)
            .padding(.bottom, Brand.s4)
        }
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .safeAreaInset(edge: .bottom) {
            GlassBar {
                Button("Atas confirmed", systemImage: "checkmark") { Task { await confirm() } }
                    .buttonStyle(.pill(.primary))
                    .disabled(busy || ongkir.isEmpty)
                Text("This freezes the bill and tells everyone to wait for delivery.")
                    .font(Type5.manrope(12)).foregroundStyle(Brand.ink2).multilineTextAlignment(.center)
                    .padding(.top, 8).padding(.bottom, 2)
            }
        }
        // The two fields sit at the top; the keyboard covers the bar instead of pushing it over the totals.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationTitle("Final bill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { field = nil } }
        }
        .problemAlert($problem)
        #if DEBUG
        .onAppear {
            // Screenshot hook for 5-3: "30000,15000" fills both fields and focuses the discount.
            if let v = DebugScreens.value("ATASTE_CONFIRM")?.split(separator: ","), v.count == 2 {
                ongkir = String(v[0]); discount = String(v[1]); field = .discount
            }
        }
        #endif
    }

    /// Label above a 56 pt white field with the "Rp" prefix and the amount in Roundo; the focused one gets the
    /// caramel edge and the choc-100 halo.
    private func amountField(_ label: String, prefix: String, text: Binding<String>, _ which: Field) -> some View {
        let on = field == which
        let shape = RoundedRectangle(cornerRadius: Brand.rField, style: .continuous)
        let shown = Binding<String>(
            get: { text.wrappedValue.isEmpty ? "" : Rupiah.bare(Int(text.wrappedValue) ?? 0) },
            set: { text.wrappedValue = String($0.filter(\.isNumber).drop { $0 == "0" }.prefix(9)) })
        return VStack(alignment: .leading, spacing: 8) {
            Text(label).brand(.label).padding(.leading, 4)
            HStack(spacing: 8) {
                Text(prefix).font(Type5.manrope(16, 600)).foregroundStyle(Brand.ink3)
                TextField("0", text: shown, prompt: Text("0").foregroundStyle(Brand.ink4))
                    .font(Type5.roundo(20))
                    .foregroundStyle(Brand.cocoa)
                    .tint(Brand.caramel)
                    .keyboardType(.numberPad)
                    .focused($field, equals: which)
                    .accessibilityLabel(label)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(shape.fill(Brand.card))
            .overlay(shape.strokeBorder(on ? Brand.caramel : Brand.liquorice100, lineWidth: on ? 2 : 1.5))
            .background(RoundedRectangle(cornerRadius: Brand.rField + 4, style: .continuous).fill(Brand.choc100).padding(-4).opacity(on ? 1 : 0))
            .contentShape(Rectangle())
            .onTapGesture { field = which }
        }
    }

    /// Cocoa card: items, ongkir − discount, the total, and what each bill gains.
    private var totals: some View {
        VStack(alignment: .leading, spacing: 8) {
            totalsRow("Items", store.subtotal)
            totalsRow("Ongkir − discount", net)
            HStack(alignment: .firstTextBaseline) {
                Text("Total").font(Type5.manrope(12, 600)).tracking(12 * 0.03).textCase(.uppercase)
                Spacer()
                Text(Rupiah.format(store.subtotal + net)).font(Type5.roundo(30)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Brand.cream)
            .padding(.top, 8)
            .overlay(alignment: .top) { DashedRule(color: Brand.cream.opacity(0.25)) }
            Text("+ \(Rupiah.format(net / payers)) on each of \(payers) bills").font(Type5.manrope(13, 600)).foregroundStyle(Brand.lime)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.cocoa))
        .accessibilityElement(children: .combine)
    }

    private func totalsRow(_ label: String, _ n: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(Brand.liquorice400)
            Spacer()
            Text(Rupiah.format(n)).foregroundStyle(Brand.cream)
        }
        .font(Type5.manrope(14, 600))
    }

    /// Each person's items and their bill once this is confirmed (the host takes the rounding, as the view does).
    private var people: some View {
        VStack(spacing: 0) {
            ForEach(Array(orderers.enumerated()), id: \.element.user_id) { i, r in
                let each = net / payers
                let share = r.user_id == store.group?.host_id ? net - (payers - 1) * each : each
                HStack(spacing: 10) {
                    Avatar(name: store.name(r.user_id), index: store.colorIndex(r.user_id), size: 28, art: store.people[r.user_id]?.avatar,
                           bg: store.people[r.user_id]?.avatar_bg)
                    Text(store.name(r.user_id)).font(Type5.manrope(14, 600)).foregroundStyle(Brand.cocoa)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Rupiah.bare(r.items)).font(Type5.manrope(12)).foregroundStyle(Brand.ink3)
                    Text(Rupiah.format(r.items + share)).font(Type5.roundo(15)).foregroundStyle(Brand.cocoa)
                        .frame(minWidth: 88, alignment: .trailing)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if i < orderers.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }

    private func confirm() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't confirm") {
            try await store.rpc("confirm_atas", ["g": .string(store.id.uuidString), "ongkir": .integer(o), "discount": .integer(d)])
            dismiss()
        }
    }
}
