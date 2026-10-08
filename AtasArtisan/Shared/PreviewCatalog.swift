import SwiftUI

/// Xcode canvas catalog for all screen-level views. Fixtures keep previews offline and do not affect app code.
@MainActor
enum PreviewData {
    static let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let guestID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let groupID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    static let profile = Profile(
        id: userID,
        phone: "6281234567890",
        name: "Putri",
        msg_lang: "en",
        notify_mute: [],
        avatar: "pose-waving",
        avatar_bg: nil
    )

    static let group = OrderGroup(
        id: groupID,
        code: "FRIDAY",
        host_id: userID,
        name: "Friday Treats",
        personal: false,
        area: "Canggu",
        address_label: "Villa Merah",
        address_detail: "Jl. Pantai Batu Bolong 12",
        maps_url: "",
        delivery_at: .now.addingTimeInterval(86_400),
        cutoff_at: .now.addingTimeInterval(43_200),
        pay_rule: "pay_later",
        msg_lang: "en",
        payout_account_id: nil,
        state: .open,
        ongkir: 20_000,
        discount: nil,
        created_at: .now,
        sent_at: nil,
        confirmed_at: nil,
        delivered_at: nil,
        closed_at: nil
    )

    static let product = Product(
        id: "brioche",
        collection_id: "pastries",
        name: "Brioche Bun",
        description: "A soft, buttery bun baked fresh every morning.",
        photo_url: "",
        base_price: 32_000,
        option_groups: [OptionGroup(name: "Size", choices: ["Regular", "Large"])],
        variants: [
            Variant(options: ["Size": "Regular"], price: 32_000, available: true),
            Variant(options: ["Size": "Large"], price: 42_000, available: true)
        ],
        available: true,
        sort: 0
    )

    static let item = Item(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        group_id: groupID,
        owner_id: userID,
        product_id: product.id,
        name: product.name,
        options: ["Size": "Regular"],
        unit_price: 32_000,
        qty: 2,
        note: "",
        flag_reason: nil,
        flagged_at: nil
    )

    /// Rani's cheesecake, shared in 12 pieces; Putri (me) has claimed 3.
    static let sharedItem = Item(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        group_id: groupID,
        owner_id: guestID,
        product_id: product.id,
        name: "Burnt Cheesecake 20 cm",
        options: [:],
        unit_price: 260_000,
        qty: 1,
        note: "",
        flag_reason: nil,
        flagged_at: nil,
        share_pieces: 12,
        share_min: 4
    )

    static let app: AppModel = {
        let app = AppModel.shared
        app.userID = userID
        app.profile = profile
        app.phase = .signedIn
        return app
    }()

    static let store: GroupStore = {
        let store = GroupStore(id: groupID)
        store.group = group
        store.members = [
            Member(group_id: groupID, user_id: userID, joined_at: .now, removed_at: nil, done_editing_at: nil, proof_at: nil, paid_at: nil, bill_total: nil),
            Member(group_id: groupID, user_id: guestID, joined_at: .now, removed_at: nil, done_editing_at: nil, proof_at: nil, paid_at: nil, bill_total: nil)
        ]
        store.people = [
            userID: profile,
            guestID: Profile(id: guestID, phone: "6281999999999", name: "Rani", msg_lang: "en", notify_mute: [], avatar: "pose-neutral", avatar_bg: nil)
        ]
        store.items = [item, sharedItem]
        store.claims = [ItemClaim(item_id: sharedItem.id, group_id: groupID, user_id: userID, pieces: 3, created_at: .now)]
        store.products = [product.id: product]
        store.bill = [
            BillRow(group_id: groupID, user_id: userID, items: 64_000, delivery_share: 10_000, bill_total: nil, proof_at: nil, paid_at: nil),
            BillRow(group_id: groupID, user_id: guestID, items: 0, delivery_share: 10_000, bill_total: 10_000, proof_at: .now, paid_at: nil)
        ]
        store.payout = PayoutAccount(user_id: userID, label: "BCA", account_name: "Putri", number: "1234567890")
        store.loaded = true
        return store
    }()
}

#Preview("Root") {
    RootView()
        .environment(PreviewData.app)
}

#Preview("Onboarding") {
    OnboardingFlow()
        .environment(PreviewData.app)
}

#Preview("Welcome") {
    NavigationStack { WelcomeStep(next: {}) }
}

#Preview("Verified") {
    NavigationStack {
        VerifiedStep(phone: "6281234567890", suggestedName: "Putri", token: "", notMe: {})
    }
}

#Preview("Name") {
    NameStep()
        .environment(PreviewData.app)
}

#Preview("Main tabs") {
    MainTabs()
        .environment(PreviewData.app)
}

