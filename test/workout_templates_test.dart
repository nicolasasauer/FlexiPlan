import 'dart:io';

import 'package:flexiplan/services/plan_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stellt sicher, dass alle im Repository mitgelieferten Workout-Vorlagen
/// dauerhaft dem Import-Schema entsprechen. Schlägt eine
/// Vorlage fehl, listet der Test das vollständige Fehlerprotokoll auf.
void main() {
  final templateFiles = <File>[
    File('beispiel_trainingsplan.json'),
    ...Directory('workouts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json')),
  ];

  test('Vorlagen-Verzeichnis enthält Workouts', () {
    expect(templateFiles.length, greaterThanOrEqualTo(8),
        reason: 'Erwartet: beispiel_trainingsplan.json und mindestens '
            '7 Vorlagen unter workouts/.');
  });

  for (final file in templateFiles) {
    test('${file.path} ist ein gültiger FlexiPlan-Trainingsplan', () {
      final plan = PlanParser.parse(file.readAsStringSync());
      expect(plan.workoutTitle, isNotEmpty);
      expect(plan.exercises, isNotEmpty);
      // Jede Übung braucht eine Beschreibung, damit die Vorlagen auch als
      // Anleitung taugen (strenger als das Schema selbst).
      for (final ex in plan.exercises) {
        expect(ex.description.trim(), isNotEmpty,
            reason: '${file.path}: Übung "${ex.name}" ohne Beschreibung.');
      }
    });
  }
}
