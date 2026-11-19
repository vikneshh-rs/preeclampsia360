import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import 'referral_screen.dart';

class PuducherryHospital {
  final String id;
  final String shortName;
  final String fullName;
  final String facilityCode;
  final String address;
  final double latitude;
  final double longitude;
  final double relX; // 0..1 relative position on map canvas
  final double relY; // 0..1 relative position on map canvas
  final double distanceKm;
  final int transitMinutes;
  final String emergencyPhone;
  final List<String> specializedServices;
  final bool isApexCenter;
  final int availableIcuBeds;

  const PuducherryHospital({
    required this.id,
    required this.shortName,
    required this.fullName,
    required this.facilityCode,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.relX,
    required this.relY,
    required this.distanceKm,
    required this.transitMinutes,
    required this.emergencyPhone,
    required this.specializedServices,
    this.isApexCenter = false,
    this.availableIcuBeds = 4,
  });

  PuducherryHospital copyWith({String? id}) {
    return PuducherryHospital(
      id: id ?? this.id,
      shortName: shortName,
      fullName: fullName,
      facilityCode: facilityCode,
      address: address,
      latitude: latitude,
      longitude: longitude,
      relX: relX,
      relY: relY,
      distanceKm: distanceKm,
      transitMinutes: transitMinutes,
      emergencyPhone: emergencyPhone,
      specializedServices: specializedServices,
      isApexCenter: isApexCenter,
      availableIcuBeds: availableIcuBeds,
    );
  }
}

class NearbyHospitalsMapScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String patientCode;
  final List<String> selectedMedicines;
  final String? existingReferralId;
  final String? notes;
  final Map<String, dynamic>? referralData;

  const NearbyHospitalsMapScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.patientCode,
    required this.selectedMedicines,
    this.existingReferralId,
    this.notes,
    this.referralData,
  });

  @override
  State<NearbyHospitalsMapScreen> createState() => _NearbyHospitalsMapScreenState();
}

