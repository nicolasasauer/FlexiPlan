import 'package:flutter/material.dart';

import '../models/workout_session.dart';
import '../services/storage_service.dart';

/// Fortschritts-Analyse (Lastenheft 2.3): vergleicht Leistungen
/// identischer Übungen (per Name) über alle vergangenen Sessions hinweg –
/// bewusst als einfache tabellarische Übersicht (V1, ohne Chart-Paket).
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

/// Beste Werte einer Übung innerhalb einer Session.
class _SessionBest {
  _SessionBest(this.date);

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
    final weight = bestWeightKg > 0
        ? ' à ${bestWeightKg.toStringAsFixed(1)} kg'
        : '';
    return '$bestReps Wdh.$weight';
  }
}

class _ExerciseProgress {
  _ExerciseProgress(this.name, this.first, this.latest, this.sessionCount);

  final String name;
  final _SessionBest first;
  final _SessionBest latest;
  final int sessionCount;

  /// Kurzes Trend-Label, wenn sich zwischen erster und letzter Session
  /// etwas verändert hat (Gewicht vor Wiederholungen vor Dauer).
  String? get delta {
    if (sessionCount < 2) {
      return null;
    }
    final weightDiff = latest.bestWeightKg - first.bestWeightKg;
    if (weightDiff != 0) {
      final sign = weightDiff > 0 ? '+' : '';
      return '$sign${weightDiff.toStringAsFixed(1)} kg';
    }
    final repsDiff = latest.bestReps - first.bestReps;
    if (repsDiff != 0) {
      final sign = repsDiff > 0 ? '+' : '';
      return '$sign$repsDiff Wdh.';
    }
    final durationDiff = latest.bestDurationSeconds - first.bestDurationSeconds;
    if (durationDiff != 0) {
      final sign = durationDiff > 0 ? '+' : '';
      return '$sign$durationDiff Sek.';
    }
    return 'stabil';
  }
}

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<List<_ExerciseProgress>> _progressFuture;

  @override
  void initState() {
    super.initState();
    _progressFuture = _buildProgress();
  }

  Future<List<_ExerciseProgress>> _buildProgress() async {
    // loadSessions liefert absteigend sortiert (neueste zuerst).
    final sessions = await widget.storage.loadSessions();

    // Pro Übungsname: Session-Bestwerte in chronologischer Reihenfolge.
    final byExercise = <String, List<_SessionBest>>{};
    for (final session in sessions.reversed) {
      for (final exercise in session.completedExercises) {
        final best = _SessionBest(session.date);
        for (final set in exercise.setsLogged) {
          if (set.status != SetStatus.completed) {
            continue;
          }
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
        }
        if (!best.isEmpty) {
          byExercise.putIfAbsent(exercise.exerciseName, () => []).add(best);
        }
      }
    }

    final result = byExercise.entries
        .map((e) => _ExerciseProgress(
            e.key, e.value.first, e.value.last, e.value.length))
        .toList()
      // Übungen mit den meisten Datenpunkten zuerst.
      ..sort((a, b) => b.sessionCount.compareTo(a.sessionCount));
    return result;
  }

  String _formatDate(DateTime utc) {
    final local = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fortschritt')),
      body: SafeArea(
        child: FutureBuilder<List<_ExerciseProgress>>(
          future: _progressFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data ?? const <_ExerciseProgress>[];
            if (entries.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Noch keine abgeschlossenen Sätze.\n'
                    'Nach deinem ersten Workout siehst du hier,\n'
                    'wie du dich von Session zu Session steigerst.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final delta = entry.delta;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(entry.name,
                                  style: theme.textTheme.titleLarge),
                            ),
                            if (delta != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  delta,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (entry.sessionCount >= 2) ...[
                          Text(
                            'Erste Session (${_formatDate(entry.first.date)}): '
                            '${entry.first.label}',
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Zuletzt (${_formatDate(entry.latest.date)}): '
                            '${entry.latest.label}',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ] else
                          Text(
                            'Bisher 1 Session '
                            '(${_formatDate(entry.latest.date)}): '
                            '${entry.latest.label}',
                            style: theme.textTheme.bodyLarge,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '${entry.sessionCount} Session'
                          '${entry.sessionCount == 1 ? '' : 's'} erfasst',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
