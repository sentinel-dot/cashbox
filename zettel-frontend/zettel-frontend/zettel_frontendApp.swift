// zettel_frontendApp.swift
// cashbox — App-Entry-Point
// Environment Objects werden hier erstellt und in die gesamte View-Hierarchie injiziert.

import SwiftUI

@main
struct zettel_frontendApp: App {
    @StateObject private var authStore      = AuthStore()
    @StateObject private var networkMonitor = NetworkMonitor()

    // Weitere Stores folgen in Phase 1:
    // @StateObject private var orderStore   = OrderStore()
    // @StateObject private var sessionStore = SessionStore()
    // @StateObject private var syncManager  = SyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authStore)
                .environmentObject(networkMonitor)
        }
    }
}
