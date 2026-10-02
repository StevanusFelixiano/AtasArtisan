import SwiftUI
import Supabase
import CoreImage.CIFilterBuiltins

// MARK: Share (2-5)

struct ShareCard: View {
    var group: OrderGroup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var toast: String?

    private var link: URL { Links.join(group.code) }
    /// The link as the field shows it, without the scheme: "ataste.app/j/FRI-7Q2K".
    private var shownLink: String { (link.host() ?? "") + link.path() }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    Text(group.name).styled(.title2, 22).multilineTextAlignment(.center)
                    if let c = group.cutoff_at {
                        Label("Locks \(Wita.string(c, "EEE d MMM, HH:mm")) WITA", systemImage: "clock")
                            .labelStyle(TightLabel())
                            .styled(.callout, 13, weight: 600, Brand.caramel)
                    }
                    if let qr = QR.mask(link.absoluteString) {
                        Image(uiImage: qr).renderingMode(.template).interpolation(.none).resizable().scaledToFit()
                            .foregroundStyle(Brand.cocoa)
                            .frame(width: 176, height: 176)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.cream))
                            .accessibilityLabel("QR code for the join link")
                    }
                    HStack(spacing: 10) {
                        Text(shownLink).styled(.body, 15, weight: 600).lineLimit(1).minimumScaleFactor(0.75).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Button { copy(link.absoluteString, "Link copied", $toast) } label: {
                            Label("Copy link", systemImage: "doc.on.doc")
                                .labelStyle(TightLabel())
                                .styled(.callout, 14, weight: 600, Brand.cream)
                                .padding(.vertical, Brand.s2).padding(.horizontal, Brand.s4)
                                .background(Capsule().fill(Brand.caramel))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, Brand.s4).padding(.trailing, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Brand.cream))
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))

                HStack(spacing: 10) {
                    Button { openURL(Links.whatsApp("", text: shareText)) } label: {
                        HStack(spacing: Brand.s2) {
                            WAGlyph(size: 17)
                            Text("Send on WhatsApp").font(Brand.font(.headline, size: 15, weight: 600))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.dark, .medium))
                    Button { presentShare([shareText]) } label: {
                        // The secondary pill's colours on a 56pt round-ended square (the pill's 32pt sides don't fit).
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(Brand.cocoa)
                            .frame(width: 56, height: 52)
                            .background(Capsule().fill(Brand.cream))
                            .overlay(Capsule().strokeBorder(Brand.choc100, lineWidth: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More ways to share")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Brand.s2)
        }
        .screen()
        .navigationTitle("Invite people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        .toast($toast)
    }

    private var shareText: String {
        "Join \(group.name) on Ataste: \(link.absoluteString)\nNo app yet? Get Ataste: \(Links.getTheApp)"
    }
}

enum QR {
    /// The QR code as an alpha mask (modules opaque, the rest clear), to tint with `.foregroundStyle`.
    static func mask(_ s: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        let invert = CIFilter.colorInvert()
        invert.inputImage = f.outputImage
        let alpha = CIFilter.maskToAlpha()
        alpha.inputImage = invert.outputImage
        guard let out = alpha.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: Paste a join link (2-3)

/// Sheet for a link that opened in Safari instead of the app: reads the clipboard, previews the group, and hands
/// the code back for the join screen.
struct PasteLinkSheet: View {
    var choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// What was read from the clipboard; "Found in your clipboard" shows while the field still holds it.
    @State private var clipText: String?
    @State private var preview: JoinPreview?
    @State private var looked = false
    @FocusState private var focused: Bool

    /// https://…/join/ABC123, ataste://join/ABC123 or just ABC123.
    static func code(from s: String) -> String? {
        let last = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").last.map(String.init) ?? ""
        let code = last.split(separator: "?").first.map(String.init) ?? ""
        return code.count == 6 && code.allSatisfy { $0.isLetter || $0.isNumber } ? code.uppercased() : nil
    }

    private var code: String? { Self.code(from: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s4) {
            HStack {
                Text("Paste a join link").styled(.title2, 24)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Brand.cocoa)
                        .frame(width: 32, height: 32).background(Circle().fill(Brand.cocoa.opacity(0.08)))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            HStack(spacing: 10) {
                Image(systemName: "link").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.caramel)
                TextField("Link or code", text: $text)
                    .focused($focused)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(Brand.font(.body, size: 16, weight: 600)).foregroundStyle(Brand.cocoa)
                if text.isEmpty {
                    PasteButton(payloadType: String.self) { strings in text = strings.first ?? "" }
                        .labelStyle(.iconOnly).buttonBorderShape(.capsule).tint(Brand.caramel)
                }
            }
            .padding(.horizontal, Brand.s4)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.card))
            .overlay(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).strokeBorder(Brand.caramel, lineWidth: 2))

            if let p = preview {
                HStack(spacing: Brand.s3) {
                    Avatar(name: p.host_name, index: 1, host: true, size: 44, art: p.host_avatar, bg: p.host_avatar_bg)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).styled(.headline, 16)
                        Text(p.summary).styled(.body, 13, Brand.ink2)
                    }
                    Spacer(minLength: 0)
                    StateTag(state: p.state, size: .small)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
            } else if looked, code != nil {
                Text("No group found for this link. Ask your host to share it again.").brand(.callout, Brand.ink2)
            }

            Button("See the group") {
                guard let code else { return }
                choose(code)
                dismiss()
            }
            .buttonStyle(.pill(.primary))
            .disabled(code == nil || (looked && preview == nil))

            if let clipText, clipText == text {
                Text("Found in your clipboard").brand(.footnote, Brand.ink3).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, Brand.s5)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Brand.cream.ignoresSafeArea())
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .task {
            #if DEBUG
            if let s = DebugScreens.value("ATASTE_PASTE") { text = s; clipText = s; return }
            #endif
            // Only a link on the clipboard is read (reading asks the system's paste permission); otherwise the
            // field waits for typing or the Paste button.
            let link: Bool = await withCheckedContinuation { c in
                UIPasteboard.general.detectPatterns(for: [\.probableWebURL]) { r in
                    c.resume(returning: (try? r.get())?.contains(\.probableWebURL) ?? false)
                }
            }
            if link, let s = UIPasteboard.general.string, Self.code(from: s) != nil {
                text = s
                clipText = s
            } else {
                focused = true
            }
        }
        .task(id: code) {
            preview = nil
            looked = false
            guard let code else { return }
            preview = await JoinPreview.load(code)
            looked = true
        }
    }
}

