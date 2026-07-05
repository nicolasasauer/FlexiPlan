import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_links.dart';
import '../models/workout_plan.dart';
import '../services/plan_parser.dart';
import '../services/storage_service.dart';

/// Hybrid-Import (Lastenheft 2.1): Datei-Upload UND Copy-Paste-Textfeld,
/// jeweils mit automatischer Schema-Validierung samt Fehlerprotokoll.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final TextEditingController _jsonController = TextEditingController();

  WorkoutPlan? _parsedPlan;
  List<String> _errors = const [];
  String? _sourceLabel;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return; // Abgebrochen.
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() {
        _parsedPlan = null;
        _errors = ['Datei konnte nicht gelesen werden.'];
        _sourceLabel = file.name;
      });
      return;
    }
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      setState(() {
        _parsedPlan = null;
        _errors = ['Datei ist keine gültige UTF-8-Textdatei.'];
        _sourceLabel = file.name;
      });
      return;
    }
    _validate(content, sourceLabel: file.name);
  }

  void _validatePastedText() {
    _validate(_jsonController.text, sourceLabel: 'Zwischenablage');
  }

  void _validate(String source, {required String sourceLabel}) {
    setState(() {
      _sourceLabel = sourceLabel;
      try {
        _parsedPlan = PlanParser.parse(source);
        _errors = const [];
      } on PlanValidationException catch (e) {
        _parsedPlan = null;
        _errors = e.errors;
      }
    });
  }

  Future<void> _activatePlan() async {
    final plan = _parsedPlan;
    if (plan == null) {
      return;
    }
    await widget.storage.saveActivePlan(plan);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Plan importieren')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open, size: 28),
              label: const Text('JSON-Datei auswählen'),
            ),
            const SizedBox(height: 20),
            Card(
              child: ExpansionTile(
                initiallyExpanded: true,
                title: Text(
                  'JSON einfügen (Copy-Paste)',
                  style: theme.textTheme.titleLarge,
                ),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _jsonController,
                    maxLines: 10,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '{ "workout_title": "...", '
                          '"exercises": [ ... ] }',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _validatePastedText,
                    icon: const Icon(Icons.rule, size: 28),
                    label: const Text('Prüfen & übernehmen'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_errors.isNotEmpty) _buildErrorCard(theme),
            if (_parsedPlan != null) _buildPreviewCard(theme),
            _buildTemplatesHintCard(theme),
          ],
        ),
      ),
    );
  }

  /// Verweis auf das offene GitHub-Repository mit fertigen
  /// Workout-Vorlagen und der JSON-Schema-Dokumentation.
  Widget _buildTemplatesHintCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Noch keinen Plan?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'FlexiPlan ist Open Source. Im GitHub-Repository findest du '
              'fertige Workout-Vorlagen zum Kopieren sowie eine Anleitung, '
              'wie du dir eigene Pläne erstellst – selbst, von deinem Coach '
              'oder von einer KI generiert.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => openExternalUrl(workoutTemplatesUrl),
              icon: const Icon(Icons.open_in_new, size: 28),
              label: const Text('Vorlagen auf GitHub'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline,
                    color: theme.colorScheme.error, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fehlerprotokoll (${_sourceLabel ?? 'Eingabe'})',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final error in _errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• $error',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme) {
    final plan = _parsedPlan!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Validierung erfolgreich (${_sourceLabel ?? ''})',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(plan.workoutTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${plan.exercises.length} Übungen · ${plan.totalSets} Sätze',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            for (final ex in plan.exercises)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  ex.type == ExerciseType.reps
                      ? '• ${ex.name}: ${ex.sets} × ${ex.reps} Wdh.'
                          '${ex.weightKg > 0 ? ' à ${ex.weightKg} kg' : ''}'
                      : '• ${ex.name}: ${ex.sets} × '
                          '${ex.durationSeconds} Sek.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _activatePlan,
              icon: const Icon(Icons.download_done, size: 28),
              label: const Text('Plan aktivieren'),
            ),
          ],
        ),
      ),
    );
  }
}
