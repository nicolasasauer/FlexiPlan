import 'package:flexiplan/models/workout_plan.dart';
import 'package:flexiplan/services/plan_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const String validPlanJson = '''
{
  "workout_title": "Ganzkörper Heimtraining",
  "version": "1.0",
  "description": "Effektives Training ohne schwere Geräte.",
  "exercises": [
    {
      "id": 1,
      "name": "Liegestütze",
      "description": "Gerade Plankenposition.",
      "type": "reps",
      "sets": 3,
      "reps": 12,
      "weight_kg": 0,
      "rest_duration_seconds": 60
    },
    {
      "id": 2,
      "name": "Plank (Unterarmstütz)",
      "description": "Kein Hohlkreuz bilden.",
      "type": "time",
      "sets": 2,
      "duration_seconds": 45,
      "rest_duration_seconds": 45
    }
  ]
}
''';

void main() {
  group('PlanParser – gültige Eingaben', () {
    test('parst das Beispiel aus dem Lastenheft korrekt', () {
      final plan = PlanParser.parse(validPlanJson);
      expect(plan.workoutTitle, 'Ganzkörper Heimtraining');
      expect(plan.exercises.length, 2);
      expect(plan.totalSets, 5);

      final pushups = plan.exercises[0];
      expect(pushups.type, ExerciseType.reps);
      expect(pushups.reps, 12);
      expect(pushups.weightKg, 0);
      expect(pushups.restDurationSeconds, 60);

      final plank = plan.exercises[1];
      expect(plank.type, ExerciseType.time);
      expect(plank.durationSeconds, 45);
    });

    test('Plan überlebt toJson/fromJson-Roundtrip', () {
      final plan = PlanParser.parse(validPlanJson);
      final restored = WorkoutPlan.fromJson(plan.toJson());
      expect(restored.workoutTitle, plan.workoutTitle);
      expect(restored.exercises.length, plan.exercises.length);
      expect(restored.exercises[1].durationSeconds, 45);
    });
  });

  group('PlanParser – Fehlerprotokoll', () {
    test('leere Eingabe wird abgelehnt', () {
      expect(() => PlanParser.parse('   '),
          throwsA(isA<PlanValidationException>()));
    });

    test('kaputtes JSON wird abgelehnt', () {
      expect(() => PlanParser.parse('{ "workout_title": '),
          throwsA(isA<PlanValidationException>()));
    });

    test('fehlender Titel und fehlende Übungen werden gemeldet', () {
      try {
        PlanParser.parse('{}');
        fail('Exception erwartet');
      } on PlanValidationException catch (e) {
        expect(e.errors.any((m) => m.contains('workout_title')), isTrue);
        expect(e.errors.any((m) => m.contains('exercises')), isTrue);
      }
    });

    test('unbekannter Übungstyp wird gemeldet', () {
      const json = '''
      {
        "workout_title": "Test",
        "exercises": [
          {"id": 1, "name": "X", "type": "cardio", "sets": 1,
           "rest_duration_seconds": 30}
        ]
      }
      ''';
      try {
        PlanParser.parse(json);
        fail('Exception erwartet');
      } on PlanValidationException catch (e) {
        expect(e.errors.single, contains('"type"'));
      }
    });

    test('type "time" ohne duration_seconds wird gemeldet', () {
      const json = '''
      {
        "workout_title": "Test",
        "exercises": [
          {"id": 1, "name": "Plank", "type": "time", "sets": 2,
           "rest_duration_seconds": 30}
        ]
      }
      ''';
      try {
        PlanParser.parse(json);
        fail('Exception erwartet');
      } on PlanValidationException catch (e) {
        expect(
            e.errors.any((m) => m.contains('duration_seconds')), isTrue);
      }
    });

    test('bodyweight: true wird geparst, Gewicht bleibt 0', () {
      const json = '''
      {
        "workout_title": "Test",
        "exercises": [
          {"id": 1, "name": "Liegestütze", "type": "reps", "sets": 3,
           "reps": 10, "bodyweight": true, "rest_duration_seconds": 30}
        ]
      }
      ''';
      final plan = PlanParser.parse(json);
      expect(plan.exercises.single.bodyweight, isTrue);
      expect(plan.exercises.single.weightKg, 0);
      // Roundtrip erhält das Flag.
      final restored = WorkoutPlan.fromJson(plan.toJson());
      expect(restored.exercises.single.bodyweight, isTrue);
    });

    test('altes Schema ohne bodyweight bleibt gültig (Rückwärtskompat.)', () {
      final plan = PlanParser.parse(validPlanJson);
      expect(plan.exercises.first.bodyweight, isFalse);
    });

    test('bodyweight mit falschem Typ wird gemeldet', () {
      const json = '''
      {
        "workout_title": "Test",
        "exercises": [
          {"id": 1, "name": "X", "type": "reps", "sets": 1, "reps": 1,
           "bodyweight": "ja", "rest_duration_seconds": 30}
        ]
      }
      ''';
      try {
        PlanParser.parse(json);
        fail('Exception erwartet');
      } on PlanValidationException catch (e) {
        expect(e.errors.single, contains('"bodyweight"'));
      }
    });

    test('type "reps" ohne reps wird gemeldet', () {
      const json = '''
      {
        "workout_title": "Test",
        "exercises": [
          {"id": 1, "name": "Squats", "type": "reps", "sets": 3,
           "rest_duration_seconds": 30}
        ]
      }
      ''';
      try {
        PlanParser.parse(json);
        fail('Exception erwartet');
      } on PlanValidationException catch (e) {
        expect(e.errors.any((m) => m.contains('"reps"')), isTrue);
      }
    });
  });
}
