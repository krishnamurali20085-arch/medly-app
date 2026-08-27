import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Medicine Reminder E2E', () {
    Future<void> reachHealthTab(WidgetTester tester) async {
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
      await tapNavDestination(tester, 'Health');
    }

    testWidgets('Health tab shows medicine reminder section', (tester) async {
      await reachHealthTab(tester);
      expect(find.text('Medicine reminder'), findsOneWidget);
      expect(find.text('Medicine name'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Submit reminder'), findsOneWidget);
    });

    testWidgets('Cannot submit empty reminder', (tester) async {
      await reachHealthTab(tester);
      await tapButton(tester, 'Submit reminder');
      expect(find.textContaining('Enter medicine and time'), findsOneWidget);
    });

    testWidgets('Can add a medicine reminder', (tester) async {
      await reachHealthTab(tester);
      // Enter medicine name
      await enterTextByLabel(tester, 'Medicine name', 'Paracetamol');
      await tester.pump();
      // Enter time
      await enterTextByLabel(tester, 'Time', '08:00 AM');
      await tester.pump();
      // Submit
      await tapButton(tester, 'Submit reminder');
      await tester.pumpAndSettle();
      // Should show the reminder in the list
      expect(find.text('Paracetamol'), findsOneWidget);
      expect(find.text('08:00 AM'), findsOneWidget);
      // Success snackbar
      expect(find.text('Reminder saved'), findsOneWidget);
    });

    testWidgets('Can add multiple reminders', (tester) async {
      await reachHealthTab(tester);
      // First reminder
      await enterTextByLabel(tester, 'Medicine name', 'Paracetamol');
      await tester.pump();
      await enterTextByLabel(tester, 'Time', '08:00 AM');
      await tester.pump();
      await tapButton(tester, 'Submit reminder');
      await tester.pumpAndSettle();
      // Second reminder
      await enterTextByLabel(tester, 'Medicine name', 'Vitamin D');
      await tester.pump();
      await enterTextByLabel(tester, 'Time', '12:00 PM');
      await tester.pump();
      await tapButton(tester, 'Submit reminder');
      await tester.pumpAndSettle();
      // Both should appear
      expect(find.text('Paracetamol'), findsOneWidget);
      expect(find.text('Vitamin D'), findsOneWidget);
    });

    testWidgets('Can mark reminder as taken', (tester) async {
      await reachHealthTab(tester);
      // Add a reminder
      await enterTextByLabel(tester, 'Medicine name', 'Ibuprofen');
      await tester.pump();
      await enterTextByLabel(tester, 'Time', '06:00 PM');
      await tester.pump();
      await tapButton(tester, 'Submit reminder');
      await tester.pumpAndSettle();
      // Find and tap the checkbox to mark as taken
      final checkbox = find.byType(CheckboxListTile).first;
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      // Should be checked
      final checkboxWidget = tester.widget<CheckboxListTile>(checkbox);
      expect(checkboxWidget.value, true);
    });

    testWidgets('Can delete a medicine reminder', (tester) async {
      await reachHealthTab(tester);
      // Add a reminder
      await enterTextByLabel(tester, 'Medicine name', 'Temp Med');
      await tester.pump();
      await enterTextByLabel(tester, 'Time', '10:00 AM');
      await tester.pump();
      await tapButton(tester, 'Submit reminder');
      await tester.pumpAndSettle();
      // Delete it
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();
      // Should be removed
      expect(find.text('Temp Med'), findsNothing);
    });

    testWidgets('Nearby services section shows on health tab', (tester) async {
      await reachHealthTab(tester);
      expect(find.text('Nearby healthcare services'), findsOneWidget);
    });
  });
}
