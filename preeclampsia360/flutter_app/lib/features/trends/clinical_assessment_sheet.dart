import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';

class ClinicalAssessmentSheet extends StatefulWidget {
  final String patientId;
  final String patientName;
  final Map<String, dynamic> analytics;
  final Map<String, dynamic> screening;
  final Map<String, dynamic> riskProfile;
  final VoidCallback onAssessmentSaved;

  const ClinicalAssessmentSheet({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.analytics,
    required this.screening,
    required this.riskProfile,
    required this.onAssessmentSaved,
  });

  @override
  State<ClinicalAssessmentSheet> createState() => _ClinicalAssessmentSheetState();
}

class _ClinicalAssessmentSheetState extends State<ClinicalAssessmentSheet> {
  final formKey = GlobalKey<FormState>();
  bool saving = false;

  late TextEditingController trendSummaryCtrl;
  final clinicalImpressionCtrl = TextEditingController();
  final followUpCtrl = TextEditingController(text: 'Review blood pressure within 24–48 hours.');
  final clinicalNotesCtrl = TextEditingController();
  final labCtrl = TextEditingController();
  final fetalCtrl = TextEditingController();

  String urineProtein = 'not_tested';
  String referralDecision = 'no_referral_needed';
  final Set<String> selectedSymptoms = {};
  final Set<String> selectedRisks = {};

  static const List<String> kCommonSymptoms = [
    'Persistent Headache',
    'Visual Disturbances / Flashes',
    'Epigastric / RUQ Pain',
    'Facial / Hand Swelling',
    'Nausea / Vomiting',
    'Chest Pain / Dyspnea',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-populate trend summary from analytics
    final latest = widget.analytics['latest_reading'] as Map<String, dynamic>?;
    final prev = widget.analytics['previous_reading'] as Map<String, dynamic>?;
    final deltaSys = widget.analytics['delta_systolic'];
    final elevatedCount = widget.analytics['elevated_count'] ?? 0;
    final verifiedCount = widget.analytics['verified_count'] ?? 0;

    String initialSummary = '';
    if (latest != null) {
      initialSummary = 'Current verified BP: ${latest["systolic_mmhg"]}/${latest["diastolic_mmhg"]} mmHg.';
      if (prev != null && deltaSys != null) {
        initialSummary += ' Change of ${deltaSys > 0 ? "+$deltaSys" : "$deltaSys"} mmHg from prior reading (${prev["systolic_mmhg"]}/${prev["diastolic_mmhg"]}).';
      }
      initialSummary += ' $elevatedCount of $verifiedCount verified readings crossed screening thresholds.';
    }
    trendSummaryCtrl = TextEditingController(text: initialSummary);

    // Auto-detect high-risk factors
    final factors = List<Map<String, dynamic>>.from(widget.riskProfile['factors'] ?? []);
    for (final f in factors) {
      if (f['status'] == 'present') {
        selectedRisks.add(f['name']?.toString() ?? '');
      }
    }

    // Pre-populate lab findings if investigations recorded
    final inv = (widget.riskProfile['investigations'] as Map<String, dynamic>?) ?? {};
    if (inv.isNotEmpty) {
      final labParts = <String>[];
      if (inv['hb'] != null && inv['hb'].toString().trim().isNotEmpty) labParts.add('HB: ${inv['hb']}');
      if (inv['urea'] != null && inv['urea'].toString().trim().isNotEmpty) labParts.add('Urea: ${inv['urea']}');
      if (inv['platelet'] != null && inv['platelet'].toString().trim().isNotEmpty) labParts.add('Platelet: ${inv['platelet']}');
      if (inv['creatinine'] != null && inv['creatinine'].toString().trim().isNotEmpty) labParts.add('Creatinine: ${inv['creatinine']}');
      if (inv['lft'] != null && inv['lft'].toString().trim().isNotEmpty) labParts.add('LFT: ${inv['lft']}');
      if (labParts.isNotEmpty) {
        labCtrl.text = labParts.join(' • ');
      }
    }

    // Set clinical impression default
    final screeningStatus = widget.screening['screening_status']?.toString();
    if (screeningStatus == 'severe_screening') {
      clinicalImpressionCtrl.text = 'Severe-range blood pressure elevation. High suspicion of severe gestational hypertension / preeclampsia.';
      referralDecision = 'urgent_referral';
      followUpCtrl.text = 'Immediate clinical review and inpatient maternal/fetal evaluation.';
    } else if (screeningStatus == 'elevated_screening') {
      clinicalImpressionCtrl.text = 'Elevated blood pressure screening. Requires repeat measurement and diagnostic evaluation.';
      referralDecision = 'routine_referral';
      followUpCtrl.text = 'Repeat BP within 4 hours; follow up within 24–48 hours.';
    } else {
      clinicalImpressionCtrl.text = 'Blood pressure currently within screening threshold. Routine antenatal protocol.';
      referralDecision = 'no_referral_needed';
    }
  }

  @override
  void dispose() {
    trendSummaryCtrl.dispose();
    clinicalImpressionCtrl.dispose();
    followUpCtrl.dispose();
    clinicalNotesCtrl.dispose();
    labCtrl.dispose();
    fetalCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAssessment() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);

