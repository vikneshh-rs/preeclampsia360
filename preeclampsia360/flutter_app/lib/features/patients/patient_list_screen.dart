import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import 'patient_registration_screen.dart';

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
      final queryParam = search.text.trim().isEmpty ? '' : '&q=${Uri.encodeQueryComponent(search.text.trim())}';
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
    return Column(
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
              hintText: 'Search patient name',
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
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final p = items[i];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.paleRose,
                                    child: Text(
                                      (p['full_name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                                      style: const TextStyle(color: AppColors.crimson, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(p['full_name'] ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${p['patient_code'] ?? 'No patient code'}${p['phone'] == null ? '' : ' • ${p['phone']}'}'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: p['id'].toString())),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
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
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await ApiClient.instance.get('/api/v1/patients/${widget.patientId}');
      final t = await ApiClient.instance.get('/api/v1/patients/${widget.patientId}/timeline');
      if (mounted) {
        setState(() {
          patient = Map<String, dynamic>.from(p);
          timeline = Map<String, dynamic>.from(t);
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
    final q = Map<String, dynamic>.from(p['questionnaire_data'] ?? {});
    final bpList = List<dynamic>.from(timeline?['bp_measurements'] ?? []);
    final refList = List<dynamic>.from(timeline?['referrals'] ?? []);

    return Scaffold(
      appBar: AppBar(title: const Text('Patient 360')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          P360Card(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.blush,
                  child: Text(
                    (p['full_name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: AppColors.crimson, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['full_name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(p['patient_code'] ?? '', style: const TextStyle(color: AppColors.muted)),
                      if (p['phone'] != null) Text('Phone: ${p['phone']}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Pregnancy summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          P360Card(
            child: Wrap(
              spacing: 20,
              runSpacing: 16,
              children: [
                _Info('Blood group', p['blood_group']),
                _Info('LMP', p['lmp']),
                _Info('EDD', p['edd']),
                _Info('Gravida', p['gravida']),
                _Info('Parity', p['parity']),
                _Info('Abortions', p['abortions']),
                _Info('Living children', p['living_children']),
              ],
            ),
          ),
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
          const SizedBox(height: 18),
          const Text('Assessment details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          if (q.isEmpty)
            const P360Card(child: Text('No questionnaire data captured.'))
          else
            ...q.entries.map((e) => P360Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.crimson)),
                      const SizedBox(height: 8),
                      Text(e.value.toString()),
                    ],
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
