/// Aggregiert die Trainingshistorie für die Fortschritts-Visualisierung
/// (Fortschritts-Screen V2). Bewusst reine Funktionen ohne Flutter-/
/// Storage-Abhängigkeit, damit die Logik ohne Widgets testbar bleibt.
///
/// Alle Kennzahlen leiten sich allein aus den vorhandenen Sessions ab –
/// keine neuen Storage-Keys, kein Schema-Eingriff.
library;

import '../models/workout_session.dart';

/// Welche Kennzahl trägt Trend-Badge und Sparkline einer Übung?
/// Gewicht schlägt Dauer schlägt Wiederholungen (die für Nutzer
/// aussagekräftigste vorhandene Größe).
enum ProgressMetric { weight, reps, duration }

/// Bester Wert einer Übung innerhalb einer Session – ein Datenpunkt der
/// Fortschritts-Zeitreihe.
class SessionBest {
  SessionBest(this.date);

  final DateTime date;
  int bestReps = 0;
  double bestWeightKg = 0;
  int bestDurationSeconds = 0;

  bool get isEmpty =>
      bestReps == 0 && bestWeightKg == 0 && bestDurationSeconds == 0;

  String get label {
    if (bestDurationSeconds > 0) {
      return '$bestDurationSeconds Sek.';
    }
    final weight =
        bestWeightKg > 0 ? ' à ${bestWeightKg.toStringAsFixed(1)} kg' : '';
    return '$bestReps Wdh.$weight';
  }
}

/// Fortschritt einer Übung über alle Sessions hinweg (chronologisch,
/// älteste zuerst).
class ExerciseProgress {
  ExerciseProgress(this.name, this.series);

  final String name;
  final List<SessionBest> series;

  SessionBest get first => series.first;
  SessionBest get latest => series.last;
  int get sessionCount => series.length;

  ProgressMetric get metric {
    if (series.any((s) => s.bestWeightKg > 0)) {
      return ProgressMetric.weight;
    }
    if (series.any((s) => s.bestDurationSeconds > 0)) {
      return ProgressMetric.duration;
    }
    return ProgressMetric.reps;
  }

  double _valueOf(SessionBest s) {
    switch (metric) {
      case ProgressMetric.weight:
        return s.bestWeightKg;
      case ProgressMetric.duration:
        return s.bestDurationSeconds.toDouble();
      case ProgressMetric.reps:
        return s.bestReps.toDouble();
    }
  }

  /// Werte der gewählten Kennzahl in chronologischer Reihenfolge –
  /// Datenbasis der Sparkline.
  List<double> get values => series.map(_valueOf).toList();

  /// Kurzes Trend-Label zwischen erster und letzter Session (Gewicht vor
  /// Wiederholungen vor Dauer). null bei nur einer Session.
  String? get delta {
    if (sessionCount < 2) {
      return null;
    }
    final weightDiff = latest.bestWeightKg - first.bestWeightKg;
    if (weightDiff != 0) {
      return '${weightDiff > 0 ? '+' : ''}${weightDiff.toStringAsFixed(1)} kg';
    }
    final repsDiff = latest.bestReps - first.bestReps;
    if (repsDiff != 0) {
      return '${repsDiff > 0 ? '+' : ''}$repsDiff Wdh.';
    }
    final durationDiff =
        latest.bestDurationSeconds - first.bestDurationSeconds;
    if (durationDiff != 0) {
      return '${durationDiff > 0 ? '+' : ''}$durationDiff Sek.';
    }
    return 'stabil';
  }
}

/// Eine Kennzahl-Kachel im Kopf des Fortschritts-Screens.
class StatTile {
  const StatTile({
    required this.label,
    required this.value,
    this.sub,
    this.highlightSub = false,
  });

  final String label;
  final String value;
  final String? sub;

  /// Sub-Text in Akzentfarbe hervorheben (z. B. „Wochenziel erreicht ✓").
  final bool highlightSub;
}

/// Alle für den Fortschritts-Screen aufbereiteten Daten.
class ProgressData {
  ProgressData({
    required this.exercises,
    required this.tiles,
    required this.setsPerDay,
    required this.weekStreak,
  });

  final List<ExerciseProgress> exercises;
  final List<StatTile> tiles;

  /// Anzahl abgeschlossener Sätze je Kalendertag (lokale Mitternacht) –
  /// Datenbasis der Heatmap.
  final Map<DateTime, int> setsPerDay;

  /// Aufeinanderfolgende Wochen mit mindestens einer Session, rückwärts
  /// ab der aktuellen Woche gezählt.
  final int weekStreak;

  bool get isEmpty => exercises.isEmpty && setsPerDay.isEmpty;
}

