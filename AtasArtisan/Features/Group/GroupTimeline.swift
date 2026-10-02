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
/// when an edit round happened. When the order moves on while it shows, the line to the next step fills top to
/// bottom, the finished step turns to a lime check, the new step pops in caramel with its halo, and its time fades in.
struct Timeline: View {
    enum Layout { case stacked, inline }

    var group: OrderGroup
    var lockedAt: Date?
    /// When the host asked for edits, if they did.
    var editsAt: Date?
    var hadEdits = false
    var layout: Layout = .stacked

    fileprivate enum Phase { case done, now, todo }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        TimelineDot(phase: phase, symbol: nowSymbol(s))
                        Rectangle()
                            .fill(i == list.count - 1 ? .clear : Brand.liquorice100)
                            .overlay {
                                if i < list.count - 1 {
                                    Rectangle().fill(Brand.limeDeep)
                                        .scaleEffect(y: phase == .done || reduceMotion ? 1 : 0, anchor: .top)
                                        .opacity(phase == .done ? 1 : 0)
                                        .animation(reduceMotion ? Motion.Reduced.fade : Motion.doughTrail, value: phase == .done)
                                        .geometryGroup()
                                }
                            }
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
        let title = Text(s.title).foregroundStyle(ink)
            .animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(StatusMotion.nowDelay), value: phase)
            .geometryGroup()
        let time = meta(s, phase).map { m in
            Text(m).ui(GFont.manrope(12), Brand.ink3)
                .transition(.opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(StatusMotion.timeDelay)))
        }
        switch layout {
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                title.font(GFont.manrope(15, 700)).frame(minHeight: 22)
                time
            }
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            HStack {
                title.font(GFont.manrope(14, 700))
                Spacer()
                time
            }
            .frame(minHeight: 22)
            .padding(.bottom, 10)
        }
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

/// A timeline step's 22 pt dot: done is a lime check, now a caramel circle with a 5 pt choc halo and the step's
/// icon, to come a white circle with an ellipsis. Turning done: the check pops and the colours fade after 0.08 s.
/// Turning now: it pops from 0.6 after 0.20 s as the caramel and halo fade in. Reduce Motion crossfades.
private struct TimelineDot: View {
    var phase: Timeline.Phase
    var symbol: String
    @State private var arrivals = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let done = phase == .done, now = phase == .now
        let delay = done ? StatusMotion.doneDelay : StatusMotion.nowDelay
        let colours = (reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(delay)
        ZStack {
            Circle().fill(Brand.choc100).padding(now ? -5 : 0)
            Circle().fill(done ? Brand.lime : now ? Brand.caramel : .white)
            Circle().strokeBorder(done ? Brand.limeDeep : Brand.liquorice400, lineWidth: done ? 1.5 : 2).opacity(now ? 0 : 1)
            PopSymbol(name: done ? "checkmark" : now ? symbol : "ellipsis", animation: Motion.pop.delay(delay))
                .font(.system(size: 12 * 0.85, weight: .heavy))
                .foregroundStyle(now ? Brand.cream : Brand.cocoa)
                .frame(width: 12, height: 12)
        }
        .frame(width: 22, height: 22)
        .animation(colours, value: phase)
        .geometryGroup()
        .kick(reduceMotion ? 0 : arrivals, from: StatusMotion.nowFrom, delay: StatusMotion.nowDelay, spring: Motion.Keyframe.pop)
        .onChange(of: phase) { _, new in if new == .now { arrivals += 1 } }
    }
}
