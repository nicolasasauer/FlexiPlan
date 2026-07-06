import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/workout_session.dart';
import '../services/storage_service.dart';
import 'progress_screen.dart';
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

  /// Manuelles Backup (Lastenheft 3.2): exportiert die gesamte Historie
  /// als flexiplan_backup.json an einen vom Nutzer gewählten Ort.
  Future<void> _exportBackup() async {
    final json = await widget.storage.exportHistoryJson();
    final bytes = Uint8List.fromList(utf8.encode(json));
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Backup speichern',
        fileName: 'flexiplan_backup.json',
        bytes: bytes,
      );
    } on Object {
      path = null;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path == null
            ? 'Backup abgebrochen.'
            : 'Backup gespeichert: $path'),
      ),
    );
  }

  void _openProgress() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProgressScreen(storage: widget.storage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verlauf'),
        actions: [
          IconButton(
            icon: const Icon(Icons.trending_up, size: 28),
            tooltip: 'Fortschritt',
            onPressed: _openProgress,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt, size: 28),
            tooltip: 'Backup exportieren',
            onPressed: _exportBackup,
          ),
        ],
      ),
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
