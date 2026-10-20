import SwiftUI
import Supabase

/// 6-5 Profile (9-9a/b): picture, name, the verified number with the L badge or the "Get the Verified badge" card,
/// payment methods, notifications, message language, saved places, change number, Sign in with Apple, log out; then
/// legal, support and delete account (guideline 5.1.1(v)), which the board leaves out.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var accounts: [PayoutAccount] = []
    @State private var addresses: [Address] = []
    @State private var editingAccount: PayoutAccount?
    @State private var confirmDelete = false
    @State private var pickingAvatar = false
    @State private var confirmLogout = false
    /// 9-4a from the badge card or Change number, pushed on this stack.
    @State private var verifying = false
    /// 9-8 from the "Signed in with Apple · Link" row.
    @State private var linking: LinkPrompt?
    @State private var problem: Problem?
    @FocusState private var editingName: Bool
    /// DEBUG `ATASTE_PROFILE` = notifications (6-7) | payout (6-6, the first payment method).
    @State private var debugNotifications = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if app.profile?.verified == false { verifyCard }
                Text("Payment methods · for when you host").brand(.label).padding(.horizontal, 4).padding(.top, 6)
                payoutCard
                settingsCard
                aboutCard
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, Brand.s5)
        }
        .scrollsToTopOnRetap()
        .screen()
        .navigationTitle("Profile")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await load()
            switch DebugScreens.value("ATASTE_PROFILE") {
            case "notifications": debugNotifications = true
            case "payout": editingAccount = accounts.first
            default: break
            }
        }
        .navigationDestination(isPresented: $debugNotifications) { NotificationSettingsView() }
        .onAppear { if DebugScreens.value("ATASTE_SHEET") == "avatar" { pickingAvatar = true } }
        .sheet(isPresented: $pickingAvatar) { NavigationStack { AvatarPicker() } }
        .navigationDestination(item: $editingAccount) { a in PayoutEditor(account: a, sheet: false) { _ in Task { await load() } } }
        .navigationDestination(isPresented: $verifying) {
            VerifyFlow(origin: .profile) { end in
                Task {
                    if end == .verified { await app.loadProfile() }
                    verifying = false
                }
            }
        }
        .doughSheet(item: $linking) { _ in LinkAppleSheet {} }
        .alert("Log out?", isPresented: $confirmLogout) {
            Button("Log out", role: .destructive) { Task { await app.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            // An account made with WhatsApp sign-in and never linked comes back through 9-7 instead.
            Text(app.appleLinked == false ? "To get back to this account, sign in with Apple and verify the same WhatsApp number."
                                          : "You can sign back in with Apple any time.")
        }
            .alert("Delete your account?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await attempt($problem, "Couldn't delete your account") { try await app.deleteAccount() } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your profile, orders, payment methods, receipts and photos are deleted. Groups you host are deleted for everyone. Your Apple ID is disconnected from Ataste. This can't be undone.") }
            .problemAlert($problem)
    }
    
    // MARK: Header
    
    private var header: some View {
        VStack(spacing: Brand.s2) {
            Button { pickingAvatar = true } label: {
                Avatar(name: app.profile?.name ?? "?", index: 0, size: 84, art: app.profile?.avatar, bg: app.profile?.avatar_bg)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.cream)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Brand.cocoa))
                            .overlay(Circle().strokeBorder(Brand.cream, lineWidth: 3))
                            .offset(x: 4, y: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change profile picture")
            TextField("Your name", text: $name)
                .obText(.display, 28)
                .multilineTextAlignment(.center)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($editingName)
                .onSubmit { Task { await saveName() } }
                .onChange(of: editingName) { _, on in if !on { Task { await saveName() } } }
                .accessibilityLabel("Your name")
            // 9-9b: the number with the L badge (6-5's lime pill read as PAID). 9-9a: no number yet.
            if let p = app.profile, let phone = p.phone {
                HStack(spacing: 8) {
                    Text(PhoneFormat.spaced(phone)).obText(.headline, 14, weight: 600, Brand.ink2)
                        .accessibilityLabel("Verified number \(PhoneFormat.spaced(phone))")
                    VerifiedBadge(size: .l, person: VerifiedPerson(p))
                }
            } else {
                Text("No phone number yet").obText(.callout, 13, Brand.ink3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
    
    // MARK: Cards

    /// 9-9a: hosting needs a verified number, and hosts reach members on WhatsApp.
    private var verifyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Get the Verified badge").obText(.headline, 17).frame(maxWidth: .infinity, alignment: .leading)
                VerifiedBadge()
            }
            Text("Prove the WhatsApp number is yours with one message. You need it to host, and hosts can reach you.")
                .obText(.callout, 14, Brand.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button { verifying = true } label: { ObWhatsAppLabel(title: "Verify with WhatsApp").frame(maxWidth: .infinity) }
                .buttonStyle(.pill(.primary, .medium))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.card))
    }
    
    private var payoutCard: some View {
        VStack(spacing: 0) {
            ForEach(accounts) { a in
                Button { editingAccount = a } label: {
                    ProfileRow(divider: true) {
                        Tag(text: a.label, fill: PayoutKind.isWallet(a.label) ? Brand.lime : Brand.choc400)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(a.account_name).obText(.headline, 15)
                            Text(PayoutKind.shown(a)).obText(.callout, 13, Brand.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Chevron()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(a.label), \(a.account_name)")
                .accessibilityHint("Edit payment method")
            }
            Button { editingAccount = PayoutAccount(label: "BCA", account_name: app.profile?.name ?? "") } label: {
                ProfileRow(divider: false) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28).background(Circle().fill(Brand.choc100))
                    Text("Add payment method").obText(.headline, 15, weight: 600).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Brand.s4).padding(.vertical, Brand.s1)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }
    
    private var settingsCard: some View {
        VStack(spacing: 0) {
            NavigationLink { NotificationSettingsView() } label: {
                ProfileRow(divider: true, vertical: 13) {
                    Image(systemName: "bell").rowIcon()
                    Text("Notifications").obText(.headline, 15, weight: 600).frame(maxWidth: .infinity, alignment: .leading)
                    Chevron()
                }
            }
            .buttonStyle(.plain)
            // The language of the order message to Atas, which only hosts send: unverified people can't host yet.
            if app.profile?.verified == true { languageRow }
            NavigationLink { SavedPlacesView() } label: {
                ProfileRow(divider: true, vertical: 13) {
                    Image(systemName: "mappin.and.ellipse").rowIcon()
                    Text("Saved places").obText(.headline, 15, weight: 600).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(addresses.count)").obText(.callout, 13, Brand.ink3)
                    Chevron()
                }
            }
            .buttonStyle(.plain)
            // 9-9b: runs 9-4a again; the new number replaces the old one and the badge moves with it.
            if app.profile?.verified == true {
                Button { verifying = true } label: {
                    ProfileRow(divider: true, vertical: 13) {
                        Image(systemName: "arrow.triangle.2.circlepath").rowIcon()
                        Text("Change number").obText(.headline, 15, weight: 600).frame(maxWidth: .infinity, alignment: .leading)
                        Chevron()
                    }
                }
                .buttonStyle(.plain)
            }
            appleRow
            Button { confirmLogout = true } label: {
                ProfileRow(divider: false, vertical: 13) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").rowIcon()
                    Text("Log out").obText(.headline, 15, weight: 600, Brand.destructive).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Brand.destructive)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Brand.s4).padding(.vertical, Brand.s1)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }

    /// "Signed in with Apple · Linked", or a Link button (9-8) for an account made with WhatsApp sign-in. Hidden until
    /// the server has said which.
    @ViewBuilder private var appleRow: some View {
        if let linked = app.appleLinked {
            Button { linking = LinkPrompt() } label: {
                ProfileRow(divider: true, vertical: 13) {
                    Image(systemName: "person").rowIcon()
                    Text("Signed in with Apple").obText(.headline, 15, weight: 600).frame(maxWidth: .infinity, alignment: .leading)
                    Text(linked ? "Linked" : "Link").obText(linked ? .callout : .headline, linked ? 13 : 15, weight: linked ? nil : 600,
                                                          linked ? Brand.ink3 : Brand.caramel)
                }
            }
            .buttonStyle(.plain)
            .disabled(linked)
            .accessibilityHint(linked ? "" : "Links your Apple ID to this account")
        }
    }

    private var languageRow: some View {
        // The system pull-down menu, with the up/down arrows of the Area picker in Saved places.
        Menu {
            Picker("Atas message language", selection: Binding(
                get: { app.profile?.msg_lang ?? "id" },
                set: { lang in Task { try? await app.saveProfile(msgLang: lang) } })) {
                Text("Bahasa Indonesia").tag("id")
                Text("English").tag("en")
            }
        } label: {
            ProfileRow(divider: true, vertical: 13) {
                // A Menu label takes the caramel tint and centres wrapped text; the other rows don't.
                ObWhatsAppGlyph(size: 19).foregroundStyle(Color.primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Atas message language")
                        .obText(.headline, 15, weight: 600)

                    Text("Used when you send a group order")
                        .obText(.footnote, 12, Brand.ink3)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    app.profile?.msg_lang == "en"
                    ? "English"
                    : "Bahasa Indonesia"
                )
                .obText(.callout, 13, Brand.ink3)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.ink4)
            }
        }
        .accessibilityLabel("Atas message language, \(app.profile?.msg_lang == "en" ? "English" : "Bahasa Indonesia")")
    }
    
    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([("Privacy Policy", Links.privacy, "hand.raised"), ("Terms of Use", Links.terms, "doc.text"),
                     ("Support", Links.support, "questionmark.circle")], id: \.0) { title, url, icon in
                Button { openURL(url) } label: {
                    ProfileRow(divider: true, vertical: 13) {
                        Image(systemName: icon).rowIcon()
                        Text(title).obText(.headline, 15, weight: 600).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.ink4)
                    }
                }
                .buttonStyle(.plain)
            }
            Button { confirmDelete = true } label: {
                ProfileRow(divider: false, vertical: 13) {
                    Image(systemName: "trash").rowIcon()
                    Text("Delete account").obText(.headline, 15, weight: 600, Brand.destructive).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Brand.destructive)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Brand.s4).padding(.vertical, Brand.s1)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
        .overlay(alignment: .bottom) {
            Text("Ataste is an independent app and is not affiliated with Atas Artisan.")
                .obText(.footnote, 12, Brand.ink3).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .offset(y: 56)
        }
        .padding(.bottom, 36)
    }
    
    // MARK: Data
    
    private func load() async {
        name = app.profile?.name ?? ""
        accounts = (try? await supabase.from("payout_accounts").select().eq("user_id", value: app.userID ?? UUID()).order("created_at").execute().value) ?? []
        addresses = (try? await supabase.from("addresses").select().order("created_at").execute().value) ?? []
    }
    
    private func saveName() async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.count <= 60 else { name = app.profile?.name ?? ""; return }
        guard n != app.profile?.name else { return }
        await attempt($problem, "Couldn't save your name") { try await app.saveProfile(name: n) }
    }
}

