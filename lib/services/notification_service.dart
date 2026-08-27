import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Callback when user taps a notification
  static Function(String? payload)? onNotificationTapped;

  /// Initialize the notification system — must be called early (e.g. main())
  static Future<void> initialize() async {
    if (_initialized) return;

    initializeTimeZones();

    // Android settings with high-importance channel
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        print('[Notifications] User tapped notification: ${details.payload}');
        onNotificationTapped?.call(details.payload);
      },
    );

    // Create the notification channel (required for Android 8+)
    await _createNotificationChannel();

    _initialized = true;
    print('[Notifications] Initialized successfully');
  }

  /// Create Android notification channel
  static Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      'medly_medicine_reminders',
      'Medicine Reminders',
      description: 'Daily reminders to take your medicine',
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      playSound: true,
    );

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
      print('[Notifications] Notification channel created');
    }
  }

  /// Request notification permission (Android 13+ requires this)
  static Future<bool> requestPermission() async {
    // Android 13+ (API 33+)
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    final result = await Permission.notification.request();
    print('[Notifications] Permission result: $result');
    return result.isGranted;
  }

  /// Schedule a daily notification at the given time for a medicine reminder.
  /// Works even when the app is closed — uses exact alarms.
  static Future<void> scheduleMedicineReminder({
    required int id,
    required String medicineName,
    required String timeString, // e.g. "08:00 AM" or "14:30"
  }) async {
    await initialize();

    // Request permission first
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      print('[Notifications] Permission denied — cannot schedule');
      return;
    }

    final time = _parseTime(timeString);
    if (time == null) {
      print('[Notifications] Could not parse time: $timeString');
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // If the time has already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    final androidDetails = AndroidNotificationDetails(
      'medly_medicine_reminders',
      'Medicine Reminders',
      channelDescription: 'Daily reminders to take your medicine',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      ongoing: false,
      autoCancel: true,
      enableVibration: true,
      enableLights: true,
      styleInformation: BigTextStyleInformation(
        'Time to take your medicine: $medicineName',
        contentTitle: '💊 Medicine Reminder',
        summaryText: 'Tap to open Medly',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      id,
      '💊 Medicine Reminder',
      'Time to take: $medicineName',
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'medicine_reminder:$medicineName',
    );

    // Save scheduled reminder info for rescheduling after boot
    await _saveScheduledReminder(id, medicineName, timeString);

    print('[Notifications] Scheduled reminder #$id: $medicineName at $timeString (fires from: $scheduledDate)');
  }

  /// Cancel a scheduled notification
  static Future<void> cancelReminder(int id) async {
    await _plugin.cancel(id);
    await _removeScheduledReminder(id);
    print('[Notifications] Cancelled reminder #$id');
  }

  /// Cancel all reminders
  static Future<void> cancelAllReminders() async {
    await _plugin.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('scheduled_notifications');
    print('[Notifications] Cancelled all reminders');
  }

  /// Reschedule all saved reminders — call this on app start and after boot
  static Future<void> rescheduleAllReminders() async {
    await initialize();

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('scheduled_notifications') ?? [];

    int rescheduled = 0;
    for (final entry in saved) {
      final parts = entry.split('|||');
      if (parts.length == 3) {
        final id = int.tryParse(parts[0]);
        final name = parts[1];
        final time = parts[2];
        if (id != null) {
          await scheduleMedicineReminder(
            id: id,
            medicineName: name,
            timeString: time,
          );
          rescheduled++;
        }
      }
    }
    print('[Notifications] Rescheduled $rescheduled reminders');
  }

  /// Show an immediate notification (for testing)
  static Future<void> showImmediate({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();
    await requestPermission();

    const androidDetails = AndroidNotificationDetails(
      'medly_medicine_reminders',
      'Medicine Reminders',
      channelDescription: 'Daily reminders to take your medicine',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details);
  }

  // ---- Persistence helpers ----

  static Future<void> _saveScheduledReminder(
      int id, String name, String time) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('scheduled_notifications') ?? [];
    // Remove any existing entry with the same id
    saved.removeWhere((e) => e.startsWith('$id|||'));
    saved.add('$id|||$name|||$time');
    await prefs.setStringList('scheduled_notifications', saved);
  }

  static Future<void> _removeScheduledReminder(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('scheduled_notifications') ?? [];
    saved.removeWhere((e) => e.startsWith('$id|||'));
    await prefs.setStringList('scheduled_notifications', saved);
  }

  // ---- Time parsing ----

  static DateTime? _parseTime(String timeString) {
    try {
      final cleaned = timeString.trim().toUpperCase();

      // Try "HH:MM AM/PM" format
      final amPmMatch =
          RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(cleaned);
      if (amPmMatch != null) {
        var hour = int.parse(amPmMatch.group(1)!);
        final minute = int.parse(amPmMatch.group(2)!);
        final period = amPmMatch.group(3);

        if (period == 'AM' && hour == 12) {
          hour = 0;
        } else if (period == 'PM' && hour < 12) {
          hour += 12;
        }

        return DateTime(2024, 1, 1, hour, minute);
      }

      // Try "HH:MM" (24-hour) format
      final militaryMatch =
          RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(cleaned);
      if (militaryMatch != null) {
        final hour = int.parse(militaryMatch.group(1)!);
        final minute = int.parse(militaryMatch.group(2)!);
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return DateTime(2024, 1, 1, hour, minute);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Generate a unique ID from medicine name and time
  static int generateId(String name, String time) {
    return (name + time).hashCode.abs() % 2147483647;
  }
}
