import SwiftUI

/// DEBUG-only screenshot hooks (simulator, headless): `SIMCTL_CHILD_ATASTE_REVIEW_CODE` signs in as the App Review
/// account, `ATASTE_TAB` (1 History, 2 Profile), `ATASTE_OPEN` (group name contains), `ATASTE_SHEET`
/// (menu, send, confirm, bill, board, delivery, pickup, share, claim, shareitem, ask, splititem, product; avatar on the
/// Profile tab),
/// `ATASTE_SIGNIN` (board 9, see `OnboardingFlow` and `HomeView`), `ATASTE_UNVERIFIED` (names, comma-separated, or `me`:
/// those people show without a number), `ATASTE_APPLE` (linked | unlinked: what `apple_linked()` answers), `ATASTE_ROLE`
/// (host | member: how the open group is seen), `ATASTE_SCROLL` (0 to 1: where the group screen starts). Compiled out of
/// release builds.
enum DebugScreens {
    #if DEBUG
    static func value(_ key: String) -> String? { ProcessInfo.processInfo.environment[key] }
    #else
    static func value(_ key: String) -> String? { nil }
    #endif

    /// `ATASTE_SCROLL`: the group screen opens this far down (0 top, 1 bottom); nil keeps the top.
    static var scrollAnchor: UnitPoint? { value("ATASTE_SCROLL").flatMap(Double.init).map { UnitPoint(x: 0.5, y: $0) } }

    /// `ATASTE_UNVERIFIED` names this person (by name; `me` for the signed-in account's own profile).
    static func unverified(_ name: String, me: Bool = false) -> Bool {
        guard let v = value("ATASTE_UNVERIFIED") else { return false }
        let names = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return names.contains(name.lowercased()) || (me && names.contains("me"))
    }
}
