import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class BPTrendPoint {
  final String id;
  final DateTime measuredAt;
  final int systolic;
  final int diastolic;
  final int? pulse;
  final double? gestationalAgeWeeks;
  final String gestationalAgeDisplay;
  final String verificationStatus;
  final bool workerConfirmed;
  final String captureMethod;
  final String facilityName;
  final String recorderName;
  final String? urineProtein;
  final List<String> imminentSymptoms;
  final bool isElevated;
  final bool isSevere;

  BPTrendPoint({
    required this.id,
    required this.measuredAt,
    required this.systolic,
    required this.diastolic,
    this.pulse,
    this.gestationalAgeWeeks,
    required this.gestationalAgeDisplay,
    required this.verificationStatus,
    required this.workerConfirmed,
    required this.captureMethod,
    required this.facilityName,
    required this.recorderName,
    this.urineProtein,
    this.imminentSymptoms = const [],
    required this.isElevated,
    required this.isSevere,
  });

  factory BPTrendPoint.fromJson(Map<String, dynamic> json) {
    DateTime dt;
    try {
      dt = DateTime.parse(json['measured_at'] as String);
    } catch (_) {
      dt = DateTime.now();
    }

    return BPTrendPoint(
      id: json['id']?.toString() ?? '',
      measuredAt: dt,
      systolic: (json['systolic_mmhg'] as num?)?.toInt() ?? 120,
      diastolic: (json['diastolic_mmhg'] as num?)?.toInt() ?? 80,
      pulse: (json['pulse_bpm'] as num?)?.toInt(),
      gestationalAgeWeeks: (json['gestational_age_weeks'] as num?)?.toDouble(),
      gestationalAgeDisplay: json['gestational_age_display']?.toString() ?? '—',
      verificationStatus: json['verification_status']?.toString() ?? 'pending',
      workerConfirmed: json['worker_confirmed'] == true,
      captureMethod: json['capture_method']?.toString() ?? 'manual',
      facilityName: json['facility_name']?.toString() ?? 'Health Facility',
      recorderName: json['recorder_name']?.toString() ?? 'Healthcare Worker',
      urineProtein: json['urine_protein']?.toString(),
      imminentSymptoms: List<String>.from(json['imminent_symptoms'] ?? []),
      isElevated: json['is_elevated'] == true,
      isSevere: json['is_severe'] == true,
    );
  }
}

class BPTrendGraph extends StatefulWidget {
  final List<BPTrendPoint> measurements;
  final String selectedPeriod;
  final ValueChanged<String> onPeriodChanged;

