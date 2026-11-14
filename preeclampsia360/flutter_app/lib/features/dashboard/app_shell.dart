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
                        const Icon(Icons.cloud_off_outlined, size: 42, color: AppColors.warning),
                        const SizedBox(height: 12),
                        Text(error!, textAlign: TextAlign.center),
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
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      color: AppColors.paleRose,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, ${user['full_name'] ?? 'Healthcare Worker'}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.ink),
                          ),
                          Text(
                            '${user['login_id'] ?? ''}  •  ${_roleLabel()}',
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
      if (mounted) {
        setState(() {
          patients = List.from(p['items'] ?? []);
          referrals = List.from(r['items'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const P360Header('Clinical overview', subtitle: 'Your facility activity at a glance'),
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
                title: 'Registered women',
                value: loading ? '—' : '${patients.length}',
                icon: Icons.pregnant_woman,
                color: AppColors.crimson,
              ),
              _Metric(
                title: 'Active referrals',
                value: loading ? '—' : '${referrals.where((x) => x['status'] != 'completed').length}',
                icon: Icons.local_hospital,
                color: AppColors.warning,
              ),
              _Metric(
                title: 'Facility role',
                value: (ApiClient.instance.assignments.isEmpty ? 'Staff' : (ApiClient.instance.assignments.first['role'] ?? 'Staff').toString()).replaceAll('_', ' '),
                icon: Icons.badge_outlined,
                color: AppColors.success,
              ),
              const _Metric(
                title: 'Sync status',
                value: 'Online',
                icon: Icons.cloud_done_outlined,
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text('Quick actions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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
                ),
              ),
              _ActionChip(
                icon: Icons.monitor_heart,
                label: 'Record BP',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BPEntryScreen()),
                ),
              ),
              _ActionChip(
                icon: Icons.people,
                label: 'View patients',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PatientListScreen()),
                ),
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
                subtitle: Text(p['patient_code'] ?? 'Patient record'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: p['id'].toString())),
                ),
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