#Preview("Create group") {
    NavigationStack {
        CreateGroupView(personal: false, created: { _ in })
    }
    .environment(PreviewData.app)
}

#Preview("Create personal order") {
    NavigationStack {
        CreateGroupView(personal: true, created: { _ in })
    }
    .environment(PreviewData.app)
}

#Preview("Payment method") {
    NavigationStack {
        PayoutEditor(account: PayoutAccount(label: "BCA", account_name: PreviewData.profile.name), saved: { _ in })
    }
}

#Preview("New address") {
    NavigationStack {
        NewAddressSheet(saved: { _ in })
    }
}

#Preview("Group created") {
    GroupBornState(group: PreviewData.group)
        .padding()
        .screen()
}

#Preview("Share group") {
    NavigationStack {
        ShareCard(group: PreviewData.group)
    }
}

#Preview("Paste link") {
    PasteLinkSheet(choose: { _ in })
}

#Preview("Join login prompt") {
    JoinLoginPrompt(code: PreviewData.group.code, action: {})
}

#Preview("Home") {
    PreviewHome()
        .environment(PreviewData.app)
}

#Preview("History") {
    NavigationStack { HistoryView() }
        .environment(PreviewData.app)
}

#Preview("History detail") {
    NavigationStack { HistoryDetailView(id: PreviewData.groupID) }
        .environment(PreviewData.app)
}

#Preview("Group") {
    NavigationStack { PreviewGroup() }
        .environment(PreviewData.app)
}

#Preview("Edit delivery") {
    NavigationStack { EditDeliverySheet(store: PreviewData.store) }
}

#Preview("Send to Atas") {
    NavigationStack {
        SendToAtasView(store: PreviewData.store)
            .environment(PreviewData.app)
    }
}

#Preview("Confirm Atas") {
    NavigationStack { ConfirmAtasView(store: PreviewData.store) }
}

#Preview("Menu") {
    NavigationStack { MenuView(store: PreviewData.store) }
}

#Preview("Product") {
    NavigationStack {
        ProductView(store: PreviewData.store, product: PreviewData.product)
    }
}

#Preview("My order") {
    MyOrderView(store: PreviewData.store)
}

#Preview("Claim pieces") {
    ClaimSheet(store: PreviewData.store, itemID: PreviewData.sharedItem.id, withdrawn: { _, _ in })
        .padding()
        .screen()
}

#Preview("Share settings") {
    ShareSettingsSheet(store: PreviewData.store, itemID: PreviewData.item.id, request: nil, stop: { _ in })
        .padding()
        .screen()
}

#Preview("Ask to share") {
    AskShareSheet(store: PreviewData.store, owner: PreviewData.guestID, asked: { _ in })
        .padding()
        .screen()
}

#Preview("Your bill") {
    NavigationStack { BillView(store: PreviewData.store) }
}

#Preview("Payment board") {
    NavigationStack { PaymentBoardView(store: PreviewData.store) }
}

#Preview("Pickup board") {
    NavigationStack { PickupBoardView(store: PreviewData.store) }
}

#Preview("Receipt") {
    NavigationStack {
        ReceiptView(store: PreviewData.store, user: PreviewData.guestID)
    }
}

#Preview("Delivery") {
    NavigationStack { DeliveryView(store: PreviewData.store) }
}

#Preview("Profile") {
    NavigationStack { ProfileView() }
        .environment(PreviewData.app)
}

#Preview("Notifications") {
    NavigationStack { NotificationSettingsView() }
}

#Preview("Payout editor") {
    NavigationStack {
        PayoutEditor(account: PreviewData.store.payout!, sheet: false, saved: { _ in })
    }
}

#Preview("Saved places") {
    NavigationStack { SavedPlacesView() }
}

#Preview("Address editor") {
    NavigationStack {
        AddressEditor(
            address: Address(user_id: PreviewData.userID, label: "Villa Merah", area: "Canggu", detail: "Jl. Pantai Batu Bolong 12", maps_url: ""),
            sheet: false,
            saved: { _ in }
        )
    }
}

#Preview("Avatar picker") {
    NavigationStack {
        AvatarPicker()
            .environment(PreviewData.app)
    }
}

private struct PreviewHome: View {
    @State private var path = NavigationPath()
    @State private var creating: Bool?
    @Namespace private var cards

    var body: some View {
        NavigationStack(path: $path) {
            // The preview has no card-open overlay (MainTabs owns it), so a card pushes its group directly.
            HomeView(path: $path, creating: $creating, cards: cards, openCard: { id, _ in path.append(id) }, showTab: { _ in })
        }
    }
}

private struct PreviewGroup: View {
    @State private var path = NavigationPath()

    var body: some View {
        GroupView(id: PreviewData.groupID, path: $path)
    }
}
