# FlexiPlan – E2E-Testbericht & Optimierungsplan

**Datum:** 2026-07-05 (aktualisiert nach Fix-Runde, gleicher Tag)
**Tester:** Autonomer Flutter-QA-Agent (Claude)
**Testgerät:** Android-Emulator `Medium_Phone_API_36.1` (Android 16 / API 36, `emulator-5554`)
**Testgrundlage:** `Lastenheft_FlexiPlan_V1_2.pdf`, `TestWorkouts/v_cut.json`
**Testartefakt:** [`integration_test/app_test.dart`](integration_test/app_test.dart)

## Management Summary (Stand nach Fix-Runde)

**Alle Tests sind grün.** ✅

| Suite | Ergebnis |
|---|---|
| `flutter analyze` | 0 Probleme |
| `flutter test` (Unit-/Widget-Tests) | **13/13 bestanden** (vorher 12/13) |
| `flutter test integration_test/app_test.dart -d emulator-5554` | **2/2 bestanden** (TC1 Datei-Import, TC2 Copy-Paste + voller Workout-Durchlauf), Laufzeit ~1:25 Min. inkl. eines real ablaufenden 60-Sekunden-Belastungs-Timers |

Die im ursprünglichen Bericht dokumentierten Blocker (Start-Crash auf allen Plattformen, Android-Build-Fehler) sowie der UX-Mangel „Belastungs-Timer nicht abbrechbar" wurden behoben. Die App startet, baut, installiert und durchläuft beide E2E-Szenarien auf dem Emulator vollständig – inklusive Verifikation von Gesamtvolumen (30,0 kg mit der +2,5-kg-Anpassung), 76 Wiederholungen, 8 bestätigten und 1 übersprungenem Satz sowie dem Eintrag in der Verlaufs-Historie.

---

## ✅ Durchgeführte Fixes (Nachtrag)

### Fix 1 — Start-Crash behoben ([`lib/main.dart`](lib/main.dart))

- **War:** `base.textTheme.apply(fontSizeFactor: 1.15)` assertete beim ersten `build()` auf jeder Plattform, weil `ThemeData.textTheme` in Flutter 3.44 vor dem Lokalisierungs-Merge keine konkreten `fontSize`-Werte trägt (alle 15 Slots `null`).
- **Fix:** Die M3-Geometrie wird jetzt explizit geladen und skaliert: `Typography.material2021(...).englishLike.merge(typography.white).apply(fontSizeFactor: 1.15)`. Die Lastenheft-Vorgabe „große Schriften" (Faktor 1,15) bleibt erhalten.
- **Verifikation:** Der zuvor rote `test/widget_test.dart` ist grün; App rendert auf Emulator und im Web.

### Fix 2 — Android-Build repariert (`pubspec.yaml`: file_picker ^8.1.2 → **^10.0.0**, aufgelöst 10.3.10)

Dieser Fix hat eine Vorgeschichte, die für künftige Upgrades wichtig ist:

1. **8.3.7 (Ausgangszustand):** bringt hartes `compileSdk 34` mit → kollidiert mit `flutter_plugin_android_lifecycle` (verlangt 36) → `checkDebugAarMetadata` bricht jeden Build ab.
2. **11.0.2 (erster Fix-Versuch, verworfen):** behebt zwar das compileSdk-Problem, ist aber mit **Flutter 3.44 + AGP 9.0.1 unbaubar** – ein Drei-Wege-Deadlock:
   - file_picker 11 prüft in seinem `build.gradle` nur die AGP-Major-Version (`isAgp9OrAbove`) und wendet unter AGP 9 **kein** Kotlin-Gradle-Plugin (KGP) mehr an, weil es Built-in Kotlin voraussetzt.
   - Das Flutter-3.44-Template setzt aber `android.builtInKotlin=false` (+ `android.newDsl=false`) – **zwingend**, denn das Flutter-Gradle-Plugin wendet selbst KGP an, was AGP 9 nur mit diesem Bypass erlaubt (`IllegalStateException: The 'org.jetbrains.kotlin.android' plugin is no longer required since AGP 9.0` bei `builtInKotlin=true`).
   - Ergebnis mit 11.0.2: Niemand kompiliert die Kotlin-Quellen des Plugins → AAR ohne Klassen → `GeneratedPluginRegistrant.java:19: Fehler: Symbol nicht gefunden (FilePickerPlugin)`.
