import 'package:flexiplan/models/workout_plan.dart';
import 'package:flexiplan/screens/workout_screen.dart';
import 'package:flexiplan/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifiziert die Referenzuhr nach regulärem Timer-Ablauf: Der
/// Eingabewert bleibt stabil bei der Vorgabe, eine separate kleine Uhr
/// führt den Timerstand weiter, bis der Satz beendet wird.
///
/// Wichtig: Während die Referenzuhr läuft, niemals pumpAndSettle
/// verwenden (der periodische Timer erzeugt in der Fake-Zeit endlos
/// neue Frames) – stattdessen gezielt pump(1s)-Schritte.
void main() {
  WorkoutPlan buildTimePlan() => WorkoutPlan.fromJson(<String, dynamic>{
        'workout_title': 'Timer-Test',
        'exercises': [
          {
            'id': 1,
            'name': 'Mini-Plank',
            'type': 'time',
            'sets': 1,
            'duration_seconds': 5,
            'rest_duration_seconds': 0,
          }
        ],
      });

  testWidgets(
      'Referenzuhr zählt nach Timer-Ablauf weiter, Eingabewert bleibt '
      'bei der Vorgabe stehen', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(MaterialApp(
      home: WorkoutScreen(plan: buildTimePlan(), storage: StorageService()),
    ));
    await tester.pump(); // Sound-Einstellung asynchron geladen.

    await tester.tap(find.text('Timer starten'));
    await tester.pump();

    // Timer regulär ablaufen lassen (5 Sekunden).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Satz beendet'), findsOneWidget,
        reason: 'Nach Ablauf wechselt der Screen automatisch zum Loggen.');
    expect(find.text('5'), findsOneWidget,
        reason: 'Eingabewert steht auf der Vorgabe (5 Sekunden).');
    expect(find.text('Läuft weiter: 5 Sek.'), findsOneWidget,
        reason: 'Die Referenzuhr startet beim Timerstand.');

    // Referenzuhr zählt weiter – der Eingabewert bleibt unangetastet.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Läuft weiter: 8 Sek.'), findsOneWidget);
    expect(find.text('5'), findsOneWidget,
        reason: 'Der Eingabewert darf sich nicht von selbst verändern.');

    // Manueller Eingriff verändert nur den Eingabewert; die Referenzuhr
    // läuft davon unabhängig weiter.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Läuft weiter: 10 Sek.'), findsOneWidget);
    expect(find.text('10'), findsNWidgets(1),
        reason: 'Eingabewert bleibt bei 10, nur die Uhr tickt.');

    // Beenden loggt den Eingabewert; die Uhr verschwindet.
    await tester.tap(find.text('Satz beendet'));
    await tester.pumpAndSettle();
    expect(find.text('Zusammenfassung'), findsOneWidget);
    expect(find.text('Satz 1: 10 Sek.'), findsOneWidget);
  });

  testWidgets('"Satz vorzeitig beenden" zeigt keine Referenzuhr',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(MaterialApp(
      home: WorkoutScreen(plan: buildTimePlan(), storage: StorageService()),
    ));
    await tester.pump();

    await tester.tap(find.text('Timer starten'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Satz vorzeitig beenden'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget,
        reason: 'Verstrichene Zeit (2 Sek.) wird übernommen.');
    expect(find.textContaining('Läuft weiter'), findsNothing,
        reason: 'Beim manuellen Stop ist der Wert exakt – keine Uhr.');

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('2'), findsOneWidget);
  });
}
