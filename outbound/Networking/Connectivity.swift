//
//  Connectivity.swift
//  outbound
//

import Network
import Observation

/// Whether the device has a network path at all, so screens can say they're offline
/// and refresh once the connection comes back.
///
/// A path being up doesn't mean the server answers (a weak signal can still time
/// out), so screens also treat a failed refresh of a saved copy as offline.
@Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.isOnline = isOnline }
        }
        monitor.start(queue: DispatchQueue(label: "earth.outbound.connectivity"))
    }
}
