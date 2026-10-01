import SwiftUI
import Supabase
import CoreImage.CIFilterBuiltins

/// Tab bar (Liquid Glass on iOS 26): Home, History, Profile.
struct MainTabs: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0
    @State private var homePath = NavigationPath()

    var body: some View {
        @Bindable var app = app
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                NavigationStack(path: $homePath) {
                    HomeView(path: $homePath)
                        .navigationDestination(for: UUID.self) { GroupView(id: $0, path: $homePath) }
                }
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: 1) {
                NavigationStack { HistoryView() }
            }
            Tab("Profile", systemImage: "person.crop.circle", value: 2) {
                NavigationStack { ProfileView() }
            }
        }
        .sheet(item: Binding(get: { app.pendingJoin.map(JoinCode.init) }, set: { app.pendingJoin = $0?.code })) { join in
            JoinSheet(code: join.code) { id in
                tab = 0
                homePath.append(id)
            }
        }
        .task {
            if let t = DebugScreens.value("ATASTE_TAB"), let n = Int(t) { tab = n }
            if let name = DebugScreens.value("ATASTE_OPEN") {
                let rows: [OrderGroup] = (try? await supabase.from("groups").select().ilike("name", pattern: "%\(name)%").execute().value) ?? []
                if let g = rows.first { homePath.append(g.id) }
            }
        }
        .onChange(of: app.openGroup) { _, id in
            guard let id else { return }
            tab = 0
            homePath = NavigationPath([id])
            app.openGroup = nil
        }
    }
}

struct JoinCode: Identifiable { var code: String; var id: String { code } }

// MARK: Home (2-1)

struct HomeView: View {
    @Binding var path: NavigationPath
    @Environment(AppModel.self) private var app
    @State private var groups: [OrderGroup] = []
    @State private var bills: [UUID: BillRow] = [:]
    @State private var loaded = false
    @State private var creating: Bool?   // true = group, false = for myself
    @State private var pasting = false
    @State private var problem: Problem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s5) {
                VStack(alignment: .leading, spacing: Brand.s1) {
                    Text(Wita.string(Date(), "EEEE d MMMM")).brand(.label, Brand.ink3)
                    Text("Hi, \(app.profile?.name ?? "")").brand(.display)
                }
                .padding(.horizontal, Brand.s4)
                Marquee()
                HStack(spacing: Brand.s3) {
                    BigChoice(title: "Order for myself", subtitle: "Just you, no sharing", pose: "pose-cakebox", fill: Brand.pink100) { creating = false }
                    BigChoice(title: "Start a group order", subtitle: "Share a link, split the bill", pose: "pose-waving", fill: Brand.caramel, dark: true) { creating = true }
                }
                .padding(.horizontal, Brand.s4)

                let active = groups.filter { $0.state.isLive }
                if loaded && active.isEmpty {
                    EmptyStateView(title: "No orders baking...yet!", message: "Start a group order or paste a link a friend sent you.")
                } else {
                    VStack(alignment: .leading, spacing: Brand.s3) {
                        Text("Active orders").brand(.label)
                        ForEach(active) { g in
                            Button { path.append(g.id) } label: { OrderCard(group: g, bill: bills[g.id]) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Brand.s4)
                }
                VStack(spacing: Brand.s2) {
                    RowLink(icon: "link", title: "Paste a join link", subtitle: "If a link opened in Safari instead") { pasting = true }
                }
                .padding(.horizontal, Brand.s4)
            }
            .padding(.vertical, Brand.s4)
        }
        .screen()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task(id: app.homeVersion) { await load() }
        .sheet(item: Binding(get: { creating.map(CreateMode.init) }, set: { creating = $0?.group })) { mode in
            NavigationStack {
                CreateGroupView(personal: !mode.group) { id in
                    creating = nil
                    path.append(id)
                }
            }
        }
        .alert("Paste a join link", isPresented: $pasting) {
            PasteJoinField()
        } message: { Text("Paste the Ataste link your host shared.") }
        .problemAlert($problem)
    }

    private func load() async {
        do {
            groups = try await supabase.from("groups").select().order("delivery_at").execute().value
            if let me = app.userID {
                let rows: [BillRow] = try await supabase.from("group_bill_v").select().eq("user_id", value: me).execute().value
                bills = Dictionary(uniqueKeysWithValues: rows.map { ($0.group_id, $0) })
            }
        } catch where isCancellation(error) {
            return
        } catch {
            problem = Problem(title: "Couldn't load your orders", message: readable(error))
        }
        loaded = true
    }
}

