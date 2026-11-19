import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import 'referral_sheet_screen.dart';

class StabilizePatientDialog extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String patientCode;
  final int? systolic;
  final int? diastolic;
  final String? alertId;
  final VoidCallback? onReferralCompleted;

  const StabilizePatientDialog({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.patientCode,
    this.systolic,
    this.diastolic,
    this.alertId,
    this.onReferralCompleted,
  });

  @override
  State<StabilizePatientDialog> createState() => _StabilizePatientDialogState();
}

class _StabilizePatientDialogState extends State<StabilizePatientDialog> {
  static const List<String> kStabilizationMedicines = [
    'Tab Labetalol 100 mg',
    'Tab Nifidipine 10 mg',
    'IV MgSO4 4g iv',
    'IV Lasix',
    'Betamethasone 12mg',
    'Dexamethasone 12mg',
  ];

  final Set<String> selectedMedicines = {};
  final notesCtrl = TextEditingController();
  List<dynamic> facilities = [];
  String? receivingFacilityId;
  String? receivingFacilityName;
  bool loading = true;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    _loadFacilities();
  }

  @override
  void dispose() {
    notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFacilities() async {
    try {
      final fRes = await ApiClient.instance.get('/api/v1/facilities');
      if (mounted) {
        final allFacs = List<dynamic>.from(fRes['items'] ?? []);
        final myFid = ApiClient.instance.activeFacilityId;
        final filtered = allFacs.where((f) => f['id']?.toString() != myFid).toList();
        setState(() {
          facilities = filtered;
          if (facilities.isNotEmpty) {
            receivingFacilityId = facilities.first['id']?.toString();
            receivingFacilityName = facilities.first['name']?.toString();
          }
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _onPrintReferralSheet() async {
    if (receivingFacilityId == null && facilities.isNotEmpty) {
      receivingFacilityId = facilities.first['id']?.toString();
      receivingFacilityName = facilities.first['name']?.toString();
    }

    setState(() => submitting = true);
    Map<String, dynamic>? createdReferral;

    try {
      final bpText = widget.systolic != null && widget.diastolic != null
          ? '${widget.systolic}/${widget.diastolic} mmHg'
          : 'Severe Range';

      final reason = 'Emergency Red Alert Referral: Severe Hypertension ($bpText). '
          'Pre-referral stabilization initiated at PHC.';

      final clinicalSummary = {
        'stabilization_medicines': selectedMedicines.toList(),
        'latest_bp': bpText,
        'alert_id': widget.alertId,
        'notes': notesCtrl.text.trim(),
        'stabilized_at': DateTime.now().toIso8601String(),
        'referring_facility': ApiClient.instance.activeFacilityName ?? 'PHC',
      };

      if (receivingFacilityId != null) {
        final res = await ApiClient.instance.post('/api/v1/referrals', {
          'patient_id': widget.patientId,
          'receiving_facility_id': receivingFacilityId,
          'reason': reason,
          'clinical_summary': clinicalSummary,
        });
        createdReferral = res is Map<String, dynamic> ? res : null;
      }

      // If tied to an alert, review the alert
      if (widget.alertId != null) {
        try {
          await ApiClient.instance.post('/api/v1/alerts/${widget.alertId}/review', {
            'status': 'referred',
            'review_notes': 'Referral initiated with stabilization medicines: ${selectedMedicines.join(", ")}',
          });
        } catch (_) {}
      }

      widget.onReferralCompleted?.call();

      if (mounted) {
        Navigator.pop(context); // Close dialog
        // Navigate to the Print Referral Sheet screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReferralSheetScreen(
              patientId: widget.patientId,
              patientName: widget.patientName,
              patientCode: widget.patientCode,
              selectedMedicines: selectedMedicines.toList(),
              receivingFacilityName: receivingFacilityName ?? 'Tertiary Hospital',
              notes: notesCtrl.text.trim(),
              referralData: createdReferral,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Failed to save referral: $e', error: true);
        setState(() => submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bpDisplay = widget.systolic != null && widget.diastolic != null
        ? '${widget.systolic} / ${widget.diastolic} mmHg'
        : 'Severe Hypertension';

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        decoration: const BoxDecoration(
          color: Color(0xFF991B1B), // Dark emergency crimson
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Row(
          children: [
            const Icon(Icons.emergency, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stabilize the Patient',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  Text(
                    'Pre-referral emergency clinical stabilization',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'RED ALERT',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 520,
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator(color: AppColors.crimson)),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Patient Banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFFEE2E2),
                            child: Icon(Icons.person, color: Color(0xFFDC2626)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.patientName,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF991B1B)),
                                ),
                                Text(
                                  'ID: ${widget.patientCode}  •  BP: $bpDisplay',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFB91C1C)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Emergency Stabilization Medicines',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink),
                    ),
                    const Text(
                      'Tick all medications administered to the patient prior to emergency transfer:',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),

                    // 6 Checkboxes for the specified medicines
                    Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: Column(
                        children: kStabilizationMedicines.map((med) {
                          final isChecked = selectedMedicines.contains(med);
                          return CheckboxListTile(
                            value: isChecked,
                            dense: true,
                            activeColor: const Color(0xFF991B1B),
                            title: Text(
                              med,
                              style: TextStyle(
                                fontWeight: isChecked ? FontWeight.w800 : FontWeight.w600,
                                color: isChecked ? const Color(0xFF991B1B) : AppColors.ink,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              _getMedDescription(med),
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  selectedMedicines.add(med);
                                } else {
                                  selectedMedicines.remove(med);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Receiving Facility Selector
                    if (facilities.isNotEmpty) ...[
                      const Text(
                        'Destination Receiving Facility',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: receivingFacilityId,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: facilities.map((f) {
                          return DropdownMenuItem<String>(
                            value: f['id']?.toString(),
                            child: Text(
                              '${f['name']} (${f['facility_type'] ?? ''})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            receivingFacilityId = val;
                            final match = facilities.firstWhere(
                              (f) => f['id']?.toString() == val,
                              orElse: () => null,
                            );
                            receivingFacilityName = match?['name']?.toString();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Notes Field
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Clinical Notes / Stabilizing Directives',
                        hintText: 'e.g. Patient IV line established, Foley catheter placed...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF991B1B),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          onPressed: submitting ? null : _onPrintReferralSheet,
          icon: submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.print_outlined, size: 18),
          label: Text(
            submitting ? 'Preparing Sheet...' : 'Print Referral Sheet',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _getMedDescription(String med) {
    switch (med) {
      case 'Tab Labetalol 100 mg':
        return 'First-line oral anti-hypertensive for acute BP reduction';
      case 'Tab Nifidipine 10 mg':
        return 'Oral calcium channel blocker (rapid acting)';
      case 'IV MgSO4 4g iv':
        return 'Loading dose for eclampsia seizure prophylaxis';
      case 'IV Lasix':
        return 'Furosemide for pulmonary edema or fluid overload';
      case 'Betamethasone 12mg':
        return 'Antenatal corticosteroid for fetal lung maturation';
      case 'Dexamethasone 12mg':
        return 'Alternative corticosteroid for fetal lung maturation';
      default:
        return 'Emergency stabilization medication';
    }
  }
}

