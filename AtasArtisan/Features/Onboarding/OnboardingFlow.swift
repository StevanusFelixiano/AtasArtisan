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
    }
    @State private var path: [Step] = []
    @State private var attempt = 0
    @Environment(AppModel.self) private var app
    /// 2-6b: an invite link opened before sign-in. Shown once; the code stays in `pendingJoin` and the join
    /// sheet opens by itself after sign-in.
    @State private var invitePrompted = false

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
                .navigationDestination(for: Step.self) { _ in
                    // 1-4b is shown over the verify step itself, so it fades in over the waiting screen.
                    VerifyStep { restart() }
                }
        }
        .sheet(isPresented: Binding(get: { app.pendingJoin != nil && !invitePrompted }, set: { if !$0 { invitePrompted = true } })) {
            JoinLoginPrompt(code: app.pendingJoin ?? "") {
                invitePrompted = true
                restart()
            }
        }
        .onAppear {
            switch DebugScreens.value("ATASTE_ONBOARD") {
            case "verify", "waiting", "expired", "nowa", "verified": path = [.verify(attempt: 0)]
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

// MARK: Verify + Waiting + Timed out + No WhatsApp (1-3, 1-4a, 1-4c, 1-4d), Verified (1-4b)

/// Motion board 16. Open WhatsApp hands off to WhatsApp; when the app comes back the code card turns into the code
/// chip (its sides and height on `Motion.doughLead`, its top on `Motion.doughTrail`, the code 40 → 15 pt), the giraffe
/// grows into the waiting pose as the ring fades in and turns a quarter, and the copy and button change. Timed out:
/// the chip shakes and the fresh code rolls in over it, the giraffe looks confused and the ring fades. Verified: the
/// ring turns once more, then the Cocoa screen fades in over this one and its parts arrive in order. Reduce Motion:
/// crossfades at the final size, the ring still. The polling and the endpoints are the same as before.
struct VerifyStep: View {
    var notMe: () -> Void

    // `expires_at` is left out: the functions client decodes dates with Foundation's default strategy, which
    // can't read Postgres timestamps, so including it failed every start. The server enforces expiry; the
    // countdown on 1-4a runs from when this app received the code (codes last 10 minutes).
    private struct Start: Decodable { var code: String; var message: String?; var nonce: String }
    private struct Status: Decodable { var status: String; var phone: String?; var push_name: String?; var token_hash: String? }
    private struct Verified { var phone: String; var name: String; var token: String }

    enum Wait { case starting, ready, waiting, expired, noWhatsApp }
    @State private var start: Start?
    @State private var expiresAt = Date()
    @State private var wait: Wait = .starting
    /// What the screen shows. It follows `wait`, except that after Open WhatsApp the move to 1-4a waits until the app
    /// is back, so the card turns into the chip in front of the person.
    @State private var shown: Wait = .starting
    @State private var awayForCode = false
    @State private var problem: Problem?
    @State private var wentAway = false
    @State private var verifiedAs: Verified?
    /// The bar goes once 1-4b has faded in over it; hiding it sooner shifts the waiting screen up under the fade.
    @State private var barHidden = false
    @State private var ringTurns = 0
    /// The code that ran out, kept on the chip until the fresh one rolls in over it (1-4c).
    @State private var oldCode: String?
    @State private var expiredAt = Date.distantPast
    @State private var timeouts = 0
    @State private var arrivals = 0
    /// Where each layout leaves room for the code (the card on 1-3, the chip on 1-4a), and the drawn surface's edges.
    @State private var cardSlot = CGRect.zero
    @State private var chipSlot = CGRect.zero
    @State private var edgeL: CGFloat = 0
    @State private var edgeR: CGFloat = 0
    @State private var edgeT: CGFloat = 0
    @State private var edgeH: CGFloat = 0
    @State private var surfaceChip = false
    /// The giraffe's spot in each layout (140 pt on 1-3, 206 pt on 1-4a), and where it is drawn.
    @State private var sendSpot = CGRect.zero
    @State private var waitSpot = CGRect.zero
    @State private var giraffeFrame = CGRect.zero
    @State private var giraffeWaits = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let whatsAppStore = URL(string: "https://apps.apple.com/app/whatsapp-messenger/id310633997")!
    private static let space = "verify"

    private static var windowTop: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.top ?? 0
    }

    private var chipLook: Bool { shown == .waiting || shown == .expired }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                content
                Spacer(minLength: Brand.s4)
                buttons
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, Brand.s4)
            .overlay(alignment: .topLeading) { giraffe }
            .overlay(alignment: .topLeading) { codeSurface }
            .coordinateSpace(.named(Self.space))
            .screen()
        }
        .overlay {
            // Laid out against the window's top inset, not the bar's: the bar is still up while 1-4b fades in, and a
            // taller overlay would otherwise push the waiting screen up under the fade.
            if let v = verifiedAs {
                VerifiedStep(phone: v.phone, suggestedName: v.name, token: v.token, notMe: notMe)
                    .ignoresSafeArea(.container, edges: .top)
                    .safeAreaPadding(.top, Self.windowTop)
                    .transition(.opacity)
            }
        }
        .navigationTitle(verifiedAs == nil ? "Verify" : "Verified")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar(barHidden ? .hidden : .automatic, for: .navigationBar)
        .navigationBarBackButtonHidden(barHidden)
        .task { await debugOrBegin() }
        .task(id: wait) { if wait == .waiting, DebugScreens.value("ATASTE_ONBOARD") == nil { await poll() } }
        .onChange(of: scenePhase) { _, p in
            // Back from WhatsApp without using our button (e.g. the code was typed by hand): start checking.
            if p == .background { wentAway = true }
            if p == .active, wentAway, wait == .ready, start != nil { wait = .waiting }
            if p == .active { cameBack() }
        }
        .onChange(of: wait) { old, new in
            if old == .waiting && new == .expired {
                expiredAt = .now
                timeouts += 1
            }
            if new == .waiting && awayForCode { return }
            show(new)
        }
        .onChange(of: chipLook ? chipSlot : cardSlot, initial: true) { _, rect in place(rect) }
        .onChange(of: chipLook ? waitSpot : sendSpot, initial: true) { _, rect in
            guard rect != .zero else { return }
            // A change of layout grows the giraffe from one spot to the other on `Motion.settle`; the first placement,
            // a layout change and Reduce Motion are still.
            if chipLook != giraffeWaits && giraffeFrame != .zero && !reduceMotion {
                withAnimation(Motion.settle) { giraffeFrame = rect }
            } else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { giraffeFrame = rect }
            }
            giraffeWaits = chipLook
        }
        .sensoryFeedback(Haptic.warn, trigger: timeouts)
        .sensoryFeedback(Haptic.done, trigger: arrivals)
        .problemAlert($problem)
    }

    @ViewBuilder private var content: some View {
        switch shown {
        case .starting, .ready:
            ready.transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fadeOut)))
        case .waiting, .expired:
            waiting.transition(.asymmetric(insertion: .opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(SignInMotion.waitInDelay)),
                                           removal: .opacity))
        case .noWhatsApp:
            noWhatsApp
        }
    }

    /// One giraffe drawn over the spot each layout leaves for it, so it grows from 1-3's 140 pt to 1-4a's 206 pt on
    /// `Motion.settle` as its pose crossfades (phone → waiting → confused).
    private var giraffe: some View {
        let (pose, fill): (String, Color) = switch shown {
        case .waiting: ("pose-waiting", Brand.choc100)
        case .expired: ("pose-confused", Brand.pink100)
        default: ("pose-phone", Brand.lime)
        }
        return ZStack {
            Circle().fill(fill).overlay { Image(pose).resizable().scaledToFill() }.clipShape(Circle())
                .id(pose)
                .transition(.opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fade))
        }
        .frame(width: giraffeFrame.width, height: giraffeFrame.height)
        .offset(x: giraffeFrame.minX, y: giraffeFrame.minY)
        .opacity(shown == .noWhatsApp || giraffeFrame == .zero ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Room for the giraffe in a layout, reported to `spot`.
    private func giraffeSpot(_ size: CGFloat, _ spot: Binding<CGRect>) -> some View {
        Color.clear.frame(width: size, height: size)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { spot.wrappedValue = $0 }
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
                giraffeSpot(SignInMotion.mascotSize.send, $sendSpot)
                // Room for the code card, drawn by `codeSurface`.
                cardFace(code: start?.code)
                    .hidden()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { cardSlot = $0 }
                Text("Send it from the WhatsApp you want to log in with. We read your number from the message.")
                    .obText(.callout, 14, Brand.ink2).lineSpacing(3).multilineTextAlignment(.center).frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Brand.s2)
        }
    }

    // 1-4a, and 1-4c in its place: the chip stays, the fresh code rolls in, the giraffe is confused, the ring fades.
    private var waiting: some View {
        let expired = shown == .expired
        return VStack(spacing: 30) {
            ZStack {
                ObRing(size: 250, turns: ringTurns)
                    .opacity(expired ? 0 : 1)
                    .animation(reduceMotion ? Motion.Reduced.fade : Motion.fade, value: expired)
                    .onAppear { if shown == .waiting { ringTurns += 1 } }
                giraffeSpot(SignInMotion.mascotSize.wait, $waitSpot)
            }
            ZStack {
                VStack(spacing: 10) {
                    Text(expired ? "We didn’t get your message" : "Checking your WhatsApp…").obText(.title1, 28).multilineTextAlignment(.center)
                    Text(expired ? "Codes last 10 minutes and this one ran out. Here’s a fresh one — send it the same way."
                                 : "This finishes by itself as soon as your message reaches us. You can leave and come back.")
                        .obText(.body, 15, Brand.ink2).lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 310)
                }
                .id(expired)
                .transition(.opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fade))
            }
            // Room for the code chip, drawn by `codeSurface`.
            chipFace(code: start?.code ?? oldCode)
                .hidden()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { chipSlot = $0 }
        }
        .padding(.top, 52)
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
        switch shown {
        case .noWhatsApp:
            VStack(spacing: 10) {
                Button("Get WhatsApp") { openURL(Self.whatsAppStore) }.buttonStyle(.pill(.primary))
                Button("I’ve installed it") { send() }.buttonStyle(.pill(.secondary))
            }
        default:
            // One button through 1-3, 1-4a and 1-4c: Dark → Secondary → Dark, its label rolling to the next.
            let title = switch shown { case .waiting: "Open WhatsApp again"; case .expired: "Send new code"; default: "Open WhatsApp" }
            let delay = shown == .waiting ? SignInMotion.waitInDelay : 0
            VStack(spacing: 12) {
                Button {
                    if shown == .expired && start == nil { Task { await renew() } } else { send() }
                } label: {
                    ZStack {
                        ObWhatsAppLabel(title: title).id(title)
                            .transition(AnyTransition.roll(reduceMotion).animation((reduceMotion ? Motion.Reduced.fade : Motion.digits).delay(delay)))
                    }
                }
                .buttonStyle(.pill(shown == .waiting ? .secondary : .dark))
                .disabled(!chipLook && start == nil)
                .animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(delay), value: shown)
                if !chipLook {
                    Text("Code works for this iPhone only, for 10 minutes").obText(.footnote, 12, Brand.ink3)
                        .transition(.opacity.animation(reduceMotion ? Motion.Reduced.fade : Motion.fadeOut))
                }
            }
        }
    }

    // MARK: The code card and chip

    /// 1-3's card: "Your code" over the code in Roundo 40, white with a dashed Caramel ring, radius 32.
    private func cardFace(code: String?) -> some View {
        VStack(spacing: Brand.s2) {
            Text("Your code").brand(.label, Brand.ink3)
            codeText(code, size: SignInMotion.codeSize.card)
        }
        .padding(.top, 22).padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    /// 1-4a's chip: the code at 15 pt, then "· m:ss left", on Liquorice 100.
    private func chipFace(code: String?) -> some View {
        HStack(spacing: Brand.s2) {
            codeText(code, size: SignInMotion.codeSize.chip)
            TimelineView(.periodic(from: .now, by: 1)) { t in
                Text("· \(remaining(at: t.date)) left").obText(.footnote, 12, Brand.ink2)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, Brand.s2)
    }

    private func codeText(_ code: String?, size: CGFloat) -> some View {
        Text(code ?? "ATASTE ····")
            .modifier(CodeType(size: size))
            .foregroundStyle(code == nil ? Brand.liquorice400 : Brand.cocoa)
            .lineLimit(1).minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, size > 20 ? Brand.s3 : 0)
    }

    /// The code surface, drawn over the slot of whichever layout is on show. Each edge rides its own spring, so it
    /// moves as one piece from the card to the chip; the fill, ring and radius crossfade while it moves.
    private var codeSurface: some View {
        EdgeValue(value: edgeL) { l in EdgeValue(value: edgeR) { r in EdgeValue(value: edgeT) { t in EdgeValue(value: edgeH) { h in
            surface
                .frame(width: max(0, r - l), height: max(0, h))
                .offset(x: l, y: t)
        } } } }
        .opacity(shown == .noWhatsApp || edgeH == 0 ? 0 : 1)
        .shake(reduceMotion ? 0 : timeouts)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(surfaceLabel)
        .accessibilityHidden(shown == .noWhatsApp)
    }

    private var surface: some View {
        let chip = surfaceChip
        let fill = reduceMotion ? Motion.Reduced.fade : Motion.fade
        let code = chip ? start?.code ?? oldCode : start?.code
        return ZStack {
            RoundedRectangle(cornerRadius: SignInMotion.cardRadius, style: .continuous).fill(Brand.card)
                .overlay(RoundedRectangle(cornerRadius: SignInMotion.cardRadius, style: .continuous)
                    .strokeBorder(Brand.caramel, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                .opacity(chip ? 0 : 1)
                .animation(fill, value: chip)
            Capsule().fill(Brand.liquorice100)
                .opacity(chip ? 1 : 0)
                .animation(fill, value: chip)
            if reduceMotion {
                // A crossfade at the final size.
                ZStack {
                    Group { if chip { chipFace(code: code) } else { cardFace(code: code) } }
                        .id(chip)
                        .transition(.opacity.animation(Motion.Reduced.fade))
                }
            } else {
                HStack(spacing: chip ? Brand.s2 : 0) {
                    VStack(spacing: chip ? 0 : Brand.s2) {
                        Text("Your code").brand(.label, Brand.ink3)
                            .fixedSize()
                            .frame(height: chip ? 0 : nil)
                            .opacity(chip ? 0 : 1)
                            .animation(chip ? Motion.fadeOut : Motion.fade, value: chip)
                        ZStack {
                            codeText(code, size: chip ? SignInMotion.codeSize.chip : SignInMotion.codeSize.card)
                                .id(code)
                                // The fresh code after a time-out rolls in 0.32 s after the shake.
                                .transition(shown == .expired ? AnyTransition(Roll()).animation(Motion.digits.delay(rollDelay)) : .identity)
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { t in
                        Text("· \(remaining(at: t.date)) left").obText(.footnote, 12, Brand.ink2).fixedSize()
                    }
                    .frame(width: chip ? nil : 0, alignment: .leading)
                    .clipped()
                    .opacity(chip ? 1 : 0)
                    .animation(chip ? Motion.fade.delay(SignInMotion.waitInDelay) : Motion.fadeOut, value: chip)
                }
                .padding(.horizontal, chip ? 18 : 0)
                .animation(Motion.settle, value: chip)
            }
        }
    }

    private var rollDelay: Double { max(0, SignInMotion.newCodeDelay - Date.now.timeIntervalSince(expiredAt)) }

    private var surfaceLabel: String {
        guard let code = surfaceChip ? start?.code ?? oldCode : start?.code else { return "Getting your code" }
        return surfaceChip ? "Code \(code), \(remaining(at: .now)) left" : "Your code, \(code)"
    }

    /// Moves the surface onto `rect`: a real change of look (card ↔ chip) travels; a layout change, the first
    /// placement and Reduce Motion are still.
    private func place(_ rect: CGRect) {
        guard rect != .zero else { return }
        let chip = chipLook
        if chip != surfaceChip && edgeH > 0 && !reduceMotion {
            withAnimation(Motion.doughLead) {
                edgeL = rect.minX
                edgeR = rect.maxX
                edgeH = rect.height
            }
            withAnimation(Motion.doughTrail) { edgeT = rect.minY }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { (edgeL, edgeR, edgeT, edgeH) = (rect.minX, rect.maxX, rect.minY, rect.height) }
        }
        surfaceChip = chip
    }

    // MARK: Steps

    /// Shows `w`: layouts change on `Motion.settle` (the giraffe's frame); every part carries its own timing.
    private func show(_ w: Wait) {
        guard w != shown else { return }
        if w == .waiting && shown == .expired { ringTurns += 1 }
        withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.settle) { shown = w }
    }

    /// The app is back from the WhatsApp hand-off: 1-3 turns into 1-4a now.
    private func cameBack() {
        guard awayForCode else { return }
        awayForCode = false
        show(wait)
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
        if state == "verified" { arrive(phone: "6281290345521", name: "Putri", token: "") }
    }

    private func begin() async {
        wait = .starting
        if await fetchCode() { wait = .ready } else { wait = .expired }
    }

    /// 1-4c: swap the expired code for a fresh one while the timed-out screen stays up.
    private func renew() async {
        if let code = start?.code { oldCode = code }
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
        // The screen changes once the app is back; if WhatsApp doesn't open, at once.
        if shown != .waiting { awayForCode = true }
        openURL(Links.whatsApp(Links.verifyNumber, text: start?.message ?? code)) { opened in if !opened { cameBack() } }
        wait = .waiting
    }

    /// Polls every 2 s until the bridge has seen the message, or the code expires.
    private func poll() async {
        guard let nonce = start?.nonce else { return }
        while !Task.isCancelled && wait == .waiting {
            if let s: Status = try? await supabase.functions.invoke("otp/status", options: .init(method: .get, query: [URLQueryItem(name: "nonce", value: nonce)])) {
                if s.status == "verified", let phone = s.phone, let token = s.token_hash {
                    arrive(phone: phone, name: s.push_name ?? "", token: token)
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

    /// The message arrived: the ring turns a quarter, then 1-4b fades in over this screen.
    private func arrive(phone: String, name: String, token: String) {
        ringTurns += 1
        arrivals += 1
        withAnimation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(SignInMotion.screenDelay)) {
            verifiedAs = Verified(phone: phone, name: name, token: token)
        } completion: {
            barHidden = true
        }
    }
}

/// Roundo 700 at a size that animates, its tracking going from the card's 0.05 em to the chip's 0.04 em with it.
private struct CodeType: ViewModifier, Animatable {
    var size: CGFloat
    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }
    func body(content: Content) -> some View {
        let card = SignInMotion.codeSize.card, chip = SignInMotion.codeSize.chip
        let em = 0.04 + 0.01 * max(0, min(1, (size - chip) / (card - chip)))
        return content.font(Font(Brand.uiFont(.roundo, size: size, weight: 700, relativeTo: .largeTitle))).tracking(size * em)
    }
}


// MARK: Verified (1-4b)

/// Shown over the waiting screen when the message arrives: the Cocoa screen fades in, the sunburst turns from −40° and
/// grows from 0.8, the lime disc pops, the celebrating giraffe rises 60 pt, "You’re in!" pops from 0.6 at −6°, the
/// verified line fades in and Continue rises 40 pt, then everything rests. Reduce Motion: the parts fade in and the
/// sunburst is still.
struct VerifiedStep: View {
    var phone: String
    var suggestedName: String
    var token: String
    var notMe: () -> Void
    @State private var busy = false
    @State private var problem: Problem?
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sun = SignInMotion.sunburst
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Brand.lime).frame(width: 300, height: 300)
                    .entrance(shown, scale: 0.01, Motion.pop, delay: SignInMotion.discDelay)
                Image("pose-celebrating").resizable().scaledToFill()
                    .frame(width: 270, height: 270)
                    .frame(width: 250, height: 250).clipShape(Circle())
                    .entrance(shown, offset: SignInMotion.mascot.offset, Motion.bounce, fade: nil, delay: SignInMotion.mascot.delay)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 500)
            // The 500 pt sunburst is wider than the screen: as a background it no longer widens the column (which pushed
            // Continue past both edges).
            .background {
                Rays(width: 9, period: 18).frame(width: 500, height: 500)
                    .rotationEffect(shown || reduceMotion ? .zero : sun.tilt)
                    .animation(shown && !reduceMotion ? Motion.glide.delay(sun.delay) : nil, value: shown)
                    .scaleEffect(shown || reduceMotion ? 1 : sun.scale)
                    .animation(shown && !reduceMotion ? Motion.settle.delay(sun.delay) : nil, value: shown)
            }
            .padding(.top, 28)
            VStack(spacing: 12) {
                Text("You’re in!").obText(.accent, 52, Brand.lime)
                    .entrance(shown, scale: SignInMotion.headline.scale, tilt: SignInMotion.headline.tilt, Motion.pop, delay: SignInMotion.headline.delay)
                HStack(spacing: Brand.s2) {
                    Image(systemName: "checkmark.circle").font(.system(size: 19, weight: .semibold)).foregroundStyle(Brand.lime)
                    Text("Verified as \(PhoneFormat.masked(phone))").obText(.headline, 16, weight: 600, Brand.cream)
                }
                .accessibilityElement(children: .combine)
                .entrance(shown, Motion.fade, delay: SignInMotion.lineDelay)
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
            .entrance(shown, offset: SignInMotion.continueButton.offset, Motion.arrive, fade: nil, delay: SignInMotion.continueButton.delay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.cocoa.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            NameStep.suggested = suggestedName
            shown = true
        }
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
        Button("Continue") { primer = true }.buttonStyle(.pill(.primary)).disabled(!valid, reason: "Type your name first")
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