/// A row in a Profile card: 12 pt gaps, a liquorice-100 rule under all but the last.
private struct ProfileRow<Content: View>: View {
    var divider: Bool
    var vertical: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.vertical, vertical)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { if divider { Rectangle().fill(Brand.liquorice100).frame(height: 1) } }
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.ink4)
    }
}

private extension Image {
    func rowIcon() -> some View { self.font(.system(size: 17, weight: .regular)).frame(width: 20) }
}

/// Banks show a masked number, e-wallets the phone number they're tied to.
enum PayoutKind {
    static let banks = ["BCA", "Mandiri", "BNI", "BRI", "BSI", "CIMB Niaga", "Permata", "Danamon", "BTN", "Jago", "SeaBank", "blu"]
    static let wallets = ["GoPay", "OVO", "DANA", "ShopeePay", "LinkAja"]
    /// The label chips, banks first. Anything else is typed under "Other…".
    static let all = banks + wallets
    static func isWallet(_ label: String) -> Bool { wallets.contains { $0.caseInsensitiveCompare(label) == .orderedSame } }
    
    /// BCA 0951228441 7 → "•••• 4417"; GoPay 081290345521 → "0812 9034 5521".
    static func shown(_ a: PayoutAccount) -> String {
        if isWallet(a.label) { return PayoutCard.grouped(a.number) }
        return "•••• " + String(a.number.filter(\.isNumber).suffix(4))
    }
}

