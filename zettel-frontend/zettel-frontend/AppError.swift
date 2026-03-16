// AppError.swift
// cashbox — App-weite Fehlertypen

import Foundation

enum AppError: LocalizedError {
    case invalidCredentials
    case unauthorized
    case noActiveSession
    case networkError(String)
    case serverError(Int, String)
    case fiskalyError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "E-Mail oder Passwort falsch."
        case .unauthorized:
            return "Keine Berechtigung für diese Aktion."
        case .noActiveSession:
            return "Keine offene Kassensitzung. Bitte Sitzung öffnen."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        case .serverError(let code, let msg):
            return "Serverfehler \(code): \(msg)"
        case .fiskalyError(let msg):
            return "TSE-Fehler: \(msg)"
        case .unknown(let msg):
            return "Unbekannter Fehler: \(msg)"
        }
    }
}
