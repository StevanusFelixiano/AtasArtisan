import SwiftUI
import Supabase

/// Home, History and Profile under the Ataste tab bar (design board "Ataste Tab Bar", 1a).
/// All three stacks stay alive in a ZStack, as TabView kept them; the inactive ones are hidden.
struct MainTabs: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0
    @State private var homePath = NavigationPath()
    @State private var historyPath = NavigationPath()
    /// The create sheet on Home: true = group order, false = for myself.
    @State private var creating: Bool?
    /// "Start my own order" on a locked invite: opens the create sheet once the invite has closed.
    @State private var createAfterJoin = false
    /// Tabs whose root screen has something pushed over it.
    @State private var covered: Set<Int> = []
    @State private var retaps = [0, 0, 0]
    @State private var keyboard = false
    @State private var safeBottom: CGFloat = 0
    /// A group card opening into its group (Motion board 09), and the groups opened that way: their screens zoom
    /// back into the card.
    @State private var opening: CardOpening?
    @State private var zoomed: Set<UUID> = []
    @State private var homeStill = ScreenStill()
    @Namespace private var cards

    /// Home and History push through their paths, which hides the bar as the push starts; a root's onDisappear
    /// catches the other pushes (Profile's links), at the end of the push.
    private var barHidden: AtasteTabBar.Hidden? {
        if keyboard { return .keyboard }
        let pushed = covered.contains(tab) || (tab == 0 && (!homePath.isEmpty || opening != nil)) || (tab == 1 && !historyPath.isEmpty)
        return pushed ? .pushed : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            page(0) {
                NavigationStack(path: $homePath) {
                    root(0, HomeView(path: $homePath, creating: $creating, cards: cards, openCard: openCard) { tab = $0 })
                        .background(ScreenStillProbe(still: homeStill))
                        .navigationDestination(for: UUID.self) { id in
                            GroupView(id: id, path: $homePath).modifier(ZoomBack(id: id, active: zoomed.contains(id), space: cards))
                        }
                }
            }
            if let o = opening {
                CardOpenOverlay(opening: o) { opening = nil }
            }
            page(1) { NavigationStack(path: $historyPath) { root(1, HistoryView()) } }
            page(2) { NavigationStack { root(2, ProfileView()) } }
            AtasteTabBar(selection: $tab, hidden: barHidden, safeBottom: keyboard ? 0 : safeBottom) { retaps[$0] += 1 }
        }
        .background {
            Color.clear.ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeBottom = $0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
        .fullScreenCover(item: Binding(get: { app.pendingJoin.map(JoinCode.init) }, set: { app.pendingJoin = $0?.code }),
                         onDismiss: {
                             if createAfterJoin { createAfterJoin = false; tab = 0; creating = true }
                         }) { join in
            JoinSheet(code: join.code) { id in
                tab = 0
                homePath.append(id)
            } startOwn: {
                createAfterJoin = true
            }
        }
        .task {
            if let t = DebugScreens.value("ATASTE_TAB"), let n = Int(t) { tab = n }
            if let name = DebugScreens.value("ATASTE_OPEN") {
                let rows: [OrderGroup] = (try? await supabase.from("groups").select().ilike("name", pattern: "%\(name)%").execute().value) ?? []
                if let g = rows.first { homePath.append(g.id) }
            }
            if let code = DebugScreens.value("ATASTE_JOIN") { app.pendingJoin = code.uppercased() }
        }
        .onChange(of: app.openGroup) { _, id in
            guard let id else { return }
            tab = 0
            homePath = NavigationPath([id])
            app.openGroup = nil
        }
    }
}

extension MainTabs {
    fileprivate func page(_ i: Int, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .environment(\.pageShown, tab == i)
            .opacity(tab == i ? 1 : 0)
            .allowsHitTesting(tab == i)
            .accessibilityHidden(tab != i)
            .animation(TabMotion.screenSwap, value: tab)
    }

