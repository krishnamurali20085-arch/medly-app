import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Home Dashboard E2E', () {
    Future<void> loginAndReachHome(WidgetTester tester) async {
      await pumpMedlyApp(tester);
      await tapCreateAccount(tester);
      await fillCreateAccountForm(tester);
      await acceptTerms(tester);
      await tapButton(tester, 'Create account');
      await tester.pumpAndSettle();
      // Complete onboarding
      await enterTextByLabel(tester, 'Weight (kg)', '65');
      await tester.pump();
      await enterTextByLabel(tester, 'Height (cm)', '170');
      await tester.pump();
      await tapButton(tester, 'Continue');
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets('Home tab shows all sections', (tester) async {
      await loginAndReachHome(tester);
      expect(find.text('Emergency status'), findsOneWidget);
      expect(find.text('Stable'), findsOneWidget);
      expect(find.text('Today\'s health snapshot'), findsOneWidget);
      expect(find.text('Nearby healthcare services'), findsOneWidget);
      expect(find.text('Screen time today'), findsOneWidget);
    });

    testWidgets('Health metrics grid shows all 4 metrics', (tester) async {
      await loginAndReachHome(tester);
      expect(find.text('Blood Pressure'), findsOneWidget);
      expect(find.text('Blood Sugar'), findsOneWidget);
      expect(find.text('Heart Rate'), findsOneWidget);
      expect(find.text('Sleep'), findsOneWidget);
    });

    testWidgets('Step counter card shows on home', (tester) async {
      await loginAndReachHome(tester);
      expect(find.text('Today\'s steps'), findsOneWidget);
      expect(find.text('kcal'), findsOneWidget);
    });

    testWidgets('Navigation between tabs works', (tester) async {
      await loginAndReachHome(tester);

      // Navigate to SOS tab
      await tapNavDestination(tester, 'SOS');
      expect(find.text('Smart SOS'), findsOneWidget);

      // Navigate to Health tab
      await tapNavDestination(tester, 'Health');
      expect(find.text('Medicine reminder'), findsOneWidget);

      // Navigate back to Home
      await tapNavDestination(tester, 'Home');
      expect(find.text('Emergency status'), findsOneWidget);
    });

    testWidgets('Profile menu shows all options', (tester) async {
      await loginAndReachHome(tester);
      // Open profile menu
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Family Dashboard'), findsOneWidget);
      expect(find.text('Live Map'), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Blood Donation'), findsOneWidget);
    });

    testWidgets('Health data dialog opens and saves', (tester) async {
      await loginAndReachHome(tester);
      // Tap "Enter data" button
      await tester.tap(find.text('Enter data'));
      await tester.pumpAndSettle();
      // Dialog should open
      expect(find.text('Today\'s health snapshot'), findsWidgets);
      // Enter blood pressure
      final bpField = find.widgetWithText(TextField, 'Blood Pressure (e.g. 120/80)');
      if (bpField.evaluate().isNotEmpty) {
        await tester.enterText(bpField.first, '120/80');
        await tester.pump();
      }
      // Tap Save
      await tapButton(tester, 'Save');
      await tester.pumpAndSettle();
    });

    testWidgets('AI assistant FAB opens bottom sheet', (tester) async {
      await loginAndReachHome(tester);
      // Tap the AI FAB
      await tester.tap(find.byIcon(Icons.smart_toy_rounded));
      await tester.pumpAndSettle();
      // Should show AI assistant sheet
      expect(find.text('AI Health Assistant'), findsOneWidget);
      expect(find.text('How to use'), findsOneWidget);
    });

    testWidgets('Language selector works', (tester) async {
      await loginAndReachHome(tester);
      // Tap language dropdown
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      // Should show language options
      expect(find.text('English'), findsWidgets);
      expect(find.text('Tamil'), findsWidgets);
      expect(find.text('Hindi'), findsWidgets);
    });
  });
}