struct CreateMode: Identifiable { var group: Bool; var id: Bool { group } }

private struct PasteJoinField: View {
    @Environment(AppModel.self) private var app
    @State private var text = UIPasteboard.general.string ?? ""
    var body: some View {
        TextField("Link or code", text: $text)
        Button("Join") {
            // https://…/functions/v1/join/ABC123, ataste://join/ABC123 or just ABC123
            let code = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").last.map(String.init) ?? ""
            if code.count == 6 { app.pendingJoin = code.uppercased() }
        }
        Button("Cancel", role: .cancel) {}
    }
}

struct BigChoice: View {
    var title: String
    var subtitle: String
    var pose: String
    var fill: Color
    var dark = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Brand.s2) {
                Image(pose).resizable().scaledToFit().frame(height: 96).frame(maxWidth: .infinity, alignment: .trailing)
                Text(title).brand(.title2, dark ? Brand.cream : Brand.cocoa).multilineTextAlignment(.leading)
                Text(subtitle).brand(.footnote, dark ? Brand.choc100 : Brand.ink2)
            }
            .padding(Brand.s4)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .bottomLeading)
            .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
    }
}

struct OrderCard: View {
    var group: OrderGroup
    var bill: BillRow?
    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).brand(.title2)
                    Text("\(group.personal ? "Just me" : "Group") · \(Wita.string(group.delivery_at, "EEE d MMM, HH:mm")) WITA")
                        .brand(.footnote, Brand.ink3)
                }
                Spacer()
                StateTag(state: group.state)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.state == .confirmed || group.state == .delivered ? "You owe" : "My subtotal").brand(.label, Brand.ink3)
                    Text(Rupiah.format(bill?.total ?? 0)).brand(.title2)
                }
                Spacer()
                if let bill, group.state == .confirmed || group.state == .delivered, bill.total > 0 { PayTag(state: PayState(bill)) }
                if group.state == .open, let cutoff = group.cutoff_at {
                    Label("Locks \(cutoff, style: .relative)", systemImage: "clock").brand(.footnote, Brand.caramel)
                }
            }
        }
        .card()
    }
}

