import 'package:flexiplan/widgets/sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Der Sparkline-Painter darf mit beliebigen Wertreihen (auch flach oder
/// leer) rendern, ohne zu werfen – die Screen-Logik zeigt ihn ohnehin
/// erst ab zwei Sessions.
void main() {
  Future<void> pumpWith(WidgetTester tester, List<double> values) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: Sparkline(values: values, color: Colors.green),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('rendert eine steigende Reihe ohne Fehler', (tester) async {
    await pumpWith(tester, [20, 22.5, 25, 27.5]);
    expect(find.byType(Sparkline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flache Reihe (span 0) wirft nicht', (tester) async {
    await pumpWith(tester, [10, 10, 10]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('degenerierte Reihen (leer / ein Punkt) werfen nicht',
      (tester) async {
    await pumpWith(tester, const []);
    expect(tester.takeException(), isNull);
    await pumpWith(tester, const [5]);
    expect(tester.takeException(), isNull);
  });
}
