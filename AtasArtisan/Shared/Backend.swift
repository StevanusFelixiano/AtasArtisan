import Foundation
import Supabase

// ponytail: the publishable key ships inside the binary by design; RLS is the boundary, not this string.
// Project "Ataste" (org Ataste), ref scgyssmzfurqjkgfomtq, ap-northeast-1. The secret key never appears in this repo.
let supabaseURL = URL(string: "https://scgyssmzfurqjkgfomtq.supabase.co")!
let supabase = SupabaseClient(
    supabaseURL: supabaseURL,
    supabaseKey: "sb_publishable_ihHWwF0eSLK1SSkR85lS_A_25gle_43",
    options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
)

enum Links {
    /// Our WhatsApp number for reverse-OTP verification (0819-3610-0819). System messages only.
    static let verifyNumber = "6281936100819"
    /// Atas Artisan's ordering WhatsApp (0821-3145-473). The host sends from their own WhatsApp.
    static let atasNumber = "628213145473"
    /// Legal pages: HTML built from `legal/*.md` (`legal/build.py`), served by the VPS next to the invite page.
    static let privacy = URL(string: "https://ataste.51-79-240-114.sslip.io/legal/privacy")!
    static let terms = URL(string: "https://ataste.51-79-240-114.sslip.io/legal/terms")!
    static let support = URL(string: "https://ataste.51-79-240-114.sslip.io/legal/support")!
    static let supportEmail = "bayu.johar25@gmail.com"
    /// Public TestFlight link (external group "Public"); testers can join once a build passes beta review.
    static let getTheApp = "https://testflight.apple.com/join/U65TErQM"

    /// Invite links: the web page on the VPS (repo `web/`, design 2-7) for people without the app; with the app
    /// installed the same link opens Ataste directly (universal link, `applinks:` in the entitlements).
    static let inviteHost = "ataste.51-79-240-114.sslip.io"
    static func join(_ code: String) -> URL { URL(string: "https://\(inviteHost)/j/\(code)")! }

    static func whatsApp(_ phone: String, text: String = "") -> URL {
        var c = URLComponents(string: "https://wa.me/\(phone)")!
        if !text.isEmpty { c.queryItems = [URLQueryItem(name: "text", value: text)] }
        return c.url!
    }
}

/// A column being written to null. Synthesized `Encodable` skips a nil Optional, and PostgREST reads a
/// missing key as "leave it alone", so a write that meant "clear this" would change nothing.
struct Nullable<Value: Encodable>: Encodable {
    let value: Value?
    init(_ value: Value?) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}

/// Server errors come back as Postgres exception text ("only the host can do this"). Show that sentence,
/// not the SDK's wrapper.
/// SwiftUI cancels a view's task when the view goes away or a newer load replaces it. The result is no longer
/// wanted, so a cancelled request is never shown as a failure.
func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}

func readable(_ error: Error) -> String {
    if let e = error as? PostgrestError { return e.message }
    if let e = error as? FunctionsError, case let .httpError(_, data) = e,
       let body = try? JSONDecoder().decode([String: String].self, from: data), let m = body["error"] { return m }
    // The network's own errors read "The operation couldn't be completed. (NSURLErrorDomain error -1009.)".
    if let e = error as? URLError {
        switch e.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return "You’re offline. Check your connection and try again."
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .badServerResponse:
            return "The server didn’t answer. Try again in a moment."
        default:
            return "Something went wrong on the way to the server. Try again."
        }
    }
    return error.localizedDescription
}
