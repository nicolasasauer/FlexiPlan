/// Wake-Lock und Audio-Signale (Lastenheft 2.4/3.1) über den nativen
/// Kanal in MainActivity.kt – bewusst ohne zusätzliche Plugin-Abhängigkeit.
///
/// Auf Plattformen ohne native Gegenstelle (Windows, Tests) laufen alle
/// Aufrufe ins Leere: Signale sind Komfort, nie funktionskritisch.
library;

import 'package:flutter/services.dart';

class NativeFeedback {
  NativeFeedback._();

  static const MethodChannel _channel = MethodChannel('flexiplan/native');

  /// Hält das Display während des aktiven Workouts wach (true) bzw. gibt
  /// es wieder frei (false).
  static Future<void> keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', on);
    } on Object {
      // Keine native Gegenstelle (z. B. Windows/Tests): ignorieren.
    }
  }

  /// Kurzer Countdown-Tick (letzte 3 Sekunden eines Timers).
  static Future<void> tick() => _beep('tick');

  /// Startsignal beim Beginn eines Belastungs-Timers.
  static Future<void> start() => _beep('start');

  /// Abschlusssignal beim Ablauf eines Timers.
  static Future<void> end() => _beep('end');

  static Future<void> _beep(String kind) async {
    try {
      await _channel.invokeMethod<void>('beep', kind);
    } on Object {
      // Keine native Gegenstelle: ignorieren.
    }
  }
}
