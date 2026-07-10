import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../services/native_feedback.dart';
import '../services/storage_service.dart';
import '../utils/uuid.dart';
import 'summary_screen.dart';

enum _Phase { ready, timing, logging, resting }

/// Interaktiver Workout-Modus (Lastenheft 2.2): sequentielles Abarbeiten
/// von Übung zu Übung und Satz zu Satz, Satz-Bestätigungs-Screen mit
/// großen +/- Tasten, "Satz überspringen" mit Sicherheitsabfrage sowie
/// Belastungs- und Rest-Timer.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.plan, required this.storage});

  final WorkoutPlan plan;
  final StorageService storage;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late final DateTime _startTime;
  late final List<List<SetLog>> _logs;

  int _exerciseIndex = 0;
  int _setNumber = 1;
  _Phase _phase = _Phase.ready;

  // Anpassbare Ist-Werte im Log-Screen.
  int _repsValue = 0;
  double _weightValue = 0;
  int _durationValue = 0;

  int _secondsRemaining = 0;
  Timer? _timer;
  bool _finishing = false;

  Exercise get _exercise => widget.plan.exercises[_exerciseIndex];

  bool get _isLastSetOfWorkout =>
      _exerciseIndex == widget.plan.exercises.length - 1 &&
      _setNumber == _exercise.sets;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _logs = List.generate(widget.plan.exercises.length, (_) => <SetLog>[]);
    _setupCurrentSet();
    // Bildschirmsperre-Prävention (Lastenheft 3.1): Display bleibt während
    // des gesamten Workouts wach.
    NativeFeedback.keepScreenOn(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    NativeFeedback.keepScreenOn(false);
    super.dispose();
  }

  /// Akustischer Countdown (Lastenheft 2.4): Tick + Haptik in den letzten
  /// 3 Sekunden eines laufenden Timers.
  void _signalCountdownTick() {
    if (_secondsRemaining >= 1 && _secondsRemaining <= 3) {
      NativeFeedback.tick();
      HapticFeedback.mediumImpact();
    }
  }

  void _signalTimerEnd() {
    NativeFeedback.end();
    HapticFeedback.heavyImpact();
  }

  void _setupCurrentSet() {
    final ex = _exercise;
    _repsValue = ex.type == ExerciseType.reps ? ex.reps : 0;
    _weightValue = ex.bodyweight ? 0 : ex.weightKg;
    _durationValue = ex.type == ExerciseType.time ? ex.durationSeconds : 0;
    _phase =
        ex.type == ExerciseType.time ? _Phase.ready : _Phase.logging;
  }

  // -----------------------------------------------------------------
  // Timer-Logik
  // -----------------------------------------------------------------

  void _startExerciseTimer() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.timing;
      _secondsRemaining = _exercise.durationSeconds;
    });
    NativeFeedback.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
          _durationValue = _exercise.durationSeconds;
          _phase = _Phase.logging;
        });
        _signalTimerEnd();
      } else {
        setState(() => _secondsRemaining -= 1);
        _signalCountdownTick();
      }
    });
  }

  /// Bricht den Belastungs-Timer vorzeitig ab und übernimmt die bereits
  /// verstrichene Zeit als Ist-Wert in den Log-Screen (dort per ±5s
  /// weiter anpassbar).
  void _stopExerciseTimerEarly() {
    _timer?.cancel();
    setState(() {
      _durationValue = _exercise.durationSeconds - _secondsRemaining;
      _phase = _Phase.logging;
    });
  }

  void _startRestTimer(int seconds) {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.resting;
      _secondsRemaining = seconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _signalTimerEnd();
        _advanceToNextSet();
      } else {
        setState(() => _secondsRemaining -= 1);
        _signalCountdownTick();
      }
    });
  }

  void _skipRest() {
    _timer?.cancel();
    _advanceToNextSet();
  }

  // -----------------------------------------------------------------
  // Ablaufsteuerung
  // -----------------------------------------------------------------

  void _logSet({required bool completed}) {
    final ex = _exercise;
    _logs[_exerciseIndex].add(
      SetLog(
        setNumber: _setNumber,
        status: completed ? SetStatus.completed : SetStatus.skipped,
        repsActual:
            completed && ex.type == ExerciseType.reps ? _repsValue : 0,
        weightActualKg:
            completed && ex.type == ExerciseType.reps ? _weightValue : 0,
        durationActualSeconds: completed && ex.type == ExerciseType.time
            ? _durationValue
            : null,
      ),
    );

    if (_isLastSetOfWorkout) {
      _finishWorkout();
      return;
    }

    // Rest-Timer nur nach bestätigten Sätzen; übersprungene Sätze führen
    // direkt zum nächsten Satz.
    if (completed && ex.restDurationSeconds > 0) {
      _startRestTimer(ex.restDurationSeconds);
    } else {
      _advanceToNextSet();
    }
  }

  void _advanceToNextSet() {
    setState(() {
      if (_setNumber < _exercise.sets) {
        _setNumber += 1;
      } else {
        _exerciseIndex += 1;
        _setNumber = 1;
      }
      _setupCurrentSet();
    });
  }

  Future<void> _confirmSkipSet() async {
    final ex = _exercise;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Satz $_setNumber überspringen?'),
        content: Text('Satz $_setNumber von ${ex.sets} („${ex.name}") '
            'wirklich überspringen? Er wird in der Historie als '
            '„übersprungen" markiert.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Überspringen',
                style: TextStyle(fontSize: 18, color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _logSet(completed: false);
    }
  }

  Future<void> _finishWorkout() async {
    if (_finishing) {
      return;
    }
    _finishing = true;
    _timer?.cancel();

    final durationMinutes =
        (DateTime.now().difference(_startTime).inSeconds / 60).ceil();
    final session = WorkoutSession(
      dataVersion: StorageService.currentDataVersion,
      sessionId: generateUuidV4(),
      date: _startTime.toUtc(),
      workoutTitle: widget.plan.workoutTitle,
      durationMinutes: durationMinutes,
      completedExercises: [
        for (var i = 0; i < widget.plan.exercises.length; i++)
          if (_logs[i].isNotEmpty)
            CompletedExercise(
              exerciseName: widget.plan.exercises[i].name,
              setsLogged: List.unmodifiable(_logs[i]),
            ),
      ],
    );

    await widget.storage.addSession(session);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SummaryScreen(session: session)),
    );
  }

  Future<void> _confirmAbort() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout beenden?'),
        content: const Text('Das laufende Workout wird abgebrochen. '
            'Bisher geloggte Sätze werden nicht gespeichert.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Weiter trainieren',
                style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Beenden',
                style: TextStyle(fontSize: 18, color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // -----------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ex = _exercise;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _confirmAbort();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Übung ${_exerciseIndex + 1}/${widget.plan.exercises.length} · '
            'Satz $_setNumber/${ex.sets}',
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (_phase) {
              _Phase.ready => _buildReadyView(theme, ex),
              _Phase.timing => _buildTimerView(
                  theme,
                  label: ex.name,
                  color: theme.colorScheme.primary,
                ),
              _Phase.logging => _buildLogView(theme, ex),
              _Phase.resting => _buildRestView(theme),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Exercise ex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ex.name, style: theme.textTheme.headlineMedium),
        if (ex.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(ex.description, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 8),
        Text(
          ex.type == ExerciseType.reps
              ? 'Vorgabe: ${ex.reps} Wdh.'
                  '${ex.weightKg > 0 ? ' à ${ex.weightKg} kg' : ''}'
              : 'Vorgabe: ${ex.durationSeconds} Sekunden',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.primary),
        ),
      ],
    );
  }

  Widget _buildReadyView(ThemeData theme, Exercise ex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme, ex),
        const Spacer(),
        Center(
          child: Text(
            '${ex.durationSeconds} Sek.',
            style: theme.textTheme.displayLarge,
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _startExerciseTimer,
          icon: const Icon(Icons.timer, size: 32),
          label: const Text('Timer starten'),
        ),
        const SizedBox(height: 12),
        _buildSkipButton(),
      ],
    );
  }

  Widget _buildTimerView(ThemeData theme,
      {required String label, required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center),
        const Spacer(),
        Center(
          child: Text(
            '$_secondsRemaining',
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: 120,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _stopExerciseTimerEarly,
          icon: const Icon(Icons.stop, size: 28),
          label: const Text('Satz vorzeitig beenden'),
        ),
      ],
    );
  }

  /// Vorschau auf den nächsten Satz bzw. die nächste Übung während der
  /// Satzpause. Der Rest-Timer läuft nie nach dem letzten Satz des
  /// Workouts, daher ist der Zugriff auf die Folgeübung hier sicher.
  String get _nextUpLabel {
    final ex = _exercise;
    if (_setNumber < ex.sets) {
      return '${ex.name} · Satz ${_setNumber + 1}/${ex.sets}';
    }
    final next = widget.plan.exercises[_exerciseIndex + 1];
    return next.name;
  }

  Widget _buildRestView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Satzpause',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center),
        const Spacer(),
        Center(
          child: Text(
            '$_secondsRemaining',
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: 120,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.secondary,
            ),
          ),
        ),
        const Spacer(),
        Text(
          'Als Nächstes: $_nextUpLabel',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.primary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _secondsRemaining += 30),
                icon: const Icon(Icons.more_time, size: 28),
                label: const Text('+30 Sek.'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: _skipRest,
                icon: const Icon(Icons.skip_next, size: 28),
                label: const Text('Pause überspringen'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Satz-Bestätigungs-Screen (Log-Screen) mit großen +/- Tasten.
  Widget _buildLogView(ThemeData theme, Exercise ex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme, ex),
        const Spacer(),
        if (ex.type == ExerciseType.reps) ...[
          _ValueStepper(
            label: 'Wiederholungen',
            value: '$_repsValue',
            onDecrement: _repsValue > 0
                ? () => setState(() => _repsValue -= 1)
                : null,
            onIncrement: () => setState(() => _repsValue += 1),
          ),
          // Bei reinen Eigengewichts-Übungen entfällt die Gewichtseingabe.
          if (!ex.bodyweight) ...[
            const SizedBox(height: 20),
            _ValueStepper(
              label: 'Gewicht (kg)',
              value: _weightValue.toStringAsFixed(1),
              onDecrement: _weightValue > 0
                  ? () => setState(() {
                        final next = _weightValue - 2.5;
                        _weightValue = next < 0 ? 0 : next;
                      })
                  : null,
              onIncrement: () => setState(() => _weightValue += 2.5),
            ),
          ],
        ] else
          _ValueStepper(
            label: 'Sekunden (Ist)',
            value: '$_durationValue',
            onDecrement: _durationValue >= 5
                ? () => setState(() => _durationValue -= 5)
                : null,
            onIncrement: () => setState(() => _durationValue += 5),
          ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _logSet(completed: true),
          icon: const Icon(Icons.check, size: 32),
          label: const Text('Satz beendet'),
        ),
        const SizedBox(height: 12),
        _buildSkipButton(),
      ],
    );
  }

  Widget _buildSkipButton() {
    return OutlinedButton.icon(
      onPressed: _confirmSkipSet,
      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
      icon: const Icon(Icons.skip_next, size: 28),
      label: const Text('Satz überspringen'),
    );
  }
}

/// Großflächiger +/- Regler ("Hands-sweaty-optimiert").
class _ValueStepper extends StatelessWidget {
  const _ValueStepper({
    required this.label,
    required this.value,
    required this.onIncrement,
    this.onDecrement,
  });

  final String label;
  final String value;
  final VoidCallback onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Text(label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StepperButton(
                  icon: Icons.remove,
                  onPressed: onDecrement,
                ),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _StepperButton(
                  icon: Icons.add,
                  onPressed: onIncrement,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 88,
      height: 88,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Icon(icon, size: 44, color: theme.colorScheme.onSurface),
      ),
    );
  }
}
