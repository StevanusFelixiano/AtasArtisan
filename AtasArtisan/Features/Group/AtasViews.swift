import SwiftUI
import Supabase

/// 4.12 Send to Atas (5-1, 5-1b). The message in the hosts' own format (Indonesian by default, English
/// selectable), editable, sent from the host's own WhatsApp to Atas (0821-3145-473). Switching the language rolls the
/// message to the other one while the card settles to its height (Motion board 17).
/// Pay first under Rp 200.000 before the ongkir is in, the same screen asks Atas for the ongkir instead (G-2b): just
/// the question, no item list, and coming back marks it asked.
struct SendToAtasView: View {
    var store: GroupStore
    /// Open WhatsApp was tapped: the group screen plays 5-2 in when the app comes back.
    var handedOff: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app
    @State private var language = 0
    @State private var text = ""
    /// A language switch in progress: still copies of the old and new message roll over the hidden field.
    @State private var rolling: Rolling?
    @FocusState private var editing: Bool

    private var indonesian: Bool { language == 0 }
    private var asking: Bool { store.group?.payPhase == .asking }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Mascot(pose: "pose-phone", size: 64, fill: Brand.lime)
                    Text(asking ? "Just the question, no item list. The full order goes once everyone has paid."
                                : "This is the message Atas will get. Tap to edit anything before you open WhatsApp.")
                        .font(Type5.manrope(14)).lineSpacing(1).foregroundStyle(Brand.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
                Segmented(options: ["Bahasa Indonesia", "English"], selection: Binding(get: { language }, set: { l in
                    let old = text
                    language = l
                    text = message()
                    rolling = Rolling(old: old, new: text)
                }))
                // A labelled container: on the control itself the label would replace each segment's own.
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Message language")
                // The message rolls to the other language (`Motion.digits`): still copies of the old and new message
                // roll over the field (a text field draws its new text at once, so it can't roll itself), then the
                // field shows again. The card is sized by the new message and settles to its height on
                // `Motion.settle`. Reduce Motion: a crossfade, the height snaps.
                TextField("Message", text: $text, axis: .vertical)
                    .font(Type5.manrope(14))
                    .lineSpacing(2)
                    .foregroundStyle(Brand.cocoa)
                    .tint(Brand.caramel)
                    .focused($editing)
                    .opacity(rolling == nil ? 1 : 0)
                    .overlay(alignment: .topLeading) {
                        if let rolling {
                            MessageRoll(rolling: rolling) { if self.rolling?.id == rolling.id { self.rolling = nil } }
                                .id(rolling.id)
                        }
                    }
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
                .animation(reduceMotion ? nil : Motion.settle, value: language)
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
                AsyncPill(busyTitle: "Sending…", doneTitle: asking ? "Asked" : "Sent", failTitle: asking ? "Couldn’t mark it asked" : "Couldn’t mark it sent",
                          kind: .dark, refresh: store.refresh,
                          reached: { asking ? store.group?.ongkir_asked_at != nil : store.group?.state == .sent }) {
                    if asking {
                        openURL(Links.whatsApp(Links.atasNumber, text: text))
                        try await store.rpc("mark_ongkir_asked", ["g": .string(store.id.uuidString)])
                    } else {
                        handedOff()
                        openURL(Links.whatsApp(Links.atasNumber, text: text))
                        try await store.rpc("mark_sent", ["g": .string(store.id.uuidString)])
                    }
                } then: {
                    dismiss()
                } idle: {
                    Label { Text("Open WhatsApp") } icon: { WhatsAppGlyph(size: 20) }
                }
                .disabled(text.isEmpty, reason: "The message is empty")
                if !asking { cutoff }
            }
        }
        .navigationTitle(asking ? "Ask Atas for ongkir" : "Send to Atas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
        }
        .onAppear {
            language = (store.group?.msg_lang ?? app.profile?.msg_lang ?? "id") == "id" ? 0 : 1
            text = message()
        }
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
        // Pay first with the ongkir entered: the closing line repeats what Atas quoted.
        let agreed = g.payFirst && g.billFinal && g.ongkir_set_at != nil ? (ongkir: g.ongkir ?? 0, discount: g.discount ?? 0) : nil
        let order = AtasOrder(hostName: host?.name ?? "", hostPhone: host?.phone ?? "",
                              place: g.address_label, address: g.address_detail == g.address_label ? "" : g.address_detail,
                              mapsURL: g.maps_url, delivery: g.delivery_at, people: people, agreed: agreed)
        return asking ? AtasMessage.askOngkir(order, indonesian: indonesian) : AtasMessage.text(order, indonesian: indonesian)
    }

}

