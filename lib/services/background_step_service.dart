import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;

/// Background step counter service.
/// Uses WorkManager to periodically read the hardware step counter sensor
/// every 15 minutes, even when the app is closed.
class BackgroundStepService {
  static const String _taskName = 'medly_step_counter';
  static const String _taskUniqueName = 'medly_step_counter_periodic';

  /// Initialize WorkManager and register the periodic step counter task.
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        _onBackgroundTask,
        isInDebugMode: false,
      );

      // Register periodic task — runs every 15 minutes (minimum for Android)
      await Workmanager().registerPeriodicTask(
        _taskUniqueName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.not_required, // No internet needed
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        initialDelay: const Duration(minutes: 5),
      );

      print('[BackgroundStep] WorkManager registered (every 15 min)');
    } catch (e) {
      print('[BackgroundStep] WorkManager init error: $e');
    }
  }

  /// Cancel the periodic task
  static Future<void> cancel() async {
    try {
      await Workmanager().cancelAll();
      print('[BackgroundStep] All tasks cancelled');
    } catch (_) {}
  }
}

/// The top-level callback function for WorkManager background tasks.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
void _onBackgroundTask() async {
  // This runs in an isolate — use WidgetsFlutterBinding for plugins
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  print('[BackgroundStep] Background task executing...');

  try {
    // Read the step counter sensor
    final stepCount = await _readStepSensor();
    if (stepCount != null) {
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      final previousTotal = prefs.getInt('bg_step_total_$today') ?? 0;

      if (stepCount > previousTotal) {
        await prefs.setInt('bg_step_total_$today', stepCount);
        print('[BackgroundStep] Saved step total: $stepCount (today: $today)');
      }

      // Also save the step offset for calculating today's steps
      final offset = prefs.getInt('step_offset_$today');
      if (offset == null) {
        await prefs.setInt('step_offset_$today', stepCount);
      }

      // Calculate and save today's step count
      final savedOffset = prefs.getInt('step_offset_$today') ?? stepCount;
      final todaySteps = (stepCount - savedOffset).clamp(0, 999999);
      await prefs.setInt('today_steps_$today', todaySteps);
      print('[BackgroundStep] Today steps: $todaySteps');
    }
  } catch (e) {
    print('[BackgroundStep] Error: $e');
  }
}

/// Read the step counter sensor directly
Future<int?> _readStepSensor() async {
  try {
    final completer = Completer<int?>();
    StreamSubscription? sub;

    sub = Pedometer.stepCountStream.listen(
      (StepCount event) {
        completer.complete(event.steps);
        sub?.cancel();
      },
      onError: (error) {
        completer.complete(null);
        sub?.cancel();
      },
    );

    // Timeout after 10 seconds — sensor might not be available
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        sub?.cancel();
      }
    });

    return await completer.future;
  } catch (e) {
    print('[BackgroundStep] Sensor read error: $e');
    return null;
  }
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month}-${now.day}';
}
