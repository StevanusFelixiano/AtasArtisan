import Foundation
import Network

/// Whether the device has a network path (design 6-8: "You're offline…" banner, edits disabled until back).
@Observable
final class Connectivity {
    static let shared = Connectivity()
    private(set) var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            Task { @MainActor in Connectivity.shared.online = up }
        }
        monitor.start(queue: DispatchQueue(label: "ataste.connectivity"))
    }
}
