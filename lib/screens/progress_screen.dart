import 'package:flutter/material.dart';

import '../services/progress_analytics.dart';
import '../services/reminder_service.dart';
import '../services/storage_service.dart';
import '../widgets/sparkline.dart';

/// Fortschritts-Analyse (Lastenheft 2.3): Kennzahl-Kacheln plus der
/// Verlauf identischer Übungen über alle Sessions hinweg. Ohne
/// Chart-Paket – die Aggregation liegt in [computeProgress].
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<ProgressData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<ProgressData> _load() async {
    final sessions = await widget.storage.loadSessions();
    // Wochenziel aus der aktiven Erinnerung ableiten (Anzahl der
    // gewählten Trainingstage) – ohne Erinnerung kein Ziel. loadSettings
    // liest nur Prefs, initialisiert das Notification-Plugin nicht.
    final reminder = await ReminderService().loadSettings();
    final weeklyGoal =
        reminder.enabled && reminder.weekdays.isNotEmpty
            ? reminder.weekdays.length
            : null;
    return computeProgress(sessions, now: DateTime.now(), weeklyGoal: weeklyGoal);
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
        child: FutureBuilder<ProgressData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data;
            if (data == null || data.isEmpty) {
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
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTiles(theme, data.tiles),
                const SizedBox(height: 12),
                _buildHeatmapCard(theme, data),
                const SizedBox(height: 4),
                for (final entry in data.exercises)
                  _buildExerciseCard(theme, entry),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 2×n-Raster der Kennzahl-Kacheln.
  Widget _buildTiles(ThemeData theme, List<StatTile> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: tileWidth,
                child: _StatTileCard(tile: tile),
              ),
          ],
        );
      },
    );
  }

  /// Trainings-Heatmap der letzten 8 Wochen (Spalten) × 7 Tage (Zeilen,
  /// Mo oben) plus Streak-Chip. Farbe = Sätze am Tag, sequentiell
  /// (leer → 3 Grünstufen), adaptiv zum Maximum im Fenster.
  Widget _buildHeatmapCard(ThemeData theme, ProgressData data) {
    const weeks = 8;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Montag der aktuellen Woche, dann 7 Wochen zurück = erste Spalte.
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final firstMonday = currentMonday.subtract(const Duration(days: 7 * (weeks - 1)));

    final maxSets = data.setsPerDay.values.isEmpty
        ? 0
        : data.setsPerDay.values.reduce((a, b) => a > b ? a : b);

    // Level 0 = leer, 1..3 = zunehmender Akzent.
    Color levelColor(int level) {
      if (level <= 0) {
        return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      }
      final primary = theme.colorScheme.primary;
      return Color.lerp(
        primary.withValues(alpha: 0.28),
        primary,
        (level.clamp(1, 3) - 1) / 2,
      )!;
    }

    int levelOf(int sets) {
      if (sets <= 0 || maxSets <= 0) {
        return sets <= 0 ? 0 : 3;
      }
      return (3 * sets / maxSets).ceil().clamp(1, 3);
    }

    const dayLabels = ['Mo', '', 'Mi', '', 'Fr', '', 'So'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Konstanz · 8 Wochen',
                      style: theme.textTheme.titleLarge),
                ),
                if (data.weekStreak >= 2)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${data.weekStreak} Wochen dran 🔥',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Kompaktes Raster mit gedeckelter Zellgröße (statt die volle
            // Breite zu füllen) – bleibt nah am Mockup und lässt der
            // Übersicht Platz.
            LayoutBuilder(
              builder: (context, constraints) {
                const cellGap = 4.0;
                const labelWidth = 28.0;
                final available = constraints.maxWidth - labelWidth;
                final rawCell = (available - cellGap * (weeks - 1)) / weeks;
                final cell = rawCell.clamp(0.0, 30.0);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Column(
                        children: [
                          for (final label in dayLabels)
                            SizedBox(
                              height: cell + cellGap,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(label,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var row = 0; row < 7; row++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: cellGap),
                            child: Row(
                              children: [
                                for (var col = 0; col < weeks; col++)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: cellGap),
                                    child: () {
                                      final date = firstMonday.add(
                                          Duration(days: col * 7 + row));
                                      final future = date.isAfter(today);
                                      final sets = data.setsPerDay[date] ?? 0;
                                      return Container(
                                        width: cell,
                                        height: cell,
                                        decoration: BoxDecoration(
                                          color: future
                                              ? Colors.transparent
                                              : levelColor(levelOf(sets)),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                      );
                                    }(),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('wenig',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 6),
                for (final level in [0, 1, 2, 3])
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: levelColor(level),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                const SizedBox(width: 3),
                Text('viele Sätze',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(ThemeData theme, ExerciseProgress entry) {
    final delta = entry.delta;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.name, style: theme.textTheme.titleLarge),
                ),
                if (delta != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      delta,
                      style: theme.textTheme.titleMedium?.copyWith(
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
              const SizedBox(height: 12),
              Sparkline(
                values: entry.values,
                color: theme.colorScheme.primary,
              ),
            ] else
              Text(
                'Bisher 1 Session (${_formatDate(entry.latest.date)}): '
                '${entry.latest.label}',
                style: theme.textTheme.bodyLarge,
              ),
            const SizedBox(height: 4),
            Text(
              '${entry.sessionCount} Session'
              '${entry.sessionCount == 1 ? '' : 's'} erfasst',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTileCard extends StatelessWidget {
  const _StatTileCard({required this.tile});

  final StatTile tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tile.label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              tile.value,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (tile.sub != null) ...[
              const SizedBox(height: 2),
              Text(
                tile.sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tile.highlightSub
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
