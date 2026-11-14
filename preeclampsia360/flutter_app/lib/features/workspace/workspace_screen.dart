import 'package:flutter/material.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String role = 'ANM';
  int tab = 0;
  final Map<String, List<String>> menus = {
    'ASHA': ['My Mothers', 'Visit Log', 'Symptom Reports', 'Follow-up Tasks', 'Referral Companion'],
    'ANM': ['Patient Registration', 'Patient List', 'BP Scanner', 'Risk Radar', 'Follow-ups', 'Referrals', 'Postpartum'],
    'VHN': ['Patient Registration', 'Patient List', 'BP Scanner', 'Risk Radar', 'Follow-ups', 'Referrals', 'Postpartum'],
    'PHC_MO': ['PHC Dashboard', 'Clinical Review', 'Risk Radar', 'Referral Board', 'Team & Follow-ups', 'Reports'],
    'CHC_MO': ['CHC Dashboard', 'PHC Overview', 'Clinical Alerts', 'Referral Coordination', 'Workload Analytics'],
    'CHC_ADMIN': ['CHC Dashboard', 'PHC Overview', 'User Management', 'Referral Coordination', 'Reports'],
    'THC_MO': ['THC Dashboard', 'CHC Comparison', 'Clinical Alerts', 'Referral Performance', 'Reports'],
    'THC_ADMIN': ['THC Dashboard', 'Facility Hierarchy', 'User Management', 'Analytics', 'Audit'],
    'RECEIVING_STAFF': ['Incoming Referrals', 'Referral Details', 'Arrival Check-in', 'Assessment & Outcome'],
    'SYSTEM_ADMIN': ['System Overview', 'Users & Roles', 'Facilities', 'Clinical Rules', 'Audit Logs', 'Device Health'],
  };

  @override
  Widget build(BuildContext context) {
    final items = menus[role] ?? menus['ANM']!;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F8),
      appBar: AppBar(
        title: const Text('Preeclampsia 360'),
        actions: [
          PopupMenuButton<String>(
            initialValue: role,
            onSelected: (v) => setState(() => role = v),
            itemBuilder: (_) => menus.keys
                .map((r) => PopupMenuItem(value: r, child: Text(r.replaceAll('_', ' '))))
                .toList(),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFA61932), Color(0xFFD65A70)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Maternal care, coordinated.',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Early detection. Timely care. Safer mothers.', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _metric('Active pregnancies', '—', Icons.pregnant_woman)),
              const SizedBox(width: 10),
              Expanded(child: _metric('Follow-ups due', '—', Icons.event_note)),
              const SizedBox(width: 10),
              Expanded(child: _metric('Open referrals', '—', Icons.local_hospital)),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '${role.replaceAll('_', ' ')} WORKSPACE',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFA61932),
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.45,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (c, i) => InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _open(items[i]),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFF0E2E5)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6D2430).withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(_icon(items[i]), color: const Color(0xFFA61932), size: 26),
                    Text(items[i], style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Clinical information is displayed according to your assigned role and facility permissions.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Patients'),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Reports'),
        ],
      ),
    );
  }

  void _open(String name) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => FeaturePlaceholder(title: name)));
  }

  IconData _icon(String s) {
    if (s.contains('Patient') || s.contains('Mothers')) return Icons.people_alt_outlined;
    if (s.contains('BP')) return Icons.monitor_heart_outlined;
    if (s.contains('Referral') || s.contains('Hospital')) return Icons.local_hospital_outlined;
    if (s.contains('Follow')) return Icons.event_available_outlined;
    if (s.contains('Risk') || s.contains('Alert')) return Icons.warning_amber_rounded;
    if (s.contains('User')) return Icons.manage_accounts_outlined;
    if (s.contains('Facility') || s.contains('PHC') || s.contains('CHC')) return Icons.account_tree_outlined;
    return Icons.dashboard_customize_outlined;
  }

  Widget _metric(String title, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFA61932)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      );
}

class FeaturePlaceholder extends StatelessWidget {
  final String title;
  const FeaturePlaceholder({super.key, required this.title});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '$title\n\nThis role-specific module is scaffolded. Connect it to the authenticated API and clinical workflow before operational use.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ),
      );
}
