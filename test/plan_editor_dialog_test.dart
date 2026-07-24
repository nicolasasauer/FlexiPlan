import 'package:flexiplan/models/workout_plan.dart';
import 'package:flexiplan/screens/plan_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkoutPlan _samplePlan() => const WorkoutPlan(
      workoutTitle: 'Testplan',
      version: '1.0',
      description: 'Beschreibung',
      exercises: [
        Exercise(
          id: 1,
          name: 'Kniebeugen',
          description: 'Alte Beschreibung',
          type: ExerciseType.reps,
          sets: 3,
          reps: 10,
          weightKg: 20,
          bodyweight: false,
          durationSeconds: 0,
          restDurationSeconds: 60,
        ),
        Exercise(
          id: 2,
          name: 'Plank',
          description: 'Halten',
          type: ExerciseType.time,
          sets: 3,
          reps: 0,
          weightKg: 0,
          bodyweight: false,
          durationSeconds: 30,
          restDurationSeconds: 45,
        ),
      ],
    );

Future<WorkoutPlan?> _openDialog(
    WidgetTester tester, WorkoutPlan plan) async {
  WorkoutPlan? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showPlanEditorDialog(context, plan);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('zeigt bestehende Werte vorausgefüllt an', (tester) async {
    await _openDialog(tester, _samplePlan());

    expect(find.widgetWithText(TextField, 'Kniebeugen'), findsOneWidget);
    expect(find.text('Alte Beschreibung'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Plank'), findsOneWidget);
    // Zeit-Übung zeigt "Dauer (Sek.)" statt "Wdh."/"Gewicht (kg)".
    expect(find.text('Dauer (Sek.)'), findsOneWidget);
  });

  testWidgets('Speichern gibt den geänderten Plan zurück', (tester) async {
    WorkoutPlan? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showPlanEditorDialog(context, _samplePlan());
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final nameField = find.widgetWithText(TextField, 'Kniebeugen');
    await tester.enterText(nameField, 'Kniebeugen (schwer)');
    await tester.pumpAndSettle();

    final repsField = find.ancestor(
      of: find.text('Wdh.'),
      matching: find.byType(TextField),
    );
    await tester.enterText(repsField, '12');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    final edited = result!.exercises.first;
    expect(edited.name, 'Kniebeugen (schwer)');
    expect(edited.reps, 12);
    // Unveränderte Felder bleiben erhalten.
    expect(edited.sets, 3);
    expect(edited.weightKg, 20);
    expect(result!.exercises.last.durationSeconds, 30);
  });

  testWidgets('Speichern-Button ist bei ungültiger Eingabe deaktiviert',
      (tester) async {
    await _openDialog(tester, _samplePlan());

    final nameField = find.widgetWithText(TextField, 'Kniebeugen');
    await tester.enterText(nameField, '');
    await tester.pumpAndSettle();

    final saveButton =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Speichern'));
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('Abbrechen gibt null zurück', (tester) async {
    WorkoutPlan? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showPlanEditorDialog(context, _samplePlan());
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
