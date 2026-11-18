import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'bp_trend_graph.dart';
import 'bp_overview_card.dart';
import 'trend_insights_view.dart';
import 'maternal_risk_profile_view.dart';
import 'clinical_assessment_sheet.dart';

class BPTrendsTab extends StatefulWidget {
  final String patientId;
  final String patientName;
  final VoidCallback? onRecordBPTapped;

  const BPTrendsTab({
    super.key,
    required this.patientId,
    required this.patientName,
    this.onRecordBPTapped,
  });

  @override
  State<BPTrendsTab> createState() => _BPTrendsTabState();
}

class _BPTrendsTabState extends State<BPTrendsTab> {
  bool loading = true;
  String? error;
  String selectedPeriod = 'all';

  List<BPTrendPoint> measurements = [];
  Map<String, dynamic> analytics = {};
  Map<String, dynamic> screening = {};
  Map<String, dynamic> riskProfile = {};
  List<dynamic> pastAssessments = [];

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<void> loadAll() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final futures = await Future.wait([
        ApiClient.instance.get('/api/v1/patients/${widget.patientId}/bp-trends?period=$selectedPeriod'),
        ApiClient.instance.get('/api/v1/patients/${widget.patientId}/bp-analytics?period=$selectedPeriod'),
        ApiClient.instance.get('/api/v1/patients/${widget.patientId}/clinical-screening'),
        ApiClient.instance.get('/api/v1/patients/${widget.patientId}/risk-profile'),
        ApiClient.instance.get('/api/v1/patients/${widget.patientId}/clinical-assessments'),
      ]);

      if (mounted) {
        final trendsRes = futures[0] as Map<String, dynamic>;
        final analyticsRes = futures[1] as Map<String, dynamic>;
        final screeningRes = futures[2] as Map<String, dynamic>;
        final riskRes = futures[3] as Map<String, dynamic>;
        final assessRes = futures[4] as Map<String, dynamic>;

        final rawList = List<Map<String, dynamic>>.from(trendsRes['measurements'] ?? []);
        final parsedPoints = rawList.map((m) => BPTrendPoint.fromJson(m)).toList();

        setState(() {
          measurements = parsedPoints;
          analytics = analyticsRes;
          screening = screeningRes;
          riskProfile = riskRes;
          pastAssessments = List.from(assessRes['items'] ?? []);
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> _changePeriod(String p) async {
    if (selectedPeriod == p) return;
    setState(() => selectedPeriod = p);
    await loadAll();
  }

  void _openClinicalAssessment() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClinicalAssessmentSheet(
          patientId: widget.patientId,
          patientName: widget.patientName,
          analytics: analytics,
          screening: screening,
          riskProfile: riskProfile,
          onAssessmentSaved: loadAll,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading && measurements.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: AppColors.crimson),
        ),
      );
    }

    if (error != null && measurements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.critical),
              const SizedBox(height: 10),
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.ink)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: loadAll,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final latestPt = measurements.isNotEmpty ? measurements.last : null;

    return RefreshIndicator(
      onRefresh: loadAll,
      color: AppColors.crimson,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          // 1. BP Overview Card
          BPOverviewCard(
            analytics: analytics,
            screening: screening,
            latestPoint: latestPt,
          ),
          const SizedBox(height: 16),

          // 2. Interactive BP Graph
          BPTrendGraph(
            measurements: measurements,
            selectedPeriod: selectedPeriod,
            onPeriodChanged: _changePeriod,
          ),
          const SizedBox(height: 16),

          // 3. Trend Insights View
          TrendInsightsView(analytics: analytics),
          const SizedBox(height: 16),

          // 4. Maternal Risk Profile View
          MaternalRiskProfileView(riskProfile: riskProfile),
          const SizedBox(height: 16),

          // 5. Medical Officer Actions & Previous Assessments
          _buildAssessmentActionBar(),

          if (pastAssessments.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildPastAssessmentsSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildAssessmentActionBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paleRose,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_services_outlined, color: Color(0xFF7F1D3A), size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Medical Officer Assessment',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF7F1D3A)),
                ),
                Text(
                  'Record impression, referral decision & follow-up',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7F1D3A)),
            onPressed: _openClinicalAssessment,
            icon: const Icon(Icons.edit_note, size: 16),
            label: const Text('Assess', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildPastAssessmentsSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_outlined, size: 16, color: AppColors.slate),
              const SizedBox(width: 6),
              const Text(
                'Clinical Assessment History',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.slate),
              ),
              const Spacer(),
              Text(
                '${pastAssessments.length} recorded',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...pastAssessments.map((item) {
            final inputs = item['screening_inputs'] is Map ? item['screening_inputs'] as Map : {};
            final decision = inputs['referral_decision']?.toString() ?? item['result_category'] ?? '';
            final impression = inputs['clinical_impression']?.toString() ?? 'Assessment completed';
            final assessor = item['assessor_name']?.toString() ?? 'Medical Officer';

            String dateStr = '—';
            if (item['assessed_at'] != null) {
              try {
                final dt = DateTime.parse(item['assessed_at']).toLocal();
                dateStr = '${dt.day}/${dt.month}/${dt.year}';
              } catch (_) {}
            }

            Color decisionColor = AppColors.success;
            if (decision.contains('urgent') || decision.contains('emergency')) {
              decisionColor = const Color(0xFFDC2626);
            } else if (decision.contains('routine')) {
              decisionColor = const Color(0xFFD97706);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$assessor  •  $dateStr',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: decisionColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          decision.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: decisionColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    impression,
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

