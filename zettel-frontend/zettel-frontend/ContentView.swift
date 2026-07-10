// ContentView.swift
// cashbox — Root-Router: Login ↔ App

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if authStore.isAuthenticated {
                TableOverviewView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authStore.isAuthenticated)
        .onReceive(NotificationCenter.default.publisher(for: .authSessionExpired)) { _ in
            Task { @MainActor in
                authStore.forceLogout(reason: "Deine Sitzung ist abgelaufen. Bitte erneut anmelden.")
            }
        }
        // Offline-Bons nachsignieren: sobald wieder online / App im Vordergrund / nach Login
        .onChange(of: networkMonitor.isOnline) { _, online in
            if online, authStore.isAuthenticated { syncManager.triggerSync() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, authStore.isAuthenticated, networkMonitor.isOnline {
                syncManager.triggerSync()
            }
        }
        .onChange(of: authStore.isAuthenticated) { _, loggedIn in
            if loggedIn, networkMonitor.isOnline { syncManager.triggerSync() }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
}