    /// A tab's root screen: room for the bar (its top edge plus a 16pt gap; none while typing), the re-tap count,
    /// and whether something is pushed over it.
    fileprivate func root(_ i: Int, _ screen: some View) -> some View {
        screen
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: keyboard ? 0 : max(0, AtasteTabBar.top + 16 - safeBottom))
            }
            .environment(\.tabRetap, retaps[i])
            .onAppear { covered.remove(i) }
            .onDisappear { covered.insert(i) }
    }
}

extension MainTabs {
    /// A group card was tapped: put a still of Home over the screen, push the group under it without animation, and
    /// let the card's frame grow into the group screen.
    fileprivate func openCard(_ id: UUID, _ frame: CGRect) {
        guard opening == nil else { return }
        guard let home = homeStill.capture(), frame.width > 0 else { return homePath.append(id) }
        zoomed.insert(id)
        opening = CardOpening(id: id, frame: frame, fill: Brand.card, home: home, card: ScreenStill.crop(home, to: frame))
        Task { @MainActor in
            await Task.yield()
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { homePath.append(id) }
        }
    }
}

struct JoinCode: Identifiable { var code: String; var id: String { code } }

// MARK: Home (2-1, 2-2)

struct HomeView: View {
    @Binding var path: NavigationPath
    @Binding var creating: Bool?
    /// The group cards' zoom sources, and the opening a card plays when tapped (its frame on screen).
    var cards: Namespace.ID
    var openCard: (UUID, CGRect) -> Void
    var showTab: (Int) -> Void
    @Environment(AppModel.self) private var app
    @State private var groups: [OrderGroup] = []
    @State private var bills: [UUID: BillRow] = [:]
    /// Every member's items added up, per group: the Rp 200.000 bar on an open group's card.
    @State private var subtotals: [UUID: Int] = [:]
    @State private var hosts: [UUID: Profile] = [:]
    /// "Brioche Toast · Classic Sourdough" for a personal order's card.
    @State private var summaries: [UUID: String] = [:]
    @State private var loaded = false
    @State private var pasting = false
    @State private var pastedCode: String?
    @State private var problem: Problem?
    @State private var cardFrames: [UUID: CGRect] = [:]
    #if DEBUG
    @State private var debugSheet: String?
    #endif

