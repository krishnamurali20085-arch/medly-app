import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding E2E', () {
    Future<void> completeOnboarding(WidgetTester tester) async {
      await pumpMedlyApp(tester);
      await tapCreateAccount(tester);
      await fillCreateAccountForm(tester);
      await acceptTerms(tester);
      await tapButton(tester, 'Create account');
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets('Onboarding screen shows all health fields', (tester) async {
      await completeOnboarding(tester);
      expect(find.text('Complete Your Profile'), findsOneWidget);
      expect(find.text('Blood Group'), findsOneWidget);
      expect(find.text('Allergies (comma-separated)'), findsOneWidget);
      expect(find.text('Weight (kg)'), findsOneWidget);
      expect(find.text('Height (cm)'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('Blood group dropdown shows all options', (tester) async {
      await completeOnboarding(tester);
      // Tap blood group dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      // Should show all blood group options
      expect(find.text('A+'), findsWidgets);
      expect(find.text('B+'), findsWidgets);
      expect(find.text('O+'), findsWidgets);
      expect(find.text('AB+'), findsWidgets);
    });

    testWidgets('Cannot complete onboarding without weight/height', (tester) async {
      await completeOnboarding(tester);
      await tapButton(tester, 'Continue');
      expect(find.text('Please enter your weight and height.'), findsOneWidget);
    });

    testWidgets('Complete onboarding with all fields', (tester) async {
      await completeOnboarding(tester);
      // Select blood group
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('B+').last);
      await tester.pumpAndSettle();

      // Enter allergies
      await enterTextByLabel(tester, 'Allergies (comma-separated)', 'Peanuts, Dust');
      await tester.pump();

      // Enter weight
      await enterTextByLabel(tester, 'Weight (kg)', '65');
      await tester.pump();

      // Enter height
      await enterTextByLabel(tester, 'Height (cm)', '170');
      await tester.pump();

      // Submit
      await tapButton(tester, 'Continue');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Should navigate to home screen
      expect(find.text('Medly'), findsWidgets);
    });

    testWidgets('Health info pills show on home after onboarding', (tester) async {
      await completeOnboarding(tester);
      // Fill and complete onboarding
      await enterTextByLabel(tester, 'Weight (kg)', '70');
      await tester.pump();
      await enterTextByLabel(tester, 'Height (cm)', '175');
      await tester.pump();
      await tapButton(tester, 'Continue');
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // Home should show blood group and allergies info
      expect(find.text('Blood group'), findsOneWidget);
      expect(find.text('Allergies'), findsOneWidget);
    });
  });
}