/// Lokale Mitternacht des gegebenen Zeitpunkts.
DateTime _dayKey(DateTime utc) {
  final local = utc.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Montag (00:00 lokal) der Woche, in der [day] liegt.
DateTime _weekStart(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// Baut aus der (neueste-zuerst sortierten) Session-Liste alle
/// Fortschritts-Kennzahlen. [now] und [weeklyGoal] werden injiziert,
/// damit die Funktion deterministisch testbar bleibt.
ProgressData computeProgress(
  List<WorkoutSession> sessions, {
  required DateTime now,
  int? weeklyGoal,
}) {
  // --- Übungs-Zeitreihen (chronologisch, älteste zuerst) ---
  final byExercise = <String, List<SessionBest>>{};
  final setsPerDay = <DateTime, int>{};
  final weekStartsWithSession = <DateTime>{};

  var heaviestWeight = 0.0;
  String? heaviestExercise;
  var longestDuration = 0;
  String? longestExercise;
  var mostReps = 0;
  String? mostRepsExercise;

  for (final session in sessions.reversed) {
    final day = _dayKey(session.date);
    weekStartsWithSession.add(_weekStart(day));

    for (final exercise in session.completedExercises) {
      final best = SessionBest(session.date);
      for (final set in exercise.setsLogged) {
        if (set.status != SetStatus.completed) {
          continue;
        }
        setsPerDay[day] = (setsPerDay[day] ?? 0) + 1;
        if (set.repsActual > best.bestReps) {
          best.bestReps = set.repsActual;
        }
        if (set.weightActualKg > best.bestWeightKg) {
          best.bestWeightKg = set.weightActualKg;
        }
        final duration = set.durationActualSeconds ?? 0;
        if (duration > best.bestDurationSeconds) {
          best.bestDurationSeconds = duration;
        }
        // Rekorde für die Kacheln.
        if (set.weightActualKg > heaviestWeight) {
          heaviestWeight = set.weightActualKg;
          heaviestExercise = exercise.exerciseName;
        }
        if (duration > longestDuration) {
          longestDuration = duration;
          longestExercise = exercise.exerciseName;
        }
        if (set.repsActual > mostReps) {
          mostReps = set.repsActual;
          mostRepsExercise = exercise.exerciseName;
        }
      }
      if (!best.isEmpty) {
        byExercise.putIfAbsent(exercise.exerciseName, () => []).add(best);
      }
    }
  }

  final exercises = byExercise.entries
      .map((e) => ExerciseProgress(e.key, e.value))
      .toList()
    ..sort((a, b) => b.sessionCount.compareTo(a.sessionCount));

  // --- Sessions dieser Woche ---
  final weekStart = _weekStart(now);
  final weekEnd = weekStart.add(const Duration(days: 7));
  var sessionsThisWeek = 0;
  DateTime? firstSessionDate;
  for (final session in sessions) {
    final day = _dayKey(session.date);
    if (!day.isBefore(weekStart) && day.isBefore(weekEnd)) {
      sessionsThisWeek++;
    }
    if (firstSessionDate == null || day.isBefore(firstSessionDate)) {
      firstSessionDate = day;
    }
  }

  // --- Wochen-Streak: rückwärts ab aktueller Woche zählen ---
  var streak = 0;
  var cursor = weekStart;
  while (weekStartsWithSession.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 7));
  }

  // --- Kacheln: die ersten vier mit Daten (immer gefüllt ab 1 Session) ---
  String fmtDate(DateTime? d) {
    if (d == null) {
      return '';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.';
  }

  String fmtWeight(double kg) =>
      kg % 1 == 0 ? '${kg.toInt()} kg' : '${kg.toStringAsFixed(1)} kg';

  final weeklyReached = weeklyGoal != null && sessionsThisWeek >= weeklyGoal;
  final candidates = <StatTile>[
    StatTile(
      label: 'SESSIONS GESAMT',
      value: '${sessions.length}',
      sub: firstSessionDate != null ? 'seit ${fmtDate(firstSessionDate)}' : null,
    ),
    StatTile(
      label: 'DIESE WOCHE',
      value: weeklyGoal != null
          ? '$sessionsThisWeek / $weeklyGoal'
          : '$sessionsThisWeek',
      sub: weeklyReached ? 'Wochenziel erreicht ✓' : null,
      highlightSub: weeklyReached,
    ),
    if (heaviestWeight > 0)
      StatTile(
        label: 'SCHWERSTER SATZ',
        value: fmtWeight(heaviestWeight),
        sub: heaviestExercise,
      ),
    if (longestDuration > 0)
      StatTile(
        label: 'LÄNGSTE ZEIT',
        value: '$longestDuration Sek.',
        sub: longestExercise,
      ),
    if (mostReps > 0)
      StatTile(
        label: 'MEISTE WDH.',
        value: '$mostReps',
        sub: mostRepsExercise,
      ),
    StatTile(label: 'ÜBUNGEN', value: '${byExercise.length}'),
  ];

  return ProgressData(
    exercises: exercises,
    tiles: candidates.take(4).toList(),
    setsPerDay: setsPerDay,
    weekStreak: streak,
  );
}
