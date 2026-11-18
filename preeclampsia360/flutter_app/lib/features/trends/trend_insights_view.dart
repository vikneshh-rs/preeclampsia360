import 'package:flutter/material.dart';
import '../../core/theme.dart';

class TrendInsightsView extends StatefulWidget {
  final Map<String, dynamic> analytics;

  const TrendInsightsView({super.key, required this.analytics});

  @override
  State<TrendInsightsView> createState() => _TrendInsightsViewState();
}

class _TrendInsightsViewState extends State<TrendInsightsView> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final insights = List<Map<String, dynamic>>.from(widget.analytics['insights'] ?? []);
    final totalVerified = widget.analytics['verified_count'] ?? 0;
    final totalUnverified = widget.analytics['unverified_count'] ?? 0;
    final pctCrossing = widget.analytics['threshold_crossing_percentage'] ?? 0.0;
    final freqDays = widget.analytics['measurement_frequency_days'];
    final irregularHistory = widget.analytics['irregular_or_missing_history'] == true;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.insights, size: 16, color: Color(0xFF7F1D3A)),
                  SizedBox(width: 6),
                  Text(
                    'Clinical Trend Insights',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => setState(() => expanded = !expanded),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        expanded ? 'Hide details' : 'View detailed analysis',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7F1D3A),
                        ),
                      ),
                      Icon(
                        expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16,
                        color: const Color(0xFF7F1D3A),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Primary 3 Insights
          if (insights.isEmpty)
            const Text(
              'No trend observations available for this observation window.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            )
          else
            ...insights.map((item) {
              final type = item['type']?.toString() ?? 'neutral';
              final statement = item['statement']?.toString() ?? '';
              final val = item['value']?.toString() ?? '';

              IconData iconData = Icons.info_outline;
              Color iconColor = AppColors.muted;
              if (type == 'rising' || type == 'severe') {
                iconData = Icons.warning_amber_rounded;
                iconColor = const Color(0xFFDC2626);
              } else if (type == 'elevated') {
                iconData = Icons.report_problem_outlined;
                iconColor = const Color(0xFFD97706);
              } else if (type == 'normal') {
                iconData = Icons.check_circle_outline;
                iconColor = const Color(0xFF16A34A);
              } else if (type == 'gap') {
                iconData = Icons.event_busy;
                iconColor = const Color(0xFFB45309);
              } else if (type == 'falling') {
                iconData = Icons.trending_down;
                iconColor = const Color(0xFF2563EB);
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(iconData, size: 16, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statement,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (val.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.paleRose,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          val,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.crimson),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),

          // Expandable Detailed Metrics Panel
          if (expanded) ...[
            const Divider(height: 20, color: AppColors.border),
            const Text(
              'Detailed Statistics & Longitudinal Consistency',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.slate),
            ),
            const SizedBox(height: 8),
            _statRow('Verified Measurements', '$totalVerified verified'),
            if (totalUnverified > 0)
              _statRow('Unverified OCR Displays', '$totalUnverified excluded from trend', alert: true),
            _statRow('Threshold Crossing Rate', '$pctCrossing% of verified readings'),
            _statRow(
              'Measurement Cadence',
              freqDays != null ? 'Avg. every $freqDays days' : 'Single / sporadic baseline',
            ),
            _statRow(
              'History Continuity',
              irregularHistory ? 'Irregular / gaps > 7 days noted' : 'Regular interval monitoring',
              alert: irregularHistory,
            ),
            const SizedBox(height: 6),
            const Text(
              '* All metrics calculated strictly on persisted healthcare worker verified readings.',
              style: TextStyle(fontSize: 10, color: AppColors.muted, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, {bool alert = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: alert ? const Color(0xFFB45309) : AppColors.ink,
              ),
            ),
          ],
        ),
      );
}

