// ContentView.swift
// cashbox — Root-Router: Login ↔ App

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authStore: AuthStore

    var body: some View {
        Group {
            if authStore.isAuthenticated {
                // TODO: Phase 1 — TableOverviewView einbinden
                Text("✅ Eingeloggt als \(authStore.currentUser?.name ?? "Unbekannt")")
                    .font(.jakarta(20, weight: .semibold))
                    .foregroundColor(DS.C.text)
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authStore.isAuthenticated)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
}
