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
        content: Text(
          path == null ? 'Backup abgebrochen.' : 'Backup gespeichert: $path',
        ),
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

  void _reload() {
    setState(() {
      _sessionsFuture = widget.storage.loadSessions();
    });
  }

  /// Backup wieder einspielen (Gegenstück zu [_exportBackup]); per
  /// session_id dedupliziert, mehrfaches Einspielen ist unschädlich.
  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) {
      return; // Abgebrochen.
    }
    String message;
    try {
      final outcome = await widget.storage.importHistoryJson(
        utf8.decode(bytes),
      );
      message =
          '${outcome.added} Sessions importiert'
          '${outcome.skipped > 0 ? ', ${outcome.skipped} übersprungen (bereits vorhanden oder defekt)' : ''}.';
      _reload();
    } on FormatException catch (e) {
      message = e.message;
    } on Object {
      message = 'Backup konnte nicht gelesen werden.';
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmDeleteSession(WorkoutSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Session löschen?'),
            content: Text(
              '„${session.workoutTitle}" vom '
              '${_formatDate(session.date)} wird dauerhaft aus der '
              'Historie entfernt.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen', style: TextStyle(fontSize: 18)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Löschen',
                  style: TextStyle(fontSize: 18, color: Colors.redAccent),
                ),
              ),
            ],
          ),
    );
    return confirmed == true;
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
            // Export = Daten raus → Pfeil nach oben (Upload-Metapher).
            icon: const Icon(Icons.file_upload_outlined, size: 28),
            tooltip: 'Backup exportieren',
            onPressed: _exportBackup,
          ),
          IconButton(
            // Import = Daten rein → Pfeil nach unten (wie „Trainingsplan
            // importieren" auf dem Home-Screen).
            icon: const Icon(Icons.file_download_outlined, size: 28),
            tooltip: 'Backup importieren',
            onPressed: _importBackup,
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
                return Dismissible(
                  key: ValueKey(session.sessionId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 28, bottom: 12),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 32,
                    ),
                  ),
                  confirmDismiss: (_) => _confirmDeleteSession(session),
                  onDismissed: (_) async {
                    await widget.storage.deleteSession(session.sessionId);
                    _reload();
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      title: Text(
                        session.workoutTitle,
                        style: theme.textTheme.titleLarge,
                      ),
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
