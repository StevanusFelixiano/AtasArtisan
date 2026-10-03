import SwiftUI

// MARK: - Part 4 · Testing fixes C–H. Additions only: parts 1–3 names and values are unchanged.
// "Testing Fixes" board, Swift part 4: the Rp 200.000 card's fixed size, the bill turning final, ongkir and
// discount, pay first's steps, and closing once everyone has paid. Values match the board one to one.

/// C · DiscountBar: below the goal the amount and the "more" line stay on one line and scale down
enum DiscountBarLayout {
    static let amountMinScale: CGFloat = 0.6, lineMinScale: CGFloat = 0.8
}

/// D · The bill turning final: card leads, amount follows. BillMotion values unchanged.
enum PaySheetMotion {
    static let card   = Motion.doughLead                  // height
    static let amount = Motion.doughTrail                 // scaleEffect only, never font size
    static let amountScaleFrom: CGFloat = 46.0 / 52.0     // BillMotion.totalSize.from / .to
    static let amountDelay: Double = 0.06
    static let tagDelay: Double = 0.10, countDelay: Double = 0.10
    static let ongkirDelay: Double = 0.14, discountRowDelay: Double = 0.22, rowOffset: CGFloat = 6
    static let payDelay = BillMotion.payDelay             // 0.40, with BillMotion.payBump
}

/// E · Ongkir and discount
enum OngkirMotion {
    static let noteIn = Motion.arrive, noteFadeDelay: Double = 0.06
    static let noteOut = Motion.leave
    static let shareRoundTo = 100                         // Rp per person; the host takes the remainder
    static let maxDigits = 7
}

/// G · Pay first / order first steps
enum StepsMotion {
    static let reasonIn = Motion.settle, reasonDelay = StatusMotion.nowDelay
    static let barSwap  = Motion.digits
    static let sendReadyDelay: Double = 0.10, sendReadyBump: CGFloat = 1.05
    static let cutoffWarning: TimeInterval = 30 * 60      // before Atas's 15:00 WITA cutoff
}

/// H · Close waits for every payment
enum CloseMotion {
    static let rowCollapse = Motion.leave, rowCollapseDelay: Double = 0.6
    static let doneDelay: Double = 0.7
    static let nudgeCooldown: TimeInterval = 4 * 60 * 60
}
