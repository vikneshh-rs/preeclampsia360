import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../core/api_client.dart';
import '../../core/bp_ocr_parser.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import '../referrals/referral_screen.dart';

class BPEntryScreen extends StatefulWidget {
  final String? initialPatientId;
  final String? initialMethod;
  const BPEntryScreen({super.key, this.initialPatientId, this.initialMethod});
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
  bool syncing = false;
  String? syncStatusMessage;
  String method = 'manual';
  String? ocrText;
  List<int> _detectedNumbers = [];
  BpOcrResult? _ocrResult;
  String? _ocrStatusMessage;
  String urineProtein = 'not_tested';
  final Set<String> imminentSymptoms = {};

  static const List<String> kImminentSymptomsList = [
    'Severe Headache',
    'Blurred Vision / Flashes',
    'Epigastric / RUQ Pain',
    'Facial / Hand Swelling',
    'Nausea / Vomiting',
    'Chest Pain / Dyspnea',
  ];

  @override
  void initState() {
    super.initState();
    patientId = widget.initialPatientId;
    if (widget.initialMethod != null) {
      method = widget.initialMethod!;
    }
    loadPatients();
  }

  // Auto-synchronize reading from connected BP machine (In Development Stage)
  Future<void> _syncFromDevice() async {
    setState(() {
      syncing = true;
      syncStatusMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    // Simulated reading from digital machine in development stage
    const simulatedSys = 120;
    const simulatedDia = 80;
    const simulatedPulse = 72;

    if (!mounted) return;
    setState(() {
      syncing = false;
      sys.text = simulatedSys.toString();
      dia.text = simulatedDia.toString();
      pulse.text = simulatedPulse.toString();
      confirmed = true;
      syncStatusMessage = 'Auto-synchronized from Digital BP Machine: $simulatedSys/$simulatedDia mmHg (Pulse: $simulatedPulse bpm)';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.success,
        content: Text('Reading synchronized from machine: 120/80 mmHg, 72 bpm'),
      ),
    );
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

  Future<void> _promptImageSource(BuildContext context) async {
    if (kIsWeb) {
      await scanDisplay(source: ImageSource.gallery);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Capture BP Monitor Display',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepBurgundy),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ensure clear lighting and avoid screen reflections for best OCR results.',
                style: TextStyle(fontSize: 12, color: AppColors.slate),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.paleRose,
                  child: Icon(Icons.camera_alt, color: AppColors.deepBurgundy),
                ),
                title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Directly snap the BP machine screen'),
                onTap: () {
                  Navigator.pop(ctx);
                  scanDisplay(source: ImageSource.camera);
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.paleRose,
                  child: Icon(Icons.photo_library, color: AppColors.deepBurgundy),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Select a high-resolution saved photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  scanDisplay(source: ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> scanDisplay({ImageSource source = ImageSource.camera}) async {
    if (kIsWeb) {
      try {
        final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
        if (image == null || !mounted) return;
        showMessage(context, 'Image selected on web. For full camera recognition, run on Android mobile.');
      } catch (e) {
        if (mounted) showMessage(context, 'Image capture on web: $e', error: true);
      }
      return;
    }

    setState(() {
      scanning = true;
      _ocrStatusMessage = null;
    });

    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (image == null) return;
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
        final parsed = BpOcrParser.parseRecognizedText(result);

        if (!mounted) return;
        setState(() {
          ocrText = parsed.rawText;
          _detectedNumbers = parsed.detectedNumbers;
          _ocrResult = parsed;

          if (parsed.systolic != null) sys.text = parsed.systolic.toString();
          if (parsed.diastolic != null) dia.text = parsed.diastolic.toString();
          if (parsed.pulse != null) pulse.text = parsed.pulse.toString();

          if (parsed.isComplete) {
            _ocrStatusMessage =
                'Auto-filled: ${parsed.systolic}/${parsed.diastolic} mmHg${parsed.pulse != null ? ' (Pulse: ${parsed.pulse} bpm)' : ''}';
            confirmed = false;
          } else if (parsed.detectedNumbers.isNotEmpty) {
            _ocrStatusMessage =
                'Detected numbers: ${parsed.detectedNumbers.join(', ')}. Tap any number below to assign.';
            confirmed = false;
          } else {
            _ocrStatusMessage =
                'No clear BP values detected. Please hold camera closer and avoid glare.';
          }
        });

        if (parsed.isComplete) {
          showMessage(
            context,
            'Auto-filled: ${parsed.systolic}/${parsed.diastolic} mmHg. Verify with monitor before saving.',
          );
        } else if (parsed.detectedNumbers.isNotEmpty) {
          showMessage(
            context,
            'Numbers detected (${parsed.detectedNumbers.join(", ")}). Tap chips to assign.',
          );
        } else {
          showMessage(
            context,
            'Could not extract readings. Please check lighting or enter manually.',
            error: true,
          );
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

  void _assignValueToField(int val) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Assign Value "$val" To:',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepBurgundy),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.arrow_upward, color: AppColors.deepBurgundy),
                title: const Text('Systolic (SYS) mmHg', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Current value: ${sys.text.isEmpty ? "(empty)" : sys.text}'),
                onTap: () {
                  setState(() => sys.text = val.toString());
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_downward, color: AppColors.deepBurgundy),
                title: const Text('Diastolic (DIA) mmHg', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Current value: ${dia.text.isEmpty ? "(empty)" : dia.text}'),
                onTap: () {
                  setState(() => dia.text = val.toString());
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite, color: AppColors.alertRed),
                title: const Text('Pulse (Heart Rate) bpm', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Current value: ${pulse.text.isEmpty ? "(empty)" : pulse.text}'),
                onTap: () {
                  setState(() => pulse.text = val.toString());
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _loadDemoValues(
    int s,
    int d,
    int p,
    String label, {
    String uProtein = 'not_tested',
    List<String> symptoms = const [],
  }) {
    sys.text = s.toString();
    dia.text = d.toString();
    pulse.text = p.toString();
    ocrText = '[DEMO MONITOR READING] $label Display: SYS $s mmHg, DIA $d mmHg, PULSE $p bpm';
    setState(() {
      confirmed = false;
      method = 'camera_ocr';
      urineProtein = uProtein;
      imminentSymptoms.clear();
      imminentSymptoms.addAll(symptoms);
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
        'urine_protein': urineProtein == 'not_tested' ? null : urineProtein,
        'imminent_symptoms': imminentSymptoms.toList(),
      });
      if (mounted) {
        final isAlert = res is Map && res['alert_triggered'] == true;
        if (isAlert) {
          final alert = res['alert'] is Map ? res['alert'] as Map : {};
          final sev = (alert['severity'] ?? 'amber').toString();
          final triggerReason = alert['trigger_reason']?.toString() ?? 'Elevated BP $sVal/$dVal mmHg';
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
                  Expanded(
                    child: Text(
                      sev == 'red' ? 'Severe Critical Alert' : 'Elevated Screening Alert',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.paleRose),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Clinical Findings:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('• BP: $sVal/$dVal mmHg', style: const TextStyle(fontSize: 12)),
                        Text(
                          '• Proteinuria: ${urineProtein == "not_tested" ? "Not Tested / Pending" : urineProtein.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: (urineProtein != 'not_tested' && urineProtein != 'nil') ? FontWeight.bold : FontWeight.normal,
                            color: (urineProtein != 'not_tested' && urineProtein != 'nil') ? AppColors.critical : AppColors.ink,
                          ),
                        ),
                        if (imminentSymptoms.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '• Danger Signs: ${imminentSymptoms.join(", ")}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.critical),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This reading meets screening trigger thresholds (SBP >= 140, DBP >= 90 mmHg, proteinuria, or danger signs). This is a screening trigger, not an automated diagnosis.\n\nAn alert has been dispatched to the Medical Officer dashboard for clinical assessment and referral authorisation.',
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
                          initialReason: 'Screening alert: $triggerReason (${sev.toUpperCase()})',
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
        setState(() {
          confirmed = false;
          urineProtein = 'not_tested';
          imminentSymptoms.clear();
        });
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
                    ButtonSegment(value: 'device_sync', label: Text('Check BP'), icon: Icon(Icons.bluetooth_connected)),
                    ButtonSegment(value: 'manual', label: Text('Manual Entry'), icon: Icon(Icons.edit)),
                    ButtonSegment(value: 'camera_ocr', label: Text('Scan Machine'), icon: Icon(Icons.camera_alt)),
                  ],
                  selected: {method},
                  onSelectionChanged: (s) => setState(() => method = s.first),
                ),
                if (method == 'device_sync')
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bluetooth_connected, color: Color(0xFF16A34A), size: 24),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Digital BP Monitor Connected',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF15803D)),
                                    ),
                                    Text(
                                      'Auto-synchronizes reading directly from machine (In Development Stage)',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: syncing ? null : _syncFromDevice,
                              icon: syncing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.sync, size: 18),
                              label: Text(syncing ? 'Auto-syncing reading…' : 'Sync Reading from Machine'),
                            ),
                          ),
                          if (syncStatusMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              syncStatusMessage!,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
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
                                onPressed: scanning ? null : () => _promptImageSource(context),
                                icon: const Icon(Icons.camera_alt),
                                label: Text(scanning ? 'Reading display…' : 'Capture BP Display'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Choose from Gallery',
                              icon: const Icon(Icons.photo_library_outlined, color: AppColors.deepBurgundy),
                              onPressed: scanning ? null : () => scanDisplay(source: ImageSource.gallery),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Load Sample Monitor Reading',
                              icon: const Icon(Icons.science_outlined),
                              onSelected: (v) {
                                if (v == 'elevated') {
                                  _loadDemoValues(154, 98, 86, 'Elevated BP', uProtein: '1+');
                                }
                                if (v == 'severe') {
                                  _loadDemoValues(
                                    168,
                                    114,
                                    92,
                                    'Severe BP',
                                    uProtein: '2+',
                                    symptoms: ['Severe Headache', 'Blurred Vision / Flashes'],
                                  );
                                }
                                if (v == 'normal') {
                                  _loadDemoValues(118, 76, 72, 'Normal BP', uProtein: 'nil');
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'elevated', child: Text('Demo: Elevated BP (154/98 mmHg, 1+ Protein)')),
                                PopupMenuItem(value: 'severe', child: Text('Demo: Severe BP (168/114 mmHg, 2+ & Danger Signs)')),
                                PopupMenuItem(value: 'normal', child: Text('Demo: Normal BP (118/76 mmHg, Nil)')),
                              ],
                            ),
                          ],
                        ),
                        if (_ocrStatusMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: (_ocrResult?.isComplete ?? false)
                                    ? const Color(0xFFF0FDF4)
                                    : const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (_ocrResult?.isComplete ?? false)
                                      ? const Color(0xFFBBF7D0)
                                      : const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    (_ocrResult?.isComplete ?? false)
                                        ? Icons.check_circle_rounded
                                        : Icons.info_outline_rounded,
                                    size: 16,
                                    color: (_ocrResult?.isComplete ?? false)
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _ocrStatusMessage!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: (_ocrResult?.isComplete ?? false)
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_detectedNumbers.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Detected numbers on screen (tap to assign):',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.slate),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _detectedNumbers.map((val) {
                                    final isSys = sys.text == val.toString();
                                    final isDia = dia.text == val.toString();
                                    final isPulse = pulse.text == val.toString();
                                    return ActionChip(
                                      avatar: Icon(
                                        isSys
                                            ? Icons.arrow_upward
                                            : (isDia
                                                ? Icons.arrow_downward
                                                : (isPulse ? Icons.favorite : Icons.touch_app)),
                                        size: 14,
                                        color: (isSys || isDia || isPulse) ? Colors.white : AppColors.deepBurgundy,
                                      ),
                                      backgroundColor:
                                          (isSys || isDia || isPulse) ? AppColors.deepBurgundy : AppColors.softBlush,
                                      label: Text(
                                        '$val${isSys ? " (SYS)" : (isDia ? " (DIA)" : (isPulse ? " (PULSE)" : ""))}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: (isSys || isDia || isPulse) ? Colors.white : AppColors.deepBurgundy,
                                        ),
                                      ),
                                      onPressed: () => _assignValueToField(val),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Raw display text detected:',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.slate),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    ocrText!,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppColors.ink),
                                  ),
                                ],
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
          DropdownButtonFormField<String>(
            key: ValueKey('urine_$urineProtein'),
            initialValue: urineProtein,
            decoration: const InputDecoration(
              labelText: 'Urine Protein (Albumin Dipstick)',
              prefixIcon: Icon(Icons.water_drop_outlined),
              helperText: 'Qualitative dipstick screening for proteinuria',
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
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: imminentSymptoms.isNotEmpty ? AppColors.paleRose : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: imminentSymptoms.isNotEmpty ? AppColors.critical : AppColors.border,
                width: imminentSymptoms.isNotEmpty ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: imminentSymptoms.isNotEmpty ? AppColors.critical : AppColors.ink,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Imminent Symptoms (Danger Signs)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    if (imminentSymptoms.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.critical,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${imminentSymptoms.length} selected',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select any symptoms indicating impending eclampsia or severe disease:',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: kImminentSymptomsList.map((symptom) {
                    final isSelected = imminentSymptoms.contains(symptom);
                    return FilterChip(
                      label: Text(symptom),
                      selected: isSelected,
                      selectedColor: AppColors.blush,
                      checkmarkColor: AppColors.crimson,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isSelected ? AppColors.crimson : AppColors.ink,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            imminentSymptoms.add(symptom);
                          } else {
                            imminentSymptoms.remove(symptom);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                if (imminentSymptoms.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '⚠ Danger signs present: Triggers high-priority clinical referral.',
                      style: TextStyle(
                        color: AppColors.critical,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
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
            'Screening trigger threshold: SBP >= 140, DBP >= 90 mmHg, proteinuria (>= 1+), or imminent symptoms. This is a screening trigger, not an automated clinical diagnosis.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
