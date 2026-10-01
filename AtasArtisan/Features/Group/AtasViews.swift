import SwiftUI
import Supabase

/// 4.12 Send to Atas. The message in the hosts' own format (Indonesian by default, English selectable),
/// editable, sent from the host's own WhatsApp to Atas (0821-3145-473).
struct SendToAtasView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app
    @State private var indonesian = true
    @State private var text = ""
    @State private var busy = false
    @State private var problem: Problem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s4) {
                HStack(spacing: Brand.s3) {
                    Mascot(pose: "pose-phone", size: 64, fill: Brand.lime)
                    Text("This is the message Atas will get. Tap to edit anything before you open WhatsApp.").brand(.callout, Brand.ink2)
                }
                Picker("Message language", selection: $indonesian) {
                    Text("Bahasa Indonesia").tag(true)
                    Text("English").tag(false)
                }
                .pickerStyle(.segmented)
                TextEditor(text: $text)
                    .font(Brand.font(.callout))
                    .frame(minHeight: 380)
                    .scrollContentBackground(.hidden)
                    .padding(Brand.s3)
                    .background(RoundedRectangle(cornerRadius: Brand.rCard).fill(.white))
                HStack {
                    Text("To Atas Artisan").brand(.callout, Brand.ink3)
                    Spacer()
                    Text("+62 821 3145 473").brand(.callout)
                }
                let late = Wita.isPastTodaysCutoff()
                Label(late ? "It's past 15:00 WITA. Delivery may take up to 2 days." : "Send before 15:00 WITA for delivery tomorrow morning.",
                      systemImage: late ? "exclamationmark.triangle.fill" : "clock")
                    .brand(.footnote, late ? Brand.destructive : Brand.ink2)
            }
            .padding(Brand.s4)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            Button("Open WhatsApp") { Task { await send() } }
                .buttonStyle(.pill(.dark)).disabled(busy || text.isEmpty)
                .padding(Brand.s4)
        }
        .navigationTitle("Send to Atas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            indonesian = (store.group?.msg_lang ?? app.profile?.msg_lang ?? "id") == "id"
            text = message()
        }
        .onChange(of: indonesian) { _, _ in text = message() }
        .problemAlert($problem)
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

/// 4.12 Confirm with Atas: copy the ongkir and discount from Atas's reply. Split equally between everyone
/// who ordered; the bill freezes and everyone is told what they owe.
struct ConfirmAtasView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var ongkir = ""
    @State private var discount = ""
    @State private var busy = false
    @State private var problem: Problem?

    private var o: Int { Int(ongkir.filter(\.isNumber)) ?? 0 }
    private var d: Int { Int(discount.filter(\.isNumber)) ?? 0 }
    private var payers: Int { max(1, Set(store.items.map(\.owner_id)).count) }

    var body: some View {
        Form {
            Section {
                TextField("Ongkir from Atas", text: $ongkir).keyboardType(.numberPad)
                TextField("Discount Atas applied", text: $discount).keyboardType(.numberPad)
            } header: { Text("Final bill") } footer: { Text("Copy the numbers from Atas's reply. Ongkir and discount are split equally between the \(payers) people who ordered.") }
            Section {
                row("Items", store.subtotal)
                row("Ongkir − discount", max(0, o - d))
                row("Total", store.subtotal + max(0, o - d)).bold()
                Text("+ \(Rupiah.format(max(0, o - d) / payers)) on each bill").brand(.footnote, Brand.ink2)
            }
        }
        .scrollContentBackground(.hidden)
        .screen()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Brand.s2) {
                Button("Atas confirmed") { Task { await confirm() } }.buttonStyle(.pill(.primary)).disabled(busy || ongkir.isEmpty)
                Text("This freezes the bill and tells everyone to wait for delivery.").brand(.footnote, Brand.ink3)
            }
            .padding(Brand.s4)
        }
        .navigationTitle("Final bill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .problemAlert($problem)
    }

    private func row(_ label: String, _ n: Int) -> some View {
        HStack { Text(label).brand(.body); Spacer(); Text(Rupiah.format(n)).brand(.headline) }
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
