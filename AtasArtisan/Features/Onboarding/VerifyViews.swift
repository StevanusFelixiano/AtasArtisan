import SwiftUI
import Supabase

// Board 9: verifying a WhatsApp number is optional and earns the Verified badge; hosting needs it. The verify screens
// themselves (9-4a to 9-5) are `VerifyStep` and `VerifiedStep`; this file has what leads into them and out of them:
// the intro (9-3), the hosting gate (9-6), "This number already has an account" (9-7) and the Apple ID link (9-8).

/// Where a verification started, which decides 9-5's button and where it goes.
enum VerifyOrigin: Hashable {
    case onboarding, profile
    /// The hosting gate: a group order, or a personal one ("Order for myself").
    case gate(group: Bool)

    var continueTitle: String {
        switch self {
        case .gate(group: true): "Set up your group"
        case .gate(group: false): "Set up your order"
        default: "Continue"
        }
    }
}

/// How a verification ended: 9-5's Continue, or "Do it later" / back out of 9-7.
enum VerifyEnd { case verified, later }

/// A verification, pushed on the current stack. 9-5's "Not your number? Try again" starts a fresh one in place.
struct VerifyFlow: View {
    var origin: VerifyOrigin
    var finish: (VerifyEnd) -> Void
    @State private var attempt = 0

    var body: some View {
        VerifyStep(origin: origin, retry: { attempt += 1 }, finish: finish).id(attempt)
    }
}

// MARK: Verify intro (9-3)

/// Shown once, after the name (9-2) and before the notification primer (1-6). Later goes on to 1-6; after that the
/// badge is offered only from Profile and the hosting gate.
struct VerifyIntro: View {
    var name: String
    var avatar: String?
    var bg: String?
    var verify: () -> Void
    var later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Get the Verified badge").obText(.title1, 32, tracking: -0.01).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Send one WhatsApp message from your number. We read the phone number from it and nothing else.")
                    .obText(.body, 15, Brand.ink2).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Brand.s2)
            .padding(.top, 48)
            HStack(spacing: 14) {
                Avatar(name: name, index: 2, size: 56, art: avatar, bg: bg)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(name).font(GFont.roundo(22)).foregroundStyle(Brand.cocoa).lineLimit(1)
                        VerifiedBadge()
                    }
                    Text("How your group will see you").obText(.callout, 13, Brand.ink3)
                }
            }
            .padding(.vertical, 16).padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Brand.card))
            .accessibilityElement(children: .combine)
            .padding(.top, 24)
            VStack(spacing: 0) {
                let rows: [(icon: AnyView, fill: Color, text: String)] = [
                    (AnyView(Image(systemName: "person.2").font(.system(size: 15, weight: .semibold))), Brand.choc100, "Start and host your own group orders"),
                    (AnyView(WhatsAppGlyph(size: 18)), Brand.lime, "Your host can reach you on WhatsApp"),
                    (AnyView(Image(systemName: "lock").font(.system(size: 15, weight: .semibold))), Brand.liquorice100, "Only your number is read. No chats, no contacts."),
                ]
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 14) {
                        rows[i].icon.foregroundStyle(Brand.cocoa).frame(width: 36, height: 36).background(Circle().fill(rows[i].fill))
                        Text(rows[i].text).obText(.headline, 15, weight: 600).lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) { if i < rows.count - 1 { Rectangle().fill(Brand.liquorice100).frame(height: 1) } }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
            .padding(.top, 12)
            Text("Joining groups, ordering and paying work without it.").obText(.callout, 13, Brand.ink3)
                .padding(.horizontal, Brand.s2).padding(.top, 14)
            Spacer(minLength: Brand.s4)
            VStack(spacing: 10) {
                Button(action: verify) { ObWhatsAppLabel(title: "Verify with WhatsApp") }
                    .buttonStyle(.pill(.primary))
                Button("Later", action: later)
                    .obText(.headline, 16, weight: 600, Brand.ink2).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
}

// MARK: Hosting gate (9-6)

/// Starting a group, or a personal order, without a verified number. Atas needs the number in every order message.
struct GateRequest: Identifiable, Hashable {
    var group: Bool
    var id: Bool { group }
}

