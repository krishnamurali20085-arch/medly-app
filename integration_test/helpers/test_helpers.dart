import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medly/main.dart';

/// Pump the Medly app and wait for it to settle.
Future<void> pumpMedlyApp(WidgetTester tester) async {
  await tester.pumpWidget(const MedlyApp());
  // Wait for splash screen to finish (2 seconds + animation)
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Enter text into a TextField found by its labelText.
Future<void> enterTextByLabel(
    WidgetTester tester, String labelText, String text) async {
  final field = find.widgetWithText(TextField, labelText);
  if (field.evaluate().isEmpty) {
    // Try TextFormField
    final tfField = find.widgetWithText(TextFormField, labelText);
    await tester.enterText(tfField.first, text);
  } else {
    await tester.enterText(field.first, text);
  }
}

/// Tap a button found by its text content.
Future<void> tapButton(WidgetTester tester, String buttonText) async {
  final button = find.widgetWithText(ElevatedButton, buttonText);
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button.first);
    await tester.pumpAndSettle();
    return;
  }
  // Try TextButton
  final textButton = find.widgetWithText(TextButton, buttonText);
  if (textButton.evaluate().isNotEmpty) {
    await tester.tap(textButton.first);
    await tester.pumpAndSettle();
    return;
  }
  // Try OutlinedButton
  final outlinedButton = find.widgetWithText(OutlinedButton, buttonText);
  if (outlinedButton.evaluate().isNotEmpty) {
    await tester.tap(outlinedButton.first);
    await tester.pumpAndSettle();
  }
}

/// Tap the Sign In button specifically.
Future<void> tapSignIn(WidgetTester tester) async {
  await tapButton(tester, 'Sign In');
}

/// Tap the Create Account button on login screen.
Future<void> tapCreateAccount(WidgetTester tester) async {
  await tapButton(tester, 'Create new account');
}

/// Complete the create account form and submit.
Future<void> fillCreateAccountForm(
  WidgetTester tester, {
  String name = 'Test User',
  String email = 'test@example.com',
  String password = 'password123',
  String patientName = 'Test Patient',
}) async {
  await enterTextByLabel(tester, 'Full name', name);
  await tester.pump();
  await enterTextByLabel(tester, 'Email address', email);
  await tester.pump();
  await enterTextByLabel(tester, 'Password', password);
  await tester.pump();
  await enterTextByLabel(tester, 'Patient name', patientName);
  await tester.pump();
}

/// Accept terms and conditions checkbox.
Future<void> acceptTerms(WidgetTester tester) async {
  final checkbox = find.byType(Checkbox).first;
  await tester.tap(checkbox);
  await tester.pump();
}

/// Verify a SnackBar with the given text appears.
void expectSnackBar(String text) {
  expect(find.textContaining(text), findsOneWidget);
}

/// Tap on a navigation destination by label.
Future<void> tapNavDestination(WidgetTester tester, String label) async {
  final dest = find.byWidgetPredicate(
    (w) => w is NavigationDestination &&
        (w.label as Text).data?.contains(label) == true,
  );
  if (dest.evaluate().isNotEmpty) {
    await tester.tap(dest.first);
    await tester.pumpAndSettle();
  }
}
