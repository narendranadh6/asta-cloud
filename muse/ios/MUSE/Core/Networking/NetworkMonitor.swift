#if canImport(Network) && canImport(Observation)
import Foundation
import Network
import Observation

/// Publishes connectivity so screens can show offline states and resume work.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "app.muse.network"))
    }

    deinit {
        monitor.cancel()
    }
}
#endif
