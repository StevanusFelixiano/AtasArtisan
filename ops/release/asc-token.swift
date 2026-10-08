// Prints a 20-minute App Store Connect API token (ES256 JWT) from the team key in the Keychain
// (ataste.asc-key holds the .p8 as one line of base64, ataste.asc-key-id its id, ataste.asc-issuer the issuer).
import CryptoKit
import Foundation

func keychain(_ service: String) -> String {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", service, "-a", "ataste", "-w"]
    p.standardOutput = out
    try! p.run(); p.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let pem = String(decoding: Data(base64Encoded: keychain("ataste.asc-key"))!, as: UTF8.self)
let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
let now = Int(Date().timeIntervalSince1970)
let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keychain("ataste.asc-key-id"), "typ": "JWT"])
let claims = try JSONSerialization.data(withJSONObject: [
    "iss": keychain("ataste.asc-issuer"), "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"])
let input = b64url(header) + "." + b64url(claims)
print(input + "." + b64url(try key.signature(for: Data(input.utf8)).rawRepresentation))
