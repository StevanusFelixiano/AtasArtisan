import Foundation

/// DEBUG-only screenshot hooks (simulator, headless): `SIMCTL_CHILD_ATASTE_REVIEW_CODE` signs in as the App Review
/// account, `ATASTE_TAB` (1 History, 2 Profile), `ATASTE_OPEN` (group name contains), `ATASTE_SHEET`
/// (menu, send, confirm, bill, board, delivery, share, split, product). Compiled out of release builds.
enum DebugScreens {
    #if DEBUG
    static func value(_ key: String) -> String? { ProcessInfo.processInfo.environment[key] }
    #else
    static func value(_ key: String) -> String? { nil }
    #endif
}
