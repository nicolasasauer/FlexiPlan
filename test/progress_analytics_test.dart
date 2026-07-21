import 'package:flexiplan/models/workout_session.dart';
import 'package:flexiplan/services/progress_analytics.dart';
import 'package:flexiplan/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Baut eine Session an [date] mit einer Übung und den gegebenen Sätzen.
WorkoutSession session(
  String id,
  DateTime date,
  String exercise,
  List<SetLog> sets,
) =>
    WorkoutSession(
      dataVersion: StorageService.currentDataVersion,
      sessionId: id,
      date: date,
      workoutTitle: 'Test',
      durationMinutes: 30,
      completedExercises: [
        CompletedExercise(exerciseName: exercise, setsLogged: sets),
      ],
    );

SetLog reps(int n, double kg) => SetLog(
      setNumber: 1,
      status: SetStatus.completed,
      repsActual: n,
      weightActualKg: kg,
    );

SetLog time(int seconds) => SetLog(
      setNumber: 1,
      status: SetStatus.completed,
      repsActual: 0,
      weightActualKg: 0,
      durationActualSeconds: seconds,
    );

void main() {
  // Sessions kommen aus dem Storage neueste-zuerst; die Testdaten
  // spiegeln das wider.
  final now = DateTime(2026, 7, 15, 12); // Mittwoch

  group('Übungs-Zeitreihen', () {
    test('sammelt alle Sessions chronologisch (älteste zuerst)', () {
      final sessions = [
        session('c', DateTime(2026, 7, 13), 'Bankdrücken', [reps(8, 25)]),
        session('b', DateTime(2026, 7, 10), 'Bankdrücken', [reps(10, 22.5)]),
        session('a', DateTime(2026, 7, 6), 'Bankdrücken', [reps(10, 20)]),
      ];
      final data = computeProgress(sessions, now: now);
      final ex = data.exercises.single;
      expect(ex.sessionCount, 3);
      expect(ex.metric, ProgressMetric.weight);
      expect(ex.values, [20.0, 22.5, 25.0]); // älteste → neueste
      expect(ex.delta, '+5.0 kg');
    });

    test('wählt Wiederholungen als Kennzahl bei reinem Eigengewicht', () {
      final sessions = [
        session('b', DateTime(2026, 7, 12), 'Liegestütze', [reps(15, 0)]),
        session('a', DateTime(2026, 7, 8), 'Liegestütze', [reps(12, 0)]),
      ];
      final ex = computeProgress(sessions, now: now).exercises.single;
      expect(ex.metric, ProgressMetric.reps);
      expect(ex.values, [12.0, 15.0]);
      expect(ex.delta, '+3 Wdh.');
    });

    test('wählt Dauer als Kennzahl bei zeitbasierten Übungen', () {
      final sessions = [
        session('b', DateTime(2026, 7, 12), 'Plank', [time(75)]),
        session('a', DateTime(2026, 7, 8), 'Plank', [time(60)]),
      ];
      final ex = computeProgress(sessions, now: now).exercises.single;
      expect(ex.metric, ProgressMetric.duration);
      expect(ex.values, [60.0, 75.0]);
      expect(ex.delta, '+15 Sek.');
    });
  });

  group('Kacheln', () {
    test('Rekorde und Zählwerte', () {
      final sessions = [
        session('b', DateTime(2026, 7, 14), 'Kniebeuge', [reps(5, 40), time(90)]),
        session('a', DateTime(2026, 7, 6), 'Plank', [time(60)]),
      ];
      final tiles = computeProgress(sessions, now: now).tiles;
      String value(String label) =>
          tiles.firstWhere((t) => t.label == label).value;

      expect(value('SESSIONS GESAMT'), '2');
      expect(value('SCHWERSTER SATZ'), '40 kg');
      expect(value('LÄNGSTE ZEIT'), '90 Sek.');
      // Nur die ersten vier Kacheln mit Daten.
      expect(tiles.length, 4);
    });

    test('Wochenziel aus Erinnerung: erreicht wird hervorgehoben', () {
      final sessions = [
        // Diese Woche (Mo 13. – So 19.): zwei Sessions.
        session('b', DateTime(2026, 7, 15), 'X', [reps(10, 0)]),
        session('a', DateTime(2026, 7, 14), 'X', [reps(10, 0)]),
      ];
      final tiles =
          computeProgress(sessions, now: now, weeklyGoal: 2).tiles;
      final week = tiles.firstWhere((t) => t.label == 'DIESE WOCHE');
      expect(week.value, '2 / 2');
      expect(week.highlightSub, isTrue);
    });

    test('ohne Wochenziel nur die reine Anzahl', () {
      final sessions = [
        session('a', DateTime(2026, 7, 15), 'X', [reps(10, 0)]),
      ];
      final week = computeProgress(sessions, now: now)
          .tiles
          .firstWhere((t) => t.label == 'DIESE WOCHE');
      expect(week.value, '1');
      expect(week.highlightSub, isFalse);
    });
  });

  group('Heatmap & Streak', () {
    test('zählt abgeschlossene Sätze je Tag, ignoriert skipped', () {
      const skipped = SetLog(
          setNumber: 2,
          status: SetStatus.skipped,
          repsActual: 0,
          weightActualKg: 0);
      final sessions = [
        session('a', DateTime(2026, 7, 14), 'X', [reps(10, 0), reps(9, 0), skipped]),
      ];
      final data = computeProgress(sessions, now: now);
      expect(data.setsPerDay[DateTime(2026, 7, 14)], 2);
    });

    test('Streak zählt aufeinanderfolgende Wochen rückwärts', () {
      final sessions = [
        session('c', DateTime(2026, 7, 15), 'X', [reps(1, 0)]), // KW aktuell
        session('b', DateTime(2026, 7, 8), 'X', [reps(1, 0)]), // Vorwoche
        // Lücke KW 27 (29.6.–5.7.) fehlt bewusst
        session('a', DateTime(2026, 6, 24), 'X', [reps(1, 0)]),
      ];
      expect(computeProgress(sessions, now: now).weekStreak, 2);
    });

    test('Streak 0, wenn die aktuelle Woche leer ist', () {
      final sessions = [
        session('a', DateTime(2026, 7, 6), 'X', [reps(1, 0)]), // Vorwoche
      ];
      expect(computeProgress(sessions, now: now).weekStreak, 0);
    });
  });
}
