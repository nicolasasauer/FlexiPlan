/// Trainings-Erinnerungen: wöchentlich wiederkehrende lokale
/// Benachrichtigungen zu einer festen Uhrzeit an gewählten Wochentagen.
///
/// Komplett lokal (flutter_local_notifications, keine Internet-
/// Berechtigung). Geplant wird inexakt (inexactAllowWhileIdle): Für eine
/// Trainingserinnerung ist minutengenaue Zustellung unnötig, dafür
/// braucht die App keine Exact-Alarm-Sonderberechtigung.
library;

import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Persistierte Erinnerungs-Einstellungen.
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.weekdays,
  });

  static const ReminderSettings defaults = ReminderSettings(
    enabled: false,
    hour: 18,
    minute: 0,
    // DateTime.monday (1) … DateTime.sunday (7)
    weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
  );

  final bool enabled;
  final int hour;
  final int minute;
  final Set<int> weekdays;

  ReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    Set<int>? weekdays,
  }) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        weekdays: weekdays ?? this.weekdays,
      );

  factory ReminderSettings.fromJson(Map<String, dynamic> json) =>
      ReminderSettings(
        enabled: json['enabled'] as bool? ?? false,
        hour: (json['hour'] as num?)?.toInt() ?? 18,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
        weekdays: ((json['weekdays'] as List<dynamic>?) ?? const [])
            .map((e) => (e as num).toInt())
            .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
            .toSet(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays.toList()..sort(),
      };
}

class ReminderService {
  static const String _prefsKey = 'flexiplan_reminder';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialisiert Plugin und Zeitzonen-Datenbank (einmalig, lazy).
  Future<bool> _ensureInitialized() async {
    if (_initialized) {
      return true;
    }
    try {
      tz_data.initializeTimeZones();
      try {
        final localName = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(localName));
      } on Object {
        // Unbekannte Zone: tz.local bleibt UTC – Erinnerung kommt dann
        // ggf. verschoben, aber die App funktioniert weiter.
      }
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = true;
      return true;
    } on Object {
      // Plattform ohne Notification-Support (z. B. Windows-Build ohne
      // Setup): Erinnerungen sind ein Komfort-Feature, kein Blocker.
      return false;
    }
  }

  Future<ReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      return ReminderSettings.defaults;
    }
    try {
      return ReminderSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return ReminderSettings.defaults;
    }
  }

  /// Speichert die Einstellungen und plant alle Benachrichtigungen neu.
  /// Liefert false, wenn die Notification-Berechtigung fehlt.
  Future<bool> apply(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(settings.toJson()));

    if (!await _ensureInitialized()) {
      return false;
    }
    await _plugin.cancelAll();
    if (!settings.enabled || settings.weekdays.isEmpty) {
      return true;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? true;
    if (!granted) {
      return false;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'training_reminder',
        'Trainings-Erinnerung',
        channelDescription:
            'Erinnert dich an deinen geplanten Trainingstermin.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    for (final weekday in settings.weekdays) {
      await _plugin.zonedSchedule(
        weekday, // stabile ID pro Wochentag (1-7)
        'Zeit fürs Training 💪',
        'Dein Workout wartet – bleib an deinem Plan dran.',
        _nextInstanceOf(weekday, settings.hour, settings.minute),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
    return true;
  }

  /// Nächster Zeitpunkt des gewünschten Wochentags (1=Mo … 7=So) zur
  /// gewünschten Uhrzeit in der lokalen Zeitzone.
  tz.TZDateTime _nextInstanceOf(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
