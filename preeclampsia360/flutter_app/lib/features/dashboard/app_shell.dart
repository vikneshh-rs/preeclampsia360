import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../patients/patient_list_screen.dart';
import '../patients/patient_registration_screen.dart';
import '../patients/patient_self_monitoring_view.dart';
import '../auth/login_screen.dart';
import '../referrals/referral_screen.dart';
import '../referrals/stabilize_patient_dialog.dart';
import '../clinical/bp_entry_screen.dart';
import 'thc_web_dashboard.dart';
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
    if (ApiClient.instance.isPatient) {
      if (mounted) setState(() => loading = false);
      return;
    }
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

  bool get isThcUser {
    final a = ApiClient.instance.assignments;
    final active = ApiClient.instance.activeAssignment ?? (a.isNotEmpty ? a.first : null);
    final role = active?['role']?.toString() ?? '';
    final fac = active?['facilities'] is Map ? active!['facilities'] as Map : null;
    final fType = fac?['facility_type']?.toString() ?? '';
    return role.contains('THC') || role.contains('HOSPITAL') || fType == 'THC' || fType == 'HOSPITAL';
  }

  @override
  Widget build(BuildContext context) {
    if (ApiClient.instance.isPatient) {
      return PatientSelfMonitoringView(onLogout: logout);
    }
    if (!loading && error == null && isThcUser) {
      return THCWebDashboardView(onLogout: logout);
    }
    final user = ApiClient.instance.currentUser ?? {};
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: AppColors.deepBurgundy),
            const SizedBox(width: 9),
            Text(
              'Preeclampsia 360',
              style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, fontSize: 20, color: AppColors.darkWine),
            ),
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
  final Set<String> _notifiedAlertIds = {};
  bool _notifiedAncDue = false;

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

        // Trigger notification popup for incoming red alerts
        final redAlerts = activeAlerts.where((x) => x['severity'] == 'red').toList();
        if (redAlerts.isNotEmpty) {
          final unnotified = redAlerts.where((x) => !_notifiedAlertIds.contains(x['id']?.toString())).toList();
          if (unnotified.isNotEmpty) {
            final target = unnotified.first;
            _notifiedAlertIds.add(target['id']?.toString() ?? '');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showRedAlertNotification(target);
            });
          }
        }

        // Trigger 2-week Antenatal visit due notification popup
        final dueMothers = patients.where((pt) {
          return pt['anc_due_2_weeks'] == true ||
              (pt['days_since_last_visit'] is num && pt['days_since_last_visit'] >= 14);
        }).toList();

        if (dueMothers.isNotEmpty && !_notifiedAncDue) {
          _notifiedAncDue = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showAncDueNotification(dueMothers);
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openStabilizeDialog(Map<String, dynamic> alert) {
    final pat = alert['patient'] is Map ? alert['patient'] as Map : {};
    showDialog(
      context: context,
      builder: (c) => StabilizePatientDialog(
        patientId: alert['patient_id']?.toString() ?? '',
        patientName: pat['full_name']?.toString() ?? 'Mother',
        patientCode: pat['patient_code']?.toString() ?? '',
        systolic: (alert['systolic_mmhg'] as num?)?.toInt(),
        diastolic: (alert['diastolic_mmhg'] as num?)?.toInt(),
        alertId: alert['id']?.toString(),
        onReferralCompleted: refresh,
      ),
    );
  }

  void _showRedAlertNotification(Map<String, dynamic> alert) {
    final pat = alert['patient'] is Map ? alert['patient'] as Map : {};
    final sys = alert['systolic_mmhg'];
    final dia = alert['diastolic_mmhg'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFF991B1B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Incoming Red Alert: Action Required',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A patient has been screened with Severe-Range Blood Pressure (Red Alert):',
              style: TextStyle(fontSize: 13, color: AppColors.ink),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pat['full_name'] ?? 'Mother'} (${pat['patient_code'] ?? '—'})',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF991B1B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Severe BP: $sys / $dia mmHg',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFFDC2626)),
                  ),
                  Text(
                    'Trigger: ${alert['trigger_reason']}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Click "Initiate Referral" to open the pre-referral stabilization checklist (medicines) and generate the printable referral sheet.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF991B1B)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Dismiss'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF991B1B)),
            onPressed: () {
              Navigator.pop(c);
              _openStabilizeDialog(alert);
            },
            icon: const Icon(Icons.emergency, size: 18),
            label: const Text('Initiate Referral', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAncDueNotification(List<dynamic> dueMothers) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFF7F1D3A), // Clinical Burgundy
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: const Row(
            children: [
              Icon(Icons.event_repeat, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '2-Week Antenatal Visit Alert',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clinical protocol reminder: Every mother must be checked every 2 weeks. '
                '${dueMothers.length} mother(s) in your jurisdiction are due or overdue for their routine follow-up:',
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: dueMothers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = dueMothers[i];
                    final days = p['days_since_last_visit'] ?? 14;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECDD3)),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.paleRose,
                            child: Icon(Icons.person, color: AppColors.crimson, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['full_name'] ?? 'Mother',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  '${p['patient_code']} • $days days since last checkup',
                                  style: const TextStyle(fontSize: 11, color: AppColors.critical, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.crimson,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () {
                              Navigator.pop(c);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BPEntryScreen(initialPatientId: p['id']),
                                ),
                              ).then((_) => refresh());
                            },
                            child: const Text('Visit / BP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7F1D3A)),
            onPressed: () {
              Navigator.pop(c);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PatientListScreen(initialTab: 'due'),
                ),
              ).then((_) => refresh());
            },
            child: const Text('View All in Directory'),
          ),
        ],
      ),
    );
  }

  Widget _buildAncDueSection(List<dynamic> dueMothers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.event_repeat, color: Color(0xFF7F1D3A), size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Antenatal Visits Due',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  '${dueMothers.length} DUE (2-WEEKS)',
                  color: AppColors.crimson,
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PatientListScreen(initialTab: 'due')),
              ).then((_) => refresh()),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...dueMothers.take(4).map((p) {
          final days = p['days_since_last_visit'] ?? 14;
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFFECDD3)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.paleRose,
                child: Icon(Icons.event_repeat, color: AppColors.crimson),
              ),
              title: Text(
                p['full_name'] ?? 'Mother',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${p['patient_code']} • $days days since last checkup\nMandatory 2-week Antenatal visit due',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.crimson,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BPEntryScreen(initialPatientId: p['id']),
                  ),
                ).then((_) => refresh()),
                icon: const Icon(Icons.monitor_heart, size: 16),
                label: const Text('Visit / BP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildIncomingRedAlertBanner(Map<String, dynamic> alert) {
    final pat = alert['patient'] is Map ? alert['patient'] as Map : {};
    final sys = alert['systolic_mmhg'];
    final dia = alert['diastolic_mmhg'];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDC2626), width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF991B1B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emergency_share, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'INCOMING ALERT • SEVERE HYPERTENSION (RED)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'CRITICAL',
                    style: TextStyle(
                      color: Color(0xFF991B1B),
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        pat['full_name'] ?? 'Mother',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    ),
                    Text(
                      '$sys / $dia mmHg',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Patient Code: ${pat['patient_code'] ?? '—'}  •  Trigger: ${alert['trigger_reason']}',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF991B1B),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _openStabilizeDialog(alert),
                        icon: const Icon(Icons.emergency, size: 18),
                        label: const Text(
                          'Initiate Referral',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDC2626)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      ),
                      onPressed: () => _openReviewDialog(alert),
                      child: const Text('Review', style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledgeYellowAlert(Map<String, dynamic> alert) async {
    try {
      await ApiClient.instance.post('/api/v1/alerts/${alert['id']}/review', {
        'status': 'reviewed',
        'review_notes': 'Yellow alert acknowledged by PHC doctor. Patient placed under active surveillance tracking.',
      });
      if (mounted) {
        final pat = alert['patient'] is Map ? alert['patient'] as Map : {};
        final pName = pat['full_name'] ?? 'Patient';
        showMessage(context, 'Alert acknowledged. $pName added to Track Patients list.');
        refresh();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Failed to acknowledge alert: $e', error: true);
    }
  }

  Widget _buildIncomingYellowAlertBanner(Map<String, dynamic> alert) {
    final pat = alert['patient'] is Map ? alert['patient'] as Map : {};
    final sys = alert['systolic_mmhg'];
    final dia = alert['diastolic_mmhg'];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF59E0B), width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFD97706),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'INCOMING ALERT • ELEVATED BP SCREENING (YELLOW ALERT)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'YELLOW ALERT',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        pat['full_name'] ?? 'Mother',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                    Text(
                      '$sys / $dia mmHg',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Patient Code: ${pat['patient_code'] ?? '—'}  •  Trigger: ${alert['trigger_reason']}',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _acknowledgeYellowAlert(alert),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text(
                          'Acknowledge Alert',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD97706), width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _openStabilizeDialog(alert),
                        icon: const Icon(Icons.local_hospital, size: 18, color: Color(0xFFB45309)),
                        label: const Text(
                          'Initiate Referral',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB45309)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackedPatientsSection(List<dynamic> trackedPatients) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.radar, color: Color(0xFFD97706), size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Track Patients',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  '${trackedPatients.length} UNDER OBSERVATION',
                  color: const Color(0xFFD97706),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PatientListScreen(initialTab: 'tracked')),
              ).then((_) => refresh()),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...trackedPatients.take(4).map((p) {
          final q = p['questionnaire_data'] is Map ? p['questionnaire_data'] as Map : {};
          final lastBp = q['last_alert_bp'] ?? 'Elevated';
          final reason = q['tracking_reason'] ?? 'Active Surveillance';

          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFFDE68A)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFEF3C7),
                child: Icon(Icons.person, color: Color(0xFFD97706)),
              ),
              title: Text(
                p['full_name'] ?? 'Mother',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${p['patient_code']} • BP: $lastBp\nStatus: $reason',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.monitor_heart, color: AppColors.crimson, size: 20),
                    tooltip: 'Record BP',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BPEntryScreen(initialPatientId: p['id']),
                      ),
                    ).then((_) => refresh()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'View Profile',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PatientDetailScreen(patientId: p['id']),
                      ),
                    ).then((_) => refresh()),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
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

    final redAlerts = activeAlerts.where((x) => x['severity'] == 'red').toList();
    final yellowAlerts = activeAlerts.where((x) => x['severity'] == 'amber').toList();
    final trackedPatients = patients.where((p) => p['questionnaire_data'] is Map && (p['questionnaire_data'] as Map)['is_tracked'] == true).toList();
    final dueMothers = patients.where((p) {
      return p['anc_due_2_weeks'] == true ||
          (p['days_since_last_visit'] is num && p['days_since_last_visit'] >= 14);
    }).toList();

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const P360Header('Clinical care overview', subtitle: 'Live maternal surveillance & referral coordination'),
          const SizedBox(height: 14),
          // Quick Check BP (Digital Machine Sync) Banner for ANMs & PHCs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bluetooth_connected, color: Color(0xFF16A34A), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Check BP • Machine Auto-Sync',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF15803D)),
                      ),
                      Text(
                        'Digital monitor auto-synchronization (In Development Stage)',
                        style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BPEntryScreen(initialMethod: 'device_sync')),
                  ).then((_) => refresh()),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Check BP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (redAlerts.isNotEmpty) ...[
            _buildIncomingRedAlertBanner(redAlerts.first),
            const SizedBox(height: 14),
          ],
          if (yellowAlerts.isNotEmpty) ...[
            _buildIncomingYellowAlertBanner(yellowAlerts.first),
            const SizedBox(height: 14),
          ],
          if (dueMothers.isNotEmpty) ...[
            _buildAncDueSection(dueMothers),
            const SizedBox(height: 18),
          ],
          if (trackedPatients.isNotEmpty) ...[
            _buildTrackedPatientsSection(trackedPatients),
            const SizedBox(height: 18),
          ],
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
                          if (!isRed) ...[
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFD97706),
                              ),
                              onPressed: () => _acknowledgeYellowAlert(alert),
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Acknowledge Alert'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFD97706)),
                              ),
                              onPressed: () => _openStabilizeDialog(alert),
                              icon: const Icon(Icons.local_hospital, size: 16, color: Color(0xFFB45309)),
                              label: const Text('Initiate Referral', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
                            ),
                          ] else ...[
                            OutlinedButton.icon(
                              onPressed: () => _openReviewDialog(alert),
                              icon: const Icon(Icons.assignment_turned_in, size: 16),
                              label: const Text('Review Alert'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF991B1B),
                              ),
                              onPressed: () => _openStabilizeDialog(alert),
                              icon: const Icon(Icons.emergency, size: 16),
                              label: const Text('Initiate Referral'),
                            ),
                          ],
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
                icon: Icons.bluetooth_connected,
                label: 'Check BP (Device Sync)',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BPEntryScreen(initialMethod: 'device_sync')),
                ).then((_) => refresh()),
              ),
              _ActionChip(
                icon: Icons.person_add_alt,
                label: 'Smart Pregnancy Registration',
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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.darkWine,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              title,
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.slate, fontWeight: FontWeight.w500),
            ),
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
  Widget build(BuildContext context) => P360MotionButton(
        onTap: onTap,
        child: ActionChip(
          avatar: Icon(icon, color: AppColors.deepBurgundy, size: 18),
          label: Text(
            label,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          onPressed: onTap,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
}
