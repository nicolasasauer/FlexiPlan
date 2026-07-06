/// Gespeicherter Trainingsplan in der lokalen Plan-Bibliothek.
///
/// Wrapper um [WorkoutPlan] mit stabiler, App-generierter ID: Der
/// `workout_title` aus dem Import-JSON ist Nutzertext und taugt nicht als
/// Kennung (Duplikate möglich). Das Import-Schema selbst (Lastenheft 4.1)
/// bleibt unverändert – ID und Importzeitpunkt existieren nur intern.
library;

import 'workout_plan.dart';

class StoredPlan {
  const StoredPlan({
    required this.id,
    required this.importedAt,
    required this.plan,
  });

  /// App-generierte UUID, unabhängig vom Planinhalt.
  final String id;

  /// Zeitpunkt des Imports (UTC), für eine stabile Sortierung.
  final DateTime importedAt;

  final WorkoutPlan plan;

  factory StoredPlan.fromJson(Map<String, dynamic> json) => StoredPlan(
        id: json['plan_id'] as String,
        importedAt: DateTime.parse(json['imported_at'] as String),
        plan: WorkoutPlan.fromJson(json['plan'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'plan_id': id,
        'imported_at': importedAt.toUtc().toIso8601String(),
        'plan': plan.toJson(),
      };
}
