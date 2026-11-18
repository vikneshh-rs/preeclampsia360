import 'package:flutter/material.dart';
import '../../core/theme.dart';

class MaternalRiskProfileView extends StatefulWidget {
  final Map<String, dynamic> riskProfile;
  final VoidCallback? onUpdateRequested;

  const MaternalRiskProfileView({
    super.key,
    required this.riskProfile,
    this.onUpdateRequested,
  });

  @override
  State<MaternalRiskProfileView> createState() => _MaternalRiskProfileViewState();
}

class _MaternalRiskProfileViewState extends State<MaternalRiskProfileView> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final factors = List<Map<String, dynamic>>.from(widget.riskProfile['factors'] ?? []);
    final presentCount = widget.riskProfile['documented_risk_factors_count'] ?? 0;
    final unknownCount = widget.riskProfile['unknown_count'] ?? 0;
    final headline = widget.riskProfile['summary_headline'] ?? '$presentCount documented risk factors';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Collapsible Header
          InkWell(
            onTap: () => setState(() => expanded = !expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: presentCount > 0 ? const Color(0xFFFEE2E2) : AppColors.paleRose,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: presentCount > 0 ? const Color(0xFFDC2626) : const Color(0xFF7F1D3A),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Maternal Risk Profile',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.slate,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          headline,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: presentCount > 0 ? FontWeight.w700 : FontWeight.w500,
                            color: presentCount > 0 ? const Color(0xFFDC2626) : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unknownCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$unknownCount unrecorded',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                    ),
                  Icon(
                    expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Factors List
          if (expanded) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clinical Risk Factors (NICE / ACOG / FIGO Guideline Screening)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted),
                  ),
                  const SizedBox(height: 10),
                  ...factors.map((f) => _buildFactorTile(f)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warmWhite,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 14, color: AppColors.muted),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Missing or unavailable clinical data is explicitly labeled as "Unknown" and is never interpreted as absence of maternal risk.',
                            style: TextStyle(fontSize: 10, height: 1.4, color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFactorTile(Map<String, dynamic> f) {
    final status = f['status']?.toString() ?? 'unknown';
    final name = f['name']?.toString() ?? '';
    final detail = f['detail']?.toString() ?? '';
    final source = f['source']?.toString() ?? '';

    Color badgeBg;
    Color badgeText;
    String badgeLabel;

    if (status == 'present') {
      badgeBg = const Color(0xFFFEE2E2);
      badgeText = const Color(0xFFDC2626);
      badgeLabel = 'PRESENT';
    } else if (status == 'absent') {
      badgeBg = const Color(0xFFF1F5F9);
      badgeText = const Color(0xFF475569);
      badgeLabel = 'ABSENT';
    } else {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFB45309);
      badgeLabel = 'UNKNOWN';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: status == 'present' ? const Color(0xFFFFF8F8) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: status == 'present' ? const Color(0xFFFECACA) : AppColors.border,
          width: status == 'present' ? 1.0 : 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: status == 'present' ? FontWeight.w700 : FontWeight.w600,
                    color: status == 'present' ? const Color(0xFF7F1D3A) : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                Text(
                  'Source: $source',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(
                color: badgeText,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

