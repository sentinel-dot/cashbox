// NetworkMonitor.swift
// cashbox — Netzwerkstatus (Offline-Awareness für TSE-Signatur-Hinweise)

import Foundation
import Network
import SwiftUI

class NetworkMonitor: ObservableObject {
    @Published var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "cashbox.NetworkMonitor", qos: .background)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Preview

    static var preview: NetworkMonitor {
        NetworkMonitor()
    }

    static var previewOffline: NetworkMonitor {
        let m = NetworkMonitor()
        // NWPathMonitor läuft async — für Preview manuell setzen
        DispatchQueue.main.async { m.isOnline = false }
        return m
    }
}
