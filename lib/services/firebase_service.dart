import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase initialization helper.
///
/// This app is designed to run in both demo and configured-firebase modes.
/// Without generated platform config, the app should still launch and display
/// the emergency-health interface instead of crashing.
class FirebaseService {
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (e, st) {
      if (kDebugMode) {
        print('Firebase initialization error: $e');
        print(st);
      }
      // Intentionally continue in demo mode when Firebase platform config is not set.
    }
  }
}
