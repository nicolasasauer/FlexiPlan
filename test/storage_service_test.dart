import 'package:flexiplan/models/workout_session.dart';
import 'package:flexiplan/services/plan_parser.dart';
import 'package:flexiplan/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plan_parser_test.dart' show validPlanJson;

WorkoutSession buildSession() => WorkoutSession(
      dataVersion: StorageService.currentDataVersion,
      sessionId: '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
      date: DateTime.utc(2026, 7, 5, 15, 30),
      workoutTitle: 'Ganzkörper Heimtraining',
      durationMinutes: 45,
      completedExercises: const [
        CompletedExercise(
          exerciseName: 'Liegestütze',
          setsLogged: [
            SetLog(
                setNumber: 1,
                status: SetStatus.completed,
                repsActual: 12,
                weightActualKg: 0),
            SetLog(
                setNumber: 2,
                status: SetStatus.completed,
                repsActual: 10,
                weightActualKg: 20),
            SetLog(
                setNumber: 3,
                status: SetStatus.skipped,
                repsActual: 0,
                weightActualKg: 0),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Session-Roundtrip: speichern und wieder laden', () async {
    final storage = StorageService();
    await storage.addSession(buildSession());

    final loaded = await storage.loadSessions();
    expect(loaded.length, 1);

    final session = loaded.single;
    expect(session.sessionId, '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d');
    expect(session.completedSetCount, 2);
    expect(session.skippedSetCount, 1);
    expect(session.totalReps, 22);
    expect(session.totalVolumeKg, 200.0);
    expect(session.completedExercises.single.setsLogged[2].status,
        SetStatus.skipped);
  });

  test('Export-JSON entspricht dem Schema aus Lastenheft 4.2', () {
    final json = buildSession().toJson();
    expect(json['data_version'], 1);
    expect(json['session_id'], isNotEmpty);
    expect(json['date'], '2026-07-05T15:30:00.000Z');
    expect(json['workout_title'], 'Ganzkörper Heimtraining');
    expect(json['duration_minutes'], 45);
    final exercises = json['completed_exercises'] as List<dynamic>;
    final sets = (exercises.first
        as Map<String, dynamic>)['sets_logged'] as List<dynamic>;
    final firstSet = sets.first as Map<String, dynamic>;
    expect(firstSet.keys,
        containsAll(['set_number', 'status', 'reps_actual',
          'weight_actual_kg']));
  });

  test('Migration: Session ohne data_version erhält Version 1', () {
    final storage = StorageService();
    final legacy = buildSession().toJson()..remove('data_version');
    final migrated = storage.migrateSession(legacy);
    expect(migrated['data_version'], 1);
    // Verlustfrei: alle übrigen Felder unverändert.
    expect(migrated['workout_title'], legacy['workout_title']);
  });

  test('Aktiver Plan: speichern und laden', () async {
    final storage = StorageService();
    final plan = PlanParser.parse(validPlanJson);
    await storage.saveActivePlan(plan);

    final loaded = await storage.loadActivePlan();
    expect(loaded, isNotNull);
    expect(loaded!.workoutTitle, plan.workoutTitle);
    expect(loaded.exercises.length, 2);
  });
}
