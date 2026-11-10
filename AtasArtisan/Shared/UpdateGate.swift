import SwiftUI
import StoreKit
import Supabase

extension AppModel {
    /// Blocks the app when its build is below `app_release.min_build` for the channel it was installed from.
    /// TestFlight installs report the sandbox environment, App Store installs production; App Review installs also
    /// report sandbox, so `testflight.py` keeps that minimum at or below the build in review. Xcode builds are never
    /// gated. The channel comes from the app transaction, unverified if need be (this is a nudge, not a security
    /// check), else from the receipt's file name: on some iOS 26 TestFlight installs the app transaction fails and
    /// the gate never ran. Offline leaves the app usable.
    func checkUpdate() async {
        guard let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""),
              let channel = await Self.installChannel() else { return }
        let url = channel == "testflight" ? URL(string: Links.getTheApp)! : Links.appStore
        struct Row: Decodable { let min_build: Int }
        guard let row: Row = try? await supabase.from("app_release").select("min_build").eq("channel", value: channel)
            .single().execute().value else { return }
        updateURL = build < row.min_build ? url : nil
    }

    /// "testflight", "appstore", or nil for Xcode and unknown installs.
    private static func installChannel() async -> String? {
        if let t = try? await AppTransaction.shared {
            switch t.unsafePayloadValue.environment {
            case .sandbox: return "testflight"
            case .production: return "appstore"
            case .xcode: return nil
            default: break
            }
        }
        // Deprecated since iOS 18 but still set: "sandboxReceipt" on TestFlight, "receipt" from the App Store.
        switch Bundle.main.appStoreReceiptURL?.lastPathComponent {
        case "sandboxReceipt": return "testflight"
        case "receipt": return "appstore"
        default: return nil
        }
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
