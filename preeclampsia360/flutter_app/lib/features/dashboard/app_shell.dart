import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../patients/patient_list_screen.dart';
import '../patients/patient_registration_screen.dart';
import '../auth/login_screen.dart';
import '../referrals/referral_screen.dart';
import '../clinical/bp_entry_screen.dart';
import '../../shared/ui.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  Map<String, dynamic>? workspace;
  bool loading = true;
  String? error;

  final pages = const <Widget>[
    DashboardHome(),
    PatientListScreen(),
    PatientRegistrationScreen(),
    BPEntryScreen(),
    ReferralScreen(),
  ];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await ApiClient.instance.get('/api/v1/workspace');
      if (r['profile'] is Map) {
        ApiClient.instance.currentUser = Map<String, dynamic>.from(r['profile']);
      }
      if (r['assignments'] is List) {
        ApiClient.instance.assignments = List<dynamic>.from(r['assignments']);
      }
      if (mounted) setState(() => workspace = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> logout() async {
    await ApiClient.instance.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  String _roleLabel() {
    final a = ApiClient.instance.assignments;
    if (a.isEmpty) return 'Staff';
    final active = ApiClient.instance.activeAssignment;
    final r = active?['role'] ?? a.first['role'] ?? 'Staff';
    final facilityName = active?['facilities']?['name'] ?? a.first['facilities']?['name'] ?? '';
    return '$r ($facilityName)'.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.instance.currentUser ?? {};
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.favorite_rounded, color: AppColors.crimson),
            SizedBox(width: 9),
            Text('Preeclampsia 360', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(onPressed: load, icon: const Icon(Icons.sync)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: loading
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
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: AppColors.paleRose,
                      child: Row(
                        children: [
                          const Icon(Icons.badge_outlined, color: AppColors.crimson, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            user['full_name'] ?? 'Healthcare Worker',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.crimson),
                          ),
                          const Spacer(),
                          Text(
                            _roleLabel(),
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: index,
                        children: pages,
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_add_alt),
            label: 'Register',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            label: 'BP',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_hospital_outlined),
            label: 'Referrals',
          ),
        ],
      ),
    );
  }
}