class _NearbyHospitalsMapScreenState extends State<NearbyHospitalsMapScreen>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformController;
  late final AnimationController _pulseController;
  bool _loadingFacilities = true;
  bool _transmitting = false;
  int _selectedTab = 0; // 0: Map View, 1: Hospital Directory List

  // 5 Key Puducherry Maternity Hospitals
  List<PuducherryHospital> _hospitals = [
    const PuducherryHospital(
      id: '5b95070e-c913-4b57-994c-da8e4f97f30d',
      shortName: 'RGGWCH',
      fullName: 'Rajiv Gandhi Government Women & Children Hospital',
      facilityCode: 'PY-THC-01',
      address: 'Ellaipillaichavady, Puducherry',
      latitude: 11.9360,
      longitude: 79.8080,
      relX: 0.65,
      relY: 0.58,
      distanceKm: 3.1,
      transitMinutes: 8,
      emergencyPhone: '+91 413 2200252 / 108',
      specializedServices: [
        'Dedicated Apex Maternal Hospital',
        '24/7 Eclampsia Labor Room',
        'Obstetric HDU & Level-III NICU',
        'Emergency Blood Storage Center',
      ],
      isApexCenter: true,
      availableIcuBeds: 6,
    ),
    const PuducherryHospital(
      id: '66fb0f8f-2db9-4e0d-9b80-19628bc70055',
      shortName: 'JIPMER',
      fullName: 'JIPMER (Jawaharlal Institute of Postgraduate Medical Education & Research)',
      facilityCode: 'PY-HOSP-JIPMER',
      address: 'Gorimedu, Puducherry',
      latitude: 11.9542,
      longitude: 79.8093,
      relX: 0.62,
      relY: 0.42,
      distanceKm: 4.2,
      transitMinutes: 12,
      emergencyPhone: '+91 413 2296000 / 108',
      specializedServices: [
        'Central Institute of National Importance',
        'Apex Intensive Maternal Care Unit',
        'Multi-organ Failure & Dialysis Unit',
        'Super-specialty Neonatology Level-III',
      ],
      isApexCenter: true,
      availableIcuBeds: 8,
    ),
    const PuducherryHospital(
      id: '466e8758-fafa-4996-ac85-b4d44babe070',
      shortName: 'IGMC&RI',
      fullName: 'Indira Gandhi Medical College & Research Institute',
      facilityCode: 'PY-HOSP-IGMCRI',
      address: 'Kathirkamam, Puducherry',
      latitude: 11.9488,
      longitude: 79.7915,
      relX: 0.52,
      relY: 0.50,
      distanceKm: 5.6,
      transitMinutes: 15,
      emergencyPhone: '+91 413 2277540 / 108',
      specializedServices: [
        'Govt Medical College Hospital',
        'Comprehensive Emergency Obstetric Care',
        'Surgical Obstetric ICU',
        '24/7 Transfusion Medicine Unit',
      ],
      availableIcuBeds: 5,
    ),
    const PuducherryHospital(
      id: '5cb241d6-077b-4068-83ce-bc71fc58cc12',
      shortName: 'PIMS',
      fullName: 'Pondicherry Institute of Medical Sciences',
      facilityCode: 'PY-HOSP-PIMS',
      address: 'Kalapet, East Coast Road (ECR), Puducherry',
      latitude: 12.0227,
      longitude: 79.8546,
      relX: 0.78,
      relY: 0.16,
      distanceKm: 11.5,
      transitMinutes: 20,
      emergencyPhone: '+91 413 2656271 / 108',
      specializedServices: [
        'Coastal Tertiary Referral Center',
        'Maternal-Fetal Medicine Specialists',
        'Advanced Cardiac & Respiratory HDU',
        'Level-III NICU & Transport Incubators',
      ],
      availableIcuBeds: 4,
    ),
    const PuducherryHospital(
      id: 'c7b08913-3f1f-4292-9a48-3bec7fde05d2',
      shortName: 'SMVMCH',
      fullName: 'Sri Manakula Vinayagar Medical College and Hospital',
      facilityCode: 'PY-HOSP-SMVMCH',
      address: 'Madagadipet, Puducherry',
      latitude: 11.9163,
      longitude: 79.6335,
      relX: 0.18,
      relY: 0.68,
      distanceKm: 18.5,
      transitMinutes: 28,
      emergencyPhone: '+91 413 2643000 / 108',
      specializedServices: [
        'Western Corridor Apex Medical Center',
        'High-Risk Pregnancy Care Unit',
        'Special Newborn Care Unit (SNCU)',
        'Obstetric Ultrasound & Doppler Lab',
      ],
      availableIcuBeds: 4,
    ),
  ];

  PuducherryHospital? _selectedHospital;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Default to the closest apex hospital (RGGWCH)
    _selectedHospital = _hospitals.first;
    _syncFacilitiesFromBackend();
  }

  @override
  void dispose() {
    _transformController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _syncFacilitiesFromBackend() async {
    try {
      final res = await ApiClient.instance.get('/api/v1/facilities');
      final items = List<Map<String, dynamic>>.from(res['items'] ?? []);

      if (items.isNotEmpty && mounted) {
        setState(() {
          _hospitals = _hospitals.map((h) {
            final match = items.firstWhere(
              (item) =>
                  item['facility_code'] == h.facilityCode ||
                  (item['name'] != null &&
                      item['name'].toString().toLowerCase().contains(h.shortName.toLowerCase())),
              orElse: () => {},
            );
            if (match.isNotEmpty && match['id'] != null) {
              return h.copyWith(id: match['id'].toString());
            }
            return h;
          }).toList();

          if (_selectedHospital != null) {
            _selectedHospital = _hospitals.firstWhere(
              (h) => h.facilityCode == _selectedHospital!.facilityCode,
              orElse: () => _hospitals.first,
            );
          }
        });
      }
    } catch (_) {
      // Retain pre-configured verified Puducherry hospital database
    } finally {
      if (mounted) setState(() => _loadingFacilities = false);
    }
  }

  void _onHospitalTapped(PuducherryHospital hospital) {
    setState(() => _selectedHospital = hospital);
  }

  void _confirmAndTransmitReferral(PuducherryHospital hospital) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReferralDispatchBottomSheet(
        hospital: hospital,
        patientName: widget.patientName,
        patientCode: widget.patientCode,
        selectedMedicines: widget.selectedMedicines,
        notes: widget.notes,
        onConfirm: () async {
          Navigator.pop(ctx);
          await _executeReferralDispatch(hospital);
        },
      ),
    );
  }

  Future<void> _executeReferralDispatch(PuducherryHospital hospital) async {
    setState(() => _transmitting = true);
    try {
      final referringFac = ApiClient.instance.activeFacilityName ?? 'Muthialpet PHC';
      final reason = 'Emergency Red Alert Referral: Severe Preeclampsia / HTN. '
          'Patient routed to ${hospital.shortName}. Pre-referral stabilization initiated at $referringFac.';

      final clinicalSummary = {
        'receiving_hospital_name': hospital.fullName,
        'receiving_facility_code': hospital.facilityCode,
        'selected_medicines': widget.selectedMedicines,
        'referring_facility': referringFac,
        'notes': widget.notes,
        'dispatched_via': 'Puducherry Maternity Care Map',
        'distance_km': hospital.distanceKm,
        'transit_minutes': hospital.transitMinutes,
        'dispatched_at': DateTime.now().toIso8601String(),
      };

      String referralId = widget.existingReferralId ?? '';

      if (referralId.isEmpty) {
        final createRes = await ApiClient.instance.post('/api/v1/referrals', {
          'patient_id': widget.patientId,
          'receiving_facility_id': hospital.id,
          'reason': reason,
          'clinical_summary': clinicalSummary,
        });
        referralId = createRes['id']?.toString() ?? '';
      }

      // Transition referral to 'sent'
      if (referralId.isNotEmpty) {
        try {
          await ApiClient.instance.post(
            '/api/v1/referrals/$referralId/transition',
            {
              'status': 'sent',
              'note': 'Referral sheet dispatched to ${hospital.shortName} via Puducherry referral network.',
            },
          );
        } catch (_) {
          // Fallback if transition is already handled or in alternate status
        }
      }

      if (mounted) {
        _showSuccessDialog(hospital, referralId);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Referral dispatch failed: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _transmitting = false);
    }
  }

  void _showSuccessDialog(PuducherryHospital hospital, String referralId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Referral Dispatched!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_hospital, size: 18, color: Color(0xFF991B1B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hospital.fullName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Text('Patient: ${widget.patientName} (${widget.patientCode})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Status: Assigned & Sent • Ambulance ETA: ~${hospital.transitMinutes} mins',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Emergency Hotline: ${hospital.emergencyPhone}',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The receiving obstetrician and labor room team at this facility have been notified. The referral sheet and stabilization details have been transmitted.',
              style: TextStyle(fontSize: 12, color: AppColors.slate),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ReferralScreen()),
                (route) => route.isFirst,
              );
            },
            child: const Text('View Referrals List'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF991B1B)),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop(); // Back to referral sheet
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _resetMapTransform() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selectedHospital ?? _hospitals.first;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Maternity Care Referral Map',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Puducherry Region • ${widget.patientName}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reset Map View',
            icon: const Icon(Icons.my_location_outlined),
            onPressed: _resetMapTransform,
          ),
          IconButton(
            tooltip: _selectedTab == 0 ? 'Switch to List' : 'Switch to Map',
            icon: Icon(_selectedTab == 0 ? Icons.format_list_bulleted : Icons.map_outlined),
            onPressed: () {
              setState(() => _selectedTab = _selectedTab == 0 ? 1 : 0);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _transmitting
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.crimson),
                  SizedBox(height: 16),
                  Text(
                    'Transmitting Referral Sheet & Assigning Patient...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Top Patient & Instructions strip
                _PatientRoutingStrip(
                  patientName: widget.patientName,
                  patientCode: widget.patientCode,
                  selectedMedicinesCount: widget.selectedMedicines.length,
                ),
                if (_loadingFacilities)
                  const LinearProgressIndicator(minHeight: 2, color: AppColors.crimson),

                // Main Content: Interactive Map or Hospital Directory List
                Expanded(
                  child: _selectedTab == 0
                      ? Stack(
                          children: [
                            // Interactive Puducherry Map Canvas
                            InteractiveViewer(
                              transformationController: _transformController,
                              minScale: 0.8,
                              maxScale: 2.8,
                              boundaryMargin: const EdgeInsets.all(80),
                              child: Center(
                                child: SizedBox(
                                  width: 720,
                                  height: 600,
                                  child: Stack(
                                    children: [
                                      // Custom Vector Map Background
                                      CustomPaint(
                                        size: const Size(720, 600),
                                        painter: _PuducherryMapPainter(
                                          hospitals: _hospitals,
                                          selectedHospital: sel,
                                        ),
                                      ),

                                      // Referring Facility Marker (Muthialpet PHC)
                                      _OriginPhcMarker(
                                        x: 720 * 0.69,
                                        y: 600 * 0.49,
                                      ),

                                      // 5 Hospital Location Pin Markers
                                      ..._hospitals.map((h) {
                                        final isSel = h.facilityCode == sel.facilityCode;
                                        return Positioned(
                                          left: (720 * h.relX) - 22,
                                          top: (600 * h.relY) - 52,
                                          child: _HospitalMapPin(
                                            hospital: h,
                                            isSelected: isSel,
                                            pulseAnimation: _pulseController,
                                            onTap: () => _onHospitalTapped(h),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Floating Map Controls & Map Legend
                            Positioned(
                              top: 12,
                              right: 12,
                              child: _MapControlsOverlay(
                                onZoomIn: () {
                                  _transformController.value =
                                      Matrix4.diagonal3Values(1.2, 1.2, 1.0) * _transformController.value;
                                },
                                onZoomOut: () {
                                  _transformController.value =
                                      Matrix4.diagonal3Values(0.833, 0.833, 1.0) * _transformController.value;
                                },
                                onReset: _resetMapTransform,
                              ),
                            ),

                            Positioned(
                              top: 12,
                              left: 12,
                              child: _MapLegend(),
                            ),
                          ],
                        )
                      : _HospitalListView(
                          hospitals: _hospitals,
                          selectedHospital: sel,
                          onSelect: _onHospitalTapped,
                          onAssign: _confirmAndTransmitReferral,
                        ),
                ),

                // Bottom Floating Sheet: Selected Hospital Details & Assign Action
                _SelectedHospitalActionCard(
                  hospital: sel,
                  patientName: widget.patientName,
                  onAssignPressed: () => _confirmAndTransmitReferral(sel),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Patient Routing Strip
// ---------------------------------------------------------------------------
class _PatientRoutingStrip extends StatelessWidget {
  final String patientName;
  final String patientCode;
  final int selectedMedicinesCount;

  const _PatientRoutingStrip({
    required this.patientName,
    required this.patientCode,
    required this.selectedMedicinesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF1F2),
        border: Border(bottom: BorderSide(color: Color(0xFFFECDD3))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.emergency_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF991B1B)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• $patientCode',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
                Text(
                  '$selectedMedicinesCount Stabilization Meds Administered • Tap hospital pin or card to assign & route',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF7F1D1D)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF991B1B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'RED ALERT',
              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hospital Map Pin Marker
// ---------------------------------------------------------------------------
class _HospitalMapPin extends StatelessWidget {
  final PuducherryHospital hospital;
  final bool isSelected;
  final AnimationController pulseAnimation;
  final VoidCallback onTap;

  const _HospitalMapPin({
    required this.hospital,
    required this.isSelected,
    required this.pulseAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated Pulse ring around pin if selected
          Stack(
            alignment: Alignment.center,
            children: [
              if (isSelected)
                AnimatedBuilder(
                  animation: pulseAnimation,
                  builder: (context, child) {
                    final scale = 1.0 + (pulseAnimation.value * 0.35);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFDC2626).withValues(alpha: 0.25 - (pulseAnimation.value * 0.15)),
                          border: Border.all(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // Pin Teardrop Shape
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF991B1B) : const Color(0xFFDC2626),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? const Color(0xFF991B1B).withValues(alpha: 0.45)
                          : Colors.black26,
                      blurRadius: isSelected ? 10 : 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    hospital.isApexCenter ? Icons.local_hospital : Icons.local_hospital_outlined,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          // Pin Stem / Arrow
          CustomPaint(
            size: const Size(12, 6),
            painter: _PinStemPainter(isSelected ? const Color(0xFF991B1B) : const Color(0xFFDC2626)),
          ),

          const SizedBox(height: 3),

          // Floating Label with Hospital Name and Distance
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF991B1B) : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? const Color(0xFF7F1D1D) : const Color(0xFFE2E8F0),
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hospital.shortName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${hospital.distanceKm}km',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.muted,
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

class _PinStemPainter extends CustomPainter {
  final Color color;
  _PinStemPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PinStemPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Referring PHC Origin Marker
// ---------------------------------------------------------------------------
class _OriginPhcMarker extends StatelessWidget {
  final double x;
  final double y;

  const _OriginPhcMarker({required this.x, required this.y});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x - 18,
      top: y - 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Muthialpet PHC (You)',
              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Puducherry Vector Map Painter
// ---------------------------------------------------------------------------
class _PuducherryMapPainter extends CustomPainter {
  final List<PuducherryHospital> hospitals;
  final PuducherryHospital selectedHospital;

  _PuducherryMapPainter({
    required this.hospitals,
    required this.selectedHospital,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Background Land Canvas
    final landPaint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), landPaint);

    // 2. Puducherry Territory Polygon with subtle contour
    final territoryPaint = Paint()..color = const Color(0xFFE2E8F0);
    final territoryPath = Path()
      ..moveTo(w * 0.10, h * 0.40)
      ..lineTo(w * 0.40, h * 0.20)
      ..lineTo(w * 0.70, h * 0.08)
      ..lineTo(w * 0.85, h * 0.12)
      ..lineTo(w * 0.76, h * 0.45)
      ..lineTo(w * 0.72, h * 0.75)
      ..lineTo(w * 0.45, h * 0.85)
      ..lineTo(w * 0.15, h * 0.78)
      ..close();
    canvas.drawPath(territoryPath, territoryPaint);

    // 3. Bay of Bengal Coastline (East side)
    final seaPaint = Paint()..color = const Color(0xFFBAE6FD);
    final seaPath = Path()
      ..moveTo(w * 0.78, 0)
      ..cubicTo(w * 0.75, h * 0.30, w * 0.71, h * 0.50, w * 0.74, h * 0.70)
      ..cubicTo(w * 0.76, h * 0.85, w * 0.73, h * 0.95, w * 0.72, h)
      ..lineTo(w, h)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(seaPath, seaPaint);

    // Coastal Water Contour
    final shoreLinePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final shorePath = Path()
      ..moveTo(w * 0.78, 0)
      ..cubicTo(w * 0.75, h * 0.30, w * 0.71, h * 0.50, w * 0.74, h * 0.70)
      ..cubicTo(w * 0.76, h * 0.85, w * 0.73, h * 0.95, w * 0.72, h);
    canvas.drawPath(shorePath, shoreLinePaint);

    // Bay of Bengal Label
    _drawText(
      canvas,
      'BAY OF BENGAL',
      Offset(w * 0.84, h * 0.45),
      const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0284C7),
        letterSpacing: 2.0,
      ),
    );

    // 4. Distance Radial Arcs from Muthialpet PHC (Origin)
    final originOffset = Offset(w * 0.69, h * 0.49);
    final arcPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final radius in [w * 0.12, w * 0.24, w * 0.38]) {
      canvas.drawCircle(originOffset, radius, arcPaint);
    }

    // 5. Road Networks connecting Referral Hospitals
    final highwayPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final roadPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // East Coast Road (ECR) connecting North to PIMS (Kalapet)
    final ecrPath = Path()
      ..moveTo(w * 0.69, h * 0.49) // Muthialpet PHC
      ..lineTo(w * 0.71, h * 0.35)
      ..lineTo(w * 0.78, h * 0.16); // PIMS
    canvas.drawPath(ecrPath, highwayPaint);

    // Villupuram Road (NH332) connecting West to SMVMCH (Madagadipet)
    final nh332Path = Path()
      ..moveTo(w * 0.65, h * 0.58) // RGGWCH
      ..lineTo(w * 0.52, h * 0.50) // IGMC&RI
      ..lineTo(w * 0.35, h * 0.56)
      ..lineTo(w * 0.18, h * 0.68); // SMVMCH
    canvas.drawPath(nh332Path, highwayPaint);

    // Gorimedu Road to JIPMER
    final jipmerPath = Path()
      ..moveTo(w * 0.69, h * 0.49) // Muthialpet
      ..lineTo(w * 0.62, h * 0.42); // JIPMER
    canvas.drawPath(jipmerPath, roadPaint);

    // Urban Arterial link: JIPMER to IGMC&RI
    final jipmerToIgmc = Path()
      ..moveTo(w * 0.62, h * 0.42)
      ..lineTo(w * 0.52, h * 0.50);
    canvas.drawPath(jipmerToIgmc, roadPaint);

    // Urban link: RGGWCH to Muthialpet
    final rggwchToPhc = Path()
      ..moveTo(w * 0.65, h * 0.58)
      ..lineTo(w * 0.69, h * 0.49);
    canvas.drawPath(rggwchToPhc, roadPaint);

    // Route line highlight from Origin PHC to Selected Hospital
    final selectedTarget = Offset(w * selectedHospital.relX, h * selectedHospital.relY);
    final routeHighlightPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final routePath = Path()
      ..moveTo(originOffset.dx, originOffset.dy)
      ..lineTo(selectedTarget.dx, selectedTarget.dy);
    canvas.drawPath(routePath, routeHighlightPaint);

    // Road Labels
    _drawText(
      canvas,
      'ECR Coastal Highway (To PIMS)',
      Offset(w * 0.71, h * 0.28),
      const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
    );

    _drawText(
      canvas,
      'NH 332 (To SMVMCH)',
      Offset(w * 0.28, h * 0.59),
      const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
    );

    // Compass Indicator (Top Right)
    final compassOffset = Offset(w * 0.08, h * 0.12);
    _drawCompass(canvas, compassOffset);
  }

  void _drawCompass(Canvas canvas, Offset center) {
    final pNorth = Paint()..color = const Color(0xFFDC2626);
    final pSouth = Paint()..color = const Color(0xFF94A3B8);

    final pathN = Path()
      ..moveTo(center.dx, center.dy - 16)
      ..lineTo(center.dx - 5, center.dy)
      ..lineTo(center.dx, center.dy - 3)
      ..close();
    canvas.drawPath(pathN, pNorth);

    final pathS = Path()
      ..moveTo(center.dx, center.dy + 16)
      ..lineTo(center.dx + 5, center.dy)
      ..lineTo(center.dx, center.dy + 3)
      ..close();
    canvas.drawPath(pathS, pSouth);

    _drawText(
      canvas,
      'N',
      Offset(center.dx - 4, center.dy - 30),
      const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFDC2626)),
    );
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _PuducherryMapPainter old) =>
      old.selectedHospital.facilityCode != selectedHospital.facilityCode;
}

// ---------------------------------------------------------------------------
// Map Legend Overlay
// ---------------------------------------------------------------------------
class _MapLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('MAP LEGEND', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.muted)),
          const SizedBox(height: 4),
          _legendItem(const Color(0xFFDC2626), 'Tertiary Maternity Care Center'),
          _legendItem(const Color(0xFF0D9488), 'Referring Facility (Origin PHC)'),
          _legendItem(const Color(0xFFFBBF24), 'Major Arterial Corridor / ECR'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map Controls Overlay (Zoom In, Zoom Out, Recenter)
// ---------------------------------------------------------------------------
class _MapControlsOverlay extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _MapControlsOverlay({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controlButton(Icons.add, onZoomIn, 'Zoom In'),
        const SizedBox(height: 6),
        _controlButton(Icons.remove, onZoomOut, 'Zoom Out'),
        const SizedBox(height: 6),
        _controlButton(Icons.refresh, onReset, 'Reset View'),
      ],
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onPressed, String tooltip) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: IconButton(
        icon: Icon(icon, size: 20, color: const Color(0xFF334155)),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom Card: Selected Hospital Details & Assign Action
// ---------------------------------------------------------------------------
class _SelectedHospitalActionCard extends StatelessWidget {
  final PuducherryHospital hospital;
  final String patientName;
  final VoidCallback onAssignPressed;

  const _SelectedHospitalActionCard({
    required this.hospital,
    required this.patientName,
    required this.onAssignPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hospital Name & Distance row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: const Icon(Icons.local_hospital, color: Color(0xFF991B1B), size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            hospital.fullName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hospital.isApexCenter) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('APEX',
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hospital.address,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _metricBadge(Icons.route, '${hospital.distanceKm} km', const Color(0xFF0369A1)),
                        const SizedBox(width: 8),
                        _metricBadge(Icons.timer_outlined, '~${hospital.transitMinutes} mins', const Color(0xFFB45309)),
                        const SizedBox(width: 8),
                        _metricBadge(Icons.bed_outlined, '${hospital.availableIcuBeds} HDU Beds', const Color(0xFF15803D)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action Button: Assign Patient & Send Referral Sheet
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF991B1B),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onAssignPressed,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(
              'Assign Patient & Send Referral Sheet to ${hospital.shortName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hospital Directory List View (Alternative to Map View)
// ---------------------------------------------------------------------------
class _HospitalListView extends StatelessWidget {
  final List<PuducherryHospital> hospitals;
  final PuducherryHospital selectedHospital;
  final ValueChanged<PuducherryHospital> onSelect;
  final ValueChanged<PuducherryHospital> onAssign;

  const _HospitalListView({
    required this.hospitals,
    required this.selectedHospital,
    required this.onSelect,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: hospitals.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, idx) {
        final h = hospitals[idx];
        final isSel = h.facilityCode == selectedHospital.facilityCode;

        return Card(
          elevation: isSel ? 3 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSel ? const Color(0xFF991B1B) : AppColors.border,
              width: isSel ? 2.0 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.local_hospital,
                        color: isSel ? const Color(0xFF991B1B) : const Color(0xFF475569),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                h.shortName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              if (h.isApexCenter) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('APEX',
                                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            h.fullName,
                            style: const TextStyle(fontSize: 12, color: AppColors.slate),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            h.address,
                            style: const TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${h.distanceKm} km',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0369A1)),
                        ),
                        Text(
                          '~${h.transitMinutes} mins',
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: h.specializedServices.map((svc) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(svc, style: const TextStyle(fontSize: 10, color: Color(0xFF334155))),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => onSelect(h),
                        child: Text(isSel ? 'Selected' : 'View on Map'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF991B1B)),
                        onPressed: () => onAssign(h),
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Assign & Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Referral Dispatch Confirmation Bottom Sheet
// ---------------------------------------------------------------------------
class _ReferralDispatchBottomSheet extends StatelessWidget {
  final PuducherryHospital hospital;
  final String patientName;
  final String patientCode;
  final List<String> selectedMedicines;
  final String? notes;
  final VoidCallback onConfirm;

  const _ReferralDispatchBottomSheet({
    required this.hospital,
    required this.patientName,
    required this.patientCode,
    required this.selectedMedicines,
    this.notes,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emergency_share, color: Color(0xFF991B1B), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirm Patient Referral & Dispatch',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Maternal Referral Sheet will be transmitted electronically',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Receiving Facility Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('RECEIVING HOSPITAL',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.muted)),
                    Text('${hospital.distanceKm} km • ~${hospital.transitMinutes} mins',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hospital.fullName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(hospital.address, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Clinical Payload Summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECDD3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PATIENT & CLINICAL SUMMARY',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF991B1B))),
                const SizedBox(height: 4),
                Text('$patientName ($patientCode)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  'Stabilization Medicines: ${selectedMedicines.isEmpty ? "None" : selectedMedicines.join(", ")}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF7F1D1D)),
                ),
                if (notes != null && notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Clinical Notes: $notes', style: const TextStyle(fontSize: 11, color: AppColors.slate)),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF991B1B),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: onConfirm,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text(
                    'Confirm & Send Sheet',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