  const BPTrendGraph({
    super.key,
    required this.measurements,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  @override
  State<BPTrendGraph> createState() => _BPTrendGraphState();
}

class _BPTrendGraphState extends State<BPTrendGraph> {
  int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    final verified = widget.measurements
        .where((m) => m.workerConfirmed || m.verificationStatus == 'worker_verified')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter segmented control
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Longitudinal Trend',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.slate,
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.paleRose,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: ['7D', '30D', '90D', 'All'].map((p) {
                  final key = p.toLowerCase();
                  final isSel = widget.selectedPeriod == key;
                  return InkWell(
                    onTap: () {
                      setState(() => selectedIndex = null);
                      widget.onPeriodChanged(key);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF7F1D3A) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        p,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSel ? Colors.white : AppColors.ink,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Chart Card
        Container(
          height: 240,
          padding: const EdgeInsets.fromLTRB(10, 14, 14, 10),
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
          child: verified.isEmpty
              ? _buildEmptyState()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final chartSize = Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        _handleTap(details.localPosition, chartSize, verified);
                      },
                      child: CustomPaint(
                        size: chartSize,
                        painter: _BPTrendPainter(
                          points: verified,
                          selectedIndex: selectedIndex,
                        ),
                      ),
                    );
                  },
                ),
        ),

        const SizedBox(height: 8),

        // Compact Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem(const Color(0xFF7F1D3A), 'Systolic (SBP)'),
            const SizedBox(width: 16),
            _legendItem(const Color(0xFFC6A46A), 'Diastolic (DBP)'),
            const SizedBox(width: 16),
            _legendDashed(const Color(0xFFD97706), '140/90 Threshold'),
            const SizedBox(width: 16),
            _legendDashed(const Color(0xFFDC2626), '160/110 Severe'),
          ],
        ),

        // Selected Tooltip Detail Card
        if (selectedIndex != null && selectedIndex! < verified.length)
          _buildTooltipCard(verified[selectedIndex!]),
      ],
    );
  }

  Widget _legendItem(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _legendDashed(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 2,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      );

  Widget _buildEmptyState() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, color: AppColors.muted, size: 36),
            SizedBox(height: 8),
            Text(
              'No verified BP readings in this timeframe',
              style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Switch to "All" or record a verified BP measurement.',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      );

  void _handleTap(Offset pos, Size size, List<BPTrendPoint> points) {
    if (points.isEmpty) return;
    const leftMargin = 38.0;
    const rightMargin = 16.0;

    final chartWidth = size.width - leftMargin - rightMargin;
    if (pos.dx < leftMargin || pos.dx > size.width - rightMargin) return;

    if (points.length == 1) {
      setState(() => selectedIndex = 0);
      return;
    }

    // Find nearest point along x
    final stepX = chartWidth / (points.length - 1);
    final relativeX = pos.dx - leftMargin;
    final nearestIndex = (relativeX / stepX).round().clamp(0, points.length - 1);

    setState(() => selectedIndex = nearestIndex);
  }

  Widget _buildTooltipCard(BPTrendPoint pt) {
    final isCritical = pt.isSevere;
    final isWarning = pt.isElevated;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCritical ? AppColors.blush : (isWarning ? AppColors.paleRose : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCritical ? AppColors.critical : (isWarning ? AppColors.warning : AppColors.border),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${pt.systolic} / ${pt.diastolic} mmHg',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: isCritical ? AppColors.critical : (isWarning ? AppColors.warning : AppColors.ink),
                ),
              ),
              if (pt.pulse != null) ...[
                const SizedBox(width: 8),
                Text('• Pulse ${pt.pulse} bpm', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCritical ? AppColors.critical : (isWarning ? AppColors.warning : AppColors.success),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isCritical ? 'SEVERE' : (isWarning ? 'ELEVATED' : 'NORMAL'),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.muted),
              const SizedBox(width: 4),
              Text(
                '${pt.measuredAt.toLocal().toString().substring(0, 16)}  •  GA: ${pt.gestationalAgeDisplay}',
                style: const TextStyle(fontSize: 12, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 13, color: AppColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${pt.facilityName} (${pt.recorderName})  •  Verified',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (pt.urineProtein != null && pt.urineProtein != 'nil' && pt.urineProtein != 'not_tested') ...[
            const SizedBox(height: 4),
            Text(
              '• Proteinuria: ${pt.urineProtein!.toUpperCase()}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.critical),
            ),
          ],
          if (pt.imminentSymptoms.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '• Danger Signs: ${pt.imminentSymptoms.join(", ")}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.critical),
            ),
          ],
        ],
      ),
    );
  }
}

class _BPTrendPainter extends CustomPainter {
  final List<BPTrendPoint> points;
  final int? selectedIndex;

  _BPTrendPainter({required this.points, this.selectedIndex});

  static const double leftMargin = 38.0;
  static const double rightMargin = 16.0;
  static const double topMargin = 20.0;
  static const double bottomMargin = 28.0;

  static const double minY = 50.0;
  static const double maxY = 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chartWidth = size.width - leftMargin - rightMargin;
    final chartHeight = size.height - topMargin - bottomMargin;

    double yToPx(double yVal) {
      final clamped = yVal.clamp(minY, maxY);
      final ratio = (clamped - minY) / (maxY - minY);
      return size.height - bottomMargin - (ratio * chartHeight);
    }

    double xToPx(int index) {
      if (points.length <= 1) return leftMargin + (chartWidth / 2);
      return leftMargin + (index * (chartWidth / (points.length - 1)));
    }

    // 1. Draw horizontal gridlines & Y labels
    final gridPaint = Paint()
      ..color = const Color(0xFFF1E9EC)
      ..strokeWidth = 1.0;

