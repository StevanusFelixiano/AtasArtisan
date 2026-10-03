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
/// Pay first passes its own steps (G2: ask, bills final, everyone pays, send); the current one can carry a reason.
struct Timeline: View {
    enum Layout { case stacked, inline }

    var group: OrderGroup
    var lockedAt: Date?
    /// When the host asked for edits, if they did.
    var editsAt: Date?
    var hadEdits = false
    var layout: Layout = .stacked
    /// Pay first's steps and which one is current; nil draws the order's states.
    var flow: (steps: [TimelineStep], current: Int)? = nil

    enum Phase { case done, now, todo }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var states: [GroupState] {
        var s: [GroupState] = [.open, .locked]
        if hadEdits || group.state == .edits { s.append(.edits) }
        return s + [.sent, .confirmed, .delivered, .closed]
    }

    /// The order's states as steps (order first, as before pay first existed).
    private var stateSteps: (steps: [TimelineStep], current: Int) {
        let list = states
        let steps = list.map { s in
            TimelineStep(id: s.rawValue, title: s.title, symbol: nowSymbol(s), meta: date(s).map { meta(s, $0) }, todoMeta: todoMeta(s))
        }
        return (steps, list.firstIndex(of: group.state) ?? 0)
    }

    var body: some View {
        let (list, at) = flow ?? stateSteps
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                let phase: Phase = s.phase ?? (i < at ? .done : i == at ? .now : .todo)
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        TimelineDot(phase: phase, symbol: s.symbol)
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

    @ViewBuilder private func text(_ s: TimelineStep, _ phase: Phase) -> some View {
        let ink = phase == .todo ? Brand.ink4 : Brand.cocoa
        let title = Text(s.title).foregroundStyle(ink)
            .animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(StatusMotion.nowDelay), value: phase)
            .geometryGroup()
        let time = (phase == .todo ? s.todoMeta : s.meta).map { m in
            Text(m).ui(GFont.manrope(12), Brand.ink3)
                .transition(.opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(StatusMotion.timeDelay)))
        }
        let reason = phase == .now ? s.reason : nil
        switch layout {
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                title.font(GFont.manrope(15, 700)).frame(minHeight: 22)
                time
                if let reason { reasonLine(reason, warn: s.warn) }
            }
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    title.font(GFont.manrope(14, 700))
                    Spacer()
                    time
                }
                .frame(minHeight: 22)
                if let reason { reasonLine(reason, warn: s.warn) }
            }
            .padding(.bottom, 10)
        }
    }

    /// The current step's one reason line (G2), opening 0.20 s after the step turns current. Near Atas's cutoff it
    /// becomes the peach notice.
    @ViewBuilder private func reasonLine(_ text: String, warn: Bool) -> some View {
        let shown = Text(text).ui(GFont.manrope(13, warn ? 600 : 500), warn ? Brand.cocoa : Brand.ink2).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if warn {
                Label { shown } icon: { icon("exclamationmark.triangle", 15) }
                    .labelStyle(IconLabel(spacing: 8, size: 15))
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(Brand.choc100))
                    .padding(.top, 4)
            } else {
                shown
            }
        }
        .transition(.opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(StepsMotion.reasonDelay)))
        .animation(reduceMotion ? nil : StepsMotion.reasonIn.delay(StepsMotion.reasonDelay), value: text)
    }

    /// A done or current step's time: "Fri 3 Oct, 13:00 · at cutoff" stacked, "Fri 13:00" inline.
    func meta(_ s: GroupState, _ d: Date) -> String {
        if layout == .inline { return Wita.string(d, "EEE HH:mm") }
        var line = Wita.string(d, "EEE d MMM, HH:mm")
        if s == .locked, let c = group.cutoff_at, abs(c.timeIntervalSince(d)) < 120 { line += " · at cutoff" }
        return line
    }

    /// Steps to come show nothing, except Delivered: when it's due.
    func todoMeta(_ s: GroupState) -> String? {
        guard s == .delivered else { return nil }
        return layout == .stacked ? Wita.string(group.delivery_at, "EEE d MMM, HH:mm") + " WITA"
                                  : Wita.string(group.delivery_at, "EEE") + " ~" + Wita.string(group.delivery_at, "HH:mm")
    }

    func date(_ s: GroupState) -> Date? {
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

    func nowSymbol(_ s: GroupState) -> String {
        switch s {
        case .open: "clock"
        case .locked: "lock"
        case .edits: "pencil"
        case .sent: "paperplane"
        default: "checkmark"
        }
    }
}

/// One timeline row: its title, the icon its dot shows while current, its time once reached (`meta`) or while to
/// come (`todoMeta`), and the reason line it adds while current. `phase` overrides the position's phase (pay first's
/// Everyone pays stays current after an early send).
struct TimelineStep: Identifiable, Hashable {
    var id: String
    var title: String
    var symbol: String
    var meta: String?
    var todoMeta: String? = nil
    var reason: String? = nil
    /// The reason is a warning (Atas's cutoff is near): the peach notice.
    var warn = false
    var phase: Timeline.Phase? = nil
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
