import 'package:flutter/material.dart';

import '../models/workout_session.dart';
import '../services/storage_service.dart';
import 'summary_screen.dart';

/// Lokale Historie (Lastenheft 2.3): chronologische Liste aller
/// absolvierten Sessions aus dem persistenten Speicher.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<WorkoutSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = widget.storage.loadSessions();
  }

  String _formatDate(DateTime utc) {
    final local = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} · '
        '${two(local.hour)}:${two(local.minute)} Uhr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf')),
      body: SafeArea(
        child: FutureBuilder<List<WorkoutSession>>(
          future: _sessionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final sessions = snapshot.data ?? const <WorkoutSession>[];
            if (sessions.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Noch keine Sessions gespeichert.\n'
                    'Starte dein erstes Workout!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    title: Text(session.workoutTitle,
                        style: theme.textTheme.titleLarge),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${_formatDate(session.date)}\n'
                        '${session.durationMinutes} Min. · '
                        '${session.completedSetCount} Sätze'
                        '${session.totalVolumeKg > 0 ? ' · ${session.totalVolumeKg.toStringAsFixed(1)} kg Volumen' : ''}',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 32),
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => SummaryScreen(session: session),
                        ),
                      );
                    },
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
