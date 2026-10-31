//
//  Connectivity.swift
//  outbound
//

import Foundation
import Network
import Observation

/// Whether the app can talk to the server, so screens can say they're offline, hold
/// off saving, and refresh once the connection comes back.
///
/// A network path being up doesn't mean the server answers (a weak signal can still
/// time out, or the server may be down), so requests that can't reach it count as
/// offline too, until the server answers again.
@Observable
final class Connectivity {
    static let shared = Connectivity()

    /// Whether the device has a network path at all.
    private(set) var isOnline = true
    /// Whether the last request got an answer from the server.
    private(set) var canReachServer = true

    /// Whether requests can be expected to go through.
    var isConnected: Bool { isOnline && canReachServer }

    private let monitor = NWPathMonitor()
    private var probeTask: Task<Void, Never>?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.setOnline(isOnline) }
        }
        monitor.start(queue: DispatchQueue(label: "earth.outbound.connectivity"))
    }

    /// Statuses a proxy or load balancer sends when the server behind it is down.
    static let gatewayStatuses = 502...504

    /// The server answered a request, whatever the status.
    func serverResponded() {
        canReachServer = true
        probeTask?.cancel()
        probeTask = nil
    }

    /// A request couldn't reach the server. Checks back every few seconds, since
    /// screens that can't save won't send anything that would notice it's back.
    func serverUnreachable() {
        canReachServer = false
        guard probeTask == nil else { return }
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                if self.isOnline, await Self.serverAnswers() {
                    self.serverResponded()
                }
            }
        }
    }

    private func setOnline(_ isOnline: Bool) {
        self.isOnline = isOnline
        // A new path (e.g. Wi-Fi back) is worth checking right away.
        if isOnline, !canReachServer {
            Task { if await Self.serverAnswers() { serverResponded() } }
        }
    }

    /// Whether the server itself answers; even a 404 means it's there, but not a
    /// gateway saying it's down.
    private static func serverAnswers() async -> Bool {
        var request = URLRequest(url: APIConfig.baseURL, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        guard let http = (try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse else { return false }
        return !gatewayStatuses.contains(http.statusCode)
    }
}
