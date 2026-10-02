import SwiftUI
import Supabase

// MARK: Create group (2-4, 2-4b, 2-4e)

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
    @State private var addingAddress = false
    @State private var addingAccount = false
    @State private var loaded = false
    @State private var busy = false
    @State private var problem: Problem?

    private var late: Bool { useCutoff && Wita.cutoffTooLate(cutoff: cutoff, delivery: delivery) }
    private var needsAccount: Bool { !personal && loaded && accounts.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !personal {
                    BrandField(label: "Group name", placeholder: "e.g. Friday Treats", text: $name)
                }
                deliverTo
                deliverySection
                if !personal {
                    cutoffCard
                    payRule
                    payYouAt
                }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.top, Brand.s2)
            .padding(.bottom, Brand.s5)
        }
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .navigationTitle(personal ? "Order for myself" : "New group order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
        }
        .safeAreaInset(edge: .bottom) { createBar }
        .task {
            await load()
            #if DEBUG
            switch HomeDebug.screen {
            case "nopay": accounts = []; accountID = nil
            case "late": cutoff = Wita.atasDeadline(for: delivery).addingTimeInterval(2 * 3600)
            case "payment": addingAccount = true
            case "address": addingAddress = true
            default: break
            }
            #endif
        }
        .sheet(isPresented: $addingAddress) {
            NavigationStack { NewAddressSheet { saved in addresses.append(saved); addressID = saved.id } }
        }
        .sheet(isPresented: $addingAccount) {
            NavigationStack {
                PayoutEditor(account: PayoutAccount(label: "BCA", account_name: app.profile?.name ?? "")) { saved in accounts.append(saved); accountID = saved.id }
            }
        }
        .onChange(of: delivery) { _, d in
            if useCutoff && cutoff > d { cutoff = Wita.atasDeadline(for: d).addingTimeInterval(-3600) }
        }
        .problemAlert($problem)
    }

    // MARK: Deliver to

    private var deliverTo: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            FieldLabel("Deliver to")
            ForEach(addresses) { a in
                PlaceRow(title: a.label, detail: place(a), icon: addressID == a.id ? "mappin" : "house", selected: addressID == a.id) { addressID = a.id }

            }
            PlaceRow(title: "Add new address", icon: "plus") { addingAddress = true }
        }
    }

    private func place(_ a: Address) -> String {
        if a.detail.isEmpty { return a.area }
        return a.detail.localizedCaseInsensitiveContains(a.area) ? a.detail : "\(a.detail), \(a.area)"
    }

    // MARK: Delivery and cutoff

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            FieldLabel("Delivery")
            HStack(spacing: 10) {
                DateField(date: $delivery, part: .date, title: "Delivery day") {
                    Label {
                        HStack(spacing: 6) {
                            Text(Wita.string(delivery, "EEE, d MMM")).styled(.body, 15, weight: 600)
                            if let rel = relativeDay(delivery) { Text("· \(rel)").brand(.footnote, Brand.ink3) }
                        }
                    } icon: { Image(systemName: "calendar").foregroundStyle(Brand.caramel) }
                    .labelStyle(FieldLabelStyle())
                    .fieldBox()
                }
                DateField(date: $delivery, part: .time, title: "Delivery time") {
                    Label { Text("\(Wita.string(delivery, "HH:mm")) WITA").styled(.body, 15, weight: 600) }
                        icon: { Image(systemName: "clock").foregroundStyle(Brand.caramel) }
                        .labelStyle(FieldLabelStyle())
                        .fieldBox()
                }
                .frame(width: 150)
            }
            Text("Defaults to tomorrow morning. Atas delivers in Bali only.")
                .brand(.footnote, Brand.ink3).padding(.leading, Brand.s1)
        }
    }

    private func relativeDay(_ d: Date) -> String? {
        let c = Wita.calendar
        if c.isDateInToday(d) { return "today" }
        if c.isDateInTomorrow(d) { return "tomorrow" }
        return nil
    }

    private var cutoffCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $useCutoff) { Text("Cutoff").styled(.headline, 16) }
                .tint(Brand.caramel)
            if useCutoff {
                HStack(spacing: 10) {
                    DateField(date: $cutoff, part: .date, title: "Cutoff day") {
                        Text(Wita.string(cutoff, "EEE, d MMM")).styled(.body, 15, weight: 600)
                            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Brand.rField, style: .continuous).fill(Brand.cream))
                    }
                    DateField(date: $cutoff, part: .time, title: "Cutoff time") {
                        Text("\(Wita.string(cutoff, "HH:mm")) WITA").styled(.body, 15, weight: 600)
                            .padding(.horizontal, late ? 12 : 14).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Brand.rField, style: .continuous).fill(late ? Brand.card : Brand.cream))
                            .overlay(RoundedRectangle(cornerRadius: Brand.rField, style: .continuous).strokeBorder(late ? Brand.choc400 : .clear, lineWidth: 2))
                    }
                    .frame(width: 130)
                }
            }
            if late {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.cocoa)
                    VStack(alignment: .leading, spacing: Brand.s1) {
                        Text("Atas’s cutoff is 3 PM. After that, delivery can take up to 2 days.").styled(.callout, 14, weight: 700)
                        Text("Set the cutoff before 15:00 WITA to keep \(Wita.string(delivery, "EEEE")) \(partOfDay(delivery)) delivery.")
                            .styled(.body, 13, Brand.ink2)
                    }
                }
                .padding(.vertical, Brand.s3).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.choc100))
                Button("Use 14:00 WITA") { cutoff = Wita.atasDeadline(for: delivery).addingTimeInterval(-3600) }
                    .font(Brand.font(.callout, size: 13, weight: 600)).foregroundStyle(Brand.cocoa)
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(Capsule().fill(Brand.cream)).overlay(Capsule().strokeBorder(Brand.liquorice400, lineWidth: 1.5))
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
            } else {
                Text("The group locks itself at cutoff. You can unlock it to give people more time.").styled(.body, 13, Brand.ink2)
            }
        }
        .padding(Brand.s4)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }

    private func partOfDay(_ d: Date) -> String {
        let h = Wita.calendar.component(.hour, from: d)
        return h < 12 ? "morning" : h < 17 ? "afternoon" : "evening"
    }

    // MARK: Payment rule and payout account

    private var payRule: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Payment rule")
            ChoiceCard(title: "Order first", detail: "Send the order to Atas without waiting. Everyone pays once the bill is final.", selected: !payFirst) { payFirst = false }
            ChoiceCard(title: "Pay first", detail: "Wait until everyone has paid you, then send the order.", selected: payFirst) { payFirst = true }
        }
    }

    @ViewBuilder private var payYouAt: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            FieldLabel("People pay you at")
            if needsAccount {
                VStack(spacing: 14) {
                    Mascot(pose: "pose-sleeping", size: 96, fill: Brand.liquorice100)
                    Text("No payment method…yet!").styled(.title2, 20)
                    Text("Add the bank or e-wallet your group should transfer to. It shows on everyone’s bill.")
                        .styled(.callout, 14, Brand.ink2).multilineTextAlignment(.center)
                    Button { addingAccount = true } label: { Label("Add payment method", systemImage: "plus") }
                        .buttonStyle(.pill(.dark, .medium))
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
                .overlay(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).strokeBorder(Brand.caramel, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            } else if let a = accounts.first(where: { $0.id == accountID }) ?? accounts.first {
                HStack(spacing: Brand.s3) {
                    Text(a.label).styled(.label, 11).padding(.vertical, 3).padding(.horizontal, 10).background(Capsule().fill(Brand.choc400))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.account_name).styled(.headline, 15)
                        Text(a.number).styled(.body, 13, Brand.ink2)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(accounts) { acc in
                            Button { accountID = acc.id } label: {
                                if acc.id == accountID { Label("\(acc.label) · \(acc.number)", systemImage: "checkmark") } else { Text("\(acc.label) · \(acc.number)") }
                            }
                        }
                        Divider()
                        Button { addingAccount = true } label: { Label("Add payment method", systemImage: "plus") }
                    } label: {
                        Text("Change").styled(.callout, 14, weight: 600, Brand.caramel).frame(minHeight: 44)
                    }
                }
                .padding(.vertical, 14).padding(.horizontal, Brand.s4)
                .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.card))
                .overlay(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).strokeBorder(Brand.liquorice100, lineWidth: 1.5))
            }
        }
    }

    // MARK: Create bar

    private var createBar: some View {
        VStack(spacing: 0) {
            Button(personal ? "Start my order" : "Create group") { Task { await create() } }
                .buttonStyle(.pill(.primary))
                .disabled(!valid || busy)
            if needsAccount {
                Text("Add a payment method to continue").brand(.footnote, Brand.ink2).padding(.top, Brand.s2).padding(.bottom, 2)
            }
        }
        .padding(Brand.s3)
        .glassEffect(.regular.tint(Brand.cream.opacity(0.4)), in: .rect(cornerRadius: 36))
        .padding(.horizontal, Brand.s3)
        .padding(.bottom, Brand.s1)
    }

    private var valid: Bool {
        addressID != nil && (personal || (!name.trimmingCharacters(in: .whitespaces).isEmpty && accountID != nil))
    }

    private func load() async {
        addresses = (try? await supabase.from("addresses").select().order("created_at").execute().value) ?? []
        accounts = (try? await supabase.from("payout_accounts").select().eq("user_id", value: app.userID ?? UUID()).order("created_at").execute().value) ?? []
        addressID = addressID ?? addresses.first?.id
        accountID = accountID ?? accounts.first?.id
        loaded = true
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

/// Icon 10pt before the text, the way the board's date and time fields draw it.
private struct FieldLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) { configuration.icon.font(.system(size: 16, weight: .semibold)); configuration.title }
    }
}

