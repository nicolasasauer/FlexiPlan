/// JSON-Parser mit Schema-Validierung für Trainingspläne
/// (Lastenheft V1.2, Abschnitt 2.1 und 4.1).
library;

import 'dart:convert';

import '../models/workout_plan.dart';

/// Wird geworfen, wenn der Import-JSON das Schema verletzt.
/// [errors] enthält ein klares, vollständiges Fehlerprotokoll.
class PlanValidationException implements Exception {
  PlanValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'PlanValidationException:\n${errors.join('\n')}';
}

class PlanParser {
  PlanParser._();

  static const Set<String> _allowedTypes = {'reps', 'time'};

  /// Parst und validiert einen JSON-String.
  /// Wirft [PlanValidationException] mit Fehlerprotokoll bei Verstößen.
  static WorkoutPlan parse(String source) {
    if (source.trim().isEmpty) {
      throw PlanValidationException(
          ['Die Eingabe ist leer. Bitte JSON einfügen oder Datei wählen.']);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw PlanValidationException(['Ungültiges JSON: ${e.message}']);
    }

    if (decoded is! Map<String, dynamic>) {
      throw PlanValidationException(
          ['Das Wurzelelement muss ein JSON-Objekt sein.']);
    }

    final errors = <String>[];

    // workout_title
    final title = decoded['workout_title'];
    if (title is! String || title.trim().isEmpty) {
      errors.add(
          'Feld "workout_title" fehlt oder ist kein nicht-leerer String.');
    }

    // version / description (optional, aber typgeprüft)
    if (decoded.containsKey('version') && decoded['version'] is! String) {
      errors.add('Feld "version" muss ein String sein.');
    }
    if (decoded.containsKey('description') &&
        decoded['description'] is! String) {
      errors.add('Feld "description" muss ein String sein.');
    }

    // exercises
    final rawExercises = decoded['exercises'];
    if (rawExercises is! List || rawExercises.isEmpty) {
      errors.add('Feld "exercises" fehlt oder ist keine nicht-leere Liste.');
    } else {
      for (var i = 0; i < rawExercises.length; i++) {
        final label = 'Übung ${i + 1}';
        final ex = rawExercises[i];
        if (ex is! Map<String, dynamic>) {
          errors.add('$label: Eintrag muss ein JSON-Objekt sein.');
          continue;
        }
        _validateExercise(ex, label, errors);
      }
    }

    if (errors.isNotEmpty) {
      throw PlanValidationException(errors);
    }
    return WorkoutPlan.fromJson(decoded);
  }

  static void _validateExercise(
      Map<String, dynamic> ex, String label, List<String> errors) {
    // id
    if (ex['id'] is! int) {
      errors.add('$label: Feld "id" fehlt oder ist keine Ganzzahl.');
    }

    // name
    final name = ex['name'];
    if (name is! String || name.trim().isEmpty) {
      errors.add('$label: Feld "name" fehlt oder ist kein nicht-leerer '
          'String.');
    }

    // description (optional)
    if (ex.containsKey('description') && ex['description'] is! String) {
      errors.add('$label: Feld "description" muss ein String sein.');
    }

    // type
    final type = ex['type'];
    if (type is! String || !_allowedTypes.contains(type)) {
      errors.add('$label: Feld "type" muss "reps" oder "time" sein.');
      return; // Folgeprüfungen hängen vom Typ ab.
    }

    // sets
    final sets = ex['sets'];
    if (sets is! int || sets < 1) {
      errors.add('$label: Feld "sets" muss eine Ganzzahl >= 1 sein.');
    }

    // rest_duration_seconds
    final rest = ex['rest_duration_seconds'];
    if (rest is! int || rest < 0) {
      errors.add('$label: Feld "rest_duration_seconds" muss eine '
          'Ganzzahl >= 0 sein.');
    }

    if (type == 'reps') {
      final reps = ex['reps'];
      if (reps is! int || reps < 1) {
        errors.add('$label: Bei type "reps" ist "reps" als Ganzzahl >= 1 '
            'Pflicht.');
      }
      final weight = ex['weight_kg'];
      if (weight != null && (weight is! num || weight < 0)) {
        errors.add('$label: Feld "weight_kg" muss eine Zahl >= 0 sein.');
      }
    } else {
      // type == 'time'
      final duration = ex['duration_seconds'];
      if (duration is! int || duration < 1) {
        errors.add('$label: Bei type "time" ist "duration_seconds" als '
            'Ganzzahl >= 1 Pflicht.');
      }
    }
  }
}
