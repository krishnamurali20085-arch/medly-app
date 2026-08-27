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

    // Create the notification channels (required for Android 8+)
    await _createNotificationChannel();
    await _createStreakChannel();

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

  // ==================== EXERCISE STREAK REMINDERS ====================

  /// Create the streak reminder notification channel
  static Future<void> _createStreakChannel() async {
    const channel = AndroidNotificationChannel(
      'medly_streak_reminders',
      'Exercise Streak Reminders',
      description: 'Motivating reminders to keep your exercise streak alive',
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
    }
  }

  /// Schedule a daily streak reminder at 8:00 PM.
  /// If exercises aren't completed by 8 PM, this notification fires
  /// with a motivating message based on the user's current streak.
  static Future<void> scheduleStreakReminder() async {
    await initialize();
    await _createStreakChannel();

    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      20, // 8 PM
      0,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'medly_streak_reminders',
      'Exercise Streak Reminders',
      channelDescription: 'Motivating reminders to keep your exercise streak alive',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      ongoing: false,
      autoCancel: true,
      enableVibration: true,
      enableLights: true,
      styleInformation: BigTextStyleInformation(
        'Complete your daily exercises to keep your streak going!',
        contentTitle: '🏋️ Exercise Reminder',
        summaryText: 'Tap to open Medly',
      ),
    );

    const details = NotificationDetails(android: androidDetails);

    // Use a fixed ID for the streak reminder so only one is scheduled
    await _plugin.zonedSchedule(
      99999, // Fixed ID for streak reminder
      "🏋️ Don\'t Break Your Streak!",
      "Your exercises are waiting - complete them before midnight!",
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'streak_reminder',
    );

    print('[Notifications] Streak reminder scheduled for 8:00 PM daily');
  }

  /// Cancel the streak reminder
  static Future<void> cancelStreakReminder() async {
    await _plugin.cancel(99999);
    print('[Notifications] Streak reminder cancelled');
  }

  /// Show an immediate streak notification with motivating message.
  /// Call this when user opens the app and hasn't done exercises today.
  static Future<void> showStreakReminder({
    required int currentStreak,
    required int exercisesCompleted,
    required int totalExercises,
  }) async {
    await initialize();
    await _createStreakChannel();
    await requestPermission();

    final message = _getStreakMotivationalMessage(
      currentStreak,
      exercisesCompleted,
      totalExercises,
    );

    const androidDetails = AndroidNotificationDetails(
      'medly_streak_reminders',
      'Exercise Streak Reminders',
      channelDescription: 'Motivating reminders to keep your exercise streak alive',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(
        'Complete your exercises to keep your streak going!',
        contentTitle: '🏋️ Exercise Streak',
        summaryText: 'Tap to open Medly',
      ),
    );

    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(99998, message['title'], message['body'], details);
  }

  /// Generates a motivational message based on streak length and progress.
  /// Messages get more intense as streak grows.
  static Map<String, String> _getStreakMotivationalMessage(
    int currentStreak,
    int exercisesCompleted,
    int totalExercises,
  ) {
    final remaining = totalExercises - exercisesCompleted;

    if (currentStreak == 0) {
      // No streak yet - gentle nudge
      return {
        'title': '🌟 Start Your Journey Today!',
        'body': remaining > 0
            ? 'You have $remaining exercise${remaining > 1 ? 's' : ''} left today. Even 5 minutes makes a difference!'
            : 'Great job completing your exercises! Keep it up tomorrow!',
      };
    } else if (currentStreak >= 1 && currentStreak <= 3) {
      // Early streak - encouraging
      return {
        'title': '🔥 $currentStreak Day Streak - Keep Going!',
        'body': remaining > 0
            ? "Don't stop now! $remaining exercise${remaining > 1 ? 's' : ''} to go. Every day counts!"
            : "You're building a habit! Day $currentStreak done - see you tomorrow!",
      };
    } else if (currentStreak >= 4 && currentStreak <= 6) {
      // Building momentum - excited
      return {
        'title': '💪 $currentStreak Days Strong!',
        'body': remaining > 0
            ? 'Almost a week! Just $remaining exercise${remaining > 1 ? 's' : ''} left. Your body is thanking you!'
            : "$currentStreak days in a row! You're unstoppable!",
      };
    } else if (currentStreak >= 7 && currentStreak <= 13) {
      // One week milestone - celebratory + caution
      return {
        'title': '🎉 Week Streak! Don\'t Let It Slip!',
        'body': remaining > 0
            ? "$currentStreak days strong! $remaining exercise${remaining > 1 ? 's' : ''} to keep the fire burning. You've got this!"
            : "A whole week! You're an inspiration! Keep the momentum going!",
      };
    } else if (currentStreak >= 14 && currentStreak <= 29) {
      // Two weeks - intense motivation
      return {
        'title': "⚡ $currentStreak DAYS! You're a Warrior!",
        'body': remaining > 0
            ? "Two weeks of dedication! Don't let $remaining exercise${remaining > 1 ? 's' : ''} end it all. Champions don't quit!"
            : "$currentStreak days! You're in the top 1% of dedicated people!",
      };
    } else if (currentStreak >= 30 && currentStreak <= 59) {
      // Monthly - elite status
      return {
        'title': '🏆 $currentStreak Day LEGEND!',
        'body': remaining > 0
            ? 'Over a month of consistency! $remaining exercise${remaining > 1 ? 's' : ''} stand between you and greatness. Your future self is counting on you!'
            : '$currentStreak days! You are literally rewiring your brain for health!',
      };
    } else {
      // 60+ days - godlike
      return {
        'title': "👑 $currentStreak DAYS! You're UNSTOPPABLE!",
        'body': remaining > 0
            ? "A $currentStreak-day streak is EXTRAORDINARY. $remaining exercise${remaining > 1 ? 's' : ''} and you'll keep history rolling!"
            : '$currentStreak days of pure discipline! You are an absolute champion!',
      };
    }
  }

  /// Check if exercises were completed today and show reminder if not.
  /// Call this on app open and at 8 PM via scheduled notification.
  static Future<void> checkAndNotifyStreak({
    required String email,
    required int currentStreak,
    required int exercisesCompleted,
    required int totalExercises,
  }) async {
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    final prefs = await SharedPreferences.getInstance();

    // Check if we already sent a reminder today
    final lastReminder = prefs.getString('last_streak_reminder_date');
    if (lastReminder == todayKey) return; // Already reminded today

    // Only remind if there are incomplete exercises
    if (exercisesCompleted < totalExercises) {
      await showStreakReminder(
        currentStreak: currentStreak,
        exercisesCompleted: exercisesCompleted,
        totalExercises: totalExercises,
      );
      await prefs.setString('last_streak_reminder_date', todayKey);
      print('[Notifications] Streak reminder shown: streak=$currentStreak, done=$exercisesCompleted/$totalExercises');
    }
  }

  /// Schedule morning motivational notification (7 AM daily)
  /// to start the day with exercise encouragement.
  static Future<void> scheduleMorningMotivation() async {
    await initialize();
    await _createStreakChannel();

    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      7, // 7 AM
      0,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'medly_streak_reminders',
      'Exercise Streak Reminders',
      channelDescription: 'Motivating reminders to keep your exercise streak alive',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(
        'Start your day with a healthy exercise routine!',
        contentTitle: '🌅 Good Morning!',
        summaryText: 'Tap to open Medly',
      ),
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      99997, // Fixed ID for morning motivation
      "🌅 Rise & Shine - Exercise Time!",
      "A new day, a new chance to build your streak. Let\'s move!",
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'morning_motivation',
    );

    print('[Notifications] Morning motivation scheduled for 7:00 AM daily');
  }
}
