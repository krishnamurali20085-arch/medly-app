import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Login & Signup E2E', () {
    testWidgets('App launches and shows splash screen', (tester) async {
      await tester.pumpWidget(const MedlyApp());
      // Splash should show the logo
      expect(find.byType(Image), findsWidgets);
      // Wait for splash to finish
      await tester.pumpAndSettle(const Duration(seconds: 3));
      // Should show login screen
      expect(find.text('Welcome to Medly'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('Login screen shows all required elements', (tester) async {
      await pumpMedlyApp(tester);
      // Check all UI elements exist
      expect(find.text('Welcome to Medly'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Create new account'), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsOneWidget);
    });

    testWidgets('Cannot sign in without accepting terms', (tester) async {
      await pumpMedlyApp(tester);
      await enterTextByLabel(tester, 'Email', 'test@example.com');
      await enterTextByLabel(tester, 'Password', 'password123');
      await tapSignIn(tester);
      // Should show terms error
      expect(find.text('Please accept Terms & Conditions to continue.'),
          findsOneWidget);
    });

    testWidgets('Cannot sign in with empty fields', (tester) async {
      await pumpMedlyApp(tester);
      await tapSignIn(tester);
      expect(find.text('Please enter both email and password.'),
          findsOneWidget);
    });

    testWidgets('Login fails with wrong credentials', (tester) async {
      await pumpMedlyApp(tester);
      await acceptTerms(tester);
      await enterTextByLabel(tester, 'Email', 'wrong@example.com');
      await enterTextByLabel(tester, 'Password', 'wrongpass');
      await tapSignIn(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.textContaining('Account not found'), findsOneWidget);
    });

    testWidgets('Navigate to create account screen', (tester) async {
      await pumpMedlyApp(tester);
      await tapCreateAccount(tester);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Set up your profile and link a patient.'), findsOneWidget);
    });

    testWidgets('Create account form has all fields', (tester) async {
      await pumpMedlyApp(tester);
      await tapCreateAccount(tester);
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Role'), findsOneWidget);
      expect(find.text('Patient name'), findsOneWidget);
      expect(find.text('I accept the Terms & Conditions'), findsOneWidget);
    });

    testWidgets('Cannot create account without terms', (tester) async {
      await pumpMedlyApp(tester);
      await tapCreateAccount(tester);
      await fillCreateAccountForm(tester);
      await tapButton(tester, 'Create account');
      expect(find.text('Please accept Terms & Conditions to continue.'),
          findsOneWidget);
    });

    testWidgets('Create account with all fields filled', (tester) async {
      await pumpMedlyApp(tester);
      await tapCreateAccount(tester);
      await fillCreateAccountForm(
        tester,
        name: 'Test Doctor',
        email: 'doctor@test.com',
        password: 'test1234',
        patientName: 'Patient One',
      );
      await acceptTerms(tester);
      await tapButton(tester, 'Create account');
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // Should navigate to onboarding (blood group, allergies, etc.)
      expect(find.text('Complete Your Profile'), findsOneWidget);
    });

    testWidgets('Can navigate back from create account', (tester) async {
      await pumpMedlyApp(tester);
      await tapCreateAccount(tester);
      expect(find.text('Create Account'), findsOneWidget);
      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Medly'), findsOneWidget);
    });

    testWidgets('Theme toggle works on login screen', (tester) async {
      await pumpMedlyApp(tester);
      // Tap theme toggle
      await tester.tap(find.byIcon(Icons.dark_mode_rounded));
      await tester.pumpAndSettle();
      // Should show light mode icon now
      expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    });

    testWidgets('Terms & Conditions page opens from login', (tester) async {
      await pumpMedlyApp(tester);
      await tester.tap(find.text('Terms & Conditions'));
      await tester.pumpAndSettle();
      expect(find.text('Terms & Conditions'), findsWidgets);
      expect(find.text('Medly - Terms & Conditions'), findsOneWidget);
    });
  });
}
