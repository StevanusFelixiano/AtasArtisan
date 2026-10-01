import SwiftUI
import Supabase

/// Board 1. Welcome → Verify via WhatsApp → Waiting → Verified "+62…" → (signed in) → Name → notification primer.
/// Reverse OTP: the user never types a number. They send "ATASTE 4K9X" from their own WhatsApp to our number,
/// the VPS bridge reads the sender, and `otp/status` hands back a one-time token for this app session.
///
/// DEBUG hook `ATASTE_ONBOARD` = splash | verify | waiting | expired | nowa | verified | name | primer renders one
/// state without the network (no code is requested, nothing is sent).
struct OnboardingFlow: View {
    enum Step: Hashable {
        /// `attempt` gives each new verification its own view identity, so "Try again" starts fresh.
        case verify(attempt: Int)
        case verified(phone: String, name: String, token: String)
    }
    @State private var path: [Step] = []
    @State private var attempt = 0

    var body: some View {
        switch DebugScreens.value("ATASTE_ONBOARD") {
        case "splash": SplashView()
        case "name", "primer": NameStep(debugPrimer: DebugScreens.value("ATASTE_ONBOARD") == "primer")
        default: flow
        }
    }

    private var flow: some View {
        NavigationStack(path: $path) {
            WelcomeStep { restart() }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .verify:
                        VerifyStep { phone, name, token in path.append(.verified(phone: phone, name: name, token: token)) }
                    case let .verified(phone, name, token):
                        VerifiedStep(phone: phone, suggestedName: name, token: token) { restart() }
                    }
                }
        }
        .onAppear {
            switch DebugScreens.value("ATASTE_ONBOARD") {
            case "verify", "waiting", "expired", "nowa": path = [.verify(attempt: 0)]
            case "verified": path = [.verify(attempt: 0), .verified(phone: "6281290345521", name: "Putri", token: "")]
            default: break
            }
        }
    }

    private func restart() {
        attempt += 1
        path = [.verify(attempt: attempt)]
    }
}

// MARK: Welcome (1-2)

struct WelcomeStep: View {
    var next: () -> Void
    @State private var askReview = false
    @State private var reviewCode = ""
    @State private var problem: Problem?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            LogoPill(size: 22)
                .onLongPressGesture(minimumDuration: 1.2) { askReview = true }
                .padding(.top, 8)
            ZStack(alignment: .top) {
                PaintingFrame(art: "paint-croissant", width: 218, height: 276, frame: 12, mat: 6, tilt: -2.5)
                    .accessibilityElement().accessibilityLabel("Girl with a Croissant, a giraffe painting")
                Marquee(tilt: -3).padding(.top, 290)
            }
            .padding(.top, 20)
            ObCaption(title: "Girl with a Croissant").padding(.top, 24)
            Spacer(minLength: Brand.s4)
            VStack(alignment: .leading, spacing: 14) {
                // The board balances the heading over two lines: "One order for / the whole group."
                Text("One order for\nthe whole group.")
                    .obText(.display, 36, tracking: -0.02)
                    .lineSpacing(-4)
                    .accessibilityLabel("One order for the whole group.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ataste collects everyone’s Atas Artisan order, checks it, splits the bill and writes the WhatsApp message for you.")
                    .obText(.body, 16, Brand.ink2).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: next) { ObWhatsAppLabel(title: "Continue with WhatsApp") }
                    .buttonStyle(.pill(.dark))
                    .padding(.top, 10)
                LegalNote().frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Brand.s5)
            .padding(.bottom, Brand.s2)
        }
        .screen()
        .navigationTitle("Welcome")
        .toolbar(.hidden, for: .navigationBar)
        .disabled(busy)
        .alert("App Review", isPresented: $askReview) {
            TextField("Review code", text: $reviewCode).textInputAutocapitalization(.characters)
            Button("Sign in") { Task { await review() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Enter the code from the App Review notes.") }
        .problemAlert($problem)
        .task {
            if let code = DebugScreens.value("ATASTE_REVIEW_CODE") { reviewCode = code; await review() }
        }
    }

    private func review() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't sign in") {
            struct Reply: Decodable { var token_hash: String }
            let reply: Reply = try await supabase.functions.invoke("otp/review", options: .init(method: .post, body: ["code": reviewCode]))
            try await supabase.auth.verifyOTP(tokenHash: reply.token_hash, type: .magiclink)
        }
    }
}

