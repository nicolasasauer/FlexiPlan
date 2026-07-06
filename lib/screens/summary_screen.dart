import 'package:flutter/material.dart';

import '../models/workout_session.dart';

/// Session-Zusammenfassung nach Trainingsende (Lastenheft 2.3):
/// Gesamtzeit, geschaffte Sätze/Wiederholungen, bewegtes Gesamtvolumen.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Zusammenfassung')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.workoutTitle,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 20),
                    _StatRow(
                      icon: Icons.timer_outlined,
                      label: 'Gesamtzeit',
                      value: '${session.durationMinutes} Min.',
                    ),
                    _StatRow(
                      icon: Icons.check_circle_outline,
                      label: 'Geschaffte Sätze',
                      value: '${session.completedSetCount}',
                    ),
                    _StatRow(
                      icon: Icons.skip_next,
                      label: 'Übersprungene Sätze',
                      value: '${session.skippedSetCount}',
                    ),
                    _StatRow(
                      icon: Icons.repeat,
                      label: 'Wiederholungen gesamt',
                      value: '${session.totalReps}',
                    ),
                    // Bei reinen Eigengewichts-Workouts wäre "0.0 kg" nur
                    // verwirrend – die Zeile entfällt dann.
                    if (session.totalVolumeKg > 0)
                      _StatRow(
                        icon: Icons.fitness_center,
                        label: 'Bewegtes Volumen',
                        value:
                            '${session.totalVolumeKg.toStringAsFixed(1)} kg',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            for (final ex in session.completedExercises)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex.exerciseName,
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      for (final set in ex.setsLogged)
                        Text(
                          set.status == SetStatus.skipped
                              ? 'Satz ${set.setNumber}: übersprungen'
                              : set.durationActualSeconds != null
                                  ? 'Satz ${set.setNumber}: '
                                      '${set.durationActualSeconds} Sek.'
                                  : 'Satz ${set.setNumber}: '
                                      '${set.repsActual} Wdh.'
                                      '${set.weightActualKg > 0 ? ' à ${set.weightActualKg.toStringAsFixed(1)} kg' : ''}',
                          style: theme.textTheme.bodyLarge,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.home, size: 28),
              label: const Text('Fertig'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: theme.textTheme.titleMedium),
          ),
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