struct HostingGateSheet: View {
    var verify: () -> Void
    @Environment(\.closeSheet) private var close

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Verify your number to host").font(GFont.roundo(24)).foregroundStyle(Brand.cocoa)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                reason("Members pay you, so they see your bank or e-wallet account.") {
                    Image(systemName: "list.bullet.rectangle.portrait").font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32).background(Circle().fill(Brand.choc100))
                }
                reason("Atas needs your number in the order message.") {
                    WhatsAppGlyph(size: 16).frame(width: 32, height: 32).background(Circle().fill(Brand.lime))
                }
                reason("The Verified badge tells members the number is really yours.") {
                    VerifiedBadge(size: .dot, ring: .clear).frame(width: 32, height: 32)
                }
            }
            Text("One WhatsApp message, about a minute.").font(GFont.manrope(13)).foregroundStyle(Brand.ink2)
            HStack(spacing: 10) {
                Button { close?() } label: { Text("Not now").padding(.horizontal, 16) }
                    .buttonStyle(PillStyle(kind: .secondary, size: .medium, tight: true))
                Button {
                    verify()
                    close?()
                } label: {
                    Label { Text("Verify with WhatsApp") } icon: { ObWhatsAppGlyph(size: 18) }.frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(kind: .primary, size: .medium, tight: true))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reason(_ text: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon().foregroundStyle(Brand.cocoa)
            Text(text).font(GFont.manrope(15)).lineSpacing(3).foregroundStyle(Brand.cocoa)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
        }
    }
}

extension View {
    /// 9-6 while `request` is set: Not now drops it; Verify with WhatsApp pushes 9-4a on the current stack, and once the
    /// number is verified (9-5 "Set up your group") `proceed` runs with the request.
    func hostingGate(_ request: Binding<GateRequest?>, proceed: @escaping (GateRequest) -> Void) -> some View {
        modifier(HostingGate(request: request, proceed: proceed))
    }
}

private struct HostingGate: ViewModifier {
    @Binding var request: GateRequest?
    var proceed: (GateRequest) -> Void
    /// Verify was tapped: pushed once the sheet has gone (a push under a leaving cover can be dropped).
    @State private var pending: GateRequest?
    @State private var verifying: GateRequest?
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .doughSheet(item: $request) { r in HostingGateSheet { pending = r } }
            .onChange(of: request == nil) { _, gone in
                if gone, let p = pending {
                    pending = nil
                    verifying = p
                }
            }
            .navigationDestination(item: $verifying) { r in
                VerifyFlow(origin: .gate(group: r.group)) { end in
                    Task {
                        if end == .verified { await app.loadProfile() }
                        verifying = nil
                        guard end == .verified else { return }
                        // After the pop, so the create sheet opens over the screen the gate was on.
                        try? await Task.sleep(for: .seconds(0.45))
                        proceed(r)
                    }
                }
            }
    }
}

/// `otp/status` for a verify-mode code: pending | expired | verified (the number is on the profile now) | taken (9-7).
nonisolated struct VerifyStatus: Decodable {
    var status: String
    var phone: String?
    var account: TakenAccount?

    @MainActor static func check(_ nonce: String) async -> VerifyStatus? {
        try? await supabase.functions.invoke("otp/status", options: .init(method: .get, query: [URLQueryItem(name: "nonce", value: nonce)]))
    }
}

// MARK: Number has an account (9-7)

/// The account a verified number already belongs to (`otp/status` "taken").
nonisolated struct TakenAccount: Decodable, Hashable {
    var name: String
    var avatar: String?
    var avatar_bg: String?
    var groups: Int
}

nonisolated struct Taken: Identifiable, Hashable {
    var nonce: String
    var phone: String
    var account: TakenAccount
    var id: String { nonce }

    static let fixture = Taken(nonce: "", phone: "6281277882210", account: TakenAccount(name: "Rani", avatar: "pose-waving", avatar_bg: "choc400", groups: 5))
}

/// A returning TestFlight user signed in with Apple (a new, empty account) and verified the number of their old one.
/// Continue moves this Apple ID to the old account and drops the new one (`otp/claim`); Cancel stays on the new account,
/// unverified, and the number stays with the old one.
struct TakenView: View {
    var taken: Taken
    var close: () -> Void
    @Environment(AppModel.self) private var app
    @State private var busy = false
    @State private var problem: Problem?

