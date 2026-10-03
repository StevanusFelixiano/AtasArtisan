import SwiftUI

// MARK: - Part 4 · Testing fixes (A–I). Additions only: parts 1–3 names and values are unchanged.
// "Testing Fixes" board: A shared items, B the host's own items, I flavours. (C–H live in their own file.)

/// A · Shared items: pieces claimed until lock
enum PieceMotion {
    static let range = 2...24
    static let defaultPieces = 8                          // when Atas's menu gives no serving count
    static let minPeopleFloor = 2, minPeopleDefault = 3   // the owner counts as one
    static let barHeight: CGFloat = 18, segmentGap: CGFloat = 2, segmentRadius: CGFloat = 4
    static let shareRows = Motion.settle                  // product sheet: pieces + minimum rows
    static let cardIn    = Motion.arrive                  // Up for sharing card
    static let claim     = Motion.pop                     // segment scaleX 0 → 1, .leading
    static let release   = Motion.leave
    static let remoteStagger: Double = 0.025              // per piece: others' claims, lock fill
    static let chipDelay: Double = 0.06, chipFrom: CGFloat = 0.9
    static let removeFade = Motion.fadeOut                // lock, minimum not met
    static let removeCollapse = Motion.leave, removeCollapseDelay: Double = 0.06
    static let noticeIn = Motion.settle, noticeDelay: Double = 0.18, noticeFadeDelay: Double = 0.24
}

/// B · The host's own items
enum HostItemsMotion {
    static let firstItem  = Motion.settle
    static let lockPillIn = Motion.arrive, lockPillDelay: Double = 0.06, lockPillOffset: CGFloat = 12
    static let barWidths: (add: CGFloat, lock: CGFloat) = (1, 1.25)
    static let stackFrom: DynamicTypeSize = .xLarge
}

/// I · Flavours
enum FlavourMotion {
    static let photoOut = Motion.fadeOut, photoIn = Motion.fade
    static let photoScaleFrom: CGFloat = 0.96, photoScale = Motion.settle
    static let chipInkDelay = OptionMotion.inkDelay
}
