import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';

class ReferralScreen extends StatefulWidget {
  final String? initialPatientId;
  final String? initialReason;
  const ReferralScreen({super.key, this.initialPatientId, this.initialReason});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  List<dynamic> referrals = [];
  bool loading = true;
  String? error;
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    load().then((_) {
      if (widget.initialPatientId != null && mounted) {
        showDialog(
          context: context,
          builder: (c) => _CreateReferralDialog(
            initialPatientId: widget.initialPatientId,
            initialReason: widget.initialReason,
            onCreated: load,
          ),
        );
      }
    });
  }

  Future<void> load() async {
    try {
      final r = await ApiClient.instance.get('/api/v1/referrals');
      if (mounted) {
        setState(() {
          referrals = List.from(r['items'] ?? []);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> change(String id, String status) async {
    try {
      await ApiClient.instance.post(
        '/api/v1/referrals/$id/transition',
        {'status': status, 'note': 'Updated via Preeclampsia 360 app'},
      );
      if (mounted) {
        showMessage(context, 'Referral transitioned to $status.');
      }
      await load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  bool _isOrigin(Map<String, dynamic> r) {
    final myFid = ApiClient.instance.activeFacilityId;
    return r['origin_facility_id']?.toString() == myFid;
  }

  bool _isReceiver(Map<String, dynamic> r) {
    final myFid = ApiClient.instance.activeFacilityId;
    return r['receiving_facility_id']?.toString() == myFid;
  }

  bool _isAdmin() {
    final a = ApiClient.instance.assignments;
    return a.any((x) => x['role'] == 'SYSTEM_ADMIN' || x['role']?.toString().contains('ADMIN') == true);
  }

  @override
  Widget build(BuildContext context) {
    final isPushed = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.warmWhite,
      appBar: isPushed ? AppBar(title: const Text('Referrals & Handover')) : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: P360Header('Referral coordination', subtitle: 'Track referrals through receiving-facility handover'),
                  ),
                  IconButton.filled(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _CreateReferralDialog(onCreated: load),
                    ),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All Referrals')),
                  ButtonSegment(value: 'inbox', label: Text('Receiving Inbox'), icon: Icon(Icons.inbox)),
                  ButtonSegment(value: 'outbound', label: Text('Dispatches'), icon: Icon(Icons.outbox)),
                ],
                selected: {filter},
                onSelectionChanged: (s) => setState(() => filter = s.first),
              ),
            ),
            const SizedBox(height: 8),
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
                      : referrals.isEmpty
                          ? const Center(child: Text('No active referrals for your assigned facility.'))
                          : RefreshIndicator(
                              onRefresh: load,
                              child: Builder(
                                builder: (context) {
                                  final displayed = referrals.where((r) {
                                    final item = Map<String, dynamic>.from(r as Map);
                                    if (filter == 'inbox') return _isReceiver(item);
                                    if (filter == 'outbound') return _isOrigin(item);
                                    return true;
                                  }).toList();

                                  if (displayed.isEmpty) {
                                    return Center(
                                      child: Text(
                                        filter == 'inbox'
                                            ? 'No incoming referrals waiting in your facility inbox.'
                                            : 'No referrals in this view.',
                                        style: const TextStyle(color: AppColors.muted),
                                      ),
                                    );
                                  }

                                  return ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: displayed.length,
                                    itemBuilder: (context, i) {
                                      final r = Map<String, dynamic>.from(displayed[i] as Map);
                                  final status = (r['status'] ?? 'generated').toString();
                                  final isOrig = _isOrigin(r);
                                  final isRecv = _isReceiver(r);
                                  final isAdmin = _isAdmin();

                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Referral ${r['id'].toString().substring(0, 8)}',
                                                style: const TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                              StatusPill(
                                                status.toUpperCase(),
                                                color: status == 'completed'
                                                    ? AppColors.success
                                                    : status == 'rejected'
                                                        ? AppColors.critical
                                                        : AppColors.warning,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(r['reason'] ?? 'No reason recorded', style: const TextStyle(fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              if (isOrig) const StatusPill('ORIGIN FACILITY', color: AppColors.slate),
                                              if (isRecv) const StatusPill('RECEIVING FACILITY', color: AppColors.crimson),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              if (status == 'generated' && (isOrig || isAdmin))
                                                OutlinedButton(
                                                  onPressed: () => change(r['id'], 'sent'),
                                                  child: const Text('Send Referral'),
                                                ),
                                              if (status == 'sent' && (isRecv || isAdmin)) ...[
                                                FilledButton(
                                                  onPressed: () => change(r['id'], 'acknowledged'),
                                                  child: const Text('Acknowledge'),
                                                ),
                                                OutlinedButton(
                                                  onPressed: () => change(r['id'], 'rejected'),
                                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.critical),
                                                  child: const Text('Reject'),
                                                ),
                                              ],
                                              if (status == 'acknowledged' && (isOrig || isAdmin))
                                                OutlinedButton(
                                                  onPressed: () => change(r['id'], 'departed'),
                                                  child: const Text('Mark Departed'),
                                                ),
                                              if (status == 'departed' && (isRecv || isAdmin))
                                                FilledButton(
                                                  onPressed: () => change(r['id'], 'arrived'),
                                                  child: const Text('Mark Arrived'),
                                                ),
                                              if (status == 'arrived' && (isRecv || isAdmin))
                                                FilledButton(
                                                  onPressed: () => change(r['id'], 'assessed'),
                                                  child: const Text('Mark Assessed'),
                                                ),
                                              if (status == 'assessed' && (isRecv || isAdmin)) ...[
                                                FilledButton(
                                                  onPressed: () => change(r['id'], 'completed'),
                                                  child: const Text('Complete Referral'),
                                                ),
                                                OutlinedButton(
                                                  onPressed: () => change(r['id'], 'redirected'),
                                                  child: const Text('Redirect'),
                                                ),
                                              ],
                                              if (status == 'rejected' && (isOrig || isAdmin))
                                                OutlinedButton(
                                                  onPressed: () => change(r['id'], 'redirected'),
                                                  child: const Text('Redirect Referral'),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
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

class _CreateReferralDialog extends StatefulWidget {
  final Future<void> Function() onCreated;
  final String? initialPatientId;
  final String? initialReason;
  const _CreateReferralDialog({required this.onCreated, this.initialPatientId, this.initialReason});
  @override
  State<_CreateReferralDialog> createState() => _CreateReferralDialogState();
}

class _CreateReferralDialogState extends State<_CreateReferralDialog> {
  late final TextEditingController reason;
  List<dynamic> patients = [];
  List<dynamic> facilities = [];
  String? patientId;
  String? receivingFacilityId;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    reason = TextEditingController(text: widget.initialReason ?? '');
    patientId = widget.initialPatientId;
    _loadData();
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final pRes = await ApiClient.instance.get('/api/v1/patients?limit=100');
      final fRes = await ApiClient.instance.get('/api/v1/facilities');
      if (mounted) {
        setState(() {
          patients = List.from(pRes['items'] ?? []);
          facilities = List.from(fRes['items'] ?? []);
          // Exclude own facility from receiving list
          final myFid = ApiClient.instance.activeFacilityId;
          if (myFid != null) {
            facilities = facilities.where((f) => f['id']?.toString() != myFid).toList();
          }
          if (receivingFacilityId == null && facilities.isNotEmpty) {
            receivingFacilityId = facilities.first['id']?.toString();
          }
        });
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    if (patientId == null) {
      showMessage(context, 'Please select a patient.', error: true);
      return;
    }
    if (receivingFacilityId == null) {
      showMessage(context, 'Please select a receiving facility (CHC, THC, or Hospital).', error: true);
      return;
    }
    if (reason.text.trim().length < 3) {
      showMessage(context, 'Please enter a detailed referral reason.', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      await ApiClient.instance.post('/api/v1/referrals', {
        'patient_id': patientId,
        'receiving_facility_id': receivingFacilityId,
        'reason': reason.text.trim(),
        'clinical_summary': {'source': 'flutter_app', 'timestamp': DateTime.now().toUtc().toIso8601String()},
      });
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Referral created and logged.');
        await widget.onCreated();
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Referral'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: patients.any((p) => p['id'].toString() == patientId) ? patientId : null,
              decoration: const InputDecoration(labelText: 'Patient'),
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
            DropdownButtonFormField<String>(
              initialValue: facilities.any((f) => f['id'].toString() == receivingFacilityId) ? receivingFacilityId : null,
              decoration: const InputDecoration(labelText: 'Receiving Facility (Target)'),
              items: facilities
                  .map((f) => DropdownMenuItem<String>(
                        value: f['id'].toString(),
                        child: Text(
                          '${f['name']} (${f['facility_type']})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => receivingFacilityId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason for referral (clinical indications)',
                hintText: 'e.g. Systolic >= 160 mmHg, severe headache, epigastric pain',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : create,
          child: saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create Referral'),
        ),
      ],
    );
  }
}
