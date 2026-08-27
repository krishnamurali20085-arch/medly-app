import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SOS & Emergency E2E', () {
    Future<void> reachHome(WidgetTester tester) async {
      await pumpMedlyApp(tester);
      await tapCreateAccount(tester);
      await fillCreateAccountForm(tester);
      await acceptTerms(tester);
      await tapButton(tester, 'Create account');
      await tester.pumpAndSettle();
      await enterTextByLabel(tester, 'Weight (kg)', '65');
      await tester.pump();
      await enterTextByLabel(tester, 'Height (cm)', '170');
      await tester.pump();
      await tapButton(tester, 'Continue');
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets('SOS tab shows emergency card', (tester) async {
      await reachHome(tester);
      await tapNavDestination(tester, 'SOS');
      expect(find.text('Smart SOS'), findsOneWidget);
      expect(find.text('Call Emergency Contact'), findsOneWidget);
      expect(find.text('Broadcast SMS to All'), findsOneWidget);
    });

    testWidgets('SOS tab shows emergency contact section', (tester) async {
      await reachHome(tester);
      await tapNavDestination(tester, 'SOS');
      expect(find.text('Emergency contact'), findsOneWidget);
      expect(find.text('Add contact'), findsOneWidget);
    });

    testWidgets('SOS tab shows emergency profile', (tester) async {
      await reachHome(tester);
      await tapNavDestination(tester, 'SOS');
      expect(find.text('Emergency profile'), findsOneWidget);
      expect(find.text('Blood group'), findsOneWidget);
      expect(find.text('Allergies'), findsOneWidget);
    });

    testWidgets('SOS tab shows call log', (tester) async {
      await reachHome(tester);
      await tapNavDestination(tester, 'SOS');
      expect(find.text('SOS call log'), findsOneWidget);
    });

    testWidgets('Add emergency contact dialog opens', (tester) async {
      await reachHome(tester);
      await tapNavDestination(tester, 'SOS');
      // Tap "Add contact"
      await tapButton(tester, 'Add contact');
      await tester.pumpAndSettle();
      expect(find.text('Add Emergency Contact'), findsOneWidget);
      expect(find.text('Name'), findsWidgets);
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Priority Tier'), findsOneWidget);
    });

    testWidgets('Can add a tier 1 emergency contact', (tester) async {
      await reachHome(tester);
      await tapNavDestination(tester, 'SOS');
      await tapButton(tester, 'Add contact');
      await tester.pumpAndSettle();
      // Fill name
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mom');
      await tester.pump();
      // Fill phone
      await tester.enterText(
          find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.pump();
      // Save
      await tapButton(tester, 'Save');
      await tester.pumpAndSettle();
      // Should show the contact in the list
      expect(find.text('Mom'), findsOneWidget);
    });

    testWidgets('SOS trigger shows confirmation dialog', (tester) async {
      await reachHome(tester);
      await tapNavDestination(tester, 'SOS');
      await tapButton(tester, 'Call Emergency Contact');
      await tester.pumpAndSettle();
      expect(find.text('Trigger SOS?'), findsOneWidget);
      expect(find.text('SEND SOS'), findsOneWidget);
    });

    testWidgets('Broadcast SMS shows confirmation dialog', (tester) async {
      await reachHome(tester);
      await tapNavDestination(tester, 'SOS');
      await tapButton(tester, 'Broadcast SMS to All');
      await tester.pumpAndSettle();
      expect(find.text('Emergency Broadcast?'), findsOneWidget);
    });

    testWidgets('Emergency SOS button on home tab works', (tester) async {
      await reachHome(tester);
      // Home tab has Emergency SOS button
      await tester.tap(find.text('Emergency SOS'));
      await tester.pumpAndSettle();
      expect(find.text('Trigger SOS?'), findsOneWidget);
    });
  });
}
