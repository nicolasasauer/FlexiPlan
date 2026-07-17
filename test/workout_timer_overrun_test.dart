import 'package:flexiplan/models/workout_plan.dart';
import 'package:flexiplan/screens/workout_screen.dart';
import 'package:flexiplan/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifiziert das Overrun-Verhalten des Belastungs-Timers: Nach dem
/// regulären Ablauf zählt der Ist-Wert automatisch weiter, bis der Satz
/// beendet oder der Wert manuell angepasst wird.
///
/// Wichtig: Während der Overrun-Zähler läuft, niemals pumpAndSettle
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
      'Ist-Wert zählt nach Timer-Ablauf weiter, stoppt bei manuellem '
      'Eingriff und friert beim Beenden ein', (tester) async {
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
        reason: 'Ist-Wert startet bei der Vorgabe (5 Sekunden).');

    // Overrun: Wert zählt sekündlich weiter.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('8'), findsOneWidget,
        reason: 'Drei Sekunden nach Ablauf muss der Ist-Wert 8 zeigen.');

    // Manueller Eingriff stoppt das automatische Weiterzählen.
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('3'), findsOneWidget,
        reason: 'Nach manuellem -5 darf nichts mehr automatisch ticken.');

    // Beenden friert den Wert ein und loggt ihn.
    await tester.tap(find.text('Satz beendet'));
    await tester.pumpAndSettle();
    expect(find.text('Zusammenfassung'), findsOneWidget);
    expect(find.text('Satz 1: 3 Sek.'), findsOneWidget);
  });

  testWidgets('"Satz vorzeitig beenden" startet keinen Overrun-Zähler',
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

    // Kein automatisches Weiterzählen nach manuellem Stop.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('2'), findsOneWidget);
  });
}
