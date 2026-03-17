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
    var deviceTokenOrCreate: String {
        if let existing = deviceToken { return existing }
        let token = UUID().uuidString
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
        body: B?
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw AppError.networkError("Ungültige URL: \(path)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1.0.0", forHTTPHeaderField: "X-App-Version")

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let device = deviceToken {
            req.setValue(device, forHTTPHeaderField: "X-Device-Token")
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

        try mapStatusCode(http.statusCode, data: data)

        do {
            return try JSONDecoder.cashbox.decode(T.self, from: data)
        } catch {
            throw AppError.networkError("Antwort nicht verarbeitbar: \(error.localizedDescription)")
        }
    }

    private func mapStatusCode(_ code: Int, data: Data) throws {
        guard code >= 400 else { return }
        let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error
            ?? HTTPURLResponse.localizedString(forStatusCode: code)
        switch code {
        case 401: throw AppError.unauthorized
        case 402: throw AppError.serverError(402, "Abonnement abgelaufen oder Trial beendet")
        case 409: throw AppError.conflict(msg)
        case 422: throw AppError.serverError(422, msg)
        case 426: throw AppError.serverError(426, "App-Version veraltet — bitte Update installieren")
        default:  throw AppError.serverError(code, msg)
        }
    }
}

// MARK: - Hilftypen

private struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable {}

private struct APIErrorBody: Decodable {
    let error: String
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
