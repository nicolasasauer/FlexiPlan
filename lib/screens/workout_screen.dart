import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/progression_rule.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../services/native_feedback.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../utils/uuid.dart';
import 'summary_screen.dart';

enum _Phase { ready, timing, logging, resting }

/// Interaktiver Workout-Modus (Lastenheft 2.2): sequentielles Abarbeiten
/// von Übung zu Übung und Satz zu Satz, Satz-Bestätigungs-Screen mit
/// großen +/- Tasten, "Satz überspringen" mit Sicherheitsabfrage sowie
/// Belastungs- und Rest-Timer.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({
    super.key,
    required this.plan,
    required this.storage,
    this.lastPerformances = const {},
    this.progressionRules = const {},
    this.resumeDraft,
  });

  final WorkoutPlan plan;
  final StorageService storage;

  /// Letzte geschaffte Leistung je Übungsname (Progression V1): dient als
  /// Startwert-Vorschlag und "Zuletzt:"-Anzeige. Wird vom Aufrufer vor
  /// dem Start geladen, damit die Werte ab dem ersten Frame stimmen.
  final Map<String, ({SetLog log, DateTime date})> lastPerformances;

  /// Auto-Steigerungs-Regeln je Übungsname (Progression V2, opt-in).
  final Map<String, ProgressionRule> progressionRules;

  /// Zwischenstand eines unterbrochenen Workouts (App-Kill-Schutz);
  /// null = normaler Neustart des Workouts.
  final Map<String, dynamic>? resumeDraft;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late final DateTime _startTime;
  late final List<List<SetLog>> _logs;
  final SpeechService _speech = SpeechService();

  /// Mutable Kopie der Progressions-Regeln – kann im Workout per Zahnrad
  /// geändert werden.
  late final Map<String, ProgressionRule> _rules =
      Map.of(widget.progressionRules);

  /// true, wenn der aktuelle Startwert durch Progression über die letzte
  /// Leistung gehoben wurde (steuert die „↗"-Anzeige).
  bool _currentBumped = false;

  /// Gemeinsamer Schalter für Töne, Haptik und Ansagen (persistiert).
  bool _soundEnabled = true;

  int _exerciseIndex = 0;
  int _setNumber = 1;
  _Phase _phase = _Phase.ready;

  // Anpassbare Ist-Werte im Log-Screen.
  int _repsValue = 0;
  double _weightValue = 0;
  int _durationValue = 0;

  int _secondsRemaining = 0;
  Timer? _timer;

  /// Referenzuhr nach regulärem Ablauf des Belastungs-Timers: Sie führt
  /// den Timerstand sichtbar weiter (5 → 6 → 7 …), während der
  /// Eingabewert stabil bei der Vorgabe stehen bleibt. Wer die Übung
  /// länger hält, liest die tatsächliche Zeit einfach ab und stellt den
  /// Ist-Wert darauf ein – ohne Kopfrechnen. null = keine Uhr sichtbar.
  Timer? _overrunTimer;
  int? _overrunReferenceSeconds;
  bool _finishing = false;

  Exercise get _exercise => widget.plan.exercises[_exerciseIndex];

  bool get _isLastSetOfWorkout =>
      _exerciseIndex == widget.plan.exercises.length - 1 &&
      _setNumber == _exercise.sets;

  @override
  void initState() {
    super.initState();
    final draft = widget.resumeDraft;
    if (draft != null) {
      // Unterbrochenes Workout fortsetzen: Logs und Position aus dem
      // Entwurf wiederherstellen (defensive Casts – bei defektem Draft
      // greift der catch und startet normal).
      DateTime start;
      List<List<SetLog>> logs;
      var exerciseIndex = 0;
      var setNumber = 1;
      try {
        start = DateTime.parse(draft['start_time'] as String);
        logs = [
          for (final exLogs in draft['logs'] as List<dynamic>)
            [
              for (final raw in exLogs as List<dynamic>)
                SetLog.fromJson(raw as Map<String, dynamic>)
            ]
        ];
        exerciseIndex = draft['exercise_index'] as int;
        setNumber = draft['set_number'] as int;
      } on Object {
        start = DateTime.now();
        logs =
            List.generate(widget.plan.exercises.length, (_) => <SetLog>[]);
      }
      _startTime = start;
      _logs = logs;
      _exerciseIndex = exerciseIndex;
      _setNumber = setNumber;
    } else {
      _startTime = DateTime.now();
      _logs =
          List.generate(widget.plan.exercises.length, (_) => <SetLog>[]);
    }
    _setupCurrentSet();
    // Bildschirmsperre-Prävention (Lastenheft 3.1): Display bleibt während
    // des gesamten Workouts wach.
    NativeFeedback.keepScreenOn(true);
    // Ton-Einstellung laden, erst danach die erste Übung ansagen –
    // sonst spräche die Ansage, bevor der Schalter bekannt ist.
    widget.storage.loadSoundEnabled().then((enabled) {
      if (!mounted) {
        return;
      }
      setState(() => _soundEnabled = enabled);
      _announceExercise(first: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _overrunTimer?.cancel();
    _speech.stop();
    NativeFeedback.keepScreenOn(false);
    super.dispose();
  }

  /// Startet die Referenzuhr beim Vorgabewert. Sie läuft rein
  /// informativ bis zum Beenden/Überspringen des Satzes weiter und
  /// verändert den Eingabewert nie von selbst.
  void _startOverrunReference() {
    _overrunTimer?.cancel();
    _overrunReferenceSeconds = _exercise.durationSeconds;
    _overrunTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(
          () => _overrunReferenceSeconds = (_overrunReferenceSeconds ?? 0) + 1);
    });
  }

  void _stopOverrunReference() {
    _overrunTimer?.cancel();
    _overrunTimer = null;
    _overrunReferenceSeconds = null;
  }

  /// Sprachansage der aktuellen Übung (Lastenheft 2.4), z. B.
  /// "Nächste Übung: Kniebeugen, 3 Sätze à 15 Wiederholungen".
  void _announceExercise({bool first = false}) {
    if (!_soundEnabled) {
      return;
    }
    final ex = _exercise;
    final prefix = first ? 'Erste Übung' : 'Nächste Übung';
    final String load;
    if (ex.type == ExerciseType.time) {
      load = '${ex.sets} Sätze à ${ex.durationSeconds} Sekunden';
    } else {
      final weight = !ex.bodyweight && ex.weightKg > 0
          ? ' mit ${ex.weightKg % 1 == 0 ? ex.weightKg.toInt() : ex.weightKg} Kilo'
          : '';
      load = '${ex.sets} Sätze à ${ex.reps} Wiederholungen$weight';
    }
    _speech.speak('$prefix: ${ex.name}, $load.');
  }

  Future<void> _toggleSound() async {
    setState(() => _soundEnabled = !_soundEnabled);
    if (!_soundEnabled) {
      _speech.stop();
    }
    await widget.storage.saveSoundEnabled(_soundEnabled);
  }

  /// Akustischer Countdown (Lastenheft 2.4): Tick + Haptik in den letzten
  /// 3 Sekunden eines laufenden Timers.
  void _signalCountdownTick() {
    if (_soundEnabled && _secondsRemaining >= 1 && _secondsRemaining <= 3) {
      NativeFeedback.tick();
      HapticFeedback.mediumImpact();
    }
  }

  void _signalTimerEnd() {
    if (!_soundEnabled) {
      return;
    }
    NativeFeedback.end();
    HapticFeedback.heavyImpact();
  }

  /// Letzte Leistung dieser Übung, sofern sie zum Übungstyp passt
  /// (Reps-Übungen ignorieren zeitbasierte Alt-Sätze und umgekehrt).
  ({SetLog log, DateTime date})? get _lastPerformance {
    final last = widget.lastPerformances[_exercise.name];
    if (last == null) {
      return null;
    }
    final isTimeLog = last.log.durationActualSeconds != null;
    final matchesType =
        (_exercise.type == ExerciseType.time) == isTimeLog;
    return matchesType ? last : null;
  }

  void _setupCurrentSet() {
    final ex = _exercise;
    // Progression V1 (letzte Leistung als Startwert) + optional V2
    // (Auto-Steigerung); ohne Historie gilt die Plan-Vorgabe. Die
    // Timer-Dauer zeitbasierter Übungen bleibt bewusst die Plan-Vorgabe
    // (ein früher abgebrochener Satz soll das Ziel nicht senken).
    if (ex.type == ExerciseType.reps) {
      final last = _lastPerformance;
      final suggestion = suggestStart(
        rule: _rules[ex.name] ?? ProgressionRule.none,
        bodyweight: ex.bodyweight,
        planReps: ex.reps,
        planWeight: ex.weightKg,
        lastReps: last?.log.repsActual,
        lastWeight: last?.log.weightActualKg,
      );
      _repsValue = suggestion.reps;
      _weightValue = suggestion.weightKg;
      _currentBumped = suggestion.bumped;
    } else {
      _repsValue = 0;
      _weightValue = 0;
      _currentBumped = false;
    }
    _durationValue = ex.type == ExerciseType.time ? ex.durationSeconds : 0;
    _phase =
        ex.type == ExerciseType.time ? _Phase.ready : _Phase.logging;
  }

  /// Öffnet die Auto-Steigerungs-Einstellung für die aktuelle Übung.
  Future<void> _editProgression() async {
    final ex = _exercise;
    final current = _rules[ex.name] ?? ProgressionRule.none;
    final options = <ProgressionRule>[
      ProgressionRule.none,
      if (!ex.bodyweight)
        const ProgressionRule(type: ProgressionType.weight, step: 2.5),
      if (!ex.bodyweight)
        const ProgressionRule(type: ProgressionType.weight, step: 5),
      const ProgressionRule(type: ProgressionType.reps, step: 1),
      const ProgressionRule(type: ProgressionType.reps, step: 2),
    ];
    final theme = Theme.of(context);
    final chosen = await showDialog<ProgressionRule>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Progression: ${ex.name}'),
        children: [
          for (final option in options)
            ListTile(
              leading: Icon(
                option == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: option == current
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(option.label, style: const TextStyle(fontSize: 18)),
              onTap: () => Navigator.of(context).pop(option),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Schlägt beim nächsten Mal etwas mehr vor als zuletzt '
              'geschafft. Standard ist aus – der Wert bleibt jederzeit '
              'manuell anpassbar.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
    if (chosen == null) {
      return;
    }
    await widget.storage.saveProgressionRule(ex.name, chosen);
    if (!mounted) {
      return;
    }
    setState(() {
      if (chosen.isActive) {
        _rules[ex.name] = chosen;
      } else {
        _rules.remove(ex.name);
      }
      // Startwert der laufenden Übung sofort neu berechnen.
      _setupCurrentSet();
    });
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
    if (_soundEnabled) {
      NativeFeedback.start();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
          _durationValue = _exercise.durationSeconds;
          _phase = _Phase.logging;
        });
        _signalTimerEnd();
        // Wer nach dem Signal weitermacht, sieht die echte Zeit auf der
        // Referenzuhr weiterlaufen; der Eingabewert bleibt stabil bei
        // der Vorgabe (nur beim regulären Ablauf – nach "Satz vorzeitig
        // beenden" steht der Wert bereits exakt fest).
        _startOverrunReference();
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

  /// Persistiert den Zwischenstand mit der Position des NÄCHSTEN Satzes,
  /// damit ein Resume nach App-Kill nahtlos dort weitermacht – auch wenn
  /// der Prozess während der Satzpause stirbt.
  void _persistDraft() {
    var nextExercise = _exerciseIndex;
    var nextSet = _setNumber + 1;
    if (nextSet > _exercise.sets) {
      nextExercise += 1;
      nextSet = 1;
    }
    widget.storage.saveWorkoutDraft(<String, dynamic>{
      'start_time': _startTime.toIso8601String(),
      'plan': widget.plan.toJson(),
      'exercise_index': nextExercise,
      'set_number': nextSet,
      'logs': [
        for (final exLogs in _logs) [for (final log in exLogs) log.toJson()]
      ],
    });
  }

  void _logSet({required bool completed}) {
    // Ab jetzt ist der Ist-Wert final, die Referenzuhr verschwindet.
    _stopOverrunReference();
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
    _persistDraft();

    // Rest-Timer nur nach bestätigten Sätzen; übersprungene Sätze führen
    // direkt zum nächsten Satz.
    if (completed && ex.restDurationSeconds > 0) {
      _startRestTimer(ex.restDurationSeconds);
    } else {
      _advanceToNextSet();
    }
  }

  void _advanceToNextSet() {
    final exerciseChanges = _setNumber >= _exercise.sets;
    setState(() {
      if (_setNumber < _exercise.sets) {
        _setNumber += 1;
      } else {
        _exerciseIndex += 1;
        _setNumber = 1;
      }
      _setupCurrentSet();
    });
    if (exerciseChanges) {
      _announceExercise();
    }
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
    // Erst die Session sichern, dann den Entwurf entsorgen – so geht
    // selbst bei einem Crash dazwischen nichts verloren.
    await widget.storage.clearWorkoutDraft();
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
      // Bewusster Abbruch: Entwurf verwerfen (dokumentiertes Verhalten,
      // geloggte Sätze werden nicht gespeichert).
      await widget.storage.clearWorkoutDraft();
      if (!mounted) {
        return;
      }
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
          actions: [
            // Auto-Steigerung nur für Wiederholungs-Übungen sinnvoll.
            if (ex.type == ExerciseType.reps)
              IconButton(
                icon: const Icon(Icons.tune, size: 28),
                tooltip: 'Auto-Steigerung für diese Übung',
                onPressed: _editProgression,
              ),
            IconButton(
              icon: Icon(
                _soundEnabled ? Icons.volume_up : Icons.volume_off,
                size: 28,
              ),
              tooltip: _soundEnabled
                  ? 'Töne & Ansagen aus'
                  : 'Töne & Ansagen an',
              onPressed: _toggleSound,
            ),
          ],
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

  String _formatLastPerformance(({SetLog log, DateTime date}) last) {
    final local = last.date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(local.day)}.${two(local.month)}.';
    final log = last.log;
    if (log.durationActualSeconds != null) {
      return 'Zuletzt: ${log.durationActualSeconds} Sek. ($date)';
    }
    final weight = log.weightActualKg > 0
        ? ' à ${log.weightActualKg.toStringAsFixed(1)} kg'
        : '';
    return 'Zuletzt: ${log.repsActual} Wdh.$weight ($date)';
  }

  Widget _buildHeader(ThemeData theme, Exercise ex) {
    final last = _lastPerformance;
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
        if (last != null) ...[
          const SizedBox(height: 4),
          Text(
            _formatLastPerformance(last),
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        // Progression V2: transparenter Hinweis, wenn der Startwert über
        // die letzte Leistung angehoben wurde.
        if (_currentBumped) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.trending_up,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Auto-Steigerung: '
                '${(_rules[ex.name] ?? ProgressionRule.none).shortLabel}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        ],
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
        ] else ...[
          // Referenzuhr: führt nach regulärem Timer-Ablauf den Stand
          // sichtbar weiter, damit die tatsächlich gehaltene Zeit ohne
          // Kopfrechnen abgelesen und unten eingestellt werden kann.
          if (_overrunReferenceSeconds != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer, size: 22,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Läuft weiter: $_overrunReferenceSeconds Sek.',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _ValueStepper(
            label: 'Sekunden (Ist)',
            value: '$_durationValue',
            onDecrement: _durationValue >= 5
                ? () => setState(() => _durationValue -= 5)
                : null,
            onIncrement: () => setState(() => _durationValue += 5),
          ),
        ],
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
