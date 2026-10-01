import SwiftUI

/// Times the group screen needs that `OrderGroup`/`Item` don't decode (`groups.locked_at`, `items.created_at`).
nonisolated struct GroupTimes: Decodable, Hashable {
    var locked_at: Date?
    var cancelled_at: Date?
}

nonisolated struct ItemTime: Decodable, Hashable {
    var id: UUID
    var created_at: Date
}

/// The order's states, done, now and to come (3-5 stacked, 5-4 inline). "Edits requested" is a step only
/// when an edit round happened.
struct Timeline: View {
    enum Layout { case stacked, inline }

    var group: OrderGroup
    var lockedAt: Date?
    /// When the host asked for edits, if they did.
    var editsAt: Date?
    var hadEdits = false
    var layout: Layout = .stacked

    private enum Phase { case done, now, todo }

    private var steps: [GroupState] {
        var s: [GroupState] = [.open, .locked]
        if hadEdits || group.state == .edits { s.append(.edits) }
        return s + [.sent, .confirmed, .delivered, .closed]
    }

    var body: some View {
        let list = steps
        let at = list.firstIndex(of: group.state) ?? 0
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                let phase: Phase = i < at ? .done : i == at ? .now : .todo
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        dot(s, phase)
                        Rectangle()
                            .fill(i == list.count - 1 ? .clear : phase == .done ? Brand.limeDeep : Brand.liquorice100)
                            .frame(width: 2)
                            .frame(minHeight: layout == .stacked ? 14 : 10, maxHeight: .infinity)
                    }
                    .frame(width: 22)
                    text(s, phase)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .surface(layout == .stacked ? 32 : 28, padding: EdgeInsets(top: 20, leading: 20, bottom: 4, trailing: 20))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func text(_ s: GroupState, _ phase: Phase) -> some View {
        let ink = phase == .todo ? Brand.ink4 : Brand.cocoa
        switch layout {
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).ui(GFont.manrope(15, 700), ink).frame(minHeight: 22)
                if let m = meta(s, phase) { Text(m).ui(GFont.manrope(12), Brand.ink3) }
            }
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            HStack {
                Text(s.title).ui(GFont.manrope(14, 700), ink)
                Spacer()
                if let m = meta(s, phase) { Text(m).ui(GFont.manrope(12), Brand.ink3) }
            }
            .frame(minHeight: 22)
            .padding(.bottom, 10)
        }
    }

    private func dot(_ s: GroupState, _ phase: Phase) -> some View {
        ZStack {
            switch phase {
            case .done:
                Circle().fill(Brand.lime)
                Circle().strokeBorder(Brand.limeDeep, lineWidth: 1.5)
                icon("checkmark", 12, Brand.cocoa, weight: .heavy)
            case .now:
                Circle().fill(Brand.caramel)
                Circle().stroke(Brand.choc100, lineWidth: 5).padding(-2.5)
                icon(nowSymbol(s), 12, Brand.cream, weight: .heavy)
            case .todo:
                Circle().fill(.white)
                Circle().strokeBorder(Brand.liquorice400, lineWidth: 2)
                icon("ellipsis", 12, Brand.cocoa, weight: .heavy)
            }
        }
        .frame(width: 22, height: 22)
    }

    private func nowSymbol(_ s: GroupState) -> String {
        switch s {
        case .open: "clock"
        case .locked: "lock"
        case .edits: "pencil"
        case .sent: "paperplane"
        default: "checkmark"
        }
    }

    private func date(_ s: GroupState) -> Date? {
        switch s {
        case .open: group.created_at
        case .locked: lockedAt
        case .edits: editsAt
        case .sent: group.sent_at
        case .confirmed: group.confirmed_at
        case .delivered: group.delivered_at
        case .closed: group.closed_at
        case .cancelled: nil
        }
    }

    private func meta(_ s: GroupState, _ phase: Phase) -> String? {
        if s == .delivered && phase == .todo {
            return layout == .stacked ? Wita.string(group.delivery_at, "EEE d MMM, HH:mm") + " WITA"
                                      : Wita.string(group.delivery_at, "EEE") + " ~" + Wita.string(group.delivery_at, "HH:mm")
        }
        guard phase != .todo, let d = date(s) else { return nil }
        if layout == .inline { return Wita.string(d, "EEE HH:mm") }
        var line = Wita.string(d, "EEE d MMM, HH:mm")
        if s == .locked, let c = group.cutoff_at, abs(c.timeIntervalSince(d)) < 120 { line += " · at cutoff" }
        return line
    }
}