    private var name: String { taken.account.name.isEmpty ? "that account" : taken.account.name }
    private var groupsLine: String {
        switch taken.account.groups {
        case 0: "No group orders yet"
        case 1: "1 group order"
        case let n: "\(n) group orders"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("This number already has an account").obText(.title1, 32, tracking: -0.01)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("You just verified \(PhoneFormat.spaced(taken.phone)). It belongs to this Ataste account:")
                    .obText(.body, 15, Brand.ink2).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Brand.s2)
            .padding(.top, 62)
            VStack(spacing: 10) {
                Avatar(name: taken.account.name, index: 0, size: 84, art: taken.account.avatar, bg: taken.account.avatar_bg)
                HStack(spacing: 8) {
                    Text(taken.account.name).font(GFont.roundo(28)).foregroundStyle(Brand.cocoa).lineLimit(1)
                    VerifiedBadge(person: VerifiedPerson(name: taken.account.name, avatar: taken.account.avatar, bg: taken.account.avatar_bg))
                }
                Text(PhoneFormat.spaced(taken.phone)).font(GFont.manrope(14, 600)).foregroundStyle(Brand.ink2)
                Label { Text(groupsLine) } icon: { Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold)) }
                    .labelStyle(TightLabel())
                    .font(GFont.manrope(13, 600)).foregroundStyle(Brand.cocoa)
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(Capsule().fill(Brand.cream))
            }
            .padding(.vertical, 24).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
            .padding(.top, 32)
            Text("Continue as \(name) to keep its groups and history. From now on you sign in with this Apple ID, and the empty account you just made is removed.")
                .obText(.callout, 14, Brand.ink2).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Brand.s2).padding(.top, 24)
            Spacer(minLength: Brand.s4)
            VStack(spacing: 10) {
                Button("Continue as \(name)") { Task { await claim() } }
                    .buttonStyle(.pill(.primary))
                    .disabled(busy)
                Button("Cancel", action: close)
                    .obText(.headline, 16, weight: 600, Brand.ink2).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, Brand.s4)
        .padding(.bottom, Brand.s4)
        .screen()
        .overlay(alignment: .topLeading) {
            Button(action: close) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Brand.cocoa)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.leading, Brand.s4)
            .padding(.top, Brand.s1)
            .accessibilityLabel("Back")
        }
        .problemAlert($problem)
    }

    private func claim() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't continue as \(name)") {
            let reply: ClaimReply = try await supabase.functions.invoke("otp/claim", options: .init(method: .post, body: ["nonce": taken.nonce]))
            app.onboarding = false
            try await supabase.auth.verifyOTP(tokenHash: reply.token_hash, type: .magiclink)
            close()
        }
    }
}

nonisolated private struct ClaimReply: Decodable { var token_hash: String }

// MARK: Link your Apple ID (9-8)

/// Once, over Home, for an account that can't sign in with Apple yet (made with WhatsApp sign-in, before build 24).
/// Later doesn't ask again; Profile keeps a "Signed in with Apple · Link" row.
struct LinkAppleSheet: View {
    /// Linked, or Later: either way the prompt is done.
    var done: () -> Void
    @Environment(\.closeSheet) private var close
    @Environment(AppModel.self) private var app
    @State private var busy = false
    @State private var problem: Problem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Mascot(pose: "pose-phone", size: 64, fill: Brand.lime)
                Text("Link your Apple ID").font(GFont.roundo(24)).foregroundStyle(Brand.cocoa)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Ataste now signs in with Apple. Link it to this account so you can always get back to your groups and history, on this iPhone or a new one.")
                .font(GFont.manrope(15)).lineSpacing(3).foregroundStyle(Brand.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if app.profile?.verified == true {
                HStack(spacing: 8) {
                    Text("Your number stays on your profile").font(GFont.manrope(13, 600)).foregroundStyle(Brand.cocoa)
                    VerifiedBadge()
                }
            }
            AppleButton(mode: .link, busy: $busy) { reason in
                problem = Problem(title: "Couldn’t link your Apple ID", message: reason.isEmpty ? "Try again." : reason)
            } done: {
                done()
                close?()
            }
            .padding(.top, 4)
            Button("Later") {
                done()
                close?()
            }
            .obText(.headline, 16, weight: 600, Brand.ink2).frame(maxWidth: .infinity, minHeight: 44)
            .disabled(busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .problemAlert($problem)
    }
}
