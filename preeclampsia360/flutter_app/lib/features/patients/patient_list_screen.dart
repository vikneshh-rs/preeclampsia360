import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import 'patient_registration_screen.dart';
import '../clinical/bp_entry_screen.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});
  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final search = TextEditingController();
  List<dynamic> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final queryParam = search.text.trim().isEmpty
          ? ''
          : '&q=${Uri.encodeQueryComponent(search.text.trim())}';
      final r = await ApiClient.instance.get('/api/v1/patients?limit=100$queryParam');
      if (mounted) {
        setState(() {
          items = List.from(r['items'] ?? []);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPushed = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.warmWhite,
      appBar: isPushed ? AppBar(title: const Text('Patient Directory')) : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: P360Header('Pregnant women', subtitle: 'Patients assigned to your facility'),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const PatientRegistrationScreen()))
                        .then((_) => load()),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: search,
                onSubmitted: (_) => load(),
                decoration: InputDecoration(
                  hintText: 'Search by patient name',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(onPressed: load, icon: const Icon(Icons.arrow_forward)),
                ),
              ),
            ),
            Expanded(
              child: loading
                  ? const LoadingView()
                  : error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.critical)),
                                const SizedBox(height: 12),
                                FilledButton(onPressed: load, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : items.isEmpty
                          ? const Center(child: Text('No patient records found.'))
                          : RefreshIndicator(
                              onRefresh: load,
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final p = items[i];
                                  return Card(
                                    child: ListTile(
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PatientDetailScreen(patientId: p['id']),
                                        ),
                                      ).then((_) => load()),
                                      leading: CircleAvatar(
                                        backgroundColor: AppColors.paleRose,
                                        child: Text(
                                          p['full_name'][0].toUpperCase(),
                                          style: const TextStyle(color: AppColors.crimson, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      title: Text(p['full_name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                                      subtitle: Text('${p['patient_code']} • Blood: ${p['blood_group'] ?? '—'} • ${p['phone'] ?? 'No phone'}'),
                                      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  const PatientDetailScreen({super.key, required this.patientId});
  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  Map<String, dynamic>? patient;
  Map<String, dynamic>? timeline;
  List<dynamic> obstetricHistory = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await ApiClient.instance.get('/api/v1/patients/${widget.patientId}');
      final t = await ApiClient.instance.get('/api/v1/patients/${widget.patientId}/timeline');
      final ob = await ApiClient.instance.get('/api/v1/patients/${widget.patientId}/obstetric-history');
      if (mounted) {
        setState(() {
          patient = Map<String, dynamic>.from(p);
          timeline = Map<String, dynamic>.from(t);
          obstetricHistory = List<dynamic>.from(ob['items'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openEditDialog() {
    if (patient == null) return;
    final p = patient!;
    final nameCtrl = TextEditingController(text: p['full_name'] ?? '');
    final phoneCtrl = TextEditingController(text: p['phone'] ?? '');
    final addrCtrl = TextEditingController(text: p['address'] ?? '');
    final bloodCtrl = TextEditingController(text: p['blood_group'] ?? '');
    final lmpCtrl = TextEditingController(text: p['lmp'] ?? '');
    final eddCtrl = TextEditingController(text: p['edd'] ?? '');
    final gCtrl = TextEditingController(text: p['gravida']?.toString() ?? '');
    final pCtrl = TextEditingController(text: p['parity']?.toString() ?? '');
    final aCtrl = TextEditingController(text: p['abortions']?.toString() ?? '');
    final lCtrl = TextEditingController(text: p['living_children']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit Patient Profile'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name *')),
                const SizedBox(height: 10),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
                const SizedBox(height: 10),
                TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Address')),
                const SizedBox(height: 10),
                TextField(controller: bloodCtrl, decoration: const InputDecoration(labelText: 'Blood Group (e.g. O+, B+)')),
                const SizedBox(height: 10),
                TextField(controller: lmpCtrl, decoration: const InputDecoration(labelText: 'LMP (YYYY-MM-DD)')),
                const SizedBox(height: 10),
                TextField(controller: eddCtrl, decoration: const InputDecoration(labelText: 'EDD (YYYY-MM-DD)')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: gCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'G (Gravida)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: pCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'P (Parity)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: aCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'A (Abortions)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: lCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'L (Living)'))),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            onPressed: () async {
              try {
                await ApiClient.instance.put('/api/v1/patients/${widget.patientId}', {
                  'full_name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                  'address': addrCtrl.text.trim(),
                  'blood_group': bloodCtrl.text.trim().isEmpty ? null : bloodCtrl.text.trim(),
                  'lmp': lmpCtrl.text.trim().isEmpty ? null : lmpCtrl.text.trim(),
                  'edd': eddCtrl.text.trim().isEmpty ? null : eddCtrl.text.trim(),
                  'gravida': int.tryParse(gCtrl.text.trim()),
                  'parity': int.tryParse(pCtrl.text.trim()),
                  'abortions': int.tryParse(aCtrl.text.trim()),
                  'living_children': int.tryParse(lCtrl.text.trim()),
                });
                if (c.mounted) Navigator.pop(c);
                if (mounted) {
                  showMessage(context, 'Patient profile updated successfully.');
                  load();
                }
              } catch (err) {
                if (mounted) showMessage(context, err.toString(), error: true);
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _openAddObstetricHistoryDialog() {
    int nextNumber = obstetricHistory.length + 1;
    final numCtrl = TextEditingController(text: nextNumber.toString());
    final outcomeCtrl = TextEditingController(text: 'Full Term Normal Delivery');
    final compCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final babySexCtrl = TextEditingController(text: 'Female');
    final yearCtrl = TextEditingController(text: DateTime.now().year.toString());

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add Previous Pregnancy Record'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: numCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pregnancy Number (e.g. 1, 2)')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: outcomeCtrl.text,
                  decoration: const InputDecoration(labelText: 'Pregnancy Outcome'),
                  items: const [
                    DropdownMenuItem(value: 'Full Term Normal Delivery', child: Text('Full Term Normal Delivery')),
                    DropdownMenuItem(value: 'LSCS / Cesarean Section', child: Text('LSCS / Cesarean Section')),
                    DropdownMenuItem(value: 'Preterm Delivery', child: Text('Preterm Delivery')),
                    DropdownMenuItem(value: 'Spontaneous Abortion / Miscarriage', child: Text('Spontaneous Abortion')),
                    DropdownMenuItem(value: 'Medical Termination (MTP)', child: Text('Medical Termination (MTP)')),
                    DropdownMenuItem(value: 'Stillbirth / IUD', child: Text('Stillbirth / IUD')),
                  ],
                  onChanged: (v) => outcomeCtrl.text = v ?? '',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: compCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Antenatal / Delivery Complications',
                    hintText: 'e.g. Preeclampsia, Gestational HTN, Eclampsia, None',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: weightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Baby Weight (kg)'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: babySexCtrl.text,
                        decoration: const InputDecoration(labelText: 'Baby Gender'),
                        items: const [
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Not applicable', child: Text('N/A')),
                        ],
                        onChanged: (v) => babySexCtrl.text = v ?? '',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: yearCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Year'))),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            onPressed: () async {
              try {
                final pNum = int.tryParse(numCtrl.text.trim()) ?? nextNumber;
                await ApiClient.instance.post('/api/v1/patients/${widget.patientId}/obstetric-history', {
                  'pregnancy_number': pNum,
                  'conception_type': 'spontaneous',
                  'antenatal_complications': compCtrl.text.trim().isEmpty ? 'None reported' : compCtrl.text.trim(),
                  'delivery_details': {
                    'outcome': outcomeCtrl.text,
                    'year': yearCtrl.text.trim(),
                  },
                  'baby_details': {
                    'birth_weight_kg': double.tryParse(weightCtrl.text.trim()),
                    'gender': babySexCtrl.text,
                  },
                  'abortion_details': {},
                });
                if (c.mounted) Navigator.pop(c);
                if (mounted) {
                  showMessage(context, 'Previous pregnancy record saved.');
                  load();
                }
              } catch (err) {
                if (mounted) showMessage(context, err.toString(), error: true);
              }
            },
            child: const Text('Save Record'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: LoadingView());
    if (patient == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error ?? 'Patient unavailable', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final p = patient!;
    final bpList = List<dynamic>.from(timeline?['bp_measurements'] ?? []);
    final refList = List<dynamic>.from(timeline?['referrals'] ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient 360 Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: _openEditDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          P360Card(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.blush,
                  child: Text(
                    (p['full_name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: AppColors.crimson, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['full_name'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      Text(p['patient_code'] ?? '', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.bold)),
                      if (p['phone'] != null) Text('Phone: ${p['phone']}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                      if (p['address'] != null && p['address'].toString().isNotEmpty)
                        Text('Address: ${p['address']}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Quick Action Bar
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.crimson,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BPEntryScreen(initialPatientId: widget.patientId),
                ),
              ).then((_) => load()),
              icon: const Icon(Icons.monitor_heart, size: 20),
              label: const Text('Record Blood Pressure', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Current pregnancy details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              TextButton.icon(
                onPressed: _openEditDialog,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          P360Card(
            child: Wrap(
              spacing: 20,
              runSpacing: 16,
              children: [
                _Info('Blood group', p['blood_group']),
                _Info('LMP', p['lmp']),
                _Info('EDD', p['edd']),
                _Info('Gravida (G)', p['gravida']),
                _Info('Parity (P)', p['parity']),
                _Info('Abortions (A)', p['abortions']),
                _Info('Living children (L)', p['living_children']),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Obstetric History Repeatable Records
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Obstetric history & past pregnancies', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              TextButton.icon(
                onPressed: _openAddObstetricHistoryDialog,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('+ Add Pregnancy'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (obstetricHistory.isEmpty)
            P360Card(
              child: Row(
                children: [
                  const Icon(Icons.history_edu, color: AppColors.muted),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('No past pregnancy records recorded. Tap "+ Add Pregnancy" for multi-gravida mothers.', style: TextStyle(color: AppColors.muted)),
                  ),
                ],
              ),
            )
          else
            ...obstetricHistory.map((ob) {
              final del = ob['delivery_details'] is Map ? ob['delivery_details'] as Map : {};
              final baby = ob['baby_details'] is Map ? ob['baby_details'] as Map : {};
              final comp = ob['antenatal_complications'] ?? 'None';
              final hasPreeclampsia = comp.toString().toLowerCase().contains('preeclampsia') ||
                  comp.toString().toLowerCase().contains('eclampsia') ||
                  comp.toString().toLowerCase().contains('htn');
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: hasPreeclampsia ? AppColors.blush : AppColors.paleRose,
                    child: Text(
                      'P${ob['pregnancy_number']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hasPreeclampsia ? AppColors.critical : AppColors.crimson,
                      ),
                    ),
                  ),
                  title: Text(
                    'Pregnancy #${ob['pregnancy_number']}: ${del['outcome'] ?? 'Delivery'} (${del['year'] ?? ''})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Complications: $comp\nBaby: ${baby['gender'] ?? '—'} • Weight: ${baby['birth_weight_kg'] ?? '—'} kg',
                  ),
                  trailing: hasPreeclampsia
                      ? const StatusPill('PREV PE RISK', color: AppColors.critical)
                      : const StatusPill('RECORDED', color: AppColors.success),
                ),
              );
            }),
          const SizedBox(height: 18),
          const Text('Recent BP measurements', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          if (bpList.isEmpty)
            const P360Card(child: Text('No recorded blood pressure measurements yet.'))
          else
            ...bpList.take(5).map((bp) {
              final sys = bp['systolic_mmhg'];
              final dia = bp['diastolic_mmhg'];
              final isHigh = (sys is num && sys >= 140) || (dia is num && dia >= 90);
              return Card(
                child: ListTile(
                  leading: Icon(
                    Icons.monitor_heart,
                    color: isHigh ? AppColors.critical : AppColors.success,
                  ),
                  title: Text(
                    '$sys / $dia mmHg',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isHigh ? AppColors.critical : AppColors.ink,
                    ),
                  ),
                  subtitle: Text('Pulse: ${bp['pulse_bpm'] ?? '—'} bpm  •  ${bp['measured_at']?.toString().substring(0, 10) ?? ''}'),
                  trailing: StatusPill(
                    isHigh ? 'ELEVATED' : 'NORMAL',
                    color: isHigh ? AppColors.critical : AppColors.success,
                  ),
                ),
              );
            }),
          const SizedBox(height: 18),
          const Text('Referrals history', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          if (refList.isEmpty)
            const P360Card(child: Text('No referrals for this patient.'))
          else
            ...refList.map((r) => Card(
                  child: ListTile(
                    title: Text(r['reason'] ?? 'Referral'),
                    subtitle: Text('Status: ${r['status']}  •  ${r['created_at']?.toString().substring(0, 10) ?? ''}'),
                    trailing: StatusPill(
                      r['status']?.toString().toUpperCase() ?? 'PENDING',
                      color: r['status'] == 'completed' ? AppColors.success : AppColors.warning,
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final dynamic value;
  const _Info(this.label, this.value);
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(value?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
