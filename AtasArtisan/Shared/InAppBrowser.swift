import SafariServices
import SwiftUI

/// Web pages open inside Ataste (in-app Safari), not in the Safari app. Installed at the root as the `openURL`
/// action, so every `openURL(...)`, `Link` and Markdown link in a `Text` goes through it. Links that only work
/// in another app (WhatsApp, the App Store, TestFlight, mail) still hand off to it, and our own invite links
/// open the join sheet directly.
enum InAppBrowser {
    private static let elsewhere: Set<String> = ["wa.me", "api.whatsapp.com", "apps.apple.com", "itunes.apple.com", "testflight.apple.com"]

    static let action = OpenURLAction { url in
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host()?.lowercased() else {
            return .systemAction
        }
        if host == Links.inviteHost && url.path().hasPrefix("/j/") {
            AppModel.shared.open(url)
            return .handled
        }
        if elsewhere.contains(host) { return .systemAction }
        present(url)
        return .handled
    }

    static func present(_ url: URL) {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Brand.caramel)
        vc.dismissButtonStyle = .close
        top.present(vc, animated: true)
    }
}
