/// Datenmodell für aufgezeichnete Sessions gemäß Lastenheft V1.2,
/// Abschnitt 4.2 (Export- & Tracking-Schema) inkl. data_version für
/// update-resistente Schema-Migration.
library;

/// Status-Konstanten für geloggte Sätze.
class SetStatus {
  SetStatus._();

  static const String completed = 'completed';
  static const String skipped = 'skipped';
}

class SetLog {
  const SetLog({
    required this.setNumber,
    required this.status,
    required this.repsActual,
    required this.weightActualKg,
    this.durationActualSeconds,
  });

  final int setNumber;

  /// [SetStatus.completed] oder [SetStatus.skipped].
  final String status;
  final int repsActual;
  final double weightActualKg;

  /// Nur gesetzt bei zeitbasierten Übungen (Schema-Erweiterung, optional).
  final int? durationActualSeconds;

  factory SetLog.fromJson(Map<String, dynamic> json) => SetLog(
        setNumber: json['set_number'] as int,
        status: json['status'] as String,
        repsActual: (json['reps_actual'] as num).toInt(),
        weightActualKg: (json['weight_actual_kg'] as num).toDouble(),
        durationActualSeconds:
            (json['duration_actual_seconds'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'set_number': setNumber,
        'status': status,
        'reps_actual': repsActual,
        'weight_actual_kg': weightActualKg,
        if (durationActualSeconds != null)
          'duration_actual_seconds': durationActualSeconds,
      };
}

class CompletedExercise {
  const CompletedExercise({
    required this.exerciseName,
    required this.setsLogged,
  });

  final String exerciseName;
  final List<SetLog> setsLogged;

  factory CompletedExercise.fromJson(Map<String, dynamic> json) =>
      CompletedExercise(
        exerciseName: json['exercise_name'] as String,
        setsLogged: (json['sets_logged'] as List<dynamic>)
            .map((e) => SetLog.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'exercise_name': exerciseName,
        'sets_logged': setsLogged.map((s) => s.toJson()).toList(),
      };
}

class WorkoutSession {
  const WorkoutSession({
    required this.dataVersion,
    required this.sessionId,
    required this.date,
    required this.workoutTitle,
    required this.durationMinutes,
    required this.completedExercises,
  });

  final int dataVersion;
  final String sessionId;
  final DateTime date;
  final String workoutTitle;
  final int durationMinutes;
  final List<CompletedExercise> completedExercises;

  int get completedSetCount => completedExercises.fold(
      0,
      (sum, ex) =>
          sum +
          ex.setsLogged.where((s) => s.status == SetStatus.completed).length);

  int get skippedSetCount => completedExercises.fold(
      0,
      (sum, ex) =>
          sum +
          ex.setsLogged.where((s) => s.status == SetStatus.skipped).length);

  int get totalReps => completedExercises.fold(
      0,
      (sum, ex) =>
          sum +
          ex.setsLogged
              .where((s) => s.status == SetStatus.completed)
              .fold(0, (inner, s) => inner + s.repsActual));

  /// Bewegtes Gesamtvolumen in kg (Summe reps * weight).
  double get totalVolumeKg => completedExercises.fold(
      0.0,
      (sum, ex) =>
          sum +
          ex.setsLogged.where((s) => s.status == SetStatus.completed).fold(
              0.0, (inner, s) => inner + s.repsActual * s.weightActualKg));

  factory WorkoutSession.fromJson(Map<String, dynamic> json) =>
      WorkoutSession(
        dataVersion: json['data_version'] as int,
        sessionId: json['session_id'] as String,
        date: DateTime.parse(json['date'] as String),
        workoutTitle: json['workout_title'] as String,
        durationMinutes: (json['duration_minutes'] as num).toInt(),
        completedExercises: (json['completed_exercises'] as List<dynamic>)
            .map((e) => CompletedExercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'data_version': dataVersion,
        'session_id': sessionId,
        'date': date.toUtc().toIso8601String(),
        'workout_title': workoutTitle,
        'duration_minutes': durationMinutes,
        'completed_exercises':
            completedExercises.map((e) => e.toJson()).toList(),
      };
}