// MARK: Notification settings (6-7)

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app
    
    /// Each row mutes the notification kinds the server sends for it (`profiles.notify_mute`).
    private let sections: [(String, [(String, [String])])] = [
        ("Your orders", [
            ("Cutoff in 30 minutes", ["cutoff_soon"]),
            ("Group locked or unlocked", ["locked", "unlocked", "discount_unlocked"]),
            ("Host asks you to edit an item", ["edit_requested"]),
            ("Item sold out on the menu", ["sold_out"]),
            ("Order sent, confirmed, delivered, closed", ["sent", "delivered", "closed", "cancelled", "removed"]),
            ("Pickup reminders from the host", ["pickup_nudge"]),
            ("A spot opened in a full group", ["spot_open"]),
        ]),
        ("Sharing", [
            ("Someone shares an item", ["item_shared"]),
            ("Someone wants to share your item", ["share_asked"]),
            ("Your shared item at lock, or 30 minutes before", ["share_min_reminder", "share_locked_in", "share_min_not_met"]),
            ("Sharing stopped on an item you claimed", ["share_stopped"]),
            ("Someone takes your shared pieces out of the fridge", ["split_taken", "split_put_back"]),
        ]),
        ("Money", [
            ("Bill is final", ["bill_final"]),
            ("Payment confirmed", ["payment_confirmed"]),
            ("Payment reminders from the host", ["nudge", "payment_not_received"]),
        ]),
        ("When you host", [
            ("Someone joined", ["joined"]),
            ("Everyone is ready to lock", ["all_ready"]),
            ("Reminder to tap Atas confirmed", ["atas_reply"]),
            ("Member finished editing", ["edit_done"]),
            ("Member says they’ve paid", ["member_paid"]),
            ("Everyone has paid", ["everyone_paid"]),
            ("Everyone has taken their food", ["fridge_clear"]),
        ]),
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sections, id: \.0) { title, rows in
                    VStack(alignment: .leading, spacing: Brand.s2) {
                        Text(title).brand(.label).padding(.horizontal, 4).padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(rows.indices, id: \.self) { i in
                                Toggle(isOn: binding(rows[i].1)) {
                                    Text(rows[i].0).obText(.headline, 14, weight: 600).lineSpacing(2)
                                }
                                .tint(Brand.caramel)
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) {
                                    if i < rows.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                                }
                            }
                        }
                        .padding(.horizontal, Brand.s4).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
                    }
                    .padding(.bottom, 6)
                }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, Brand.s5)
        }
        .screen()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func binding(_ kinds: [String]) -> Binding<Bool> {
        Binding(get: { !kinds.contains { (app.profile?.notify_mute ?? []).contains($0) } },
                set: { on in
            var mute = Set(app.profile?.notify_mute ?? [])
            if on { mute.subtract(kinds) } else { mute.formUnion(kinds) }
            Task { try? await app.saveProfile(mute: Array(mute).sorted()) }
        })
    }
}

