/// Main E2E test runner for Medly app.
///
/// Run with:
///   flutter test integration_test/app_e2e_test.dart
///
/// Or run all integration tests:
///   flutter test integration_test/
///
/// For a specific test file:
///   flutter test integration_test/login_signup_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Import all test groups
import 'login_signup_test.dart' as login_tests;
import 'onboarding_test.dart' as onboarding_tests;
import 'home_dashboard_test.dart' as home_tests;
import 'sos_emergency_test.dart' as sos_tests;
import 'medicine_reminder_test.dart' as medicine_tests;
import 'settings_profile_test.dart' as settings_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Medly E2E Tests', () {
    login_tests.main();
    onboarding_tests.main();
    home_tests.main();
    sos_tests.main();
    medicine_tests.main();
    settings_tests.main();
  });
}