3. **10.3.10 (finaler Fix):** wendet KGP bedingungslos an (kompatibel mit den Template-Bypass-Flags) **und** erbt `compileSdk flutter.compileSdkVersion` (= 36). Baut sauber; es bleibt eine harmlose Deprecation-Warnung („plugins that apply KGP: file_picker").
- Die Dart-API-Aufrufe (`FilePicker.platform.pickFiles`) entsprechen wieder der ursprünglichen Codebasis; `import_screen.dart` ist gegenüber dem Original unverändert bis auf nichts – der zwischenzeitliche 11er-API-Umbau wurde zurückgenommen.
- **Upgrade-Pfad:** Auf file_picker ≥ 11 erst wechseln, wenn Flutter Built-in Kotlin unterstützt (dann `android.builtInKotlin=true` + statische `FilePicker.pickFiles`-API).

### Fix 3 — Belastungs-Timer vorzeitig beendbar ([`lib/screens/workout_screen.dart`](lib/screens/workout_screen.dart))

- Neuer Button **„Satz vorzeitig beenden"** in der Timer-Ansicht (`_buildTimerView`) + Methode `_stopExerciseTimerEarly()`: stoppt den Timer und übernimmt die bereits verstrichene Zeit als Ist-Wert in den Log-Screen (dort per ±5s anpassbar). Behebt den ursprünglichen Mangel 6 – ein Nutzer kann eine zeitbasierte Übung jetzt abbrechen, ohne das gesamte Workout zu verwerfen.
- Nebeneffekt: erfüllt die Testanforderung „Belastungs-Timer im Test abkürzen" auf echtem Nutzerweg (TC2 kürzt Sätze 2+3 der Plank darüber ab; Satz 1 lässt den 60s-Timer bewusst komplett real ablaufen und deckt so den automatischen Übergang in den Log-Screen ab).

### Infrastruktur-Fixes (keine App-Logik)

| Problem | Lösung |
|---|---|
| Emulator-Datenpartition voll (`INSTALL_FAILED_INSUFFICIENT_STORAGE`, 5,8G zu 91 % belegt) | AVD-Konfig `disk.dataPartition.size` 6G → **10G** (`~/.android/avd/Medium_Phone.avd/config.ini`) + einmalig `-wipe-data` |
| `integration_test`-Abhängigkeit fehlte | in `pubspec.yaml` (dev_dependencies) ergänzt |
| Testskript-Robustheit auf realem Gerät | 3 Erkenntnisse eingebaut: (a) ListView baut lazy – Ziele unterhalb des Folds existieren nicht im Baum, daher `scrollUntilVisible` statt direktem `tap`/`ensureVisible`; (b) nach `enterText` verschiebt die einfahrende IME das Layout asynchron – vor Folge-Taps `FocusManager…unfocus()` + kurze Realzeit-Wartepause; (c) reale Timer per Polling-Helfer (`_waitForText`) statt fixer pump-Schleifen abwarten |

---

## 🟢 Erfolgreich getestete Features (E2E auf dem Emulator, Stand nach Fixes)

| Bereich | Status | Bemerkung |
|---|---|---|
| **ADB-Push** | ✅ | `adb push "TestWorkouts/v_cut.json" /sdcard/Download/Vcut.json` verifiziert (unter Git-Bash `MSYS_NO_PATHCONV=1` nötig, sonst wird `/sdcard/...` zu `C:/Program Files/Git/sdcard/...` umgeschrieben) |
| **TC1: Datei-Import via File Picker** | ✅ | Kompletter App-Codepfad (Datei-Bytes → UTF-8 → `PlanParser` → Vorschau „Validierung erfolgreich" → „Plan aktivieren" freigeschaltet → Home zeigt aktiven Plan, „Workout starten" enabled). Hinweis: Der native SAF-Dialog selbst ist prinzipbedingt nicht per WidgetTester bedienbar; er wird durch eine Test-Bridge ersetzt, die die gepushte Datei einliest. Scoped Storage verweigert dem App-Prozess den Direktzugriff auf `/sdcard/Download` (erwartete `PathAccessException`, geloggt) → die Bridge nutzt dokumentiert die identische eingebettete Kopie. |
| **TC2: Copy-Paste-Import** | ✅ | JSON per `enterText` ins Textfeld, „Prüfen & übernehmen", Validierung, Aktivierung |
| **TC2: Übung 1 (Hängendes Beinheben)** | ✅ | Satz 1 mit **+2,5 kg** über die „+"-Taste, Sätze 2+3 mit Vorgabewerten, Rest-Timer jeweils übersprungen |
| **TC2: Übung 2 (Russian Twists)** | ✅ | Satz 2 über „Satz überspringen" mit bestätigter Sicherheitsabfrage („Satz überspringen?"), Status `skipped` in der Session verifiziert |
| **TC2: Übung 3 (Spiderman-Plank, zeitbasiert)** | ✅ | Satz 1: 60s-Belastungs-Timer real abgelaufen (Auto-Übergang in Log-Screen, `duration_actual_seconds: 60` verifiziert); Sätze 2+3 über neuen „Satz vorzeitig beenden"-Button abgekürzt |
| **TC2: Summary-Screen** | ✅ | Verifiziert direkt am Session-Objekt **und** an der UI: 8 bestätigte Sätze, 1 übersprungen, 76 Wdh. (36+40; zeitbasierte Übung zählt schemagemäß nicht zu Reps/Volumen), **Volumen 30,0 kg** (= 12 Wdh. × 2,5 kg aus der Live-Änderung) |
| **TC2: Historie** | ✅ | Nach „Fertig": Home zeigt „Verlauf (1 Sessions)" – Session wurde über die echte SharedPreferences-Schicht des Geräts persistiert (Test cleart echte Prefs statt Mock) |
| **Dark Mode / Theme** | ✅ | `widget_test.dart` prüft Brightness.dark + skalierte Schriften; App rendert nach Fix 1 korrekt |
| **Unit-Tests Parser/Storage** | ✅ 12/12 | unverändert grün (Schema 4.1/4.2, Fehlerprotokoll, Migration) |

---

## 🔴 Verbleibende Mängel / offene Punkte

Die ursprünglichen Blocker sind behoben. Übrig bleiben (unverändert aus dem Erstbericht, nach Priorität):

1. **Keine Widget-Keys/Test-Tags in `lib/`** – die E2E-Tests müssen über sichtbaren UI-Text lokalisieren (brüchig bei Wording-/i18n-Änderungen). Betrifft auch `ElevatedButton.icon(...)` (private Subklasse, `byType` matcht nicht – Workaround per `is ElevatedButton`-Prädikat im Test).
2. **Lastenheft 2.3 „Fortschritts-Analyse" fehlt** ([`history_screen.dart`](lib/screens/history_screen.dart)): kein Vergleich identischer Übungen über Sessions hinweg (Pflicht-Feature V1).
3. **Lastenheft 2.4 TTS + Audio-Signale fehlen** (kein Audio-Package eingebunden).
4. **Lastenheft 3.1 Wake-Lock fehlt** (Bildschirm kann im Workout sperren; z. B. `wakelock_plus`).
5. **Lastenheft 3.2 Backup nur halb**: `exportHistoryJson()` existiert ([`storage_service.dart:83`](lib/services/storage_service.dart)), aber ohne UI-Anbindung und ohne Wiederimport von `flexiplan_backup.json`.
6. **Timer nicht injizierbar** (`Timer.periodic` fest verdrahtet): E2E-Tests müssen reale Sekunden abwarten (TC2 ≈ 1:25 Min. wegen des 60s-Volllaufs). Eine injizierbare Uhr würde das eliminieren.
7. **file_picker-Deprecation:** 10.x wendet KGP an – künftige Flutter-Versionen werden das ablehnen (Build-Warnung). Upgrade-Pfad siehe Fix 2.
8. *(Kosmetisch)* Nach erfolgreicher Validierung liegt „Plan aktivieren" unterhalb des Folds – ein automatisches Hinscrollen zur Vorschau-Karte wäre nutzerfreundlicher.

### Dokumentierte, bewusste Lastenheft-Abweichungen (bestätigungsbedürftig)

- Flutter-App statt SPA/PWA (3.1) – gemäß übergeordnetem Auftrag.
- `shared_preferences` statt IndexedDB/LocalStorage (3.2) – plattformbedingt, mit `data_version`-Migration umgesetzt.

---

## 📋 Nächste Schritte

1. **Fehlende Pflicht-Features V1** (Reihenfolge nach Lastenheft-Gewicht): Fortschritts-Analyse (2.3) → Backup-Export/-Import-UI (3.2) → Wake-Lock (3.1) → TTS/Audio (2.4).
2. **Testbarkeit härten:** Widget-Keys für alle interaktiven Elemente (`Key('start_workout_button')` usw.) + injizierbare Zeitquelle für die Timer; danach die Text-Finder in `app_test.dart` auf Keys umstellen.
3. **file_picker beobachten:** Sobald eine Flutter-Version Built-in Kotlin unterstützt, auf file_picker ≥ 11 heben (API-Migration: statisches `FilePicker.pickFiles`, `FilePickerPlatform.instance` für Test-Bridges) und `android.builtInKotlin=true` setzen.
4. Optional: `patrol` für echte Bedienung des nativen SAF-Dialogs.

---

### Anhang: Reproduzierbare Testumgebung (dieser Rechner)

- **Emulator-Start (Pflicht-Workaround):** `emulator -avd Medium_Phone_API_36.1 -no-snapshot -no-window -gpu swiftshader_indirect -no-boot-anim` – der Standard-GPU-Modus (`flutter emulators --launch`) hängt auf diesem System (AMD Radeon RX 9060 XT) mit `Failed to create EGL fence sync` / eingefrorenen QEMU-Threads.
- **AVD:** Datenpartition wurde auf 10G erhöht (`disk.dataPartition.size=10G` in `~/.android/avd/Medium_Phone.avd/config.ini`); bei erneutem `INSTALL_FAILED_INSUFFICIENT_STORAGE` Emulator einmal mit `-wipe-data` starten.
- **ADB unter Git-Bash:** vor Gerätepfaden `export MSYS_NO_PATHCONV=1` setzen.
- **Kompletter E2E-Ablauf:**
  ```
  adb push "TestWorkouts/v_cut.json" /sdcard/Download/Vcut.json
  flutter test integration_test/app_test.dart -d emulator-5554
  ```
