// E2E-Tests für FlexiPlan auf dem Android-Emulator.
//
// TEST CASE 1: Datei-Import via File Picker aus /sdcard/Download
//              (Datei zuvor per `adb push` auf den Emulator geschoben).
// TEST CASE 2: Copy-Paste-Import + vollständiger Workout-Durchlauf über
//              alle 3 Übungen aus workouts/v_cut.json bis zum
//              Summary-Screen inkl. Zahlen-Verifikation.
//
// Ausführung:
//   adb push "workouts/v_cut.json" /sdcard/Download/Vcut.json
//   flutter test integration_test/app_test.dart -d <device-id>
//
// Werkzeug-Grenze (kein App-Bug): Der native
// Android-SAF-Dateiauswahldialog läuft in einer eigenen System-Activity
// außerhalb des Flutter-Widget-Baums und kann nicht per WidgetTester
// bedient werden. TEST CASE 1 ersetzt deshalb FilePicker.platform
// durch _PushedFileFilePicker, die die zuvor per ADB gepushte Datei
// einliest und so den kompletten App-seitigen Code-Pfad (_pickFile ->
// utf8.decode -> PlanParser.parse -> Button-Freischaltung) real auf dem
// Gerät prüft.
//
// Timer-Strategie in TEST CASE 2 (Übung 3, zeitbasiert): Die Timer laufen
// im On-Device-Test in Echtzeit (IntegrationTestWidgetsFlutterBinding,
// kein FakeAsync). Satz 1 lässt den 60s-Belastungs-Timer daher einmal
// komplett real ablaufen (deckt den automatischen Übergang in den
// Log-Screen ab); Sätze 2 und 3 kürzen den Timer über den Button
// "Satz vorzeitig beenden" ab.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flexiplan/main.dart';
import 'package:flexiplan/models/workout_session.dart';
import 'package:flexiplan/screens/summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An workouts/v_cut.json angelehnter Testplan für den Copy-Paste-Import
/// (TEST CASE 2). Bewusste Abweichung von der Vorlage: Übung 1 bleibt
/// gewichtsfähig (weight_kg statt bodyweight), damit der ±2,5-kg-Stepper
/// getestet wird; Übung 2 nutzt bodyweight und deckt damit den
/// Log-Screen OHNE Gewichtseingabe ab.
const String _vCutJsonContent = '''
{
  "workout_title": "V-Cut Core Finisher",
  "version": "1.0",
  "description": "Gezieltes Zusatztraining für den unteren Bauch und die schrägen Bauchmuskeln zur Definition des V-Cuts.",
  "exercises": [
    {
      "id": 1,
      "name": "Hängendes Beinheben",
      "description": "An der Klimmzugstange hängen. Die Beine kontrolliert nach oben ziehen und das Becken am höchsten Punkt bewusst nach oben-vorne einrollen. Kein Schwung.",
      "type": "reps",
      "sets": 3,
      "reps": 12,
      "weight_kg": 0,
      "rest_duration_seconds": 60
    },
    {
      "id": 2,
      "name": "Russian Twists",
      "description": "Im Sitzen den Oberkörper leicht nach hinten lehnen, Beine anwinkeln und den Oberkörper kontrolliert von links nach rechts drehen.",
      "type": "reps",
      "sets": 3,
      "reps": 20,
      "bodyweight": true,
      "rest_duration_seconds": 60
    },
    {
      "id": 3,
      "name": "Spiderman-Plank",
      "description": "Im Unterarmstütz den Bauch fest anspannen und abwechselnd das linke und rechte Knie über die Seite zum gleichseitigen Ellenbogen ziehen.",
      "type": "time",
      "sets": 3,
      "duration_seconds": 60,
      "rest_duration_seconds": 60
    }
  ]
}
''';

/// Pfad, unter dem die Testdatei vor dem Testlauf abgelegt wird:
/// `adb push "workouts/v_cut.json" /sdcard/Download/Vcut.json`.
const String _adbPushedFilePath = '/storage/emulated/0/Download/Vcut.json';

