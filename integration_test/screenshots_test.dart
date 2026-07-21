// Erzeugt die Play-Store-Screenshots automatisiert auf dem Emulator
// (Ausführung siehe test_driver/integration_test.dart). Fährt die App
// einmal durch alle Kern-Screens: Import mit Vorschau, Home mit aktivem
// Plan, Workout-Log, Satzpause, Zusammenfassung, Verlauf.
import 'package:flexiplan/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _demoPlanJson = '''
{
  "workout_title": "V-Cut Core Finisher",
  "version": "1.0",
  "description": "Gezieltes Zusatztraining für den unteren Bauch und die schrägen Bauchmuskeln.",
  "exercises": [
    {
      "id": 1,
      "name": "Hängendes Beinheben",
      "description": "An der Klimmzugstange hängen. Beine kontrolliert nach oben ziehen, Becken oben einrollen. Kein Schwung.",
      "type": "reps",
      "sets": 3,
      "reps": 12,
      "weight_kg": 0,
      "rest_duration_seconds": 60
    },
    {
      "id": 2,
      "name": "Russian Twists",
      "description": "Oberkörper leicht zurücklehnen, Beine anwinkeln, kontrolliert mit Gewicht von links nach rechts drehen.",
      "type": "reps",
      "sets": 3,
      "reps": 20,
      "weight_kg": 5,
      "rest_duration_seconds": 60
    },
    {
      "id": 3,
      "name": "Spiderman-Plank",
      "description": "Im Unterarmstütz abwechselnd das Knie zum gleichseitigen Ellenbogen ziehen.",
      "type": "time",
      "sets": 2,
      "duration_seconds": 45,
      "rest_duration_seconds": 45
    }
  ]
}
''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Store-Screenshots aufnehmen', (tester) async {
    await binding.convertFlutterSurfaceToImage();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    Future<void> tapText(String text) async {
      await tester.scrollUntilVisible(
        find.text(text),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const FlexiPlanApp());
    await tester.pumpAndSettle();

    // --- Import mit Live-Validierung ---
    await tapText('Trainingsplan importieren');
    await tester.enterText(find.byType(TextField), _demoPlanJson);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await shot('02_import_vorschau');

    // "Plan übernehmen" → Vorschau-Popup bestätigen.
    await tapText('Plan übernehmen');
    await tester.tap(find.widgetWithText(TextButton, 'Übernehmen'));
    await tester.pumpAndSettle();

    // --- Home mit aktivem Plan ---
    await shot('01_home');

    // --- Workout: Log-Screen der ersten Übung ---
    await tapText('Workout starten');
    await shot('03_workout_satz');

    // Satz 1 beenden -> Satzpause mit "Als Nächstes"-Vorschau.
    await tester.tap(find.text('Satz beendet'));
    await tester.pumpAndSettle();
    await shot('04_satzpause');
    await tester.tap(find.text('Pause überspringen'));
    await tester.pumpAndSettle();

    // Restliche Sätze zügig durcharbeiten.
    Future<void> confirmAndSkipRest() async {
      await tester.tap(find.text('Satz beendet'));
      await tester.pumpAndSettle();
      final rest = find.text('Pause überspringen');
      if (rest.evaluate().isNotEmpty) {
        await tester.tap(rest);
        await tester.pumpAndSettle();
      }
    }

    // Übung 1: Sätze 2-3, Übung 2: Sätze 1-3.
    for (var i = 0; i < 5; i++) {
      await confirmAndSkipRest();
    }

    // Übung 3 (zeitbasiert, 2 Sätze): Timer kurz laufen lassen und
    // vorzeitig beenden.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Timer starten'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Satz vorzeitig beenden'));
      await tester.pumpAndSettle();
      await confirmAndSkipRest();
    }

    // --- Zusammenfassung ---
    expect(find.text('Zusammenfassung'), findsOneWidget);
    await shot('05_zusammenfassung');

    await tapText('Fertig');

    // --- Verlauf ---
    await tapText('Verlauf (1 Sessions)');
    await shot('06_verlauf');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
