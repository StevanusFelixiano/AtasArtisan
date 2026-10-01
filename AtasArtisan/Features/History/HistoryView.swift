import SwiftUI
import Supabase

/// 4.15 Past orders. Opening one shows the group screen read-only (its state is closed, cancelled or delivered).
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var groups: [OrderGroup] = []
    @State private var bills: [UUID: BillRow] = [:]
    @State private var loaded = false
    @State private var path = NavigationPath()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s3) {
                if loaded && groups.isEmpty {
                    VStack(spacing: Brand.s4) {
                        Image("paint-creation").resizable().scaledToFit()
                            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Brand.caramel))
                            .accessibilityLabel("The Creation of Ataste, a giraffe painting")
                        Text("No past orders yet").brand(.title2)
                        Text("Finished orders land here with their bill and delivery photo.").brand(.body, Brand.ink2).multilineTextAlignment(.center)
                    }
                    .padding(Brand.s4)
                }
                ForEach(groups) { g in
                    NavigationLink(value: g.id) { OrderCard(group: g, bill: bills[g.id]) }.buttonStyle(.plain)
                }
            }
            .padding(Brand.s4)
        }
        .screen()
        .navigationTitle("History")
        .navigationDestination(for: UUID.self) { GroupView(id: $0, path: $path) }
        .refreshable { await load() }
        .task(id: app.homeVersion) { await load() }
    }

    private func load() async {
        groups = (try? await supabase.from("groups").select()
            .in("state", values: ["delivered", "closed", "cancelled"]).order("delivery_at", ascending: false).execute().value) ?? []
        if let me = app.userID {
            let rows: [BillRow] = (try? await supabase.from("group_bill_v").select().eq("user_id", value: me).execute().value) ?? []
            bills = Dictionary(uniqueKeysWithValues: rows.map { ($0.group_id, $0) })
        }
        loaded = true
    }
}
