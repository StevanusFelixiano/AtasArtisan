import SwiftUI
import Supabase

/// Board 1. Welcome → Verify via WhatsApp → Waiting → Verified "+62…" → (signed in) → Name → notification primer.
/// Reverse OTP: the user never types a number. They send "ATASTE 4K9X" from their own WhatsApp to our number,
/// the VPS bridge reads the sender, and `otp/status` hands back a one-time token for this app session.
struct OnboardingFlow: View {
    enum Step: Equatable { case welcome, verify, verified(phone: String, name: String, token: String) }
    @State private var step: Step = .welcome

    var body: some View {
        switch step {
        case .welcome: WelcomeStep { step = .verify }
        case .verify: VerifyStep { phone, name, token in step = .verified(phone: phone, name: name, token: token) }
        case let .verified(phone, name, token): VerifiedStep(phone: phone, suggestedName: name, token: token) { step = .verify }
        }
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
        VStack(spacing: Brand.s5) {
            Spacer(minLength: 0)
            Image("paint-croissant").resizable().scaledToFit()
                .frame(maxHeight: 300)
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Brand.caramel))
                .accessibilityLabel("Girl with a Croissant, a giraffe painting")
            LogoPill(size: 44)
                .onLongPressGesture(minimumDuration: 1.2) { askReview = true }
            Text("Group-order from Atas Artisan with your friends. Ataste collects everyone's order, splits the bill and writes the WhatsApp message.")
                .brand(.body, Brand.ink2).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button("Continue with WhatsApp", action: next).buttonStyle(.pill(.dark))
            LegalNote()
        }
        .padding(Brand.s5)
        .screen()
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

struct LogoPill: View {
    var size: CGFloat = 32
    var body: some View {
        Text("ataste")
            .font(Brand.font(.display, size: size))
            .foregroundStyle(Brand.cream)
            .padding(.horizontal, size * 0.55).padding(.vertical, size * 0.2)
            .background(Capsule().fill(Brand.caramel))
            .overlay(Capsule().stroke(Brand.caramel, lineWidth: 4))
            .background(Capsule().fill(Brand.cocoa).offset(y: size * 0.1))
            .overlay(alignment: .topLeading) {
                Image("icon-head").resizable().scaledToFit().frame(width: size * 1.1)
                    .offset(x: size * 0.4, y: -size * 0.8)
            }
            .padding(.top, size * 0.7)
            .accessibilityLabel("Ataste")
    }
}

// MARK: Verify + Waiting (1-3, 1-4)

struct VerifyStep: View {
    var verified: (_ phone: String, _ name: String, _ token: String) -> Void

    // `expires_at` is left out: the functions client decodes dates with Foundation's default strategy, which
    // can't read Postgres timestamps, so including it failed every start. The server enforces expiry.
    private struct Start: Decodable { var code: String; var nonce: String }
    private struct Status: Decodable { var status: String; var phone: String?; var push_name: String?; var token_hash: String? }

