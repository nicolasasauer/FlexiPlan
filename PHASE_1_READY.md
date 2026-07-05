# FlexiPlan – Phase 1 (Stand: 2026-07-05, automatischer Lauf)

## Status

Der komplette Phase-1-Code ist implementiert (produktiver Code, keine
Platzhalter/TODOs). **Wichtige Einschränkung:** In der Sandbox dieses
automatischen Laufs war kein Netzwerkzugang zu den Flutter/Dart-Servern
möglich (Proxy-Allowlist blockiert storage.googleapis.com, pub.dev etc.)
und kein Flutter-SDK vorinstalliert. `flutter create`, `flutter analyze`
und `flutter build apk` konnten daher **nicht ausgeführt werden**. Der
Code wurde stattdessen statisch geprüft (Klammer-Balance aller
Dart-Dateien, Schema-Logik gegen das Lastenheft-Beispiel validiert).

## Build auf deinem Rechner (ein Befehl)

```
bootstrap.bat
```

Das Skript führt aus: `flutter create . --project-name flexiplan
--platforms=android,windows` (erzeugt nur die fehlenden Plattformordner,
`lib/` bleibt unangetastet), `flutter pub get`, `flutter analyze`,
`flutter test`, `flutter build apk --debug`. Voraussetzung:
Flutter ≥ 3.29 im PATH.

## Implementierte Komponenten

| Komponente | Datei(en) |
|---|---|
| App-Grundgerüst, Material 3 Dark Mode (hoher Kontrast, große Schriften, 64px-Buttons) | `lib/main.dart` |
| Satz-Bestätigungs-Screen: große +/-Tasten für Reps (±1) und Gewicht (±2,5 kg), „Satz überspringen" mit Sicherheitsabfrage („Satz wirklich überspringen?"), Status `skipped` in der Historie | `lib/screens/workout_screen.dart` |
| Sequentieller Workout-Ablauf inkl. Belastungs-Timer (zeitbasierte Übungen) und Rest-Timer mit „Pause überspringen" | `lib/screens/workout_screen.dart` |
| Hybrid-Import: ausklappbares Copy-Paste-Textfeld **und** Datei-Picker für .json (file_picker) | `lib/screens/import_screen.dart` |
| JSON-Parser mit Schema-Validierung (Lastenheft 4.1) und klarem Fehlerprotokoll | `lib/services/plan_parser.dart` |
| Persistente, update-resistente Speicherung (shared_preferences) mit `data_version` + Migrationsroutine; Export-Schema gemäß Lastenheft 4.2 | `lib/services/storage_service.dart`, `lib/models/workout_session.dart` |
| Summary-Screen (Gesamtzeit, Sätze, Wiederholungen, bewegtes Volumen) | `lib/screens/summary_screen.dart` |
| Verlauf (chronologische Session-Liste, Detailansicht) | `lib/screens/history_screen.dart` |
| Unit-/Widget-Tests (Parser, Storage/Migration, App-Start) | `test/` |
| Beispielplan aus dem Lastenheft zum Testen des Imports | `beispiel_trainingsplan.json` |

## Getroffene Entscheidungen (autonom)

- **Flutter statt SPA/PWA:** Das Lastenheft (3.1) nennt HTML5/JS, der
  Auftrag verlangt explizit eine Flutter-App – umgesetzt wurde Flutter.
  Statt IndexedDB/Wake-Lock: shared_preferences; Wake-Lock folgt in einer
  späteren Phase (z. B. wakelock_plus).
- **Speicherung:** shared_preferences (laut Aufgabenstellung zulässig);
  jede Session trägt `data_version`, Migrationsroutine in
  `StorageService.migrateSession`.
- **Zeitbasierte Sätze:** Das Export-Schema (4.2) kennt nur
  `reps_actual`/`weight_actual_kg`. Für `type: "time"` wird zusätzlich das
  optionale Feld `duration_actual_seconds` geloggt (abwärtskompatible
  Schema-Erweiterung).
- **Übersprungene Sätze** lösen keinen Rest-Timer aus und werden mit
  `reps_actual: 0` gespeichert (wie im Lastenheft-Beispiel).
- **UUID v4** wird ohne Fremdpaket generiert (`lib/utils/uuid.dart`).
- Kein `uuid`-/`intl`-Paket, um die Abhängigkeiten minimal zu halten.

## Noch offen (spätere Phasen)

TTS/Audio-Signale (2.4), Fortschritts-Analyse über Sessions hinweg (2.3),
Backup-Export als Datei (Logik in `exportHistoryJson()` vorhanden, UI
fehlt), Wake-Lock.
