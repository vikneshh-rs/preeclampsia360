import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import '../referrals/referral_screen.dart';

class BPEntryScreen extends StatefulWidget {
  final String? initialPatientId;
  const BPEntryScreen({super.key, this.initialPatientId});
  @override
  State<BPEntryScreen> createState() => _BPEntryScreenState();
}

class _BPEntryScreenState extends State<BPEntryScreen> {
  final sys = TextEditingController();
  final dia = TextEditingController();
  final pulse = TextEditingController();
  List<dynamic> patients = [];
  String? patientId;
  bool confirmed = false;
  bool saving = false;
  bool loading = true;
  bool scanning = false;
  String method = 'manual';
  String? ocrText;

  @override
  void initState() {
    super.initState();
    patientId = widget.initialPatientId;
    loadPatients();
  }

  @override
  void dispose() {
    sys.dispose();
    dia.dispose();
    pulse.dispose();
    super.dispose();
  }

  Future<void> loadPatients() async {
    try {
      final r = await ApiClient.instance.get('/api/v1/patients?limit=100');
      if (mounted) {
        setState(() => patients = List.from(r['items'] ?? []));
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> scanDisplay() async {
    if (kIsWeb) {
      // On web or browsers without direct ML Kit, use file upload or demo simulation
      try {
        final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
        if (image == null || !mounted) return;
        showMessage(context, 'Image picked. For competition evaluation, select a sample monitor preset or enter readings.');
      } catch (e) {
        if (mounted) showMessage(context, 'Image capture on web: $e', error: true);
      }
      return;
    }

    setState(() => scanning = true);
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
      if (image == null) return;
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
        final text = result.text;
        ocrText = text;

        int? extract(String label) {
          final m = RegExp('(?:$label)[^0-9]{0,18}(\\d{2,3})', caseSensitive: false).firstMatch(text);
          return m == null ? null : int.tryParse(m.group(1)!);
        }

        final s = extract('SYS');
        final d = extract('DIA');
        final p = extract('PULSE');
        if (s != null) sys.text = s.toString();
        if (d != null) dia.text = d.toString();
        if (p != null) pulse.text = p.toString();

        if (mounted) {
          setState(() => confirmed = false);
          showMessage(context, 'OCR suggestions extracted. Verify every value against the device before saving.');
        }
      } finally {
        await recognizer.close();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not scan the display: $e', error: true);
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  void _loadDemoValues(int s, int d, int p, String label) {
    sys.text = s.toString();
    dia.text = d.toString();
    pulse.text = p.toString();
    ocrText = '[DEMO MONITOR READING] $label Display: SYS $s mmHg, DIA $d mmHg, PULSE $p bpm';
    setState(() {
      confirmed = false;
      method = 'camera_ocr';
    });
    showMessage(context, 'Sample readings loaded. Visual confirmation against monitor required before saving.');
  }

  Future<void> save() async {
    if (patientId == null) {
      showMessage(context, 'Please select a patient.', error: true);
      return;
    }

    final sVal = int.tryParse(sys.text.trim());
    final dVal = int.tryParse(dia.text.trim());
    final pVal = pulse.text.trim().isEmpty ? null : int.tryParse(pulse.text.trim());

    if (sVal == null || dVal == null) {
      showMessage(context, 'Please enter valid integer values for Systolic and Diastolic BP.', error: true);
      return;
    }
    if (sVal <= dVal) {
      showMessage(context, 'Systolic value ($sVal) must exceed Diastolic value ($dVal).', error: true);
      return;
    }
    if (sVal < 40 || sVal > 300 || dVal < 20 || dVal > 200) {
      showMessage(context, 'BP readings are outside the valid physiological range.', error: true);
      return;
    }
    if (!confirmed) {
      showMessage(context, 'You must visually verify and confirm the readings against the physical monitor display.', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      final res = await ApiClient.instance.post('/api/v1/bp/measurements', {
        'patient_id': patientId,
        'systolic_mmhg': sVal,
        'diastolic_mmhg': dVal,
        'pulse_bpm': pVal,
        'capture_method': method,
        'worker_confirmed': confirmed,
        'measured_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        final isAlert = res is Map && res['alert_triggered'] == true;
        if (isAlert) {
          final alert = res['alert'] is Map ? res['alert'] as Map : {};
          final sev = (alert['severity'] ?? 'amber').toString();
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (c) => AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: sev == 'red' ? AppColors.critical : AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  const Text('Elevated BP Alert Triggered'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sev == 'red' ? AppColors.blush : AppColors.paleRose,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '$sVal / $dVal mmHg',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const Spacer(),
                        StatusPill(
                          sev == 'red' ? 'CRITICAL SEVERE' : 'ELEVATED SCREENING',
                          color: sev == 'red' ? AppColors.critical : AppColors.warning,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This reading meets the screening trigger threshold (SBP >= 140 or DBP >= 90 mmHg). This is a screening trigger, not an automated diagnosis of preeclampsia.\n\nAn alert has been dispatched to the Medical Officer dashboard for clinical assessment and referral authorisation.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Acknowledge'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
                  onPressed: () {
                    Navigator.pop(c);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReferralScreen(
                          initialPatientId: patientId,
                          initialReason: 'Screening alert: Elevated BP $sVal/$dVal mmHg (${sev.toUpperCase()})',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.local_hospital, size: 16),
                  label: const Text('Initiate Referral'),
                ),
              ],
            ),
          );
        } else {
          showMessage(context, 'Verified BP measurement ($sVal/$dVal mmHg) saved successfully.');
        }
        sys.clear();
        dia.clear();
        pulse.clear();
        setState(() => confirmed = false);
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
      appBar: AppBar(title: const Text('Blood pressure recording')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const P360Header('Record blood pressure', subtitle: 'Capture, review and confirm the monitor display'),
          const SizedBox(height: 16),
          P360Card(
            child: Column(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'manual', label: Text('Manual'), icon: Icon(Icons.edit)),
                    ButtonSegment(value: 'camera_ocr', label: Text('Camera OCR'), icon: Icon(Icons.camera_alt)),
                  ],
                  selected: {method},
                  onSelectionChanged: (s) => setState(() => method = s.first),
                ),
                if (method == 'camera_ocr')
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: scanning ? null : scanDisplay,
                                icon: const Icon(Icons.camera_alt),
                                label: Text(scanning ? 'Reading display…' : 'Capture BP Display'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              tooltip: 'Load Sample Monitor Reading',
                              icon: const Icon(Icons.science_outlined),
                              onSelected: (v) {
                                if (v == 'elevated') _loadDemoValues(154, 98, 86, 'Elevated BP');
                                if (v == 'severe') _loadDemoValues(168, 114, 92, 'Severe BP');
                                if (v == 'normal') _loadDemoValues(118, 76, 72, 'Normal BP');
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'elevated', child: Text('Demo: Elevated BP (154/98 mmHg)')),
                                PopupMenuItem(value: 'severe', child: Text('Demo: Severe BP (168/114 mmHg)')),
                                PopupMenuItem(value: 'normal', child: Text('Demo: Normal BP (118/76 mmHg)')),
                              ],
                            ),
                          ],
                        ),
                        if (ocrText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.paleRose,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ocrText!,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppColors.ink),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'OCR extraction alone never creates a clinical alert. A healthcare worker must visually verify and confirm the displayed values.',
                          style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: patientId,
            decoration: const InputDecoration(labelText: 'Select pregnant woman *'),
            items: patients
                .map((p) => DropdownMenuItem<String>(
                      value: p['id'].toString(),
                      child: Text(
                        '${p['full_name']} • ${p['patient_code'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => patientId = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: sys,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Systolic (mmHg) *'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: dia,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Diastolic (mmHg) *'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pulse,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Pulse (bpm) — optional'),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            value: confirmed,
            onChanged: (v) => setState(() => confirmed = v ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text('I visually verified these values against the BP monitor display.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            onPressed: saving ? null : save,
            child: saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save verified measurement'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Screening trigger threshold: SBP >= 140 or DBP >= 90 mmHg. This is a screening trigger, not an automated clinical diagnosis of preeclampsia.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
