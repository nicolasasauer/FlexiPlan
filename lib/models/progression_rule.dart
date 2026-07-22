/// Optionale Auto-Steigerung pro Übung (Progression V2): schlägt beim
/// nächsten Workout etwas mehr vor als zuletzt geschafft. Pro Übungsname
/// gespeichert (App-Einstellung, nicht im Import-JSON), standardmäßig aus.
///
/// Reine Datenklasse + reine Berechnungsfunktion – ohne Flutter-/Storage-
/// Abhängigkeit, damit die Logik ohne Widgets testbar bleibt.
library;

enum ProgressionType { none, weight, reps }

class ProgressionRule {
  const ProgressionRule({required this.type, required this.step});

  final ProgressionType type;

  /// kg bei [ProgressionType.weight], Anzahl bei [ProgressionType.reps].
  final double step;

  static const ProgressionRule none =
      ProgressionRule(type: ProgressionType.none, step: 0);

  bool get isActive => type != ProgressionType.none;

  /// Anzeige-Label für Dialog und Header.
  String get label {
    switch (type) {
      case ProgressionType.none:
        return 'Aus';
      case ProgressionType.weight:
        final s = step % 1 == 0 ? step.toInt().toString() : step.toString();
        return '+$s kg pro Einheit';
      case ProgressionType.reps:
        return '+${step.toInt()} Wdh. pro Einheit';
    }
  }

  /// Kurzform ("+2,5 kg" / "+1 Wdh.") für die kompakte Header-Anzeige.
  String get shortLabel {
    switch (type) {
      case ProgressionType.none:
        return '';
      case ProgressionType.weight:
        final s = step % 1 == 0 ? step.toInt().toString() : step.toString();
        return '+$s kg';
      case ProgressionType.reps:
        return '+${step.toInt()} Wdh.';
    }
  }

  factory ProgressionRule.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    final type = ProgressionType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => ProgressionType.none,
    );
    return ProgressionRule(
      type: type,
      step: (json['step'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'type': type.name, 'step': step};

  @override
  bool operator ==(Object other) =>
      other is ProgressionRule && other.type == type && other.step == step;

  @override
  int get hashCode => Object.hash(type, step);
}

/// Vorgeschlagener Startwert für den Log-Screen einer reps-Übung.
class SuggestedStart {
  const SuggestedStart({
    required this.reps,
    required this.weightKg,
    required this.bumped,
  });

  final int reps;
  final double weightKg;

  /// true, wenn die Progression den Wert über die letzte Leistung gehoben
  /// hat (steuert die „↗"-Anzeige).
  final bool bumped;
}

/// Reine Berechnung des Startwert-Vorschlags (Progression V1 + V2):
/// Basis ist die zuletzt geschaffte Leistung (V1), bei aktiver Regel und
/// vorhandener Historie um [ProgressionRule.step] erhöht (V2). Ohne
/// Historie gilt die Plan-Vorgabe ohne Steigerung.
SuggestedStart suggestStart({
  required ProgressionRule rule,
  required bool bodyweight,
  required int planReps,
  required double planWeight,
  int? lastReps,
  double? lastWeight,
}) {
  final hasLast = lastReps != null;
  var reps = hasLast && lastReps > 0 ? lastReps : planReps;
  var weight = bodyweight ? 0.0 : (hasLast ? (lastWeight ?? 0) : planWeight);
  var bumped = false;

  if (rule.isActive && hasLast) {
    if (rule.type == ProgressionType.weight && !bodyweight) {
      weight += rule.step;
      bumped = true;
    } else if (rule.type == ProgressionType.reps) {
      reps += rule.step.toInt();
      bumped = true;
    }
  }
  return SuggestedStart(reps: reps, weightKg: weight, bumped: bumped);
}
