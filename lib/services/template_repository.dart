import 'dart:convert';

import 'package:http/http.dart' as http;

/// Referenz auf eine Beispiel-Vorlage im öffentlichen Repository. Es wird
/// bewusst nichts in der App gebündelt: Neue oder aktualisierte Dateien im
/// `workouts/`-Ordner auf GitHub stehen damit sofort allen Nutzern zur
/// Verfügung, ganz ohne App-Update.
class WorkoutTemplateRef {
  const WorkoutTemplateRef({required this.fileName, required this.downloadUrl});

  final String fileName;
  final String downloadUrl;

  /// Menschenlesbarer Titel aus dem Dateinamen, z. B.
  /// "ganzkoerper_anfaenger.json" → "Ganzkoerper Anfaenger".
  String get displayName {
    final base =
        fileName.endsWith('.json') ? fileName.substring(0, fileName.length - 5) : fileName;
    return base
        .split(RegExp('[_-]'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

class TemplateRepositoryException implements Exception {
  const TemplateRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lädt Liste und Inhalt der Beispiel-Vorlagen zur Laufzeit aus dem
/// öffentlichen GitHub-Repository (workouts/-Ordner, main-Branch) über die
/// GitHub Contents API. Unauthentifiziert, öffentliches Repo – kein Token
/// nötig; das reicht für den seltenen, manuell ausgelösten Abruf locker
/// innerhalb des anonymen Rate-Limits.
class TemplateRepository {
  const TemplateRepository({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const String _listUrl = 'https://api.github.com/repos/'
      'nicolasasauer/FlexiPlan/contents/workouts?ref=main';

  Future<List<WorkoutTemplateRef>> listTemplates() async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse(_listUrl),
              headers: const {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw TemplateRepositoryException(
            'GitHub antwortete mit Status ${response.statusCode}.');
      }
      final entries = jsonDecode(response.body) as List<dynamic>;
      final templates = entries
          .cast<Map<String, dynamic>>()
          .where((e) => (e['name'] as String).endsWith('.json'))
          .map((e) => WorkoutTemplateRef(
                fileName: e['name'] as String,
                downloadUrl: e['download_url'] as String,
              ))
          .toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      return templates;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<String> fetchContent(WorkoutTemplateRef template) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse(template.downloadUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw TemplateRepositoryException(
            'Vorlage konnte nicht geladen werden (Status ${response.statusCode}).');
      }
      return response.body;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }
}
