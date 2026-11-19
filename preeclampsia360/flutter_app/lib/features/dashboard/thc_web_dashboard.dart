import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import '../referrals/referral_sheet_screen.dart';

class THCWebDashboardView extends StatefulWidget {
  final VoidCallback? onLogout;

  const THCWebDashboardView({super.key, this.onLogout});

  @override
  State<THCWebDashboardView> createState() => _THCWebDashboardViewState();
}

class _THCWebDashboardViewState extends State<THCWebDashboardView> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _phcList = [];
  Map<String, dynamic>? _selectedPhc;

  List<Map<String, dynamic>> _allPatients = [];
  List<Map<String, dynamic>> _referrals = [];
  List<Map<String, dynamic>> _alerts = [];

  String _phcSearchQuery = '';
  String _activeTab = 'referrals'; // 'referrals' or 'patients'
  String _patientRiskFilter = 'all'; // 'all', 'red', 'normal'
  String _referralStatusFilter = 'all'; // 'all', 'pending', 'acknowledged', 'arrived'

  // Real-time Escalated Alert Pop Card State
  Map<String, dynamic>? _activeEscalatedAlert;
  final Set<String> _dismissedAlertIds = {};
  Timer? _pollingTimer;

  // Selected Hospital Facility
  final String _activeHospitalName = 'Rajiv Gandhi Government Women & Children Hospital (RGGWCH)';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    // Real-time polling every 5 seconds for incoming escalated alerts from PHCs
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollAlertsAndReferrals());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadFacilities(),
        _loadReferrals(),
        _loadAlerts(),
        _loadAllPatients(),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFacilities() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/facilities');
      final items = List<Map<String, dynamic>>.from(res['items'] ?? []);
      final phcs = items.where((f) => f['facility_type'] == 'PHC').toList();
      if (mounted) {
        setState(() {
          _phcList = phcs;
          if (_phcList.isNotEmpty && _selectedPhc == null) {
            _selectedPhc = _phcList.first;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadReferrals() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/referrals');
      final items = List<Map<String, dynamic>>.from(res['items'] ?? []);
      if (mounted) {
        setState(() => _referrals = items);
      }
    } catch (_) {}
  }

  Future<void> _loadAlerts() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/alerts?limit=50');
      final items = List<Map<String, dynamic>>.from(res['items'] ?? []);
      if (mounted) {
        setState(() {
          _alerts = items;
          _checkForEscalatedAlerts();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAllPatients() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/patients?limit=200');
      final items = List<Map<String, dynamic>>.from(res['items'] ?? []);
      if (mounted) {
        setState(() => _allPatients = items);
      }
    } catch (_) {}
  }

  Future<void> _pollAlertsAndReferrals() async {
    await Future.wait([_loadAlerts(), _loadReferrals()]);
  }

  void _checkForEscalatedAlerts() {
    final activeReds = _alerts.where((a) =>
        a['severity'] == 'red' &&
        a['status'] == 'active' &&
        !_dismissedAlertIds.contains(a['id']?.toString()));

    if (activeReds.isNotEmpty) {
      final latest = activeReds.first;
      if (_activeEscalatedAlert == null || _activeEscalatedAlert!['id'] != latest['id']) {
        setState(() {
          _activeEscalatedAlert = latest;
        });
      }
    }
  }

  Future<void> _acceptEscalatedAlert(Map<String, dynamic> alert) async {
    final alertId = alert['id']?.toString();
    if (alertId == null) return;

    _dismissedAlertIds.add(alertId);

    try {
      // 1. Review alert as referred
      await ApiClient.instance.post('/api/v1/alerts/$alertId/review', {
        'status': 'referred',
        'review_notes': 'Escalated alert accepted by THC Receiving Hospital. Emergency bay assigned.',
      });

      // 2. Acknowledge matching referral if exists
      final patId = alert['patient_id']?.toString();
      final matchingRef = _referrals.firstWhere(
        (r) => r['patient_id']?.toString() == patId && (r['status'] == 'sent' || r['status'] == 'generated'),
        orElse: () => {},
      );

      if (matchingRef.isNotEmpty && matchingRef['id'] != null) {
        await ApiClient.instance.post(
          '/api/v1/referrals/${matchingRef['id']}/transition',
          {
            'status': 'acknowledged',
            'note': 'Referral acknowledged & accepted by THC Obstetric Medical Officer.',
          },
        );
      }

      if (mounted) {
        setState(() => _activeEscalatedAlert = null);
        showMessage(context, 'Alert Accepted! Emergency Obstetric Bay notified for incoming patient.');
        await _loadReferrals();
        await _loadAlerts();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Failed to accept alert: $e', error: true);
    }
  }

  Future<void> _transitionReferral(String refId, String targetStatus) async {
    try {
      await ApiClient.instance.post('/api/v1/referrals/$refId/transition', {
        'status': targetStatus,
        'note': 'Updated to $targetStatus via THC Web Command Center',
      });
      if (mounted) {
        showMessage(context, 'Referral transitioned to $targetStatus.');
        await _loadReferrals();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Transition error: $e', error: true);
    }
  }

  void _onPhcSelected(Map<String, dynamic> phc) {
    setState(() {
      _selectedPhc = phc;
      _activeTab = 'patients'; // Switch to patient roster view
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.instance.currentUser ?? {};
    final activeHospital = ApiClient.instance.activeFacilityName ?? _activeHospitalName;

    final redAlertsCount = _alerts.where((a) => a['severity'] == 'red' && a['status'] == 'active').length;
    final pendingReferralsCount = _referrals.where((r) => r['status'] == 'sent' || r['status'] == 'generated').length;

    // Filter PHCs
    final filteredPhcs = _phcList.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final code = (p['facility_code'] ?? '').toString().toLowerCase();
      final q = _phcSearchQuery.toLowerCase().trim();
      return name.contains(q) || code.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          Column(
            children: [
              // 1. TOP COMMAND BAR
              _buildTopHeader(user, activeHospital),

              // 2. METRICS ROW
              _buildMetricsRow(redAlertsCount, pendingReferralsCount),

              // 3. MAIN COMMAND CENTER (DUAL PANE)
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.crimson))
                    : _error != null
                        ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left Pane: Affiliated PHC Directory (360px)
                                SizedBox(
                                  width: 360,
                                  child: _buildPhcDirectoryPanel(filteredPhcs),
                                ),

                                const SizedBox(width: 20),

                                // Right Pane: Selected PHC Patients / Referrals Workspace
                                Expanded(
                                  child: _buildWorkspacePanel(),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),

          // 4. REAL-TIME ESCALATED INCOMING ALERT POP CARD
          if (_activeEscalatedAlert != null)
            Positioned(
              top: 80,
              right: 24,
              child: _buildIncomingAlertPopCard(_activeEscalatedAlert!),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Header Bar
  // -------------------------------------------------------------------------
  Widget _buildTopHeader(Map<String, dynamic> user, String hospitalName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECDD3)),
                        ),
                        child: const Icon(Icons.local_hospital, color: Color(0xFF991B1B), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Preeclampsia 360',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF991B1B),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'THC COMMAND CENTER',
                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            hospitalName,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(width: 24),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
                            SizedBox(width: 6),
                            Text(
                              'LIVE NETWORK MONITORING',
                              style: TextStyle(color: Color(0xFF065F46), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF1E293B),
                        child: Text(
                          (user['full_name'] ?? 'THC').toString().substring(0, 1),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user['full_name'] ?? 'Dr. Medical Officer',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const Text('Obstetric Consultant', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Sign Out',
                        icon: const Icon(Icons.logout, size: 18, color: AppColors.muted),
                        onPressed: widget.onLogout,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Metrics Row
  // -------------------------------------------------------------------------
  Widget _buildMetricsRow(int redAlerts, int pendingReferrals) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(child: _metricCard('Affiliated PHCs', '${_phcList.length} PHCs', Icons.home_work_outlined, const Color(0xFF0369A1), const Color(0xFFE0F2FE))),
          const SizedBox(width: 16),
          Expanded(child: _metricCard('Critical Red Alerts', '$redAlerts Alerts', Icons.warning_amber_rounded, const Color(0xFFDC2626), const Color(0xFFFEE2E2), isPulsing: redAlerts > 0)),
          const SizedBox(width: 16),
          Expanded(child: _metricCard('Incoming Referrals', '$pendingReferrals Pending', Icons.emergency_outlined, const Color(0xFFD97706), const Color(0xFFFEF3C7))),
          const SizedBox(width: 16),
          Expanded(child: _metricCard('HDU & ICU Capacity', '6 HDU • 8 NICU', Icons.bed_outlined, const Color(0xFF16A34A), const Color(0xFFDCFCE7))),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color, Color bg, {bool isPulsing = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Left Panel: Affiliated PHC Directory
  // -------------------------------------------------------------------------
  Widget _buildPhcDirectoryPanel(List<Map<String, dynamic>> phcs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title & Total
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.network_check, color: Color(0xFF991B1B), size: 18),
                    SizedBox(width: 8),
                    Text('Affiliated PHCs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${phcs.length} Total',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Filter by area or code...',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              onChanged: (v) => setState(() => _phcSearchQuery = v),
            ),
          ),

          const SizedBox(height: 6),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Scrollable PHC List
          Expanded(
            child: ListView.separated(
              itemCount: phcs.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (ctx, idx) {
                final phc = phcs[idx];
                final code = (phc['facility_code'] ?? '').toString();
                final isSelected = _selectedPhc != null && _selectedPhc!['facility_code'] == code;
                final phcPatients = _allPatients.where((p) => p['facility_id'] == phc['id']).length;

                return InkWell(
                  onTap: () => _onPhcSelected(phc),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: isSelected ? const Color(0xFFFEF2F2) : Colors.transparent,
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF991B1B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.home_work,
                            size: 16,
                            color: isSelected ? Colors.white : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (phc['name'] ?? '').toString().replaceAll(' Primary Health Centre', ''),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isSelected ? const Color(0xFF991B1B) : const Color(0xFF1E293B),
                                ),
                              ),
                              Text(
                                code,
                                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFEE2E2) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$phcPatients pts',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? const Color(0xFF991B1B) : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Right Workspace: Tabbed View (Referrals vs PHC Patients)
  // -------------------------------------------------------------------------
  Widget _buildWorkspacePanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Navigation Tab Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tabButton('referrals', 'Hospital Referrals & Handover (${_referrals.length})', Icons.emergency_share),
                  const SizedBox(width: 10),
                  _tabButton('patients', 'Selected PHC Patients', Icons.people_outline),
                  const SizedBox(width: 16),
                  IconButton(
                    tooltip: 'Refresh Network Data',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _loadInitialData,
                  ),
                ],
              ),
            ),
          ),

          // Workspace Body
          Expanded(
            child: _activeTab == 'referrals'
                ? _buildReferralsTab()
                : _buildSelectedPhcPatientsTab(),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String key, String title, IconData icon) {
    final isSel = _activeTab == key;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: isSel ? const Color(0xFF991B1B) : const Color(0xFFF1F5F9),
        foregroundColor: isSel ? Colors.white : const Color(0xFF475569),
        elevation: isSel ? 1 : 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => setState(() => _activeTab = key),
      icon: Icon(icon, size: 16),
      label: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  // -------------------------------------------------------------------------
  // Referrals Workspace
  // -------------------------------------------------------------------------
  Widget _buildReferralsTab() {
    var filtered = _referrals;
    if (_referralStatusFilter == 'pending') {
      filtered = filtered.where((r) => r['status'] == 'sent' || r['status'] == 'generated').toList();
    } else if (_referralStatusFilter == 'acknowledged') {
      filtered = filtered.where((r) => r['status'] == 'acknowledged').toList();
    } else if (_referralStatusFilter == 'arrived') {
      filtered = filtered.where((r) => r['status'] == 'arrived').toList();
    }

    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Incoming Referrals List', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 16),
                _refFilterChip('all', 'All'),
                const SizedBox(width: 6),
                _refFilterChip('pending', 'Pending Acceptance'),
                const SizedBox(width: 6),
                _refFilterChip('acknowledged', 'In Transit'),
                const SizedBox(width: 6),
                _refFilterChip('arrived', 'Arrived'),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox, size: 40, color: Color(0xFFCBD5E1)),
                      SizedBox(height: 8),
                      Text('No referrals found in this view', style: TextStyle(color: Color(0xFF64748B))),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, idx) {
                    final r = filtered[idx];
                    final refId = r['id']?.toString() ?? '';
                    final status = (r['status'] ?? '').toString();
                    final isPending = status == 'sent' || status == 'generated';
                    final summary = r['clinical_summary'] is Map ? r['clinical_summary'] as Map : {};
                    final meds = List<String>.from(summary['selected_medicines'] ?? ['Tab Labetalol 100 mg']);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isPending ? const Color(0xFFFFF1F2) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isPending ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPending ? const Color(0xFFDC2626) : const Color(0xFF0369A1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        r['reason'] ?? 'Emergency Maternal Referral',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Originating Facility: ${summary["referring_facility"] ?? "PHC"} • Patient ID: ${r["patient_id"]?.toString().substring(0, 8)}...',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: meds.map((m) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFA7F3D0)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.check, size: 10, color: Color(0xFF059669)),
                                          const SizedBox(width: 2),
                                          Text(m, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF065F46))),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Action buttons
                          if (isPending)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF991B1B)),
                              onPressed: () => _transitionReferral(refId, 'acknowledged'),
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Accept Handover', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            )
                          else if (status == 'acknowledged')
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                              onPressed: () => _transitionReferral(refId, 'arrived'),
                              child: const Text('Mark Arrived', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            )
                          else if (status == 'arrived')
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                              onPressed: () => _transitionReferral(refId, 'completed'),
                              child: const Text('Complete Handover', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _refFilterChip(String key, String label) {
    final isSel = _referralStatusFilter == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.white : const Color(0xFF475569))),
      selected: isSel,
      selectedColor: const Color(0xFF1E293B),
      backgroundColor: const Color(0xFFF1F5F9),
      onSelected: (_) => setState(() => _referralStatusFilter = key),
    );
  }

  // -------------------------------------------------------------------------
  // Selected PHC Patients Workspace
  // -------------------------------------------------------------------------
  Widget _buildSelectedPhcPatientsTab() {
    if (_selectedPhc == null) {
      return const Center(child: Text('Select a PHC from the left directory.'));
    }

    final phcId = _selectedPhc!['id'];
    var patients = _allPatients.where((p) => p['facility_id'] == phcId).toList();

    if (_patientRiskFilter == 'red') {
      patients = patients.where((p) => p['risk_level'] == 'high' || p['risk_level'] == 'critical').toList();
    } else if (_patientRiskFilter == 'normal') {
      patients = patients.where((p) => p['risk_level'] != 'high' && p['risk_level'] != 'critical').toList();
    }

    return Column(
      children: [
        // Selected PHC Profile Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          _selectedPhc!['facility_code'] ?? 'PHC',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedPhc!['name'] ?? 'Primary Health Centre',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_selectedPhc!["address"] ?? "Puducherry"} • Doctor On-Duty: Dr. MO (${_selectedPhc!["facility_code"]?.toString().replaceAll("PY-PHC-", "")})',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              Row(
                children: [
                  _riskFilterChip('all', 'All'),
                  const SizedBox(width: 4),
                  _riskFilterChip('red', 'Red Alert'),
                  const SizedBox(width: 4),
                  _riskFilterChip('normal', 'Normal'),
                ],
              ),
            ],
          ),
        ),

        // Patients Table
        Expanded(
          child: patients.isEmpty
              ? Center(
                  child: Text('No mothers registered under ${_selectedPhc!["name"]}.', style: const TextStyle(color: Color(0xFF94A3B8))),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: patients.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (ctx, idx) {
                    final p = patients[idx];
                    final isRed = p['risk_level'] == 'high' || p['risk_level'] == 'critical';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: isRed ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                        child: Icon(Icons.person, color: isRed ? const Color(0xFFDC2626) : const Color(0xFF64748B), size: 18),
                      ),
                      title: Text(p['full_name'] ?? 'Mother', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        '${p["patient_code"] ?? ""} • GA: ${p["gestational_weeks"] ?? 28} Wks • Blood: ${p["blood_group"] ?? "O+"}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isRed ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isRed ? 'RED ALERT' : 'NORMAL',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isRed ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, size: 14),
                            onPressed: () => _openPatientSheet(p),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _riskFilterChip(String key, String label) {
    final isSel = _patientRiskFilter == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.white : const Color(0xFF475569))),
      selected: isSel,
      selectedColor: const Color(0xFF1E293B),
      backgroundColor: const Color(0xFFF1F5F9),
      onSelected: (_) => setState(() => _patientRiskFilter = key),
    );
  }

  void _openPatientSheet(Map<String, dynamic> patient) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReferralSheetScreen(
          patientId: patient['id'],
          patientName: patient['full_name'] ?? 'Mother',
          patientCode: patient['patient_code'] ?? 'PE360',
          selectedMedicines: const [],
          receivingFacilityName: _activeHospitalName,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Real-Time Escalated Alert Floating Pop Card
  // -------------------------------------------------------------------------
  Widget _buildIncomingAlertPopCard(Map<String, dynamic> alert) {
    final pat = alert['patient'] is Map ? alert['patient'] as Map : {};
    final ad = alert['alert_data'] is Map ? alert['alert_data'] as Map : {};
    final bp = (ad['systolic'] != null && ad['diastolic'] != null)
        ? '${ad["systolic"]}/${ad["diastolic"]} mmHg'
        : '168/118 mmHg (Severe)';

    return Container(
      width: 420,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDC2626), width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF991B1B), Color(0xFFDC2626)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emergency, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'INCOMING ESCALATED ALERT FROM PHC',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 16),
                  onPressed: () => setState(() {
                    _dismissedAlertIds.add(alert['id']?.toString() ?? '');
                    _activeEscalatedAlert = null;
                  }),
                ),
              ],
            ),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pat['full_name'] ?? 'Pregnant Mother',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          pat['patient_code'] ?? 'PE360-ALERT',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    Text(
                      alert['facility_name'] ?? 'Primary Health Centre',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Critical Blood Pressure:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF991B1B))),
                      Text(bp, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF991B1B))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _acceptEscalatedAlert(alert),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text(
                      'Accept Alert & Acknowledge Handover',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
