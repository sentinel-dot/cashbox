// Models.swift
// cashbox — Datenmodelle (spiegeln das Backend-Schema wider)

import Foundation

// MARK: - User

struct User: Identifiable, Codable, Equatable {
    let id: Int
    let tenantId: Int
    let name: String
    let email: String
    let role: UserRole
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, email, role
        case tenantId = "tenant_id"
        case isActive = "is_active"
    }
}

enum UserRole: String, Codable {
    case owner, manager, staff

    var displayName: String {
        switch self {
        case .owner:   return "Owner"
        case .manager: return "Manager"
        case .staff:   return "Staff"
        }
    }
}

// MARK: - Tenant

struct Tenant: Identifiable, Codable {
    let id: Int
    let name: String
    let address: String
    let vatId: String?
    let taxNumber: String?
    let plan: SubscriptionPlan
    let subscriptionStatus: SubscriptionStatus

    enum CodingKeys: String, CodingKey {
        case id, name, address, plan
        case vatId = "vat_id"
        case taxNumber = "tax_number"
        case subscriptionStatus = "subscription_status"
    }
}

enum SubscriptionPlan: String, Codable {
    case starter, pro, business
}

enum SubscriptionStatus: String, Codable {
    case trial, active, pastDue = "past_due", cancelled
}

// MARK: - Auth Response
// Spiegelt exakt was das Backend zurückgibt — nur id/name/role im user-Objekt

struct AuthResponse: Decodable {
    let token: String
    let refreshToken: String
    let user: AuthUser
}

/// Schlankes User-Objekt wie vom Backend bei Login/Register geliefert.
/// Für vollständige User-Daten: GET /users
struct AuthUser: Codable, Identifiable {
    let id: Int
    let name: String
    let role: UserRole
}
