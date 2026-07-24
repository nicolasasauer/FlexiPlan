import 'package:flexiplan/screens/import_screen.dart';
import 'package:flexiplan/services/storage_service.dart';
import 'package:flexiplan/services/template_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _validPlanJson = '''
{
  "workout_title": "Testplan",
  "version": "1.0",
  "exercises": [
    {
      "id": 1,
      "name": "Kniebeugen",
      "description": "Test",
      "type": "reps",
      "sets": 3,
      "reps": 10,
      "weight_kg": 20,
      "rest_duration_seconds": 60
    }
  ]
}
''';

const String _templateListResponse = '''
[
  {"name": "ganzkoerper_anfaenger.json", "download_url": "https://raw/ganzkoerper.json"}
]
''';

const String _templateContentResponse = '''
{
  "workout_title": "Ganzkörper für Einsteiger",
  "version": "1.0",
  "exercises": [
    {
      "id": 1,
      "name": "Liegestütze",
      "description": "Test",
      "type": "reps",
      "sets": 3,
      "reps": 12,
      "bodyweight": true,
      "rest_duration_seconds": 60
    }
  ]
}
''';

Future<void> _pumpImportScreen(
    WidgetTester tester, TemplateRepository repo) async {
  await tester.pumpWidget(MaterialApp(
    home: ImportScreen(storage: StorageService(), templateRepository: repo),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Copy-Paste-Import zeigt Statuszeile und Bearbeiten-Icon',
      (tester) async {
    await _pumpImportScreen(tester, const TemplateRepository());

    await tester.enterText(find.byType(TextField), _validPlanJson);
    await tester.pumpAndSettle();

    expect(find.text('Testplan · 1 Übungen · 3 Sätze'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Plan übernehmen'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Bearbeiten-Icon öffnet Editor und Speichern aktualisiert JSON',
      (tester) async {
    await _pumpImportScreen(tester, const TemplateRepository());
    await tester.enterText(find.byType(TextField), _validPlanJson);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Übungen bearbeiten'), findsOneWidget);
    final nameField = find.widgetWithText(TextField, 'Kniebeugen');
    expect(nameField, findsOneWidget);

    await tester.enterText(nameField, 'Kniebeugen (schwer)');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Speichern'));
    await tester.pumpAndSettle();

    // Dialog geschlossen, geänderter Name im JSON-Textfeld angekommen und
    // von der Live-Validierung übernommen.
    expect(find.text('Übungen bearbeiten'), findsNothing);
    expect(find.textContaining('Kniebeugen (schwer)'), findsWidgets);
  });

  testWidgets(
      'Beispiel-Workout laden zeigt Liste und übernimmt den Inhalt ins Textfeld',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.toString().contains('api.github.com')) {
        return http.Response(_templateListResponse, 200);
      }
      return http.Response(_templateContentResponse, 200);
    });
    await _pumpImportScreen(tester, TemplateRepository(client: client));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Beispiel-Workout laden'));
    await tester.pumpAndSettle();

    expect(find.text('Ganzkoerper Anfaenger'), findsOneWidget);

    await tester.tap(find.text('Ganzkoerper Anfaenger'));
    await tester.pumpAndSettle();

    // Sheet geschlossen, Vorlagen-Inhalt geladen und validiert.
    expect(find.text('Ganzkoerper Anfaenger'), findsNothing);
    expect(find.textContaining('Ganzkörper für Einsteiger'), findsWidgets);
  });

  testWidgets('Beispiel-Workout laden zeigt Fehlermeldung bei Netzwerkfehler',
      (tester) async {
    final client = MockClient((request) async => http.Response('', 500));
    await _pumpImportScreen(tester, TemplateRepository(client: client));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Beispiel-Workout laden'));
    await tester.pumpAndSettle();

    expect(find.textContaining('konnten nicht geladen werden'), findsOneWidget);
  });
}
