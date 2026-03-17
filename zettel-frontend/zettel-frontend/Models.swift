// Models.swift
// cashbox — Datenmodelle (spiegeln das Backend-Schema wider)

import Foundation

// MARK: - User

struct User: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let email: String
    let role: UserRole
    let isActive: Bool
    let hasPin: Bool
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
}

enum SubscriptionPlan: String, Codable {
    case starter, pro, business
}

enum SubscriptionStatus: String, Codable {
    case trial, active, pastDue = "past_due", cancelled
}

/// Generische `{ ok: true }` Antwort für PATCH/DELETE-Endpunkte
struct OkResponse: Decodable { let ok: Bool }

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

// MARK: - Cash Register Session

struct CashRegisterSession: Identifiable, Codable {
    let id: Int
    let status: String
    let openingCashCents: Int
    let openedAt: String
    let openedByName: String
    let movements: [CashMovement]
}

struct CashMovement: Codable {
    let type: MovementType
    let amountCents: Int
    let reason: String
    let createdAt: String
}

enum MovementType: String, Codable {
    case deposit, withdrawal

    var displayName: String {
        switch self {
        case .deposit:    return "Einlage"
        case .withdrawal: return "Entnahme"
        }
    }
}

struct CloseSessionResult: Codable {
    let sessionId: Int
    let zReportId: Int
    let closingCashCents: Int
    let expectedCashCents: Int
    let differenceCents: Int
    let totalRevenueCents: Int
    let totalOrders: Int
    let totalDiscountCents: Int
    let cancellationCount: Int
}

// MARK: - Order

enum OrderStatus: String, Codable {
    case open, paid, cancelled
}

struct OrderTable: Codable {
    let id: Int
    let name: String
}

struct Order: Identifiable, Codable {
    let id: Int
    let status: OrderStatus
    let isTakeaway: Bool
    let createdAt: String
    let openedByName: String
    let table: OrderTable?
}

struct OrderDetail: Identifiable, Codable {
    let id: Int
    let status: OrderStatus
    let isTakeaway: Bool
    let createdAt: String
    let closedAt: String?
    let sessionId: Int
    let openedByName: String
    let table: OrderTable?
    let items: [OrderItem]
    let totalCents: Int
}

struct OrderItem: Identifiable, Codable {
    let id: Int
    let productId: Int
    let productName: String
    let productPriceCents: Int
    let vatRate: Double
    let quantity: Int
    let subtotalCents: Int
    let discountCents: Int
    let discountReason: String?
    let createdAt: String
    let modifiers: [OrderItemModifier]
}

struct OrderItemModifier: Codable {
    let modifierOptionId: Int
    let name: String
    let priceDeltaCents: Int
}

// MARK: - Product & Modifier

/// Inline-Kategorie-Referenz wie sie in GET /products mitgeliefert wird
struct ProductCategoryRef: Codable, Identifiable {
    let id: Int
    let name: String
    let color: String?
}

struct ModifierOption: Identifiable, Codable {
    let id: Int
    let name: String
    let priceDeltaCents: Int
    let sortOrder: Int
}

struct ModifierGroup: Identifiable, Codable {
    let id: Int
    let productId: Int?
    let categoryId: Int?
    let name: String
    let isRequired: Bool
    let minSelections: Int
    let maxSelections: Int?
    let sortOrder: Int
    let options: [ModifierOption]
}

struct Product: Identifiable, Codable {
    let id: Int
    let name: String
    let priceCents: Int
    let vatRateInhouse: String
    let vatRateTakeaway: String?
    let isActive: Bool
    let createdAt: String
    let category: ProductCategoryRef?
    let modifierGroups: [ModifierGroup]

    var hasRequiredModifiers: Bool {
        modifierGroups.contains { $0.isRequired }
    }
}

// MARK: - Payment

enum PaymentMethod: String, Codable {
    case cash, card

    var displayName: String {
        switch self {
        case .cash: return "Bar"
        case .card: return "Karte"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "banknote"
        case .card: return "creditcard"
        }
    }
}

struct PaymentItem: Codable {
    let method:      PaymentMethod
    let amountCents: Int
}

