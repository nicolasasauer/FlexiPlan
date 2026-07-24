import 'package:flexiplan/services/template_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('WorkoutTemplateRef.displayName', () {
    test('formatiert Snake-Case-Dateinamen menschenlesbar', () {
      expect(
        const WorkoutTemplateRef(
                fileName: 'ganzkoerper_anfaenger.json', downloadUrl: '')
            .displayName,
        'Ganzkoerper Anfaenger',
      );
      expect(
        const WorkoutTemplateRef(fileName: 'v_cut.json', downloadUrl: '')
            .displayName,
        'V Cut',
      );
    });
  });

  group('TemplateRepository.listTemplates', () {
    test('filtert auf .json-Dateien und sortiert alphabetisch', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), contains('workouts?ref=main'));
        return http.Response(
          '''
          [
            {"name": "push_kurzhanteln.json", "download_url": "https://raw/push.json"},
            {"name": "README.md", "download_url": "https://raw/README.md"},
            {"name": "beine_po_kurzhanteln.json", "download_url": "https://raw/beine.json"}
          ]
          ''',
          200,
        );
      });
      final repo = TemplateRepository(client: client);
      final templates = await repo.listTemplates();

      expect(templates, hasLength(2));
      expect(templates.map((t) => t.fileName),
          ['beine_po_kurzhanteln.json', 'push_kurzhanteln.json']);
    });

    test('wirft bei Fehlerstatus eine TemplateRepositoryException', () async {
      final client = MockClient((request) async => http.Response('', 404));
      final repo = TemplateRepository(client: client);

      expect(repo.listTemplates(), throwsA(isA<TemplateRepositoryException>()));
    });
  });

  group('TemplateRepository.fetchContent', () {
    test('gibt den rohen Datei-Inhalt zurück', () async {
      const jsonBody = '{"workout_title": "Test"}';
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://raw/beine.json');
        return http.Response(jsonBody, 200);
      });
      final repo = TemplateRepository(client: client);
      final content = await repo.fetchContent(const WorkoutTemplateRef(
        fileName: 'beine.json',
        downloadUrl: 'https://raw/beine.json',
      ));

      expect(content, jsonBody);
    });

    test('wirft bei Fehlerstatus eine TemplateRepositoryException', () async {
      final client = MockClient((request) async => http.Response('', 500));
      final repo = TemplateRepository(client: client);

      expect(
        repo.fetchContent(const WorkoutTemplateRef(
            fileName: 'x.json', downloadUrl: 'https://raw/x.json')),
        throwsA(isA<TemplateRepositoryException>()),
      );
    });
  });
}