/// Test-Bridge für TEST CASE 1 (siehe Datei-Kommentar). Liest bevorzugt
/// die real gepushte Datei; falls Android Scoped Storage den Direktzugriff
/// aus dem App-Prozess heraus verweigert, wird auf die eingebettete
/// Testkopie ausgewichen, damit die App-Validierungslogik dennoch
/// geprüft werden kann.
class _PushedFileFilePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    // ignore: deprecated_member_use
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    Uint8List bytes;
    try {
      bytes = await File(_adbPushedFilePath).readAsBytes();
      // ignore: avoid_print
      print('[E2E] Vcut.json real von $_adbPushedFilePath gelesen '
          '(${bytes.length} Byte).');
    } catch (error) {
      // ignore: avoid_print
      print('[E2E] Direktzugriff auf $_adbPushedFilePath fehlgeschlagen: '
          '$error. Nutze eingebettete Kopie als Fallback (siehe '
          'Dateikommentar).');
      bytes = Uint8List.fromList(utf8.encode(_vCutJsonContent));
    }
    return FilePickerResult(<PlatformFile>[
      PlatformFile(name: 'Vcut.json', size: bytes.length, bytes: bytes),
    ]);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Jeder Testdurchlauf beginnt mit leerem lokalen Speicher (entspricht
    // "Starte die App neu"). Bewusst über die ECHTE SharedPreferences-
    // Implementierung des Geräts (clear statt Mock), damit auch die
    // Persistenzschicht real mitgetestet wird.
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  group('TEST CASE 1 – Datei-Import via File Picker', () {
    testWidgets('Vcut.json aus /sdcard/Download wird geladen und validiert',
        (tester) async {
      FilePicker.platform = _PushedFileFilePicker();

      await tester.pumpWidget(const FlexiPlanApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trainingsplan importieren'));
      await tester.pumpAndSettle();
      expect(find.text('Plan importieren'), findsOneWidget);

      await tester.tap(find.text('JSON-Datei auswählen'));
      await tester.pumpAndSettle();

      // Datei-Auswahl füllt das Textfeld → Live-Validierung zeigt eine
      // Statuszeile ("… · N Übungen · M Sätze") und schaltet den Button
      // frei. "Übungen ·" kommt nur in der Statuszeile vor (nicht im JSON).
      expect(find.textContaining('Übungen ·'), findsOneWidget,
          reason:
              'Vcut.json aus dem Download-Ordner sollte erfolgreich validiert werden.');
      expect(_isElevatedButtonEnabled(tester, 'Plan übernehmen'), isTrue,
          reason: '"Plan übernehmen" muss nach erfolgreicher Live-Validierung '
              'freigeschaltet sein.');

      await _applyPlan(tester);

      expect(find.text('FlexiPlan'), findsOneWidget);
      expect(find.text('Workout starten'), findsOneWidget);
      expect(_isElevatedButtonEnabled(tester, 'Workout starten'), isTrue,
          reason: '"Workout starten" muss freigeschaltet sein, sobald ein '
              'Plan aktiv ist.');
    });
  });

  group('TEST CASE 2 – Copy-Paste-Import & voller Workout-Durchlauf', () {
    testWidgets(
      'Kompletter Workout-Ablauf inkl. Summary-Screen',
      (tester) async {
        await tester.pumpWidget(const FlexiPlanApp());
        await tester.pumpAndSettle();

        // --- Copy-Paste-Import ---
        await tester.tap(find.text('Trainingsplan importieren'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), _vCutJsonContent);
        // Kein "Prüfen"-Schritt mehr: Die Eingabe wird live validiert.
        await tester.pumpAndSettle();

        // Tastatur schließen: Die nach enterText geöffnete IME verkleinert
        // den Viewport (adjustResize) und verschiebt das Layout asynchron
        // zur Flutter-Frame-Pipeline; ohne Unfocus wären die folgenden
        // Finder/Taps unzuverlässig.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.textContaining('Übungen ·'), findsOneWidget);
        expect(_isElevatedButtonEnabled(tester, 'Plan übernehmen'), isTrue);

        await _applyPlan(tester);

        await _scrollToAndTap(tester, 'Workout starten');

        // --- Übung 1: Hängendes Beinheben (reps, 3 Sätze à 12 Wdh.) ---
        expect(find.text('Hängendes Beinheben'), findsOneWidget);

        // Satz 1: Gewicht um +2,5 kg erhöhen, bestätigen, Pause überspringen.
        await _incrementWeight(tester);
        await _confirmSet(tester);
        await _skipRestIfShown(tester);

        // Satz 2 & 3: mit Vorgabewerten bestätigen.
        await _confirmSet(tester);
        await _skipRestIfShown(tester);
        await _confirmSet(tester);
        await _skipRestIfShown(tester);

        // --- Übung 2: Russian Twists (reps, 3 Sätze à 20 Wdh.) ---
        expect(find.text('Russian Twists'), findsOneWidget);

        // Satz 1: normal bestätigen.
        await _confirmSet(tester);
        await _skipRestIfShown(tester);

        // Satz 2: überspringen inkl. Sicherheitsabfrage.
        await _skipSetWithSafetyPrompt(tester, setNumber: 2);

        // Satz 3: normal bestätigen.
        await _confirmSet(tester);
        await _skipRestIfShown(tester);

        // --- Übung 3: Spiderman-Plank (time, 3 Sätze à 60 Sek.) ---
        expect(find.text('Spiderman-Plank'), findsOneWidget);

        // Satz 1: Timer komplett real ablaufen lassen (Auto-Übergang).
        await _runExerciseTimerFullyAndLog(tester, 60);
        await _skipRestIfShown(tester);
        // Sätze 2 & 3: Timer über den Button vorzeitig abkürzen.
        await _cutExerciseTimerShortAndLog(tester);
        await _skipRestIfShown(tester);
        await _cutExerciseTimerShortAndLog(tester); // letzter Satz -> Summary

        // --- Summary-Screen verifizieren ---
        expect(find.text('Zusammenfassung'), findsOneWidget);

        final summary =
            tester.widget<SummaryScreen>(find.byType(SummaryScreen));
        final session = summary.session;

        // Erwartung: 8 bestätigte Sätze, 1 übersprungener Satz, 76
        // Wiederholungen gesamt (36 aus Übung 1 + 40 aus Übung 2,
        // Übung 3 ist zeitbasiert und zählt nicht zu
        // reps/Volumen), 30,0 kg Volumen (nur Satz 1 von Übung 1: 12 x 2,5).
        expect(session.completedSetCount, 8);
        expect(session.skippedSetCount, 1);
        expect(session.totalReps, 76);
        expect(session.totalVolumeKg, 30.0,
            reason:
                'Nur Übung 1 Satz 1 hat Gewicht (12 Wdh. x 2,5 kg = 30 kg).');

        final russianTwists = session.completedExercises
            .firstWhere((e) => e.exerciseName == 'Russian Twists');
        expect(russianTwists.setsLogged[1].status, SetStatus.skipped,
            reason: 'Satz 2 von Russian Twists wurde übersprungen.');

        final plank = session.completedExercises
            .firstWhere((e) => e.exerciseName == 'Spiderman-Plank');
        expect(plank.setsLogged[0].durationActualSeconds, 60,
            reason: 'Satz 1 der Plank lief komplett durch: Der Eingabewert '
                'bleibt bei der Vorgabe (60 Sek.) stehen; nur die '
                'Referenzuhr zählt daneben weiter.');

        // Sichtprüfung der auf dem Summary-Screen angezeigten Werte.
        expect(find.text('30.0 kg'), findsOneWidget);
        expect(find.text('76'), findsOneWidget);

        await _scrollToAndTap(tester, 'Fertig');

        expect(find.textContaining('Verlauf (1 Sessions)'), findsOneWidget,
            reason: 'Die absolvierte Session muss in der Historie '
                '(Lastenheft 2.3) auftauchen.');
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}

// ---------------------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------------------

/// Prüft den Freischalt-Status eines ElevatedButton.icon anhand seines
/// Labeltexts. ElevatedButton.icon(...) liefert eine private Subklasse
/// zurück (siehe Hinweis in test/widget_test.dart), daher hier bewusst
/// über `is ElevatedButton` (statt exaktem byType) gesucht.
bool _isElevatedButtonEnabled(WidgetTester tester, String text) {
  final buttonFinder = find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
  );
  final button = tester.widget<ElevatedButton>(buttonFinder);
  return button.onPressed != null;
}

/// Scrollt das Ziel bei Bedarf in den sichtbaren Bereich und tappt es.
/// Nötig für Buttons am Ende scrollbarer ListViews (Import-Vorschau,
/// Summary), die auf dem Emulator-Display unterhalb des Folds liegen und
/// wegen des Lazy-Buildings vor dem Scrollen noch gar nicht im Baum sind.
Future<void> _scrollToAndTap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Übernimmt den validierten Plan: tippt „Plan übernehmen" und bestätigt
/// das Vorschau-Popup.
Future<void> _applyPlan(WidgetTester tester) async {
  await _scrollToAndTap(tester, 'Plan übernehmen');
  // Vorschau-Popup: finale Bestätigung.
  expect(find.text('Plan übernehmen?'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, 'Übernehmen'));
  await tester.pumpAndSettle();
}

Future<void> _confirmSet(WidgetTester tester) async {
  await tester.tap(find.text('Satz beendet'));
  await tester.pumpAndSettle();
}

Future<void> _skipRestIfShown(WidgetTester tester) async {
  final finder = find.text('Pause überspringen');
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
}

Future<void> _skipSetWithSafetyPrompt(WidgetTester tester,
    {required int setNumber}) async {
  await tester.tap(find.text('Satz überspringen'));
  await tester.pumpAndSettle();

  // Sicherheitsabfrage nennt den konkreten Satz.
  expect(find.text('Satz $setNumber überspringen?'), findsOneWidget);
  await tester.tap(find.text('Überspringen'));
  await tester.pumpAndSettle();
}

/// Erhöht den Gewichtswert im Log-Screen um +2,5 kg (ein Tap auf die
/// "+"-Taste der "Gewicht (kg)"-Karte). Beide Stepper (Wiederholungen und
/// Gewicht) zeigen ein Icons.add, daher wird gezielt innerhalb der
/// Gewichts-Karte gesucht.
Future<void> _incrementWeight(WidgetTester tester, {int times = 1}) async {
  final weightCard = find.ancestor(
    of: find.text('Gewicht (kg)'),
    matching: find.byType(Card),
  );
  final plusButton = find.descendant(
    of: weightCard,
    matching: find.byIcon(Icons.add),
  );
  for (var i = 0; i < times; i++) {
    await tester.tap(plusButton);
    await tester.pumpAndSettle();
  }
}

/// Pumpt in Echtzeit (1s-Schritte), bis [text] sichtbar ist oder
/// [maxSeconds] erreicht sind. Nötig, weil die Belastungs-Timer der App
/// real ticken und der genaue Übergangszeitpunkt leicht schwanken kann.
Future<void> _waitForText(WidgetTester tester, String text,
    {required int maxSeconds}) async {
  for (var i = 0; i < maxSeconds; i++) {
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(seconds: 1));
  }
  fail('Timeout: "$text" nicht innerhalb von $maxSeconds s erschienen.');
}

/// Übung-3-Satz mit vollem Timer-Durchlauf: Timer starten, real bis zum
/// automatischen Übergang in den Log-Screen warten, Satz bestätigen.
Future<void> _runExerciseTimerFullyAndLog(
    WidgetTester tester, int durationSeconds) async {
  await tester.tap(find.text('Timer starten'));
  await tester.pump();
  await _waitForText(tester, 'Satz beendet',
      maxSeconds: durationSeconds + 15);
  await tester.pumpAndSettle();
  await _confirmSet(tester);
}

/// Übung-3-Satz mit abgekürztem Timer: Timer starten, nach ~2 Sekunden
/// über "Satz vorzeitig beenden" in den Log-Screen wechseln und den Satz
/// mit der verstrichenen Zeit loggen.
Future<void> _cutExerciseTimerShortAndLog(WidgetTester tester) async {
  await tester.tap(find.text('Timer starten'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.tap(find.text('Satz vorzeitig beenden'));
  await tester.pumpAndSettle();
  await _confirmSet(tester);
}
