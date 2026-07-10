import 'dart:convert';

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

  group('Progression: loadLastPerformances', () {
    test('liefert den letzten abgeschlossenen Satz der neuesten Session '
        'und ignoriert übersprungene Sätze', () async {
      final storage = StorageService();
      // Ältere Session (buildSession: 2026-07-05, letzter completed Satz
      // = 10 Wdh. à 20 kg, danach ein skipped Satz).
      await storage.addSession(buildSession());
      // Neuere Session mit besserer Leistung.
      await storage.addSession(WorkoutSession(
        dataVersion: StorageService.currentDataVersion,
        sessionId: 'neuere-session',
        date: DateTime.utc(2026, 7, 6, 18),
        workoutTitle: 'Ganzkörper Heimtraining',
        durationMinutes: 40,
        completedExercises: const [
          CompletedExercise(
            exerciseName: 'Liegestütze',
            setsLogged: [
              SetLog(
                  setNumber: 1,
                  status: SetStatus.completed,
                  repsActual: 14,
                  weightActualKg: 22.5),
              SetLog(
                  setNumber: 2,
                  status: SetStatus.skipped,
                  repsActual: 0,
                  weightActualKg: 0),
            ],
          ),
        ],
      ));

      final result =
          await storage.loadLastPerformances({'Liegestütze', 'Unbekannt'});
      expect(result.containsKey('Unbekannt'), isFalse);
      final last = result['Liegestütze']!;
      expect(last.log.repsActual, 14);
      expect(last.log.weightActualKg, 22.5);
      expect(last.date, DateTime.utc(2026, 7, 6, 18));
    });
  });

  group('Workout-Entwurf (App-Kill-Schutz)', () {
    test('Draft speichern, laden und löschen', () async {
      final storage = StorageService();
      expect(await storage.loadWorkoutDraft(), isNull);

      await storage.saveWorkoutDraft(<String, dynamic>{
        'start_time': '2026-07-06T10:00:00.000',
        'exercise_index': 1,
        'set_number': 2,
        'logs': [
          [buildSession().completedExercises.single.setsLogged.first.toJson()],
          <Map<String, dynamic>>[],
        ],
      });

      final draft = await storage.loadWorkoutDraft();
      expect(draft, isNotNull);
      expect(draft!['exercise_index'], 1);
      expect(draft['set_number'], 2);

      await storage.clearWorkoutDraft();
      expect(await storage.loadWorkoutDraft(), isNull);
    });
  });

  group('Plan-Bibliothek', () {
    test('addPlan speichert und wählt aus, loadSelectedPlan liefert ihn',
        () async {
      final storage = StorageService();
      final plan = PlanParser.parse(validPlanJson);
      final stored = await storage.addPlan(plan);

      expect(stored.id, isNotEmpty);
      final plans = await storage.loadPlans();
      expect(plans.length, 1);

      final selected = await storage.loadSelectedPlan();
      expect(selected!.id, stored.id);
      expect(selected.plan.workoutTitle, plan.workoutTitle);
      expect(selected.plan.exercises.length, 2);
    });

    test('mehrere Pläne: zuletzt importierter ist ausgewählt, '
        'selectPlan wechselt', () async {
      final storage = StorageService();
      final plan = PlanParser.parse(validPlanJson);
      final first = await storage.addPlan(plan);
      final second = await storage.addPlan(plan);

      expect((await storage.loadSelectedPlan())!.id, second.id);
      await storage.selectPlan(first.id);
      expect((await storage.loadSelectedPlan())!.id, first.id);
    });

    test('deletePlan entfernt nur den Plan; Auswahl fällt zurück und '
        'Historie bleibt unberührt', () async {
      final storage = StorageService();
      await storage.addSession(buildSession());
      final plan = PlanParser.parse(validPlanJson);
      final first = await storage.addPlan(plan);
      final second = await storage.addPlan(plan);

      await storage.deletePlan(second.id);

      final plans = await storage.loadPlans();
      expect(plans.single.id, first.id);
      expect((await storage.loadSelectedPlan())!.id, first.id);
      // Historie unangetastet (Kernanforderung).
      expect((await storage.loadSessions()).length, 1);

      await storage.deletePlan(first.id);
      expect(await storage.loadPlans(), isEmpty);
      expect(await storage.loadSelectedPlan(), isNull);
    });

    test('Migration: alter Single-Plan-Key wird verlustfrei in die '
        'Bibliothek überführt', () async {
      // Alt-Zustand einer 0.2.x-Installation nachstellen.
      final plan = PlanParser.parse(validPlanJson);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.flexiplan_active_plan': jsonEncode(plan.toJson()),
      });

      final storage = StorageService();
      final plans = await storage.loadPlans();
      expect(plans.length, 1);
      expect(plans.single.plan.workoutTitle, plan.workoutTitle);
      final selected = await storage.loadSelectedPlan();
      expect(selected!.id, plans.single.id);

      // Alt-Key ist weg, erneutes Laden dupliziert nichts.
      expect((await storage.loadPlans()).length, 1);
    });
  });
}
