import SwiftUI
import StoreKit
import Supabase

extension AppModel {
    /// Blocks the app when its build is below `app_release.min_build` for the channel it was installed from.
    /// TestFlight installs report the sandbox environment, App Store installs production; Xcode builds are never
    /// gated. Any failure (offline, no receipt) leaves the app usable.
    func checkUpdate() async {
        guard case .verified(let t)? = try? await AppTransaction.shared,
              let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") else { return }
        let channel: String, url: URL
        switch t.environment {
        case .sandbox: (channel, url) = ("testflight", URL(string: Links.getTheApp)!)
        case .production: (channel, url) = ("appstore", Links.appStore)
        default: return
        }
        struct Row: Decodable { let min_build: Int }
        guard let row: Row = try? await supabase.from("app_release").select("min_build").eq("channel", value: channel)
            .single().execute().value else { return }
        updateURL = build < row.min_build ? url : nil
    }
}

/// Covers every screen until the user installs the newer build.
struct UpdateView: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        EmptyStateView(pose: "pose-waving", fill: Brand.choc100, title: "Update Ataste",
                       message: "A newer version is ready. Update to keep ordering with your group.",
                       actionTitle: "Update", actionIcon: "arrow.down.circle") { openURL(url) }
            .padding(Brand.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.cream.ignoresSafeArea())
    }
}