    private static let emptyID = "home"
    private var active: [OrderGroup] { groups.filter { $0.state.isLive } }
    private var pastCount: Int { groups.filter { [.delivered, .closed, .cancelled].contains($0.state) }.count }
    private var empty: Bool { loaded && active.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if empty { emptyState } else { list }
            }
            // Room under the last card. The empty state needs none: its buttons sit in their own bottom inset.
            .padding(.bottom, empty ? 0 : Brand.s5)
        }
        .pullToRefresh { await load() }
        .scrollsToTopOnRetap()
        .scrollBounceBehavior(.basedOnSize)
        .screen()
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { if empty { emptyActions } }
        .task(id: app.homeVersion) { await load() }
        .task {
            switch HomeDebug.screen {
            case "paste": pasting = true
            case "create", "nopay", "late", "payment", "address": creating = true
            case "personal": creating = false
            #if DEBUG
            case "born", "login": try? await Task.sleep(for: .seconds(2)); debugSheet = HomeDebug.screen
            #endif
            default: break
            }
        }
        #if DEBUG
        .sheet(item: Binding(get: { debugSheet.map(JoinCode.init) }, set: { debugSheet = $0?.code })) { s in
            if s.code == "born", let g = active.first {
                ScrollView { GroupBornState(group: g).padding(.top, 40) }.screen()
            } else {
                JoinLoginPrompt(code: DebugScreens.value("ATASTE_JOIN_CODE") ?? "") {}
            }
        }
        #endif
        .sheet(item: Binding(get: { creating.map(CreateMode.init) }, set: { creating = $0?.group })) { mode in
            NavigationStack {
                CreateGroupView(personal: !mode.group) { id in
                    creating = nil
                    path.append(id)
                }
            }
        }
        .sheet(isPresented: $pasting, onDismiss: {
            if let code = pastedCode { pastedCode = nil; app.pendingJoin = code }
        }) {
            PasteLinkSheet { pastedCode = $0 }
        }
        .problemAlert($problem)
    }

    // MARK: Header: logo, avatar, greeting, marquee

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HomeLogo()
                Spacer()
                Button { showTab(2) } label: {
                    Avatar(name: app.profile?.name ?? "", index: 2, size: 40, art: app.profile?.avatar, bg: app.profile?.avatar_bg)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 2) {
                if !empty {
                    Text(Wita.string(Date(), "EEEE, d MMMM")).styled(.body, 15, Brand.ink2)
                }
                Text("Hi, \(app.profile?.name ?? "")").styled(.display, 40).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, empty ? 20 : 28)
            Marquee()
        }
    }

    // MARK: Active orders (2-1)

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Brand.s3) {
                BigChoice(kind: .personal) { creating = false }
                BigChoice(kind: .group) { creating = true }
            }
            .padding(.top, 27)
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: Brand.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Active orders").brand(.label)
                    Spacer()
                    if loaded { Text("\(active.count)").styled(.callout, 13, weight: 600, Brand.caramel) }
                }
                .padding(.horizontal, Brand.s1)
                ForEach(active) { g in
                    Button { openCard(g.id, cardFrames[g.id] ?? .zero) } label: {
                        OrderCard(group: g, bill: bills[g.id], host: hosts[g.host_id], groupSubtotal: subtotals[g.id], summary: summaries[g.id])
                    }
                    .buttonStyle(DoughStyle(squash: Motion.pressCard, haptic: nil))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardFrames[g.id] = $0 }
                    .matchedTransitionSource(id: g.id, in: cards)
                }
                VStack(spacing: 0) {
                    RowLink(icon: "link", fill: Brand.choc100, title: "Paste a join link", subtitle: "If a link opened in Safari instead") { pasting = true }
                    Rectangle().fill(Brand.liquorice100).frame(height: 1)
                    RowLink(icon: "clock.arrow.circlepath", fill: Brand.liquorice100, title: "History",
                            subtitle: pastCount == 0 ? "No past orders yet" : "\(pastCount) past order\(pastCount == 1 ? "" : "s")") { showTab(1) }
                }
                .padding(.vertical, Brand.s1)
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.card))
            }
        }
        .padding(.horizontal, Brand.s4)
    }

    // MARK: Empty (2-2)

    /// 2-2's first view this session plays the empty-state entrance (Motion board 22); later views are still.
    private var emptyState: some View {
        VStack(spacing: 14) {
            CaptionedPainting(art: "paint-supper", title: "The Last Supper Club", width: 300, height: 167, tilt: -1.5, intro: Self.emptyID)
            Text("No orders baking…yet!").styled(.title1, 28).multilineTextAlignment(.center)
                .emptyIntro(.headline, id: Self.emptyID)
            Text("Start a group so everyone’s croissants count toward the Rp 200.000 ongkir discount.")
                .styled(.body, 15, Brand.ink2).lineSpacing(4).multilineTextAlignment(.center).frame(maxWidth: 300)
                .emptyIntro(.body, id: Self.emptyID)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, Brand.s5)
    }

    private var emptyActions: some View {
        VStack(spacing: 10) {
            Button("Start a group order") { creating = true }.buttonStyle(.pill(.primary))
                .emptyIntro(.primary, id: Self.emptyID)
            HStack(spacing: 10) {
                // Two pills share the row: the pill's 32pt side padding is trimmed to the design's 12.
                Button { creating = false } label: { Text("Order for myself").padding(.horizontal, -20).frame(maxWidth: .infinity) }
                Button { pasting = true } label: { Label("Paste link", systemImage: "link").padding(.horizontal, -20).frame(maxWidth: .infinity) }
            }
            .buttonStyle(.pill(.secondary, .medium))
            .emptyIntro(.secondary, id: Self.emptyID)
        }
        .padding(.horizontal, Brand.s4)
        .padding(.bottom, Brand.s4)
    }

    /// Loads the active orders; says whether it worked (a failure also raises the problem alert).
    @discardableResult
    private func load() async -> Bool {
        do {
            var all: [OrderGroup] = try await supabase.from("groups").select().order("delivery_at").execute().value
            #if DEBUG
            if HomeDebug.screen == "empty" { all = [] }
            #endif
            groups = all
            let live = all.filter { $0.state.isLive }
            if !live.isEmpty {
                let ids = live.map(\.id)
                let rows: [BillRow] = try await supabase.from("group_bill_v").select().in("group_id", values: ids).execute().value
                bills = Dictionary(rows.filter { $0.user_id == app.userID }.map { ($0.group_id, $0) }, uniquingKeysWith: { a, _ in a })
                subtotals = Dictionary(grouping: rows, by: \.group_id).mapValues { $0.reduce(0) { $0 + $1.items } }
                let hostIDs = Array(Set(live.filter { !$0.personal }.map(\.host_id)))
                if !hostIDs.isEmpty {
                    let people: [Profile] = try await supabase.from("profiles").select().in("id", values: hostIDs).execute().value
                    hosts = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                }
                let personal = live.filter(\.personal).map(\.id)
                if !personal.isEmpty {
                    struct Line: Decodable { var group_id: UUID; var name: String; var options: [String: String] }
                    let lines: [Line] = try await supabase.from("items").select("group_id,name,options")
                        .in("group_id", values: personal).order("created_at").execute().value
                    summaries = Dictionary(grouping: lines, by: \.group_id).mapValues { ls in
                        ls.map { l in ([l.name] + l.options.keys.sorted().compactMap { l.options[$0] }).joined(separator: " · ") }
                            .joined(separator: " · ")
                    }
                }
            }
        } catch where isCancellation(error) {
            return true
        } catch {
            problem = Problem(title: "Couldn't load your orders", message: readable(error))
            loaded = true
            return false
        }
        loaded = true
        return true
    }
}

