import 'package:flutter/material.dart';

import '../services/reminder_service.dart';
import '../services/storage_service.dart';

/// Minimalistische Einstellung der Trainings-Erinnerung: Uhrzeit +
/// Wochentage, Änderungen werden sofort gespeichert und eingeplant.
class ReminderScreen extends StatefulWidget {
  const ReminderScreen({
    super.key,
    required this.reminders,
    required this.storage,
  });

  final ReminderService reminders;
  final StorageService storage;

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  static const List<String> _dayLabels = [
    'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So',
  ];

  ReminderSettings? _settings;

  @override
  void initState() {
    super.initState();
    widget.reminders.loadSettings().then((value) {
      if (mounted) {
        setState(() => _settings = value);
      }
    });
  }

  Future<void> _update(ReminderSettings next) async {
    setState(() => _settings = next);
    final selected = await widget.storage.loadSelectedPlan();
    final ok = await widget.reminders
        .apply(next, planTitle: selected?.plan.workoutTitle);
    if (!mounted) {
      return;
    }
    if (!ok && next.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte erlaube FlexiPlan Benachrichtigungen in den '
              'System-Einstellungen, damit Erinnerungen ankommen.'),
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final settings = _settings!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.hour, minute: settings.minute),
      helpText: 'Erinnerungszeit',
    );
    if (picked != null) {
      await _update(
          settings.copyWith(hour: picked.hour, minute: picked.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Erinnerung')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      title: Text('Trainings-Erinnerung',
                          style: theme.textTheme.titleLarge),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Push-Benachrichtigung an deinen Trainingstagen.',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      value: settings.enabled,
                      onChanged: (value) =>
                          _update(settings.copyWith(enabled: value)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          enabled: settings.enabled,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          leading: const Icon(Icons.schedule, size: 28),
                          title: Text('Uhrzeit',
                              style: theme.textTheme.titleMedium),
                          trailing: Text(
                            '${settings.hour.toString().padLeft(2, '0')}:'
                            '${settings.minute.toString().padLeft(2, '0')}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: settings.enabled
                                  ? theme.colorScheme.primary
                                  : theme.disabledColor,
                            ),
                          ),
                          onTap: _pickTime,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var day = DateTime.monday;
                                  day <= DateTime.sunday;
                                  day++)
                                FilterChip(
                                  label: Text(_dayLabels[day - 1],
                                      style: const TextStyle(fontSize: 16)),
                                  selected:
                                      settings.weekdays.contains(day),
                                  onSelected: settings.enabled
                                      ? (selected) {
                                          final days = Set<int>.from(
                                              settings.weekdays);
                                          if (selected) {
                                            days.add(day);
                                          } else {
                                            days.remove(day);
                                          }
                                          _update(settings.copyWith(
                                              weekdays: days));
                                        }
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Die Erinnerung kommt als normale Benachrichtigung – '
                    'ganz ohne Internet, direkt von deinem Gerät.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}
