import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_links.dart';
import '../models/stored_plan.dart';
import '../models/workout_plan.dart';
import '../services/reminder_service.dart';
import '../services/storage_service.dart';
import 'history_screen.dart';
import 'import_screen.dart';
import 'reminder_screen.dart';
import 'workout_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ReminderService _reminders = ReminderService();

  List<StoredPlan> _plans = const [];
  StoredPlan? _selected;
  int _sessionCount = 0;
  bool _loading = true;

  /// Aufklapp-Zustände der Plan-Karte: Liste aller Pläne bzw.
  /// Übungs-Vorschau des aktiven Plans. Zugeklappt sieht die Karte aus
  /// wie in der Single-Plan-Version – der Home-Screen bleibt minimal.
  bool _showPlanList = false;
  bool _showExercises = false;

  /// Fortsetzen-Dialog für unterbrochene Workouts nur einmal anbieten.
  bool _draftPromptShown = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final plans = await widget.storage.loadPlans();
    final selected = await widget.storage.loadSelectedPlan();
    final sessions = await widget.storage.loadSessions();
    final draft = await widget.storage.loadWorkoutDraft();
    if (!mounted) {
      return;
    }
    setState(() {
      _plans = plans;
      _selected = selected;
      _sessionCount = sessions.length;
      _loading = false;
      if (plans.length <= 1) {
        _showPlanList = false;
      }
    });
    if (draft != null && !_draftPromptShown) {
      _draftPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _askResumeDraft(draft);
        }
      });
    }
  }

  /// App-Kill-Schutz: bietet an, ein unterbrochenes Workout fortzusetzen.
  Future<void> _askResumeDraft(Map<String, dynamic> draft) async {
    WorkoutPlan plan;
    int loggedSets;
    try {
      plan = WorkoutPlan.fromJson(draft['plan'] as Map<String, dynamic>);
      loggedSets = (draft['logs'] as List<dynamic>)
          .fold<int>(0, (sum, ex) => sum + (ex as List<dynamic>).length);
    } on Object {
      // Defekter Entwurf: still entsorgen.
      await widget.storage.clearWorkoutDraft();
      return;
    }
    if (!mounted) {
      return;
    }
    final resume = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout fortsetzen?'),
        content: Text('„${plan.workoutTitle}" wurde unterbrochen '
            '($loggedSets von ${plan.totalSets} Sätzen geloggt). '
            'Möchtest du weitermachen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Verwerfen',
                style: TextStyle(fontSize: 18, color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child:
                const Text('Fortsetzen', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    if (resume != true) {
      await widget.storage.clearWorkoutDraft();
      return;
    }
    final lastPerformances = await widget.storage.loadLastPerformances(
      plan.exercises.map((e) => e.name).toSet(),
    );
    final progressionRules = await widget.storage.loadProgressionRules();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkoutScreen(
          plan: plan,
          storage: widget.storage,
          lastPerformances: lastPerformances,
          progressionRules: progressionRules,
          resumeDraft: draft,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openImport() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ImportScreen(storage: widget.storage),
      ),
    );
    if (imported == true) {
      await _refresh();
    }
  }

  Future<void> _startWorkout() async {
    final selected = _selected;
    if (selected == null) {
      return;
    }
    // Progression V1/V2: letzte Leistungen und Steigerungs-Regeln vor dem
    // Start laden, damit die Startwerte ab dem ersten Satz stimmen.
    final lastPerformances = await widget.storage.loadLastPerformances(
      selected.plan.exercises.map((e) => e.name).toSet(),
    );
    final progressionRules = await widget.storage.loadProgressionRules();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkoutScreen(
          plan: selected.plan,
          storage: widget.storage,
          lastPerformances: lastPerformances,
          progressionRules: progressionRules,
        ),
      ),
    );
    await _refresh();
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'FlexiPlan',
      applicationVersion: appVersion,
      applicationLegalese: '© 2026 Nicolas Sauer · MIT-Lizenz',
      children: [
        const SizedBox(height: 16),
        const Text('Minimalistischer, lokaler Workout-Begleiter. '
            'Keine Cloud, kein Konto, keine Datenerhebung.'),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => openExternalUrl(gitHubRepoUrl),
          icon: const Icon(Icons.code, size: 22),
          label: const Text('Quellcode auf GitHub'),
        ),
      ],
    );
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HistoryScreen(storage: widget.storage),
      ),
    );
  }

  Future<void> _selectPlan(StoredPlan plan) async {
    await widget.storage.selectPlan(plan.id);
    // Geplante Erinnerungen nennen den aktiven Plan – nach dem Wechsel
    // mit dem neuen Titel neu einplanen (No-op, wenn deaktiviert).
    await _reminders.reapply(planTitle: plan.plan.workoutTitle);
    if (!mounted) {
      return;
    }
    setState(() {
      _selected = plan;
      _showPlanList = false;
      _showExercises = false;
    });
  }

  /// Kopiert das Import-JSON des Plans in die Zwischenablage – damit
  /// lassen sich gespeicherte Workouts teilen oder weiterbearbeiten.
  Future<void> _copyPlanJson(StoredPlan stored) async {
    final json =
        const JsonEncoder.withIndent('  ').convert(stored.plan.toJson());
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('„${stored.plan.workoutTitle}" als JSON kopiert.'),
      ),
    );
  }

  Future<void> _confirmDeletePlan(StoredPlan stored) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Plan löschen?'),
        content: Text('„${stored.plan.workoutTitle}" wird aus deiner '
            'Bibliothek entfernt. Deine Trainingshistorie bleibt '
            'unberührt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen',
                style: TextStyle(fontSize: 18, color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.storage.deletePlan(stored.id);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlexiPlan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, size: 28),
            tooltip: 'Trainings-Erinnerung',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ReminderScreen(
                  reminders: _reminders,
                  storage: widget.storage,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.code, size: 28),
            tooltip: 'Open Source auf GitHub',
            onPressed: () => openExternalUrl(gitHubRepoUrl),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 28),
            tooltip: 'Über FlexiPlan',
            onPressed: _showAbout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildPlanCard(theme),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _selected == null ? null : _startWorkout,
                    icon: const Icon(Icons.play_arrow, size: 32),
                    label: const Text('Workout starten'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _openImport,
                    icon: const Icon(Icons.file_download_outlined, size: 28),
                    label: const Text('Trainingsplan importieren'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _openHistory,
                    icon: const Icon(Icons.history, size: 28),
                    label: Text('Verlauf ($_sessionCount Sessions)'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPlanCard(ThemeData theme) {
    final selected = _selected;
    if (selected == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kein Plan geladen', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Importiere einen Trainingsplan als JSON, um zu starten.',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    final plan = selected.plan;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kopfzeile: Titel + Pfeil öffnet die Plan-Bibliothek.
            InkWell(
              onTap: () => setState(() {
                _showPlanList = !_showPlanList;
                _showExercises = false;
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Aktiver Plan',
                              style: theme.textTheme.labelLarge),
                          const SizedBox(height: 8),
                          Text(plan.workoutTitle,
                              style: theme.textTheme.headlineSmall),
                        ],
                      ),
                    ),
                    Icon(
                      _showPlanList ? Icons.expand_less : Icons.expand_more,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (_showPlanList)
              _buildPlanList(theme)
            else
              _buildPlanDetails(theme, plan),
          ],
        ),
      ),
    );
  }

  /// Zugeklappte Ansicht: Beschreibung + Stats-Zeile; die Stats-Zeile
  /// klappt die Übungs-Vorschau des aktiven Plans auf.
  Widget _buildPlanDetails(ThemeData theme, WorkoutPlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child:
                Text(plan.description, style: theme.textTheme.bodyLarge),
          ),
        InkWell(
          onTap: () => setState(() => _showExercises = !_showExercises),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${plan.exercises.length} Übungen · '
                    '${plan.totalSets} Sätze',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Icon(
                  _showExercises ? Icons.expand_less : Icons.expand_more,
                  size: 24,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_showExercises)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
              ],
            ),
          ),
      ],
    );
  }

  /// Aufgeklappte Plan-Bibliothek: auswählen, JSON kopieren, löschen.
  Widget _buildPlanList(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Meine Pläne (${_plans.length}/${StorageService.softPlanLimit})',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          for (final stored in _plans)
            InkWell(
              onTap: () => _selectPlan(stored),
              child: Row(
                children: [
                  Icon(
                    stored.id == _selected?.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 26,
                    color: stored.id == _selected?.id
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        stored.plan.workoutTitle,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 24),
                    tooltip: 'JSON kopieren',
                    onPressed: () => _copyPlanJson(stored),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 24),
                    tooltip: 'Plan löschen',
                    color: Colors.redAccent,
                    onPressed: () => _confirmDeletePlan(stored),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
