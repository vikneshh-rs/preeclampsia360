import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import '../trends/bp_trend_graph.dart';
import 'nearby_hospitals_map_screen.dart';

class ReferralSheetScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String patientCode;
  final List<String> selectedMedicines;
  final String receivingFacilityName;
  final String? notes;
  final Map<String, dynamic>? referralData;

  const ReferralSheetScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.patientCode,
    required this.selectedMedicines,
    required this.receivingFacilityName,
    this.notes,
    this.referralData,
  });

  @override
  State<ReferralSheetScreen> createState() => _ReferralSheetScreenState();
}

class _ReferralSheetScreenState extends State<ReferralSheetScreen> {
  bool loading = true;
  String? error;

  Map<String, dynamic>? patient;
  Map<String, dynamic>? analytics;
  Map<String, dynamic>? riskProfile;
  List<BPTrendPoint> measurements = [];

  static const List<String> kAllStabilizationMeds = [
    'Tab Labetalol 100 mg',
    'Tab Nifidipine 10 mg',
    'IV MgSO4 4g iv',
    'IV Lasix',
    'Betamethasone 12mg',
    'Dexamethasone 12mg',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      final pRes = await ApiClient.instance.get('/api/v1/patients/${widget.patientId}');
      final tRes = await ApiClient.instance.get('/api/v1/patients/${widget.patientId}/bp-trends?period=all');
      final rRes = await ApiClient.instance.get('/api/v1/patients/${widget.patientId}/risk-profile');

      final rawPts = List<dynamic>.from(tRes['measurements'] ?? []);
      final pts = rawPts.map((j) => BPTrendPoint.fromJson(j as Map<String, dynamic>)).toList();

      if (mounted) {
        setState(() {
          patient = Map<String, dynamic>.from(pRes);
          analytics = Map<String, dynamic>.from(tRes['analytics'] ?? {});
          riskProfile = Map<String, dynamic>.from(rRes);
          measurements = pts;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<Uint8List> _generatePdfDocument(PdfPageFormat format) async {
    final pdf = pw.Document(title: 'Maternal Referral Sheet - ${widget.patientName}');

    final p = patient ?? {};
    final qData = (p['questionnaire_data'] is Map ? p['questionnaire_data'] as Map : {});
    final inv = (qData['investigations'] is Map ? qData['investigations'] as Map : {});
    final factors = List<Map<String, dynamic>>.from(riskProfile?['factors'] ?? []);

    final latestReading = analytics?['latest_reading'] as Map<String, dynamic>?;
    final bpStr = latestReading != null
        ? '${latestReading["systolic_mmhg"]} / ${latestReading["diastolic_mmhg"]} mmHg'
        : 'Severe Range';

    final referringDoctor = ApiClient.instance.currentUser?['full_name'] ?? 'Medical Officer';
    final referringFacility = ApiClient.instance.activeFacilityName ?? 'Primary Health Centre';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.red800, width: 2)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PREECLAMPSIA 360 - EMERGENCY MATERNAL REFERRAL SHEET',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Government of Puducherry - Department of Health & Family Welfare',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red100,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.red800),
                    ),
                    child: pw.Text(
                      'RED ALERT: SEVERE HTN',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Patient Information Table
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('PATIENT DETAILS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                      pw.Text('Date: ${DateTime.now().toString().substring(0, 16)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text('Name: ${p["full_name"] ?? widget.patientName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Expanded(child: pw.Text('ID: ${p["patient_code"] ?? widget.patientCode}', style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(child: pw.Text('Blood Group: ${p["blood_group"] ?? "—"}', style: const pw.TextStyle(fontSize: 9))),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text('LMP: ${p["lmp"] ?? "—"}', style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(child: pw.Text('EDD: ${p["edd"] ?? "—"}', style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(child: pw.Text('GPAL: G${p["gravida"] ?? "-"} P${p["parity"] ?? "-"} A${p["abortions"] ?? "-"} L${p["living_children"] ?? "-"}', style: const pw.TextStyle(fontSize: 9))),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text('Origin: $referringFacility', style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(child: pw.Text('Destination: ${widget.receivingFacilityName}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(child: pw.Text('Referring Officer: $referringDoctor', style: const pw.TextStyle(fontSize: 9))),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Emergency Pre-Referral Stabilization Section
            pw.Text(
              'EMERGENCY PRE-REFERRAL STABILIZATION MEDICINES ADMINISTERED',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
            ),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Medication', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Clinical Indication', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Status', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                ...kAllStabilizationMeds.map((med) {
                  final administered = widget.selectedMedicines.contains(med);
                  return pw.TableRow(
                    decoration: administered ? const pw.BoxDecoration(color: PdfColors.red50) : null,
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(med, style: pw.TextStyle(fontSize: 8, fontWeight: administered ? pw.FontWeight.bold : pw.FontWeight.normal)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(_getMedIndication(med), style: const pw.TextStyle(fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          administered ? '[YES] ADMINISTERED' : 'Not Given',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: administered ? PdfColors.green800 : PdfColors.grey600,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            if (widget.notes != null && widget.notes!.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Stabilization Notes: ${widget.notes}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
            ],
            pw.SizedBox(height: 12),

            // BP Trend Summary
            pw.Text(
              'BLOOD PRESSURE READINGS & LONGITUDINAL TREND',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Latest Verified BP', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.Text(bpStr, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Total Readings', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.Text('${measurements.length}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Elevated Readings', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.Text('${analytics?["elevated_count"] ?? 0}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Severe Readings', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.Text('${analytics?["severe_count"] ?? 0}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),

            // Recent BP Table
            if (measurements.isNotEmpty) ...[
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Date & Time', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Gestational Age', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('BP (mmHg)', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Pulse', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Status', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  ...measurements.take(6).map((m) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(m.measuredAt.toString().substring(0, 16), style: const pw.TextStyle(fontSize: 7))),
                        pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(m.gestationalAgeDisplay, style: const pw.TextStyle(fontSize: 7))),
                        pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('${m.systolic}/${m.diastolic}', style: pw.TextStyle(fontSize: 7, fontWeight: m.isSevere ? pw.FontWeight.bold : pw.FontWeight.normal, color: m.isSevere ? PdfColors.red800 : PdfColors.black))),
                        pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(m.pulse != null ? '${m.pulse} bpm' : '—', style: const pw.TextStyle(fontSize: 7))),
                        pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(m.isSevere ? 'SEVERE' : (m.isElevated ? 'ELEVATED' : 'NORMAL'), style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: m.isSevere ? PdfColors.red800 : (m.isElevated ? PdfColors.orange800 : PdfColors.green800)))),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 10),
            ],

            // Maternal Risk Factors
            pw.Text(
              'MATERNAL RISK PROFILE',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
            ),
            pw.SizedBox(height: 4),
            pw.Wrap(
              spacing: 8,
              runSpacing: 4,
              children: factors.map((f) {
                final isPresent = f['status'] == 'present';
                return pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: isPresent ? PdfColors.red100 : PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: isPresent ? PdfColors.red700 : PdfColors.grey400),
                  ),
                  child: pw.Text(
                    '${f["name"]}: ${f["status"]?.toString().toUpperCase()}',
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: isPresent ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: isPresent ? PdfColors.red900 : PdfColors.grey800,
                    ),
                  ),
                );
              }).toList(),
            ),
            pw.SizedBox(height: 10),

            // Lab Investigations
            if (inv.isNotEmpty) ...[
              pw.Text(
                'LABORATORY INVESTIGATIONS',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
              ),
              pw.SizedBox(height: 4),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Text('HB: ${inv["hb"] ?? "—"}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Urea: ${inv["urea"] ?? "—"}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Platelets: ${inv["platelet"] ?? "—"}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Creatinine: ${inv["creatinine"] ?? "—"}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('LFT: ${inv["lft"] ?? "—"}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
            ],

            // Handover & Authentication Footer
            pw.Spacer(),
            pw.Container(
              padding: const pw.EdgeInsets.only(top: 10),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 1)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Referring Medical Officer Signature:', style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 18),
                      pw.Text('Dr. $referringDoctor', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text(referringFacility, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Receiving Facility Handover:', style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 18),
                      pw.Text('Arrival Timestamp & Doctor Signature', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.Text('Seal / Facility Stamp', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static String _getMedIndication(String med) {
    switch (med) {
      case 'Tab Labetalol 100 mg':
        return 'Acute BP control (First-line)';
      case 'Tab Nifidipine 10 mg':
        return 'Rapid calcium channel blocker';
      case 'IV MgSO4 4g iv':
        return 'Eclampsia seizure prophylaxis loading dose';
      case 'IV Lasix':
        return 'Diuretic for pulmonary edema / fluid overload';
      case 'Betamethasone 12mg':
        return 'Fetal lung maturity maturation';
      case 'Dexamethasone 12mg':
        return 'Alternative fetal lung maturation';
      default:
        return 'Emergency stabilization protocol';
    }
  }

  Future<void> _downloadPdf() async {
    try {
      final bytes = await _generatePdfDocument(PdfPageFormat.a4);
      final filename = 'Referral_Sheet_${widget.patientCode}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      if (mounted) showMessage(context, 'PDF Generation error: $e', error: true);
    }
  }

  Future<void> _previewPdf() async {
    await Printing.layoutPdf(
      onLayout: (format) => _generatePdfDocument(format),
      name: 'Referral_Sheet_${widget.patientCode}',
    );
  }

  void _navigateToHospitalsMap() {
    final refId = widget.referralData?['id']?.toString();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NearbyHospitalsMapScreen(
          patientId: widget.patientId,
          patientName: widget.patientName,
          patientCode: widget.patientCode,
          selectedMedicines: widget.selectedMedicines,
          existingReferralId: refId,
          notes: widget.notes,
          referralData: widget.referralData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = patient ?? {};
    final latestReading = analytics?['latest_reading'] as Map<String, dynamic>?;
    final factors = List<Map<String, dynamic>>.from(riskProfile?['factors'] ?? []);

    final bpStr = latestReading != null
        ? '${latestReading["systolic_mmhg"]} / ${latestReading["diastolic_mmhg"]} mmHg'
        : 'Severe Hypertension';

    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F5),
      appBar: AppBar(
        title: Text(
          'Referral Sheet • ${widget.patientName}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Print / Fullscreen Preview',
            icon: const Icon(Icons.print_outlined),
            onPressed: loading ? null : _previewPdf,
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: loading ? null : _navigateToHospitalsMap,
            icon: const Icon(Icons.map_outlined, size: 16),
            label: const Text('Hospital Map', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF991B1B)),
            onPressed: loading ? null : _downloadPdf,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.crimson))
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 40, color: AppColors.critical),
                        const SizedBox(height: 10),
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _loadAll, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    // Emergency Header Banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF991B1B), Color(0xFFB91C1C)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.emergency_share, color: Colors.white, size: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PRE-REFERRAL EMERGENCY STABILIZATION SHEET',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Target: ${widget.receivingFacilityName}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'RED ALERT',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: _navigateToHospitalsMap,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.map_rounded, size: 18, color: Color(0xFF991B1B)),
                                  SizedBox(width: 8),
                                  Text(
                                    'View Nearby Maternity Hospitals Map (Puducherry)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF991B1B)),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF991B1B)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 1: Patient Demographics Card
                    _SectionTitle(title: 'Patient Profile & Obstetric Status', icon: Icons.person_pin_outlined),
                    const SizedBox(height: 6),
                    P360Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                p['full_name'] ?? widget.patientName,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                              ),
                              StatusPill(
                                p['blood_group'] != null ? 'Blood: ${p['blood_group']}' : 'Blood: —',
                                color: AppColors.crimson,
                              ),
                            ],
                          ),
                          Text(
                            'Patient ID: ${p['patient_code'] ?? widget.patientCode}  •  Phone: ${p['phone'] ?? "—"}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                          const Divider(height: 20),
                          Wrap(
                            spacing: 18,
                            runSpacing: 10,
                            children: [
                              _FieldItem('LMP', p['lmp'] ?? '—'),
                              _FieldItem('EDD', p['edd'] ?? '—'),
                              _FieldItem('Gravida (G)', p['gravida']?.toString() ?? '—'),
                              _FieldItem('Parity (P)', p['parity']?.toString() ?? '—'),
                              _FieldItem('Abortions (A)', p['abortions']?.toString() ?? '—'),
                              _FieldItem('Living (L)', p['living_children']?.toString() ?? '—'),
                              _FieldItem('Origin Facility', ApiClient.instance.activeFacilityName ?? 'PHC'),
                              _FieldItem('Destination', widget.receivingFacilityName),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 2: Stabilization Medicines Administered
                    _SectionTitle(title: 'Stabilization Medicines Administered at PHC', icon: Icons.medication_outlined),
                    const SizedBox(height: 6),
                    P360Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Emergency Pre-Referral Medication Protocol Checklist:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.ink),
                          ),
                          const SizedBox(height: 8),
                          ...kAllStabilizationMeds.map((med) {
                            final administered = widget.selectedMedicines.contains(med);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: administered ? const Color(0xFFFEF2F2) : const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: administered ? const Color(0xFFFCA5A5) : AppColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    administered ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 18,
                                    color: administered ? const Color(0xFFDC2626) : AppColors.muted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      med,
                                      style: TextStyle(
                                        fontWeight: administered ? FontWeight.w800 : FontWeight.w500,
                                        color: administered ? const Color(0xFF991B1B) : AppColors.muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    administered ? 'ADMINISTERED' : 'NOT GIVEN',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: administered ? const Color(0xFFDC2626) : AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (widget.notes != null && widget.notes!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.paleRose,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Notes: ${widget.notes}',
                                style: const TextStyle(fontSize: 12, color: AppColors.crimson),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 3: BP Trend Graph & Readings
                    _SectionTitle(title: 'Blood Pressure Trend Graph & Readings', icon: Icons.show_chart),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Latest Verified BP', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                  Text(
                                    bpStr,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF991B1B)),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${measurements.length} Readings Recorded',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Visual Line Chart
                          if (measurements.isNotEmpty)
                            BPTrendGraph(
                              measurements: measurements,
                              selectedPeriod: 'all',
                              onPeriodChanged: (_) {},
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('No verified readings to plot.')),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 4: Maternal Risk Profile
                    _SectionTitle(title: 'Maternal Risk Profile Factors', icon: Icons.warning_amber_outlined),
                    const SizedBox(height: 6),
                    P360Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (factors.isEmpty)
                            const Text('No risk factors recorded.')
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: factors.map((f) {
                                final isPresent = f['status'] == 'present';
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isPresent ? const Color(0xFFFEF2F2) : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isPresent ? const Color(0xFFF87171) : const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isPresent ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                                        size: 14,
                                        color: isPresent ? const Color(0xFFDC2626) : AppColors.muted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        f['name'] ?? '',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isPresent ? FontWeight.bold : FontWeight.w500,
                                          color: isPresent ? const Color(0xFF991B1B) : AppColors.slate,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Nearby Maternity Care Hospitals Map Navigation Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.map_rounded, color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Nearby Maternity Care Hospitals (Puducherry Map)',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0C4A6E)),
                                    ),
                                    Text(
                                      'JIPMER, IGMC&RI, PIMS, RGGWCH, SMVMCH',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF0369A1), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'View hospital locations on an interactive Puducherry map. Tap any hospital pin or name to assign this patient and dispatch this referral sheet directly to the receiving facility.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _navigateToHospitalsMap,
                              icon: const Icon(Icons.pin_drop_rounded, size: 18),
                              label: const Text(
                                'Open Puducherry Map & Route Referral',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Download / Print Action Card at bottom
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf, color: Color(0xFF991B1B), size: 28),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Download Official Referral Sheet',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  'Includes patient details, BP graph, risk factors, and stabilization medicines checklist.',
                                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF991B1B),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onPressed: _downloadPdf,
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF991B1B)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink),
        ),
      ],
    );
  }
}

class _FieldItem extends StatelessWidget {
  final String label;
  final String value;
  const _FieldItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