    try {
      final latest = widget.analytics['latest_reading'] as Map<String, dynamic>?;
      final refMeasIds = <String>[];
      if (latest != null && latest['id'] != null) {
        refMeasIds.add(latest['id'].toString());
      }

      final payload = {
        'bp_trend_summary': trendSummaryCtrl.text.trim(),
        'obstetric_risk_factors': selectedRisks.toList(),
        'maternal_symptoms': selectedSymptoms.toList(),
        'urine_protein': urineProtein == 'not_tested' ? null : urineProtein,
        'lab_investigations': labCtrl.text.trim().isNotEmpty ? {'summary': labCtrl.text.trim()} : null,
        'fetal_assessment': fetalCtrl.text.trim().isNotEmpty ? fetalCtrl.text.trim() : null,
        'clinical_impression': clinicalImpressionCtrl.text.trim(),
        'follow_up_recommendation': followUpCtrl.text.trim(),
        'referral_decision': referralDecision,
        'clinical_notes': clinicalNotesCtrl.text.trim().isNotEmpty ? clinicalNotesCtrl.text.trim() : null,
        'referenced_measurement_ids': refMeasIds,
      };

      await ApiClient.instance.post(
        '/api/v1/patients/${widget.patientId}/clinical-assessment',
        payload,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onAssessmentSaved();
        showMessage(context, 'Medical Officer clinical assessment documented successfully.');
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MO Assessment — ${widget.patientName}'),
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: saving ? null : _submitAssessment,
            child: saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Record', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7F1D3A))),
          ),
        ],
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.paleRose,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.assignment_ind_outlined, color: Color(0xFF7F1D3A), size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Documenting Medical Officer Assessment & Risk Evaluation. An immutable audit record will be logged upon submission.',
                      style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF7F1D3A), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Group 1: BP Trend Summary
            _sectionHeader('1. BP Trend & Pattern Summary'),
            TextFormField(
              controller: trendSummaryCtrl,
              maxLines: 2,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              decoration: const InputDecoration(
                labelText: 'BP Trend Summary *',
                helperText: 'Summary of longitudinal readings and screening pattern',
              ),
            ),
            const SizedBox(height: 16),

            // Group 2: Documented Maternal Risk Factors
            _sectionHeader('2. Maternal Risk Factors (Auto-detected)'),
            if (selectedRisks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('No high-risk maternal factors documented in profile.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: selectedRisks.map((rf) => Chip(
                  backgroundColor: AppColors.blush,
                  label: Text(rf, style: const TextStyle(fontSize: 11, color: Color(0xFF7F1D3A), fontWeight: FontWeight.bold)),
                  avatar: const Icon(Icons.check, size: 14, color: Color(0xFF7F1D3A)),
                )).toList(),
              ),
            const SizedBox(height: 16),

            // Group 3: Symptoms & Clinical Findings
            _sectionHeader('3. Maternal Symptoms & Urine Protein'),
            const Text(
              'Select any symptoms reported by the patient during current evaluation:',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: kCommonSymptoms.map((symptom) {
                final isSel = selectedSymptoms.contains(symptom);
                return FilterChip(
                  label: Text(symptom),
                  selected: isSel,
                  selectedColor: AppColors.blush,
                  checkmarkColor: const Color(0xFF7F1D3A),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    color: isSel ? const Color(0xFF7F1D3A) : AppColors.ink,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        selectedSymptoms.add(symptom);
                      } else {
                        selectedSymptoms.remove(symptom);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('urine_$urineProtein'),
              initialValue: urineProtein,
              decoration: const InputDecoration(
                labelText: 'Urine Protein Findings (Dipstick)',
                prefixIcon: Icon(Icons.water_drop_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'not_tested', child: Text('Not Tested / Pending')),
                DropdownMenuItem(value: 'nil', child: Text('Nil / Negative (0)')),
                DropdownMenuItem(value: 'trace', child: Text('Trace')),
                DropdownMenuItem(value: '1+', child: Text('+1 (30 mg/dL)')),
                DropdownMenuItem(value: '2+', child: Text('+2 (100 mg/dL)')),
                DropdownMenuItem(value: '3+', child: Text('+3 (300 mg/dL)')),
                DropdownMenuItem(value: '4+', child: Text('+4 (1000 mg/dL)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => urineProtein = v);
              },
            ),
            const SizedBox(height: 16),

            // Group 4: Laboratory & Fetal Assessment
            _sectionHeader('4. Laboratory & Fetal Findings'),
            TextFormField(
              controller: labCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Laboratory Investigations (Optional)',
                hintText: 'e.g. Platelets: 180k, AST/ALT: Normal, S. Creatinine: 0.7 mg/dL',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: fetalCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Fetal Assessment (Optional)',
                hintText: 'e.g. FHR: 142 bpm regular, active fetal movements, normal USG liquor',
              ),
            ),
            const SizedBox(height: 16),

            // Group 5: Clinical Impression, Follow-up & Referral
            _sectionHeader('5. Clinical Impression & Plan'),
            TextFormField(
              controller: clinicalImpressionCtrl,
              maxLines: 2,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              decoration: const InputDecoration(
                labelText: 'Medical Officer Clinical Impression *',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: followUpCtrl,
              maxLines: 2,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              decoration: const InputDecoration(
                labelText: 'Follow-up Recommendation *',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Referral Decision *',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.slate),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _decisionChip('no_referral_needed', 'No Referral', Colors.green),
                _decisionChip('routine_referral', 'Routine Referral', Colors.orange),
                _decisionChip('urgent_referral', 'Urgent Referral', const Color(0xFFDC2626)),
                _decisionChip('immediate_emergency', 'Emergency Transfer', const Color(0xFF7F1D3A)),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: clinicalNotesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Additional Clinical Notes (Optional)',
              ),
            ),
            const SizedBox(height: 20),

            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7F1D3A),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: saving ? null : _submitAssessment,
              child: saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save & Authorise Assessment', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF7F1D3A)),
        ),
      );

  Widget _decisionChip(String value, String label, Color color) {
    final isSel = referralDecision == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSel,
      selectedColor: color.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 11,
        color: isSel ? color : AppColors.ink,
        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (val) {
        if (val) setState(() => referralDecision = value);
      },
    );
  }
}