// MARK: Join (2-6, 2-6c, 2-6d)

/// `group_preview` as the join screens read it. The optional fields are not in the RPC yet (see the report):
/// each screen shows them once the RPC returns them.
nonisolated struct JoinPreview: Decodable, Hashable {
    var id: UUID
    var name: String
    var host_name: String
    var area: String
    var delivery_at: Date
    var cutoff_at: Date?
    var state: GroupState
    var members: Int
    var already_member: Bool
    var pay_rule: String?
    var address_label: String?
    var subtotal: Int?
    var host_phone: String?
    var host_avatar: String?
    var host_avatar_bg: String?

    /// "Rani · 4 members · locks Thu 13:00"
    var summary: String {
        var parts = [host_name, "\(members) member\(members == 1 ? "" : "s")"]
        if let c = cutoff_at, state == .open { parts.append("locks \(Wita.string(c, "EEE HH:mm"))") }
        return parts.joined(separator: " · ")
    }

    @MainActor static func load(_ code: String) async -> JoinPreview? {
        let rows: [JoinPreview] = (try? await supabase.rpc("group_preview", params: ["code": code]).execute().value) ?? []
        return rows.first
    }
}

/// `web_invite`: what the invite web page shows, callable before sign-in. Gives the place and members' first names.
nonisolated struct WebInvite: Decodable, Hashable {
    var host_name: String
    var place: String
    var members: [String]

    @MainActor static func load(_ code: String) async -> WebInvite? {
        let rows: [WebInvite] = (try? await supabase.rpc("web_invite", params: ["code": code]).execute().value) ?? []
        return rows.first
    }
}

struct JoinSheet: View {
    var code: String
    var joined: (UUID) -> Void
    var startOwn: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var preview: JoinPreview?
    @State private var mine: [Item] = []
    @State private var web: WebInvite?
    @State private var loaded = false
    @State private var busy = false
    @State private var problem: Problem?

    var body: some View {
        Group {
            if let p = preview {
                if p.already_member { member(p) } else if p.state != .open { closed(p) } else { invite(p) }
            } else if loaded {
                VStack {
                    Spacer()
                    EmptyStateView(pose: "pose-confused", title: "Link not found", message: "Ask your host to share the link again.")
                    Spacer()
                }
                .overlay(alignment: .topLeading) { closeButton(dark: false) }
            } else {
                ProgressView().tint(Brand.caramel)
            }
        }
        .screen()
        .task {
            async let w = WebInvite.load(code)
            preview = await JoinPreview.load(code)
            web = await w
            if let p = preview, p.already_member, let me = AppModel.shared.userID {
                mine = (try? await supabase.from("items").select().eq("group_id", value: p.id).eq("owner_id", value: me)
                    .order("created_at").execute().value) ?? []
            }
            loaded = true
        }
        .problemAlert($problem)
    }

