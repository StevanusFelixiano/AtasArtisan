import SwiftUI
import Supabase

/// 4.16 Profile: name, verified number, payment methods, saved places, notifications, message language,
/// legal, log out, delete account (guideline 5.1.1(v)).
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var accounts: [PayoutAccount] = []
    @State private var addresses: [Address] = []
    @State private var editingAccount: PayoutAccount?
    @State private var editingAddress: Address?
    @State private var confirmDelete = false
    @State private var pickingAvatar = false
    @State private var confirmLogout = false
    @State private var problem: Problem?

    var body: some View {
        Form {
            Section {
                HStack(spacing: Brand.s3) {
                    Button { pickingAvatar = true } label: {
                        Avatar(name: app.profile?.name ?? "?", index: 0, size: 64, art: app.profile?.avatar)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil.circle.fill").font(.system(size: 20)).foregroundStyle(Brand.caramel)
                                    .background(Circle().fill(.white))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change profile picture")
                    VStack(alignment: .leading) {
                        TextField("Your name", text: $name).font(Brand.font(.title2)).onSubmit { Task { await saveName() } }
                        Label(PhoneFormat.display(app.profile?.phone ?? ""), systemImage: "checkmark.seal.fill").brand(.callout, Color(rgb: 0x5E7A00))
                            .accessibilityLabel("Verified number \(PhoneFormat.display(app.profile?.phone ?? ""))")
                    }
                }
            }
            Section {
                ForEach(accounts) { a in
                    Button { editingAccount = a } label: { Text("\(a.label) · \(a.account_name) · \(a.number)").brand(.callout) }
                }
                .onDelete { idx in Task { await delete(accounts, idx, table: "payout_accounts") } }
                Button { editingAccount = PayoutAccount() } label: { Label("Add payment method", systemImage: "plus") }
            } header: { Text("Payment methods") } footer: { Text("Shown to members of groups you host, so they know where to transfer.") }
            Section {
                ForEach(addresses) { a in
                    Button { editingAddress = a } label: {
                        VStack(alignment: .leading) {
                            Text(a.label).brand(.headline)
                            Text([a.area, a.detail].filter { !$0.isEmpty }.joined(separator: " · ")).brand(.footnote, Brand.ink3)
                        }
                    }
                }
                .onDelete { idx in Task { await delete(addresses, idx, table: "addresses") } }
                Button { editingAddress = Address() } label: { Label("Add address", systemImage: "plus") }
            } header: { Text("Saved places") }
            Section("Notifications") {
                NavigationLink("Notification settings") { NotificationSettingsView() }
            }
            Section {
                Picker("Message to Atas", selection: Binding(get: { app.profile?.msg_lang ?? "id" },
                                                             set: { v in Task { try? await app.saveProfile(msgLang: v) } })) {
                    Text("Bahasa Indonesia").tag("id")
                    Text("English").tag("en")
                }
            } footer: { Text("The language of the WhatsApp order your groups send to Atas. You can still switch it per order.") }
            Section("About") {
                Button("Privacy Policy") { openURL(Links.privacy) }
                Button("Terms of Use") { openURL(Links.terms) }
                Button("Support") { openURL(Links.support) }
                Text("Ataste is an independent app and is not affiliated with Atas Artisan.").brand(.footnote, Brand.ink3)
            }
            Section {
                Button("Log out") { confirmLogout = true }
                Button("Delete account", role: .destructive) { confirmDelete = true }
            }
        }
        .scrollContentBackground(.hidden)
        .screen()
        .navigationTitle("Profile")
        .task { await load() }
        .onAppear { if DebugScreens.value("ATASTE_SHEET") == "avatar" { pickingAvatar = true } }
        .sheet(isPresented: $pickingAvatar) { NavigationStack { AvatarPicker() } }
        .sheet(item: $editingAccount) { a in NavigationStack { PayoutEditor(account: a) { _ in Task { await load() } } } }
        .sheet(item: $editingAddress) { a in NavigationStack { AddressEditor(address: a) { _ in Task { await load() } } } }
        .alert("Log out?", isPresented: $confirmLogout) {
            Button("Log out", role: .destructive) { Task { await app.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You can sign back in with WhatsApp any time.") }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await attempt($problem, "Couldn't delete your account") { try await app.deleteAccount() } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your profile, orders, payment methods, receipts and photos are deleted. Groups you host are deleted for everyone. This can't be undone.") }
        .problemAlert($problem)
    }

    private func load() async {
        name = app.profile?.name ?? ""
        accounts = (try? await supabase.from("payout_accounts").select().eq("user_id", value: app.userID ?? UUID()).order("created_at").execute().value) ?? []
        addresses = (try? await supabase.from("addresses").select().order("created_at").execute().value) ?? []
    }

    private func saveName() async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { name = app.profile?.name ?? ""; return }
        await attempt($problem, "Couldn't save your name") { try await app.saveProfile(name: n) }
    }

    private func delete<T: Identifiable>(_ list: [T], _ idx: IndexSet, table: String) async where T.ID == UUID {
        for i in idx {
            await attempt($problem, "Couldn't delete") { try await supabase.from(table).delete().eq("id", value: list[i].id).execute() }
        }
        await load()
    }
}

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app
    private let groups: [(String, String, [String])] = [
        ("Group activity", "Joins, cutoff reminders, locks", ["joined", "cutoff_soon", "locked", "unlocked", "discount_unlocked"]),
        ("Your items", "Edit requests, sold-out items, splits", ["edit_requested", "edit_done", "sold_out", "split_proposed", "split_invited", "split_answered", "split_cancelled"]),
        ("Order progress", "Sent, confirmed, delivered, closed, cancelled", ["sent", "bill_final", "delivered", "closed", "cancelled", "removed"]),
        ("Payments", "Paid, confirmed, reminders", ["member_paid", "payment_confirmed", "nudge", "everyone_paid"]),
    ]

    var body: some View {
        Form {
            ForEach(groups, id: \.0) { g in
                Toggle(isOn: Binding(get: { !(app.profile?.notify_mute ?? []).contains(g.2[0]) },
                                     set: { on in
                                         var mute = Set(app.profile?.notify_mute ?? [])
                                         if on { mute.subtract(g.2) } else { mute.formUnion(g.2) }
                                         Task { try? await app.saveProfile(mute: Array(mute).sorted()) }
                                     })) {
                    VStack(alignment: .leading) { Text(g.0).brand(.headline); Text(g.1).brand(.footnote, Brand.ink3) }
                }
                .tint(Brand.caramel)
            }
        }
        .scrollContentBackground(.hidden)
        .screen()
        .navigationTitle("Notifications")
    }
}

struct PayoutEditor: View {
    @State var account: PayoutAccount
    var saved: (PayoutAccount) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?
    private let labels = ["BCA", "Mandiri", "BNI", "BRI", "GoPay", "OVO", "DANA", "ShopeePay"]

    var body: some View {
        Form {
            Section("Label") {
                Picker("Label", selection: $account.label) {
                    Text("Choose").tag("")
                    ForEach(labels, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Account name") { TextField("e.g. Rani Pratiwi", text: $account.account_name).textContentType(.name) }
            Section {
                TextField("Account number", text: $account.number).keyboardType(.numberPad)
            } header: { Text("Account number") } footer: { Text("Members see this on their bill with a copy button.") }
        }
        .scrollContentBackground(.hidden)
        .screen()
        .navigationTitle("Payment method")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(account.label.isEmpty || account.account_name.isEmpty || account.number.count < 3)
            }
        }
        .problemAlert($problem)
    }

    private func save() async {
        await attempt($problem, "Couldn't save") {
            var a = account
            a.user_id = nil
            let row: PayoutAccount = try await supabase.from("payout_accounts").upsert(a).select().single().execute().value
            saved(row)
            dismiss()
        }
    }
}

struct AddressEditor: View {
    @State var address: Address
    var saved: (Address) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?

    var body: some View {
        Form {
            Section("Name") { TextField("e.g. Academy Bali", text: $address.label) }
            Section {
                Picker("Area", selection: $address.area) { ForEach(Areas.all, id: \.self) { Text($0).tag($0) } }
            } header: { Text("Area") } footer: { Text("Atas delivers to these areas of Bali only.") }
            Section("Address") { TextField("Street, building, landmark", text: $address.detail, axis: .vertical) }
            Section {
                TextField("https://maps.app.goo.gl/…", text: $address.maps_url).keyboardType(.URL).textInputAutocapitalization(.never)
            } header: { Text("Google Maps link") } footer: { Text("Goes into the order message as \"Link alamat\" so the courier finds you.") }
        }
        .scrollContentBackground(.hidden)
        .screen()
        .navigationTitle("Saved place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(address.label.isEmpty || !(address.maps_url.isEmpty || address.maps_url.hasPrefix("https://")))
            }
        }
        .problemAlert($problem)
    }

    private func save() async {
        await attempt($problem, "Couldn't save") {
            var a = address
            a.user_id = nil
            let row: Address = try await supabase.from("addresses").upsert(a).select().single().execute().value
            saved(row)
            dismiss()
        }
    }
}

/// Pick a giraffe or a painting as your profile picture.
struct AvatarPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s5) {
                section("Giraffes", Art.poses)
                section("Paintings", Art.paintings)
                Button("Use my initial instead") { Task { await choose(nil) } }.buttonStyle(.pill(.secondary, .medium))
            }
            .padding(Brand.s4)
        }
        .screen()
        .navigationTitle("Profile picture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .problemAlert($problem)
    }

    private func section(_ title: String, _ arts: [String]) -> some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Text(title).brand(.label)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Brand.s3), count: 3), spacing: Brand.s3) {
                ForEach(arts, id: \.self) { art in
                    Button { Task { await choose(art) } } label: {
                        Avatar(name: app.profile?.name ?? "?", index: Art.all.firstIndex(of: art) ?? 0, size: 96, art: art)
                            .overlay(Circle().stroke(app.profile?.avatar == art ? Brand.caramel : .clear, lineWidth: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(art.replacingOccurrences(of: "-", with: " "))
                }
            }
        }
    }

    private func choose(_ art: String?) async {
        await attempt($problem, "Couldn't save") {
            guard let id = app.userID else { return }
            try await supabase.from("profiles").update(["avatar": Nullable(art)]).eq("id", value: id).execute()
            await app.loadProfile()
            dismiss()
        }
    }
}
