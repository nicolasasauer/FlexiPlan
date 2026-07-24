import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_links.dart';
import '../models/workout_plan.dart';
import '../services/plan_parser.dart';
import '../services/storage_service.dart';
import '../services/template_repository.dart';
import 'plan_editor_dialog.dart';

/// Hybrid-Import (Lastenheft 2.1): Datei-Upload UND Copy-Paste-Textfeld.
/// Die Eingabe wird live validiert; ein einzelner „Plan übernehmen"-Button
/// öffnet eine Vorschau als Popup und speichert nach Bestätigung.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.storage,
    this.templateRepository = const TemplateRepository(),
  });

  final StorageService storage;

  /// Austauschbar für Tests (z. B. mit einem gemockten http.Client).
  final TemplateRepository templateRepository;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final TextEditingController _jsonController = TextEditingController();

  WorkoutPlan? _parsedPlan;
  List<String> _errors = const [];

  @override
  void initState() {
    super.initState();
    _jsonController.addListener(_revalidate);
  }

  @override
  void dispose() {
    _jsonController.removeListener(_revalidate);
    _jsonController.dispose();
    super.dispose();
  }

  /// Validiert die Eingabe automatisch bei jeder Änderung – kein
  /// separater „Prüfen"-Schritt nötig.
  void _revalidate() {
    final source = _jsonController.text.trim();
    if (source.isEmpty) {
      if (_parsedPlan != null || _errors.isNotEmpty) {
        setState(() {
          _parsedPlan = null;
          _errors = const [];
        });
      }
      return;
    }
    try {
      final plan = PlanParser.parse(source);
      setState(() {
        _parsedPlan = plan;
        _errors = const [];
      });
    } on PlanValidationException catch (e) {
      setState(() {
        _parsedPlan = null;
        _errors = e.errors;
      });
    }
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
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      _showSnack('Datei konnte nicht gelesen werden.');
      return;
    }
    try {
      // Setzt den Text → löst über den Listener die Validierung aus.
      _jsonController.text = utf8.decode(bytes);
    } on FormatException {
      _showSnack('Datei ist keine gültige UTF-8-Textdatei.');
    }
  }

  /// Zeigt ein Popup mit den Beispiel-Vorlagen aus dem GitHub-Repository
  /// (Liste wird live abgerufen, nichts ist in der App gebündelt) und
  /// lädt den Inhalt der gewählten Datei ins Textfeld.
  Future<void> _pickTemplate() async {
    final template = await showModalBottomSheet<WorkoutTemplateRef>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _TemplatePickerSheet(repository: widget.templateRepository),
    );
    if (template == null || !mounted) {
      return;
    }
    try {
      final content = await widget.templateRepository.fetchContent(template);
      _jsonController.text = content;
    } on Object {
      if (mounted) {
        _showSnack(
            'Vorlage konnte nicht geladen werden. Internetverbindung prüfen.');
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Öffnet die Bearbeiten-Maske für den bereits geparsten Plan und
  /// schreibt das Ergebnis als formatiertes JSON zurück ins Textfeld –
  /// die bestehende Live-Validierung übernimmt den Rest.
  Future<void> _editPlan() async {
    final plan = _parsedPlan;
    if (plan == null) {
      return;
    }
    FocusScope.of(context).unfocus();
    final edited = await showPlanEditorDialog(context, plan);
    if (edited == null) {
      return;
    }
    _jsonController.text =
        const JsonEncoder.withIndent('  ').convert(edited.toJson());
  }

  String _exerciseLine(Exercise ex) => ex.type == ExerciseType.reps
      ? '• ${ex.name}: ${ex.sets} × ${ex.reps} Wdh.'
          '${ex.weightKg > 0 ? ' à ${ex.weightKg} kg' : ''}'
      : '• ${ex.name}: ${ex.sets} × ${ex.durationSeconds} Sek.';

  /// Zeigt die vollständige Fehlerliste in einem Popup.
  void _showErrorDetails() {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ungültiges JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final error in _errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• $error',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  /// Vorschau-Popup mit dem geparsten Plan; übernimmt nach Bestätigung.
  Future<void> _confirmAndApply() async {
    final plan = _parsedPlan;
    if (plan == null) {
      return;
    }
    // Soft-Limit-Hinweis direkt im Popup, statt als zweiter Dialog.
    final existing = await widget.storage.loadPlans();
    final overLimit = existing.length >= StorageService.softPlanLimit;
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Plan übernehmen?'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.workoutTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '${plan.exercises.length} Übungen · ${plan.totalSets} Sätze',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final ex in plan.exercises)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(_exerciseLine(ex),
                                style: theme.textTheme.bodyLarge),
                          ),
                      ],
                    ),
                  ),
                ),
                if (overLimit) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Du hast bereits ${existing.length} Pläne. Nicht mehr '
                    'genutzte kannst du auf dem Startbildschirm löschen.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen', style: TextStyle(fontSize: 18)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Übernehmen', style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await widget.storage.addPlan(plan);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasInput = _jsonController.text.trim().isNotEmpty;
    final valid = _parsedPlan != null;
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
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickTemplate,
              icon: const Icon(Icons.auto_awesome, size: 28),
              label: const Text('Beispiel-Workout laden'),
            ),
            const SizedBox(height: 20),
            Text('… oder JSON einfügen', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _jsonController,
              minLines: 5,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{ "workout_title": "...", "exercises": [ ... ] }',
              ),
            ),
            const SizedBox(height: 10),
            if (hasInput) _buildStatus(theme, valid),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: valid ? _confirmAndApply : null,
              icon: const Icon(Icons.check, size: 28),
              label: const Text('Plan übernehmen'),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: () => openExternalUrl(workoutTemplatesUrl),
                icon: const Icon(Icons.open_in_new, size: 20),
                label: const Text('Beispiel-Vorlagen & Format auf GitHub'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kompakte Statuszeile unter dem Textfeld (Ergebnis der Live-Prüfung).
  Widget _buildStatus(ThemeData theme, bool valid) {
    if (valid) {
      final plan = _parsedPlan!;
      return Row(
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${plan.workoutTitle} · ${plan.exercises.length} Übungen · '
              '${plan.totalSets} Sätze',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          IconButton(
            onPressed: _editPlan,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Übungen bearbeiten',
            color: theme.colorScheme.primary,
          ),
        ],
      );
    }
    return InkWell(
      onTap: _showErrorDetails,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                color: theme.colorScheme.error, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Noch kein gültiger Plan – Details ansehen',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.error, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Bottom-Sheet-Liste der Beispiel-Vorlagen. Startet den Abruf selbst in
/// [initState] statt eine von außen übergebene Future zu verwenden – so
/// entsteht keine Lücke zwischen Future-Erzeugung und FutureBuilder-
/// Subscription (sonst könnte ein schnell fehlschlagender Request als
/// unbehandelter Fehler auffallen, bevor das Sheet überhaupt aufgebaut ist).
class _TemplatePickerSheet extends StatefulWidget {
  const _TemplatePickerSheet({required this.repository});

  final TemplateRepository repository;

  @override
  State<_TemplatePickerSheet> createState() => _TemplatePickerSheetState();
}

class _TemplatePickerSheetState extends State<_TemplatePickerSheet> {
  late final Future<List<WorkoutTemplateRef>> _templatesFuture =
      widget.repository.listTemplates();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<List<WorkoutTemplateRef>>(
          future: _templatesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    'Vorlagen konnten nicht geladen werden.\n'
                    'Internetverbindung prüfen.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              );
            }
            final templates = snapshot.data!;
            return ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Beispiel-Workout laden',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Direkt aus dem FlexiPlan-Repository auf GitHub.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: templates.length,
                      itemBuilder: (context, i) {
                        final t = templates[i];
                        return ListTile(
                          leading: const Icon(Icons.fitness_center),
                          title: Text(t.displayName,
                              style: const TextStyle(fontSize: 18)),
                          onTap: () => Navigator.of(context).pop(t),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