struct RowLink: View {
    var icon: String
    var title: String
    var subtitle: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Brand.s3) {
                Image(systemName: icon).foregroundStyle(Brand.cocoa).frame(width: 36, height: 36).background(Circle().fill(Brand.choc100))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).brand(.headline)
                    if let subtitle { Text(subtitle).brand(.footnote, Brand.ink3) }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Brand.ink3)
            }
            .card(Brand.rSmall, padding: Brand.s3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Create group (2-4 … 2-4f)

struct CreateGroupView: View {
    var personal: Bool
    var created: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var addresses: [Address] = []
    @State private var accounts: [PayoutAccount] = []
    @State private var addressID: UUID?
    @State private var accountID: UUID?
    @State private var delivery = Wita.defaultDelivery()
    @State private var useCutoff = true
    @State private var cutoff = Wita.atasDeadline(for: Wita.defaultDelivery()).addingTimeInterval(-2 * 3600)
    @State private var payFirst = false
    @State private var editingAddress: Address?
    @State private var editingAccount: PayoutAccount?
    @State private var busy = false
    @State private var problem: Problem?

    var body: some View {
        Form {
            if !personal {
                Section("Group name") { TextField("e.g. Friday Treats", text: $name) }
            }
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
                Button { editingAddress = Address() } label: { Label("Add new address", systemImage: "plus") }
            } header: { Text("Deliver to") } footer: { Text("Atas delivers in Bali only.") }

            Section {
                DatePicker("Delivery", selection: $delivery, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .environment(\.timeZone, Wita.zone)
            } header: { Text("Delivery (WITA)") } footer: { Text("Defaults to tomorrow morning.") }

            if !personal {
                Section {
                    Toggle("Cutoff", isOn: $useCutoff)
                    if useCutoff {
                        DatePicker("Locks at", selection: $cutoff, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, Wita.zone)
                    }
                    if useCutoff && Wita.cutoffTooLate(cutoff: cutoff, delivery: delivery) {
                        VStack(alignment: .leading, spacing: Brand.s2) {
                            Label("Atas's cutoff is 3 PM. After that, delivery can take up to 2 days.", systemImage: "exclamationmark.triangle.fill")
                                .brand(.callout, Brand.cocoa)
                            Button("Use 14:00 WITA") {
                                cutoff = Wita.atasDeadline(for: delivery).addingTimeInterval(-3600)
                            }
                            .buttonStyle(.pill(.secondary, .small))
                        }
                        .listRowBackground(Brand.choc100)
                    }
                } footer: { Text("The group locks itself at cutoff. You can unlock it to extend.") }

                Section("Payment rule") {
                    Picker("Payment rule", selection: $payFirst) {
                        Text("Order first").tag(false)
                        Text("Pay first").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(payFirst ? "You wait until everyone has paid, then finish the order with Atas."
                                  : "You send the order to Atas without waiting. Everyone pays once the bill is final.")
                        .brand(.footnote, Brand.ink2)
                }

                Section {
                    if accounts.isEmpty {
                        VStack(spacing: Brand.s3) {
                            Mascot(pose: "pose-confused", size: 90, fill: Brand.liquorice100)
                            Text("No payment method...yet!").brand(.headline)
                            Text("Add the bank or e-wallet your group should transfer to. It shows on everyone's bill.")
                                .brand(.footnote, Brand.ink2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(accounts) { a in
                        Button { accountID = a.id } label: {
                            HStack {
                                Text("\(a.label) · \(a.account_name) · \(a.number)").brand(.callout)
                                Spacer()
                                if accountID == a.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.caramel) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button { editingAccount = PayoutAccount() } label: { Label("Add payment method", systemImage: "plus") }
                } header: { Text("People pay you at") }
            }
        }
        .scrollContentBackground(.hidden)
        .screen()
        .navigationTitle(personal ? "Order for myself" : "New group order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(personal ? "Start" : "Create") { Task { await create() } }.disabled(!valid || busy)
            }
        }
        .task { await load() }
        .sheet(item: $editingAddress) { a in
            NavigationStack { AddressEditor(address: a) { saved in addresses.append(saved); addressID = saved.id } }
        }
        .sheet(item: $editingAccount) { a in
            NavigationStack { PayoutEditor(account: a) { saved in accounts.append(saved); accountID = saved.id } }
        }
        .onChange(of: delivery) { _, d in
            if useCutoff && cutoff > d { cutoff = Wita.atasDeadline(for: d).addingTimeInterval(-3600) }
        }
        .problemAlert($problem)
    }

    private var valid: Bool {
        addressID != nil && (personal || (!name.trimmingCharacters(in: .whitespaces).isEmpty && accountID != nil))
    }

    private func load() async {
        addresses = (try? await supabase.from("addresses").select().order("created_at").execute().value) ?? []
        accounts = (try? await supabase.from("payout_accounts").select().eq("user_id", value: app.userID ?? UUID()).order("created_at").execute().value) ?? []
        addressID = addressID ?? addresses.first?.id
        accountID = accountID ?? accounts.first?.id
    }

    private func create() async {
        guard let a = addresses.first(where: { $0.id == addressID }) else { return }
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't create the order") {
            let new = NewGroup(name: personal ? "My order" : name.trimmingCharacters(in: .whitespaces), personal: personal, area: a.area,
                               address_label: a.label, address_detail: a.detail, maps_url: a.maps_url, delivery_at: delivery,
                               cutoff_at: personal || !useCutoff ? nil : cutoff, pay_rule: payFirst ? "pay_first" : "order_first",
                               msg_lang: app.profile?.msg_lang ?? "id", payout_account_id: personal ? nil : accountID)
            let g: OrderGroup = try await supabase.from("groups").insert(new).select().single().execute().value
            app.homeVersion += 1
            created(g.id)
        }
    }
}

// MARK: Share (2-5)

struct ShareCard: View {
    var group: OrderGroup
    @Environment(\.dismiss) private var dismiss
    @State private var toast: String?

    var body: some View {
        VStack(spacing: Brand.s5) {
            Text("Invite people").brand(.title1)
            if let qr = QR.image(Links.join(group.code).absoluteString) {
                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 200, height: 200)
                    .padding(Brand.s4).background(RoundedRectangle(cornerRadius: Brand.rCard).fill(.white))
                    .accessibilityLabel("QR code for the join link")
            }
            Text(group.name).brand(.title2)
            if let c = group.cutoff_at {
                Text("Locks \(Wita.string(c, "EEE d MMM, HH:mm")) WITA").brand(.callout, Brand.ink2)
            }
            Text(Links.join(group.code).absoluteString).brand(.footnote, Brand.ink3).multilineTextAlignment(.center).textSelection(.enabled)
            Spacer(minLength: 0)
            Button("Share link") { presentShare([shareText]) }.buttonStyle(.pill(.primary))
            Button("Copy link") { copy(Links.join(group.code).absoluteString, "Link copied", $toast) }.buttonStyle(.pill(.secondary, .medium))
        }
        .padding(Brand.s5)
        .screen()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .toast($toast)
    }

    private var shareText: String {
        "Join \(group.name) on Ataste: \(Links.join(group.code).absoluteString)\nNo app yet? Get Ataste: \(Links.getTheApp)"
    }
}

enum QR {
    static func image(_ s: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: Join (2-6)

struct JoinSheet: View {
    var code: String
    var joined: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: GroupPreview?
    @State private var loaded = false
    @State private var busy = false
    @State private var problem: Problem?

    var body: some View {
        VStack(spacing: Brand.s5) {
            Spacer(minLength: 0)
            if let p = preview {
                Mascot(pose: "pose-waving", size: 150, fill: Brand.pink100)
                Text(p.name).brand(.title1).multilineTextAlignment(.center)
                Text("Hosted by \(p.host_name) · \(p.members) \(p.members == 1 ? "person" : "people")").brand(.callout, Brand.ink2)
                VStack(alignment: .leading, spacing: Brand.s2) {
                    Label("Delivery \(Wita.string(p.delivery_at, "EEE d MMM, HH:mm")) WITA", systemImage: "calendar")
                    if let c = p.cutoff_at { Label("Locks \(Wita.string(c, "EEE d MMM, HH:mm")) WITA", systemImage: "clock") }
                    Label(p.area, systemImage: "mappin")
                }
                .brand(.callout).card()
                Spacer(minLength: 0)
                if p.already_member {
                    Text("You're already in this group.").brand(.callout, Brand.ink2)
                    Button("See the group") { dismiss(); joined(p.id) }.buttonStyle(.pill(.primary))
                } else if p.state != .open {
                    Text("This group is no longer taking orders.").brand(.callout, Brand.destructive)
                } else {
                    Button("Join") { Task { await join() } }.buttonStyle(.pill(.primary)).disabled(busy)
                }
            } else if loaded {
                EmptyStateView(pose: "pose-confused", title: "Link not found", message: "Ask your host to share the link again.")
                Spacer(minLength: 0)
            } else {
                ProgressView().tint(Brand.caramel)
                Spacer(minLength: 0)
            }
        }
        .padding(Brand.s5)
        .screen()
        .presentationDetents([.large])
        .task {
            let rows: [GroupPreview] = (try? await supabase.rpc("group_preview", params: ["code": code]).execute().value) ?? []
            preview = rows.first
            loaded = true
        }
        .problemAlert($problem)
    }

    private func join() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't join") {
            let id: UUID = try await supabase.rpc("join_group", params: ["code": code]).execute().value
            AppModel.shared.homeVersion += 1
            dismiss()
            joined(id)
        }
    }
}
