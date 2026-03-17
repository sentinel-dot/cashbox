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
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
}
