/// Zentrale externe Links der App.
library;

import 'package:url_launcher/url_launcher.dart';

/// Öffentliches GitHub-Repository (Quellcode, Workout-Vorlagen,
/// JSON-Schema-Dokumentation).
const String gitHubRepoUrl = 'https://github.com/nicolasasauer/FlexiPlan';

/// Ordner mit den fertigen Workout-Vorlagen im Repository.
const String workoutTemplatesUrl = '$gitHubRepoUrl/tree/main/workouts';

/// Öffnet [url] im externen Browser. Fehler (z. B. kein Browser
/// installiert) werden bewusst verschluckt – die App bleibt nutzbar.
Future<void> openExternalUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } on Object {
    // Kein Browser verfügbar: bewusst ignorieren, kein App-Feature hängt
    // von den externen Links ab.
  }
}