struct LegalNote: View {
    var body: some View {
        Text("By continuing you agree to the [Terms](\(Links.terms.absoluteString)) and [Privacy Policy](\(Links.privacy.absoluteString)). Ataste is not affiliated with Atas Artisan.")
            .brand(.footnote, Brand.ink3).multilineTextAlignment(.center).tint(Brand.caramel)
    }
}

/// The caramel "ataste" pill sitting on a cocoa offset shadow (1-2's header logo).
struct LogoPill: View {
    var size: CGFloat = 22
    var body: some View {
        Text("ataste")
            .font(Brand.font(.display, size: size))
            .foregroundStyle(Brand.cream)
            .padding(.horizontal, size * 0.64).padding(.top, size * 0.14).padding(.bottom, size * 0.27)
            .background(Capsule().fill(Brand.caramel))
            .background(Capsule().fill(Brand.cocoa).offset(y: size * 0.14))
            .accessibilityLabel("Ataste")
    }
}

// MARK: Verify + Waiting + Timed out + No WhatsApp (1-3, 1-4a, 1-4c, 1-4d)

struct VerifyStep: View {
    var verified: (_ phone: String, _ name: String, _ token: String) -> Void

    // `expires_at` is left out: the functions client decodes dates with Foundation's default strategy, which
    // can't read Postgres timestamps, so including it failed every start. The server enforces expiry; the
    // countdown on 1-4a runs from when this app received the code (codes last 10 minutes).
    private struct Start: Decodable { var code: String; var nonce: String }
    private struct Status: Decodable { var status: String; var phone: String?; var push_name: String?; var token_hash: String? }

    enum Wait { case starting, ready, waiting, expired, noWhatsApp }
    @State private var start: Start?
    @State private var expiresAt = Date()
    @State private var wait: Wait = .starting
    @State private var problem: Problem?
    @State private var wentAway = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private static let whatsAppStore = URL(string: "https://apps.apple.com/app/whatsapp-messenger/id310633997")!

    var body: some View {
        VStack(spacing: 0) {
            switch wait {
            case .starting, .ready: ready
            case .waiting: waiting
            case .expired: expired
            case .noWhatsApp: noWhatsApp
            }
            Spacer(minLength: Brand.s4)
            buttons
        }
        .padding(.horizontal, Brand.s4)
        .padding(.bottom, Brand.s4)
        .screen()
        .navigationTitle("Verify")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .task { await debugOrBegin() }
        .task(id: wait) { if wait == .waiting, DebugScreens.value("ATASTE_ONBOARD") == nil { await poll() } }
        .onChange(of: scenePhase) { _, p in
            // Back from WhatsApp without using our button (e.g. the code was typed by hand): start checking.
            if p == .background { wentAway = true }
            if p == .active, wentAway, wait == .ready, start != nil { wait = .waiting }
        }
        .problemAlert($problem)
    }

