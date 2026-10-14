import SwiftUI
import AuthenticationServices
import CryptoKit
import Supabase

// Sign in with Apple (board 9, App Review 4.8): the only way in. Apple's own button, black on cream, at our large
// pill's height and radius; its label is never changed (HIG), so loading dims it and the spinner sits outside it.
// The `apple` function checks Apple's identity token and hands back a magic-link token hash, as `otp` did for WhatsApp;
// the app finishes with auth.verifyOTP(tokenHash:type:.magiclink).

/// The nonce Apple signs into the identity token: random per request, sent to Apple as its SHA-256 (hex), and to our
/// server raw, so a token can only be used by the sign-in that asked for it.
enum AppleNonce {
    static func make() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// `apple` replies: a sign-in's token hash, or a link's confirmation.
nonisolated private struct AppleSignInReply: Decodable { var token_hash: String; var new_user: Bool?; var given_name: String? }
nonisolated private struct AppleLinkReply: Decodable { var linked: Bool }

/// Apple's button and what happens after Apple says yes. `.signIn` signs in or creates the account (9-1, and the 2-6b
/// invite prompt); `.link` attaches the Apple ID to the account already signed in (9-8, "Continue with Apple").
struct AppleButton: View {
    enum Mode { case signIn, link }
    var mode: Mode
    @Binding var busy: Bool
    /// Apple or the server said no; the text is the server's reason, or empty. Cancelling Apple's sheet says nothing.
    var failed: (String) -> Void
    var done: () -> Void = {}
    @State private var nonce = ""
    @Environment(AppModel.self) private var app

    var body: some View {
        SignInWithAppleButton(mode == .signIn ? .signIn : .continue) { request in
            nonce = AppleNonce.make()
            // Only the name (9-2 prefills it). Never the email: Ataste doesn't use one.
            request.requestedScopes = mode == .signIn ? [.fullName] : []
            request.nonce = AppleNonce.sha256(nonce)
        } onCompletion: { result in
            Task { await complete(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 60)
        .clipShape(Capsule())
        .disabled(busy)
        .opacity(busy ? 0.45 : 1)
        .animation(Motion.quick, value: busy)
    }

    private func complete(_ result: Result<ASAuthorization, Error>) async {
        let credential: ASAuthorizationAppleIDCredential
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code == .canceled { return }
            failed("")
            return
        case .success(let a):
            guard let c = a.credential as? ASAuthorizationAppleIDCredential else { failed(""); return }
            credential = c
        }
        guard let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { failed(""); return }
        var body = ["identity_token": token, "nonce": nonce]
        if let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) { body["authorization_code"] = code }
        let given = credential.fullName?.givenName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !given.isEmpty { body["given_name"] = given }

        busy = true
        defer { busy = false }
        do {
            switch mode {
            case .signIn:
                let reply: AppleSignInReply = try await supabase.functions.invoke("apple", options: .init(method: .post, body: body))
                if reply.new_user == true {
                    // New account: 9-2 name (prefilled from Apple), 9-3 verify intro, then 1-6, before Home.
                    NameStep.suggested = given.isEmpty ? reply.given_name ?? "" : given
                    app.onboarding = true
                }
                try await supabase.auth.verifyOTP(tokenHash: reply.token_hash, type: .magiclink)
            case .link:
                let _: AppleLinkReply = try await supabase.functions.invoke("apple", options: .init(method: .post, body: body))
                app.appleLinked = true
            }
            done()
        } catch where isCancellation(error) {
        } catch {
            if mode == .signIn { app.onboarding = false }
            failed(readable(error))
        }
    }
}
