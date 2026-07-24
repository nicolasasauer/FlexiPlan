import 'package:flutter/material.dart';

import '../models/workout_plan.dart';

/// Formular-Popup zum Bearbeiten eines bereits geparsten Plans – Name,
/// Beschreibung, Sätze, Wiederholungen/Dauer, Gewicht und Pause pro Übung.
/// Alternative zum direkten Editieren des rohen JSON-Textfelds im
/// Import-Screen. Gibt den geänderten Plan zurück, oder null bei Abbruch.
Future<WorkoutPlan?> showPlanEditorDialog(
  BuildContext context,
  WorkoutPlan plan,
) {
  return showDialog<WorkoutPlan>(
    context: context,
    builder: (context) => _PlanEditorDialog(plan: plan),
  );
}

/// Ein Satz Controller pro Übung; id/type/bodyweight bleiben unverändert
/// (Typ-Wechsel wäre ein strukturellerer Eingriff als reines Werte-Tuning).
class _ExerciseControllers {
  _ExerciseControllers(Exercise ex)
      : name = TextEditingController(text: ex.name),
        description = TextEditingController(text: ex.description),
        sets = TextEditingController(text: ex.sets.toString()),
        reps = TextEditingController(text: ex.reps.toString()),
        weight = TextEditingController(
          text: ex.weightKg % 1 == 0
              ? ex.weightKg.toInt().toString()
              : ex.weightKg.toString(),
        ),
        duration = TextEditingController(text: ex.durationSeconds.toString()),
        rest = TextEditingController(text: ex.restDurationSeconds.toString());

  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController sets;
  final TextEditingController reps;
  final TextEditingController weight;
  final TextEditingController duration;
  final TextEditingController rest;

  Listenable get listenable => Listenable.merge(
        [name, description, sets, reps, weight, duration, rest],
      );

  void dispose() {
    name.dispose();
    description.dispose();
    sets.dispose();
    reps.dispose();
    weight.dispose();
    duration.dispose();
    rest.dispose();
  }
}

class _PlanEditorDialog extends StatefulWidget {
  const _PlanEditorDialog({required this.plan});

  final WorkoutPlan plan;

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  late final List<_ExerciseControllers> _controllers = [
    for (final ex in widget.plan.exercises) _ExerciseControllers(ex),
  ];
  late final Listenable _anyChange =
      Listenable.merge([for (final c in _controllers) c.listenable]);

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  int? _parsePositiveInt(String text) {
    final value = int.tryParse(text.trim());
    return (value == null || value < 1) ? null : value;
  }

  int? _parseNonNegativeInt(String text) {
    final value = int.tryParse(text.trim());
    return (value == null || value < 0) ? null : value;
  }

  double? _parseNonNegativeDouble(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return (value == null || value < 0) ? null : value;
  }

  bool _exerciseValid(Exercise ex, _ExerciseControllers c) {
    if (c.name.text.trim().isEmpty) {
      return false;
    }
    if (_parsePositiveInt(c.sets.text) == null) {
      return false;
    }
    if (ex.type == ExerciseType.reps) {
      if (_parsePositiveInt(c.reps.text) == null) {
        return false;
      }
      if (!ex.bodyweight && _parseNonNegativeDouble(c.weight.text) == null) {
        return false;
      }
    } else if (_parsePositiveInt(c.duration.text) == null) {
      return false;
    }
    return _parseNonNegativeInt(c.rest.text) != null;
  }

  bool get _allValid {
    for (var i = 0; i < _controllers.length; i++) {
      if (!_exerciseValid(widget.plan.exercises[i], _controllers[i])) {
        return false;
      }
    }
    return true;
  }

  void _save() {
    final exercises = <Exercise>[];
    for (var i = 0; i < _controllers.length; i++) {
      final ex = widget.plan.exercises[i];
      final c = _controllers[i];
      exercises.add(Exercise(
        id: ex.id,
        name: c.name.text.trim(),
        description: c.description.text.trim(),
        type: ex.type,
        sets: _parsePositiveInt(c.sets.text)!,
        reps:
            ex.type == ExerciseType.reps ? _parsePositiveInt(c.reps.text)! : 0,
        weightKg: ex.type == ExerciseType.reps && !ex.bodyweight
            ? _parseNonNegativeDouble(c.weight.text)!
            : 0,
        bodyweight: ex.bodyweight,
        durationSeconds: ex.type == ExerciseType.time
            ? _parsePositiveInt(c.duration.text)!
            : 0,
        restDurationSeconds: _parseNonNegativeInt(c.rest.text)!,
      ));
    }
    Navigator.of(context).pop(WorkoutPlan(
      workoutTitle: widget.plan.workoutTitle,
      version: widget.plan.version,
      description: widget.plan.description,
      exercises: exercises,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _anyChange,
      builder: (context, _) => AlertDialog(
        title: const Text('Übungen bearbeiten'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.6,
          child: ListView.separated(
            itemCount: _controllers.length,
            separatorBuilder: (_, __) => const Divider(height: 32),
            itemBuilder: (context, i) => _buildExerciseForm(
                theme, widget.plan.exercises[i], _controllers[i]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: _allValid ? _save : null,
            child: const Text('Speichern', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseForm(
      ThemeData theme, Exercise ex, _ExerciseControllers c) {
    const numberFieldWidth = 110.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: c.name,
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            labelText: 'Name',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: c.description,
          minLines: 1,
          maxLines: 3,
          style: theme.textTheme.bodyMedium,
          decoration: const InputDecoration(
            labelText: 'Beschreibung',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            SizedBox(
              width: numberFieldWidth,
              child: TextField(
                controller: c.sets,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Sätze',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText:
                      _parsePositiveInt(c.sets.text) == null ? 'ungültig' : null,
                ),
              ),
            ),
            if (ex.type == ExerciseType.reps) ...[
              SizedBox(
                width: numberFieldWidth,
                child: TextField(
                  controller: c.reps,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Wdh.',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: _parsePositiveInt(c.reps.text) == null
                        ? 'ungültig'
                        : null,
                  ),
                ),
              ),
              if (!ex.bodyweight)
                SizedBox(
                  width: numberFieldWidth,
                  child: TextField(
                    controller: c.weight,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Gewicht (kg)',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: _parseNonNegativeDouble(c.weight.text) == null
                          ? 'ungültig'
                          : null,
                    ),
                  ),
                ),
            ] else
              SizedBox(
                width: numberFieldWidth,
                child: TextField(
                  controller: c.duration,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Dauer (Sek.)',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: _parsePositiveInt(c.duration.text) == null
                        ? 'ungültig'
                        : null,
                  ),
                ),
              ),
            SizedBox(
              width: numberFieldWidth,
              child: TextField(
                controller: c.rest,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Pause (Sek.)',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText: _parseNonNegativeInt(c.rest.text) == null
                      ? 'ungültig'
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
