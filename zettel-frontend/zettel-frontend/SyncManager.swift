// SyncManager.swift
// cashbox — Minimaler Offline-Queue-Trigger (Phase-3-Vollausbau folgt)
//
// Stößt POST /sync/offline-queue an, sobald das Gerät wieder online ist oder
// die App in den Vordergrund kommt. Ohne diesen Trigger würden offline
// erfasste Bons nie TSE-nachsigniert (KassenSichV).

import Foundation
import SwiftUI

@MainActor
class SyncManager: ObservableObject {
    /// Anzahl noch unsignierter Bons (für OfflineBanner / Einstellungen)
    @Published var pendingCount = 0
    @Published var isSyncing = false

    private let api = APIClient.shared
    private var syncTask: Task<Void, Never>?

    /// Maximale Sync-Runden pro Trigger — verhindert Endlosschleife wenn die
    /// TSE dauerhaft nicht erreichbar ist (requeued-Einträge bleiben pending).
    private let maxRounds = 3

    struct QueueStatus: Decodable {
        let pending: Int
        let processing: Int
        let completed: Int
        let failed: Int
    }

    struct SyncResult: Decodable {
        let processed: Int
        let succeeded: Int
        let failed: Int
        let requeued: Int
        let pendingRemaining: Int
    }

    /// Von außen aufrufen: bei Online-Wechsel, App-Foreground, nach Login.
    func triggerSync() {
        guard syncTask == nil, api.authToken != nil else { return }
        syncTask = Task { [weak self] in
            await self?.runSync()
            self?.syncTask = nil
        }
    }

    func refreshPendingCount() async {
        guard api.authToken != nil else { return }
        if let status: QueueStatus = try? await api.get("/sync/offline-queue") {
            pendingCount = status.pending
        }
    }

    private func runSync() async {
        isSyncing = true
        defer { isSyncing = false }

        for _ in 0..<maxRounds {
            guard let result: SyncResult = try? await api.post("/sync/offline-queue", body: EmptyBodyEncodable()) else {
                break // Netzwerk-/Serverfehler — nächster Trigger versucht erneut
            }
            pendingCount = result.pendingRemaining
            // Fertig, oder es geht nicht voran (nur requeued) → aufhören
            if result.pendingRemaining == 0 || result.succeeded == 0 { break }
        }
    }
}

struct EmptyBodyEncodable: Encodable {}