// MARK: Payment method (2-4c, 6-6)

/// The one payment method form, from Create group (a sheet with Cancel) and Profile (pushed, with Delete for a saved
/// one): label chips with "Other…" for a typed label, account name, account number.
struct PayoutEditor: View {
    @State private var account: PayoutAccount
    /// Presented in its own sheet (Create group) with a Cancel button, or pushed from Profile with a back button.
    var sheet = true
    var saved: (PayoutAccount) -> Void
    @State private var other: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?
    @State private var confirmDelete = false
    @State private var busy = false
    
    init(account: PayoutAccount, sheet: Bool = true, saved: @escaping (PayoutAccount) -> Void) {
        _account = State(initialValue: account)
        _other = State(initialValue: !account.label.isEmpty && !PayoutKind.all.contains(account.label))
        self.sheet = sheet
        self.saved = saved
    }
    
    private var existing: Bool { account.user_id != nil }
    private var label: String { account.label.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { !label.isEmpty && !account.account_name.isEmpty && account.number.count >= 3 }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: Brand.s2) {
                    FieldLabel("Label")
                    FlowLayout(spacing: Brand.s2) {
                        ForEach(PayoutKind.all, id: \.self) { l in
                            OptionPill(text: l, selected: !other && account.label == l) { other = false; account.label = l }
                        }
                        OptionPill(text: "Other…", selected: other) { other = true; account.label = "" }
                    }
                    if other { BrandField(placeholder: "e.g. Bank Neo, Flip, Jenius", text: $account.label) }
                }
                BrandField(label: "Account name", placeholder: "e.g. Rani Pratiwi", text: $account.account_name)
                    .textContentType(.name)
                VStack(alignment: .leading, spacing: Brand.s2) {
                    BrandField(label: "Account number", placeholder: "Account number", text: $account.number, keyboard: .numberPad)
                    Text("Members see this on their bill with a copy button.").styled(.body, 13, Brand.ink2).padding(.leading, Brand.s1)
                }
                if existing {
                    Button { confirmDelete = true } label: { Label("Delete payment method", systemImage: "trash") }
                        .buttonStyle(SoftDestructivePill())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Brand.s2)
        }
        .foregroundStyle(Brand.cocoa)
        .screen()
        .navigationTitle(existing && !label.isEmpty ? label : "Payment method")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sheet { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(!valid || busy)
            }
        }
        .alert("Delete this payment method?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Groups you host that use it will show no payment method until you pick another.") }
            .problemAlert($problem)
    }
    
    private func save() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't save") {
            var a = account
            a.user_id = nil
            a.label = label
            let row: PayoutAccount = try await supabase.from("payout_accounts").upsert(a).select().single().execute().value
            saved(row)
            dismiss()
        }
    }
    
    private func delete() async {
        await attempt($problem, "Couldn't delete") {
            try await supabase.from("payout_accounts").delete().eq("id", value: account.id).execute()
            saved(account)
            dismiss()
        }
    }
}

