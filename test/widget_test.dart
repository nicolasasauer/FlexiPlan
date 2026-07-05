import 'package:flexiplan/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App startet im Dark Mode mit Home-Screen',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const FlexiPlanApp());
    await tester.pumpAndSettle();

    // Grundgerüst vorhanden.
    expect(find.text('FlexiPlan'), findsOneWidget);
    expect(find.text('Workout starten'), findsOneWidget);
    expect(find.text('Trainingsplan importieren'), findsOneWidget);

    // Ohne Plan ist der Start-Button deaktiviert.
    // Hinweis: byType matcht ElevatedButton.icon nicht (private Subklasse),
    // daher byWidgetPredicate mit is-Check.
    final startButton = tester.widget<ElevatedButton>(
      find.byWidgetPredicate((w) => w is ElevatedButton),
    );
    expect(startButton.onPressed, isNull);

    // Dark Mode aktiv.
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.dark);
  });
}
