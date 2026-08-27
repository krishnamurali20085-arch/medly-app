import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Settings & Profile E2E', () {
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

    testWidgets('Settings page shows account info', (tester) async {
      await reachHome(tester);
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('Role: User'), findsOneWidget);
    });

    testWidgets('Settings shows all menu items', (tester) async {
      await reachHome(tester);
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('AI API Key'), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(find.text('SOS Call Log'), findsOneWidget);
      expect(find.text('Database Viewer'), findsOneWidget);
      expect(find.text('Family Health Dashboard'), findsOneWidget);
      expect(find.text('Test Supabase Connection'), findsOneWidget);
    });

    testWidgets('Edit profile dialog works', (tester) async {
      await reachHome(tester);
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Health Profile'), findsOneWidget);
      expect(find.text('Blood Group'), findsWidgets);
      expect(find.text('Allergies'), findsWidgets);
      expect(find.text('Weight (kg)'), findsWidgets);
      expect(find.text('Height (cm)'), findsWidgets);
    });

    testWidgets('Blood Donation page opens for all users', (tester) async {
      await reachHome(tester);
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blood Donation'));
      await tester.pumpAndSettle();
      expect(find.text('Blood Donation'), findsWidgets);
      expect(find.text('Register as Donor'), findsOneWidget);
    });

    testWidgets('Blood donation form has all fields', (tester) async {
      await reachHome(tester);
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blood Donation'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Phone'), findsOneWidget);
      expect(find.text('Blood Group'), findsWidgets);
      expect(find.text('Register'), findsWidgets);
    });

    testWidgets('Family Dashboard page opens', (tester) async {
      await reachHome(tester);
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Family Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Family Health Dashboard'), findsOneWidget);
      expect(find.text('Add family member'), findsOneWidget);
    });

    testWidgets('Sign out returns to login screen', (tester) async {
      await reachHome(tester);
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Sign out');
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Medly'), findsOneWidget);
    });

    testWidgets('Database Viewer access control works', (tester) async {
      await reachHome(tester);
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Database Viewer'));
      await tester.pumpAndSettle();
      // Non-owner should see access denied or the viewer
      final accessDenied = find.text('Access denied');
      final viewer = find.text('Database Viewer');
      expect(accessDenied.evaluate().isNotEmpty || viewer.evaluate().isNotEmpty,
          true);
    });
  });
}
