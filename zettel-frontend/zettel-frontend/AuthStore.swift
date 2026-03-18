// AuthStore.swift
// cashbox — Authentifizierungs-State (JWT, User, Tenant)

import Foundation
import SwiftUI

class AuthStore: ObservableObject {
    @Published var currentUser: AuthUser?
    @Published var isAuthenticated = false
    @Published var availableUsers: [AuthUser] = []
    @Published var sessionExpiredReason: String? = nil

    private let usersKey       = "cachedUsers"
    private let currentUserKey = "cachedCurrentUser"
    private let api = APIClient.shared

    init() {
        // Gecachte User für PIN-Liste laden
        if let data = UserDefaults.standard.data(forKey: usersKey),
           let users = try? JSONDecoder.cashbox.decode([AuthUser].self, from: data) {
            availableUsers = users
        }
        // currentUser wiederherstellen — wird für Rollen-Checks in Views benötigt
        if let data = UserDefaults.standard.data(forKey: currentUserKey),
           let user = try? JSONDecoder.cashbox.decode(AuthUser.self, from: data) {
            currentUser = user
        }
        // Token im Keychain vorhanden → als eingeloggt behandeln (Backend validiert bei erstem Request)
        if api.authToken != nil {
            isAuthenticated = true
        }
    }

    // MARK: - Login (E-Mail + Passwort)

    func login(email: String, password: String) async throws {
        // Backend erwartet device_token beim Login (Gerät muss registriert sein)
        struct Body: Encodable { let email: String; let password: String; let deviceToken: String }
        let response: AuthResponse = try await api.post(
            "/auth/login",
            body: Body(email: email, password: password, deviceToken: api.deviceTokenOrCreate)
        )
        await applyAuthResponse(response)
    }

    // MARK: - Registrierung (neuer Tenant)

    func register(
        businessName: String,
        email: String,
        password: String,
        address: String,
        taxNumber: String,
        deviceName: String
    ) async throws {
        struct Body: Encodable {
            let businessName: String
            let email: String
            let password: String
            let address: String
            let taxNumber: String
            let deviceName: String
            let deviceToken: String
        }
        let response: AuthResponse = try await api.post(
            "/onboarding/register",
            body: Body(
                businessName: businessName,
                email: email,
                password: password,
                address: address,
                taxNumber: taxNumber,
                deviceName: deviceName,
                deviceToken: api.deviceTokenOrCreate
            )
        )
        await applyAuthResponse(response)
    }

    // MARK: - PIN-Login (Benutzer-Schnellwechsel)

    func loginWithPin(pin: String) async throws {
        struct Body: Encodable { let deviceToken: String; let pin: String }
        do {
            let response: AuthResponse = try await api.post(
                "/auth/pin",
                body: Body(deviceToken: api.deviceTokenOrCreate, pin: pin)
            )
            await applyAuthResponse(response)
        } catch AppError.unauthorized {
            throw AppError.wrongPin
        }
    }

    // Aktualisiert die PIN-Liste — nur User mit gesetzter PIN
    func updatePINUsers(_ users: [User]) {
        let authUsers = users.filter { $0.hasPin }.map { AuthUser(id: $0.id, name: $0.name, role: $0.role) }
        cacheUsers(authUsers)
    }

    // MARK: - Token-Refresh

    func refreshToken() async throws {
        struct Body: Encodable { let refreshToken: String }
        guard let stored = KeychainHelper.load(key: "refreshToken") else {
            throw AppError.unauthorized
        }
        let response: AuthResponse = try await api.post(
            "/auth/refresh",
            body: Body(refreshToken: stored)
        )
        await applyAuthResponse(response)
    }

    // MARK: - Logout

    func logout() {
        api.authToken = nil
        KeychainHelper.delete(key: "refreshToken")
        currentUser = nil
        isAuthenticated = false
        sessionExpiredReason = nil
        UserDefaults.standard.removeObject(forKey: currentUserKey)
    }

    /// Automatische Abmeldung bei ungültiger Session — zeigt Hinweis im LoginView.
    @MainActor
    func forceLogout(reason: String) {
        api.authToken = nil
        KeychainHelper.delete(key: "refreshToken")
        currentUser = nil
        sessionExpiredReason = reason
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: currentUserKey)
    }

    // MARK: - Intern

    @MainActor
    private func applyAuthResponse(_ response: AuthResponse) {
        api.authToken = response.token
        KeychainHelper.save(response.refreshToken, key: "refreshToken")
        currentUser = response.user
        isAuthenticated = true
        cacheUsers([response.user])
        // currentUser persistieren damit Rollen-Checks nach App-Neustart funktionieren
        if let data = try? JSONEncoder.cashbox.encode(response.user) {
            UserDefaults.standard.set(data, forKey: currentUserKey)
        }
    }

    private func cacheUsers(_ users: [AuthUser]) {
        availableUsers = users
        if let data = try? JSONEncoder.cashbox.encode(users) {
            UserDefaults.standard.set(data, forKey: usersKey)
        }
    }

    // MARK: - Preview

    static var preview: AuthStore {
        let store = AuthStore()
        store.availableUsers = [
            AuthUser(id: 1, name: "Niko",   role: .owner),
            AuthUser(id: 2, name: "Sara",   role: .staff),
            AuthUser(id: 3, name: "Mehmet", role: .manager),
        ]
        return store
    }

    static var previewLoggedIn: AuthStore {
        let store = AuthStore()
        store.currentUser = AuthUser(id: 1, name: "Niko", role: .owner)
        store.isAuthenticated = true
        return store
    }
}
