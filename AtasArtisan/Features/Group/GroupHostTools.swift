import SwiftUI
import Supabase

// The host menu's "Edit delivery details" (3-4) and the cancelled screen's "Start an order with my items" (6-10).

/// Where and when the order arrives, and (while open) when it locks. The host may update these columns while the
/// group is open, locked or in an edit round (`host_edits` policy).
struct EditDeliverySheet: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var addresses: [Address] = []
    @State private var addressID: UUID?
    @State private var delivery = Date()
    @State private var useCutoff = false
    @State private var cutoff = Date()
    @State private var busy = false
    @State private var problem: Problem?

    private var open: Bool { store.group?.state == .open }

    var body: some View {
        Form {
            Section {
                ForEach(addresses) { a in
                    Button { addressID = a.id } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(a.label).brand(.headline)
                                Text([a.area, a.detail].filter { !$0.isEmpty }.joined(separator: " · ")).brand(.footnote, Brand.ink3)
                            }
                            Spacer()
                            if addressID == a.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.caramel) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if addresses.isEmpty, let g = store.group {
                    Text("\(g.address_label) · \(g.area)").brand(.callout, Brand.ink2)
                }
            } header: { Text("Deliver to") } footer: { Text("Add places in Profile. Atas delivers in Bali only.") }

            Section {
                DatePicker("Delivery", selection: $delivery, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .environment(\.timeZone, Wita.zone)
            } header: { Text("Delivery (WITA)") }

            if open && store.group?.personal == false {
                Section {
                    Toggle("Cutoff", isOn: $useCutoff)
                    if useCutoff {
                        DatePicker("Locks at", selection: $cutoff, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, Wita.zone)
                    }
                    if useCutoff && Wita.cutoffTooLate(cutoff: cutoff, delivery: delivery) {
                        Label("Atas's cutoff is 3 PM. After that, delivery can take up to 2 days.", systemImage: "exclamationmark.triangle.fill")
                            .brand(.callout, Brand.cocoa)
                            .listRowBackground(Brand.choc100)
                    }
                } footer: { Text("The group locks itself at cutoff.") }
            }
        }
        .scrollContentBackground(.hidden)
        .screen()
        .navigationTitle("Delivery details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy) }
        }
        .task { await load() }
        .problemAlert($problem)
    }

    private func load() async {
        guard let g = store.group else { return }
        delivery = g.delivery_at
        useCutoff = g.cutoff_at != nil
        cutoff = g.cutoff_at ?? Wita.atasDeadline(for: g.delivery_at).addingTimeInterval(-3600)
        addresses = (try? await supabase.from("addresses").select().order("created_at").execute().value) ?? []
        addressID = addresses.first { $0.label == g.address_label && $0.area == g.area }?.id
    }

    private func save() async {
        guard let g = store.group else { return }
        struct Patch: Encodable {
            var area: String
            var address_label: String
            var address_detail: String
            var maps_url: String
            var delivery_at: Date
            var cutoff_at: Nullable<Date>?
        }
        let a = addresses.first { $0.id == addressID }
        let patch = Patch(area: a?.area ?? g.area, address_label: a?.label ?? g.address_label, address_detail: a?.detail ?? g.address_detail,
                          maps_url: a?.maps_url ?? g.maps_url, delivery_at: delivery,
                          cutoff_at: open && !g.personal ? Nullable(useCutoff ? cutoff : nil) : nil)
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't save") {
            try await supabase.from("groups").update(patch).eq("id", value: g.id).execute()
            await store.refresh()
            AppModel.shared.homeVersion += 1
            dismiss()
        }
    }
}

extension GroupView {
    /// 6-10: a personal order at the same place with my items from the cancelled group (sold-out ones left out).
    func startOrder(from g: OrderGroup, items: [Item]) async {
        await act("Couldn't start the order") {
            let delivery = max(g.delivery_at, Wita.defaultDelivery())
            let new = NewGroup(name: "My order", personal: true, area: g.area, address_label: g.address_label, address_detail: g.address_detail,
                               maps_url: g.maps_url, delivery_at: delivery, cutoff_at: nil, pay_rule: "order_first",
                               msg_lang: AppModel.shared.profile?.msg_lang ?? g.msg_lang, payout_account_id: nil)
            let created: OrderGroup = try await supabase.from("groups").insert(new).select().single().execute().value
            let copies = items.filter { store.products[$0.product_id]?.available != false }
                .map { NewItem(group_id: created.id, product_id: $0.product_id, options: $0.options, qty: $0.qty, note: $0.note) }
            if !copies.isEmpty { try await supabase.from("items").insert(copies).execute() }
            AppModel.shared.homeVersion += 1
            path.removeLast()
            path.append(created.id)
        }
    }
}
