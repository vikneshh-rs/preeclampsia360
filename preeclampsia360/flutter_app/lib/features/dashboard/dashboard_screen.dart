import 'package:flutter/material.dart';
import '../../core/theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 760;
    return Scaffold(
      appBar: AppBar(title: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.paleRose, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.favorite, color: AppColors.crimson)),
        const SizedBox(width: 12), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Preeclampsia 360', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text('Maternal care coordination', style: TextStyle(fontSize: 11, color: AppColors.muted))]),
      ]), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)), const SizedBox(width: 8)]),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1120), child: ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.crimson, AppColors.rose]), borderRadius: BorderRadius.circular(28)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Good morning, ANM', style: TextStyle(color: Colors.white70)), SizedBox(height: 8), Text('Every mother deserves\ncloser care.', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800, height: 1.15)), SizedBox(height: 10), Text('Identify  ·  Monitor  ·  Refer  ·  Follow up', style: TextStyle(color: Colors.white))])),
        const SizedBox(height: 20),
        GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: wide ? 4 : 2, childAspectRatio: 1.65, crossAxisSpacing: 12, mainAxisSpacing: 12, children: const [
          _Metric(icon: Icons.pregnant_woman, title: 'Active pregnancies', value: '—', tint: AppColors.paleRose),
          _Metric(icon: Icons.warning_amber_rounded, title: 'High-risk alerts', value: '—', tint: Color(0xFFFFF1E7)),
          _Metric(icon: Icons.event_available, title: 'Due follow-ups', value: '—', tint: Color(0xFFEAF3FF)),
          _Metric(icon: Icons.assignment_turned_in_outlined, title: 'Referrals', value: '—', tint: Color(0xFFEAF6EF)),
        ]),
        const SizedBox(height: 22), const Text('Quick actions', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)), const SizedBox(height: 12),
        GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: wide ? 3 : 2, childAspectRatio: 2.6, crossAxisSpacing: 12, mainAxisSpacing: 12, children: const [
          _Action(icon: Icons.person_add_alt_1, label: 'Smart Pregnancy Registration'), _Action(icon: Icons.camera_alt_outlined, label: 'Capture BP'), _Action(icon: Icons.groups_2_outlined, label: 'My patients'),
        ]),
        const SizedBox(height: 22), Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text('Your care workspace', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), SizedBox(height: 8), Text('Connect your Supabase project and sign in to load your facility’s live patient list, follow-ups and alerts.', style: TextStyle(color: AppColors.muted, height: 1.4)), SizedBox(height: 12), LinearProgressIndicator(value: null, color: AppColors.rose, backgroundColor: AppColors.paleRose)]))),
      ]))),
      bottomNavigationBar: NavigationBar(selectedIndex: 0, destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'), NavigationDestination(icon: Icon(Icons.people_outline), label: 'Patients'), NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Tasks'), NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'Reports'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile')]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.title, required this.value, required this.tint});
  final IconData icon; final String title, value; final Color tint;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.crimson, size: 19)), Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: AppColors.ink)), Text(title, style: const TextStyle(fontSize: 12, color: AppColors.muted))])));
}
class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label}); final IconData icon; final String label;
  @override Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(24), onTap: () {}, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [Icon(icon, color: AppColors.crimson), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))), const Icon(Icons.chevron_right, color: AppColors.muted)]))));
}
