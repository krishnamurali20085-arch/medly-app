import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medly/main.dart';

void main() {
  testWidgets('Medly shows the caregiver login screen before the dashboard', (tester) async {
    await tester.pumpWidget(const MedlyApp());

    expect(find.text('Caregiver Access'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Emergency SOS'), findsNothing);
  });

  testWidgets('Caregiver can create an account and add a patient profile', (tester) async {
    await tester.pumpWidget(const MedlyApp());

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Create caregiver account'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Aisha');
    await tester.enterText(find.byType(TextFormField).at(1), 'aisha@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'Password123');
    await tester.enterText(find.byType(TextFormField).at(3), 'Raj');

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Raj'), findsOneWidget);
  });
}
