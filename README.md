# FlexiPlan 🏋️

**Minimalistischer, lokaler Workout-Begleiter und digitales Trainingstagebuch.**

FlexiPlan führt dich interaktiv durch dein Training – Satz für Satz, mit Belastungs- und Pausen-Timern, Live-Anpassung von Gewicht und Wiederholungen sowie automatischer Trainingshistorie. Alles bleibt **lokal auf deinem Gerät**: keine Cloud, kein Konto, kein Tracking, nicht einmal eine Internet-Berechtigung.

Trainingspläne sind einfache **JSON-Dateien** – du kannst sie aus den [fertigen Vorlagen](workouts/) kopieren, von deinem Coach bekommen oder dir von einer KI (ChatGPT, Claude, Gemini …) maßschneidern lassen. Wie das geht, steht [unten](#eigene-workouts-erstellen-auch-per-ki).

## Features

- **Hybrid-Import:** JSON-Datei auswählen *oder* direkt aus der Zwischenablage einfügen – mit Schema-Validierung und klarem Fehlerprotokoll
- **Interaktiver Workout-Modus:** sequentielles Abarbeiten von Übung zu Übung, Satz zu Satz
- **Duale Timer:** Belastungs-Timer für Zeit-Übungen (z. B. Planks, vorzeitig beendbar) und Rest-Timer mit „Pause überspringen"
- **Live-Tracking:** tatsächliche Wiederholungen und Gewicht (±2,5 kg) direkt über große Touch-Tasten anpassen und loggen
- **Satz überspringen** mit Sicherheitsabfrage, in der Historie als `skipped` markiert
- **Summary & Historie:** Gesamtzeit, Sätze, Wiederholungen, bewegtes Volumen – dauerhaft lokal gespeichert (mit `data_version`-Schema-Migration, update-resistent)
- **Dark-Mode-first**, große Schriften, „Hands-sweaty-optimierte" Touch-Zonen

## Fertige Workout-Vorlagen

Einfach Datei öffnen, Inhalt kopieren und in der App unter **Trainingsplan importieren → JSON einfügen** einsetzen (oder die Datei aufs Handy laden und per Datei-Import wählen):

| Vorlage | Fokus | Equipment |
|---|---|---|
| [Ganzkörper für Einsteiger](workouts/ganzkoerper_anfaenger.json) | Ganzer Körper, Grundlagen | keins |
| [Push-Tag](workouts/push_kurzhanteln.json) | Brust, Schultern, Trizeps | Kurzhanteln |
| [Pull-Tag](workouts/pull_klimmzugstange.json) | Rücken, Bizeps | Klimmzugstange, Kurzhantel |
| [Bein-Tag](workouts/beine_po_kurzhanteln.json) | Beine, Gesäß | Kurzhanteln |
| [HIIT-Zirkel ~20 min](workouts/hiit_zirkel_20min.json) | Ausdauer, Fettverbrennung | keins |
| [Mobility-Abendroutine](workouts/mobility_abendroutine.json) | Beweglichkeit, Cooldown | keins |
| [V-Cut Core Finisher](TestWorkouts/v_cut.json) | Unterer Bauch, schräge Bauchmuskeln | Klimmzugstange |
| [Ganzkörper Heimtraining](beispiel_trainingsplan.json) | Minimalbeispiel aus der Spezifikation | keins |

Alle Vorlagen werden per Test ([test/workout_templates_test.dart](test/workout_templates_test.dart)) automatisch gegen das Schema validiert.

## JSON-Format (Import-Schema)

Ein Trainingsplan ist ein JSON-Objekt mit folgender Struktur:

```json
{
  "workout_title": "Ganzkörper Heimtraining",
  "version": "1.0",
  "description": "Effektives Training ohne schwere Geräte.",
  "exercises": [
    {
      "id": 1,
      "name": "Liegestütze",
      "description": "Achte auf eine gerade Plankenposition, Ellbogen nah am Körper führen.",
      "type": "reps",
      "sets": 3,
      "reps": 12,
      "weight_kg": 0,
      "rest_duration_seconds": 60
    },
    {
      "id": 2,
      "name": "Plank (Unterarmstütz)",
      "description": "Bauch und Gesäß maximal anspannen. Kein Hohlkreuz bilden.",
      "type": "time",
      "sets": 2,
      "duration_seconds": 45,
      "rest_duration_seconds": 45
    }
  ]
}
```

### Felddefinitionen

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `workout_title` | String | ✅ | Name des Gesamt-Workouts |
| `version` | String | – | Schema-Version, aktuell `"1.0"` |
| `description` | String | – | Kurzbeschreibung des Workouts |
| `exercises` | Array | ✅ | Liste der Übungen (mindestens eine) |
| `id` | Integer | ✅ | Laufende Nummer der Übung |
| `name` | String | ✅ | Name der Übung |
| `description` | String | – | Ausführungshinweise / Form-Cues |
| `type` | String | ✅ | `"reps"` (wiederholungsbasiert) oder `"time"` (zeitbasiert) |
| `sets` | Integer ≥ 1 | ✅ | Anzahl der Sätze |
| `reps` | Integer ≥ 1 | bei `"reps"` | Ziel-Wiederholungen pro Satz |
| `weight_kg` | Zahl ≥ 0 | – | Gewicht in kg (`0` = Eigengewicht), nur bei `"reps"` |
| `duration_seconds` | Integer ≥ 1 | bei `"time"` | Belastungsdauer pro Satz in Sekunden |
| `rest_duration_seconds` | Integer ≥ 0 | ✅ | Pause nach jedem Satz in Sekunden |

Die App validiert beim Import jedes Feld und zeigt bei Verstößen ein vollständiges Fehlerprotokoll an.

## Eigene Workouts erstellen (auch per KI)

Du kannst Pläne von Hand schreiben, von deinem Coach im obigen Format bekommen – oder dir von einer beliebigen KI generieren lassen. Kopiere dazu einfach diesen Prompt und ergänze deine Wünsche:

```text
Erstelle mir einen Trainingsplan als JSON-Datei nach exakt diesem Schema
(keine zusätzlichen Felder, keine Kommentare, nur das reine JSON):

{
  "workout_title": "<Name des Workouts>",
  "version": "1.0",
  "description": "<Kurzbeschreibung>",
  "exercises": [
    {
      "id": <fortlaufende Ganzzahl ab 1>,
      "name": "<Übungsname>",
      "description": "<kurze Ausführungshinweise>",
      "type": "reps",
      "sets": <Ganzzahl >= 1>,
      "reps": <Ganzzahl >= 1>,
      "weight_kg": <Zahl >= 0, 0 bedeutet Eigengewicht>,
      "rest_duration_seconds": <Ganzzahl >= 0>
    },
    {
      "id": <nächste Nummer>,
      "name": "<zeitbasierte Übung, z. B. Plank>",
      "description": "<kurze Ausführungshinweise>",
      "type": "time",
      "sets": <Ganzzahl >= 1>,
      "duration_seconds": <Ganzzahl >= 1>,
      "rest_duration_seconds": <Ganzzahl >= 0>
    }
  ]
}

Regeln:
- "type" ist entweder "reps" (dann sind "reps" Pflicht und "weight_kg" optional)
  oder "time" (dann ist "duration_seconds" Pflicht).
- "rest_duration_seconds" ist bei jeder Übung Pflicht.
- Schreibe die "description" als knappen Technik-Hinweis auf Deutsch.

Meine Wünsche: [z. B. 3er-Split für Muskelaufbau, 45 Minuten pro Einheit,
vorhandenes Equipment: Kurzhanteln bis 20 kg und eine Klimmzugstange,
Trainingserfahrung: 1 Jahr]
```

Die Antwort der KI kopierst du in der App unter **Trainingsplan importieren → JSON einfügen (Copy-Paste)** ein – fertig.

## Entwicklung

Flutter-App (Dart), Zielplattformen Android und Windows. Benötigt Flutter ≥ 3.29.

```bash
flutter pub get
flutter analyze
flutter test                                          # Unit-/Widget-Tests + Vorlagen-Validierung
flutter test integration_test/app_test.dart -d <device>  # E2E auf Emulator/Gerät
flutter run
```

Details zur Teststrategie und bekannten Build-Besonderheiten (file_picker/AGP): [TEST_REPORT_AND_OPTIMIZATION.md](TEST_REPORT_AND_OPTIMIZATION.md). Anforderungen: [Lastenheft_FlexiPlan_V1_2.pdf](Lastenheft_FlexiPlan_V1_2.pdf).

## Lizenz

[MIT](LICENSE) – nutze, verändere und teile FlexiPlan frei.
