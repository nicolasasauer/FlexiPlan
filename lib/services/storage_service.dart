/// Persistente, update-resistente Speicherung (Lastenheft V1.2,
/// Abschnitt 3.2) auf Basis von shared_preferences.
///
/// Jede Session trägt ein data_version-Attribut; [migrateSession] hebt
/// Alt-Daten beim Laden verlustfrei auf das aktuelle Schema an.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/workout_plan.dart';
import '../models/workout_session.dart';

class StorageService {
  static const String _planKey = 'flexiplan_active_plan';
  static const String _sessionsKey = 'flexiplan_sessions';

  /// Aktuelle Schema-Version für neu geschriebene Sessions.
  static const int currentDataVersion = 1;

  // ---------------------------------------------------------------------
  // Aktiver Trainingsplan
  // ---------------------------------------------------------------------

  Future<void> saveActivePlan(WorkoutPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_planKey, jsonEncode(plan.toJson()));
  }

  Future<WorkoutPlan?> loadActivePlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_planKey);
    if (raw == null) {
      return null;
    }
    try {
      return WorkoutPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Defekter Datensatz: nicht crashen, Plan gilt als nicht vorhanden.
      return null;
    }
  }

  Future<void> clearActivePlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_planKey);
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