struct CreateMode: Identifiable { var group: Bool; var id: Bool { group } }

/// The small "ataste" wordmark pill in the Home header: Roundo 700 19 on caramel, a 2pt cocoa drop under it.
struct HomeLogo: View {
    var body: some View {
        Text("ataste")
            .font(Brand.font(.display, size: 19))
            .foregroundStyle(Brand.cream)
            .padding(.horizontal, 15).padding(.top, 5).padding(.bottom, 8)
            .background(Capsule().fill(Brand.caramel))
            .background(Capsule().fill(Brand.cocoa).offset(y: 2))
            .compositingGroup()
            .accessibilityLabel("Ataste")
            .accessibilityAddTraits(.isHeader)
    }
}

/// The two big tiles on Home: "Order for myself" (pink, giraffe with a cake box) and "Start a group order"
/// (caramel, three friends' avatars).
struct BigChoice: View {
    enum Kind { case personal, group }
    var kind: Kind
    var action: () -> Void

    var body: some View {
        let group = kind == .group
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                if group {
                    HStack(spacing: -10) {
                        ForEach(Array(zip(["R", "D", "K"], ["pose-waving", "paint-vangogh", "paint-sonofbun"]).enumerated()), id: \.offset) { i, a in
                            Avatar(name: a.0, index: i, size: 40, art: a.1, ring: Brand.caramel)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: Brand.s1) {
                    Text(group ? "Start a group order" : "Order for myself")
                        .styled(.title2, 22, group ? Brand.cream : Brand.cocoa).lineSpacing(-2)
                    Text(group ? "Reach Rp 200.000 together, save on ongkir." : "Just you. No invite, no split.")
                        .brand(.footnote, group ? Brand.choc100 : Brand.cocoa)
                }
                .multilineTextAlignment(.leading)
            }
            .padding(Brand.s4)
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200, alignment: .leading)
            .background(alignment: .topTrailing) {
                if !group {
                    Image("pose-cakebox").resizable().scaledToFill()
                        .frame(width: 120, height: 120).clipShape(Circle())
                        .offset(x: 18, y: -14)
                }
            }
            .background(group ? Brand.caramel : Brand.pink100)
            .clipShape(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous))
        }
        // The card squashes on touch down (Motion board 09); it opens the create sheet.
        .buttonStyle(DoughStyle(squash: Motion.pressCard, haptic: nil))
    }
}