/// A field that opens a date or time picker in a small sheet (all times WITA).
struct DateField<Content: View>: View {
    enum Part { case date, time }
    @Binding var date: Date
    var part: Part
    var title: String
    @ViewBuilder var content: Content
    @State private var open = false

    var body: some View {
        Button { open = true } label: { content.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(Wita.string(date, part == .date ? "EEEE d MMMM" : "HH:mm")) WITA")
            .sheet(isPresented: $open) {
                NavigationStack {
                    Group {
                        if part == .date {
                            DatePicker(title, selection: $date, in: Date()..., displayedComponents: .date).datePickerStyle(.graphical)
                        } else {
                            DatePicker(title, selection: $date, displayedComponents: .hourAndMinute).datePickerStyle(.wheel)
                        }
                    }
                    .labelsHidden()
                    .tint(Brand.caramel)
                    .environment(\.timeZone, Wita.zone)
                    .padding(.horizontal, Brand.s4)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .screen()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { open = false } } }
                }
                .presentationDetents([part == .date ? .height(480) : .height(320)])
            }
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - s.height) / 2), proposal: .unspecified)
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + s.width <= width {
                rows[rows.count - 1].items.append(i)
                rows[rows.count - 1].width += spacing + s.width
                rows[rows.count - 1].height = max(last.height, s.height)
            } else {
                rows.append(([i], s.width, s.height))
            }
        }
        return rows
    }
}

