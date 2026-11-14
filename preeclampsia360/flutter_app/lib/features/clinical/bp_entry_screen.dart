import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';

class BPEntryScreen extends StatefulWidget {
  const BPEntryScreen({super.key});
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
      showMessage(context, 'On-device OCR is currently supported in the Android build. Use manual entry on Web.', error: true);
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
      await ApiClient.instance.post('/api/v1/bp/measurements', {
        'patient_id': patientId,
        'systolic_mmhg': sVal,
        'diastolic_mmhg': dVal,
        'pulse_bpm': pVal,
        'capture_method': method,
        'worker_confirmed': confirmed,
        'measured_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        showMessage(context, 'Verified BP measurement saved successfully.');
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
                        OutlinedButton.icon(
                          onPressed: scanning ? null : scanDisplay,
                          icon: const Icon(Icons.camera_alt),
                          label: Text(scanning ? 'Reading display…' : 'Capture BP monitor display'),
                        ),
                        if (ocrText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              ocrText!,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ),
                        const SizedBox(height: 6),
                        const Text(
                          'OCR is only a suggestion. A worker must visually verify the displayed SYS, DIA and pulse values.',
                          style: TextStyle(color: AppColors.warning, fontSize: 12),
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
            decoration: const InputDecoration(labelText: 'Select patient'),
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
                  decoration: const InputDecoration(labelText: 'Systolic (mmHg)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: dia,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Diastolic (mmHg)'),
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
            onPressed: saving ? null : save,
            child: saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save verified measurement'),
          ),
          const SizedBox(height: 12),
          const Text(
            'This screen records a measurement. It does not independently diagnose preeclampsia or replace clinical assessment.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
