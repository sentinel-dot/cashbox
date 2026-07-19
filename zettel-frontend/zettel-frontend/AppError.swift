// AppError.swift
// cashbox — App-weite Fehlertypen

import Foundation

enum AppError: LocalizedError {
    case invalidCredentials
    case unauthorized
    case authFailed(String)   // 401 mit Server-Nachricht (z.B. "Gerät nicht registriert")
    case noActiveSession
    case wrongPin
    case conflict(String)
    case validationFailed(String)   // 422 — String = betroffene Felder (Diagnose)
    case rateLimited(String)        // 429 mit Server-Nachricht (bereits nutzerfertig, deutsch)
    case networkError(String)
    case serverError(Int, String)
    case fiskalyError(String)
    case unknown(String)

    // Nutzer-Sprache zuerst — das technische Detail (Statuscode, rohe Meldung)
    // wandert in failureReason und wird nur sekundär angezeigt/geloggt.
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "E-Mail oder Passwort falsch."
        case .unauthorized:
            return "Dafür fehlt dir die Berechtigung."
        case .authFailed(let msg):
            return msg
        case .noActiveSession:
            return "Keine offene Kassensitzung. Bitte zuerst eine Schicht öffnen."
        case .wrongPin:
            return "Falsche PIN. Bitte versuch es noch einmal."
        case .conflict(let msg):
            return msg
        case .validationFailed:
            return "Bitte prüfe deine Eingaben."
        case .rateLimited(let msg):
            // Backend liefert bereits einen fertigen deutschen Satz inkl. Wartezeit —
            // durchreichen statt durch "versuch es noch einmal" ersetzen: erneutes
            // Drücken verlängert das Rate-Limit-Fenster nur.
            return msg
        case .networkError:
            return "Keine Verbindung zum Server. Prüfe dein WLAN und versuch es noch einmal."
        case .serverError:
            return "Das hat leider nicht geklappt. Bitte versuch es noch einmal."
        case .fiskalyError:
            return "Die TSE-Signatur ist gerade nicht möglich. Der Bon wird automatisch nachsigniert."
        case .unknown:
            return "Etwas ist schiefgelaufen. Bitte versuch es noch einmal."
        }
    }

    /// Technisches Detail für Support/Diagnose (sekundär anzeigen, nie als Haupttext)
    var failureReason: String? {
        switch self {
        case .validationFailed(let fields):   return fields.isEmpty ? nil : "Betroffen: \(fields)"
        case .networkError(let msg):          return msg
        case .serverError(let code, let msg): return "Serverfehler \(code): \(msg)"
        case .fiskalyError(let msg):          return msg
        case .unknown(let msg):               return msg
        default:                              return nil
        }
    }
}
