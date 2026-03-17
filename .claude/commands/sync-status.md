Prüfe ob CLAUDE.md den aktuellen Implementierungsstand korrekt widerspiegelt und korrigiere Abweichungen.

## Was du prüfst

### Backend
1. **Routes:** Vergleiche alle Dateien in `backend/src/routes/` mit der "Fertig implementiert ✅"-Tabelle in CLAUDE.md — fehlt ein Eintrag? Ist einer falsch?
2. **Controllers:** Vergleiche `backend/src/controllers/` mit der Projektstruktur-Liste in CLAUDE.md
3. **Migrations:** Vergleiche `backend/src/db/migrations/` mit der Migrations-Liste in CLAUDE.md — fehlen V003, V004 etc.?
4. **Tests:** Vergleiche `backend/src/__tests__/integration/` mit der Test-Liste in CLAUDE.md

### SwiftUI Frontend
5. **Implementierte Views:** Vergleiche alle `.swift`-Dateien in `zettel-frontend/zettel-frontend/` mit der "Fertig implementiert ✅"-Tabelle
6. **Offene Punkte:** Prüfe ob Einträge in "Offene Punkte" bereits als Dateien existieren (dann → in ✅-Tabelle verschieben)
7. **Noch nicht implementiert:** Prüfe ob Views aus der ❌-Tabelle bereits existieren

## Wie du vorgehst

1. Lese die aktuellen Dateilisten (Glob auf routes/, controllers/, migrations/, __tests__/integration/, zettel-frontend/)
2. Lese den relevanten Abschnitt aus CLAUDE.md
3. Vergleiche — liste alle Abweichungen auf
4. Korrigiere CLAUDE.md direkt (Edit-Tool), ohne zu fragen — außer bei echten Unklarheiten

## Was du NICHT änderst

- Die kritischen Regeln (GoBD, Tenant-Isolation, etc.)
- Den Phasenplan
- `implementierungsplan.md` — das ist das Design-Dokument, kein Status-Dokument
- Inhalte die du nicht durch Dateiexistenz verifizieren kannst

## Output

Nach der Prüfung kurze Zusammenfassung:
- Was war veraltet und wurde korrigiert
- Was ist korrekt
- Falls etwas unklar ist: konkrete Frage stellen
