/// Persistente, update-resistente Speicherung (Lastenheft V1.2,
/// Abschnitt 3.2) auf Basis von shared_preferences.
///
/// Jede Session trägt ein data_version-Attribut; [migrateSession] hebt
/// Alt-Daten beim Laden verlustfrei auf das aktuelle Schema an.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/stored_plan.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../utils/uuid.dart';

class StorageService {
  /// Alter Single-Plan-Key (Versionen <= 0.2.x); wird beim ersten Laden
  /// verlustfrei in die Plan-Bibliothek migriert.
  static const String _legacyPlanKey = 'flexiplan_active_plan';
  static const String _plansKey = 'flexiplan_plans';
  static const String _selectedPlanIdKey = 'flexiplan_selected_plan_id';
  static const String _sessionsKey = 'flexiplan_sessions';

  /// Aktuelle Schema-Version für neu geschriebene Sessions.
  static const int currentDataVersion = 1;

  /// Soft-Limit der Plan-Bibliothek: Ab dieser Anzahl warnt der Import,
  /// blockiert aber nicht.
  static const int softPlanLimit = 20;

  static const String _soundKey = 'flexiplan_sound_enabled';

  /// Gemeinsamer Schalter für Timer-Töne, Haptik und Sprachansagen im
  /// Workout (Default: an).
  Future<bool> loadSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundKey) ?? true;
  }

  Future<void> saveSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, enabled);
  }

  // ---------------------------------------------------------------------
  // Plan-Bibliothek
  // ---------------------------------------------------------------------

  /// Lädt alle gespeicherten Pläne (Import-Reihenfolge). Ein noch
  /// vorhandener Alt-Datensatz aus der Single-Plan-Ära wird dabei einmalig
  /// und verlustfrei in die Bibliothek überführt.
  Future<List<StoredPlan>> loadPlans() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyPlan(prefs);
    final raw = prefs.getStringList(_plansKey) ?? const <String>[];
    final plans = <StoredPlan>[];
    for (final entry in raw) {
      try {
        plans.add(
            StoredPlan.fromJson(jsonDecode(entry) as Map<String, dynamic>));
      } on Object {
        // Defekten Eintrag überspringen statt die Bibliothek zu verlieren.
        continue;
      }
    }
    return plans;
  }

  /// Fügt einen Plan hinzu und wählt ihn als aktiven Plan aus.
  Future<StoredPlan> addPlan(WorkoutPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = StoredPlan(
      id: generateUuidV4(),
      importedAt: DateTime.now().toUtc(),
      plan: plan,
    );
    final list = prefs.getStringList(_plansKey) ?? <String>[];
    list.add(jsonEncode(stored.toJson()));
    await prefs.setStringList(_plansKey, list);
    await prefs.setString(_selectedPlanIdKey, stored.id);
    return stored;
  }

  /// Entfernt einen Plan aus der Bibliothek. Die Trainingshistorie bleibt
  /// unberührt (Sessions speichern eigene Schnappschüsse). War der Plan
  /// ausgewählt, wird der zuletzt importierte verbleibende Plan aktiv.
  Future<void> deletePlan(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final plans = await loadPlans();
    plans.removeWhere((p) => p.id == id);
    await prefs.setStringList(
        _plansKey, plans.map((p) => jsonEncode(p.toJson())).toList());
    if (prefs.getString(_selectedPlanIdKey) == id) {
      if (plans.isEmpty) {
        await prefs.remove(_selectedPlanIdKey);
      } else {
        await prefs.setString(_selectedPlanIdKey, plans.last.id);
      }
    }
  }

  Future<void> selectPlan(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedPlanIdKey, id);
  }

  /// Liefert den aktuell ausgewählten Plan. Zeigt die gespeicherte Auswahl
  /// ins Leere (z. B. nach Löschung), fällt sie auf den zuletzt
  /// importierten Plan zurück.
  Future<StoredPlan?> loadSelectedPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final plans = await loadPlans();
    if (plans.isEmpty) {
      return null;
    }
    final selectedId = prefs.getString(_selectedPlanIdKey);
    for (final p in plans) {
      if (p.id == selectedId) {
        return p;
      }
    }
    await prefs.setString(_selectedPlanIdKey, plans.last.id);
    return plans.last;
  }

  Future<void> _migrateLegacyPlan(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyPlanKey);
    if (raw == null) {
      return;
    }
    try {
      final plan =
          WorkoutPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final stored = StoredPlan(
        id: generateUuidV4(),
        importedAt: DateTime.now().toUtc(),
        plan: plan,
      );
      final list = prefs.getStringList(_plansKey) ?? <String>[];
      list.add(jsonEncode(stored.toJson()));
      await prefs.setStringList(_plansKey, list);
      await prefs.setString(_selectedPlanIdKey, stored.id);
    } on Object {
      // Defekter Alt-Datensatz: nichts zu migrieren.
    }
    await prefs.remove(_legacyPlanKey);
  }

  // ---------------------------------------------------------------------
  // Session-Historie
  // ---------------------------------------------------------------------

  Future<void> addSession(WorkoutSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_sessionsKey) ?? <String>[];
    list.add(jsonEncode(session.toJson()));
    await prefs.setStringList(_sessionsKey, list);
  }

  /// Lädt alle Sessions, migriert Alt-Daten und sortiert absteigend
  /// nach Datum (neueste zuerst). Defekte Einträge werden übersprungen.
  Future<List<WorkoutSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_sessionsKey) ?? <String>[];
    final sessions = <WorkoutSession>[];
    for (final raw in list) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        sessions.add(WorkoutSession.fromJson(migrateSession(map)));
      } on Object {
        // Defekten Eintrag überspringen statt die ganze Historie zu
        // verlieren.
        continue;
      }
    }
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions;
  }

  /// Letzte geschaffte Leistung je Übungsname (Progression V1): der
  /// zuletzt abgeschlossene Satz aus der neuesten Session, die die Übung
  /// enthält. Verknüpfung bewusst über den Namen – Übungen haben keine
  /// planübergreifende ID.
  Future<Map<String, ({SetLog log, DateTime date})>> loadLastPerformances(
      Set<String> exerciseNames) async {
    final sessions = await loadSessions(); // neueste zuerst
    final result = <String, ({SetLog log, DateTime date})>{};
    for (final session in sessions) {
      for (final exercise in session.completedExercises) {
        if (!exerciseNames.contains(exercise.exerciseName) ||
            result.containsKey(exercise.exerciseName)) {
          continue;
        }
        final completed = exercise.setsLogged
            .where((s) => s.status == SetStatus.completed)
            .toList();
        if (completed.isEmpty) {
          continue;
        }
        result[exercise.exerciseName] =
            (log: completed.last, date: session.date);
      }
      if (result.length == exerciseNames.length) {
        break;
      }
    }
    return result;
  }

  /// Exportiert die gesamte Historie als strukturierten JSON-String
  /// (Basis für flexiplan_backup.json).
  Future<String> exportHistoryJson() async {
    final sessions = await loadSessions();
    final payload = <String, dynamic>{
      'data_version': currentDataVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  // ---------------------------------------------------------------------
  // Schema-Migration
  // ---------------------------------------------------------------------

  /// Migrationsroutine: prüft data_version eines Roh-Datensatzes und
  /// transformiert ihn verlustfrei in das aktuelle Zielschema.
  Map<String, dynamic> migrateSession(Map<String, dynamic> raw) {
    final data = Map<String, dynamic>.from(raw);

    // Datensätze ohne Versionsattribut stammen aus Vor-Releases und
    // entsprechen inhaltlich Version 1.
    if (data['data_version'] is! int) {
      data['data_version'] = 1;
    }

    // Zukünftige Migrationen werden hier sequenziell ergänzt, z. B.:
    // if (data['data_version'] == 1) { ...; data['data_version'] = 2; }

    return data;
  }
}