/// 6-6's "Delete payment method": white pill, soft red 4 pt border, red label.
private struct SoftDestructivePill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.font(.body, size: 15, weight: 600))
            .foregroundStyle(Brand.destructive)
            .padding(.horizontal, 24)
            .frame(minHeight: 48)
            .background(Capsule().fill(configuration.isPressed ? Brand.trashFill : Brand.card))
            .overlay(Capsule().strokeBorder(Brand.destructiveSoft, lineWidth: 4))
            .contentShape(Capsule())
    }
}

// MARK: Saved places

struct SavedPlacesView: View {
    @State private var addresses: [Address] = []
    @State private var editing: Address?
    @State private var loaded = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if loaded && addresses.isEmpty {
                    EmptyStateView(pose: "pose-delivery", fill: Brand.choc100, title: "No saved places...yet!",
                                   message: "Save where Atas should deliver, so a new order is two taps.")
                }
                ForEach(addresses) { a in
                    PlaceRow(title: a.label, detail: [a.area, a.detail].filter { !$0.isEmpty }.joined(separator: " · ")) { editing = a }
                }
                PlaceRow(title: "Add a place", icon: "plus") { editing = Address() }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.top, Brand.s2)
        }
        .screen()
        .navigationTitle("Saved places")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { a in AddressEditor(address: a, sheet: false) { _ in Task { await load() } } }
        .task { await load() }
    }
    
    private func load() async {
        addresses = (try? await supabase.from("addresses").select().order("created_at").execute().value) ?? []
        loaded = true
    }
}