    // MARK: 2-6 Invite

    private func invite(_ p: JoinPreview) -> some View {
        ScrollView {
            ZStack(alignment: .top) {
                band(pose: "pose-waving", marquee: "YOU’RE INVITED • \(p.name.uppercased()) • FRESH FROM ATAS • ")
                VStack(alignment: .leading, spacing: Brand.s4) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(p.host_name) invited you").brand(.label, Brand.caramel)
                        Text(p.name).styled(.title1, 28)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        tile("Delivery", "\(Wita.string(p.delivery_at, "EEE d MMM, HH:mm")) WITA", p.address_label ?? web?.place ?? p.area, Brand.ink2, Brand.cream)
                        if let c = p.cutoff_at {
                            TimelineView(.everyMinute) { t in
                                tile("Cutoff", "\(Wita.string(c, "EEE, HH:mm")) WITA",
                                     c > t.date ? "in \(Countdown.text(to: c, now: t.date))" : "Locking now", Brand.caramel, Brand.choc100, labelInk: Brand.cocoa)
                            }
                        } else {
                            tile("Cutoff", "No cutoff", "\(p.host_name) locks it", Brand.caramel, Brand.choc100, labelInk: Brand.cocoa)
                        }
                    }
                    HStack(spacing: 10) {
                        HStack(spacing: -10) {
                            let names = Array((web?.members ?? [p.host_name]).prefix(3))
                            ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                                Avatar(name: n, index: i, size: 34, art: i == 0 ? p.host_avatar : nil, bg: i == 0 ? p.host_avatar_bg : nil, ring: Brand.card)
                            }
                        }
                        Text("\(p.members) member\(p.members == 1 ? "" : "s") so far").styled(.callout, 14, weight: 600)
                        Spacer(minLength: 0)
                        if let s = p.subtotal { Text("\(Rupiah.format(s)) so far").styled(.callout, 13, weight: 600, Brand.ink2) }
                    }
                    if let rule = p.pay_rule {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "list.bullet.rectangle.portrait").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.cocoa)
                            Text(ruleText(rule, host: p.host_name)).styled(.body, 13, Brand.ink2).lineSpacing(3)
                        }
                        .padding(Brand.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.cream))
                    }
                }
                .padding(22)
                .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
                .padding(.horizontal, Brand.s4)
                .padding(.top, 300)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topLeading) { closeButton(dark: true) }
        .safeAreaInset(edge: .bottom) {
            Button("Join") { Task { await join() } }
                .buttonStyle(.pill(.primary)).disabled(busy)
                .padding(.horizontal, Brand.s4).padding(.bottom, Brand.s4)
        }
    }

    private func ruleText(_ rule: String, host: String) -> AttributedString {
        let bold = rule == "pay_first" ? "Pay first." : "Order first."
        let rest = rule == "pay_first"
            ? " Everyone pays \(host) first, then \(host) sends the order to Atas."
            : " \(host) sends the order, then everyone pays the host once Atas confirms the bill."
        var head = AttributedString(bold)
        head.font = Brand.font(.body, size: 13, weight: 700)
        head.foregroundColor = Brand.cocoa
        return head + AttributedString(rest)
    }

    private func tile(_ label: String, _ value: String, _ note: String, _ noteInk: Color, _ fill: Color, labelInk: Color = Brand.ink3) -> some View {
        VStack(alignment: .leading, spacing: Brand.s1) {
            Text(label).styled(.label, 11, labelInk)
            Text(value).styled(.headline, 15)
            Text(note).styled(.footnote, 12, weight: noteInk == Brand.caramel ? 600 : 500, noteInk)
        }
        .padding(Brand.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(fill))
    }

    // MARK: 2-6d Already a member

    private func member(_ p: JoinPreview) -> some View {
        ScrollView {
            ZStack(alignment: .top) {
                band(pose: "pose-neutral", marquee: nil)
                VStack(alignment: .leading, spacing: 14) {
                    Text(p.name).styled(.title1, 28)
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle").font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.cocoa)
                        Text(mine.isEmpty ? "You’re already in this group." : "You’re already in this group, with \(itemCount) item\(itemCount == 1 ? "" : "s").")
                            .styled(.callout, 14, weight: 600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Brand.s3).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.lime))
                    .overlay(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).strokeBorder(Brand.limeDeep, lineWidth: 1.5))
                    if !mine.isEmpty {
                        Text(mine.map { "\($0.qty)× \($0.name)" }.joined(separator: ", ") + " · " + Rupiah.format(mine.reduce(0) { $0 + $1.total }))
                            .styled(.callout, 14, Brand.ink2).lineSpacing(3)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
                .padding(.horizontal, Brand.s4)
                .padding(.top, 300)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topLeading) { closeButton(dark: true) }
        .safeAreaInset(edge: .bottom) {
            Button("Open group") { dismiss(); joined(p.id) }
                .buttonStyle(.pill(.primary))
                .padding(.horizontal, Brand.s4).padding(.bottom, Brand.s4)
        }
    }

    private var itemCount: Int { mine.reduce(0) { $0 + $1.qty } }

    // MARK: 2-6c Locked or closed

    private func closed(_ p: JoinPreview) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                CaptionedPainting(art: "paint-gothic", title: "American Baguettic", width: 150, height: 186, tilt: 1.5)
                StateTag(state: p.state)
                Text("This oven door’s shut").styled(.title1, 28).multilineTextAlignment(.center)
                Text(closedText(p)).styled(.body, 15, Brand.ink2).lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Brand.s5)
            .padding(.top, 108)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topLeading) { closeButton(dark: false) }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let phone = p.host_phone {
                    Button { openURL(Links.whatsApp(phone)) } label: {
                        HStack(spacing: 10) { WAGlyph(size: 20); Text("Message \(p.host_name)") }
                    }
                    .buttonStyle(.pill(.dark))
                }
                Button("Start my own order") { startOwn(); dismiss() }
                    .buttonStyle(.pill(.secondary))
            }
            .padding(.horizontal, Brand.s4).padding(.bottom, Brand.s4)
        }
    }

    private func closedText(_ p: JoinPreview) -> String {
        switch p.state {
        case .locked, .edits:
            let at = p.cutoff_at.flatMap { $0 <= Date() ? " at \(Wita.string($0, "HH:mm"))" : nil } ?? ""
            return "\(p.name) locked\(at), so no one can join right now. Ask \(p.host_name) to unlock it, or start your own order."
        default:
            return "\(p.name) isn’t taking orders anymore. Start your own order instead."
        }
    }

    // MARK: Shared pieces

    /// The caramel band at the top of the invite: the giraffe in a choc100 circle, and a tilted marquee.
    private func band(pose: String, marquee: String?) -> some View {
        ZStack(alignment: .top) {
            Brand.caramel
            Mascot(pose: pose, size: 160, fill: Brand.choc100)
                .padding(.top, 76)
            if let marquee {
                Marquee(text: marquee, fill: Brand.cocoa, ink: Brand.choc100, speed: 28, tilt: -4)
                    .padding(.horizontal, -20)
                    .padding(.top, 250)
            }
        }
        .frame(height: 330)
        .clipped()
    }

    private func closeButton(dark: Bool) -> some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(dark ? Brand.cream : Brand.cocoa)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(dark ? .regular.tint(Brand.cocoa.opacity(0.45)).interactive() : .regular.interactive(), in: .circle)
        .padding(.leading, Brand.s4)
        .padding(.top, Brand.s1)
        .accessibilityLabel("Close")
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

// MARK: Join while signed out (2-6b)

/// Shown over the invite when a join link arrives before sign-in. `app.pendingJoin` already survives sign-in,
/// so the join screen opens by itself once the user is in. Wire it from the signed-out flow (see the report).
struct JoinLoginPrompt: View {
    var code: String
    var action: () -> Void
    @State private var hostName: String?

    var body: some View {
        VStack(spacing: 14) {
            Mascot(pose: "pose-phone", size: 96, fill: Brand.lime)
            Text(hostName.map { "Log in to join \($0)’s group" } ?? "Log in to join the group")
                .styled(.title2, 24).multilineTextAlignment(.center)
            Text("One WhatsApp message and you’re in. We’ll bring you straight back to this invite.")
                .styled(.body, 15, Brand.ink2).lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 310)
            Button(action: action) {
                HStack(spacing: 10) { WAGlyph(size: 20); Text("Continue with WhatsApp") }
            }
            .buttonStyle(.pill(.dark))
        }
        .padding(.horizontal, 20)
        .padding(.top, Brand.s5)
        .padding(.bottom, Brand.s4)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .task { hostName = await WebInvite.load(code)?.host_name }
    }
}