class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});
  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  bool loading = true;
  List<dynamic> patients = [];
  List<dynamic> referrals = [];
  List<dynamic> activeAlerts = [];
  Map<String, dynamic> metrics = {};
  String? err;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final p = await ApiClient.instance.get('/api/v1/patients?limit=100');
      final r = await ApiClient.instance.get('/api/v1/referrals');
      final a = await ApiClient.instance.get('/api/v1/alerts?status=active');
      final m = await ApiClient.instance.get('/api/v1/dashboard/metrics');
      if (mounted) {
        setState(() {
          patients = List.from(p['items'] ?? []);
          referrals = List.from(r['items'] ?? []);
          activeAlerts = List.from(a['items'] ?? []);
          metrics = Map<String, dynamic>.from(m);
          err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openReviewDialog(Map<String, dynamic> alert) {
    final notesCtrl = TextEditingController();
    String decision = 'reviewed';

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clinical Assessment of Alert'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patient: ${alert['patient']?['full_name'] ?? 'Mother'} (${alert['patient']?['patient_code'] ?? ''})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Trigger: ${alert['trigger_reason']}',
                style: TextStyle(
                  color: alert['severity'] == 'red' ? AppColors.critical : AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: decision,
                decoration: const InputDecoration(labelText: 'Clinical Decision'),
                items: const [
                  DropdownMenuItem(value: 'reviewed', child: Text('Reviewed — Stable under observation')),
                  DropdownMenuItem(value: 'referred', child: Text('Referred — Specialist intervention required')),
                  DropdownMenuItem(value: 'dismissed', child: Text('Dismissed — Repeat reading normal')),
                ],
                onChanged: (v) => decision = v ?? 'reviewed',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Medical Officer Review Notes *',
                  hintText: 'Enter clinical impression and management directives...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            onPressed: () async {
              if (notesCtrl.text.trim().length < 2) {
                showMessage(context, 'Please enter clinical review notes.', error: true);
                return;
              }
              try {
                await ApiClient.instance.post('/api/v1/alerts/${alert['id']}/review', {
                  'status': decision,
                  'review_notes': notesCtrl.text.trim(),
                });
                if (c.mounted) Navigator.pop(c);
                if (mounted) {
                  showMessage(context, 'Alert clinical review recorded.');
                  refresh();
                }
              } catch (e) {
                if (mounted) showMessage(context, e.toString(), error: true);
              }
            },
            child: const Text('Submit Review'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myFid = ApiClient.instance.activeFacilityId;
    final incomingWaiting = referrals.where((r) {
      final isMine = r['receiving_facility_id']?.toString() == myFid;
      final isWaiting = r['status'] == 'sent' || r['status'] == 'acknowledged';
      return isMine && isWaiting;
    }).toList();

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const P360Header('Clinical care overview', subtitle: 'Live maternal surveillance & referral coordination'),
          const SizedBox(height: 18),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(err!, style: const TextStyle(color: AppColors.critical)),
            ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _Metric(
                title: 'Mothers in care',
                value: loading ? '—' : '${metrics['registered_patients'] ?? patients.length}',
                icon: Icons.pregnant_woman,
                color: AppColors.crimson,
              ),
              _Metric(
                title: 'Active BP alerts',
                value: loading ? '—' : '${activeAlerts.length}',
                icon: Icons.warning_amber_rounded,
                color: activeAlerts.isNotEmpty ? AppColors.critical : AppColors.success,
              ),
              _Metric(
                title: 'Active referrals',
                value: loading ? '—' : '${metrics['active_referrals'] ?? referrals.where((x) => x['status'] != 'completed').length}',
                icon: Icons.local_hospital,
                color: AppColors.warning,
              ),
              _Metric(
                title: 'Incoming referrals',
                value: loading ? '—' : '${incomingWaiting.length}',
                icon: Icons.inbox_outlined,
                color: incomingWaiting.isNotEmpty ? AppColors.critical : AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Medical Officer Elevated BP Alerts Center
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Elevated BP screening alerts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  if (activeAlerts.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    StatusPill('${activeAlerts.length} ACTION REQUIRED', color: AppColors.critical),
                  ],
                ],
              ),
              IconButton(onPressed: refresh, icon: const Icon(Icons.refresh, size: 20)),
            ],
          ),
          const SizedBox(height: 8),
          if (activeAlerts.isEmpty)
            P360Card(
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: AppColors.success, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'All screened mothers have blood pressure within normal limits across your jurisdiction.',
                      style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          else
            ...activeAlerts.map((alert) {
              final pat = alert['patient'] is Map ? alert['patient'] as Map : {};
              final isRed = alert['severity'] == 'red';
              final sys = alert['systolic_mmhg'];
              final dia = alert['diastolic_mmhg'];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: isRed ? AppColors.critical : AppColors.warning, width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: isRed ? AppColors.critical : AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pat['full_name'] ?? 'Mother',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                          StatusPill(
                            isRed ? 'SEVERE HYPERTENSION' : 'ELEVATED SCREENING',
                            color: isRed ? AppColors.critical : AppColors.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Patient ID: ${pat['patient_code'] ?? '—'} • Blood Group: ${pat['blood_group'] ?? '—'}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isRed ? AppColors.blush : AppColors.paleRose,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Verified Reading: $sys / $dia mmHg (${alert['trigger_reason']})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isRed ? AppColors.critical : AppColors.crimson,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openReviewDialog(alert),
                            icon: const Icon(Icons.assignment_turned_in, size: 16),
                            label: const Text('Review Alert'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReferralScreen(
                                    initialPatientId: alert['patient_id'],
                                    initialReason: 'Referral authorized by Medical Officer: Elevated BP $sys/$dia mmHg (${alert['severity'].toString().toUpperCase()})',
                                  ),
                                ),
                              ).then((_) => refresh());
                            },
                            icon: const Icon(Icons.local_hospital, size: 16),
                            label: const Text('Authorise Referral'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 22),
          const Text('Quick workflow actions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionChip(
                icon: Icons.person_add_alt,
                label: 'Register mother',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PatientRegistrationScreen()),
                ).then((_) => refresh()),
              ),
              _ActionChip(
                icon: Icons.monitor_heart,
                label: 'Record BP & OCR',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BPEntryScreen()),
                ).then((_) => refresh()),
              ),
              _ActionChip(
                icon: Icons.people,
                label: 'Patient directory',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PatientListScreen()),
                ).then((_) => refresh()),
              ),
              _ActionChip(
                icon: Icons.local_hospital,
                label: 'Referral board',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReferralScreen()),
                ).then((_) => refresh()),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent patients', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              TextButton(onPressed: refresh, child: const Text('Refresh')),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          ...patients.take(5).map((p) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.blush,
                  child: Text(
                    (p['full_name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: AppColors.crimson, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(p['full_name'] ?? 'Unnamed patient', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${p['patient_code']} • Blood: ${p['blood_group'] ?? '—'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: p['id'].toString())),
                ).then((_) => refresh()),
              )),
          if (!loading && patients.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No patient records found in your assigned facility.'),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  const _Metric({required this.title, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => P360Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(title, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, color: AppColors.crimson, size: 18),
        label: Text(label),
        onPressed: onTap,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
      );
}