/// An order on Home (and History): name, host and delivery, state; on an open group the Rp 200.000 bar;
/// then my subtotal or bill, the pay state and the time left before it locks.
struct OrderCard: View {
    var group: OrderGroup
    var bill: BillRow?
    var host: Profile? = nil
    var groupSubtotal: Int? = nil
    var summary: String? = nil
    @Environment(AppModel.self) private var app

    private var owes: Bool { group.state == .confirmed || group.state == .delivered }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: Brand.s3) {
                VStack(alignment: .leading, spacing: Brand.s1) {
                    Text(group.name).styled(.title2, 20).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if !group.personal, let host {
                            Avatar(name: host.name, index: 0, size: 18, art: host.avatar, bg: host.avatar_bg)
                        }
                        Text(subtitle).styled(.body, 13, Brand.ink2)
                    }
                }
                Spacer(minLength: 0)
                StateTag(group: group)
            }
            if !group.personal, group.state == .open, let total = groupSubtotal { progress(total) }
            VStack(spacing: Brand.s3) {
                Line().stroke(Brand.liquorice400, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
                HStack(alignment: .center, spacing: Brand.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.personal ? "Total" : owes ? "You owe" : "My subtotal").styled(.label, 11, Brand.ink3)
                        Text(Rupiah.format(bill?.total ?? 0)).styled(.title2, 20)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
    }

    private var subtitle: String {
        if group.personal { return "Just me · \(Wita.string(group.delivery_at, "EEE d MMM, HH:mm"))" }
        let who = host.map { $0.name.isEmpty ? "Host" : $0.name }
        return [who, "\(Wita.string(group.delivery_at, "EEE d MMM, HH:mm")) WITA"].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var trailing: some View {
        if group.personal {
            VStack(alignment: .trailing, spacing: 0) {
                if let summary, !summary.isEmpty { Text(summary).lineLimit(3) }
                Text("Ongkir paid to Atas directly")
            }
            .styled(.footnote, 12, Brand.ink2)
            .multilineTextAlignment(.trailing)
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                if let bill, bill.total > 0, group.host_id != app.userID { PayTag(state: PayState(bill), size: .small) }
                if group.state == .open, let cutoff = group.cutoff_at {
                    TimelineView(.everyMinute) { t in
                        Label { Text(Countdown.locks(cutoff, now: t.date)) } icon: { Image(systemName: "clock").font(.system(size: 12, weight: .semibold)) }
                            .labelStyle(TightLabel())
                            .styled(.footnote, 12, weight: 600, Brand.caramel)
                    }
                }
            }
        }
    }

    private func progress(_ total: Int) -> some View {
        let goal = DiscountBar.goal, done = total >= goal
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.liquorice100)
                    Capsule().fill(done ? Brand.limeDeep : Brand.choc400).frame(width: g.size.width * min(1, CGFloat(total) / CGFloat(goal)))
                }
            }
            .frame(height: 10)
            Group {
                if done {
                    Text("The ongkir discount is unlocked")
                } else {
                    Text("\(Text("\(Rupiah.format(goal - total)) more").font(Brand.font(.footnote, weight: 700)).foregroundStyle(Brand.caramel)) to unlock the ongkir discount")
                }
            }
            .styled(.footnote, 12, Brand.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

/// Icon and title 4pt apart (the board's inline "clock + Locks in…").
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Brand.s1) { configuration.icon; configuration.title }
    }
}

/// A row in the Home links card: 36pt tinted circle, title and subtitle, chevron.
struct RowLink: View {
    var icon: String
    var fill: Color = Brand.choc100
    var title: String
    var subtitle: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Brand.s3) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.cocoa)
                    .frame(width: 36, height: 36).background(Circle().fill(fill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).styled(.headline, 15)
                    if let subtitle { Text(subtitle).brand(.footnote, Brand.ink3) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.ink4)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
