import SwiftUI
import Supabase
import UserNotifications

@main
struct AtasArtisanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel.shared

    init() { Brand.registerFonts() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Brand.caramel)
                .onOpenURL { app.open($0) }
        }
    }
}

/// Session, profile, deep links and notification taps. Routes on the SDK's own session: there is no second
/// "signed in" flag to drift from it.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase { case launching, signedOut, signedIn }
    var phase: Phase = .launching
    var userID: UUID?
    var profile: Profile?
    /// A join code from a link, held until the user is signed in.
    var pendingJoin: String?
    /// A group a tapped notification points at.
    var openGroup: UUID?
    /// Bumped when anything the Home list shows may have changed.
    var homeVersion = 0

    func watchSession() async {
        for await (_, session) in supabase.auth.authStateChanges {
            userID = session?.user.id
            if session != nil {
                await loadProfile()
                phase = .signedIn
                Notices.shared.registerIfAllowed()
            } else {
                profile = nil
                phase = .signedOut
            }
        }
    }

    func loadProfile() async {
        guard let userID else { return }
        profile = try? await supabase.from("profiles").select().eq("id", value: userID).single().execute().value
    }

    func saveProfile(name: String? = nil, msgLang: String? = nil, mute: [String]? = nil) async throws {
        guard let userID else { return }
        struct Patch: Encodable { var name: String?; var msg_lang: String?; var notify_mute: [String]? }
        try await supabase.from("profiles").update(Patch(name: name, msg_lang: msgLang, notify_mute: mute))
            .eq("id", value: userID).execute()
        await loadProfile()
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    func deleteAccount() async throws {
        try await supabase.functions.invoke("account", options: .init(method: .delete))
        try? await supabase.auth.signOut(scope: .local)
    }

    func open(_ url: URL) {
        // ataste://join/ABC123 (from the join function's redirect)
        guard url.scheme == "ataste", url.host() == "join", let code = url.pathComponents.last, code.count == 6 else { return }
        pendingJoin = code.uppercased()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Notices.shared.start()
        return true
    }

    /// Hands the APNs token to Supabase (`devices`) so the `push` function can reach this phone.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            _ = try? await supabase.from("devices")
                .upsert(["token": token, "env": Notices.apnsEnv, "updated_at": Date().ISO8601Format()]).execute()
        }
    }
}

/// Notification permission, registration and taps. A tap opens the group it is about.
final class Notices: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notices()
    #if DEBUG
    nonisolated static let apnsEnv = "sandbox"
    #else
    nonisolated static let apnsEnv = "production"
    #endif

    func start() { UNUserNotificationCenter.current().delegate = self }

    func registerIfAllowed() {
        Task {
            if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in AppModel.shared.homeVersion += 1 }
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let group = (response.notification.request.content.userInfo["group"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if let group { AppModel.shared.openGroup = group }
            completionHandler()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .launching: LoaderView(line: "Proofing the dough…")
            case .signedOut: OnboardingFlow()
            case .signedIn:
                if let p = app.profile {
                    if p.name.isEmpty { NameStep() } else { MainTabs() }
                } else {
                    // Signed in but the profile didn't load (offline, or a session that couldn't be stored):
                    // don't ask for a name the server already has.
                    VStack(spacing: Brand.s4) {
                        LoaderView(line: "Checking your account…")
                        Button("Try again") { Task { await app.loadProfile() } }.buttonStyle(.pill(.secondary, .medium))
                    }
                    .padding(Brand.s5).background(Brand.cream.ignoresSafeArea())
                    .task { while app.profile == nil && !Task.isCancelled { try? await Task.sleep(for: .seconds(4)); await app.loadProfile() } }
                }
            }
        }
        .task { await app.watchSession() }
    }
}