    enum Wait { case starting, ready, waiting, expired, noWhatsApp }
    @State private var start: Start?
    @State private var wait: Wait = .starting
    @State private var problem: Problem?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: Brand.s5) {
            Spacer(minLength: 0)
            Mascot(pose: wait == .expired ? "pose-confused" : "pose-phone", size: 170, fill: Brand.lime)
            switch wait {
            case .starting:
                ProgressView().tint(Brand.caramel)
            case .ready, .waiting:
                Text(wait == .waiting ? "Waiting for your message…" : "Verify with WhatsApp").brand(.title1).multilineTextAlignment(.center)
                Text("Tap the button. WhatsApp opens with this code already typed. Just press send.")
                    .brand(.body, Brand.ink2).multilineTextAlignment(.center)
                Text(start?.code ?? "").font(Brand.font(.hero, size: 40)).foregroundStyle(Brand.caramel)
                    .padding(.horizontal, Brand.s5).padding(.vertical, Brand.s3)
                    .background(RoundedRectangle(cornerRadius: Brand.rCard).fill(.white))
                    .accessibilityLabel("Code \(start?.code ?? "")")
                if wait == .waiting { ProgressView().tint(Brand.caramel) }
            case .expired:
                Text("That code expired").brand(.title1)
                Text("It's only valid for 10 minutes. Send a new one.").brand(.body, Brand.ink2).multilineTextAlignment(.center)
            case .noWhatsApp:
                Text("WhatsApp isn't installed").brand(.title1).multilineTextAlignment(.center)
                Text("Ataste verifies your number through WhatsApp. Install it, then come back.").brand(.body, Brand.ink2).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            switch wait {
            case .ready, .waiting: Button(wait == .waiting ? "Open WhatsApp again" : "Open WhatsApp") { send() }.buttonStyle(.pill(.dark))
            case .expired, .noWhatsApp: Button("Send again") { Task { await begin() } }.buttonStyle(.pill(.primary))
            case .starting: EmptyView()
            }
        }
        .padding(Brand.s5)
        .screen()
        .task { await begin() }
        .task(id: wait) { if wait == .waiting { await poll() } }
        .onChange(of: scenePhase) { _, p in if p == .active, wait == .ready, start != nil { wait = .waiting } }
        .problemAlert($problem)
    }

    private func begin() async {
        wait = .starting
        do {
            start = try await supabase.functions.invoke("otp/start", options: .init(method: .post))
            wait = .ready
        } catch where isCancellation(error) {
            return
        } catch {
            problem = Problem(title: "Couldn't start verification", message: readable(error))
            wait = .expired
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
                if s.status == "expired" { wait = .expired; return }
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
        VStack(spacing: Brand.s5) {
            Spacer(minLength: 0)
            Mascot(pose: "pose-celebrating", size: 190, fill: Brand.lime)
            Text("You're in!").font(Brand.font(.accent)).foregroundStyle(Brand.caramel)
            Text("Verified as \(PhoneFormat.display(phone))").brand(.title2).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button("Continue") { Task { await finish() } }.buttonStyle(.pill(.primary)).disabled(busy)
            Button("Not you? Try again", action: notMe).brand(.callout, Brand.caramel)
        }
        .padding(Brand.s5)
        .screen()
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
        guard p.hasPrefix("62"), p.count > 6 else { return "+" + p }
        let rest = Array(p.dropFirst(2))
        let a = String(rest.prefix(3)), b = String(rest.dropFirst(3).prefix(4)), c = String(rest.dropFirst(7))
        return "+62 " + [a, b, c].filter { !$0.isEmpty }.joined(separator: "-")
    }
}

// MARK: Name + notification primer (1-5, 1-6)

struct NameStep: View {
    static var suggested = ""
    @Environment(AppModel.self) private var app
    @State private var name = NameStep.suggested
    @State private var primer = false
    @State private var problem: Problem?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Brand.s5) {
            if primer {
                Spacer(minLength: 0)
                Mascot(pose: "pose-waving", size: 170, fill: Brand.pink100)
                Text("Stay in the loop").brand(.title1)
                VStack(alignment: .leading, spacing: Brand.s3) {
                    ForEach(["Someone joins your group or the cutoff is near", "The host needs you to change an item",
                             "Atas confirms and your bill is final", "Payments, and when the order arrives"], id: \.self) {
                        Label($0, systemImage: "bell.fill").brand(.body).labelStyle(.titleAndIcon)
                    }
                }
                .card()
                Spacer(minLength: 0)
                Button("Turn on notifications") { Task { await Notices.shared.requestPermission(); await save() } }
                    .buttonStyle(.pill(.primary))
                Button("Not now") { Task { await save() } }.brand(.callout, Brand.caramel)
            } else {
                Spacer(minLength: 0)
                Mascot(pose: "pose-neutral", size: 150)
                Text("What should we call you?").brand(.title1).multilineTextAlignment(.center)
                Text("Your group and Atas see this name on your items.").brand(.body, Brand.ink2).multilineTextAlignment(.center)
                TextField("Your name", text: $name)
                    .font(Brand.font(.headline))
                    .textContentType(.givenName)
                    .padding(Brand.s4)
                    .background(RoundedRectangle(cornerRadius: Brand.rField).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: Brand.rField).stroke(focused ? Brand.caramel : Brand.liquorice400, lineWidth: 2))
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit { if valid { primer = true } }
                Spacer(minLength: 0)
                Button("Continue") { primer = true }.buttonStyle(.pill(.primary)).disabled(!valid)
            }
        }
        .padding(Brand.s5)
        .screen()
        .problemAlert($problem)
    }

    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 60 }

    private func save() async {
        await attempt($problem, "Couldn't save your name") {
            try await app.saveProfile(name: name.trimmingCharacters(in: .whitespaces))
        }
    }
}
