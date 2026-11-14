import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preeclampsia360/core/app.dart';
import 'package:preeclampsia360/features/auth/login_screen.dart';
import 'package:preeclampsia360/features/clinical/bp_entry_screen.dart';
import 'package:preeclampsia360/features/patients/patient_registration_screen.dart';
import 'package:preeclampsia360/features/referrals/referral_screen.dart';

void main() {
  testWidgets('1. Application startup smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const Preeclampsia360App());
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('2. Login screen input and PIN validation', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Healthcare Worker Login'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);

    // Try submitting empty
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Enter your assigned ID and 6-digit PIN.'), findsOneWidget);

    // Enter ID and 5-digit PIN (invalid length)
    await tester.enterText(find.byType(TextField).first, 'PY-PHC-ANM-01');
    await tester.enterText(find.byType(TextField).last, '12345');
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Enter your assigned ID and 6-digit PIN.'), findsOneWidget);
  });

  testWidgets('3. BP Entry screen elements and rendering', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: BPEntryScreen()));
    await tester.pump();
    expect(find.text('Record blood pressure'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Camera OCR'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });

  testWidgets('4. Patient registration screen: validation and progression', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PatientRegistrationScreen()));
    await tester.pump();
    expect(find.text('Register pregnant woman'), findsOneWidget);
    expect(find.text('Mother’s details'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    // Enter required name
    await tester.enterText(find.byType(TextFormField).first, 'Ananya Sharma');
    await tester.pump();

    // Tap Continue button
    final continueBtn = find.text('Continue');
    await tester.ensureVisible(continueBtn);
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('Obstetric history'), findsOneWidget);
  });

  testWidgets('5. Referral screen displays header and create button', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ReferralScreen())));
    await tester.pump();
    expect(find.text('Referral coordination'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