// MARK: New address (2-4f)

struct NewAddressSheet: View {
    var saved: (Address) -> Void
    @State private var address = Address(area: "")
    @Environment(\.dismiss) private var dismiss
    @State private var problem: Problem?
    @State private var busy = false
    /// Places in Bali people pick that Atas does not deliver to; choosing one explains why it can't be saved.
    private static let elsewhere = ["Amed", "Bedugul", "Candidasa", "Gianyar", "Karangasem", "Klungkung", "Lovina", "Negara", "Singaraja", "Tulamben"]

    private var outside: Bool { !address.area.isEmpty && !Areas.all.contains(address.area) }
    private var mapsOK: Bool { address.maps_url.isEmpty || address.maps_url.hasPrefix("https://") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s4) {
                BrandField(label: "Name", placeholder: "e.g. Academy Bali", text: $address.label)
                BrandField(label: "Street", placeholder: "Street, building, landmark", text: $address.detail, multiline: true)
                VStack(alignment: .leading, spacing: Brand.s2) {
                    FieldLabel("Area")
                    Menu {
                        Picker("Atas delivers to", selection: $address.area) { ForEach(Areas.all, id: \.self) { Text($0).tag($0) } }
                        Section("Elsewhere in Bali") {
                            Picker("Elsewhere in Bali", selection: $address.area) { ForEach(Self.elsewhere, id: \.self) { Text($0).tag($0) } }
                        }
                    } label: {
                        HStack {
                            Text(address.area.isEmpty ? "Choose an area" : address.area)
                                .styled(.body, 16, weight: 600, address.area.isEmpty ? Brand.ink3 : Brand.cocoa)
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.cocoa)
                        }
                        .fieldBox(error: outside)
                    }
                    .accessibilityLabel("Area, \(address.area.isEmpty ? "not chosen" : address.area)")
                    if outside {
                        Label("Atas doesn’t deliver here", systemImage: "exclamationmark.triangle")
                            .labelStyle(TightLabel())
                            .styled(.callout, 14, weight: 600, Brand.destructive)
                            .padding(.leading, Brand.s1)
                    }
                }
                VStack(alignment: .leading, spacing: Brand.s2) {
                    Text("Atas delivers to").brand(.label)
                    Text(Areas.all.joined(separator: " · ")).styled(.body, 13, Brand.ink2).lineSpacing(4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.card))
                VStack(alignment: .leading, spacing: Brand.s2) {
                    BrandField(label: "Google Maps link", placeholder: "https://maps.app.goo.gl/…", text: $address.maps_url,
                               error: mapsOK ? nil : "Paste a link that starts with https://", keyboard: .URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Goes into the order message as \"Link alamat\" so the courier finds you.")
                        .styled(.body, 13, Brand.ink2).padding(.leading, Brand.s1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Brand.s2)
            .padding(.bottom, Brand.s5)
        }
        .foregroundStyle(Brand.cocoa)
        .screen()
        .navigationTitle("New address")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(busy || address.label.trimmingCharacters(in: .whitespaces).isEmpty || address.area.isEmpty || outside || !mapsOK)
            }
        }
        #if DEBUG
        .task { if HomeDebug.screen == "address" { address.label = "Kevin’s family"; address.detail = "Jl. Ngurah Rai 21"; address.area = "Singaraja" } }
        #endif
        .problemAlert($problem)
    }

    private func save() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't save") {
            var a = address
            a.user_id = nil
            let row: Address = try await supabase.from("addresses").upsert(a).select().single().execute().value
            saved(row)
            dismiss()
        }
    }
}

// MARK: Group created (2-4d)

/// The empty group a host lands on right after creating it: The Birth of Brioche and a nudge to share the link.
/// GroupView shows this in place of the member list while the group is open and has no items.
struct GroupBornState: View {
    var group: OrderGroup
    var body: some View {
        VStack(spacing: 0) {
            CaptionedPainting(art: "paint-brioche", title: "The Birth of Brioche", width: 200, height: 254, tilt: 1.5)
                .padding(.bottom, Brand.s5)
            VStack(spacing: Brand.s2) {
                Text("Your group is born!").styled(.title1, 26).multilineTextAlignment(.center)
                Text(message).styled(.body, 15, Brand.ink2).lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var message: String {
        guard let c = group.cutoff_at else { return "No orders yet. Share the link so everyone can add theirs." }
        return "No orders yet. Share the link so everyone can add theirs before \(Wita.string(c, "EEEE HH:mm")) WITA."
    }
}

