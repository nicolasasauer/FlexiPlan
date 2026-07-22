import 'package:flexiplan/models/progression_rule.dart';
import 'package:flexiplan/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('suggestStart – Progression V1 (Basis)', () {
    test('ohne Historie gilt die Plan-Vorgabe, keine Steigerung', () {
      final s = suggestStart(
        rule: ProgressionRule.none,
        bodyweight: false,
        planReps: 10,
        planWeight: 20,
      );
      expect(s.reps, 10);
      expect(s.weightKg, 20);
      expect(s.bumped, isFalse);
    });

    test('mit Historie zählt die letzte Leistung', () {
      final s = suggestStart(
        rule: ProgressionRule.none,
        bodyweight: false,
        planReps: 10,
        planWeight: 20,
        lastReps: 12,
        lastWeight: 25,
      );
      expect(s.reps, 12);
      expect(s.weightKg, 25);
      expect(s.bumped, isFalse);
    });
  });

  group('suggestStart – Progression V2 (Auto-Steigerung)', () {
    test('Gewichts-Regel hebt das Gewicht über die letzte Leistung', () {
      final s = suggestStart(
        rule: const ProgressionRule(type: ProgressionType.weight, step: 2.5),
        bodyweight: false,
        planReps: 10,
        planWeight: 20,
        lastReps: 10,
        lastWeight: 25,
      );
      expect(s.weightKg, 27.5);
      expect(s.reps, 10);
      expect(s.bumped, isTrue);
    });

    test('Wiederholungs-Regel hebt die Wdh.', () {
      final s = suggestStart(
        rule: const ProgressionRule(type: ProgressionType.reps, step: 1),
        bodyweight: false,
        planReps: 10,
        planWeight: 20,
        lastReps: 12,
        lastWeight: 25,
      );
      expect(s.reps, 13);
      expect(s.weightKg, 25);
      expect(s.bumped, isTrue);
    });

    test('ohne Historie wird NICHT gesteigert (kein Basiswert)', () {
      final s = suggestStart(
        rule: const ProgressionRule(type: ProgressionType.weight, step: 2.5),
        bodyweight: false,
        planReps: 10,
        planWeight: 20,
      );
      expect(s.weightKg, 20);
      expect(s.bumped, isFalse);
    });

    test('Gewichts-Regel bei Eigengewicht wird ignoriert', () {
      final s = suggestStart(
        rule: const ProgressionRule(type: ProgressionType.weight, step: 2.5),
        bodyweight: true,
        planReps: 10,
        planWeight: 0,
        lastReps: 15,
        lastWeight: 0,
      );
      expect(s.weightKg, 0);
      expect(s.bumped, isFalse);
    });

    test('Wiederholungs-Regel greift auch bei Eigengewicht', () {
      final s = suggestStart(
        rule: const ProgressionRule(type: ProgressionType.reps, step: 2),
        bodyweight: true,
        planReps: 10,
        planWeight: 0,
        lastReps: 15,
        lastWeight: 0,
      );
      expect(s.reps, 17);
      expect(s.bumped, isTrue);
    });
  });

  group('ProgressionRule Labels & Roundtrip', () {
    test('Labels', () {
      expect(ProgressionRule.none.label, 'Aus');
      expect(const ProgressionRule(type: ProgressionType.weight, step: 2.5)
          .label, '+2.5 kg pro Einheit');
      expect(const ProgressionRule(type: ProgressionType.reps, step: 1)
          .shortLabel, '+1 Wdh.');
    });

    test('toJson/fromJson', () {
      const rule = ProgressionRule(type: ProgressionType.weight, step: 5);
      expect(ProgressionRule.fromJson(rule.toJson()), rule);
    });
  });

  group('StorageService – Progressions-Regeln', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('speichern, laden und wieder entfernen (Aus)', () async {
      final storage = StorageService();
      expect(await storage.loadProgressionRules(), isEmpty);

      await storage.saveProgressionRule('Kniebeugen',
          const ProgressionRule(type: ProgressionType.weight, step: 2.5));
      await storage.saveProgressionRule('Liegestütze',
          const ProgressionRule(type: ProgressionType.reps, step: 1));

      var rules = await storage.loadProgressionRules();
      expect(rules.length, 2);
      expect(rules['Kniebeugen']!.type, ProgressionType.weight);
      expect(rules['Liegestütze']!.step, 1);

      // "Aus" entfernt den Eintrag wieder.
      await storage.saveProgressionRule('Kniebeugen', ProgressionRule.none);
      rules = await storage.loadProgressionRules();
      expect(rules.containsKey('Kniebeugen'), isFalse);
      expect(rules.length, 1);
    });
  });
}
