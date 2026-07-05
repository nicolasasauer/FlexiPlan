import 'package:flutter/material.dart';

import '../app_links.dart';
import '../models/workout_plan.dart';
import '../services/storage_service.dart';
import 'history_screen.dart';
import 'import_screen.dart';
import 'workout_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WorkoutPlan? _activePlan;
  int _sessionCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final plan = await widget.storage.loadActivePlan();
    final sessions = await widget.storage.loadSessions();
    if (!mounted) {
      return;
    }
    setState(() {
      _activePlan = plan;
      _sessionCount = sessions.length;
      _loading = false;
    });
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
    final plan = _activePlan;
    if (plan == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkoutScreen(plan: plan, storage: widget.storage),
      ),
    );
    await _refresh();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HistoryScreen(storage: widget.storage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlexiPlan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.code, size: 28),
            tooltip: 'Open Source auf GitHub',
            onPressed: () => openExternalUrl(gitHubRepoUrl),
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
                    onPressed: _activePlan == null ? null : _startWorkout,
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
    final plan = _activePlan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: plan == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kein Plan geladen',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Importiere einen Trainingsplan als JSON, um zu '
                    'starten.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aktiver Plan', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Text(plan.workoutTitle,
                      style: theme.textTheme.headlineSmall),
                  if (plan.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(plan.description, style: theme.textTheme.bodyLarge),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '${plan.exercises.length} Übungen · '
                    '${plan.totalSets} Sätze',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
      ),
    );
  }
}
