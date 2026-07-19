// ModelDecodingTests.swift
// TC-IOS / REQ-UX-004: Backend-Responses (snake_case, wörtliche Fixtures) müssen
// mit der Produktions-Decoder-Konfiguration (JSONDecoder.cashbox) verlustfrei
// decodieren — inkl. des receipt-Blocks aus GET /orders/:id (A4-Recovery).

import XCTest
@testable import zettel_frontend

final class ModelDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.cashbox.decode(T.self, from: Data(json.utf8))
    }

    // ── PaymentResult: wörtliche POST /orders/:id/pay-Response ──

    func testPaymentResultDecoding() throws {
        let json = """
        {
          "receipt_id": 12, "receipt_number": 3, "total_gross_cents": 2849,
          "vat_7_net_cents": 327, "vat_7_tax_cents": 23,
          "vat_19_net_cents": 2100, "vat_19_tax_cents": 399,
          "payments": [
            { "method": "cash", "amount_cents": 1000 },
            { "method": "card", "amount_cents": 1849 }
          ],
          "tse_pending": true,
          "tse_transaction_id": null, "tse_serial_number": null, "tse_counter": null
        }
        """
        let result = try decode(PaymentResult.self, json)
        XCTAssertEqual(result.receiptId, 12)
        XCTAssertEqual(result.receiptNumber, 3)
        XCTAssertEqual(result.totalGrossCents, 2849)
        XCTAssertEqual(result.vat7NetCents + result.vat7TaxCents, 350)
        XCTAssertEqual(result.vat19NetCents + result.vat19TaxCents, 2499)
        XCTAssertEqual(result.payments.count, 2)
        XCTAssertEqual(result.payments[0].method, .cash)
        XCTAssertEqual(result.payments[1].amountCents, 1849)
        XCTAssertTrue(result.tsePending)
    }

    // ── OrderDetail: GET /orders/:id — offen (receipt null) und bezahlt (receipt-Block) ──

    private let openOrderJson = """
    {
      "id": 42, "status": "open", "is_takeaway": false,
      "created_at": "2026-07-19T10:00:00.000Z", "closed_at": null,
      "session_id": 7, "opened_by_name": "Niko",
      "table": { "id": 3, "name": "Tisch 3" },
      "items": [
        {
          "id": 1, "product_id": 5, "product_name": "Shisha Premium",
          "product_price_cents": 2500, "vat_rate": "19", "quantity": 1,
          "subtotal_cents": 2500, "discount_cents": 0, "discount_reason": null,
          "created_at": "2026-07-19T10:01:00.000Z",
          "modifiers": [
            { "modifier_option_id": 2, "name": "Fumari Ambrosia", "price_delta_cents": 0 }
          ]
        }
      ],
      "total_cents": 2500,
      "receipt": null
    }
    """

    func testOrderDetailDecoding_offen_receiptNull() throws {
        let order = try decode(OrderDetail.self, openOrderJson)
        XCTAssertEqual(order.id, 42)
        XCTAssertEqual(order.status, .open)
        XCTAssertEqual(order.totalCents, 2500)
        XCTAssertEqual(order.items[0].modifiers[0].name, "Fumari Ambrosia")
        XCTAssertNil(order.receipt)
    }

    func testOrderDetailDecoding_ohneReceiptFeld_bleibtKompatibel() throws {
        // Ältere Backend-Version ohne receipt-Feld darf nicht crashen
        let legacy = openOrderJson.replacingOccurrences(of: ",\n      \"receipt\": null", with: "")
        let order = try decode(OrderDetail.self, legacy)
        XCTAssertNil(order.receipt)
    }

    func testOrderDetailDecoding_bezahlt_mitReceiptBlock() throws {
        let json = openOrderJson.replacingOccurrences(
            of: "\"receipt\": null",
            with: """
            "receipt": {
              "receipt_id": 9, "receipt_number": 1, "total_gross_cents": 2500,
              "vat_7_net_cents": 0, "vat_7_tax_cents": 0,
              "vat_19_net_cents": 2101, "vat_19_tax_cents": 399,
              "payments": [ { "method": "cash", "amount_cents": 2500 } ],
              "tse_pending": false
            }
            """
        ).replacingOccurrences(of: "\"status\": \"open\"", with: "\"status\": \"paid\"")

        let order = try decode(OrderDetail.self, json)
        XCTAssertEqual(order.status, .paid)
        let receipt = try XCTUnwrap(order.receipt)
        XCTAssertEqual(receipt.receiptNumber, 1)
        XCTAssertEqual(receipt.totalGrossCents, 2500)
        XCTAssertEqual(receipt.payments[0].method, .cash)
        XCTAssertFalse(receipt.tsePending)
    }

    // ── ReceiptDetail: GET /receipts/:id (Phase-1-Bon, TSE pending) ──

    func testReceiptDetailDecoding() throws {
        let json = """
        {
          "id": 9, "receipt_number": 1, "status": "active",
          "order_id": 42, "session_id": 7,
          "device_id": 2, "device_name": "iPad Theke",
          "vat_7_net_cents": 0, "vat_7_tax_cents": 0,
          "vat_19_net_cents": 2101, "vat_19_tax_cents": 399,
          "total_gross_cents": 2500, "tip_cents": 0,
          "is_takeaway": false, "is_split_receipt": false,
          "tse_pending": true,
          "tse_transaction_id": null, "tse_serial_number": null,
          "tse_signature": null, "tse_counter": null,
          "tse_transaction_start": null, "tse_transaction_end": null,
          "created_at": "2026-07-19T10:05:00.000Z",
          "raw_receipt_json": null,
          "payments": [
            { "id": 1, "method": "cash", "amount_cents": 2500, "tip_cents": 0,
              "paid_at": "2026-07-19T10:05:00.000Z" }
          ]
        }
        """
        let receipt = try decode(ReceiptDetail.self, json)
        XCTAssertEqual(receipt.receiptNumber, 1)
        XCTAssertEqual(receipt.status, .active)
        XCTAssertEqual(receipt.deviceName, "iPad Theke")
        XCTAssertEqual(receipt.totalGrossCents, 2500)
        XCTAssertTrue(receipt.tsePending)
        XCTAssertNil(receipt.tseSignature)
        XCTAssertEqual(receipt.payments[0].amountCents, 2500)
    }
}
