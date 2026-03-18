// ContentView.swift
// cashbox — Root-Router: Login ↔ App

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authStore: AuthStore

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
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
}
