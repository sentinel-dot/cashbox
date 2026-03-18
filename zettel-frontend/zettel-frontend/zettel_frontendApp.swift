// zettel_frontendApp.swift
// cashbox — App-Entry-Point
// Environment Objects werden hier erstellt und in die gesamte View-Hierarchie injiziert.

import SwiftUI

@main
struct zettel_frontendApp: App {

    init() {
        // Entfernt die iPad-Input-Accessory-Bar (QuickType/Undo-Bar), die sonst
        // AutoLayout-Constraint-Konflikte ("Unable to simultaneously satisfy constraints")
        // verursacht und den ersten Keyboard-Aufbau verlangsamt.
        UITextField.appearance().inputAssistantItem.leadingBarButtonGroups  = []
        UITextField.appearance().inputAssistantItem.trailingBarButtonGroups = []
        UITextView.appearance().inputAssistantItem.leadingBarButtonGroups   = []
        UITextView.appearance().inputAssistantItem.trailingBarButtonGroups  = []
    }
    @StateObject private var authStore      = AuthStore()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var sessionStore   = SessionStore()
    @StateObject private var orderStore     = OrderStore()
    @StateObject private var tableStore     = TableStore()
    @StateObject private var productStore   = ProductStore()
    @StateObject private var reportStore    = ReportStore()
    @StateObject private var usersStore     = UsersStore()

    // Phase 3:
    // @StateObject private var syncManager  = SyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authStore)
                .environmentObject(networkMonitor)
                .environmentObject(sessionStore)
                .environmentObject(orderStore)
                .environmentObject(tableStore)
                .environmentObject(productStore)
                .environmentObject(reportStore)
                .environmentObject(usersStore)
        }
    }
}
