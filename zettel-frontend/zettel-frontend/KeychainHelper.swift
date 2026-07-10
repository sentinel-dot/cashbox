// KeychainHelper.swift
// cashbox — Sicherer Token-Speicher (JWT + Device Token)

import Foundation
import Security

struct KeychainHelper {
    private static let service = "com.cashbox.app"

    /// AfterFirstUnlock: Tokens auch lesbar wenn das iPad gesperrt ist —
    /// nötig für Hintergrund-Sync der Offline-Queue (TSE-Nachsignierung).
    private static let accessible = kSecAttrAccessibleAfterFirstUnlock

    @discardableResult
    static func save(_ string: String, key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String]      = data
        insert[kSecAttrAccessible as String] = accessible
        let status = SecItemAdd(insert as CFDictionary, nil)
        #if DEBUG
        if status != errSecSuccess {
            print("KeychainHelper.save(\(key)) fehlgeschlagen: OSStatus \(status)")
        }
        #endif
        return status == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
