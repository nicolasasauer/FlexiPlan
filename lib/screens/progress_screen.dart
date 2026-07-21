import 'package:flutter/material.dart';

import '../services/progress_analytics.dart';
import '../services/reminder_service.dart';
import '../services/storage_service.dart';

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
                const SizedBox(height: 8),
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