    // 1-3
    private var ready: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Send us one message").obText(.title1, 32, tracking: -0.01)
                Text("Tap the button. WhatsApp opens with a code already typed — just press send.")
                    .obText(.body, 16, Brand.ink2).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Brand.s2)
            .padding(.top, 6)
            Spacer(minLength: Brand.s4).frame(maxHeight: 74)
            VStack(spacing: 18) {
                Mascot(pose: "pose-phone", size: 140, fill: Brand.lime)
                VStack(spacing: Brand.s2) {
                    Text("Your code").brand(.label, Brand.ink3)
                    codeText(size: 40, tracking: 0.05)
                }
                .padding(.top, 22).padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
                .overlay(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).strokeBorder(Brand.caramel, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                Text("Send it from the WhatsApp you want to log in with. We read your number from the message.")
                    .obText(.callout, 14, Brand.ink2).lineSpacing(3).multilineTextAlignment(.center).frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Brand.s2)
        }
    }

    // 1-4a
    private var waiting: some View {
        VStack(spacing: 30) {
            ZStack {
                ObSpinRing(size: 250)
                Mascot(pose: "pose-waiting", size: 206, fill: Brand.choc100)
            }
            VStack(spacing: 10) {
                Text("Checking your WhatsApp…").obText(.title1, 28).multilineTextAlignment(.center)
                Text("This finishes by itself as soon as your message reaches us. You can leave and come back.")
                    .obText(.body, 15, Brand.ink2).lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 310)
            }
            TimelineView(.periodic(from: .now, by: 1)) { t in
                HStack(spacing: Brand.s2) {
                    Text(start?.code ?? "").obText(.headline, 15, tracking: 0.04)
                    Text("· \(remaining(at: t.date)) left").obText(.footnote, 12, Brand.ink2)
                }
                .padding(.horizontal, 18).padding(.vertical, Brand.s2)
                .background(Capsule().fill(Brand.liquorice100))
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.top, 52)
    }

    // 1-4c: the old code ran out; a fresh one is already fetched and shown.
    private var expired: some View {
        VStack(spacing: 20) {
            Mascot(pose: "pose-confused", size: 180, fill: Brand.pink100)
            Text("We didn’t get your message").obText(.title1, 28).multilineTextAlignment(.center)
            Text("Codes last 10 minutes and this one ran out. Here’s a fresh one — send it the same way.")
                .obText(.body, 15, Brand.ink2).lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 320)
            codeText(size: 36, tracking: 0.06)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
                .overlay(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).strokeBorder(Brand.caramel, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        }
        .padding(.horizontal, Brand.s2)
        .padding(.top, 72)
    }

    // 1-4d
    private var noWhatsApp: some View {
        VStack(spacing: 20) {
            Mascot(pose: "pose-confused", size: 180, fill: Brand.pink100)
            Text("WhatsApp isn’t on this iPhone").obText(.title1, 28).multilineTextAlignment(.center)
            Text("Ataste logs you in with one WhatsApp message, and the group order goes to Atas on WhatsApp too. Install it, then come back — your code will still be here.")
                .obText(.body, 15, Brand.ink2).lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .padding(.horizontal, Brand.s2)
        .padding(.top, 72)
    }

    @ViewBuilder private var buttons: some View {
        switch wait {
        case .starting, .ready:
            VStack(spacing: 12) {
                Button { send() } label: { ObWhatsAppLabel(title: "Open WhatsApp") }
                    .buttonStyle(.pill(.dark)).disabled(start == nil)
                Text("Code works for this iPhone only, for 10 minutes").obText(.footnote, 12, Brand.ink3)
            }
        case .waiting:
            Button { send() } label: { ObWhatsAppLabel(title: "Open WhatsApp again") }.buttonStyle(.pill(.secondary))
        case .expired:
            Button { if start == nil { Task { await renew() } } else { send() } } label: { ObWhatsAppLabel(title: "Send new code") }
                .buttonStyle(.pill(.dark))
        case .noWhatsApp:
            VStack(spacing: 10) {
                Button("Get WhatsApp") { openURL(Self.whatsAppStore) }.buttonStyle(.pill(.primary))
                Button("I’ve installed it") { send() }.buttonStyle(.pill(.secondary))
            }
        }
    }

    private func codeText(size: CGFloat, tracking: CGFloat) -> some View {
        Text(start?.code ?? "ATASTE ····")
            .obText(.display, size, tracking: tracking, start == nil ? Brand.liquorice400 : Brand.cocoa)
            .lineLimit(1).minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Brand.s3)
            .accessibilityLabel(start.map { "Code \($0.code)" } ?? "Getting your code")
    }

    private func remaining(at now: Date) -> String {
        let s = max(0, Int(expiresAt.timeIntervalSince(now)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private func debugOrBegin() async {
        guard let state = DebugScreens.value("ATASTE_ONBOARD") else { await begin(); return }
        start = Start(code: state == "expired" ? "ATASTE 7HQ2" : "ATASTE 4K9X", nonce: "")
        expiresAt = Date().addingTimeInterval(522)
        wait = switch state { case "waiting": .waiting; case "expired": .expired; case "nowa": .noWhatsApp; default: .ready }
    }

    private func begin() async {
        wait = .starting
        if await fetchCode() { wait = .ready } else { wait = .expired }
    }

    /// 1-4c: swap the expired code for a fresh one while the timed-out screen stays up.
    private func renew() async {
        start = nil
        _ = await fetchCode()
    }

    private func fetchCode() async -> Bool {
        do {
            start = try await supabase.functions.invoke("otp/start", options: .init(method: .post))
            expiresAt = Date().addingTimeInterval(600)
            return true
        } catch where isCancellation(error) {
            return false
        } catch {
            problem = Problem(title: "Couldn't start verification", message: readable(error))
            return false
        }
    }

    private func send() {
        guard let code = start?.code else { return }
        guard UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!) else { wait = .noWhatsApp; return }
        openURL(Links.whatsApp(Links.verifyNumber, text: code))
        wait = .waiting
    }

    /// Polls every 2 s until the bridge has seen the message, or the code expires.
    private func poll() async {
        guard let nonce = start?.nonce else { return }
        while !Task.isCancelled && wait == .waiting {
            if let s: Status = try? await supabase.functions.invoke("otp/status", options: .init(method: .get, query: [URLQueryItem(name: "nonce", value: nonce)])) {
                if s.status == "verified", let phone = s.phone, let token = s.token_hash {
                    verified(phone, s.push_name ?? "", token)
                    return
                }
                if s.status == "expired" {
                    wait = .expired
                    await renew()
                    return
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

// MARK: Verified (1-4b)

struct VerifiedStep: View {
    var phone: String
    var suggestedName: String
    var token: String
    var notMe: () -> Void
    @State private var busy = false
    @State private var problem: Problem?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rays().frame(width: 500, height: 500)
                Circle().fill(Brand.lime).frame(width: 300, height: 300)
                Image("pose-celebrating").resizable().scaledToFill()
                    .frame(width: 270, height: 270)
                    .frame(width: 250, height: 250).clipShape(Circle())
                    .accessibilityHidden(true)
            }
            .frame(height: 500)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            VStack(spacing: 12) {
                Text("You’re in!").obText(.accent, 52, Brand.lime)
                HStack(spacing: Brand.s2) {
                    Image(systemName: "checkmark.circle").font(.system(size: 19, weight: .semibold)).foregroundStyle(Brand.lime)
                    Text("Verified as \(PhoneFormat.masked(phone))").obText(.headline, 16, weight: 600, Brand.cream)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.top, 22)
            Spacer(minLength: Brand.s4)
            VStack(spacing: 12) {
                Button("Continue") { Task { await finish() } }
                    .buttonStyle(.pill(.success))
                    .disabled(busy)
                Button(action: notMe) {
                    (Text("Not you? ").foregroundStyle(Brand.liquorice400) + Text("Try again").bold().foregroundStyle(Brand.choc100))
                        .font(Brand.font(.callout, size: 14))
                }
                .frame(minHeight: 44)
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, Brand.s2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.cocoa.ignoresSafeArea())
        .navigationTitle("Verified")
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.dark)
        .onAppear { NameStep.suggested = suggestedName }
        .problemAlert($problem)
    }

    private func finish() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't sign in") {
            try await supabase.auth.verifyOTP(tokenHash: token, type: .magiclink)
        }
    }
}

enum PhoneFormat {
    /// 6281277882210 → "+62 812-7788-2210"
    static func display(_ p: String) -> String {
        groups(p).map { "+62 " + $0.joined(separator: "-") } ?? "+" + p
    }

    /// 6281290345521 → "+62 812-xxxx-5521" (1-4b: confirms the number without showing all of it).
    static func masked(_ p: String) -> String {
        guard var g = groups(p), g.count == 3 else { return display(p) }
        g[1] = String(repeating: "x", count: g[1].count)
        return "+62 " + g.joined(separator: "-")
    }

    /// 6281290345521 → "+62 812 9034 5521" (6-5 Profile).
    static func spaced(_ p: String) -> String {
        groups(p).map { "+62 " + $0.joined(separator: " ") } ?? "+" + p
    }

    private static func groups(_ p: String) -> [String]? {
        guard p.hasPrefix("62"), p.count > 6 else { return nil }
        let rest = Array(p.dropFirst(2))
        return [String(rest.prefix(3)), String(rest.dropFirst(3).prefix(4)), String(rest.dropFirst(7))].filter { !$0.isEmpty }
    }
}

// MARK: Name + notification primer (1-5, 1-6)

struct NameStep: View {
    static var suggested = ""
    var debugPrimer = false
    @Environment(AppModel.self) private var app
    @State private var name = NameStep.suggested
    @State private var primer = false
    @State private var problem: Problem?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if primer { primerContent } else { nameContent }
        }
        .padding(.horizontal, Brand.s4)
        .padding(.bottom, Brand.s4)
        .screen()
        .problemAlert($problem)
        .onAppear { if debugPrimer { primer = true } else if DebugScreens.value("ATASTE_ONBOARD") == "name" { name = "Putri"; focused = true } }
    }

    // 1-5
    @ViewBuilder private var nameContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: Brand.s2) {
                PaintingFrame(art: "paint-vangogh", width: 120, height: 149, tilt: -2)
                    .accessibilityElement().accessibilityLabel("Self-Portrait as Vincent van Dough, a giraffe painting")
                ObCaption(title: "Self-Portrait as Vincent van Dough")
            }
            Text("What should the group call you?").obText(.title1, 32, tracking: -0.01)
                .fixedSize(horizontal: false, vertical: true)
            Text("Shown to your group, and on every item Atas packs for you.")
                .obText(.body, 15, Brand.ink2).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            TextField("Your name", text: $name)
                .font(Brand.font(.headline, size: 20, weight: 600))
                .foregroundStyle(Brand.cocoa)
                .tint(Brand.caramel)
                .textContentType(.givenName)
                .padding(.horizontal, 18)
                .frame(height: 60)
                .background(RoundedRectangle(cornerRadius: Brand.rSmall).fill(Brand.card))
                .overlay(RoundedRectangle(cornerRadius: Brand.rSmall).strokeBorder(focused ? Brand.caramel : Brand.liquorice400, lineWidth: 2))
                .background(RoundedRectangle(cornerRadius: Brand.rSmall + 4).fill(focused ? Brand.choc100 : .clear).padding(-4))
                .focused($focused)
                .submitLabel(.continue)
                .onSubmit { if valid { primer = true } }
                .padding(.top, 12)
            Text("First name is fine. You can change it in Profile.").obText(.footnote, 13, Brand.ink3)
        }
        .padding(.horizontal, Brand.s2)
        .padding(.top, 48)
        Spacer(minLength: Brand.s4)
        Button("Continue") { primer = true }.buttonStyle(.pill(.primary)).disabled(!valid)
    }

    // 1-6
    @ViewBuilder private var primerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Mascot(pose: "pose-waving", size: 84, fill: Brand.choc100)
                Text("Psst!").obText(.accent, 30, Brand.caramel)
            }
            Text("Want a nudge when it matters?").obText(.title1, 32, tracking: -0.01).fixedSize(horizontal: false, vertical: true)
            Text("Only for things that need you. No promos.").obText(.body, 15, Brand.ink2)
        }
        .padding(.horizontal, Brand.s2)
        .padding(.top, 34)
        Spacer(minLength: Brand.s4).frame(maxHeight: 40)
        VStack(spacing: 0) {
            let rows: [(String, String, Color)] = [
                ("clock", "Cutoff in 30 minutes, and when the group locks", Brand.choc100),
                ("pencil", "The host asks you to change an item", Brand.pink100),
                ("chart.pie", "Someone wants to split an item with you", Brand.pink100),
                ("list.bullet.rectangle.portrait", "Your bill is final, and what you owe", Brand.lime),
                ("truck.box", "Your order is delivered", Brand.liquorice100),
            ]
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 14) {
                    Image(systemName: rows[i].0).font(.system(size: 16, weight: .medium)).foregroundStyle(Brand.cocoa)
                        .frame(width: 36, height: 36).background(Circle().fill(rows[i].2))
                    Text(rows[i].1).obText(.headline, 15, weight: 600).lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) { if i < rows.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) } }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
        Spacer(minLength: Brand.s4)
        VStack(spacing: 10) {
            Button { Task { await Notices.shared.requestPermission(); await save() } } label: { Label("Turn on notifications", systemImage: "bell") }
                .buttonStyle(.pill(.primary))
            Button("Not now") { Task { await save() } }
                .obText(.headline, 16, weight: 600, Brand.ink2).frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 60 }

    private func save() async {
        await attempt($problem, "Couldn't save your name") {
            try await app.saveProfile(name: name.trimmingCharacters(in: .whitespaces))
        }
    }
}
