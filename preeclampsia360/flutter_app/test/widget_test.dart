import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preeclampsia360/core/app.dart';
import 'package:preeclampsia360/features/auth/login_screen.dart';
import 'package:preeclampsia360/features/clinical/bp_entry_screen.dart';
import 'package:preeclampsia360/features/patients/patient_registration_screen.dart';
import 'package:preeclampsia360/features/referrals/referral_screen.dart';
import 'package:preeclampsia360/features/referrals/stabilize_patient_dialog.dart';
import 'package:preeclampsia360/features/trends/bp_trend_graph.dart';
import 'package:preeclampsia360/features/trends/bp_overview_card.dart';
import 'package:preeclampsia360/features/trends/trend_insights_view.dart';
import 'package:preeclampsia360/features/trends/maternal_risk_profile_view.dart';

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
    expect(find.text('Urine Protein (Albumin Dipstick)'), findsOneWidget);
    expect(find.text('Imminent Symptoms (Danger Signs)'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });

  testWidgets('4. Patient registration screen: validation and progression', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PatientRegistrationScreen()));
    await tester.pump();
    expect(find.text('Smart Pregnancy Registration'), findsOneWidget);
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

  testWidgets('6. BP Trend Graph and Overview Card rendering', (WidgetTester tester) async {
    final samplePoint1 = BPTrendPoint(
      id: 'm1',
      measuredAt: DateTime(2026, 11, 1),
      systolic: 120,
      diastolic: 78,
      pulse: 74,
      gestationalAgeWeeks: 26.0,
      gestationalAgeDisplay: '26w 0d',
      verificationStatus: 'worker_verified',
      workerConfirmed: true,
      captureMethod: 'manual',
      facilityName: 'Muthialpet PHC',
      recorderName: 'ANM Ananya',
      isElevated: false,
      isSevere: false,
    );

    final samplePoint2 = BPTrendPoint(
      id: 'm2',
      measuredAt: DateTime(2026, 11, 15),
      systolic: 146,
      diastolic: 94,
      pulse: 82,
      gestationalAgeWeeks: 28.0,
      gestationalAgeDisplay: '28w 0d',
      verificationStatus: 'worker_verified',
      workerConfirmed: true,
      captureMethod: 'camera_ocr',
      facilityName: 'Muthialpet PHC',
      recorderName: 'ANM Ananya',
      urineProtein: '1+',
      imminentSymptoms: ['Severe Headache'],
      isElevated: true,
      isSevere: false,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            BPOverviewCard(
              analytics: {
                'latest_reading': {'systolic_mmhg': 146, 'diastolic_mmhg': 94, 'measured_at': '2026-11-15T10:00:00Z'},
                'previous_reading': {'systolic_mmhg': 120, 'diastolic_mmhg': 78},
                'delta_systolic': 26,
                'delta_diastolic': 16,
                'verified_count': 2,
                'elevated_count': 1,
                'severe_count': 0,
                'trend_direction': 'rising',
              },
              screening: {
                'screening_status': 'elevated_screening',
                'status_label': 'Elevated BP screening',
                'repeat_confirmation_needed': true,
              },
              latestPoint: samplePoint2,
            ),
            BPTrendGraph(
              measurements: [samplePoint1, samplePoint2],
              selectedPeriod: 'all',
              onPeriodChanged: (_) {},
            ),
            TrendInsightsView(
              analytics: {
                'insights': [
                  {
                    'type': 'rising',
                    'statement': 'Systolic BP increased by 26 mmHg since previous reading.',
                    'value': '+26 mmHg',
                  }
                ],
                'verified_count': 2,
                'threshold_crossing_percentage': 50.0,
              },
            ),
            MaternalRiskProfileView(
              riskProfile: {
                'documented_risk_factors_count': 2,
                'unknown_count': 1,
                'summary_headline': '2 documented risk factors',
                'factors': [
                  {
                    'factor_key': 'nulliparity',
                    'name': 'Nulliparity (First Delivery)',
                    'status': 'present',
                    'detail': 'Parity 0',
                    'source': 'Obstetric History',
                  },
                ],
              },
            ),
          ],
        ),
      ),
    ));

    await tester.pump();
    expect(find.text('146 / 94'), findsOneWidget);
    expect(find.text('Elevated BP screening'), findsOneWidget);
    expect(find.text('Longitudinal Trend'), findsOneWidget);
    expect(find.text('Systolic (SBP)'), findsOneWidget);
    expect(find.text('Diastolic (DBP)'), findsOneWidget);
    expect(find.text('Clinical Trend Insights'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(find.text('Maternal Risk Profile'), findsOneWidget);
    expect(find.text('2 documented risk factors'), findsOneWidget);
  });

  testWidgets('7. Stabilize the Patient dialog with emergency medicines and referral initiation', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StabilizePatientDialog(
          patientId: 'p-test-1',
          patientName: 'Ananya Sharma',
          patientCode: 'PE360-TEST01',
          systolic: 168,
          diastolic: 118,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Stabilize the Patient'), findsOneWidget);
    expect(find.text('RED ALERT'), findsOneWidget);
    expect(find.text('Tab Labetalol 100 mg'), findsOneWidget);
    expect(find.text('Tab Nifidipine 10 mg'), findsOneWidget);
    expect(find.text('IV MgSO4 4g iv'), findsOneWidget);
    expect(find.text('IV Lasix'), findsOneWidget);
    expect(find.text('Betamethasone 12mg'), findsOneWidget);
    expect(find.text('Dexamethasone 12mg'), findsOneWidget);
    expect(find.text('Print Referral Sheet'), findsOneWidget);
  });
}
