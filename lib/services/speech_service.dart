/// Sprachausgabe (Lastenheft 2.4): liest die nächste Übung samt
/// Kurzanweisung vor. Ansagen sind reiner Komfort – jede Fehlerlage
/// (keine TTS-Engine, fehlende Sprache) wird geschluckt.
library;

import 'package:flutter_tts/flutter_tts.dart';

class SpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) {
      return;
    }
    await _tts.setLanguage('de-DE');
    // Etwas langsamer als Default: besser verständlich, wenn das Handy
    // beim Training weiter weg liegt.
    await _tts.setSpeechRate(0.55);
    _ready = true;
  }

  Future<void> speak(String text) async {
    try {
      await _ensureReady();
      await _tts.speak(text);
    } on Object {
      // Keine TTS-Engine o. ä.: Ansage stumm auslassen.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // ignorieren
    }
  }
}