private struct Rolling: Identifiable {
    let id = UUID()
    var old: String
    var new: String
}

/// The Send to Atas message rolling once to the other language: the old one leaves upwards and the new one comes up
/// from 8 pt below (`Roll` on `Motion.digits`), then `done` hands back to the field. Reduce Motion crossfades.
private struct MessageRoll: View {
    var rolling: Rolling
    var done: () -> Void
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = reduceMotion ? 0 : StatusMotion.labelOffset
        ZStack(alignment: .topLeading) {
            copy(rolling.old).offset(y: on ? -d : 0).opacity(on ? 0 : 1)
            copy(rolling.new).offset(y: on ? 0 : d).opacity(on ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.digits, completionCriteria: .logicallyComplete) { on = true } completion: { done() }
        }
    }

    private func copy(_ text: String) -> some View {
        Text(text).font(Type5.manrope(14)).lineSpacing(2).foregroundStyle(Brand.cocoa)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 4.12 Confirm with Atas (5-3, Testing Fixes E). From Rp 200.000 the ongkir is free: no inputs, a Free ongkir card
/// and Continue (E-1). Under it (E-2), copy the ongkir and discount from Atas's reply; both are optional, empty counts
/// as Rp 0 and the button is never disabled. Every row updates on each keystroke, whichever field comes first; the
/// net is split between the members with items (each share truncated to Rp 100, the host takes the rest); a discount
/// bigger than the ongkir gets a gentle note. Order first: confirm_atas freezes the bill and moves the order to
/// Confirmed. Pay first, before sending: set_bill makes the bills final and payments open (it can be reopened until
/// the order is sent).
struct ConfirmAtasView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ongkir = ""
    @State private var discount = ""
    @State private var busy = false
    @State private var confirms = 0
    @State private var problem: Problem?
    @FocusState private var field: Field?

    private enum Field { case ongkir, discount }

    /// Pay first before sending: the amounts go in with set_bill and the order stays locked.
    private var payFirst: Bool { store.group?.payFirst == true && store.group?.state == .locked }
    private var free: Bool { Ongkir.isFree(subtotal: store.subtotal) }
    private var o: Int { Int(ongkir) ?? 0 }
    /// The discount as the server applies it: never more than items + ongkir.
    private var d: Int { Ongkir.cappedDiscount(Int(discount) ?? 0, subtotal: store.subtotal, ongkir: o) }
    private var net: Int { o - d }
    /// Everyone with items, and the host (who takes the rounding even with none), in join order.
    private var rows: [BillRow] {
        store.bill.filter { $0.items > 0 || $0.user_id == store.group?.host_id }
            .sorted { store.colorIndex($0.user_id) < store.colorIndex($1.user_id) }
    }
    private var payers: Int { store.bill.filter { $0.items > 0 }.count }
    private var shares: [Int] {
        Ongkir.shares(net: net, bills: rows.map { ($0.items, $0.user_id == store.group?.host_id) })
    }
    /// The discount note: bigger than the ongkir, or a discount with no ongkir at all.
    private var note: String? {
        let typed = Int(discount) ?? 0
        guard typed > o else { return nil }
        return o == 0 ? "There’s a discount but no ongkir. Worth a second look at Atas’s reply, it usually only comes off the ongkir."
            : "The discount (\(Rupiah.format(typed))) is bigger than the ongkir (\(Rupiah.format(o))). Worth a second look at Atas’s reply, it usually only comes off the ongkir."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if free { freeContent } else { amountsContent }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.top, 10)
            .padding(.bottom, Brand.s4)
        }
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .safeAreaInset(edge: .bottom) {
            GlassBar {
                Button(free ? "Continue" : "Atas confirmed", systemImage: "checkmark") { Task { await confirm() } }
                    .buttonStyle(.pill(.primary))
                    .disabled(busy)
                Text(free ? "Everyone’s bill is final now." : "Empty fields count as Rp 0. This freezes the bill.")
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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if field == .ongkir { Button("Next") { field = .discount } } else { Button("Done") { field = nil } }
            }
        }
        .sensoryFeedback(Haptic.warn, trigger: note != nil) { !$0 && $1 }
        .sensoryFeedback(Haptic.done, trigger: confirms)
        .problemAlert($problem)
        .onAppear {
            // Pay first reopening the ongkir before sending: start from what was entered.
            if let g = store.group, payFirst, g.ongkir_set_at != nil {
                ongkir = (g.ongkir ?? 0) > 0 ? String(g.ongkir ?? 0) : ""
                discount = (g.discount ?? 0) > 0 ? String(g.discount ?? 0) : ""
            }
            #if DEBUG
            // Screenshot hook for 5-3: "30000,15000" fills both fields and focuses the discount.
            if let v = DebugScreens.value("ATASTE_CONFIRM")?.split(separator: ",", omittingEmptySubsequences: false), v.count == 2 {
                ongkir = String(v[0]); discount = String(v[1]); field = .discount
            }
            #endif
        }
    }

    // MARK: E-1 · free ongkir

    @ViewBuilder private var freeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Free ongkir").font(GFont.shrikhand(34)).foregroundStyle(Brand.cocoa)
            Text("\(Rupiah.format(store.subtotal)) is over Rp 200.000, so Atas doesn’t charge ongkir. There’s nothing to type.")
                .font(Type5.manrope(14, 600)).lineSpacing(1).foregroundStyle(Brand.cocoa)
                .frame(maxWidth: 270, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 22).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            Rays(color: .white).frame(width: 220, height: 220).opacity(0.7).offset(x: 60, y: -60)
        }
        .background(Brand.lime)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Brand.limeDeep, lineWidth: 2))
        .accessibilityElement(children: .combine)
        VStack(alignment: .leading, spacing: 8) {
            totalsRow("Items", Text(Rupiah.format(store.subtotal)))
            totalsRow("Ongkir", Text("Free").foregroundStyle(Brand.lime))
            totalLine(store.subtotal)
            Text("Nothing is added to anyone’s bill").font(Type5.manrope(13, 600)).foregroundStyle(Brand.lime)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.cocoa))
        .accessibilityElement(children: .combine)
        if !rows.isEmpty { people(before: false) }
    }

    // MARK: E-2 · under Rp 200.000

    @ViewBuilder private var amountsContent: some View {
        Text("Copy the numbers from Atas’s reply. Leave a field empty if Atas didn’t mention it. Both are split equally between the \(payers) member\(payers == 1 ? "" : "s") with items.")
            .font(Type5.manrope(14)).lineSpacing(1).foregroundStyle(Brand.ink2)
            .padding(.horizontal, 4)
        amountField("Ongkir", prefix: "Rp", text: $ongkir, .ongkir)
        amountField("Discount", prefix: "− Rp", text: $discount, .discount)
        if let note {
            Label { Text(note) } icon: { icon("exclamationmark.triangle", 17) }
                .labelStyle(IconLabel(spacing: 10, size: 17))
                .font(Type5.manrope(13, 600)).lineSpacing(1).foregroundStyle(Brand.cocoa)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.choc100))
                .transition(reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade)
                            : .asymmetric(insertion: .opacity.animation(Motion.fade.delay(OngkirMotion.noteFadeDelay)),
                                          removal: .opacity.animation(Motion.fadeOut)))
        }
        totals
        if !rows.isEmpty { people(before: true) }
    }

    /// "ONGKIR · optional" above a 56 pt white field with the "Rp" prefix and the amount in Roundo, dots as you type,
    /// 7 digits at most; the focused one gets the caramel edge and the choc-100 halo.
    private func amountField(_ label: String, prefix: String, text: Binding<String>, _ which: Field) -> some View {
        let on = field == which
        let shape = RoundedRectangle(cornerRadius: Brand.rField, style: .continuous)
        let shown = Binding<String>(
            get: { text.wrappedValue.isEmpty ? "" : Rupiah.bare(Int(text.wrappedValue) ?? 0) },
            set: { text.wrappedValue = String($0.filter(\.isNumber).drop { $0 == "0" }.prefix(OngkirMotion.maxDigits)) })
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(Text(label.uppercased()).font(Type5.manrope(12, 600)).tracking(12 * 0.03).foregroundStyle(Brand.cocoa))\(Text(" · optional").font(Type5.manrope(12)).foregroundStyle(Brand.ink3))")
                .padding(.leading, 4)
            HStack(spacing: 8) {
                Text(prefix).font(Type5.manrope(16, 600)).foregroundStyle(Brand.ink3)
                TextField("0", text: shown, prompt: Text("0").foregroundStyle(Brand.ink4))
                    .font(Type5.roundo(20))
                    .foregroundStyle(Brand.cocoa)
                    .tint(Brand.caramel)
                    .keyboardType(.numberPad)
                    .focused($field, equals: which)
                    .accessibilityLabel("\(label), optional")
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

    /// Cocoa card: items, ongkir, discount, the total, and what each bill gains or loses. Values roll on each keystroke.
    private var totals: some View {
        let each = Ongkir.each(net: net, payers: payers)
        return VStack(alignment: .leading, spacing: 8) {
            totalsRow("Items", Text(Rupiah.format(store.subtotal)))
            totalsRow("Ongkir", rolling("+ \(Rupiah.format(o))", o))
            totalsRow("Discount", rolling("− \(Rupiah.format(d))", d))
            totalLine(store.subtotal + net)
            rolling(each > 0 ? "+ \(Rupiah.format(each)) on each of \(payers) bills"
                    : each < 0 ? "− \(Rupiah.format(-each)) off each of \(payers) bills" : "Nothing added to the bills", each)
                .font(Type5.manrope(13, 600)).foregroundStyle(Brand.lime)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.cocoa))
        .animation(reduceMotion ? nil : OngkirMotion.noteIn, value: note != nil)
        .accessibilityElement(children: .combine)
    }

    private func rolling(_ s: String, _ value: Int) -> some View {
        Text(s)
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
            .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: value)
    }

    private func totalsRow(_ label: String, _ value: some View) -> some View {
        HStack {
            Text(label).foregroundStyle(Brand.liquorice400)
            Spacer()
            value.foregroundStyle(Brand.cream)
        }
        .font(Type5.manrope(14, 600))
    }

    private func totalLine(_ total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Total").font(Type5.manrope(12, 600)).tracking(12 * 0.03).textCase(.uppercase)
            Spacer()
            rolling(Rupiah.format(total), total).font(Type5.roundo(30)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Brand.cream)
        .padding(.top, 8)
        .overlay(alignment: .top) { DashedRule(color: Brand.cream.opacity(0.25)) }
    }

    /// Each person's items and their bill once this is confirmed (the host takes the rounding, as the view does).
    private func people(before: Bool) -> some View {
        let shares = shares
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.user_id) { i, r in
                let after = r.items + (free ? 0 : shares[i])
                HStack(spacing: 10) {
                    Avatar(name: store.name(r.user_id), index: store.colorIndex(r.user_id), size: 28, art: store.people[r.user_id]?.avatar,
                           bg: store.people[r.user_id]?.avatar_bg)
                    Text(store.name(r.user_id)).font(Type5.manrope(14, 600)).foregroundStyle(Brand.cocoa)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if before { Text(Rupiah.bare(r.items)).font(Type5.manrope(12)).foregroundStyle(Brand.ink3) }
                    rolling(Rupiah.format(after), after).font(Type5.roundo(15)).foregroundStyle(Brand.cocoa)
                        .frame(minWidth: 88, alignment: .trailing)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if i < rows.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
    }

    private func confirm() async {
        busy = true
        defer { busy = false }
        let amounts: [String: AnyJSON] = ["g": .string(store.id.uuidString), "ongkir": .integer(free ? 0 : o), "discount": .integer(free ? 0 : d)]
        await attempt($problem, "Couldn't confirm") {
            try await store.rpc(payFirst ? "set_bill" : "confirm_atas", amounts)
            confirms += 1
            dismiss()
        }
    }
}