struct PaymentResult: Codable {
    let receiptId:       Int
    let receiptNumber:   Int
    let totalGrossCents: Int
    let vat7NetCents:    Int
    let vat7TaxCents:    Int
    let vat19NetCents:   Int
    let vat19TaxCents:   Int
    let payments:        [PaymentItem]
    let tsePending:      Bool
}

// MARK: - Receipt

enum ReceiptStatus: String, Codable {
    case active, voided, cancelled
}

struct ReceiptDetail: Identifiable, Codable {
    let id: Int
    let receiptNumber: Int
    let status: ReceiptStatus
    let orderId: Int?
    let sessionId: Int
    let deviceId: Int
    let deviceName: String
    let vat7NetCents: Int
    let vat7TaxCents: Int
    let vat19NetCents: Int
    let vat19TaxCents: Int
    let totalGrossCents: Int
    let tipCents: Int
    let isTakeaway: Bool
    let isSplitReceipt: Bool
    let tsePending: Bool
    let tseTransactionId: String?
    let tseSerialNumber: String?
    let tseSignature: String?
    let tseCounter: Int?
    let tseTransactionStart: String?
    let tseTransactionEnd: String?
    let createdAt: String
    let rawReceiptJson: ReceiptSnapshot?
    let payments: [ReceiptPayment]
}

struct ReceiptPayment: Codable {
    let id: Int
    let method: PaymentMethod
    let amountCents: Int
    let tipCents: Int
    let paidAt: String
}

/// Unveränderlicher Snapshot aller Bon-Pflichtfelder (gespeichert in raw_receipt_json)
struct ReceiptSnapshot: Codable {
    let receiptNumber: Int
    let createdAt: String
    let tenant: ReceiptTenantSnapshot
    let items: [ReceiptItemSnapshot]
    let vat7NetCents: Int
    let vat7TaxCents: Int
    let vat19NetCents: Int
    let vat19TaxCents: Int
    let totalGrossCents: Int
    let payments: [ReceiptPaymentSnapshot]
    let tsePending: Bool
    let tseTransactionId: String?
}

struct ReceiptTenantSnapshot: Codable {
    let name: String
    let address: String
    let vatId: String?
    let taxNumber: String?
}

struct ReceiptItemSnapshot: Codable {
    let productName: String
    let productPriceCents: Int
    let vatRate: String   // "7" oder "19"
    let quantity: Int
    let subtotalCents: Int
    let discountCents: Int
    let discountReason: String?
}

struct ReceiptPaymentSnapshot: Codable {
    let method: PaymentMethod
    let amountCents: Int
}

// MARK: - Reports

struct DailyReport: Codable {
    let date: String
    let receiptCount: Int
    let cancellationCount: Int
    let totalGrossCents: Int
    let vat7NetCents: Int
    let vat7TaxCents: Int
    let vat19NetCents: Int
    let vat19TaxCents: Int
    let paymentsCashCents: Int
    let paymentsCardCents: Int
    let sessions: [ReportSession]
}

struct ReportSession: Identifiable, Codable {
    let id: Int
    let openedAt: String
    let closedAt: String?
    let openingCashCents: Int
    let closingCashCents: Int?
    let expectedCashCents: Int?
    let differenceCents: Int?
    let status: String
}

struct SummaryReport: Codable {
    let from: String
    let to: String
    let receiptCount: Int
    let totalGrossCents: Int
    let vat7NetCents: Int
    let vat7TaxCents: Int
    let vat19NetCents: Int
    let vat19TaxCents: Int
    let paymentsCashCents: Int
    let paymentsCardCents: Int
    let byDay: [DaySummary]
}

struct DaySummary: Codable {
    let date: String
    let receiptCount: Int
    let totalGrossCents: Int
    let paymentsCashCents: Int
    let paymentsCardCents: Int
}

// MARK: - Table & Zone

struct TableZone: Identifiable, Codable {
    let id: Int
    let name: String
    let sortOrder: Int
}

struct TableItem: Identifiable, Codable {
    let id: Int
    let name: String
    let isActive: Bool
    let openOrdersCount: Int
    let zone: TableZone?
}
