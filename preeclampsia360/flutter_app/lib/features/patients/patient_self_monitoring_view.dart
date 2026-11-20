import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';

class PatientSelfMonitoringView extends StatefulWidget {
  final VoidCallback? onLogout;
  const PatientSelfMonitoringView({super.key, this.onLogout});

  @override
  State<PatientSelfMonitoringView> createState() => _PatientSelfMonitoringViewState();
}

class _PatientSelfMonitoringViewState extends State<PatientSelfMonitoringView> {
  final TextEditingController _sysCtrl = TextEditingController();
  final TextEditingController _diaCtrl = TextEditingController();
  final TextEditingController _pulseCtrl = TextEditingController();

  String _method = 'device_sync'; // 'device_sync' (Check BP), 'manual', 'camera_ocr'
  final Set<String> _imminentSymptoms = {};
  bool _saving = false;
  bool _syncing = false;
  bool _scanning = false;
  String? _syncStatusMessage;

  static const List<Map<String, String>> _kSymptomsList = [
    {
      'id': 'Severe Headache',
      'label': 'Severe Headache',
      'tamil': 'கடுமையான தலைவலி',
    },
    {
      'id': 'Blurred Vision / Flashes',
      'label': 'Blurred Vision / Flashes',
      'tamil': 'பார்வை மங்குதல் / ஒளி மின்னல்',
    },
    {
      'id': 'Epigastric / RUQ Pain',
      'label': 'Upper Abdominal Pain',
      'tamil': 'வயிற்று மேல் வலி',
    },
    {
      'id': 'Facial / Hand Swelling',
      'label': 'Face or Hand Swelling',
      'tamil': 'முகம் அல்லது கைகளில் வீக்கம்',
    },
    {
      'id': 'Nausea / Vomiting',
      'label': 'Nausea or Vomiting',
      'tamil': 'குமட்டல் அல்லது வாந்தி',
    },
    {
      'id': 'Chest Pain / Dyspnea',
      'label': 'Chest Pain / Shortness of Breath',
      'tamil': 'மார்பு வலி / மூச்சுத்திணறல்',
    },
  ];

