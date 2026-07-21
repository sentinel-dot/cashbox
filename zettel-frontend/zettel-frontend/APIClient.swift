// APIClient.swift
// cashbox — HTTP-Client (JWT + Device Token, async/await)

import Foundation

class APIClient {
    static let shared = APIClient()
    private init() {}

    // MARK: - Konfiguration

    #if DEBUG
    var baseURL = "http://localhost:3000"
    #else
    var baseURL = "https://api.cashbox.app"
    #endif

    var authToken: String? {
        get { KeychainHelper.load(key: "authToken") }
        set {
            if let t = newValue { KeychainHelper.save(t, key: "authToken") }
            else { KeychainHelper.delete(key: "authToken") }
        }
    }

    var deviceToken: String? {
        get { KeychainHelper.load(key: "deviceToken") }
        set {
            if let t = newValue { KeychainHelper.save(t, key: "deviceToken") }
            else { KeychainHelper.delete(key: "deviceToken") }
        }
    }

    /// Einmaliges Device-Token — wird beim ersten Start generiert und nie mehr geändert.
    /// In DEBUG-Builds wird der feste Seed-Token genutzt (passend zur V005-Migration).
    var deviceTokenOrCreate: String {
        if let existing = deviceToken { return existing }
        #if DEBUG
        let token = "shishabar-dev-ipad-token-2026"
        #else
        let token = UUID().uuidString
        #endif
        deviceToken = token
        return token
    }

    // MARK: - Öffentliche Methoden

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET", body: nil as EmptyBody?)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(path, method: "POST", body: body)
    }

    /// POST mit Zusatz-Headern (z.B. Idempotency-Key beim Preset-Import)
    func post<T: Decodable, B: Encodable>(_ path: String, body: B, headers: [String: String]) async throws -> T {
        try await request(path, method: "POST", body: body, extraHeaders: headers)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(path, method: "PATCH", body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request(path, method: "DELETE", body: nil as EmptyBody?)
    }

    // MARK: - Core

    private func request<T: Decodable, B: Encodable>(
        _ path: String,
        method: String,
        body: B?,
        allowRefresh: Bool = true,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw AppError.networkError("Ungültige URL: \(path)")
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1.0.0", forHTTPHeaderField: "X-App-Version")

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let device = deviceToken {
            req.setValue(device, forHTTPHeaderField: "X-Device-Token")
        }
        for (field, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            req.httpBody = try JSONEncoder.cashbox.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("Keine HTTP-Antwort erhalten")
        }

        // 401 mit vorhandenem Token: einmalig Refresh versuchen und Request
        // wiederholen — statt den Kassierer mitten in der Schicht auszuloggen.
        if http.statusCode == 401, allowRefresh, authToken != nil, path != "/auth/refresh" {
            if await attemptTokenRefresh() {
                return try await request(path, method: method, body: body, allowRefresh: false, extraHeaders: extraHeaders)
            }
        }

        try mapStatusCode(http.statusCode, data: data)

        do {
            return try JSONDecoder.cashbox.decode(T.self, from: data)
        } catch {
            throw AppError.networkError("Antwort nicht verarbeitbar: \(error.localizedDescription)")
        }
    }

    // MARK: - Token-Refresh (POST /auth/refresh liefert nur {token, refreshToken})

    private var refreshTask: Task<Bool, Never>?

    private func attemptTokenRefresh() async -> Bool {
        // Laufenden Refresh mitbenutzen — parallele 401s lösen nur EINEN Refresh aus
        if let running = refreshTask { return await running.value }

        let task = Task<Bool, Never> { [weak self] in
            guard let self, let stored = KeychainHelper.load(key: "refreshToken") else { return false }
            struct Body: Encodable { let refreshToken: String }
            struct RefreshResponse: Decodable { let token: String; let refreshToken: String }
            do {
                let resp: RefreshResponse = try await self.request(
                    "/auth/refresh", method: "POST",
                    body: Body(refreshToken: stored),
                    allowRefresh: false
                )
                self.authToken = resp.token
                KeychainHelper.save(resp.refreshToken, key: "refreshToken")
                return true
            } catch {
                return false
            }
        }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    private func mapStatusCode(_ code: Int, data: Data) throws {
        guard code >= 400 else { return }
        let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        let serverMsg = body?.error ?? ""
        switch code {
        case 401:
            // Wenn ein Token vorhanden war → Session abgelaufen → App-weite Abmeldung auslösen
            if authToken != nil {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .authSessionExpired, object: nil)
                }
            }
            throw AppError.authFailed(serverMsg.isEmpty ? "Anmeldung fehlgeschlagen. Bitte erneut versuchen." : serverMsg)
        case 402:
            throw AppError.serverError(402, "Abonnement abgelaufen oder Trial beendet.")
        case 403:
            throw AppError.unauthorized
        case 409:
            throw AppError.conflict(serverMsg.isEmpty ? "Aktion nicht möglich." : serverMsg)
        case 422:
            // details enthält die Zod-Meldungen (englisch, technisch) — die betroffenen
            // Feldnamen reichen als Diagnose in failureReason, der Haupttext bleibt deutsch.
            let fields = (body?.details?.keys).map { Array($0).sorted().joined(separator: ", ") } ?? ""
            throw AppError.validationFailed(fields)
        case 426:
            throw AppError.serverError(426, "App-Version veraltet — bitte Update installieren.")
        case 429:
            throw AppError.rateLimited(serverMsg.isEmpty
                ? "Zu viele Versuche. Bitte kurz warten."
                : serverMsg)
        default:
            let fallback = "Unerwarteter Fehler (\(code))."
            throw AppError.serverError(code, serverMsg.isEmpty ? fallback : serverMsg)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let authSessionExpired = Notification.Name("cashbox.authSessionExpired")
}

// MARK: - Hilftypen

private struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable {}

private struct APIErrorBody: Decodable {
    let error: String
    /// Nur bei 422 gesetzt (validationMiddleware): Feldname → Zod-Meldungen.
    let details: [String: [String]]?
}

// MARK: - JSON Konfiguration (snake_case ↔ camelCase)

extension JSONEncoder {
    static let cashbox: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}

extension JSONDecoder {
    static let cashbox: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