    final textStyle = const TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    final yLabels = [60, 90, 110, 140, 160, 180];
    for (final yVal in yLabels) {
      final py = yToPx(yVal.toDouble());
      canvas.drawLine(Offset(leftMargin, py), Offset(size.width - rightMargin, py), gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: '$yVal', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftMargin - tp.width - 5, py - (tp.height / 2)));
    }

    // 2. Clinical Threshold Lines
    _drawDashedThreshold(canvas, leftMargin, size.width - rightMargin, yToPx(160), const Color(0xFFDC2626), '160 SBP');
    _drawDashedThreshold(canvas, leftMargin, size.width - rightMargin, yToPx(140), const Color(0xFFD97706), '140 SBP');
    _drawDashedThreshold(canvas, leftMargin, size.width - rightMargin, yToPx(110), const Color(0xFFDC2626), '110 DBP');
    _drawDashedThreshold(canvas, leftMargin, size.width - rightMargin, yToPx(90), const Color(0xFFD97706), '90 DBP');

    if (points.isEmpty) return;

    // 3. Draw SBP and DBP connecting lines (if multiple points)
    final sbpPath = Path();
    final dbpPath = Path();

    for (int i = 0; i < points.length; i++) {
      final px = xToPx(i);
      final pyS = yToPx(points[i].systolic.toDouble());
      final pyD = yToPx(points[i].diastolic.toDouble());

      if (i == 0) {
        sbpPath.moveTo(px, pyS);
        dbpPath.moveTo(px, pyD);
      } else {
        sbpPath.lineTo(px, pyS);
        dbpPath.lineTo(px, pyD);
      }
    }

    // Paint SBP Line (Deep Burgundy)
    final sbpLinePaint = Paint()
      ..color = const Color(0xFF7F1D3A)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(sbpPath, sbpLinePaint);

    // Paint DBP Line (Warm Gold / Champagne)
    final dbpLinePaint = Paint()
      ..color = const Color(0xFFC6A46A)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(dbpPath, dbpLinePaint);

    // 4. Draw Point Markers
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final px = xToPx(i);
      final pyS = yToPx(pt.systolic.toDouble());
      final pyD = yToPx(pt.diastolic.toDouble());
      final isSel = selectedIndex == i;

      // SBP Dot
      final sbpDotColor = pt.systolic >= 160
          ? const Color(0xFFDC2626)
          : (pt.systolic >= 140 ? const Color(0xFFD97706) : const Color(0xFF7F1D3A));

      canvas.drawCircle(
        Offset(px, pyS),
        isSel ? 6.5 : 4.0,
        Paint()..color = sbpDotColor,
      );
      canvas.drawCircle(
        Offset(px, pyS),
        isSel ? 3.0 : 2.0,
        Paint()..color = Colors.white,
      );

      // DBP Dot
      final dbpDotColor = pt.diastolic >= 110
          ? const Color(0xFFDC2626)
          : (pt.diastolic >= 90 ? const Color(0xFFD97706) : const Color(0xFFC6A46A));

      canvas.drawCircle(
        Offset(px, pyD),
        isSel ? 6.5 : 4.0,
        Paint()..color = dbpDotColor,
      );
      canvas.drawCircle(
        Offset(px, pyD),
        isSel ? 3.0 : 2.0,
        Paint()..color = Colors.white,
      );

      // Selected vertical guide bar
      if (isSel) {
        final selBarPaint = Paint()
          ..color = const Color(0xFF7F1D3A).withValues(alpha: 0.15)
          ..strokeWidth = 1.5;
        canvas.drawLine(
          Offset(px, topMargin),
          Offset(px, size.height - bottomMargin),
          selBarPaint,
        );
      }

      // X-axis label (date + GA)
      if (points.length <= 6 || i == 0 || i == points.length - 1 || i % ((points.length / 4).ceil()) == 0) {
        final dateStr = '${pt.measuredAt.day}/${pt.measuredAt.month}';
        final gaStr = pt.gestationalAgeWeeks != null ? '${pt.gestationalAgeWeeks!.toInt()}w' : '';
        final labelText = gaStr.isNotEmpty ? '$dateStr\n$gaStr' : dateStr;

        final tpX = TextPainter(
          text: TextSpan(
            text: labelText,
            style: TextStyle(
              fontSize: 9,
              color: isSel ? const Color(0xFF7F1D3A) : const Color(0xFF64748B),
              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout();

        tpX.paint(canvas, Offset(px - (tpX.width / 2), size.height - bottomMargin + 4));
      }
    }
  }

  void _drawDashedThreshold(Canvas canvas, double startX, double endX, double y, Color color, String label) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double curX = startX;
    while (curX < endX) {
      canvas.drawLine(Offset(curX, y), Offset(math.min(curX + dashWidth, endX), y), paint);
      curX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _BPTrendPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.selectedIndex != selectedIndex;
  }
}