struct AddressEditor: View {
    @State var address: Address
    var sheet = true
    var saved: (Address) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?
    @State private var confirmDelete = false
    
    private var valid: Bool { !address.label.isEmpty && (address.maps_url.isEmpty || address.maps_url.hasPrefix("https://")) }
    
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
            if address.user_id != nil {
                Section { Button("Delete this place", role: .destructive) { confirmDelete = true } }
            }
        }
        .scrollContentBackground(.hidden)
        .screen()
        .navigationTitle("Saved place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sheet { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(!valid)
            }
        }
        .alert("Delete this place?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Orders already placed keep their address.") }
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
    
    private func delete() async {
        await attempt($problem, "Couldn't delete") {
            try await supabase.from("addresses").delete().eq("id", value: address.id).execute()
            saved(address)
            dismiss()
        }
    }
}

// MARK: Profile picture (6-5b, 6-5c)

/// Pick a giraffe, a painting or your initial (Ataste's own art, never an upload) and the background colour the
/// giraffe or initial sits on. Both are staged and written on Save.
struct AvatarPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var choice: String?
    @State private var bg: String?
    @State private var started = false
    @State private var busy = false
    @State private var problem: Problem?
    
    /// Each giraffe's own pastel before a background is chosen, as an index into `Brand.people`
    /// (choc-100 3, pink-100 1, lime 2, liquorice-100 4).
    private static let poseFill: [String: Int] = [
        "pose-neutral": 3, "pose-waving": 1, "pose-cakebox": 3, "pose-waiting": 4, "pose-celebrating": 2,
        "pose-confused": 1, "pose-sleeping": 4, "pose-delivery": 3, "pose-phone": 2, "pose-splitting": 1,
    ]
    /// Board order for the paintings.
    private static let paintings = ["paint-croissant", "paint-creation", "paint-brioche", "paint-monalisa", "paint-scream",
                                    "paint-gothic", "paint-sonofbun", "paint-vangogh", "paint-supper"]
    
    static func title(_ art: String?) -> String {
        switch art {
        case "paint-monalisa": "Mona Loafa"
        case "paint-croissant": "Girl with a Croissant"
        case "paint-scream": "The Scream of Dough"
        case "paint-gothic": "American Baguettic"
        case "paint-brioche": "The Birth of Brioche"
        case "paint-sonofbun": "The Son of Bun"
        case "paint-vangogh": "Self-Portrait as Vincent van Dough"
        case "paint-supper": "The Last Supper Club"
        case "paint-creation": "The Creation of Ataste"
        case "pose-neutral": "Classic giraffe"
        case "pose-cakebox": "Cake-box giraffe"
        case let a? where a.hasPrefix("pose-"): a.dropFirst(5).capitalized + " giraffe"
        default: "Initial"
        }
    }
    
    /// "Cake-box giraffe · Sour lime"; a painting fills its circle, so it shows its name alone.
    private var caption: String {
        let name = Self.title(choice)
        guard choice?.hasPrefix("paint-") != true, let colour = Art.backgrounds.first(where: { $0.key == bg })?.name else { return name }
        return "\(name) · \(colour)"
    }
    
    var body: some View {
        let me = app.profile?.name ?? "?"
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 6) {
                    Avatar(name: me, index: index(choice), size: 120, art: choice, bg: bg)
                    Text(caption).obText(.headline, 15)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Preview, \(caption)")
                Text("Background").brand(.label).padding(.horizontal, 4).padding(.top, 2)
                swatches
                section("Giraffes", Art.poses, onColour: true)
                section("Paintings", Self.paintings, onColour: false)
                Button { choice = nil } label: {
                    HStack(spacing: 12) {
                        Avatar(name: me, index: 0, size: 40, bg: bg)
                        Text("Use my initial instead").obText(.headline, 15, weight: 600).frame(maxWidth: .infinity, alignment: .leading)
                        ZStack {
                            if choice == nil {
                                Circle().fill(Brand.caramel)
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.cream)
                            } else {
                                Circle().strokeBorder(Brand.liquorice400, lineWidth: 2)
                            }
                        }
                        .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.card))
                    .overlay { if choice == nil { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Brand.caramel, lineWidth: 2.5) } }
                    .padding(.top, 20)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice == nil ? .isSelected : [])
                .padding(.top, 2)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, Brand.s5)
        }
        .screen()
        .navigationTitle("Profile picture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy).bold() }
        }
        .onAppear {
            guard !started else { return }
            choice = app.profile?.avatar
            bg = app.profile?.avatar_bg
            // DEBUG `ATASTE_PICK=<art|initial>:<background key>` stages a choice for screenshots (nothing is saved).
            if let pick = DebugScreens.value("ATASTE_PICK")?.split(separator: ":").map(String.init), pick.count == 2 {
                choice = pick[0] == "initial" ? nil : pick[0]
                bg = pick[1]
            }
            started = true
        }
        .problemAlert($problem)
    }
    
    /// Seven 36 pt swatches in 44 pt tap areas, spread across the row; the chosen one has a cream gap, a cocoa
    /// ring and a check (cream on Caramel).
    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(Art.backgrounds.indices, id: \.self) { i in
                let s = Art.backgrounds[i]
                let selected = bg == s.key
                if i > 0 { Spacer(minLength: 0) }
                Button { bg = s.key } label: {
                    ZStack {
                        Circle().fill(s.color)
                        Circle().strokeBorder(Brand.cocoa.opacity(0.12), lineWidth: 1.5)
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(s.key == "caramel" ? Brand.cream : Brand.cocoa)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .overlay { if selected { Circle().strokeBorder(Brand.cocoa, lineWidth: 2.5).padding(-5.5) } }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
    
    private func index(_ art: String?) -> Int { art.flatMap { Self.poseFill[$0] } ?? 0 }
    
    private func section(_ title: String, _ arts: [String], onColour: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).brand(.label).padding(.horizontal, 4).padding(.top, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(arts, id: \.self) { art in
                    let selected = choice == art
                    Button { choice = art } label: {
                        Avatar(name: "", index: index(art), size: 58, art: art, bg: onColour ? bg : nil)
                            .overlay { if selected { Circle().strokeBorder(Brand.caramel, lineWidth: 3).padding(-6) } }
                            .overlay(alignment: .bottomTrailing) {
                                if selected {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.cream)
                                        .frame(width: 22, height: 22).background(Circle().fill(Brand.caramel))
                                        .overlay(Circle().strokeBorder(Brand.cream, lineWidth: 2))
                                        .offset(x: 4, y: 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.title(art))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
    
    private func save() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't save") {
            guard let id = app.userID else { return }
            try await supabase.from("profiles").update(["avatar": Nullable(choice), "avatar_bg": Nullable(bg)]).eq("id", value: id).execute()
            await app.loadProfile()
            dismiss()
        }
    }
}

#Preview("Profile") {
    NavigationStack { ProfileView() }
        .environment(PreviewData.app)
}