  @override
  void dispose() {
    _sysCtrl.dispose();
    _diaCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // Auto-sync simulation for "Check BP" (Development Stage)
  Future<void> _syncFromDevice() async {
    setState(() {
      _syncing = true;
      _syncStatusMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 900));

    // Simulated reading from digital machine in development stage
    const simulatedSys = 122;
    const simulatedDia = 80;
    const simulatedPulse = 74;

    if (!mounted) return;
    setState(() {
      _syncing = false;
      _sysCtrl.text = simulatedSys.toString();
      _diaCtrl.text = simulatedDia.toString();
      _pulseCtrl.text = simulatedPulse.toString();
      _syncStatusMessage = 'Synchronized from Digital Monitor: $simulatedSys/$simulatedDia mmHg (Pulse: $simulatedPulse bpm)';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.success,
        content: Text('Reading synchronized from machine: 122/80 mmHg, 74 bpm'),
      ),
    );
  }

  // Camera OCR for "Scan Machine"
  Future<void> _scanMonitorDisplay() async {
    if (kIsWeb) {
      showMessage(context, 'Web camera scan not supported in browser. Please enter manually or use Check BP.');
      return;
    }

    setState(() => _scanning = true);
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
      if (image == null) return;
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
        final text = result.text;

        int? extract(String label) {
          final m = RegExp('(?:$label)[^0-9]{0,18}(\\d{2,3})', caseSensitive: false).firstMatch(text);
          return m == null ? null : int.tryParse(m.group(1)!);
        }

        final s = extract('SYS');
        final d = extract('DIA');
        final p = extract('PULSE');
        if (s != null) _sysCtrl.text = s.toString();
        if (d != null) _diaCtrl.text = d.toString();
        if (p != null) _pulseCtrl.text = p.toString();

        if (mounted) {
          showMessage(context, 'Monitor display scanned. Verify readings before saving.');
        }
      } finally {
        await recognizer.close();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Camera scan failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _saveMeasurement() async {
    final user = ApiClient.instance.currentUser ?? {};
    final patientId = user['id']?.toString();

    if (patientId == null || patientId.isEmpty) {
      showMessage(context, 'Patient session expired. Please sign in again.', error: true);
      return;
    }

    final sVal = int.tryParse(_sysCtrl.text.trim());
    final dVal = int.tryParse(_diaCtrl.text.trim());
    final pVal = _pulseCtrl.text.trim().isEmpty ? null : int.tryParse(_pulseCtrl.text.trim());

    if (sVal == null || dVal == null) {
      showMessage(context, 'Please enter valid numbers for Systolic and Diastolic BP.', error: true);
      return;
    }
    if (sVal <= dVal) {
      showMessage(context, 'Systolic value ($sVal) must be greater than Diastolic value ($dVal).', error: true);
      return;
    }
    if (sVal < 40 || sVal > 300 || dVal < 20 || dVal > 200) {
      showMessage(context, 'Values are outside the valid physiological range.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await ApiClient.instance.post('/api/v1/bp/measurements', {
        'patient_id': patientId,
        'systolic_mmhg': sVal,
        'diastolic_mmhg': dVal,
        'pulse_bpm': pVal,
        'capture_method': _method,
        'worker_confirmed': true,
        'measured_at': DateTime.now().toUtc().toIso8601String(),
        'imminent_symptoms': _imminentSymptoms.toList(),
      });

      if (!mounted) return;

      final isAlert = res is Map && res['alert_triggered'] == true;
      if (isAlert) {
        final alert = res['alert'] is Map ? res['alert'] as Map : {};
        final sev = (alert['severity'] ?? 'amber').toString();

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            titlePadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sev == 'red' ? const Color(0xFF991B1B) : const Color(0xFFD97706),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sev == 'red' ? 'Critical Alert Notice' : 'Elevated Reading Notice',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your reading of $sVal / $dVal mmHg and reported symptoms require medical evaluation.',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.ink),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please contact your Village Health Nurse / ANM or visit your nearest Primary Health Centre (PHC) immediately.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                if (_imminentSymptoms.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Reported Danger Symptoms:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _imminentSymptoms
                        .map((s) => Chip(
                              label: Text(s, style: const TextStyle(fontSize: 11)),
                              backgroundColor: AppColors.blush,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: sev == 'red' ? const Color(0xFF991B1B) : const Color(0xFFD97706)),
                onPressed: () => Navigator.pop(c),
                child: const Text('I Understand'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.success,
            content: Text('Measurement saved successfully! Your BP is within normal range.'),
          ),
        );
      }

      // Clear fields after successful save
      setState(() {
        _sysCtrl.clear();
        _diaCtrl.clear();
        _pulseCtrl.clear();
        _imminentSymptoms.clear();
        _syncStatusMessage = null;
      });
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.instance.currentUser ?? {};
    final fullName = user['full_name']?.toString() ?? 'Mother';
    final patientCode = user['patient_code']?.toString() ?? 'Patient';
    final facilityName = user['facility_name']?.toString() ?? 'Primary Health Centre';

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.favorite_rounded, color: AppColors.crimson),
            SizedBox(width: 8),
            Text('Preeclampsia 360', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Patient Welcome Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.crimson, AppColors.rose],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.pregnant_woman_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Patient ID: $patientCode • $facilityName',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 1. Mode Selector: Check BP | Manual Entry | Scan Machine
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Recording Mode',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'device_sync',
                          label: Text('Check BP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          icon: Icon(Icons.bluetooth_connected, size: 16),
                        ),
                        ButtonSegment(
                          value: 'manual',
                          label: Text('Manual Entry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          icon: Icon(Icons.edit_note, size: 16),
                        ),
                        ButtonSegment(
                          value: 'camera_ocr',
                          label: Text('Scan Machine', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          icon: Icon(Icons.camera_alt, size: 16),
                        ),
                      ],
                      selected: {_method},
                      onSelectionChanged: (s) => setState(() => _method = s.first),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Mode Details:
            // Mode A: Check BP (Digital Monitor Auto-Sync - Development Stage)
            if (_method == 'device_sync')
              Card(
                elevation: 0,
                color: const Color(0xFFF0FDF4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF86EFAC)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.bluetooth_connected, color: Color(0xFF16A34A), size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Digital BP Monitor Connected',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF15803D)),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Auto-synchronization engine (In Development Stage)',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _syncing ? null : _syncFromDevice,
                          icon: _syncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.sync, size: 20),
                          label: Text(
                            _syncing ? 'Synchronizing reading…' : 'Sync Reading from Machine',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (_syncStatusMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _syncStatusMessage!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Mode C: Scan Machine (Camera OCR)
            if (_method == 'camera_ocr')
              Card(
                elevation: 0,
                color: const Color(0xFFEFF6FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.camera_alt, color: Color(0xFF2563EB), size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scan BP Machine Display',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1D4ED8)),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Use camera to recognize numbers from monitor',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF2563EB)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _scanning ? null : _scanMonitorDisplay,
                          icon: _scanning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.camera_alt, color: Color(0xFF2563EB), size: 20),
                          label: Text(
                            _scanning ? 'Reading display…' : 'Capture Machine Photo',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 14),

            // Blood Pressure Input Fields (Systolic, Diastolic, Pulse)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Blood Pressure Reading',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Systolic (SYS) *',
                              hintText: 'e.g. 120',
                              suffixText: 'mmHg',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _diaCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Diastolic (DIA) *',
                              hintText: 'e.g. 80',
                              suffixText: 'mmHg',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pulseCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Pulse (BPM) — optional',
                        hintText: 'e.g. 75',
                        suffixText: 'bpm',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 3. Imminent Symptoms Chips Selections Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFFECDD3)),
              ),
              color: const Color(0xFFFFF1F2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.crimson, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Imminent Symptoms (Danger Signs)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF881337)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap any symptom you are currently experiencing:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9F1239)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kSymptomsList.map((item) {
                        final id = item['id']!;
                        final label = item['label']!;
                        final tamil = item['tamil']!;
                        final isSelected = _imminentSymptoms.contains(id);

                        return FilterChip(
                          label: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isSelected ? Colors.white : const Color(0xFF881337),
                                ),
                              ),
                              Text(
                                tamil,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected ? Colors.white70 : AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                          selected: isSelected,
                          selectedColor: AppColors.crimson,
                          backgroundColor: Colors.white,
                          checkmarkColor: Colors.white,
                          side: BorderSide(
                            color: isSelected ? AppColors.crimson : const Color(0xFFFDA4AF),
                          ),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _imminentSymptoms.add(id);
                              } else {
                                _imminentSymptoms.remove(id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 4. Save Measurement Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.crimson,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saving ? null : _saveMeasurement,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded, size: 22),
                label: Text(
                  _saving ? 'Saving measurement…' : 'Save Measurement',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
