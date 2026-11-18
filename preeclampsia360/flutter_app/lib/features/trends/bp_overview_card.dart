import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'bp_trend_graph.dart';

class BPOverviewCard extends StatelessWidget {
  final Map<String, dynamic> analytics;
  final Map<String, dynamic> screening;
  final BPTrendPoint? latestPoint;

  const BPOverviewCard({
    super.key,
    required this.analytics,
    required this.screening,
    this.latestPoint,
  });

  @override
  Widget build(BuildContext context) {
    final latestReading = analytics['latest_reading'] as Map<String, dynamic>?;
    final prevReading = analytics['previous_reading'] as Map<String, dynamic>?;
    final deltaSys = analytics['delta_systolic'] as int?;
    final deltaDia = analytics['delta_diastolic'] as int?;

    final screeningStatus = screening['screening_status']?.toString() ?? 'no_elevated';
    final statusLabel = screening['status_label']?.toString() ?? 'No elevated reading recorded';
    final repeatNeeded = screening['repeat_confirmation_needed'] == true;
    final repeatRecorded = screening['repeat_confirmation_recorded'] == true;

    Color statusColor;
    Color statusBg;
    if (screeningStatus == 'severe_screening') {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
    } else if (screeningStatus == 'elevated_screening') {
      statusColor = const Color(0xFFD97706);
      statusBg = const Color(0xFFFEF3C7);
    } else if (screeningStatus == 'insufficient_data') {
      statusColor = const Color(0xFF475569);
      statusBg = const Color(0xFFF1F5F9);
    } else {
      statusColor = const Color(0xFF16A34A);
      statusBg = const Color(0xFFDCFCE7);
    }

    final sbp = latestReading?['systolic_mmhg'] ?? '—';
    final dbp = latestReading?['diastolic_mmhg'] ?? '—';

    String dateStr = '—';
    if (latestReading?['measured_at'] != null) {
      try {
        final dt = DateTime.parse(latestReading!['measured_at']).toLocal();
        dateStr = '${dt.day} ${_monthName(dt.month)} ${dt.year}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    final gaStr = latestPoint?.gestationalAgeDisplay ?? latestReading?['gestational_age_display'] ?? '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.crimson.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Current Blood Pressure',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Primary BP Reading (Prominent SBP / DBP)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$sbp / $dbp',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: screeningStatus == 'severe_screening'
                      ? const Color(0xFFDC2626)
                      : (screeningStatus == 'elevated_screening' ? const Color(0xFFD97706) : const Color(0xFF7F1D3A)),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'mmHg',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),

              // Delta vs previous reading
              if (prevReading != null && deltaSys != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Icon(
                          deltaSys > 0 ? Icons.arrow_upward : (deltaSys < 0 ? Icons.arrow_downward : Icons.remove),
                          size: 14,
                          color: deltaSys > 0 ? AppColors.critical : (deltaSys < 0 ? AppColors.success : AppColors.muted),
                        ),
                        Text(
                          '${deltaSys > 0 ? "+$deltaSys" : "$deltaSys"} / ${deltaDia != null && deltaDia > 0 ? "+$deltaDia" : "$deltaDia"}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: deltaSys > 0 ? AppColors.critical : (deltaSys < 0 ? AppColors.success : AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Prev: ${prevReading["systolic_mmhg"]}/${prevReading["diastolic_mmhg"]}',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Timestamp & Gestational Age Row
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: AppColors.muted),
              const SizedBox(width: 4),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 12, color: AppColors.ink),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.child_care, size: 14, color: AppColors.muted),
              const SizedBox(width: 4),
              Text(
                'GA: $gaStr',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
            ],
          ),

          // Repeat Confirmation Banner
          if (repeatNeeded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Repeat BP measurement required within 4 hours to verify sustained hypertension.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (repeatRecorded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 15, color: Color(0xFF16A34A)),
                  SizedBox(width: 6),
                  Text(
                    'Repeat verification measurement recorded in sequence.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF16A34A)),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 24, color: AppColors.border),

          // Compact Supporting Metrics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricPill('Verified Total', '${analytics["verified_count"] ?? 0}', Colors.black87),
              _metricPill('Elevated (>=140/90)', '${analytics["elevated_count"] ?? 0}', const Color(0xFFD97706)),
              _metricPill('Severe (>=160/110)', '${analytics["severe_count"] ?? 0}', const Color(0xFFDC2626)),
              _metricPill('Trend', (analytics["trend_direction"] ?? 'stable').toString().toUpperCase(), const Color(0xFF7F1D3A)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricPill(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
      ],
    );
  }

  String _monthName(int m) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return (m >= 1 && m <= 12) ? months[m] : '';
  }
}

