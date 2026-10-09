import SwiftUI
import Supabase
import UserNotifications

@main
struct AtasArtisanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel.shared

    init() {
        Brand.registerFonts()
        // The default disk cache (about 10 MB, nothing over 5% of it) can't hold the menu's photos, so every launch
        // refetched them from the slow iSeller CDN, which marks them cacheable for a year.
        URLCache.shared = URLCache(memoryCapacity: 16 << 20, diskCapacity: 200 << 20)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Brand.caramel)
                .environment(\.openURL, InAppBrowser.action)
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
    var pendingJoin: String? { didSet { if pendingJoin == nil { joinFromList = false } } }
    /// The join came from Home's public list, not an invite link: the sheet doesn't say "invited you".
    var joinFromList = false
    /// A group a tapped notification points at.
    var openGroup: UUID?
    /// Bumped when anything the Home list shows may have changed.
    var homeVersion = 0
    /// The group whose screen is on show: an event about it plays on that screen, not as a banner.
    var screenGroup: UUID?
    /// The latest order event that arrived while the app was open, for the in-app banner.
    var note: InAppNote?
    /// Where to get a newer build when this one is below the server's minimum (`app_release`); nil = up to date.
    var updateURL: URL?

    /// A push in the foreground: the in-app banner shows it, unless it is about the group on screen.
    func arrived(_ n: InAppNote) {
        homeVersion += 1
        if let g = n.group, g == screenGroup { return }
        note = n
    }

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
        // https://<invite host>/j/ABC123 (universal link) or ataste://join/ABC123 (the web page's Open button)
        let invite = (url.scheme == "https" && url.host() == Links.inviteHost && url.pathComponents.dropLast().last == "j")
            || (url.scheme == "ataste" && url.host() == "join")
        guard invite, let code = url.pathComponents.last, code.count == 6 else { return }
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

    /// In the foreground the Ataste banner replaces the system one (Motion board 08); the notification still goes to
    /// the list.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let c = notification.request.content
        let note = InAppNote(title: c.title, body: c.body, kind: c.userInfo["kind"] as? String ?? "",
                             group: (c.userInfo["group"] as? String).flatMap(UUID.init(uuidString:)))
        Task { @MainActor in
            AppModel.shared.arrived(note)
            completionHandler([.list])
        }
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
    /// The splash stays up 0.25 s past launching for its ready turn, then crossfades to the next screen.
    @State private var splash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if !splash { screen.transition(.opacity) }
            if let url = app.updateURL, !splash { UpdateView(url: url).transition(.opacity) }
            if splash { SplashView(ready: app.phase != .launching).transition(.opacity) }
        }
        .task(id: app.phase != .launching) {
            guard app.phase != .launching, splash else { return }
            if !reduceMotion { try? await Task.sleep(for: .seconds(SplashMotion.welcomeDelay)) }
            withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.fade) { splash = false }
        }
        .task { await app.watchSession() }
        .task(id: scenePhase) { if scenePhase == .active { await app.checkUpdate() } }
        .background(KeyboardDismiss())
        .background(BannerWindowInstaller())
    }

    @ViewBuilder private var screen: some View {
        Group {
            switch app.phase {
            case .launching: Color.clear
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
    }
}

/// A tap anywhere outside a text field closes the keyboard, on every screen, form and sheet: one tap recognizer
/// on the window that never cancels the tap, so buttons and rows still get it.
private struct KeyboardDismiss: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let p = Probe(); p.isUserInteractionEnabled = false; return p }
    func updateUIView(_ view: UIView, context: Context) {}

    final class Probe: UIView, UIGestureRecognizerDelegate {
        override func didMoveToWindow() {
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === self }) else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }
        @objc private func tapped() { window?.endEditing(true) }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let v = view { if v is UITextField || v is UITextView { return false }; view = v.superview }
            return true
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
