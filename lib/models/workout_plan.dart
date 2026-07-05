/// Datenmodell für importierte Trainingspläne gemäß Lastenheft V1.2,
/// Abschnitt 4.1 (Import-Schema).
library;

enum ExerciseType { reps, time }

ExerciseType exerciseTypeFromString(String value) {
  switch (value) {
    case 'reps':
      return ExerciseType.reps;
    case 'time':
      return ExerciseType.time;
    default:
      throw ArgumentError('Unbekannter Übungstyp: $value');
  }
}

String exerciseTypeToString(ExerciseType type) {
  switch (type) {
    case ExerciseType.reps:
      return 'reps';
    case ExerciseType.time:
      return 'time';
  }
}

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.durationSeconds,
    required this.restDurationSeconds,
  });

  final int id;
  final String name;
  final String description;
  final ExerciseType type;
  final int sets;

  /// Nur relevant bei [ExerciseType.reps].
  final int reps;

  /// Nur relevant bei [ExerciseType.reps]. 0 = Eigengewicht.
  final double weightKg;

  /// Nur relevant bei [ExerciseType.time].
  final int durationSeconds;

  final int restDurationSeconds;

  factory Exercise.fromJson(Map<String, dynamic> json) {
    final type = exerciseTypeFromString(json['type'] as String);
    return Exercise(
      id: json['id'] as int,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      type: type,
      sets: json['sets'] as int,
      reps: (json['reps'] as num?)?.toInt() ?? 0,
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      restDurationSeconds: (json['rest_duration_seconds'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'type': exerciseTypeToString(type),
        'sets': sets,
        if (type == ExerciseType.reps) 'reps': reps,
        if (type == ExerciseType.reps) 'weight_kg': weightKg,
        if (type == ExerciseType.time) 'duration_seconds': durationSeconds,
        'rest_duration_seconds': restDurationSeconds,
      };
}

class WorkoutPlan {
  const WorkoutPlan({
    required this.workoutTitle,
    required this.version,
    required this.description,
    required this.exercises,
  });

  final String workoutTitle;
  final String version;
  final String description;
  final List<Exercise> exercises;

  int get totalSets =>
      exercises.fold(0, (sum, exercise) => sum + exercise.sets);

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) {
    final rawExercises = json['exercises'] as List<dynamic>;
    return WorkoutPlan(
      workoutTitle: json['workout_title'] as String,
      version: (json['version'] as String?) ?? '1.0',
      description: (json['description'] as String?) ?? '',
      exercises: rawExercises
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'workout_title': workoutTitle,
        'version': version,
        'description': description,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}
