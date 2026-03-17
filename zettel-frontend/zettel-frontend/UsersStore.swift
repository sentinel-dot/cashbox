// UsersStore.swift
// cashbox — Mitarbeiterverwaltung: laden, anlegen, bearbeiten, deaktivieren

import Foundation

@MainActor
final class UsersStore: ObservableObject {

    // ── Published State ────────────────────────────────────────────────────
    @Published private(set) var users:     [User] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error:     AppError?

    // ── Dependencies ───────────────────────────────────────────────────────
    private let api = APIClient.shared

    // ── Public Interface ───────────────────────────────────────────────────

    func loadUsers() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await api.get("/users")
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    func createUser(name: String, email: String, password: String, role: UserRole, pin: String?) async throws {
        let body = CreateUserBody(name: name, email: email, password: password, role: role.rawValue, pin: pin)
        let _: CreateUserResponse = try await api.post("/users", body: body)
        await loadUsers()
    }

    func updateUser(id: Int, name: String?, role: UserRole?, pin: String?) async throws {
        let body = UpdateUserBody(name: name, role: role?.rawValue, pin: pin)
        let _: OkResponse = try await api.patch("/users/\(id)", body: body)
        await loadUsers()
    }

    func deleteUser(id: Int) async throws {
        try await api.delete("/users/\(id)")
        users.removeAll { $0.id == id }
    }

    func clearError() { error = nil }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: UsersStore {
        let store = UsersStore()
        store.users = [
            User(id: 1, name: "Niko",   email: "niko@example.com",  role: .owner,   isActive: true, hasPin: false),
            User(id: 2, name: "Sara",   email: "sara@example.com",  role: .staff,   isActive: true, hasPin: true),
            User(id: 3, name: "Mehmet", email: "mehmet@example.com", role: .manager, isActive: true, hasPin: true),
        ]
        return store
    }

    static var previewEmpty: UsersStore { UsersStore() }
}

// MARK: - Request Bodies (privat)

private struct CreateUserBody: Encodable {
    let name:     String
    let email:    String
    let password: String
    let role:     String
    let pin:      String?
}

private struct CreateUserResponse: Decodable {
    let id:    Int
    let name:  String
    let email: String
    let role:  String
}

private struct UpdateUserBody: Encodable {
    let name: String?
    let role: String?
    let pin:  String?
}

